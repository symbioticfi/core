// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {
    DeployV1VaultsChaosTestnetScript,
    V1ChaosExecutor
} from "../../script/deploy/testnet/DeployV1VaultsChaosTestnet.s.sol";
import {DeployCoreBaseScript} from "../../script/deploy/base/DeployCoreBase.s.sol";
import {NetworkMiddlewareService} from "../../src/contracts/service/NetworkMiddlewareService.sol";
import {OperatorRegistry} from "../../src/contracts/OperatorRegistry.sol";

import {IRegistry} from "../../src/interfaces/common/IRegistry.sol";
import {IBaseDelegator} from "../../src/interfaces/delegator/IBaseDelegator.sol";
import {IFullRestakeDelegator} from "../../src/interfaces/delegator/IFullRestakeDelegator.sol";
import {INetworkRestakeDelegator} from "../../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IOperatorNetworkSpecificDelegator} from "../../src/interfaces/delegator/IOperatorNetworkSpecificDelegator.sol";
import {IOperatorSpecificDelegator} from "../../src/interfaces/delegator/IOperatorSpecificDelegator.sol";
import {IOptInService} from "../../src/interfaces/service/IOptInService.sol";
import {IBaseSlasher} from "../../src/interfaces/slasher/IBaseSlasher.sol";
import {IVetoSlasher} from "../../src/interfaces/slasher/IVetoSlasher.sol";
import {IVault, VAULT_VERSION} from "../../src/interfaces/vault/IVault.sol";
import {VAULT_TOKENIZED_VERSION} from "../../src/interfaces/vault/IVaultTokenized.sol";
import {Subnetwork} from "../../src/contracts/libraries/Subnetwork.sol";

error V1ChaosExecutorTestTarget__Reverted(uint256 reason);

contract V1ChaosExecutorFailingTarget {
    function run() external pure {
        revert V1ChaosExecutorTestTarget__Reverted(17);
    }
}

contract V1ChaosExecutorSuccessfulTarget {
    uint256 public calls;

    function run() external {
        ++calls;
    }
}

contract DeployV1VaultsChaosCoreHarness is DeployCoreBaseScript {
    address internal immutable owner;

    constructor(address owner_) {
        owner = owner_;
    }

    function _startBroadcast() internal override {
        vm.startPrank(owner, owner);
    }

    function _stopBroadcast() internal override {
        vm.stopPrank();
    }
}

contract ChaosTestToken is ERC20 {
    uint8 internal immutable tokenDecimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        tokenDecimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return tokenDecimals;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract ChaosRevertingDecimalsToken {
    function decimals() external pure returns (uint8) {
        revert("decimals reverted");
    }
}

contract ChaosMalformedDecimalsToken {
    fallback() external {
        assembly ("memory-safe") {
            mstore(0, 18)
            return(31, 1)
        }
    }
}

contract ChaosTooManyDecimalsToken {
    function decimals() external pure returns (uint8) {
        return 78;
    }
}

contract DeployV1VaultsChaosTestnetScriptHarness is DeployV1VaultsChaosTestnetScript {
    function exposedHoodiDeployment() external pure returns (Core memory core_, Assets memory assets_) {
        return _hoodiDeployment();
    }

    function exposedSepoliaDeployment() external pure returns (Core memory core_, Assets memory assets_) {
        return _sepoliaDeployment();
    }

    function exposedLatestDeployment() external view returns (Core memory core_, Assets memory assets_) {
        return _latestDeployment();
    }

    function exposedPlans(Assets memory assets, uint256 seed) external pure returns (VaultPlan[] memory) {
        return _planVaults(assets, seed);
    }

    function exposedActionDeck(VaultPlan memory plan, uint256 seed) external pure returns (PlannedAction[] memory) {
        return _buildActionDeck(plan, seed, 0);
    }

    function exposedActionDeckForRound(VaultPlan memory plan, uint256 seed, uint256 round)
        external
        pure
        returns (PlannedAction[] memory)
    {
        return _buildActionDeck(plan, seed, round);
    }

    function exposedConfigurationDigest(VaultPlan[] memory plans) external pure returns (bytes32) {
        return _configurationDigest(plans);
    }

    function exposedActionPlanDigest(VaultPlan[] memory plans, uint256 seed, uint256 round)
        external
        pure
        returns (bytes32)
    {
        return _actionPlanDigest(plans, seed, round);
    }

    function exposedDelayedActionPlanDigest(DelayedRunParams memory params) external view returns (bytes32) {
        (V1ChaosExecutor executor, VaultPlan[] memory plans, VaultRecord[] memory records) =
            _validateDelayedRunParams(params);
        DelayedVaultActionPlan[] memory delayedPlans = _buildDelayedActionPlans(params.seed, executor, plans, records);
        return _delayedActionPlanDigest(params.seed, executor, delayedPlans);
    }

    function exposedBoundedExitAmount(VaultPlan memory plan, uint256 plannedWholeTokens)
        external
        view
        returns (uint256)
    {
        return _boundedExitAmount(plan, plannedWholeTokens);
    }

    function runSetupOnly(RunParams memory params) external returns (address executor, VaultRecord[] memory vaults) {
        V1ChaosExecutor setupExecutor;
        (setupExecutor,, vaults) = _setup(params);
        executor = address(setupExecutor);
    }
}

contract DeployV1VaultsChaosTestnetTest is Test {
    using Subnetwork for address;

    bytes32 internal constant V1_CHAOS_ACTION_EVENT =
        keccak256("V1ChaosAction(uint256,uint256,uint256,uint8,address,bytes4,bool,bytes32)");
    bytes4 internal constant NOT_CONTROLLER = bytes4(keccak256("V1ChaosExecutor__NotController()"));
    bytes4 internal constant MISSING_CODE = bytes4(keccak256("DeployV1VaultsChaosTestnetScript__MissingCode(address)"));
    bytes4 internal constant CONTROLLER_CALLER_MISMATCH =
        bytes4(keccak256("DeployV1VaultsChaosTestnetScript__ControllerCallerMismatch(address,address)"));
    bytes4 internal constant INVALID_ASSET_DECIMALS =
        bytes4(keccak256("DeployV1VaultsChaosTestnetScript__InvalidAssetDecimals(address)"));
    bytes4 internal constant ASSET_DECIMALS_TOO_LARGE =
        bytes4(keccak256("DeployV1VaultsChaosTestnetScript__AssetDecimalsTooLarge(address,uint256)"));
    bytes4 internal constant SCALED_AMOUNT_OVERFLOW =
        bytes4(keccak256("DeployV1VaultsChaosTestnetScript__ScaledAmountOverflow(address,uint256,uint256)"));
    bytes4 internal constant INVALID_VAULT_COUNT =
        bytes4(keccak256("DeployV1VaultsChaosTestnetScript__InvalidVaultCount(uint256)"));
    bytes4 internal constant DUPLICATE_VAULT =
        bytes4(keccak256("DeployV1VaultsChaosTestnetScript__DuplicateVault(address)"));
    bytes4 internal constant INVALID_DELAYED_VAULT =
        bytes4(keccak256("DeployV1VaultsChaosTestnetScript__InvalidDelayedVault(uint256)"));
    bytes4 internal constant UNSUPPORTED_CHAIN =
        bytes4(keccak256("DeployV1VaultsChaosTestnetScript__UnsupportedChain(uint256)"));
    bytes4 internal constant INVALID_CORE_DEPENDENCY =
        bytes4(keccak256("DeployV1VaultsChaosTestnetScript__InvalidCoreDependency(address)"));

    DeployV1VaultsChaosTestnetScriptHarness internal planner;
    DeployCoreBaseScript.CoreDeploymentData internal core;
    DeployV1VaultsChaosTestnetScript.Assets internal assets;

    function setUp() public {
        DeployV1VaultsChaosCoreHarness coreHarness = new DeployV1VaultsChaosCoreHarness(address(this));
        core = coreHarness.run(address(this));
        planner = new DeployV1VaultsChaosTestnetScriptHarness();

        ChaosTestToken usdc = new ChaosTestToken("Chaos USDC", "cUSDC", 6);
        ChaosTestToken aUsd = new ChaosTestToken("Chaos AUSD", "cAUSD", 18);
        ChaosTestToken mFone = new ChaosTestToken("Chaos MFONE", "cMFONE", 18);
        ChaosTestToken mGlobal = new ChaosTestToken("Chaos MGLOBAL", "cMGLOBAL", 18);
        assets = DeployV1VaultsChaosTestnetScript.Assets({
            usdc: address(usdc), aUsd: address(aUsd), mFone: address(mFone), mGlobal: address(mGlobal)
        });

        usdc.mint(address(planner), 1e6);
        aUsd.mint(address(planner), 1e18);
        mFone.mint(address(planner), 1e18);
        mGlobal.mint(address(planner), 1e18);
    }

    function test_ChainDefaultsMatchLatestExerciseScript() public view {
        (
            DeployV1VaultsChaosTestnetScript.Core memory hoodiCore,
            DeployV1VaultsChaosTestnetScript.Assets memory hoodiAssets
        ) = planner.exposedHoodiDeployment();
        _assertCore(
            hoodiCore,
            address(0x87d9eB1fB660e23B784bf660414297446A769F72),
            address(0x231e9c011c9B7D4Db670c4048157c12827e609c9),
            address(0x7bD4b3B1Ffaa1D670FbF20968F88Df76D0674581),
            address(0xD71a1C85741A802cc6E734091585E4Ee9C3a284b),
            address(0x62960B7c821ECcDb753D2CD5B439454f6B933399),
            address(0x593871aA6f52076f932360359371c9D5a9C91ae2)
        );
        _assertAssets(
            hoodiAssets,
            address(0x7CBD6c85A278a7586E9D1cF737b5BF2433AE69DD),
            address(0x84345D59A3a8c9acc0704595E608bE38a714b4FA),
            address(0xB47e49F0e9beF4bB7d665B8385133825F7bCFbEd),
            address(0x931E73562091aBFC583273D0E3BCB28c43268778)
        );

        (
            DeployV1VaultsChaosTestnetScript.Core memory sepoliaCore,
            DeployV1VaultsChaosTestnetScript.Assets memory sepoliaAssets
        ) = planner.exposedSepoliaDeployment();
        _assertCore(
            sepoliaCore,
            address(0x159B008Da99a6b9D1444Cade586Db2Db039a6Bb5),
            address(0x563F39055db11b2a64D7b8C883F002968b5458B8),
            address(0xf4A8dA61336e9900A1975B2a1f9bA5f338Db68fF),
            address(0x5579DDc08A6754e2AAbAFcd6E77555391a7887E0),
            address(0xF1ab4e2536b59Df2A8D28474D4c6363Ee97142CF),
            address(0xEaD132d5A9670d4f6FF7f4B73b5ae09684603e81)
        );
        _assertAssets(
            sepoliaAssets,
            address(0x49F2Db28897860b065FfD5509BD8E75FA450fD91),
            address(0x062bcE0Ec64D8f5a5b7dCCb7bFA3eb11bE0AcaE0),
            address(0x0E338C168597971eC7B0E77278653B6ae76Bc6A7),
            address(0x0a1530B52d37Cc69faE82B9D91Add40653c96ED8)
        );
    }

    function test_ChainResolutionDefaultsOverridesAndUnsupportedHandling() public {
        (
            DeployV1VaultsChaosTestnetScript.Core memory hoodiCore,
            DeployV1VaultsChaosTestnetScript.Assets memory hoodiAssets
        ) = planner.exposedHoodiDeployment();
        hoodiCore.vaultConfigurator = address(0xA11CE);
        _setDeploymentOverrides(hoodiCore, hoodiAssets);
        vm.chainId(560_048);
        (
            DeployV1VaultsChaosTestnetScript.Core memory resolvedCore,
            DeployV1VaultsChaosTestnetScript.Assets memory resolvedAssets
        ) = planner.exposedLatestDeployment();
        _assertCore(
            resolvedCore,
            hoodiCore.vaultConfigurator,
            hoodiCore.networkRegistry,
            hoodiCore.networkMiddlewareService,
            hoodiCore.operatorRegistry,
            hoodiCore.operatorVaultOptInService,
            hoodiCore.operatorNetworkOptInService
        );
        _assertAssets(resolvedAssets, hoodiAssets.usdc, hoodiAssets.aUsd, hoodiAssets.mFone, hoodiAssets.mGlobal);

        DeployV1VaultsChaosTestnetScript.Core memory overrideCore = DeployV1VaultsChaosTestnetScript.Core({
            vaultConfigurator: address(0x1001),
            networkRegistry: address(0x1002),
            networkMiddlewareService: address(0x1003),
            operatorRegistry: address(0x1004),
            operatorVaultOptInService: address(0x1005),
            operatorNetworkOptInService: address(0x1006)
        });
        DeployV1VaultsChaosTestnetScript.Assets memory overrideAssets = DeployV1VaultsChaosTestnetScript.Assets({
            usdc: address(0x2001), aUsd: address(0x2002), mFone: address(0x2003), mGlobal: address(0)
        });
        uint256 unsupportedChainId = 313_371;
        _setDeploymentOverrides(overrideCore, overrideAssets);
        vm.chainId(unsupportedChainId);
        vm.expectRevert(abi.encodeWithSelector(UNSUPPORTED_CHAIN, unsupportedChainId));
        planner.exposedLatestDeployment();

        overrideAssets.mGlobal = address(0x2004);
        _setDeploymentOverrides(overrideCore, overrideAssets);
        (resolvedCore, resolvedAssets) = planner.exposedLatestDeployment();
        _assertCore(
            resolvedCore,
            overrideCore.vaultConfigurator,
            overrideCore.networkRegistry,
            overrideCore.networkMiddlewareService,
            overrideCore.operatorRegistry,
            overrideCore.operatorVaultOptInService,
            overrideCore.operatorNetworkOptInService
        );
        _assertAssets(
            resolvedAssets, overrideAssets.usdc, overrideAssets.aUsd, overrideAssets.mFone, overrideAssets.mGlobal
        );
    }

    function test_RunBaseRejectsMissingCodeBeforeDeployment() public {
        DeployV1VaultsChaosTestnetScript.RunParams memory params = _runParams();
        params.core.operatorRegistry = address(0xBAD);

        vm.expectRevert(abi.encodeWithSelector(MISSING_CODE, address(0xBAD)));
        planner.runBase(params);
    }

    function test_RunBaseRejectsMismatchedCoreDependencyBeforeDeployment() public {
        DeployV1VaultsChaosTestnetScript.RunParams memory params = _runParams();
        NetworkMiddlewareService mismatchedMiddleware = new NetworkMiddlewareService(address(0xBAD));
        params.core.networkMiddlewareService = address(mismatchedMiddleware);
        uint256 networkCount = core.networkRegistry.totalEntities();
        uint256 operatorCount = core.operatorRegistry.totalEntities();

        vm.expectRevert(abi.encodeWithSelector(INVALID_CORE_DEPENDENCY, address(mismatchedMiddleware)));
        planner.runBase(params);

        assertEq(core.networkRegistry.totalEntities(), networkCount);
        assertEq(core.operatorRegistry.totalEntities(), operatorCount);
    }

    function test_RunBaseRejectsMismatchedControllerBeforeDeployment() public {
        DeployV1VaultsChaosTestnetScript.RunParams memory params = _runParams();
        params.controller = address(this);
        uint256 networkCount = core.networkRegistry.totalEntities();
        uint256 operatorCount = core.operatorRegistry.totalEntities();

        vm.expectRevert(abi.encodeWithSelector(CONTROLLER_CALLER_MISMATCH, address(this), address(planner)));
        planner.runBase(params);

        assertEq(core.networkRegistry.totalEntities(), networkCount);
        assertEq(core.operatorRegistry.totalEntities(), operatorCount);
    }

    function test_RunBaseRejectsRevertingCollateralDecimalsBeforeDeployment() public {
        ChaosRevertingDecimalsToken token = new ChaosRevertingDecimalsToken();
        DeployV1VaultsChaosTestnetScript.RunParams memory params = _runParams();
        params.assets.usdc = address(token);

        vm.expectRevert(abi.encodeWithSelector(INVALID_ASSET_DECIMALS, address(token)));
        planner.runBase(params);
    }

    function test_RunBaseRejectsMalformedCollateralDecimalsBeforeDeployment() public {
        ChaosMalformedDecimalsToken token = new ChaosMalformedDecimalsToken();
        DeployV1VaultsChaosTestnetScript.RunParams memory params = _runParams();
        params.assets.usdc = address(token);

        vm.expectRevert(abi.encodeWithSelector(INVALID_ASSET_DECIMALS, address(token)));
        planner.runBase(params);
    }

    function test_RunBaseRejectsTooLargeCollateralDecimalsBeforeDeployment() public {
        ChaosTooManyDecimalsToken token = new ChaosTooManyDecimalsToken();
        DeployV1VaultsChaosTestnetScript.RunParams memory params = _runParams();
        params.assets.usdc = address(token);

        vm.expectRevert(abi.encodeWithSelector(ASSET_DECIMALS_TOO_LARGE, address(token), 78));
        planner.runBase(params);
    }

    function test_RunBaseRejectsScaledAmountOverflowBeforeDeployment() public {
        ChaosTestToken token = new ChaosTestToken("Chaos High Decimals", "cHIGH", 77);
        DeployV1VaultsChaosTestnetScript.RunParams memory params = _runParams();
        params.assets.usdc = address(token);
        uint256 networkCount = core.networkRegistry.totalEntities();
        uint256 operatorCount = core.operatorRegistry.totalEntities();

        DeployV1VaultsChaosTestnetScript.VaultPlan[] memory plans = planner.exposedPlans(params.assets, params.seed);
        uint256 firstDepositLimitUnits;
        for (uint256 i; i < plans.length; ++i) {
            if (plans[i].asset == address(token)) {
                firstDepositLimitUnits = plans[i].depositLimitUnits;
                break;
            }
        }
        assertGt(firstDepositLimitUnits, 0);

        vm.expectRevert(
            abi.encodeWithSelector(SCALED_AMOUNT_OVERFLOW, address(token), firstDepositLimitUnits, uint256(77))
        );
        planner.runBase(params);

        assertEq(core.networkRegistry.totalEntities(), networkCount);
        assertEq(core.operatorRegistry.totalEntities(), operatorCount);
    }

    function test_RequiredSetupDeploysAndConfiguresEveryVault() public {
        (address executor, DeployV1VaultsChaosTestnetScript.VaultRecord[] memory records) =
            planner.runSetupOnly(_runParams());

        assertNotEq(executor, address(0));
        assertEq(records.length, 12);

        uint256 resolverCount;
        for (uint256 i; i < records.length; ++i) {
            DeployV1VaultsChaosTestnetScript.VaultRecord memory record = records[i];
            IVault vault = IVault(record.vault);
            bytes32 subnetwork = executor.subnetwork(record.subnetworkId);

            assertTrue(core.vaultFactory.isEntity(record.vault));
            assertTrue(core.delegatorFactory.isEntity(record.delegator));
            if (record.slasher == address(0)) {
                assertEq(uint8(record.slasherMode), uint8(DeployV1VaultsChaosTestnetScript.SlasherMode.None));
            } else {
                assertTrue(core.slasherFactory.isEntity(record.slasher));
            }

            assertEq(vault.collateral(), record.asset);
            assertEq(vault.delegator(), record.delegator);
            assertEq(vault.slasher(), record.slasher);
            assertEq(Ownable(record.vault).owner(), executor);
            assertTrue(IAccessControl(record.vault).hasRole(bytes32(0), executor));
            assertTrue(IRegistry(address(core.networkRegistry)).isEntity(executor));
            assertTrue(IRegistry(address(core.operatorRegistry)).isEntity(executor));
            assertEq(core.networkMiddlewareService.middleware(executor), executor);
            assertTrue(core.operatorNetworkOptInService.isOptedIn(executor, executor));
            assertTrue(core.operatorVaultOptInService.isOptedIn(executor, record.vault));
            assertGt(vault.activeBalanceOf(executor), 0);
            assertEq(record.claimEpoch, vault.currentEpoch() + 1);
            assertGt(vault.withdrawalsOf(record.claimEpoch, executor), 0);
            uint256[] memory persistedEpochs = V1ChaosExecutor(executor).claimEpochs(record.vault);
            assertEq(persistedEpochs.length, 1);
            assertEq(persistedEpochs[0], record.claimEpoch);
            assertGt(IBaseDelegator(record.delegator).maxNetworkLimit(subnetwork), 0);

            if (record.delegatorType == 0) {
                assertGt(INetworkRestakeDelegator(record.delegator).networkLimit(subnetwork), 0);
                assertGt(INetworkRestakeDelegator(record.delegator).operatorNetworkShares(subnetwork, executor), 0);
            } else if (record.delegatorType == 1) {
                assertGt(IFullRestakeDelegator(record.delegator).networkLimit(subnetwork), 0);
                assertGt(IFullRestakeDelegator(record.delegator).operatorNetworkLimit(subnetwork, executor), 0);
            } else if (record.delegatorType == 2) {
                assertEq(IOperatorSpecificDelegator(record.delegator).operator(), executor);
                assertGt(IOperatorSpecificDelegator(record.delegator).networkLimit(subnetwork), 0);
            } else {
                assertEq(IOperatorNetworkSpecificDelegator(record.delegator).network(), executor);
                assertEq(IOperatorNetworkSpecificDelegator(record.delegator).operator(), executor);
            }

            if (record.slasherMode == DeployV1VaultsChaosTestnetScript.SlasherMode.Veto && record.vetoWithResolver) {
                assertEq(IVetoSlasher(record.slasher).resolver(subnetwork, ""), executor);
                ++resolverCount;
            } else if (record.slasherMode == DeployV1VaultsChaosTestnetScript.SlasherMode.Veto) {
                assertEq(IVetoSlasher(record.slasher).resolver(subnetwork, ""), address(0));
            }
        }
        assertEq(resolverCount, 2);
    }

    function test_RunBaseExecutesEveryImmediateDeckAndReturnsConsistentCounters() public {
        DeployV1VaultsChaosTestnetScript.RunParams memory params = _runParams();
        DeployV1VaultsChaosTestnetScript.VaultPlan[] memory plans = planner.exposedPlans(params.assets, params.seed);
        uint256 expectedAttempts;
        for (uint256 i; i < plans.length; ++i) {
            expectedAttempts += planner.exposedActionDeck(plans[i], params.seed).length;
        }

        vm.recordLogs();
        DeployV1VaultsChaosTestnetScript.RunResult memory result = planner.runBase(params);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertNotEq(result.executor, address(0));
        assertEq(result.vaults.length, 12);
        assertNotEq(result.configurationDigest, bytes32(0));
        assertNotEq(result.actionPlanDigest, bytes32(0));
        assertEq(result.counters.total, result.counters.success + result.counters.failure);
        assertEq(result.counters.total, expectedAttempts);
        assertEq(V1ChaosExecutor(result.executor).totalAttempts(), result.counters.total);
        assertEq(V1ChaosExecutor(result.executor).totalSuccesses(), result.counters.success);
        assertEq(V1ChaosExecutor(result.executor).totalFailures(), result.counters.failure);

        uint256[12] memory deposits;
        uint256[12] memory withdrawals;
        uint256[12] memory redeems;
        uint256 actionEvents;
        bool sawConflictingFailure;
        bool sawLaterSuccess;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter != result.executor || logs[i].topics.length != 4
                    || logs[i].topics[0] != V1_CHAOS_ACTION_EVENT
            ) {
                continue;
            }

            ++actionEvents;
            uint256 vaultIndex = uint256(logs[i].topics[2]);
            (uint8 action, bool success) = _actionAndSuccess(logs[i]);
            assertLt(vaultIndex, 12);
            if (action == uint8(DeployV1VaultsChaosTestnetScript.Action.Deposit)) {
                ++deposits[vaultIndex];
            } else if (action == uint8(DeployV1VaultsChaosTestnetScript.Action.Withdraw)) {
                ++withdrawals[vaultIndex];
            } else if (action == uint8(DeployV1VaultsChaosTestnetScript.Action.Redeem)) {
                ++redeems[vaultIndex];
            }

            if (
                !success
                    && (action == uint8(DeployV1VaultsChaosTestnetScript.Action.OptOutVault)
                        || action == uint8(DeployV1VaultsChaosTestnetScript.Action.OptOutNetwork)
                        || action == uint8(DeployV1VaultsChaosTestnetScript.Action.SetMaxNetworkLimit))
            ) {
                sawConflictingFailure = true;
            } else if (sawConflictingFailure && success) {
                sawLaterSuccess = true;
            }
        }

        assertEq(actionEvents, result.counters.total);
        assertTrue(sawConflictingFailure);
        assertTrue(sawLaterSuccess);
        for (uint256 i; i < result.vaults.length; ++i) {
            assertEq(deposits[i], 3);
            assertEq(withdrawals[i], 3);
            assertEq(redeems[i], 3);
            assertTrue(core.operatorVaultOptInService.isOptedIn(result.executor, result.vaults[i].vault));
            assertTrue(core.operatorNetworkOptInService.isOptedIn(result.executor, result.executor));
            assertEq(IBaseDelegator(result.vaults[i].delegator).hook(), address(0));
        }
    }

    function test_RunDelayedBaseExecutesSlashingBranchesAndClaimsMaturedWithdrawals() public {
        DeployV1VaultsChaosTestnetScript.RunResult memory initial = planner.runBase(_runParams());
        vm.warp(block.timestamp + planner.DELAY_SECONDS());

        vm.recordLogs();
        DeployV1VaultsChaosTestnetScript.RunResult memory delayed =
            planner.runDelayedBase(_delayedParams(initial.vaults));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(delayed.executor, initial.executor);
        assertEq(delayed.vaults.length, 12);
        assertEq(delayed.counters.total, delayed.counters.success + delayed.counters.failure);
        assertGt(delayed.counters.total, 0);

        uint256[33] memory attempts;
        uint256[33] memory successes;
        uint256 actionEvents;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter != initial.executor || logs[i].topics.length != 4
                    || logs[i].topics[0] != V1_CHAOS_ACTION_EVENT
            ) {
                continue;
            }
            ++actionEvents;
            assertEq(logs[i].topics[3], bytes32(uint256(1)));
            (uint8 action, bool success) = _actionAndSuccess(logs[i]);
            ++attempts[action];
            if (success) {
                ++successes[action];
            }
        }
        assertEq(actionEvents, delayed.counters.total);
        assertEq(initial.counters.total + delayed.counters.total, V1ChaosExecutor(initial.executor).totalAttempts());
        assertEq(
            initial.counters.success + delayed.counters.success, V1ChaosExecutor(initial.executor).totalSuccesses()
        );
        assertEq(initial.counters.failure + delayed.counters.failure, V1ChaosExecutor(initial.executor).totalFailures());

        assertEq(attempts[uint8(DeployV1VaultsChaosTestnetScript.Action.Slash)], 4);
        assertEq(attempts[uint8(DeployV1VaultsChaosTestnetScript.Action.RequestSlash)], 4);
        assertEq(attempts[uint8(DeployV1VaultsChaosTestnetScript.Action.VetoSlash)], 2);
        assertEq(attempts[uint8(DeployV1VaultsChaosTestnetScript.Action.ExecuteSlash)], 2);
        assertEq(attempts[uint8(DeployV1VaultsChaosTestnetScript.Action.Claim)], 12);
        assertEq(attempts[uint8(DeployV1VaultsChaosTestnetScript.Action.ClaimBatch)], 12);

        assertGe(successes[uint8(DeployV1VaultsChaosTestnetScript.Action.Slash)], 1);
        assertEq(successes[uint8(DeployV1VaultsChaosTestnetScript.Action.RequestSlash)], 4);
        assertEq(successes[uint8(DeployV1VaultsChaosTestnetScript.Action.VetoSlash)], 2);
        assertEq(successes[uint8(DeployV1VaultsChaosTestnetScript.Action.ExecuteSlash)], 2);
        assertGe(successes[uint8(DeployV1VaultsChaosTestnetScript.Action.Claim)], 1);
        assertGe(successes[uint8(DeployV1VaultsChaosTestnetScript.Action.ClaimBatch)], 1);
        _assertDelayedVaultState(initial.executor, delayed.vaults);
    }

    function test_DelayedPlanDigestIdentifiesCurrentDelayedFlow() public {
        DeployV1VaultsChaosTestnetScript.RunParams memory params = _runParams();
        DeployV1VaultsChaosTestnetScript.RunResult memory initial = planner.runBase(params);
        vm.warp(block.timestamp + planner.DELAY_SECONDS());

        DeployV1VaultsChaosTestnetScript.DelayedRunParams memory delayedParams = _delayedParams(initial.vaults);
        bytes32 digestBefore = planner.exposedDelayedActionPlanDigest(delayedParams);
        bytes32 digestRepeated = planner.exposedDelayedActionPlanDigest(delayedParams);
        bytes32 immediateRoundOne =
            planner.exposedActionPlanDigest(planner.exposedPlans(params.assets, params.seed), params.seed, 1);

        assertNotEq(digestBefore, bytes32(0));
        assertEq(digestRepeated, digestBefore);
        assertNotEq(digestBefore, immediateRoundOne);

        DeployV1VaultsChaosTestnetScript.RunResult memory delayed = planner.runDelayedBase(delayedParams);
        assertEq(delayed.actionPlanDigest, digestBefore);
        assertNotEq(planner.exposedDelayedActionPlanDigest(delayedParams), digestBefore);
    }

    function test_RunDelayedBaseRejectsWrongVaultCountBeforeExecution() public {
        DeployV1VaultsChaosTestnetScript.VaultRecord[] memory records =
            new DeployV1VaultsChaosTestnetScript.VaultRecord[](0);
        vm.expectRevert(abi.encodeWithSelector(INVALID_VAULT_COUNT, 0));
        planner.runDelayedBase(_delayedParams(records));
    }

    function test_RunDelayedBaseRejectsDuplicateVaultBeforeExecution() public {
        DeployV1VaultsChaosTestnetScript.RunResult memory initial = planner.runBase(_runParams());
        DeployV1VaultsChaosTestnetScript.DelayedRunParams memory params = _delayedParams(initial.vaults);
        params.vaults[1] = params.vaults[0];
        uint256 attemptsBefore = V1ChaosExecutor(initial.executor).totalAttempts();

        vm.expectRevert(abi.encodeWithSelector(DUPLICATE_VAULT, params.vaults[0]));
        planner.runDelayedBase(params);

        assertEq(V1ChaosExecutor(initial.executor).totalAttempts(), attemptsBefore);
    }

    function test_RunDelayedBaseRejectsMismatchedComponentMiddlewareBeforeExecution() public {
        DeployV1VaultsChaosTestnetScript.RunResult memory initial = planner.runBase(_runParams());
        NetworkMiddlewareService alternateMiddleware = new NetworkMiddlewareService(address(core.networkRegistry));
        vm.prank(initial.executor);
        alternateMiddleware.setMiddleware(initial.executor);

        DeployV1VaultsChaosTestnetScript.DelayedRunParams memory params = _delayedParams(initial.vaults);
        params.core.networkMiddlewareService = address(alternateMiddleware);
        uint256 attemptsBefore = V1ChaosExecutor(initial.executor).totalAttempts();

        vm.expectRevert(abi.encodeWithSelector(INVALID_DELAYED_VAULT, 4));
        planner.runDelayedBase(params);

        assertEq(V1ChaosExecutor(initial.executor).totalAttempts(), attemptsBefore);
    }

    function test_RunDelayedBaseRejectsMismatchedDelegatorOperatorRegistryBeforeExecution() public {
        DeployV1VaultsChaosTestnetScript.RunResult memory initial = planner.runBase(_runParams());
        OperatorRegistry alternateOperatorRegistry = new OperatorRegistry();
        vm.prank(initial.executor);
        alternateOperatorRegistry.registerOperator();
        vm.mockCall(
            address(core.operatorVaultOptInService),
            abi.encodeWithSelector(IOptInService.WHO_REGISTRY.selector),
            abi.encode(address(alternateOperatorRegistry))
        );
        vm.mockCall(
            address(core.operatorNetworkOptInService),
            abi.encodeWithSelector(IOptInService.WHO_REGISTRY.selector),
            abi.encode(address(alternateOperatorRegistry))
        );

        DeployV1VaultsChaosTestnetScript.DelayedRunParams memory params = _delayedParams(initial.vaults);
        params.core.operatorRegistry = address(alternateOperatorRegistry);
        uint256 attemptsBefore = V1ChaosExecutor(initial.executor).totalAttempts();

        vm.expectRevert(abi.encodeWithSelector(INVALID_DELAYED_VAULT, 2));
        planner.runDelayedBase(params);

        assertEq(V1ChaosExecutor(initial.executor).totalAttempts(), attemptsBefore);
    }

    function test_LowDecimalExitCapNeverRoundsAboveFivePercentAndPreservesStake() public {
        DeployV1VaultsChaosTestnetScript.Assets memory zeroDecimalAssets = DeployV1VaultsChaosTestnetScript.Assets({
            usdc: address(new ChaosTestToken("Zero USDC", "zUSDC", 0)),
            aUsd: address(new ChaosTestToken("Zero AUSD", "zAUSD", 0)),
            mFone: address(new ChaosTestToken("Zero MFONE", "zMFONE", 0)),
            mGlobal: address(new ChaosTestToken("Zero MGLOBAL", "zMGLOBAL", 0))
        });
        DeployV1VaultsChaosTestnetScript.RunParams memory params = _runParams();
        params.assets = zeroDecimalAssets;
        DeployV1VaultsChaosTestnetScript.VaultPlan[] memory plans = planner.exposedPlans(zeroDecimalAssets, params.seed);

        bool sawSubTwentyResidual;
        for (uint256 i; i < plans.length; ++i) {
            uint256 remaining = plans[i].baselineDepositUnits - plans[i].baselineWithdrawalUnits;
            if (remaining < 20) {
                sawSubTwentyResidual = true;
                assertEq(planner.exposedBoundedExitAmount(plans[i], 1), 0);
            }
        }
        assertTrue(sawSubTwentyResidual);

        DeployV1VaultsChaosTestnetScript.RunResult memory result = planner.runBase(params);
        for (uint256 i; i < result.vaults.length; ++i) {
            IVault vault = IVault(result.vaults[i].vault);
            assertGt(vault.activeBalanceOf(result.executor), 0);
            assertGt(vault.slashableBalanceOf(result.executor), 0);
        }
    }

    function test_PlanIsDeterministicForSameSeed() public {
        DeployV1VaultsChaosTestnetScript.VaultPlan[] memory first = planner.exposedPlans(assets, 0xC0A5);
        DeployV1VaultsChaosTestnetScript.VaultPlan[] memory second = planner.exposedPlans(assets, 0xC0A5);

        assertEq(planner.exposedConfigurationDigest(first), planner.exposedConfigurationDigest(second));
        assertEq(planner.exposedActionPlanDigest(first, 0xC0A5, 0), planner.exposedActionPlanDigest(second, 0xC0A5, 0));
    }

    function test_DifferentSeedsChangeConfigurationAndActionPlan() public {
        DeployV1VaultsChaosTestnetScript.VaultPlan[] memory first = planner.exposedPlans(assets, 1);
        DeployV1VaultsChaosTestnetScript.VaultPlan[] memory second = planner.exposedPlans(assets, 2);

        assertNotEq(planner.exposedConfigurationDigest(first), planner.exposedConfigurationDigest(second));
        assertNotEq(planner.exposedActionPlanDigest(first, 1, 0), planner.exposedActionPlanDigest(second, 2, 0));
    }

    function test_PlanContainsCompleteTwelveCellPairMatrix() public {
        DeployV1VaultsChaosTestnetScript.VaultPlan[] memory plans = planner.exposedPlans(assets, 0xC0A5);

        assertEq(plans.length, 12);
        for (uint256 i; i < plans.length; ++i) {
            assertEq(plans[i].delegatorType, i % 4);
            assertEq(uint8(plans[i].slasherMode), i / 4);
            assertEq(plans[i].vaultVersion, i % 2 == 0 ? VAULT_VERSION : VAULT_TOKENIZED_VERSION);
        }
    }

    function test_PlannedInitializationValuesAreValid() public {
        DeployV1VaultsChaosTestnetScript.VaultPlan[] memory plans = planner.exposedPlans(assets, 0xC0A5);

        _assertValidPlans(plans);
    }

    function test_EachDeckContainsEveryDeclaredCompatibleAction() public {
        DeployV1VaultsChaosTestnetScript.VaultPlan[] memory plans = planner.exposedPlans(assets, 0xC0A5);

        for (uint256 i; i < plans.length; ++i) {
            _assertActionCoverage(plans[i], 0xC0A5, 0);
        }
    }

    function test_ActionDeckIsDeterministicForSameRound() public {
        DeployV1VaultsChaosTestnetScript.VaultPlan memory plan = planner.exposedPlans(assets, 0xC0A5)[0];

        DeployV1VaultsChaosTestnetScript.PlannedAction[] memory first =
            planner.exposedActionDeckForRound(plan, 0xC0A5, 7);
        DeployV1VaultsChaosTestnetScript.PlannedAction[] memory second =
            planner.exposedActionDeckForRound(plan, 0xC0A5, 7);

        assertEq(keccak256(abi.encode(first)), keccak256(abi.encode(second)));
        _assertExactActionMultiset(plan, first);
        _assertExactActionMultiset(plan, second);
    }

    function test_TwoArgumentActionDeckUsesRoundZero() public {
        DeployV1VaultsChaosTestnetScript.VaultPlan memory plan = planner.exposedPlans(assets, 0xC0A5)[0];

        DeployV1VaultsChaosTestnetScript.PlannedAction[] memory required = planner.exposedActionDeck(plan, 0xC0A5);
        DeployV1VaultsChaosTestnetScript.PlannedAction[] memory explicit =
            planner.exposedActionDeckForRound(plan, 0xC0A5, 0);

        assertEq(keccak256(abi.encode(required)), keccak256(abi.encode(explicit)));
    }

    function test_DifferentRoundChangesOrderingAndPreservesExactMultiset() public {
        DeployV1VaultsChaosTestnetScript.VaultPlan memory plan = planner.exposedPlans(assets, 0xC0A5)[0];

        DeployV1VaultsChaosTestnetScript.PlannedAction[] memory first =
            planner.exposedActionDeckForRound(plan, 0xC0A5, 0);
        DeployV1VaultsChaosTestnetScript.PlannedAction[] memory second =
            planner.exposedActionDeckForRound(plan, 0xC0A5, 1);

        assertNotEq(keccak256(abi.encode(first)), keccak256(abi.encode(second)));
        _assertSamePlannedActionMultiset(first, second);
        _assertExactActionMultiset(plan, first);
        _assertExactActionMultiset(plan, second);
    }

    function test_ExecutorRequiredCallBubblesTargetRevert() public {
        V1ChaosExecutor executor = new V1ChaosExecutor(address(this));
        V1ChaosExecutorFailingTarget failing = new V1ChaosExecutorFailingTarget();

        vm.expectRevert(abi.encodeWithSelector(V1ChaosExecutorTestTarget__Reverted.selector, 17));
        executor.executeRequired(address(failing), abi.encodeCall(V1ChaosExecutorFailingTarget.run, ()));
    }

    function test_ExecutorRejectsNonController() public {
        V1ChaosExecutor executor = new V1ChaosExecutor(address(this));
        V1ChaosExecutorSuccessfulTarget target = new V1ChaosExecutorSuccessfulTarget();
        bytes memory data = abi.encodeCall(V1ChaosExecutorSuccessfulTarget.run, ());

        vm.startPrank(address(0xBAD));
        vm.expectRevert(NOT_CONTROLLER);
        executor.executeRequired(address(target), data);
        vm.expectRevert(NOT_CONTROLLER);
        executor.executeAttempt(
            1, 2, 3, uint8(DeployV1VaultsChaosTestnetScript.Action.Deposit), address(target), data, false
        );
        vm.expectRevert(NOT_CONTROLLER);
        executor.ensureOptIn(address(target), address(0xCAFE));
        vm.expectRevert(NOT_CONTROLLER);
        executor.ensureHookCleared(address(target));
        vm.expectRevert(NOT_CONTROLLER);
        executor.executeInstantSlash(1, 2, 3, address(target), bytes32(0), address(target), 1);
        vm.expectRevert(NOT_CONTROLLER);
        executor.executeVetoSlashSequence(1, 2, 3, address(target), bytes32(0), address(target), 1, false);
        vm.stopPrank();
    }

    function test_ExecutorRecordsFailureAndContinuesWithLaterSuccess() public {
        uint256 seed = 0xC0A5;
        uint256 vaultIndex = 4;
        uint256 round = 2;
        V1ChaosExecutor executor = new V1ChaosExecutor(address(this));
        V1ChaosExecutorFailingTarget failing = new V1ChaosExecutorFailingTarget();
        V1ChaosExecutorSuccessfulTarget successful = new V1ChaosExecutorSuccessfulTarget();
        bytes memory failingData = abi.encodeCall(V1ChaosExecutorFailingTarget.run, ());
        bytes memory successfulData = abi.encodeCall(V1ChaosExecutorSuccessfulTarget.run, ());

        vm.recordLogs();
        (bool failed, bytes memory failureResult) = executor.executeAttempt(
            seed,
            vaultIndex,
            round,
            uint8(DeployV1VaultsChaosTestnetScript.Action.Deposit),
            address(failing),
            failingData,
            false
        );
        (bool succeeded, bytes memory successResult) = executor.executeAttempt(
            seed,
            vaultIndex,
            round,
            uint8(DeployV1VaultsChaosTestnetScript.Action.Withdraw),
            address(successful),
            successfulData,
            false
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertFalse(failed);
        assertTrue(succeeded);
        assertEq(failureResult, abi.encodeWithSelector(V1ChaosExecutorTestTarget__Reverted.selector, 17));
        assertEq(successResult, bytes(""));
        assertEq(executor.totalAttempts(), 2);
        assertEq(executor.totalSuccesses(), 1);
        assertEq(executor.totalFailures(), 1);
        assertEq(successful.calls(), 1);

        assertEq(logs.length, 2);
        _assertExecutorActionLog(
            logs[0],
            address(executor),
            seed,
            vaultIndex,
            round,
            uint8(DeployV1VaultsChaosTestnetScript.Action.Deposit),
            address(failing),
            V1ChaosExecutorFailingTarget.run.selector,
            false,
            keccak256(failureResult)
        );
        _assertExecutorActionLog(
            logs[1],
            address(executor),
            seed,
            vaultIndex,
            round,
            uint8(DeployV1VaultsChaosTestnetScript.Action.Withdraw),
            address(successful),
            V1ChaosExecutorSuccessfulTarget.run.selector,
            true,
            keccak256(successResult)
        );
    }

    function testFuzz_PlanPreservesMatrixAndActionCoverage(uint256 seed) public {
        DeployV1VaultsChaosTestnetScript.VaultPlan[] memory plans = planner.exposedPlans(assets, seed);

        assertEq(plans.length, 12);
        for (uint256 i; i < plans.length; ++i) {
            assertEq(plans[i].delegatorType, i % 4);
            assertEq(uint8(plans[i].slasherMode), i / 4);
            assertEq(plans[i].vaultVersion, i % 2 == 0 ? VAULT_VERSION : VAULT_TOKENIZED_VERSION);
            _assertActionCoverage(plans[i], seed, 0);
        }
        _assertValidPlans(plans);
    }

    function _runParams() internal view returns (DeployV1VaultsChaosTestnetScript.RunParams memory) {
        return DeployV1VaultsChaosTestnetScript.RunParams({
            core: DeployV1VaultsChaosTestnetScript.Core({
                vaultConfigurator: address(core.vaultConfigurator),
                networkRegistry: address(core.networkRegistry),
                networkMiddlewareService: address(core.networkMiddlewareService),
                operatorRegistry: address(core.operatorRegistry),
                operatorVaultOptInService: address(core.operatorVaultOptInService),
                operatorNetworkOptInService: address(core.operatorNetworkOptInService)
            }),
            assets: assets,
            controller: address(planner),
            seed: 0xC0A5,
            broadcast: false
        });
    }

    function _delayedParams(DeployV1VaultsChaosTestnetScript.VaultRecord[] memory records)
        internal
        view
        returns (DeployV1VaultsChaosTestnetScript.DelayedRunParams memory params)
    {
        params.core = _runParams().core;
        params.controller = address(planner);
        params.seed = 0xC0A5;
        params.vaults = new address[](records.length);
        for (uint256 i; i < records.length; ++i) {
            params.vaults[i] = records[i].vault;
        }
    }

    function _assertDelayedVaultState(address executor, DeployV1VaultsChaosTestnetScript.VaultRecord[] memory records)
        internal
        view
    {
        uint256 instantCumulativeSlash;
        uint256 vetoedRequests;
        uint256 executedRequests;
        uint256 executedCumulativeSlash;
        bool sawClaimedPersistedEpoch;
        for (uint256 i; i < records.length; ++i) {
            DeployV1VaultsChaosTestnetScript.VaultRecord memory record = records[i];
            uint256[] memory claimEpochs = V1ChaosExecutor(executor).claimEpochs(record.vault);
            assertGt(claimEpochs.length, 0);
            assertLe(claimEpochs.length, 32);
            for (uint256 epochIndex; epochIndex < claimEpochs.length; ++epochIndex) {
                sawClaimedPersistedEpoch = sawClaimedPersistedEpoch
                    || IVault(record.vault).isWithdrawalsClaimed(claimEpochs[epochIndex], executor);
                for (uint256 previous; previous < epochIndex; ++previous) {
                    assertNotEq(claimEpochs[epochIndex], claimEpochs[previous]);
                }
            }

            bytes32 subnetwork = executor.subnetwork(record.subnetworkId);
            if (record.slasherMode == DeployV1VaultsChaosTestnetScript.SlasherMode.Instant) {
                instantCumulativeSlash += IBaseSlasher(record.slasher).cumulativeSlash(subnetwork, executor);
            } else if (record.slasherMode == DeployV1VaultsChaosTestnetScript.SlasherMode.Veto) {
                IVetoSlasher slasher = IVetoSlasher(record.slasher);
                assertEq(slasher.slashRequestsLength(), 1);
                (,,,,, bool completed) = slasher.slashRequests(0);
                assertTrue(completed);
                if (record.vetoWithResolver) {
                    ++vetoedRequests;
                } else {
                    ++executedRequests;
                    executedCumulativeSlash += IBaseSlasher(record.slasher).cumulativeSlash(subnetwork, executor);
                }
            }
        }
        assertGt(instantCumulativeSlash, 0);
        assertGt(executedCumulativeSlash, 0);
        assertEq(vetoedRequests, 2);
        assertEq(executedRequests, 2);
        assertTrue(sawClaimedPersistedEpoch);
    }

    function _assertValidPlans(DeployV1VaultsChaosTestnetScript.VaultPlan[] memory plans) internal view {
        uint256[4] memory assetCounts;
        uint256 resolverPlans;

        for (uint256 i; i < plans.length; ++i) {
            DeployV1VaultsChaosTestnetScript.VaultPlan memory plan = plans[i];
            assertEq(plan.index, i);
            assertLt(plan.assetIndex, 4);
            ++assetCounts[plan.assetIndex];
            assertEq(plan.asset, _assetAt(plan.assetIndex));
            assertGe(plan.epochDuration, 2);
            assertLe(plan.epochDuration, 8);
            assertNotEq(plan.subnetworkId, 0);
            assertGt(plan.baselineDepositUnits, 0);
            assertLt(plan.baselineWithdrawalUnits, plan.baselineDepositUnits);
            assertGe(plan.depositLimitUnits, 10 * plan.baselineDepositUnits);
            assertGt(plan.tokenizedSuffix, 0);

            for (uint256 j; j < i; ++j) {
                assertNotEq(plan.subnetworkId, plans[j].subnetworkId);
            }

            if (plan.slasherMode == DeployV1VaultsChaosTestnetScript.SlasherMode.Veto) {
                assertGe(plan.vetoDuration, 1);
                assertLt(plan.vetoDuration, plan.epochDuration);
                if (plan.vetoWithResolver) {
                    ++resolverPlans;
                }
            } else {
                assertEq(plan.vetoDuration, 0);
                assertFalse(plan.vetoWithResolver);
            }
        }

        for (uint256 i; i < assetCounts.length; ++i) {
            assertEq(assetCounts[i], 3);
        }
        assertEq(resolverPlans, 2);
    }

    function _assertActionCoverage(DeployV1VaultsChaosTestnetScript.VaultPlan memory plan, uint256 seed, uint256 round)
        internal
        view
    {
        DeployV1VaultsChaosTestnetScript.PlannedAction[] memory deck =
            planner.exposedActionDeckForRound(plan, seed, round);

        _assertExactActionMultiset(plan, deck);
        _assertToggleCoversBoth(deck, DeployV1VaultsChaosTestnetScript.Action.SetDepositWhitelist);
        _assertToggleCoversBoth(deck, DeployV1VaultsChaosTestnetScript.Action.SetDepositorWhitelistStatus);
        _assertToggleCoversBoth(deck, DeployV1VaultsChaosTestnetScript.Action.SetIsDepositLimit);
        _assertToggleCoversBoth(deck, DeployV1VaultsChaosTestnetScript.Action.SetHook);
        _assertDepositLimitValues(plan, deck);
        _assertBoundedActionValues(plan, deck);
        _assertOccurrencesAreContiguous(deck);
        _assertReadOnlyFlags(deck);
    }

    function _assertExactActionMultiset(
        DeployV1VaultsChaosTestnetScript.VaultPlan memory plan,
        DeployV1VaultsChaosTestnetScript.PlannedAction[] memory deck
    ) internal pure {
        uint256 actionCount = uint256(uint8(type(DeployV1VaultsChaosTestnetScript.Action).max)) + 1;
        uint256[] memory expected = new uint256[](actionCount);

        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.SetDepositWhitelist)] = 2;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.SetDepositorWhitelistStatus)] = 2;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.SetIsDepositLimit)] = 2;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.SetDepositLimit)] = 3;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.OptOutVault)] = 1;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.OptInVault)] = 1;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.IncreaseVaultOptInNonce)] = 1;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.OptOutNetwork)] = 1;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.OptInNetwork)] = 1;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.IncreaseNetworkOptInNonce)] = 1;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.SetHook)] = 2;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.SetMaxNetworkLimit)] = 2;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.SetNetworkLimit)] = plan.delegatorType < 3 ? 1 : 0;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.SetOperatorNetworkShares)] =
            plan.delegatorType == 0 ? 1 : 0;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.SetOperatorNetworkLimit)] =
            plan.delegatorType == 1 ? 1 : 0;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.Deposit)] = 3;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.Withdraw)] = 3;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.Redeem)] = 3;

        bool tokenized = plan.vaultVersion == VAULT_TOKENIZED_VERSION;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.ApproveShares)] = tokenized ? 1 : 0;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.TransferShares)] = tokenized ? 1 : 0;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.TransferFromShares)] = tokenized ? 1 : 0;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.SetResolver)] =
            plan.slasherMode == DeployV1VaultsChaosTestnetScript.SlasherMode.Veto && plan.vetoWithResolver ? 1 : 0;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.Claim)] = 0;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.ClaimBatch)] = 0;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.ReadVault)] = 1;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.ReadDelegator)] = 1;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.ReadVaultOptIn)] = 1;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.ReadNetworkOptIn)] = 1;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.ReadSlasher)] =
            plan.slasherMode == DeployV1VaultsChaosTestnetScript.SlasherMode.None ? 0 : 1;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.Slash)] = 0;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.RequestSlash)] = 0;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.VetoSlash)] = 0;
        expected[uint8(DeployV1VaultsChaosTestnetScript.Action.ExecuteSlash)] = 0;

        uint256 expectedLength;
        for (uint256 action; action < expected.length; ++action) {
            assertEq(_count(deck, DeployV1VaultsChaosTestnetScript.Action(action)), expected[action]);
            expectedLength += expected[action];
        }
        assertEq(deck.length, expectedLength);
    }

    function _assertSamePlannedActionMultiset(
        DeployV1VaultsChaosTestnetScript.PlannedAction[] memory first,
        DeployV1VaultsChaosTestnetScript.PlannedAction[] memory second
    ) internal pure {
        assertEq(first.length, second.length);
        bool[] memory matched = new bool[](second.length);

        for (uint256 i; i < first.length; ++i) {
            bool found;
            for (uint256 j; j < second.length; ++j) {
                if (!matched[j] && _samePlannedAction(first[i], second[j])) {
                    matched[j] = true;
                    found = true;
                    break;
                }
            }
            assertTrue(found);
        }
    }

    function _samePlannedAction(
        DeployV1VaultsChaosTestnetScript.PlannedAction memory first,
        DeployV1VaultsChaosTestnetScript.PlannedAction memory second
    ) internal pure returns (bool) {
        return first.action == second.action && first.occurrence == second.occurrence && first.value == second.value
            && first.readOnly == second.readOnly;
    }

    function _assertBoundedActionValues(
        DeployV1VaultsChaosTestnetScript.VaultPlan memory plan,
        DeployV1VaultsChaosTestnetScript.PlannedAction[] memory deck
    ) internal pure {
        for (uint256 i; i < deck.length; ++i) {
            DeployV1VaultsChaosTestnetScript.Action action = deck[i].action;
            if (action == DeployV1VaultsChaosTestnetScript.Action.Deposit) {
                assertGt(deck[i].value, 0);
                assertLe(deck[i].value, plan.baselineDepositUnits);
            } else if (
                action == DeployV1VaultsChaosTestnetScript.Action.Withdraw
                    || action == DeployV1VaultsChaosTestnetScript.Action.Redeem
            ) {
                assertGt(deck[i].value, 0);
                assertLe(deck[i].value, plan.baselineWithdrawalUnits);
            } else if (
                action == DeployV1VaultsChaosTestnetScript.Action.SetMaxNetworkLimit
                    || action == DeployV1VaultsChaosTestnetScript.Action.SetNetworkLimit
                    || action == DeployV1VaultsChaosTestnetScript.Action.SetOperatorNetworkShares
                    || action == DeployV1VaultsChaosTestnetScript.Action.SetOperatorNetworkLimit
            ) {
                assertGt(deck[i].value, 0);
                assertLe(deck[i].value, plan.depositLimitUnits);
            } else if (
                action == DeployV1VaultsChaosTestnetScript.Action.ApproveShares
                    || action == DeployV1VaultsChaosTestnetScript.Action.TransferShares
                    || action == DeployV1VaultsChaosTestnetScript.Action.TransferFromShares
            ) {
                assertGt(deck[i].value, 0);
                assertLe(deck[i].value, plan.baselineDepositUnits);
            }
        }
    }

    function _count(
        DeployV1VaultsChaosTestnetScript.PlannedAction[] memory deck,
        DeployV1VaultsChaosTestnetScript.Action action
    ) internal pure returns (uint256 count) {
        for (uint256 i; i < deck.length; ++i) {
            if (deck[i].action == action) {
                ++count;
            }
        }
    }

    function _assertOccurrencesAreContiguous(DeployV1VaultsChaosTestnetScript.PlannedAction[] memory deck)
        internal
        pure
    {
        for (uint256 action; action <= uint256(uint8(type(DeployV1VaultsChaosTestnetScript.Action).max)); ++action) {
            uint256 count = _count(deck, DeployV1VaultsChaosTestnetScript.Action(action));
            bool[] memory seen = new bool[](count);
            for (uint256 i; i < deck.length; ++i) {
                if (uint8(deck[i].action) == action) {
                    assertLt(deck[i].occurrence, count);
                    assertFalse(seen[deck[i].occurrence]);
                    seen[deck[i].occurrence] = true;
                }
            }
        }
    }

    function _assertToggleCoversBoth(
        DeployV1VaultsChaosTestnetScript.PlannedAction[] memory deck,
        DeployV1VaultsChaosTestnetScript.Action action
    ) internal pure {
        bool sawZero;
        bool sawOne;
        for (uint256 i; i < deck.length; ++i) {
            if (deck[i].action == action) {
                assertLe(deck[i].value, 1);
                sawZero = sawZero || deck[i].value == 0;
                sawOne = sawOne || deck[i].value == 1;
            }
        }
        assertTrue(sawZero);
        assertTrue(sawOne);
    }

    function _assertDepositLimitValues(
        DeployV1VaultsChaosTestnetScript.VaultPlan memory plan,
        DeployV1VaultsChaosTestnetScript.PlannedAction[] memory deck
    ) internal pure {
        uint256 unlimited;
        uint256 finite;
        for (uint256 i; i < deck.length; ++i) {
            if (deck[i].action == DeployV1VaultsChaosTestnetScript.Action.SetDepositLimit) {
                if (deck[i].value == 0) {
                    ++unlimited;
                } else {
                    ++finite;
                    assertGe(deck[i].value, plan.baselineDepositUnits);
                    assertLe(deck[i].value, plan.depositLimitUnits);
                }
            }
        }
        assertEq(unlimited, 1);
        assertEq(finite, 2);
    }

    function _assertReadOnlyFlags(DeployV1VaultsChaosTestnetScript.PlannedAction[] memory deck) internal pure {
        for (uint256 i; i < deck.length; ++i) {
            bool expected = deck[i].action == DeployV1VaultsChaosTestnetScript.Action.ReadVault
                || deck[i].action == DeployV1VaultsChaosTestnetScript.Action.ReadDelegator
                || deck[i].action == DeployV1VaultsChaosTestnetScript.Action.ReadVaultOptIn
                || deck[i].action == DeployV1VaultsChaosTestnetScript.Action.ReadNetworkOptIn
                || deck[i].action == DeployV1VaultsChaosTestnetScript.Action.ReadSlasher;
            assertEq(deck[i].readOnly, expected);
        }
    }

    function _assertExecutorActionLog(
        Vm.Log memory log,
        address emitter,
        uint256 seed,
        uint256 vaultIndex,
        uint256 round,
        uint8 expectedAction,
        address expectedTarget,
        bytes4 expectedSelector,
        bool expectedSuccess,
        bytes32 expectedResultHash
    ) internal pure {
        assertEq(log.emitter, emitter);
        assertEq(log.topics.length, 4);
        assertEq(log.topics[0], V1_CHAOS_ACTION_EVENT);
        assertEq(log.topics[1], bytes32(seed));
        assertEq(log.topics[2], bytes32(vaultIndex));
        assertEq(log.topics[3], bytes32(round));

        (uint8 action, address target, bytes4 selector, bool success, bytes32 resultHash) =
            abi.decode(log.data, (uint8, address, bytes4, bool, bytes32));
        assertEq(action, expectedAction);
        assertEq(target, expectedTarget);
        assertEq(selector, expectedSelector);
        assertEq(success, expectedSuccess);
        assertEq(resultHash, expectedResultHash);
    }

    function _actionAndSuccess(Vm.Log memory log) internal pure returns (uint8 action, bool success) {
        (action,,, success,) = abi.decode(log.data, (uint8, address, bytes4, bool, bytes32));
    }

    function _setDeploymentOverrides(
        DeployV1VaultsChaosTestnetScript.Core memory overrideCore,
        DeployV1VaultsChaosTestnetScript.Assets memory overrideAssets
    ) internal {
        vm.setEnv("TESTNET_V1_VAULT_CONFIGURATOR", vm.toString(overrideCore.vaultConfigurator));
        vm.setEnv("TESTNET_V1_NETWORK_REGISTRY", vm.toString(overrideCore.networkRegistry));
        vm.setEnv("TESTNET_V1_NETWORK_MIDDLEWARE_SERVICE", vm.toString(overrideCore.networkMiddlewareService));
        vm.setEnv("TESTNET_V1_OPERATOR_REGISTRY", vm.toString(overrideCore.operatorRegistry));
        vm.setEnv("TESTNET_V1_OPERATOR_VAULT_OPT_IN_SERVICE", vm.toString(overrideCore.operatorVaultOptInService));
        vm.setEnv("TESTNET_V1_OPERATOR_NETWORK_OPT_IN_SERVICE", vm.toString(overrideCore.operatorNetworkOptInService));
        vm.setEnv("TESTNET_V1_USDC", vm.toString(overrideAssets.usdc));
        vm.setEnv("TESTNET_V1_AUSD", vm.toString(overrideAssets.aUsd));
        vm.setEnv("TESTNET_V1_MFONE", vm.toString(overrideAssets.mFone));
        vm.setEnv("TESTNET_V1_MGLOBAL", vm.toString(overrideAssets.mGlobal));
    }

    function _assertCore(
        DeployV1VaultsChaosTestnetScript.Core memory actual,
        address vaultConfigurator,
        address networkRegistry,
        address networkMiddlewareService,
        address operatorRegistry,
        address operatorVaultOptInService,
        address operatorNetworkOptInService
    ) internal pure {
        assertEq(actual.vaultConfigurator, vaultConfigurator);
        assertEq(actual.networkRegistry, networkRegistry);
        assertEq(actual.networkMiddlewareService, networkMiddlewareService);
        assertEq(actual.operatorRegistry, operatorRegistry);
        assertEq(actual.operatorVaultOptInService, operatorVaultOptInService);
        assertEq(actual.operatorNetworkOptInService, operatorNetworkOptInService);
    }

    function _assertAssets(
        DeployV1VaultsChaosTestnetScript.Assets memory actual,
        address usdc,
        address aUsd,
        address mFone,
        address mGlobal
    ) internal pure {
        assertEq(actual.usdc, usdc);
        assertEq(actual.aUsd, aUsd);
        assertEq(actual.mFone, mFone);
        assertEq(actual.mGlobal, mGlobal);
    }

    function _assetAt(uint256 index) internal view returns (address) {
        if (index == 0) return assets.usdc;
        if (index == 1) return assets.aUsd;
        if (index == 2) return assets.mFone;
        return assets.mGlobal;
    }
}
