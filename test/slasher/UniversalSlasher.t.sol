// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test, stdError} from "forge-std/Test.sol";

import {VaultFactory} from "../../src/contracts/VaultFactory.sol";
import {DelegatorFactory} from "../../src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "../../src/contracts/SlasherFactory.sol";
import {NetworkRegistry} from "../../src/contracts/NetworkRegistry.sol";
import {OperatorRegistry} from "../../src/contracts/OperatorRegistry.sol";
import {VaultConfigurator} from "../../src/contracts/VaultConfigurator.sol";
import {NetworkMiddlewareService} from "../../src/contracts/service/NetworkMiddlewareService.sol";
import {OptInService} from "../../src/contracts/service/OptInService.sol";

import {VaultV2} from "../../src/contracts/vault/VaultV2.sol";
import {Vault as VaultV1} from "../../src/contracts/vault/Vault.sol";
import {VaultTokenized} from "../../src/contracts/vault/VaultTokenized.sol";
import {FullRestakeDelegator} from "../../src/contracts/delegator/FullRestakeDelegator.sol";
import {NetworkRestakeDelegator} from "../../src/contracts/delegator/NetworkRestakeDelegator.sol";
import {OperatorNetworkSpecificDelegator} from "../../src/contracts/delegator/OperatorNetworkSpecificDelegator.sol";
import {OperatorSpecificDelegator} from "../../src/contracts/delegator/OperatorSpecificDelegator.sol";
import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";
import {Slasher} from "../../src/contracts/slasher/Slasher.sol";
import {UniversalSlasher} from "../../src/contracts/slasher/UniversalSlasher.sol";
import {VetoSlasher} from "../../src/contracts/slasher/VetoSlasher.sol";
import {Subnetwork} from "../../src/contracts/libraries/Subnetwork.sol";
import {Checkpoints} from "../../src/contracts/libraries/CheckpointsV2.sol";

import {IBaseDelegator} from "../../src/interfaces/delegator/IBaseDelegator.sol";
import {INetworkRestakeDelegator} from "../../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IUniversalDelegator} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IBaseSlasher} from "../../src/interfaces/slasher/IBaseSlasher.sol";
import {ISlasher} from "../../src/interfaces/slasher/ISlasher.sol";
import {IUniversalSlasher, BURNER_GAS_LIMIT, BURNER_RESERVE} from "../../src/interfaces/slasher/IUniversalSlasher.sol";
import {IVetoSlasher} from "../../src/interfaces/slasher/IVetoSlasher.sol";
import {IEntity} from "../../src/interfaces/common/IEntity.sol";
import {IMigratableEntity} from "../../src/interfaces/common/IMigratableEntity.sol";
import {IVault} from "../../src/interfaces/vault/IVault.sol";
import {IVaultV2} from "../../src/interfaces/vault/IVaultV2.sol";
import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";

import {Token} from "../mocks/Token.sol";
import {MockRewards} from "../mocks/MockRewards.sol";

contract UniversalSlasherMigrationTest is Test {
    uint48 internal constant EPOCH_DURATION = 7 days;
    string internal constant VAULT_NAME = "Test";
    string internal constant VAULT_SYMBOL = "TEST";

    address internal owner;

    VaultFactory internal vaultFactory;
    DelegatorFactory internal delegatorFactory;
    SlasherFactory internal slasherFactory;
    NetworkRegistry internal networkRegistry;
    OperatorRegistry internal operatorRegistry;
    NetworkMiddlewareService internal networkMiddlewareService;
    OptInService internal operatorVaultOptInService;
    OptInService internal operatorNetworkOptInService;
    VaultConfigurator internal vaultConfigurator;
    MockRewards internal rewards;

    Token internal collateral;

    function setUp() public {
        owner = address(this);

        vaultFactory = new VaultFactory(owner);
        delegatorFactory = new DelegatorFactory(owner);
        slasherFactory = new SlasherFactory(owner);
        networkRegistry = new NetworkRegistry();
        operatorRegistry = new OperatorRegistry();
        networkMiddlewareService = new NetworkMiddlewareService(address(networkRegistry));
        operatorVaultOptInService =
            new OptInService(address(operatorRegistry), address(vaultFactory), "OperatorVaultOptInService");
        operatorNetworkOptInService =
            new OptInService(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService");
        rewards = new MockRewards();

        address vaultImplV1 =
            address(new VaultV1(address(delegatorFactory), address(slasherFactory), address(vaultFactory)));
        vaultFactory.whitelist(vaultImplV1);

        address vaultImplTokenized =
            address(new VaultTokenized(address(delegatorFactory), address(slasherFactory), address(vaultFactory)));
        vaultFactory.whitelist(vaultImplTokenized);

        address vaultImpl = address(
            new VaultV2(
                address(delegatorFactory), address(slasherFactory), address(vaultFactory), address(rewards), address(0)
            )
        );
        vaultFactory.whitelist(vaultImpl);

        address networkRestakeDelegatorImpl = address(
            new NetworkRestakeDelegator(
                address(networkRegistry),
                address(vaultFactory),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(delegatorFactory),
                delegatorFactory.totalTypes()
            )
        );
        delegatorFactory.whitelist(networkRestakeDelegatorImpl);

        address fullRestakeDelegatorImpl = address(
            new FullRestakeDelegator(
                address(networkRegistry),
                address(vaultFactory),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(delegatorFactory),
                delegatorFactory.totalTypes()
            )
        );
        delegatorFactory.whitelist(fullRestakeDelegatorImpl);

        address operatorSpecificDelegatorImpl = address(
            new OperatorSpecificDelegator(
                address(operatorRegistry),
                address(networkRegistry),
                address(vaultFactory),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(delegatorFactory),
                delegatorFactory.totalTypes()
            )
        );
        delegatorFactory.whitelist(operatorSpecificDelegatorImpl);

        address operatorNetworkSpecificDelegatorImpl = address(
            new OperatorNetworkSpecificDelegator(
                address(operatorRegistry),
                address(networkRegistry),
                address(vaultFactory),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(delegatorFactory),
                delegatorFactory.totalTypes()
            )
        );
        delegatorFactory.whitelist(operatorNetworkSpecificDelegatorImpl);

        address universalDelegatorImpl = address(
            new UniversalDelegator(
                address(networkRegistry),
                address(vaultFactory),
                address(delegatorFactory),
                delegatorFactory.totalTypes(),
                address(networkMiddlewareService)
            )
        );
        delegatorFactory.whitelist(universalDelegatorImpl);

        address slasherImpl = address(
            new Slasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(slasherFactory),
                slasherFactory.totalTypes()
            )
        );
        slasherFactory.whitelist(slasherImpl);

        address vetoSlasherImpl = address(
            new VetoSlasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(networkRegistry),
                address(slasherFactory),
                slasherFactory.totalTypes()
            )
        );
        slasherFactory.whitelist(vetoSlasherImpl);

        address universalSlasherImpl = address(
            new UniversalSlasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(networkRegistry),
                address(slasherFactory),
                slasherFactory.totalTypes()
            )
        );
        slasherFactory.whitelist(universalSlasherImpl);

        collateral = new Token("Token");
        vaultConfigurator =
            new VaultConfigurator(address(vaultFactory), address(delegatorFactory), address(slasherFactory));
    }

    function test_MigrateWithoutSlasher_DoesNotCreateNewSlasher() public {
        (IVaultV2 vault_,) = _createLegacyVault(false, 0, "");

        bytes memory migrateData = abi.encode(_buildMigrateParams());
        vaultFactory.migrate(address(vault_), vaultFactory.lastVersion(), migrateData);

        assertEq(IMigratableEntity(address(vault_)).version(), vaultFactory.lastVersion());
        assertEq(vault_.slasher(), address(0));
    }

    function test_MigrateFromSlasher_ToUniversalSlasher() public {
        bytes memory slasherParams =
            abi.encode(ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})}));
        (IVaultV2 vault_, address oldSlasher) = _createLegacyVault(true, 0, slasherParams);

        bytes memory migrateData = abi.encode(_buildMigrateParams());
        vaultFactory.migrate(address(vault_), vaultFactory.lastVersion(), migrateData);

        assertEq(IMigratableEntity(address(vault_)).version(), vaultFactory.lastVersion());
        address newSlasher = vault_.slasher();
        assertTrue(newSlasher != oldSlasher);
        assertEq(IEntity(newSlasher).TYPE(), slasherFactory.totalTypes() - 1);
        assertEq(IUniversalSlasher(newSlasher).slashRequestsLength(), 0);
    }

    function test_MigrateFromSlasher_ToUniversalSlasher_preservesBurnerHook() public {
        bytes memory slasherParams =
            abi.encode(ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: true})}));
        (IVaultV2 vault_,) = _createLegacyVault(true, 0, slasherParams);

        bytes memory migrateData = abi.encode(_buildMigrateParams());
        vaultFactory.migrate(address(vault_), vaultFactory.lastVersion(), migrateData);

        assertTrue(IUniversalSlasher(vault_.slasher()).isBurnerHook());
    }

    function test_MigrateFromVetoSlasher_ToUniversalSlasher() public {
        bytes memory slasherParams = abi.encode(
            IVetoSlasher.InitParams({
                baseParams: IBaseSlasher.BaseParams({isBurnerHook: false}), vetoDuration: 1, resolverSetEpochsDelay: 3
            })
        );
        (IVaultV2 vault_, address oldSlasher) = _createLegacyVault(true, 1, slasherParams);
        uint256 expectedSlashRequestsLength = IVetoSlasher(oldSlasher).slashRequestsLength();

        bytes memory migrateData = abi.encode(_buildMigrateParams());
        vaultFactory.migrate(address(vault_), vaultFactory.lastVersion(), migrateData);

        assertEq(IMigratableEntity(address(vault_)).version(), vaultFactory.lastVersion());
        address newSlasher = vault_.slasher();
        assertTrue(newSlasher != oldSlasher);
        assertEq(IEntity(newSlasher).TYPE(), slasherFactory.totalTypes() - 1);
        assertEq(IUniversalSlasher(newSlasher).slashRequestsLength(), expectedSlashRequestsLength);
    }

    function test_MigrateFromVetoSlasher_ToUniversalSlasher_preservesResolverSetDelay() public {
        uint48 resolverSetEpochsDelay = 4;
        bytes memory slasherParams = abi.encode(
            IVetoSlasher.InitParams({
                baseParams: IBaseSlasher.BaseParams({isBurnerHook: false}),
                vetoDuration: 1,
                resolverSetEpochsDelay: resolverSetEpochsDelay
            })
        );
        (IVaultV2 vault_,) = _createLegacyVault(true, 1, slasherParams);

        bytes memory migrateData = abi.encode(_buildMigrateParams());
        vaultFactory.migrate(address(vault_), vaultFactory.lastVersion(), migrateData);

        assertEq(IUniversalSlasher(vault_.slasher()).resolverSetDelay(), resolverSetEpochsDelay * EPOCH_DURATION);
    }

    function _createLegacyVault(bool withSlasher, uint64 slasherIndex, bytes memory slasherParams)
        internal
        returns (IVaultV2 vault_, address oldSlasher)
    {
        IVault.InitParams memory baseParams = IVault.InitParams({
            collateral: address(collateral),
            burner: address(0xdEaD),
            epochDuration: EPOCH_DURATION,
            depositWhitelist: false,
            isDepositLimit: false,
            depositLimit: 0,
            defaultAdminRoleHolder: owner,
            depositWhitelistSetRoleHolder: owner,
            depositorWhitelistRoleHolder: owner,
            isDepositLimitSetRoleHolder: owner,
            depositLimitSetRoleHolder: owner
        });

        (address vaultAddress,, address slasherAddress) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: 1,
                owner: owner,
                vaultParams: abi.encode(baseParams),
                delegatorIndex: 0,
                delegatorParams: _legacyDelegatorParams(),
                withSlasher: withSlasher,
                slasherIndex: slasherIndex,
                slasherParams: slasherParams
            })
        );

        return (IVaultV2(vaultAddress), slasherAddress);
    }

    function _legacyDelegatorParams() internal view returns (bytes memory) {
        IBaseDelegator.BaseParams memory baseParams =
            IBaseDelegator.BaseParams({defaultAdminRoleHolder: owner, hook: address(0), hookSetRoleHolder: address(0)});
        address[] memory roleHolders = new address[](1);
        roleHolders[0] = owner;

        return abi.encode(
            INetworkRestakeDelegator.InitParams({
                baseParams: baseParams,
                networkLimitSetRoleHolders: roleHolders,
                operatorNetworkSharesSetRoleHolders: roleHolders
            })
        );
    }

    function _buildMigrateParams() internal view returns (IVaultV2.MigrateParams memory) {
        uint48 vetoDuration = EPOCH_DURATION > 1 ? 1 : 0;
        IUniversalDelegator.InitParams memory delegatorParams = IUniversalDelegator.InitParams({
            defaultAdminRoleHolder: owner,
            hook: address(0),
            hookSetRoleHolder: owner,
            createSlotRoleHolder: owner,
            setSizeRoleHolder: owner,
            swapSlotsRoleHolder: owner,
            withdrawalBufferSize: type(uint128).max
        });
        IUniversalSlasher.InitParams memory slasherParams = IUniversalSlasher.InitParams({
            isBurnerHook: false, vetoDuration: vetoDuration, resolverSetDelay: EPOCH_DURATION * 3
        });
        return IVaultV2.MigrateParams({
            name: VAULT_NAME,
            symbol: VAULT_SYMBOL,
            delegatorParams: abi.encode(delegatorParams),
            slasherParams: abi.encode(slasherParams)
        });
    }
}

contract MockRegistry {
    mapping(address entity => bool isEntity_) internal _entities;

    function setEntity(address entity, bool isEntity_) external {
        _entities[entity] = isEntity_;
    }

    function isEntity(address entity) external view returns (bool) {
        return _entities[entity];
    }
}

contract MockNetworkMiddlewareService {
    mapping(address network => address middleware_) internal _middleware;

    function setMiddleware(address network, address middleware_) external {
        _middleware[network] = middleware_;
    }

    function middleware(address network) external view returns (address) {
        return _middleware[network];
    }
}

contract MockUniversalDelegator {
    uint256 public stakeForValue;
    uint256 public stakeAtValue;
    bool public isNoPlugins;
    bool public revertOnGetIsNoPlugins;

    bytes32 public lastSlashSubnetwork;
    address public lastSlashOperator;
    uint256 public lastSlashAmount;
    bytes public lastSlashData;
    uint256 public onSlashCalls;

    function setStakeForValue(uint256 value) external {
        stakeForValue = value;
    }

    function setStakeAtValue(uint256 value) external {
        stakeAtValue = value;
    }

    function setIsNoPlugins(bool value) external {
        isNoPlugins = value;
    }

    function setRevertOnGetIsNoPlugins(bool value) external {
        revertOnGetIsNoPlugins = value;
    }

    function stakeFor(bytes32, address, uint48) external view returns (uint256) {
        return stakeForValue;
    }

    function stakeAt(bytes32, address, uint48, bytes memory) external view returns (uint256) {
        return stakeAtValue;
    }

    function onSlash(bytes32 subnetwork, address operator, uint256 amount, bytes memory data) external {
        lastSlashSubnetwork = subnetwork;
        lastSlashOperator = operator;
        lastSlashAmount = amount;
        lastSlashData = data;
        ++onSlashCalls;
    }

    function getIsNoPlugins(bytes32) external view returns (bool) {
        if (revertOnGetIsNoPlugins) {
            revert("NOT_ASSIGNED");
        }
        return isNoPlugins;
    }
}

contract MockVaultV2ForSlasher {
    address public delegator;
    address public burner;
    uint48 public epochDuration;
    uint64 public version;
    address public slasher;

    bool public useInputOnSlashAmount = true;
    uint256 public fixedOnSlashAmount;
    uint256 public onSlashOwed;
    uint256 public syncOwedReturn;

    uint256 public onSlashCalls;
    uint256 public lastOnSlashAmount;
    bool public lastOnSlashWithPlugins;
    uint256 public lastSyncOwedAmount;

    function setDelegator(address value) external {
        delegator = value;
    }

    function setBurner(address value) external {
        burner = value;
    }

    function setEpochDuration(uint48 value) external {
        epochDuration = value;
    }

    function setVersion(uint64 value) external {
        version = value;
    }

    function setSlasher(address value) external {
        slasher = value;
    }

    function setOnSlashResult(bool useInputAmount, uint256 fixedAmount, uint256 owedAmount) external {
        useInputOnSlashAmount = useInputAmount;
        fixedOnSlashAmount = fixedAmount;
        onSlashOwed = owedAmount;
    }

    function setSyncOwedReturn(uint256 value) external {
        syncOwedReturn = value;
    }

    function onSlash(uint256 amount, bool withPlugins) external returns (uint256, uint256) {
        ++onSlashCalls;
        lastOnSlashAmount = amount;
        lastOnSlashWithPlugins = withPlugins;

        uint256 slashedAmount = useInputOnSlashAmount ? amount : fixedOnSlashAmount;
        return (slashedAmount, onSlashOwed);
    }

    function syncOwedSlash(uint256 amount) external returns (uint256) {
        lastSyncOwedAmount = amount;
        return syncOwedReturn;
    }
}

contract MockLegacySlasher {
    uint64 public type_;
    uint256 public slashRequestsLength_;
    uint48 public vetoDuration_;
    uint256 public resolverSetEpochsDelay_;
    bool public isBurnerHook_;
    address public resolverAt_;
    uint48 public latestSlashedCaptureTimestamp_;
    uint256 public cumulativeSlashAt_;
    uint256 public cumulativeSlash_;

    bytes32 public slashRequestSubnetwork_;
    address public slashRequestOperator_;
    uint256 public slashRequestAmount_;
    uint48 public slashRequestCaptureTimestamp_;
    uint48 public slashRequestVetoDeadline_;
    bool public slashRequestCompleted_;

    function setType(uint64 value) external {
        type_ = value;
    }

    function setSlashRequestsLength(uint256 value) external {
        slashRequestsLength_ = value;
    }

    function setVetoDuration(uint48 value) external {
        vetoDuration_ = value;
    }

    function setResolverSetEpochsDelay(uint256 value) external {
        resolverSetEpochsDelay_ = value;
    }

    function setIsBurnerHook(bool value) external {
        isBurnerHook_ = value;
    }

    function setResolverAt(address value) external {
        resolverAt_ = value;
    }

    function setLatestSlashedCaptureTimestamp(uint48 value) external {
        latestSlashedCaptureTimestamp_ = value;
    }

    function setCumulativeSlashAt(uint256 value) external {
        cumulativeSlashAt_ = value;
    }

    function setCumulativeSlash(uint256 value) external {
        cumulativeSlash_ = value;
    }

    function setSlashRequest(
        bytes32 subnetwork,
        address operator,
        uint256 amount,
        uint48 captureTimestamp,
        uint48 vetoDeadline,
        bool completed
    ) external {
        slashRequestSubnetwork_ = subnetwork;
        slashRequestOperator_ = operator;
        slashRequestAmount_ = amount;
        slashRequestCaptureTimestamp_ = captureTimestamp;
        slashRequestVetoDeadline_ = vetoDeadline;
        slashRequestCompleted_ = completed;
    }

    function TYPE() external view returns (uint64) {
        return type_;
    }

    function slashRequestsLength() external view returns (uint256) {
        return slashRequestsLength_;
    }

    function slashRequests(uint256)
        external
        view
        returns (
            bytes32 subnetwork,
            address operator,
            uint256 amount,
            uint48 captureTimestamp,
            uint48 vetoDeadline,
            bool completed
        )
    {
        return (
            slashRequestSubnetwork_,
            slashRequestOperator_,
            slashRequestAmount_,
            slashRequestCaptureTimestamp_,
            slashRequestVetoDeadline_,
            slashRequestCompleted_
        );
    }

    function resolverAt(bytes32, uint48, bytes memory) external view returns (address) {
        return resolverAt_;
    }

    function vetoDuration() external view returns (uint48) {
        return vetoDuration_;
    }

    function resolverSetEpochsDelay() external view returns (uint256) {
        return resolverSetEpochsDelay_;
    }

    function isBurnerHook() external view returns (bool) {
        return isBurnerHook_;
    }

    function latestSlashedCaptureTimestamp(bytes32, address) external view returns (uint48) {
        return latestSlashedCaptureTimestamp_;
    }

    function cumulativeSlashAt(bytes32, address, uint48, bytes memory) external view returns (uint256) {
        return cumulativeSlashAt_;
    }

    function cumulativeSlash(bytes32, address) external view returns (uint256) {
        return cumulativeSlash_;
    }
}

contract MockBurner {
    uint256 public calls;
    bytes32 public lastSubnetwork;
    address public lastOperator;
    uint256 public lastAmount;
    uint48 public lastCaptureTimestamp;

    function onSlash(bytes32 subnetwork, address operator, uint256 amount, uint48 captureTimestamp) external {
        ++calls;
        lastSubnetwork = subnetwork;
        lastOperator = operator;
        lastAmount = amount;
        lastCaptureTimestamp = captureTimestamp;
    }
}

contract UniversalSlasherCoverageHarness is UniversalSlasher {
    using Checkpoints for Checkpoints.Trace256;

    constructor(address vaultFactory, address middlewareService, address networkRegistry)
        UniversalSlasher(vaultFactory, middlewareService, networkRegistry, address(0xBEEF), 7)
    {}

    function harnessInitialize(bytes calldata data) external {
        _initialize(data);
    }

    function setVaultRaw(address vault_) external {
        vault = vault_;
    }

    function setOldSlasherRaw(address oldSlasher) external {
        __oldSlasher = oldSlasher;
    }

    function setMigrateTimestampRaw(uint48 migrateTimestamp) external {
        __migrateTimestamp = migrateTimestamp;
    }

    function setVetoDurationRaw(uint48 value) external {
        vetoDuration = value;
    }

    function setResolverSetDelayRaw(uint48 value) external {
        resolverSetDelay = value;
    }

    function setIsBurnerHookRaw(bool value) external {
        isBurnerHook = value;
    }

    function setResolverRaw(bytes32 subnetwork, address value) external {
        _resolver[subnetwork] = value;
    }

    function setPendingResolverDataRaw(bytes32 subnetwork, bytes32 value) external {
        pendingResolverData[subnetwork] = value;
    }

    function setOwedRaw(bytes32 subnetwork, address operator, uint256 value) external {
        owed[subnetwork][operator] = value;
    }

    function setLatestSlashedCaptureTimestampRaw(bytes32 subnetwork, address operator, uint48 value) external {
        __latestSlashedCaptureTimestamp[subnetwork][operator] = value;
    }

    function pushCumulativeSlashRaw(bytes32 subnetwork, address operator, uint48 timestamp, uint256 value) external {
        __cumulativeSlash[subnetwork][operator].push(timestamp, value);
    }

    function pushSlashRequestRaw(SlashRequest calldata request_) external {
        _slashRequests.push(request_);
    }

    function exposeLatestSlashedCaptureTimestamp(bytes32 subnetwork, address operator) external view returns (uint48) {
        return _latestSlashedCaptureTimestamp(subnetwork, operator);
    }

    function exposeCumulativeSlashAt(bytes32 subnetwork, address operator, uint48 timestamp)
        external
        view
        returns (uint256)
    {
        return _cumulativeSlashAt(subnetwork, operator, timestamp);
    }

    function exposeCumulativeSlash(bytes32 subnetwork, address operator) external view returns (uint256) {
        return _cumulativeSlash(subnetwork, operator);
    }

    function exposeBurnerOnSlash(bytes32 subnetwork, address operator, uint256 amount) external {
        _burnerOnSlash(subnetwork, operator, amount);
    }
}

contract UniversalSlasherRuntimeCoverageTest is Test {
    using Subnetwork for address;

    uint48 internal constant EPOCH_DURATION = 100;

    MockRegistry internal vaultFactoryRegistry;
    MockRegistry internal networkRegistry;
    MockNetworkMiddlewareService internal middlewareService;
    MockUniversalDelegator internal delegator;
    MockVaultV2ForSlasher internal vault;
    MockLegacySlasher internal legacySlasher;
    MockBurner internal burner;
    UniversalSlasherCoverageHarness internal slasher;

    address internal network;
    address internal middleware;
    address internal operator;
    address internal resolver1;
    address internal resolver2;
    bytes32 internal subnetwork;

    function setUp() public {
        vaultFactoryRegistry = new MockRegistry();
        networkRegistry = new MockRegistry();
        middlewareService = new MockNetworkMiddlewareService();
        delegator = new MockUniversalDelegator();
        vault = new MockVaultV2ForSlasher();
        legacySlasher = new MockLegacySlasher();
        burner = new MockBurner();
        slasher = new UniversalSlasherCoverageHarness(
            address(vaultFactoryRegistry), address(middlewareService), address(networkRegistry)
        );

        network = makeAddr("network");
        middleware = makeAddr("middleware");
        operator = makeAddr("operator");
        resolver1 = makeAddr("resolver-1");
        resolver2 = makeAddr("resolver-2");
        subnetwork = network.subnetwork(0);

        middlewareService.setMiddleware(network, middleware);
        networkRegistry.setEntity(network, true);

        vault.setDelegator(address(delegator));
        vault.setBurner(address(burner));
        vault.setEpochDuration(EPOCH_DURATION);
        vault.setVersion(3);
        vault.setOnSlashResult(true, 0, 0);
        vault.setSyncOwedReturn(0);
        slasher.setVaultRaw(address(vault));

        delegator.setStakeForValue(100);
        delegator.setStakeAtValue(100);

        slasher.setVetoDurationRaw(10);
        slasher.setResolverSetDelayRaw(20);
    }

    function test_initializeReverts_NotVault() public {
        IUniversalSlasher.InitParams memory params =
            IUniversalSlasher.InitParams({isBurnerHook: false, vetoDuration: 1, resolverSetDelay: EPOCH_DURATION + 1});

        vm.expectRevert(IUniversalSlasher.NotVault.selector);
        slasher.harnessInitialize(abi.encode(address(vault), abi.encode(params)));
    }

    function test_initializeReverts_OldVault() public {
        vaultFactoryRegistry.setEntity(address(vault), true);
        vault.setVersion(2);

        IUniversalSlasher.InitParams memory params =
            IUniversalSlasher.InitParams({isBurnerHook: false, vetoDuration: 1, resolverSetDelay: EPOCH_DURATION + 1});

        vm.expectRevert(IUniversalSlasher.OldVault.selector);
        slasher.harnessInitialize(abi.encode(address(vault), abi.encode(params)));
    }

    function test_initializeReverts_InvalidVetoDuration() public {
        vaultFactoryRegistry.setEntity(address(vault), true);

        IUniversalSlasher.InitParams memory params = IUniversalSlasher.InitParams({
            isBurnerHook: false, vetoDuration: EPOCH_DURATION, resolverSetDelay: EPOCH_DURATION + 1
        });

        vm.expectRevert(IUniversalSlasher.InvalidVetoDuration.selector);
        slasher.harnessInitialize(abi.encode(address(vault), abi.encode(params)));
    }

    function test_initializeReverts_InvalidResolverSetEpochsDelay() public {
        vaultFactoryRegistry.setEntity(address(vault), true);

        IUniversalSlasher.InitParams memory params =
            IUniversalSlasher.InitParams({isBurnerHook: false, vetoDuration: 1, resolverSetDelay: EPOCH_DURATION});

        vm.expectRevert(IUniversalSlasher.InvalidResolverSetEpochsDelay.selector);
        slasher.harnessInitialize(abi.encode(address(vault), abi.encode(params)));
    }

    function test_initializeReverts_ResolverSetDelayAboveMaxDuration() public {
        vaultFactoryRegistry.setEntity(address(vault), true);

        IUniversalSlasher.InitParams memory params =
            IUniversalSlasher.InitParams({isBurnerHook: false, vetoDuration: 1, resolverSetDelay: type(uint48).max});

        vm.expectRevert(IUniversalSlasher.InvalidResolverSetEpochsDelay.selector);
        slasher.harnessInitialize(abi.encode(address(vault), abi.encode(params)));
    }

    function test_initializeReverts_NoBurner() public {
        vaultFactoryRegistry.setEntity(address(vault), true);
        vault.setBurner(address(0));

        IUniversalSlasher.InitParams memory params =
            IUniversalSlasher.InitParams({isBurnerHook: true, vetoDuration: 1, resolverSetDelay: EPOCH_DURATION + 1});

        vm.expectRevert(IUniversalSlasher.NoBurner.selector);
        slasher.harnessInitialize(abi.encode(address(vault), abi.encode(params)));
    }

    function test_migrateReverts_WrongMigrate() public {
        vault.setVersion(4);

        vm.expectRevert(IUniversalSlasher.WrongMigrate.selector);
        slasher.migrate();
    }

    function test_migrateReverts_NotMigrating() public {
        vault.setVersion(3);
        legacySlasher.setType(slasher.TYPE());
        vault.setSlasher(address(legacySlasher));

        vm.expectRevert(IUniversalSlasher.NotMigrating.selector);
        slasher.migrate();
    }

    function test_resolver_switchesToPendingWhenDelayReached() public {
        slasher.setResolverRaw(subnetwork, resolver1);
        slasher.setPendingResolverDataRaw(
            subnetwork, bytes32((uint256(uint160(resolver2)) << 48) | (uint256(block.timestamp + 5)))
        );

        assertEq(slasher.resolver(subnetwork), resolver1);

        vm.warp(block.timestamp + 5);
        assertEq(slasher.resolver(subnetwork), resolver2);
    }

    function test_setResolverReverts_NotNetwork() public {
        networkRegistry.setEntity(network, false);

        vm.prank(network);
        vm.expectRevert(IUniversalSlasher.NotNetwork.selector);
        slasher.setResolver(0, resolver1);
    }

    function test_setResolver_setsDirectAndQueuesPending() public {
        vm.prank(network);
        slasher.setResolver(0, resolver1);
        assertEq(slasher.resolver(subnetwork), resolver1);

        vm.prank(network);
        slasher.setResolver(0, resolver2);
        assertEq(slasher.resolver(subnetwork), resolver1);

        vm.warp(block.timestamp + slasher.resolverSetDelay());
        vm.prank(network);
        slasher.setResolver(0, makeAddr("resolver-3"));

        assertEq(slasher.resolver(subnetwork), resolver2);
    }

    function test_requestSlashReverts_NotNetworkMiddleware() public {
        vm.prank(makeAddr("bad-middleware"));
        vm.expectRevert(IUniversalSlasher.NotNetworkMiddleware.selector);
        slasher.requestSlash(subnetwork, operator, 1, 0, "");
    }

    function test_requestSlashReverts_InsufficientSlash() public {
        delegator.setStakeForValue(0);

        vm.prank(middleware);
        vm.expectRevert(IUniversalSlasher.InsufficientSlash.selector);
        slasher.requestSlash(subnetwork, operator, 10, 0, "");
    }

    function test_requestSlash_setsResolverAndVetoDeadline() public {
        vm.prank(network);
        slasher.setResolver(0, resolver1);

        vm.prank(middleware);
        uint256 slashIndex = slasher.requestSlash(subnetwork, operator, 25, 0, "");

        IUniversalSlasher.SlashRequest memory request = slasher.slashRequests(slashIndex);
        assertEq(request.resolver, resolver1);
        assertEq(request.vetoDeadline, uint48(block.timestamp + slasher.vetoDuration()));
    }

    function test_slashableStake_oldPathInvalidTimestampsReturnZero() public {
        slasher.setOldSlasherRaw(address(legacySlasher));
        slasher.setMigrateTimestampRaw(200);
        slasher.setLatestSlashedCaptureTimestampRaw(subnetwork, operator, 50);
        vm.warp(120);

        assertEq(slasher.slashableStake(subnetwork, operator, 10, ""), 0);
        assertEq(slasher.slashableStake(subnetwork, operator, uint48(block.timestamp), ""), 0);
        assertEq(slasher.slashableStake(subnetwork, operator, 40, ""), 0);
    }

    function test_slashableStake_oldPathUsesStakeAtAndCumulativeFallbacks() public {
        slasher.setOldSlasherRaw(address(legacySlasher));
        slasher.setMigrateTimestampRaw(200);
        legacySlasher.setCumulativeSlash(25);
        legacySlasher.setCumulativeSlashAt(10);
        delegator.setStakeAtValue(100);
        vm.warp(120);

        assertEq(slasher.slashableStake(subnetwork, operator, 30, ""), 85);
    }

    function test_executeSlashReverts_VetoPeriodNotEnded() public {
        _pushRequest(10, uint48(block.timestamp - 1), uint48(block.timestamp + 1), resolver1, false);

        vm.prank(middleware);
        vm.expectRevert(IUniversalSlasher.VetoPeriodNotEnded.selector);
        slasher.executeSlash(0, "");
    }

    function test_executeSlashReverts_InsufficientSlashForStaleCaptureTimestamp() public {
        vm.warp(1000);
        _pushRequest(10, 1, 0, resolver1, false);

        vm.prank(middleware);
        vm.expectRevert(IUniversalSlasher.InsufficientSlash.selector);
        slasher.executeSlash(0, "");
    }

    function test_executeSlashReverts_Completed() public {
        _pushRequest(10, uint48(block.timestamp - 1), 0, resolver1, true);

        vm.prank(middleware);
        vm.expectRevert(IUniversalSlasher.SlashRequestCompleted.selector);
        slasher.executeSlash(0, "");
    }

    function test_executeSlashReverts_InsufficientSlash() public {
        delegator.setStakeForValue(0);
        _pushRequest(10, uint48(block.timestamp - 1), 0, resolver1, false);

        vm.prank(middleware);
        vm.expectRevert(IUniversalSlasher.InsufficientSlash.selector);
        slasher.executeSlash(0, "");
    }

    function test_executeSlash_legacyRequestUpdatesLegacyState() public {
        slasher.setOldSlasherRaw(address(legacySlasher));
        slasher.setMigrateTimestampRaw(100);
        delegator.setStakeAtValue(90);
        delegator.setRevertOnGetIsNoPlugins(true);
        legacySlasher.setCumulativeSlash(0);
        legacySlasher.setCumulativeSlashAt(0);
        vm.warp(120);
        _pushRequest(30, 90, 0, resolver1, false);

        vm.prank(middleware);
        slasher.executeSlash(0, "");

        assertEq(slasher.exposeLatestSlashedCaptureTimestamp(subnetwork, operator), 90);
        assertEq(slasher.exposeCumulativeSlash(subnetwork, operator), 30);
        assertEq(delegator.onSlashCalls(), 0);
        assertFalse(vault.lastOnSlashWithPlugins());
    }

    function test_executeSlash_postMigrateCallsDelegatorHook() public {
        slasher.setMigrateTimestampRaw(10);
        vm.warp(20);
        _pushRequest(40, 15, 0, resolver1, false);

        vm.prank(middleware);
        slasher.executeSlash(0, "0x1234");

        assertEq(delegator.onSlashCalls(), 1);
        assertEq(delegator.lastSlashSubnetwork(), subnetwork);
        assertEq(delegator.lastSlashOperator(), operator);
        assertEq(delegator.lastSlashAmount(), 40);
    }

    function test_executeSlash_tracksOwedAndSyncOwedSlash() public {
        vault.setOnSlashResult(true, 0, 7);
        _pushRequest(40, uint48(block.timestamp), 0, resolver1, false);

        vm.prank(middleware);
        slasher.executeSlash(0, "");
        assertEq(slasher.owed(subnetwork, operator), 7);

        vault.setSyncOwedReturn(5);
        uint256 synced = slasher.syncOwedSlash(subnetwork, operator);
        assertEq(synced, 5);
        assertEq(slasher.owed(subnetwork, operator), 2);
        assertEq(vault.lastSyncOwedAmount(), 7);
    }

    function test_vetoSlashReverts_NotExist() public {
        vm.expectRevert(stdError.indexOOBError);
        slasher.vetoSlash(0);
    }

    function test_vetoSlashReverts_NotResolver() public {
        _pushRequest(10, uint48(block.timestamp - 1), uint48(block.timestamp + 10), resolver1, false);

        vm.prank(resolver2);
        vm.expectRevert(IUniversalSlasher.NotResolver.selector);
        slasher.vetoSlash(0);
    }

    function test_vetoSlashReverts_VetoPeriodEnded() public {
        _pushRequest(10, uint48(block.timestamp - 1), uint48(block.timestamp), resolver1, false);

        vm.prank(resolver1);
        vm.expectRevert(IUniversalSlasher.VetoPeriodEnded.selector);
        slasher.vetoSlash(0);
    }

    function test_vetoSlashReverts_AlreadyCompleted() public {
        _pushRequest(10, uint48(block.timestamp - 1), uint48(block.timestamp + 10), resolver1, true);

        vm.prank(resolver1);
        vm.expectRevert(IUniversalSlasher.SlashRequestCompleted.selector);
        slasher.vetoSlash(0);
    }

    function test_vetoSlash_marksCompleted() public {
        _pushRequest(10, uint48(block.timestamp - 1), uint48(block.timestamp + 10), resolver1, false);

        vm.prank(resolver1);
        slasher.vetoSlash(0);

        assertTrue(slasher.slashRequests(0).completed);
    }

    function test_slashRequests_readsLegacyDataWhenAmountIsZero() public {
        slasher.setOldSlasherRaw(address(legacySlasher));
        legacySlasher.setSlashRequest(subnetwork, operator, 33, 11, 15, true);
        legacySlasher.setResolverAt(resolver1);

        _pushRequest(0, 0, 0, address(0), false);

        IUniversalSlasher.SlashRequest memory request = slasher.slashRequests(0);
        assertEq(request.subnetwork, subnetwork);
        assertEq(request.operator, operator);
        assertEq(request.amount, 33);
        assertEq(request.createdAt, 11);
        assertEq(request.vetoDeadline, 15);
        assertTrue(request.completed);
        assertEq(request.resolver, resolver1);
    }

    function test_latestSlashedCaptureTimestamp_usesStorageThenLegacy() public {
        slasher.setLatestSlashedCaptureTimestampRaw(subnetwork, operator, 7);
        assertEq(slasher.exposeLatestSlashedCaptureTimestamp(subnetwork, operator), 7);

        slasher.setLatestSlashedCaptureTimestampRaw(subnetwork, operator, 0);
        slasher.setOldSlasherRaw(address(legacySlasher));
        legacySlasher.setLatestSlashedCaptureTimestamp(9);
        assertEq(slasher.exposeLatestSlashedCaptureTimestamp(subnetwork, operator), 9);
    }

    function test_cumulativeSlash_helpersUseLegacyAndCheckpoints() public {
        slasher.setOldSlasherRaw(address(legacySlasher));
        slasher.setMigrateTimestampRaw(50);
        legacySlasher.setCumulativeSlashAt(5);
        legacySlasher.setCumulativeSlash(7);

        assertEq(slasher.exposeCumulativeSlashAt(subnetwork, operator, 40), 5);
        assertEq(slasher.exposeCumulativeSlash(subnetwork, operator), 7);

        slasher.pushCumulativeSlashRaw(subnetwork, operator, 60, 11);
        assertEq(slasher.exposeCumulativeSlashAt(subnetwork, operator, 60), 11);
        assertEq(slasher.exposeCumulativeSlash(subnetwork, operator), 11);
    }

    function test_burnerHookExecutesCall() public {
        slasher.setIsBurnerHookRaw(true);

        slasher.exposeBurnerOnSlash(subnetwork, operator, 17);

        assertEq(burner.calls(), 1);
        assertEq(burner.lastSubnetwork(), subnetwork);
        assertEq(burner.lastOperator(), operator);
        assertEq(burner.lastAmount(), 17);
    }

    function test_burnerHookRevertsOnLowGas() public {
        slasher.setIsBurnerHookRaw(true);

        uint256 gasToSend = BURNER_RESERVE + BURNER_GAS_LIMIT * 64 / 63 - 1;
        vm.expectRevert(IUniversalSlasher.InsufficientBurnerGas.selector);
        slasher.exposeBurnerOnSlash{gas: gasToSend}(subnetwork, operator, 1);
    }

    function _pushRequest(uint256 amount, uint48 createdAt, uint48 vetoDeadline, address resolver, bool completed)
        internal
    {
        slasher.pushSlashRequestRaw(
            IUniversalSlasher.SlashRequest({
                subnetwork: subnetwork,
                operator: operator,
                createdAt: createdAt,
                amount: amount,
                resolver: resolver,
                vetoDeadline: vetoDeadline,
                completed: completed
            })
        );
    }
}
