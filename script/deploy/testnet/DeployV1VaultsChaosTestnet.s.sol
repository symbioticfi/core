// SPDX-License-Identifier: MIT
// TESTNET_V1_CHAOS_SEED=123 forge script \
//   script/deploy/testnet/DeployV1VaultsChaosTestnet.s.sol:DeployV1VaultsChaosTestnetScript \
//   --rpc-url hoodi --account "$ACCOUNT" --sender "$SENDER" --broadcast --slow -vvvv
// Wait at least DELAY_SECONDS (17 seconds) after run() completes before running the continuation:
// TESTNET_V1_CHAOS_SEED=123 \
// TESTNET_V1_CHAOS_VAULTS=0xVault0,0xVault1,0xVault2,0xVault3,0xVault4,0xVault5,0xVault6,0xVault7,0xVault8,0xVault9,0xVault10,0xVault11 \
// forge script \
//   script/deploy/testnet/DeployV1VaultsChaosTestnet.s.sol:DeployV1VaultsChaosTestnetScript \
//   --sig "runDelayed()" --rpc-url hoodi --account "$ACCOUNT" --sender "$SENDER" --broadcast --slow -vvvv
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {INetworkRegistry} from "../../../src/interfaces/INetworkRegistry.sol";
import {IOperatorRegistry} from "../../../src/interfaces/IOperatorRegistry.sol";
import {IVaultConfigurator} from "../../../src/interfaces/IVaultConfigurator.sol";
import {IMigratableEntity} from "../../../src/interfaces/common/IMigratableEntity.sol";
import {IRegistry} from "../../../src/interfaces/common/IRegistry.sol";
import {IBaseDelegator} from "../../../src/interfaces/delegator/IBaseDelegator.sol";
import {IFullRestakeDelegator} from "../../../src/interfaces/delegator/IFullRestakeDelegator.sol";
import {INetworkRestakeDelegator} from "../../../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {
    IOperatorNetworkSpecificDelegator
} from "../../../src/interfaces/delegator/IOperatorNetworkSpecificDelegator.sol";
import {IOperatorSpecificDelegator} from "../../../src/interfaces/delegator/IOperatorSpecificDelegator.sol";
import {INetworkMiddlewareService} from "../../../src/interfaces/service/INetworkMiddlewareService.sol";
import {IOptInService} from "../../../src/interfaces/service/IOptInService.sol";
import {IBaseSlasher} from "../../../src/interfaces/slasher/IBaseSlasher.sol";
import {ISlasher} from "../../../src/interfaces/slasher/ISlasher.sol";
import {IVetoSlasher} from "../../../src/interfaces/slasher/IVetoSlasher.sol";
import {IVault, VAULT_VERSION} from "../../../src/interfaces/vault/IVault.sol";
import {IVaultTokenized, VAULT_TOKENIZED_VERSION} from "../../../src/interfaces/vault/IVaultTokenized.sol";
import {Subnetwork} from "../../../src/contracts/libraries/Subnetwork.sol";

contract V1ChaosExecutor {
    uint256 internal constant MAX_CLAIM_EPOCHS = 32;

    address public immutable controller;
    uint256 public totalAttempts;
    uint256 public totalSuccesses;
    uint256 public totalFailures;
    mapping(address vault => uint256[] epochs) internal _claimEpochs;

    error V1ChaosExecutor__NotController();

    event V1ChaosAction(
        uint256 indexed seed,
        uint256 indexed vaultIndex,
        uint256 indexed round,
        uint8 action,
        address target,
        bytes4 selector,
        bool success,
        bytes32 resultHash
    );

    constructor(address controller_) {
        controller = controller_;
    }

    modifier onlyController() {
        if (msg.sender != controller) {
            revert V1ChaosExecutor__NotController();
        }
        _;
    }

    function executeRequired(address target, bytes calldata data)
        external
        onlyController
        returns (bytes memory result)
    {
        bool success;
        (success, result) = target.call(data);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(result, 0x20), mload(result))
            }
        }
        _rememberClaimEpoch(target, data);
    }

    function executeAttempt(
        uint256 seed,
        uint256 vaultIndex,
        uint256 round,
        uint8 action,
        address target,
        bytes calldata data,
        bool readOnly
    ) external onlyController returns (bool success, bytes memory result) {
        return _executeAttempt(seed, vaultIndex, round, action, target, data, readOnly);
    }

    function executeInstantSlash(
        uint256 seed,
        uint256 vaultIndex,
        uint256 round,
        address slasher,
        bytes32 subnetwork,
        address operator,
        uint256 amount
    ) external onlyController returns (bool success, bytes memory result) {
        bytes memory data = abi.encodeCall(
            ISlasher.slash, (subnetwork, operator, amount, uint48(block.timestamp - 1), bytes(""))
        );
        return _executeAttempt(
            seed, vaultIndex, round, uint8(DeployV1VaultsChaosTestnetScript.Action.Slash), slasher, data, false
        );
    }

    function executeVetoSlashSequence(
        uint256 seed,
        uint256 vaultIndex,
        uint256 round,
        address slasher,
        bytes32 subnetwork,
        address operator,
        uint256 amount,
        bool veto
    ) external onlyController {
        bytes memory requestData = abi.encodeCall(
            IVetoSlasher.requestSlash, (subnetwork, operator, amount, uint48(block.timestamp - 1), bytes(""))
        );
        (bool requestSuccess, bytes memory requestResult) = slasher.call(requestData);
        requestSuccess = requestSuccess && requestResult.length == 32;
        _recordAttempt(
            seed,
            vaultIndex,
            round,
            uint8(DeployV1VaultsChaosTestnetScript.Action.RequestSlash),
            slasher,
            requestData,
            requestSuccess,
            requestResult
        );
        if (!requestSuccess) {
            return;
        }

        uint256 slashIndex;
        assembly ("memory-safe") {
            slashIndex := mload(add(requestResult, 0x20))
        }
        bytes memory completionData = veto
            ? abi.encodeCall(IVetoSlasher.vetoSlash, (slashIndex, bytes("")))
            : abi.encodeCall(IVetoSlasher.executeSlash, (slashIndex, bytes("")));
        uint8 completionAction = uint8(
            veto
                ? DeployV1VaultsChaosTestnetScript.Action.VetoSlash
                : DeployV1VaultsChaosTestnetScript.Action.ExecuteSlash
        );
        _executeAttempt(seed, vaultIndex, round, completionAction, slasher, completionData, false);
    }

    function claimEpochs(address vault) external view returns (uint256[] memory) {
        return _claimEpochs[vault];
    }

    function ensureOptIn(address service, address where) external onlyController {
        if (!IOptInService(service).isOptedIn(address(this), where)) {
            IOptInService(service).optIn(where);
        }
    }

    function ensureHookCleared(address delegator) external onlyController {
        if (IBaseDelegator(delegator).hook() != address(0)) {
            IBaseDelegator(delegator).setHook(address(0));
        }
    }

    function _executeAttempt(
        uint256 seed,
        uint256 vaultIndex,
        uint256 round,
        uint8 action,
        address target,
        bytes memory data,
        bool readOnly
    ) internal returns (bool success, bytes memory result) {
        if (readOnly) {
            (success, result) = target.staticcall(data);
        } else {
            (success, result) = target.call(data);
        }
        if (success && !readOnly) {
            _rememberClaimEpoch(target, data);
        }
        _recordAttempt(seed, vaultIndex, round, action, target, data, success, result);
    }

    function _recordAttempt(
        uint256 seed,
        uint256 vaultIndex,
        uint256 round,
        uint8 action,
        address target,
        bytes memory data,
        bool success,
        bytes memory result
    ) internal {
        ++totalAttempts;
        if (success) {
            ++totalSuccesses;
        } else {
            ++totalFailures;
        }
        emit V1ChaosAction(seed, vaultIndex, round, action, target, _selector(data), success, keccak256(result));
    }

    function _rememberClaimEpoch(address target, bytes memory data) internal {
        bytes4 selector = _selector(data);
        if (selector != IVault.withdraw.selector && selector != IVault.redeem.selector) {
            return;
        }

        (bool success, bytes memory result) = target.staticcall{gas: 50_000}(abi.encodeWithSignature("currentEpoch()"));
        if (!success || result.length != 32) {
            return;
        }
        uint256 epoch;
        assembly ("memory-safe") {
            epoch := mload(add(result, 0x20))
        }
        if (epoch == type(uint256).max) {
            return;
        }
        ++epoch;

        uint256[] storage epochs = _claimEpochs[target];
        for (uint256 i; i < epochs.length; ++i) {
            if (epochs[i] == epoch) {
                return;
            }
        }
        if (epochs.length < MAX_CLAIM_EPOCHS) {
            epochs.push(epoch);
        }
    }

    function _selector(bytes memory data) internal pure returns (bytes4 selector) {
        if (data.length < 4) {
            return bytes4(0);
        }
        assembly ("memory-safe") {
            selector := mload(add(data, 0x20))
        }
    }
}

contract DeployV1VaultsChaosTestnetScript is Script {
    using SafeERC20 for IERC20;

    uint256 public constant VAULT_COUNT = 12;
    uint256 public constant DELAY_SECONDS = 17;
    uint256 public constant CLAIM_EPOCH_SCAN_LIMIT = 16;

    bytes32 internal constant DOMAIN_ASSET_OFFSET = keccak256("v1-chaos.asset-offset");
    bytes32 internal constant DOMAIN_EPOCH = keccak256("v1-chaos.epoch");
    bytes32 internal constant DOMAIN_VETO_DURATION = keccak256("v1-chaos.veto-duration");
    bytes32 internal constant DOMAIN_VETO_ROTATION = keccak256("v1-chaos.veto-rotation");
    bytes32 internal constant DOMAIN_SUBNETWORK = keccak256("v1-chaos.subnetwork");
    bytes32 internal constant DOMAIN_DEPOSIT_WHITELIST = keccak256("v1-chaos.deposit-whitelist");
    bytes32 internal constant DOMAIN_DEPOSIT_LIMIT_ENABLED = keccak256("v1-chaos.deposit-limit-enabled");
    bytes32 internal constant DOMAIN_BURNER_HOOK = keccak256("v1-chaos.burner-hook");
    bytes32 internal constant DOMAIN_BASELINE_DEPOSIT = keccak256("v1-chaos.baseline-deposit");
    bytes32 internal constant DOMAIN_BASELINE_WITHDRAWAL = keccak256("v1-chaos.baseline-withdrawal");
    bytes32 internal constant DOMAIN_DEPOSIT_LIMIT = keccak256("v1-chaos.deposit-limit");
    bytes32 internal constant DOMAIN_TOKENIZED_SUFFIX = keccak256("v1-chaos.tokenized-suffix");
    bytes32 internal constant DOMAIN_ACTION_VALUE = keccak256("v1-chaos.action-value");
    bytes32 internal constant DOMAIN_ACTION_SHUFFLE = keccak256("v1-chaos.action-shuffle");
    bytes32 internal constant DOMAIN_PASSIVE_RECEIVER = keccak256("v1-chaos.passive-receiver");
    bytes32 internal constant DOMAIN_DELAYED_CLAIM_ORDER = keccak256("v1-chaos.delayed-claim-order");
    bytes32 internal constant DOMAIN_DELAYED_ACTION_PLAN = keccak256("v1-chaos.delayed-action-plan");
    bytes32 internal constant FRESH_CAPTURE_TIMESTAMP_RULE =
        keccak256("v1-chaos.capture-timestamp.block-timestamp-minus-one-at-execution");

    uint256 internal constant DELAYED_ROUND = 1;
    uint256 internal constant DELAYED_SLASH_AMOUNT = 1;

    enum SlasherMode {
        None,
        Instant,
        Veto
    }

    enum DelayedSlashFlow {
        None,
        Slash,
        RequestVeto,
        RequestExecute
    }

    enum Action {
        SetDepositWhitelist,
        SetDepositorWhitelistStatus,
        SetIsDepositLimit,
        SetDepositLimit,
        OptOutVault,
        OptInVault,
        IncreaseVaultOptInNonce,
        OptOutNetwork,
        OptInNetwork,
        IncreaseNetworkOptInNonce,
        SetHook,
        SetMaxNetworkLimit,
        SetNetworkLimit,
        SetOperatorNetworkShares,
        SetOperatorNetworkLimit,
        Deposit,
        Withdraw,
        Redeem,
        ApproveShares,
        TransferShares,
        TransferFromShares,
        SetResolver,
        Claim,
        ClaimBatch,
        ReadVault,
        ReadDelegator,
        ReadVaultOptIn,
        ReadNetworkOptIn,
        ReadSlasher,
        Slash,
        RequestSlash,
        VetoSlash,
        ExecuteSlash
    }

    struct Core {
        address vaultConfigurator;
        address networkRegistry;
        address networkMiddlewareService;
        address operatorRegistry;
        address operatorVaultOptInService;
        address operatorNetworkOptInService;
    }

    struct Assets {
        address usdc;
        address aUsd;
        address mFone;
        address mGlobal;
    }

    struct RunParams {
        Core core;
        Assets assets;
        address controller;
        uint256 seed;
        bool broadcast;
    }

    struct DelayedRunParams {
        Core core;
        address controller;
        uint256 seed;
        bool broadcast;
        address[] vaults;
    }

    struct VaultPlan {
        uint256 index;
        uint8 assetIndex;
        address asset;
        uint64 vaultVersion;
        uint64 delegatorType;
        SlasherMode slasherMode;
        bool vetoWithResolver;
        uint96 subnetworkId;
        uint48 epochDuration;
        uint48 vetoDuration;
        bool initialDepositWhitelist;
        bool initialIsDepositLimit;
        bool isBurnerHook;
        uint256 baselineDepositUnits;
        uint256 baselineWithdrawalUnits;
        uint256 depositLimitUnits;
        uint256 tokenizedSuffix;
    }

    struct PlannedAction {
        Action action;
        uint8 occurrence;
        uint256 value;
        bool readOnly;
    }

    struct DelayedVaultActionPlan {
        uint256 vaultIndex;
        address vault;
        address slasher;
        bytes32 subnetwork;
        DelayedSlashFlow slashFlow;
        uint256 slashAmount;
        bool claimFirst;
        uint256 directEpoch;
        uint256[] batchEpochs;
    }

    struct VaultRecord {
        address vault;
        address delegator;
        address slasher;
        address asset;
        uint64 vaultVersion;
        uint64 delegatorType;
        SlasherMode slasherMode;
        bool vetoWithResolver;
        uint96 subnetworkId;
        uint256 claimEpoch;
    }

    struct ActionCounters {
        uint256 total;
        uint256 success;
        uint256 failure;
    }

    struct RunResult {
        address executor;
        VaultRecord[] vaults;
        bytes32 configurationDigest;
        bytes32 actionPlanDigest;
        ActionCounters counters;
    }

    error DeployV1VaultsChaosTestnetScript__InvalidController();
    error DeployV1VaultsChaosTestnetScript__ControllerCallerMismatch(address controller, address caller);
    error DeployV1VaultsChaosTestnetScript__MissingCode(address target);
    error DeployV1VaultsChaosTestnetScript__InvalidAssetDecimals(address asset);
    error DeployV1VaultsChaosTestnetScript__AssetDecimalsTooLarge(address asset, uint256 decimals);
    error DeployV1VaultsChaosTestnetScript__ScaledAmountOverflow(address asset, uint256 wholeTokens, uint256 decimals);
    error DeployV1VaultsChaosTestnetScript__InsufficientAssetBudget(address asset, uint256 required, uint256 available);
    error DeployV1VaultsChaosTestnetScript__UnsupportedImmediateAction(Action action);
    error DeployV1VaultsChaosTestnetScript__InvalidVaultCount(uint256 count);
    error DeployV1VaultsChaosTestnetScript__DuplicateVault(address vault);
    error DeployV1VaultsChaosTestnetScript__InvalidDelayedExecutor(address executor);
    error DeployV1VaultsChaosTestnetScript__InvalidDelayedVault(uint256 index);
    error DeployV1VaultsChaosTestnetScript__UnsupportedChain(uint256 chainId);
    error DeployV1VaultsChaosTestnetScript__InvalidCoreDependency(address target);

    function run() external virtual returns (RunResult memory result) {
        (Core memory core, Assets memory assets) = _latestDeployment();
        uint256 seed = vm.envOr("TESTNET_V1_CHAOS_SEED", uint256(0xC0A5));
        result =
            runBase(RunParams({core: core, assets: assets, controller: _scriptOwner(), seed: seed, broadcast: true}));
        _logSummary(seed, result);
    }

    function runDelayed() external virtual returns (RunResult memory result) {
        (Core memory core,) = _latestDeployment();
        address[] memory vaults = vm.envAddress("TESTNET_V1_CHAOS_VAULTS", ",");
        uint256 seed = vm.envOr("TESTNET_V1_CHAOS_SEED", uint256(0xC0A5));
        result = runDelayedBase(
            DelayedRunParams({core: core, controller: _scriptOwner(), seed: seed, broadcast: true, vaults: vaults})
        );
        _logSummary(seed, result);
    }

    function _latestDeployment() internal view returns (Core memory core, Assets memory assets) {
        bool supported = block.chainid == 560_048 || block.chainid == 11_155_111;
        if (block.chainid == 560_048) {
            (core, assets) = _hoodiDeployment();
        } else if (block.chainid == 11_155_111) {
            (core, assets) = _sepoliaDeployment();
        }

        core = Core({
            vaultConfigurator: vm.envOr("TESTNET_V1_VAULT_CONFIGURATOR", core.vaultConfigurator),
            networkRegistry: vm.envOr("TESTNET_V1_NETWORK_REGISTRY", core.networkRegistry),
            networkMiddlewareService: vm.envOr("TESTNET_V1_NETWORK_MIDDLEWARE_SERVICE", core.networkMiddlewareService),
            operatorRegistry: vm.envOr("TESTNET_V1_OPERATOR_REGISTRY", core.operatorRegistry),
            operatorVaultOptInService: vm.envOr(
                "TESTNET_V1_OPERATOR_VAULT_OPT_IN_SERVICE", core.operatorVaultOptInService
            ),
            operatorNetworkOptInService: vm.envOr(
                "TESTNET_V1_OPERATOR_NETWORK_OPT_IN_SERVICE", core.operatorNetworkOptInService
            )
        });
        assets = Assets({
            usdc: vm.envOr("TESTNET_V1_USDC", assets.usdc),
            aUsd: vm.envOr("TESTNET_V1_AUSD", assets.aUsd),
            mFone: vm.envOr("TESTNET_V1_MFONE", assets.mFone),
            mGlobal: vm.envOr("TESTNET_V1_MGLOBAL", assets.mGlobal)
        });

        if (!supported && !_allDeploymentAddressesSet(core, assets)) {
            revert DeployV1VaultsChaosTestnetScript__UnsupportedChain(block.chainid);
        }
    }

    function _hoodiDeployment() internal pure returns (Core memory core, Assets memory assets) {
        core = Core({
            vaultConfigurator: address(0x87d9eB1fB660e23B784bf660414297446A769F72),
            networkRegistry: address(0x231e9c011c9B7D4Db670c4048157c12827e609c9),
            networkMiddlewareService: address(0x7bD4b3B1Ffaa1D670FbF20968F88Df76D0674581),
            operatorRegistry: address(0xD71a1C85741A802cc6E734091585E4Ee9C3a284b),
            operatorVaultOptInService: address(0x62960B7c821ECcDb753D2CD5B439454f6B933399),
            operatorNetworkOptInService: address(0x593871aA6f52076f932360359371c9D5a9C91ae2)
        });
        assets = Assets({
            usdc: address(0x7CBD6c85A278a7586E9D1cF737b5BF2433AE69DD),
            aUsd: address(0x84345D59A3a8c9acc0704595E608bE38a714b4FA),
            mFone: address(0xB47e49F0e9beF4bB7d665B8385133825F7bCFbEd),
            mGlobal: address(0x931E73562091aBFC583273D0E3BCB28c43268778)
        });
    }

    function _sepoliaDeployment() internal pure returns (Core memory core, Assets memory assets) {
        core = Core({
            vaultConfigurator: address(0x159B008Da99a6b9D1444Cade586Db2Db039a6Bb5),
            networkRegistry: address(0x563F39055db11b2a64D7b8C883F002968b5458B8),
            networkMiddlewareService: address(0xf4A8dA61336e9900A1975B2a1f9bA5f338Db68fF),
            operatorRegistry: address(0x5579DDc08A6754e2AAbAFcd6E77555391a7887E0),
            operatorVaultOptInService: address(0xF1ab4e2536b59Df2A8D28474D4c6363Ee97142CF),
            operatorNetworkOptInService: address(0xEaD132d5A9670d4f6FF7f4B73b5ae09684603e81)
        });
        assets = Assets({
            usdc: address(0x49F2Db28897860b065FfD5509BD8E75FA450fD91),
            aUsd: address(0x062bcE0Ec64D8f5a5b7dCCb7bFA3eb11bE0AcaE0),
            mFone: address(0x0E338C168597971eC7B0E77278653B6ae76Bc6A7),
            mGlobal: address(0x0a1530B52d37Cc69faE82B9D91Add40653c96ED8)
        });
    }

    function _allDeploymentAddressesSet(Core memory core, Assets memory assets) internal pure returns (bool) {
        return core.vaultConfigurator != address(0) && core.networkRegistry != address(0)
            && core.networkMiddlewareService != address(0) && core.operatorRegistry != address(0)
            && core.operatorVaultOptInService != address(0) && core.operatorNetworkOptInService != address(0)
            && assets.usdc != address(0) && assets.aUsd != address(0) && assets.mFone != address(0)
            && assets.mGlobal != address(0);
    }

    function _logSummary(uint256 seed, RunResult memory result) internal view {
        console2.log("v1 chaos seed", seed);
        console2.log("v1 chaos executor", result.executor);
        console2.log("configuration digest");
        console2.logBytes32(result.configurationDigest);
        console2.log("action plan digest");
        console2.logBytes32(result.actionPlanDigest);
        console2.log("action attempts", result.counters.total);
        console2.log("action successes", result.counters.success);
        console2.log("action failures", result.counters.failure);
        for (uint256 i; i < result.vaults.length; ++i) {
            console2.log("vault index", i);
            console2.log("  vault", result.vaults[i].vault);
            console2.log("  delegator", result.vaults[i].delegator);
            console2.log("  slasher", result.vaults[i].slasher);
            console2.log("  asset", result.vaults[i].asset);
        }
    }

    function runBase(RunParams memory params) public virtual returns (RunResult memory result) {
        V1ChaosExecutor executor;
        VaultPlan[] memory plans;
        (executor, plans, result.vaults) = _setup(params);

        result.executor = address(executor);
        result.configurationDigest = _configurationDigest(plans);
        result.actionPlanDigest = _actionPlanDigest(plans, params.seed, 0);

        _startBroadcast(params.broadcast);
        _executeImmediateDecks(params, executor, plans, result.vaults);
        _stopBroadcast(params.broadcast);

        result.counters = ActionCounters({
            total: executor.totalAttempts(), success: executor.totalSuccesses(), failure: executor.totalFailures()
        });
    }

    function runDelayedBase(DelayedRunParams memory params) public virtual returns (RunResult memory result) {
        V1ChaosExecutor executor;
        VaultPlan[] memory plans;
        (executor, plans, result.vaults) = _validateDelayedRunParams(params);

        result.executor = address(executor);
        result.configurationDigest = _configurationDigest(plans);
        DelayedVaultActionPlan[] memory delayedPlans =
            _buildDelayedActionPlans(params.seed, executor, plans, result.vaults);
        result.actionPlanDigest = _delayedActionPlanDigest(params.seed, executor, delayedPlans);

        uint256 attemptsBefore = executor.totalAttempts();
        uint256 successesBefore = executor.totalSuccesses();
        uint256 failuresBefore = executor.totalFailures();

        _startBroadcast(params.broadcast);
        _executeDelayedSlashes(params.seed, executor, delayedPlans);
        _executeDelayedClaims(params.seed, executor, delayedPlans);
        _stopBroadcast(params.broadcast);

        result.counters = ActionCounters({
            total: executor.totalAttempts() - attemptsBefore,
            success: executor.totalSuccesses() - successesBefore,
            failure: executor.totalFailures() - failuresBefore
        });
    }

    function _validateDelayedRunParams(DelayedRunParams memory params)
        internal
        view
        returns (V1ChaosExecutor executor, VaultPlan[] memory plans, VaultRecord[] memory records)
    {
        if (params.controller == address(0)) {
            revert DeployV1VaultsChaosTestnetScript__InvalidController();
        }
        address caller = params.broadcast ? _scriptOwner() : address(this);
        if (params.controller != caller) {
            revert DeployV1VaultsChaosTestnetScript__ControllerCallerMismatch(params.controller, caller);
        }
        if (params.vaults.length != VAULT_COUNT) {
            revert DeployV1VaultsChaosTestnetScript__InvalidVaultCount(params.vaults.length);
        }

        _requireCode(params.core.vaultConfigurator);
        _requireCode(params.core.networkRegistry);
        _requireCode(params.core.networkMiddlewareService);
        _requireCode(params.core.operatorRegistry);
        _requireCode(params.core.operatorVaultOptInService);
        _requireCode(params.core.operatorNetworkOptInService);

        for (uint256 i; i < params.vaults.length; ++i) {
            _requireCode(params.vaults[i]);
            for (uint256 j; j < i; ++j) {
                if (params.vaults[i] == params.vaults[j]) {
                    revert DeployV1VaultsChaosTestnetScript__DuplicateVault(params.vaults[i]);
                }
            }
        }

        address executorAddress = Ownable(params.vaults[0]).owner();
        _requireCode(executorAddress);
        executor = V1ChaosExecutor(executorAddress);
        if (executor.controller() != params.controller) {
            revert DeployV1VaultsChaosTestnetScript__InvalidDelayedExecutor(executorAddress);
        }

        Assets memory assets = _reconstructAssets(params.vaults, params.seed);
        plans = _planVaults(assets, params.seed);
        records = _validateDelayedVaults(params, executor, plans);
    }

    function _reconstructAssets(address[] memory vaults, uint256 seed) internal view returns (Assets memory assets) {
        uint256 offset = _random(seed, DOMAIN_ASSET_OFFSET, 0, 0) % 4;
        for (uint256 i; i < vaults.length; ++i) {
            uint256 assetIndex = (offset + i) % 4;
            address collateral = IVault(vaults[i]).collateral();
            address known = _assetAt(assets, assetIndex);
            if (known != address(0) && known != collateral) {
                revert DeployV1VaultsChaosTestnetScript__InvalidDelayedVault(i);
            }
            if (known == address(0)) {
                assets = _withAsset(assets, assetIndex, collateral);
            }
        }
    }

    function _withAsset(Assets memory assets, uint256 index, address asset) internal pure returns (Assets memory) {
        if (index == 0) assets.usdc = asset;
        else if (index == 1) assets.aUsd = asset;
        else if (index == 2) assets.mFone = asset;
        else assets.mGlobal = asset;
        return assets;
    }

    function _validateDelayedVaults(DelayedRunParams memory params, V1ChaosExecutor executor, VaultPlan[] memory plans)
        internal
        view
        returns (VaultRecord[] memory records)
    {
        IVaultConfigurator configurator = IVaultConfigurator(params.core.vaultConfigurator);
        address vaultFactory = configurator.VAULT_FACTORY();
        address delegatorFactory = configurator.DELEGATOR_FACTORY();
        address slasherFactory = configurator.SLASHER_FACTORY();
        _requireCode(vaultFactory);
        _requireCode(delegatorFactory);
        _requireCode(slasherFactory);

        address executorAddress = address(executor);
        if (
            !IRegistry(params.core.networkRegistry).isEntity(executorAddress)
                || !IRegistry(params.core.operatorRegistry).isEntity(executorAddress)
                || INetworkMiddlewareService(params.core.networkMiddlewareService).NETWORK_REGISTRY()
                    != params.core.networkRegistry
                || INetworkMiddlewareService(params.core.networkMiddlewareService).middleware(executorAddress)
                    != executorAddress
                || IOptInService(params.core.operatorVaultOptInService).WHO_REGISTRY() != params.core.operatorRegistry
                || IOptInService(params.core.operatorVaultOptInService).WHERE_REGISTRY() != vaultFactory
                || IOptInService(params.core.operatorNetworkOptInService).WHO_REGISTRY() != params.core.operatorRegistry
                || IOptInService(params.core.operatorNetworkOptInService).WHERE_REGISTRY()
                    != params.core.networkRegistry
                || !IOptInService(params.core.operatorNetworkOptInService).isOptedIn(executorAddress, executorAddress)
        ) {
            revert DeployV1VaultsChaosTestnetScript__InvalidDelayedExecutor(executorAddress);
        }

        records = new VaultRecord[](plans.length);
        for (uint256 i; i < plans.length; ++i) {
            records[i] = _validateDelayedVault(
                params.core, executor, plans[i], params.vaults[i], vaultFactory, delegatorFactory, slasherFactory
            );
        }
    }

    function _validateDelayedVault(
        Core memory core,
        V1ChaosExecutor executor,
        VaultPlan memory plan,
        address vaultAddress,
        address vaultFactory,
        address delegatorFactory,
        address slasherFactory
    ) internal view returns (VaultRecord memory record) {
        IVault vault = IVault(vaultAddress);
        address executorAddress = address(executor);
        address delegator = vault.delegator();
        address slasher = vault.slasher();

        bool valid = IRegistry(vaultFactory).isEntity(vaultAddress)
            && IMigratableEntity(vaultAddress).FACTORY() == vaultFactory
            && IMigratableEntity(vaultAddress).version() == plan.vaultVersion
            && Ownable(vaultAddress).owner() == executorAddress && vault.collateral() == plan.asset
            && vault.DELEGATOR_FACTORY() == delegatorFactory && vault.SLASHER_FACTORY() == slasherFactory
            && vault.epochDuration() == plan.epochDuration && IRegistry(delegatorFactory).isEntity(delegator)
            && IBaseDelegator(delegator).FACTORY() == delegatorFactory
            && IBaseDelegator(delegator).NETWORK_REGISTRY() == core.networkRegistry
            && IBaseDelegator(delegator).VAULT_FACTORY() == vaultFactory
            && IBaseDelegator(delegator).OPERATOR_VAULT_OPT_IN_SERVICE() == core.operatorVaultOptInService
            && IBaseDelegator(delegator).OPERATOR_NETWORK_OPT_IN_SERVICE() == core.operatorNetworkOptInService
            && IBaseDelegator(delegator).TYPE() == plan.delegatorType
            && IBaseDelegator(delegator).vault() == vaultAddress
            && IOptInService(core.operatorVaultOptInService).isOptedIn(executorAddress, vaultAddress);
        if (!valid || !_validDelegatorShape(delegator, executorAddress, core.operatorRegistry, plan)) {
            revert DeployV1VaultsChaosTestnetScript__InvalidDelayedVault(plan.index);
        }

        if (plan.slasherMode == SlasherMode.None) {
            if (slasher != address(0)) {
                revert DeployV1VaultsChaosTestnetScript__InvalidDelayedVault(plan.index);
            }
        } else {
            uint64 expectedType = uint64(uint8(plan.slasherMode) - 1);
            valid = slasher != address(0) && IRegistry(slasherFactory).isEntity(slasher)
                && IBaseSlasher(slasher).FACTORY() == slasherFactory && IBaseSlasher(slasher).TYPE() == expectedType
                && IBaseSlasher(slasher).VAULT_FACTORY() == vaultFactory
                && IBaseSlasher(slasher).NETWORK_MIDDLEWARE_SERVICE() == core.networkMiddlewareService
                && IBaseSlasher(slasher).vault() == vaultAddress
                && IBaseSlasher(slasher).isBurnerHook() == plan.isBurnerHook;
            if (plan.slasherMode == SlasherMode.Veto) {
                bytes32 subnetwork = Subnetwork.subnetwork(executorAddress, plan.subnetworkId);
                address expectedResolver = plan.vetoWithResolver ? executorAddress : address(0);
                valid = valid && IVetoSlasher(slasher).vetoDuration() == plan.vetoDuration
                    && IVetoSlasher(slasher).NETWORK_REGISTRY() == core.networkRegistry
                    && IVetoSlasher(slasher).resolver(subnetwork, "") == expectedResolver;
            }
            if (!valid) {
                revert DeployV1VaultsChaosTestnetScript__InvalidDelayedVault(plan.index);
            }
        }

        uint256[] memory epochs = executor.claimEpochs(vaultAddress);
        if (epochs.length == 0) {
            revert DeployV1VaultsChaosTestnetScript__InvalidDelayedVault(plan.index);
        }
        record = VaultRecord({
            vault: vaultAddress,
            delegator: delegator,
            slasher: slasher,
            asset: plan.asset,
            vaultVersion: plan.vaultVersion,
            delegatorType: plan.delegatorType,
            slasherMode: plan.slasherMode,
            vetoWithResolver: plan.vetoWithResolver,
            subnetworkId: plan.subnetworkId,
            claimEpoch: epochs[0]
        });
    }

    function _validDelegatorShape(address delegator, address executor, address operatorRegistry, VaultPlan memory plan)
        internal
        view
        returns (bool)
    {
        bytes32 subnetwork = Subnetwork.subnetwork(executor, plan.subnetworkId);
        if (
            IBaseDelegator(delegator).hook() != address(0) || IBaseDelegator(delegator).maxNetworkLimit(subnetwork) == 0
        ) {
            return false;
        }
        if (plan.delegatorType == 0) {
            return INetworkRestakeDelegator(delegator).networkLimit(subnetwork) > 0
                && INetworkRestakeDelegator(delegator).operatorNetworkShares(subnetwork, executor) > 0;
        }
        if (plan.delegatorType == 1) {
            return IFullRestakeDelegator(delegator).networkLimit(subnetwork) > 0
                && IFullRestakeDelegator(delegator).operatorNetworkLimit(subnetwork, executor) > 0;
        }
        if (plan.delegatorType == 2) {
            return IOperatorSpecificDelegator(delegator).OPERATOR_REGISTRY() == operatorRegistry
                && IOperatorSpecificDelegator(delegator).operator() == executor
                && IOperatorSpecificDelegator(delegator).networkLimit(subnetwork) > 0;
        }
        if (plan.delegatorType == 3) {
            return IOperatorNetworkSpecificDelegator(delegator).OPERATOR_REGISTRY() == operatorRegistry
                && IOperatorNetworkSpecificDelegator(delegator).network() == executor
                && IOperatorNetworkSpecificDelegator(delegator).operator() == executor;
        }
        return true;
    }

    function _buildDelayedActionPlans(
        uint256 seed,
        V1ChaosExecutor executor,
        VaultPlan[] memory plans,
        VaultRecord[] memory records
    ) internal view returns (DelayedVaultActionPlan[] memory delayedPlans) {
        delayedPlans = new DelayedVaultActionPlan[](plans.length);
        for (uint256 i; i < plans.length; ++i) {
            uint256[] memory epochs = _claimableEpochs(executor, records[i].vault);
            (uint256 directEpoch, uint256[] memory batchEpochs) = _claimOperands(records[i].vault, epochs);
            delayedPlans[i] = DelayedVaultActionPlan({
                vaultIndex: plans[i].index,
                vault: records[i].vault,
                slasher: records[i].slasher,
                subnetwork: Subnetwork.subnetwork(address(executor), plans[i].subnetworkId),
                slashFlow: _delayedSlashFlow(plans[i]),
                slashAmount: plans[i].slasherMode == SlasherMode.None ? 0 : DELAYED_SLASH_AMOUNT,
                claimFirst: _claimFirst(seed, plans[i].index),
                directEpoch: directEpoch,
                batchEpochs: batchEpochs
            });
        }
    }

    function _delayedSlashFlow(VaultPlan memory plan) internal pure returns (DelayedSlashFlow) {
        if (plan.slasherMode == SlasherMode.Instant) {
            return DelayedSlashFlow.Slash;
        }
        if (plan.slasherMode == SlasherMode.Veto) {
            return plan.vetoWithResolver ? DelayedSlashFlow.RequestVeto : DelayedSlashFlow.RequestExecute;
        }
        return DelayedSlashFlow.None;
    }

    function _delayedActionPlanDigest(
        uint256 seed,
        V1ChaosExecutor executor,
        DelayedVaultActionPlan[] memory delayedPlans
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_DELAYED_ACTION_PLAN,
                seed,
                DELAYED_ROUND,
                address(executor),
                FRESH_CAPTURE_TIMESTAMP_RULE,
                delayedPlans
            )
        );
    }

    function _executeDelayedSlashes(
        uint256 seed,
        V1ChaosExecutor executor,
        DelayedVaultActionPlan[] memory delayedPlans
    ) internal {
        for (uint256 i; i < delayedPlans.length; ++i) {
            DelayedVaultActionPlan memory delayedPlan = delayedPlans[i];
            if (delayedPlan.slashFlow == DelayedSlashFlow.Slash) {
                executor.executeInstantSlash(
                    seed,
                    delayedPlan.vaultIndex,
                    DELAYED_ROUND,
                    delayedPlan.slasher,
                    delayedPlan.subnetwork,
                    address(executor),
                    delayedPlan.slashAmount
                );
            } else if (
                delayedPlan.slashFlow == DelayedSlashFlow.RequestVeto
                    || delayedPlan.slashFlow == DelayedSlashFlow.RequestExecute
            ) {
                executor.executeVetoSlashSequence(
                    seed,
                    delayedPlan.vaultIndex,
                    DELAYED_ROUND,
                    delayedPlan.slasher,
                    delayedPlan.subnetwork,
                    address(executor),
                    delayedPlan.slashAmount,
                    delayedPlan.slashFlow == DelayedSlashFlow.RequestVeto
                );
            }
        }
    }

    function _executeDelayedClaims(uint256 seed, V1ChaosExecutor executor, DelayedVaultActionPlan[] memory delayedPlans)
        internal
    {
        for (uint256 i; i < delayedPlans.length; ++i) {
            _executeClaimPair(seed, executor, delayedPlans[i]);
        }
    }

    function _claimableEpochs(V1ChaosExecutor executor, address vaultAddress)
        internal
        view
        returns (uint256[] memory epochs)
    {
        IVault vault = IVault(vaultAddress);
        uint256[] memory persisted = executor.claimEpochs(vaultAddress);
        epochs = new uint256[](persisted.length + CLAIM_EPOCH_SCAN_LIMIT);
        uint256 count;
        uint256 currentEpoch = vault.currentEpoch();

        for (uint256 i; i < persisted.length; ++i) {
            count = _appendClaimableEpoch(vault, address(executor), persisted[i], currentEpoch, epochs, count);
        }
        for (uint256 epoch; epoch < CLAIM_EPOCH_SCAN_LIMIT; ++epoch) {
            count = _appendClaimableEpoch(vault, address(executor), epoch, currentEpoch, epochs, count);
        }
        assembly ("memory-safe") {
            mstore(epochs, count)
        }
    }

    function _appendClaimableEpoch(
        IVault vault,
        address account,
        uint256 epoch,
        uint256 currentEpoch,
        uint256[] memory epochs,
        uint256 count
    ) internal view returns (uint256) {
        if (
            epoch >= currentEpoch || vault.isWithdrawalsClaimed(epoch, account)
                || vault.withdrawalsOf(epoch, account) == 0
        ) {
            return count;
        }
        for (uint256 i; i < count; ++i) {
            if (epochs[i] == epoch) {
                return count;
            }
        }
        epochs[count] = epoch;
        return count + 1;
    }

    function _claimOperands(address vault, uint256[] memory epochs)
        internal
        view
        returns (uint256 directEpoch, uint256[] memory batchEpochs)
    {
        directEpoch = epochs.length == 0 ? IVault(vault).currentEpoch() : epochs[0];
        if (epochs.length < 2) {
            batchEpochs = new uint256[](1);
            batchEpochs[0] = directEpoch;
        } else {
            batchEpochs = new uint256[](epochs.length - 1);
            for (uint256 i = 1; i < epochs.length; ++i) {
                batchEpochs[i - 1] = epochs[i];
            }
        }
    }

    function _claimFirst(uint256 seed, uint256 vaultIndex) internal pure returns (bool) {
        return (vaultIndex + _random(seed, DOMAIN_DELAYED_CLAIM_ORDER, 0, 0) % 2) % 2 == 0;
    }

    function _executeClaimPair(uint256 seed, V1ChaosExecutor executor, DelayedVaultActionPlan memory delayedPlan)
        internal
    {
        if (delayedPlan.claimFirst) {
            _attemptClaim(seed, delayedPlan.vaultIndex, executor, delayedPlan.vault, delayedPlan.directEpoch);
            _attemptClaimBatch(seed, delayedPlan.vaultIndex, executor, delayedPlan.vault, delayedPlan.batchEpochs);
        } else {
            _attemptClaimBatch(seed, delayedPlan.vaultIndex, executor, delayedPlan.vault, delayedPlan.batchEpochs);
            _attemptClaim(seed, delayedPlan.vaultIndex, executor, delayedPlan.vault, delayedPlan.directEpoch);
        }
    }

    function _attemptClaim(uint256 seed, uint256 vaultIndex, V1ChaosExecutor executor, address vault, uint256 epoch)
        internal
    {
        executor.executeAttempt(
            seed,
            vaultIndex,
            DELAYED_ROUND,
            uint8(Action.Claim),
            vault,
            abi.encodeCall(IVault.claim, (address(executor), epoch)),
            false
        );
    }

    function _attemptClaimBatch(
        uint256 seed,
        uint256 vaultIndex,
        V1ChaosExecutor executor,
        address vault,
        uint256[] memory epochs
    ) internal {
        executor.executeAttempt(
            seed,
            vaultIndex,
            DELAYED_ROUND,
            uint8(Action.ClaimBatch),
            vault,
            abi.encodeCall(IVault.claimBatch, (address(executor), epochs)),
            false
        );
    }

    function _setup(RunParams memory params)
        internal
        returns (V1ChaosExecutor executor, VaultPlan[] memory plans, VaultRecord[] memory records)
    {
        plans = _validateRunParams(params);

        _startBroadcast(params.broadcast);
        executor = new V1ChaosExecutor(params.controller);
        records = _requiredSetup(params, executor, plans);
        _stopBroadcast(params.broadcast);
    }

    function _requiredSetup(RunParams memory params, V1ChaosExecutor executor, VaultPlan[] memory plans)
        internal
        returns (VaultRecord[] memory records)
    {
        executor.executeRequired(params.core.networkRegistry, abi.encodeCall(INetworkRegistry.registerNetwork, ()));
        executor.executeRequired(params.core.operatorRegistry, abi.encodeCall(IOperatorRegistry.registerOperator, ()));
        executor.executeRequired(
            params.core.networkMiddlewareService,
            abi.encodeCall(INetworkMiddlewareService.setMiddleware, (address(executor)))
        );

        _fundExecutor(params, executor, plans);

        records = new VaultRecord[](plans.length);
        for (uint256 i; i < plans.length; ++i) {
            records[i] = _createVault(params.core.vaultConfigurator, address(executor), plans[i]);
        }

        executor.executeRequired(
            params.core.operatorNetworkOptInService, abi.encodeWithSignature("optIn(address)", address(executor))
        );
        for (uint256 i; i < records.length; ++i) {
            executor.executeRequired(
                params.core.operatorVaultOptInService, abi.encodeWithSignature("optIn(address)", records[i].vault)
            );
        }

        for (uint256 i; i < records.length; ++i) {
            _configureDelegation(executor, plans[i], records[i]);
        }

        for (uint256 i; i < records.length; ++i) {
            records[i].claimEpoch = _seedVault(executor, plans[i], records[i]);
        }

        for (uint256 i; i < records.length; ++i) {
            if (plans[i].slasherMode == SlasherMode.Veto && plans[i].vetoWithResolver) {
                executor.executeRequired(
                    records[i].slasher,
                    abi.encodeCall(IVetoSlasher.setResolver, (plans[i].subnetworkId, address(executor), bytes("")))
                );
            }
        }
    }

    function _validateRunParams(RunParams memory params) internal view returns (VaultPlan[] memory plans) {
        if (params.controller == address(0)) {
            revert DeployV1VaultsChaosTestnetScript__InvalidController();
        }
        address caller = params.broadcast ? _scriptOwner() : address(this);
        if (params.controller != caller) {
            revert DeployV1VaultsChaosTestnetScript__ControllerCallerMismatch(params.controller, caller);
        }

        _requireCode(params.core.vaultConfigurator);
        _requireCode(params.core.networkRegistry);
        _requireCode(params.core.networkMiddlewareService);
        _requireCode(params.core.operatorRegistry);
        _requireCode(params.core.operatorVaultOptInService);
        _requireCode(params.core.operatorNetworkOptInService);
        _validateCoreDependencies(params.core);
        _validateAsset(params.assets.usdc);
        _validateAsset(params.assets.aUsd);
        _validateAsset(params.assets.mFone);
        _validateAsset(params.assets.mGlobal);

        plans = _planVaults(params.assets, params.seed);
        for (uint256 i; i < plans.length; ++i) {
            _units(plans[i].asset, plans[i].depositLimitUnits);
        }

        address[4] memory collateral =
            [params.assets.usdc, params.assets.aUsd, params.assets.mFone, params.assets.mGlobal];
        for (uint256 i; i < collateral.length; ++i) {
            bool duplicate;
            for (uint256 j; j < i; ++j) {
                duplicate = duplicate || collateral[j] == collateral[i];
            }
            if (!duplicate) {
                _assetBudget(plans, collateral[i], params.seed);
            }
        }
    }

    function _validateCoreDependencies(Core memory core) internal view {
        IVaultConfigurator configurator = IVaultConfigurator(core.vaultConfigurator);
        address vaultFactory = configurator.VAULT_FACTORY();
        _requireCode(vaultFactory);
        _requireCode(configurator.DELEGATOR_FACTORY());
        _requireCode(configurator.SLASHER_FACTORY());

        if (INetworkMiddlewareService(core.networkMiddlewareService).NETWORK_REGISTRY() != core.networkRegistry) {
            revert DeployV1VaultsChaosTestnetScript__InvalidCoreDependency(core.networkMiddlewareService);
        }
        if (
            IOptInService(core.operatorVaultOptInService).WHO_REGISTRY() != core.operatorRegistry
                || IOptInService(core.operatorVaultOptInService).WHERE_REGISTRY() != vaultFactory
        ) {
            revert DeployV1VaultsChaosTestnetScript__InvalidCoreDependency(core.operatorVaultOptInService);
        }
        if (
            IOptInService(core.operatorNetworkOptInService).WHO_REGISTRY() != core.operatorRegistry
                || IOptInService(core.operatorNetworkOptInService).WHERE_REGISTRY() != core.networkRegistry
        ) {
            revert DeployV1VaultsChaosTestnetScript__InvalidCoreDependency(core.operatorNetworkOptInService);
        }
    }

    function _requireCode(address target) internal view {
        if (target.code.length == 0) {
            revert DeployV1VaultsChaosTestnetScript__MissingCode(target);
        }
    }

    function _validateAsset(address asset) internal view {
        _requireCode(asset);
        _assetDecimals(asset);
    }

    function _assetDecimals(address asset) internal view returns (uint256 decimals_) {
        (bool success, bytes memory result) = asset.staticcall(abi.encodeCall(IERC20Metadata.decimals, ()));
        if (!success || result.length != 32) {
            revert DeployV1VaultsChaosTestnetScript__InvalidAssetDecimals(asset);
        }
        assembly ("memory-safe") {
            decimals_ := mload(add(result, 0x20))
        }
        if (decimals_ > 77) {
            revert DeployV1VaultsChaosTestnetScript__AssetDecimalsTooLarge(asset, decimals_);
        }
    }

    function _fundExecutor(RunParams memory params, V1ChaosExecutor executor, VaultPlan[] memory plans) internal {
        address[4] memory collateral =
            [params.assets.usdc, params.assets.aUsd, params.assets.mFone, params.assets.mGlobal];
        for (uint256 i; i < collateral.length; ++i) {
            bool duplicate;
            for (uint256 j; j < i; ++j) {
                duplicate = duplicate || collateral[j] == collateral[i];
            }
            if (!duplicate) {
                _fundAsset(
                    params.controller, address(executor), collateral[i], _assetBudget(plans, collateral[i], params.seed)
                );
            }
        }
    }

    function _fundAsset(address controller, address executor, address asset, uint256 budget) internal {
        IERC20 token = IERC20(asset);
        uint256 executorBalance = token.balanceOf(executor);
        if (executorBalance < budget) {
            uint256 controllerBalance = token.balanceOf(controller);
            uint256 transferAmount = _min(controllerBalance, budget - executorBalance);
            if (transferAmount != 0) {
                token.safeTransfer(executor, transferAmount);
            }
        }

        executorBalance = token.balanceOf(executor);
        if (executorBalance < budget) {
            _tryMint(asset, executor, budget - executorBalance);
        }

        executorBalance = token.balanceOf(executor);
        if (executorBalance < budget) {
            revert DeployV1VaultsChaosTestnetScript__InsufficientAssetBudget(asset, budget, executorBalance);
        }
    }

    function _tryMint(address asset, address account, uint256 amount) internal {
        (bool success,) = asset.call(abi.encodeWithSignature("mint(address,uint256)", account, amount));
        if (!success) {
            return;
        }
    }

    function _assetBudget(VaultPlan[] memory plans, address asset, uint256 seed)
        internal
        view
        returns (uint256 budget)
    {
        uint256 wholeTokens;
        for (uint256 i; i < plans.length; ++i) {
            if (plans[i].asset != asset) {
                continue;
            }

            wholeTokens += plans[i].baselineDepositUnits;
            PlannedAction[] memory deck = _buildActionDeck(plans[i], seed, 0);
            for (uint256 j; j < deck.length; ++j) {
                if (deck[j].action == Action.Deposit) {
                    wholeTokens += deck[j].value;
                }
            }
        }
        budget = _units(asset, wholeTokens);
    }

    function _createVault(address configurator, address executor, VaultPlan memory plan)
        internal
        returns (VaultRecord memory record)
    {
        bool withSlasher = plan.slasherMode != SlasherMode.None;
        uint64 slasherIndex = plan.slasherMode == SlasherMode.Veto ? 1 : 0;
        (record.vault, record.delegator, record.slasher) = IVaultConfigurator(configurator)
            .create(
                IVaultConfigurator.InitParams({
                version: plan.vaultVersion,
                owner: executor,
                vaultParams: _vaultParams(executor, plan),
                delegatorIndex: plan.delegatorType,
                delegatorParams: _delegatorParams(executor, plan),
                withSlasher: withSlasher,
                slasherIndex: slasherIndex,
                slasherParams: withSlasher ? _slasherParams(plan) : bytes("")
            })
            );
        record.asset = plan.asset;
        record.vaultVersion = plan.vaultVersion;
        record.delegatorType = plan.delegatorType;
        record.slasherMode = plan.slasherMode;
        record.vetoWithResolver = plan.vetoWithResolver;
        record.subnetworkId = plan.subnetworkId;
    }

    function _vaultParams(address executor, VaultPlan memory plan) internal view returns (bytes memory) {
        IVault.InitParams memory baseParams = IVault.InitParams({
            collateral: plan.asset,
            burner: address(0xdEaD),
            epochDuration: plan.epochDuration,
            depositWhitelist: plan.initialDepositWhitelist,
            isDepositLimit: plan.initialIsDepositLimit,
            depositLimit: _units(plan.asset, plan.depositLimitUnits),
            defaultAdminRoleHolder: executor,
            depositWhitelistSetRoleHolder: executor,
            depositorWhitelistRoleHolder: executor,
            isDepositLimitSetRoleHolder: executor,
            depositLimitSetRoleHolder: executor
        });
        if (plan.vaultVersion == VAULT_TOKENIZED_VERSION) {
            string memory suffix = Strings.toString(plan.tokenizedSuffix);
            return abi.encode(
                IVaultTokenized.InitParamsTokenized({
                    baseParams: baseParams,
                    name: string.concat("V1 Chaos Vault ", suffix),
                    symbol: string.concat("V1C-", suffix)
                })
            );
        }
        return abi.encode(baseParams);
    }

    function _delegatorParams(address executor, VaultPlan memory plan) internal pure returns (bytes memory) {
        IBaseDelegator.BaseParams memory baseParams = IBaseDelegator.BaseParams({
            defaultAdminRoleHolder: executor, hook: address(0), hookSetRoleHolder: executor
        });
        address[] memory roleHolders = new address[](1);
        roleHolders[0] = executor;

        if (plan.delegatorType == 0) {
            return abi.encode(
                INetworkRestakeDelegator.InitParams({
                    baseParams: baseParams,
                    networkLimitSetRoleHolders: roleHolders,
                    operatorNetworkSharesSetRoleHolders: roleHolders
                })
            );
        }
        if (plan.delegatorType == 1) {
            return abi.encode(
                IFullRestakeDelegator.InitParams({
                    baseParams: baseParams,
                    networkLimitSetRoleHolders: roleHolders,
                    operatorNetworkLimitSetRoleHolders: roleHolders
                })
            );
        }
        if (plan.delegatorType == 2) {
            return abi.encode(
                IOperatorSpecificDelegator.InitParams({
                    baseParams: baseParams, networkLimitSetRoleHolders: roleHolders, operator: executor
                })
            );
        }
        return abi.encode(
            IOperatorNetworkSpecificDelegator.InitParams({
                baseParams: baseParams, network: executor, operator: executor
            })
        );
    }

    function _slasherParams(VaultPlan memory plan) internal pure returns (bytes memory) {
        IBaseSlasher.BaseParams memory baseParams = IBaseSlasher.BaseParams({isBurnerHook: plan.isBurnerHook});
        if (plan.slasherMode == SlasherMode.Veto) {
            return abi.encode(
                IVetoSlasher.InitParams({
                    baseParams: baseParams, vetoDuration: plan.vetoDuration, resolverSetEpochsDelay: 3
                })
            );
        }
        return abi.encode(ISlasher.InitParams({baseParams: baseParams}));
    }

    function _configureDelegation(V1ChaosExecutor executor, VaultPlan memory plan, VaultRecord memory record) internal {
        uint256 limit = _units(plan.asset, plan.depositLimitUnits);
        bytes32 subnetwork = Subnetwork.subnetwork(address(executor), plan.subnetworkId);

        executor.executeRequired(
            record.delegator, abi.encodeCall(IBaseDelegator.setMaxNetworkLimit, (plan.subnetworkId, limit))
        );
        if (plan.delegatorType == 0) {
            executor.executeRequired(
                record.delegator, abi.encodeCall(INetworkRestakeDelegator.setNetworkLimit, (subnetwork, limit))
            );
            executor.executeRequired(
                record.delegator,
                abi.encodeCall(INetworkRestakeDelegator.setOperatorNetworkShares, (subnetwork, address(executor), 1))
            );
        } else if (plan.delegatorType == 1) {
            executor.executeRequired(
                record.delegator, abi.encodeCall(IFullRestakeDelegator.setNetworkLimit, (subnetwork, limit))
            );
            executor.executeRequired(
                record.delegator,
                abi.encodeCall(IFullRestakeDelegator.setOperatorNetworkLimit, (subnetwork, address(executor), limit))
            );
        } else if (plan.delegatorType == 2) {
            executor.executeRequired(
                record.delegator, abi.encodeCall(IOperatorSpecificDelegator.setNetworkLimit, (subnetwork, limit))
            );
        }
    }

    function _seedVault(V1ChaosExecutor executor, VaultPlan memory plan, VaultRecord memory record)
        internal
        returns (uint256 claimEpoch)
    {
        if (plan.initialDepositWhitelist) {
            executor.executeRequired(
                record.vault, abi.encodeCall(IVault.setDepositorWhitelistStatus, (address(executor), true))
            );
        }

        executor.executeRequired(record.asset, abi.encodeCall(IERC20.approve, (record.vault, type(uint256).max)));
        executor.executeRequired(
            record.vault,
            abi.encodeCall(IVault.deposit, (address(executor), _units(plan.asset, plan.baselineDepositUnits)))
        );

        claimEpoch = IVault(record.vault).currentEpoch() + 1;
        executor.executeRequired(
            record.vault,
            abi.encodeCall(IVault.withdraw, (address(executor), _units(plan.asset, plan.baselineWithdrawalUnits)))
        );
    }

    function _executeImmediateDecks(
        RunParams memory params,
        V1ChaosExecutor executor,
        VaultPlan[] memory plans,
        VaultRecord[] memory records
    ) internal {
        for (uint256 i; i < plans.length; ++i) {
            PlannedAction[] memory deck = _buildActionDeck(plans[i], params.seed, 0);
            for (uint256 j; j < deck.length; ++j) {
                (address target, bytes memory data) = _immediateCall(params, executor, plans[i], records[i], deck[j]);
                executor.executeAttempt(
                    params.seed, plans[i].index, 0, uint8(deck[j].action), target, data, deck[j].readOnly
                );
            }

            executor.ensureOptIn(params.core.operatorVaultOptInService, records[i].vault);
            executor.ensureOptIn(params.core.operatorNetworkOptInService, address(executor));
            executor.ensureHookCleared(records[i].delegator);
        }
    }

    function _immediateCall(
        RunParams memory params,
        V1ChaosExecutor executor,
        VaultPlan memory plan,
        VaultRecord memory record,
        PlannedAction memory planned
    ) internal view returns (address target, bytes memory data) {
        Action action = planned.action;
        bytes32 subnetwork = Subnetwork.subnetwork(address(executor), plan.subnetworkId);

        if (action == Action.SetDepositWhitelist) {
            return (record.vault, abi.encodeCall(IVault.setDepositWhitelist, (planned.value != 0)));
        }
        if (action == Action.SetDepositorWhitelistStatus) {
            return
                (
                    record.vault,
                    abi.encodeCall(IVault.setDepositorWhitelistStatus, (address(executor), planned.value != 0))
                );
        }
        if (action == Action.SetIsDepositLimit) {
            return (record.vault, abi.encodeCall(IVault.setIsDepositLimit, (planned.value != 0)));
        }
        if (action == Action.SetDepositLimit) {
            uint256 limit = planned.value == 0 ? type(uint256).max : _units(plan.asset, planned.value);
            return (record.vault, abi.encodeCall(IVault.setDepositLimit, (limit)));
        }
        if (action == Action.OptOutVault) {
            return (params.core.operatorVaultOptInService, abi.encodeWithSignature("optOut(address)", record.vault));
        }
        if (action == Action.OptInVault) {
            return (params.core.operatorVaultOptInService, abi.encodeWithSignature("optIn(address)", record.vault));
        }
        if (action == Action.IncreaseVaultOptInNonce) {
            return (params.core.operatorVaultOptInService, abi.encodeCall(IOptInService.increaseNonce, (record.vault)));
        }
        if (action == Action.OptOutNetwork) {
            return
                (params.core.operatorNetworkOptInService, abi.encodeWithSignature("optOut(address)", address(executor)));
        }
        if (action == Action.OptInNetwork) {
            return
                (params.core.operatorNetworkOptInService, abi.encodeWithSignature("optIn(address)", address(executor)));
        }
        if (action == Action.IncreaseNetworkOptInNonce) {
            return
                (
                    params.core.operatorNetworkOptInService,
                    abi.encodeCall(IOptInService.increaseNonce, (address(executor)))
                );
        }
        if (action == Action.SetHook) {
            address hook = planned.value == 0 ? address(0) : _passiveReceiver(plan, address(executor), record.vault);
            return (record.delegator, abi.encodeCall(IBaseDelegator.setHook, (hook)));
        }
        if (action == Action.SetMaxNetworkLimit) {
            uint256 limit = planned.occurrence == 0 ? _units(plan.asset, planned.value) : type(uint256).max;
            return (record.delegator, abi.encodeCall(IBaseDelegator.setMaxNetworkLimit, (plan.subnetworkId, limit)));
        }
        if (action == Action.SetNetworkLimit) {
            uint256 limit = _units(plan.asset, planned.value);
            if (plan.delegatorType == 0) {
                return (record.delegator, abi.encodeCall(INetworkRestakeDelegator.setNetworkLimit, (subnetwork, limit)));
            }
            if (plan.delegatorType == 1) {
                return (record.delegator, abi.encodeCall(IFullRestakeDelegator.setNetworkLimit, (subnetwork, limit)));
            }
            if (plan.delegatorType == 2) {
                return
                    (record.delegator, abi.encodeCall(IOperatorSpecificDelegator.setNetworkLimit, (subnetwork, limit)));
            }
        }
        if (action == Action.SetOperatorNetworkShares && plan.delegatorType == 0) {
            return (
                record.delegator,
                abi.encodeCall(
                    INetworkRestakeDelegator.setOperatorNetworkShares, (subnetwork, address(executor), planned.value)
                )
            );
        }
        if (action == Action.SetOperatorNetworkLimit && plan.delegatorType == 1) {
            return (
                record.delegator,
                abi.encodeCall(
                    IFullRestakeDelegator.setOperatorNetworkLimit,
                    (subnetwork, address(executor), _units(plan.asset, planned.value))
                )
            );
        }
        if (action == Action.Deposit) {
            return
                (record.vault, abi.encodeCall(IVault.deposit, (address(executor), _units(plan.asset, planned.value))));
        }
        if (action == Action.Withdraw) {
            return (
                record.vault,
                abi.encodeCall(IVault.withdraw, (address(executor), _boundedExitAmount(plan, planned.value)))
            );
        }
        if (action == Action.Redeem) {
            return
                (
                    record.vault,
                    abi.encodeCall(IVault.redeem, (address(executor), _boundedExitAmount(plan, planned.value)))
                );
        }
        if (action == Action.ApproveShares && plan.vaultVersion == VAULT_TOKENIZED_VERSION) {
            return (
                record.vault,
                abi.encodeCall(IERC20.approve, (address(executor), _boundedExitAmount(plan, planned.value)))
            );
        }
        if (action == Action.TransferShares && plan.vaultVersion == VAULT_TOKENIZED_VERSION) {
            return (
                record.vault,
                abi.encodeCall(
                    IERC20.transfer,
                    (_passiveReceiver(plan, address(executor), record.vault), _boundedExitAmount(plan, planned.value))
                )
            );
        }
        if (action == Action.TransferFromShares && plan.vaultVersion == VAULT_TOKENIZED_VERSION) {
            return (
                record.vault,
                abi.encodeCall(
                    IERC20.transferFrom,
                    (
                        address(executor),
                        _passiveReceiver(plan, address(executor), record.vault),
                        _boundedExitAmount(plan, planned.value)
                    )
                )
            );
        }
        if (action == Action.SetResolver && plan.slasherMode == SlasherMode.Veto && plan.vetoWithResolver) {
            return (
                record.slasher,
                abi.encodeCall(IVetoSlasher.setResolver, (plan.subnetworkId, address(executor), bytes("")))
            );
        }
        if (action == Action.ReadVault) {
            return (record.vault, abi.encodeCall(IVault.totalStake, ()));
        }
        if (action == Action.ReadDelegator) {
            return (record.delegator, abi.encodeCall(IBaseDelegator.stake, (subnetwork, address(executor))));
        }
        if (action == Action.ReadVaultOptIn) {
            return (
                params.core.operatorVaultOptInService,
                abi.encodeCall(IOptInService.isOptedIn, (address(executor), record.vault))
            );
        }
        if (action == Action.ReadNetworkOptIn) {
            return (
                params.core.operatorNetworkOptInService,
                abi.encodeCall(IOptInService.isOptedIn, (address(executor), address(executor)))
            );
        }
        if (action == Action.ReadSlasher && plan.slasherMode != SlasherMode.None) {
            return (record.slasher, abi.encodeCall(IBaseSlasher.cumulativeSlash, (subnetwork, address(executor))));
        }

        revert DeployV1VaultsChaosTestnetScript__UnsupportedImmediateAction(action);
    }

    function _boundedExitAmount(VaultPlan memory plan, uint256 plannedWholeTokens) internal view returns (uint256) {
        uint256 remaining = _units(plan.asset, plan.baselineDepositUnits - plan.baselineWithdrawalUnits);
        uint256 cap = remaining / 20;
        return _min(_units(plan.asset, plannedWholeTokens), cap);
    }

    function _passiveReceiver(VaultPlan memory plan, address executor, address vault)
        internal
        pure
        returns (address receiver)
    {
        receiver = address(uint160(uint256(keccak256(abi.encode(DOMAIN_PASSIVE_RECEIVER, plan.index)))));
        if (receiver != address(0) && receiver != executor && receiver != vault) {
            return receiver;
        }

        receiver = address(1);
        if (receiver == executor || receiver == vault) {
            receiver = address(2);
        }
        if (receiver == executor || receiver == vault) {
            receiver = address(3);
        }
    }

    function _units(address asset, uint256 wholeTokens) internal view returns (uint256) {
        uint256 decimals_ = _assetDecimals(asset);
        uint256 scale = 10 ** decimals_;
        if (wholeTokens > type(uint256).max / scale) {
            revert DeployV1VaultsChaosTestnetScript__ScaledAmountOverflow(asset, wholeTokens, decimals_);
        }
        return wholeTokens * scale;
    }

    function _min(uint256 left, uint256 right) internal pure returns (uint256) {
        return left < right ? left : right;
    }

    function _startBroadcast(bool broadcast_) internal virtual {
        if (broadcast_) {
            vm.startBroadcast();
        }
    }

    function _stopBroadcast(bool broadcast_) internal virtual {
        if (broadcast_) {
            vm.stopBroadcast();
        }
    }

    function _scriptOwner() internal view virtual returns (address owner) {
        (,, address origin) = vm.readCallers();
        owner = origin == address(0) ? msg.sender : origin;
    }

    function _planVaults(Assets memory assets, uint256 seed) internal pure returns (VaultPlan[] memory plans) {
        plans = new VaultPlan[](VAULT_COUNT);
        for (uint256 index; index < plans.length; ++index) {
            VaultPlan memory plan;
            plan.index = index;
            plan.delegatorType = uint64(index % 4);
            plan.slasherMode = SlasherMode(index / 4);
            plan.vaultVersion = index % 2 == 0 ? VAULT_VERSION : VAULT_TOKENIZED_VERSION;
            plan.assetIndex = uint8((_random(seed, DOMAIN_ASSET_OFFSET, 0, 0) + index) % 4);
            plan.asset = _assetAt(assets, plan.assetIndex);
            plan.epochDuration = uint48(_range(seed, DOMAIN_EPOCH, index, 0, 2, 8));
            plan.vetoDuration = plan.slasherMode == SlasherMode.Veto
                ? uint48(_range(seed, DOMAIN_VETO_DURATION, index, 0, 1, plan.epochDuration - 1))
                : 0;
            plan.vetoWithResolver = plan.slasherMode == SlasherMode.Veto
                && ((index - 8 + _random(seed, DOMAIN_VETO_ROTATION, 0, 0) % 4) % 2 == 0);
            plan.subnetworkId =
                uint96(1 << 95) | (uint96(_random(seed, DOMAIN_SUBNETWORK, index, 0)) & ~uint96(0xF)) | uint96(index);
            plan.initialDepositWhitelist = _random(seed, DOMAIN_DEPOSIT_WHITELIST, index, 0) % 2 == 1;
            plan.initialIsDepositLimit = _random(seed, DOMAIN_DEPOSIT_LIMIT_ENABLED, index, 0) % 2 == 1;
            plan.isBurnerHook = _random(seed, DOMAIN_BURNER_HOOK, index, 0) % 2 == 1;
            plan.baselineDepositUnits = _range(seed, DOMAIN_BASELINE_DEPOSIT, index, 0, 10, 100);
            plan.baselineWithdrawalUnits =
                _range(seed, DOMAIN_BASELINE_WITHDRAWAL, index, 0, 1, plan.baselineDepositUnits - 1);
            plan.depositLimitUnits = _range(
                seed, DOMAIN_DEPOSIT_LIMIT, index, 0, 10 * plan.baselineDepositUnits, 20 * plan.baselineDepositUnits
            );
            plan.tokenizedSuffix = _range(seed, DOMAIN_TOKENIZED_SUFFIX, index, 0, 1, 999_999);
            plans[index] = plan;
        }
    }

    function _buildActionDeck(VaultPlan memory plan, uint256 seed, uint256 round)
        internal
        pure
        returns (PlannedAction[] memory deck)
    {
        uint256 deckLength = 32;
        if (plan.delegatorType == 0 || plan.delegatorType == 1) {
            deckLength += 2;
        } else if (plan.delegatorType == 2) {
            ++deckLength;
        }
        if (plan.vaultVersion == VAULT_TOKENIZED_VERSION) {
            deckLength += 3;
        }
        if (plan.slasherMode != SlasherMode.None) {
            ++deckLength;
        }
        if (plan.slasherMode == SlasherMode.Veto && plan.vetoWithResolver) {
            ++deckLength;
        }

        deck = new PlannedAction[](deckLength);
        uint256 cursor;
        cursor = _appendActions(deck, cursor, plan, seed, Action.SetDepositWhitelist, 2);
        cursor = _appendActions(deck, cursor, plan, seed, Action.SetDepositorWhitelistStatus, 2);
        cursor = _appendActions(deck, cursor, plan, seed, Action.SetIsDepositLimit, 2);
        cursor = _appendActions(deck, cursor, plan, seed, Action.SetDepositLimit, 3);
        cursor = _appendActions(deck, cursor, plan, seed, Action.OptOutVault, 1);
        cursor = _appendActions(deck, cursor, plan, seed, Action.OptInVault, 1);
        cursor = _appendActions(deck, cursor, plan, seed, Action.IncreaseVaultOptInNonce, 1);
        cursor = _appendActions(deck, cursor, plan, seed, Action.OptOutNetwork, 1);
        cursor = _appendActions(deck, cursor, plan, seed, Action.OptInNetwork, 1);
        cursor = _appendActions(deck, cursor, plan, seed, Action.IncreaseNetworkOptInNonce, 1);
        cursor = _appendActions(deck, cursor, plan, seed, Action.SetHook, 2);
        cursor = _appendActions(deck, cursor, plan, seed, Action.SetMaxNetworkLimit, 2);

        if (plan.delegatorType < 3) {
            cursor = _appendActions(deck, cursor, plan, seed, Action.SetNetworkLimit, 1);
        }
        if (plan.delegatorType == 0) {
            cursor = _appendActions(deck, cursor, plan, seed, Action.SetOperatorNetworkShares, 1);
        } else if (plan.delegatorType == 1) {
            cursor = _appendActions(deck, cursor, plan, seed, Action.SetOperatorNetworkLimit, 1);
        }

        cursor = _appendActions(deck, cursor, plan, seed, Action.Deposit, 3);
        cursor = _appendActions(deck, cursor, plan, seed, Action.Withdraw, 3);
        cursor = _appendActions(deck, cursor, plan, seed, Action.Redeem, 3);

        if (plan.vaultVersion == VAULT_TOKENIZED_VERSION) {
            cursor = _appendActions(deck, cursor, plan, seed, Action.ApproveShares, 1);
            cursor = _appendActions(deck, cursor, plan, seed, Action.TransferShares, 1);
            cursor = _appendActions(deck, cursor, plan, seed, Action.TransferFromShares, 1);
        }
        if (plan.slasherMode == SlasherMode.Veto && plan.vetoWithResolver) {
            cursor = _appendActions(deck, cursor, plan, seed, Action.SetResolver, 1);
        }

        cursor = _appendActions(deck, cursor, plan, seed, Action.ReadVault, 1);
        cursor = _appendActions(deck, cursor, plan, seed, Action.ReadDelegator, 1);
        cursor = _appendActions(deck, cursor, plan, seed, Action.ReadVaultOptIn, 1);
        cursor = _appendActions(deck, cursor, plan, seed, Action.ReadNetworkOptIn, 1);
        if (plan.slasherMode != SlasherMode.None) {
            _appendActions(deck, cursor, plan, seed, Action.ReadSlasher, 1);
        }

        _shuffle(deck, seed, plan.index, round);
    }

    function _configurationDigest(VaultPlan[] memory plans) internal pure returns (bytes32) {
        return keccak256(abi.encode(plans));
    }

    function _actionPlanDigest(VaultPlan[] memory plans, uint256 seed, uint256 round)
        internal
        pure
        returns (bytes32 digest)
    {
        digest = keccak256(abi.encode(round, plans.length));
        for (uint256 i; i < plans.length; ++i) {
            digest = keccak256(abi.encode(digest, _buildActionDeck(plans[i], seed, round)));
        }
    }

    function _appendActions(
        PlannedAction[] memory deck,
        uint256 cursor,
        VaultPlan memory plan,
        uint256 seed,
        Action action,
        uint8 count
    ) internal pure returns (uint256) {
        for (uint8 occurrence; occurrence < count; ++occurrence) {
            deck[cursor] = PlannedAction({
                action: action,
                occurrence: occurrence,
                value: _actionValue(plan, seed, action, occurrence),
                readOnly: _isReadOnly(action)
            });
            ++cursor;
        }
        return cursor;
    }

    function _actionValue(VaultPlan memory plan, uint256 seed, Action action, uint8 occurrence)
        internal
        pure
        returns (uint256)
    {
        bytes32 domain = keccak256(abi.encode(DOMAIN_ACTION_VALUE, action));
        uint256 randomValue = _random(seed, domain, plan.index, occurrence);

        if (
            action == Action.SetDepositWhitelist || action == Action.SetDepositorWhitelistStatus
                || action == Action.SetIsDepositLimit || action == Action.SetHook
        ) {
            return (_random(seed, domain, plan.index, 0) % 2 + occurrence) % 2;
        }
        if (action == Action.SetDepositLimit) {
            return occurrence == 0
                ? 0
                : plan.baselineDepositUnits + randomValue % (plan.depositLimitUnits - plan.baselineDepositUnits + 1);
        }
        if (action == Action.Deposit) {
            return 1 + randomValue % plan.baselineDepositUnits;
        }
        if (action == Action.Withdraw || action == Action.Redeem) {
            return 1 + randomValue % plan.baselineWithdrawalUnits;
        }
        if (
            action == Action.SetMaxNetworkLimit || action == Action.SetNetworkLimit
                || action == Action.SetOperatorNetworkShares || action == Action.SetOperatorNetworkLimit
        ) {
            return 1 + randomValue % plan.depositLimitUnits;
        }
        if (action == Action.ApproveShares || action == Action.TransferShares || action == Action.TransferFromShares) {
            return 1 + randomValue % plan.baselineDepositUnits;
        }
        return randomValue;
    }

    function _isReadOnly(Action action) internal pure returns (bool) {
        return action == Action.ReadVault || action == Action.ReadDelegator || action == Action.ReadVaultOptIn
            || action == Action.ReadNetworkOptIn || action == Action.ReadSlasher;
    }

    function _shuffle(PlannedAction[] memory deck, uint256 seed, uint256 vaultIndex, uint256 round) internal pure {
        for (uint256 position = deck.length; position > 1; --position) {
            uint256 swapIndex =
                uint256(keccak256(abi.encode(seed, DOMAIN_ACTION_SHUFFLE, vaultIndex, round, position))) % position;
            PlannedAction memory current = deck[position - 1];
            deck[position - 1] = deck[swapIndex];
            deck[swapIndex] = current;
        }
    }

    function _assetAt(Assets memory assets, uint256 index) internal pure returns (address) {
        if (index == 0) return assets.usdc;
        if (index == 1) return assets.aUsd;
        if (index == 2) return assets.mFone;
        return assets.mGlobal;
    }

    function _range(uint256 seed, bytes32 domain, uint256 vaultIndex, uint256 occurrence, uint256 min, uint256 max)
        internal
        pure
        returns (uint256)
    {
        return min + _random(seed, domain, vaultIndex, occurrence) % (max - min + 1);
    }

    function _random(uint256 seed, bytes32 domain, uint256 vaultIndex, uint256 occurrence)
        internal
        pure
        returns (uint256)
    {
        return uint256(keccak256(abi.encode(seed, domain, vaultIndex, occurrence)));
    }
}
