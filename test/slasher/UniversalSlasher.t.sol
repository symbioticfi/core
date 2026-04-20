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
import {VaultV2Migrate} from "../../src/contracts/vault/VaultV2Migrate.sol";
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
import {IVetoSlasher, VETO_SLASHER_TYPE} from "../../src/interfaces/slasher/IVetoSlasher.sol";
import {IEntity} from "../../src/interfaces/common/IEntity.sol";
import {IMigratableEntity} from "../../src/interfaces/common/IMigratableEntity.sol";
import {IVault} from "../../src/interfaces/vault/IVault.sol";
import {IVaultV2} from "../../src/interfaces/vault/IVaultV2.sol";
import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";

import {Token} from "../mocks/Token.sol";
import {MockRewards} from "../mocks/MockRewards.sol";
import {MockReentrantBurner} from "../mocks/ReentrantAttackMocks.sol";

contract UniversalSlasherMigrationTest is Test {
    using Subnetwork for address;

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

        address vaultV2Migrate = address(
            new VaultV2Migrate(
                address(delegatorFactory), address(slasherFactory), address(0), address(rewards), address(0)
            )
        );
        address vaultImpl = address(
            new VaultV2(
                address(delegatorFactory),
                address(slasherFactory),
                address(vaultFactory),
                address(0),
                address(rewards),
                address(0),
                vaultV2Migrate
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
        assertEq(IUniversalSlasher(newSlasher).migrateTimestamp(), uint48(block.timestamp));
        assertEq(IUniversalSlasher(newSlasher).oldSlasher(), oldSlasher);
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
        assertEq(IUniversalSlasher(newSlasher).migrateTimestamp(), uint48(block.timestamp));
        assertEq(IUniversalSlasher(newSlasher).oldSlasher(), oldSlasher);
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

    function test_MigrateFromVetoSlasher_ToUniversalSlasher_usesLegacyResolverUntilNewResolverIsSet() public {
        uint48 resolverSetEpochsDelay = 4;
        bytes memory slasherParams = abi.encode(
            IVetoSlasher.InitParams({
                baseParams: IBaseSlasher.BaseParams({isBurnerHook: false}),
                vetoDuration: 1,
                resolverSetEpochsDelay: resolverSetEpochsDelay
            })
        );
        (IVaultV2 vault_, address oldSlasher) = _createLegacyVault(true, 1, slasherParams);

        address network = makeAddr("migration-network");
        address resolver_1 = makeAddr("migration-resolver-1");
        address resolver_2 = makeAddr("migration-resolver-2");
        bytes32 subnetwork_ = network.subnetwork(0);

        vm.startPrank(network);
        networkRegistry.registerNetwork();
        IVetoSlasher(oldSlasher).setResolver(0, resolver_1, "");
        vm.stopPrank();

        bytes memory migrateData = abi.encode(_buildMigrateParams());
        vaultFactory.migrate(address(vault_), vaultFactory.lastVersion(), migrateData);

        IUniversalSlasher newSlasher = IUniversalSlasher(vault_.slasher());
        assertFalse(newSlasher.isResolverSet(subnetwork_));
        assertEq(newSlasher.resolver(subnetwork_), resolver_1);

        vm.prank(network);
        newSlasher.setResolver(0, resolver_2);

        assertTrue(newSlasher.isResolverSet(subnetwork_));
        assertEq(newSlasher.resolver(subnetwork_), resolver_1);
        assertEq(
            newSlasher.pendingResolverData(subnetwork_),
            bytes32((uint256(uint160(resolver_2)) << 48) | (uint256(block.timestamp + newSlasher.resolverSetDelay())))
        );

        vm.warp(block.timestamp + newSlasher.resolverSetDelay() - 1);
        assertEq(newSlasher.resolver(subnetwork_), resolver_1);

        vm.warp(block.timestamp + 1);
        assertEq(newSlasher.resolver(subnetwork_), resolver_2);
    }

    function test_MigrateFromVetoSlasher_ToUniversalSlasher_withoutLegacyResolver_setsFirstResolverInstantly() public {
        uint48 resolverSetEpochsDelay = 4;
        bytes memory slasherParams = abi.encode(
            IVetoSlasher.InitParams({
                baseParams: IBaseSlasher.BaseParams({isBurnerHook: false}),
                vetoDuration: 1,
                resolverSetEpochsDelay: resolverSetEpochsDelay
            })
        );
        (IVaultV2 vault_,) = _createLegacyVault(true, 1, slasherParams);

        address network = makeAddr("migration-network-no-legacy-resolver");
        address resolver_1 = makeAddr("migration-resolver-first");
        bytes32 subnetwork_ = network.subnetwork(0);

        vm.prank(network);
        networkRegistry.registerNetwork();

        bytes memory migrateData = abi.encode(_buildMigrateParams());
        vaultFactory.migrate(address(vault_), vaultFactory.lastVersion(), migrateData);

        IUniversalSlasher newSlasher = IUniversalSlasher(vault_.slasher());
        assertFalse(newSlasher.isResolverSet(subnetwork_));
        assertEq(newSlasher.resolver(subnetwork_), address(0));

        vm.prank(network);
        newSlasher.setResolver(0, resolver_1);

        assertTrue(newSlasher.isResolverSet(subnetwork_));
        assertEq(newSlasher.resolver(subnetwork_), resolver_1);
        assertEq(newSlasher.pendingResolverData(subnetwork_), bytes32(0));
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
            createSlotRoleHolder: owner,
            setSizeRoleHolder: owner,
            swapSlotsRoleHolder: owner,
            removeSlotRoleHolder: owner,
            setWithdrawalBufferSizeRoleHolder: owner,
            withdrawalBufferSize: type(uint128).max
        });
        IUniversalSlasher.InitParams memory slasherParams = IUniversalSlasher.InitParams({
            isBurnerHook: false, vetoDuration: vetoDuration, resolverSetDelay: EPOCH_DURATION * 3
        });
        return IVaultV2.MigrateParams({
            name: VAULT_NAME,
            symbol: VAULT_SYMBOL,
            defaultAdminRoleHolder: owner,
            setAdapterLimitRoleHolder: owner,
            swapAdaptersRoleHolder: owner,
            allocateAdapterRoleHolder: owner,
            deallocateAdapterRoleHolder: owner,
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
    bool public isNoAdapters;
    bool public revertOnGetIsNoAdapters;
    uint256 public onSlashReturnValue;
    bool public useExplicitOnSlashReturnValue;

    bytes32 public lastSlashSubnetwork;
    address public lastSlashOperator;
    uint256 public lastSlashAmount;
    uint256 public onSlashCalls;
    uint256 public lastLegacySlashAmount;
    uint256 public onSlashLegacyCalls;
    bytes32 public lastLegacySlashSubnetwork;
    address public lastLegacySlashOperator;

    function setStakeForValue(uint256 value) external {
        stakeForValue = value;
    }

    function setStakeAtValue(uint256 value) external {
        stakeAtValue = value;
    }

    function setOnSlashReturnValue(uint256 value) external {
        onSlashReturnValue = value;
        useExplicitOnSlashReturnValue = true;
    }

    function setIsNoAdapters(bool value) external {
        isNoAdapters = value;
    }

    function setRevertOnGetIsNoAdapters(bool value) external {
        revertOnGetIsNoAdapters = value;
    }

    function stakeFor(bytes32, address, uint48) external view returns (uint256) {
        return stakeForValue;
    }

    function stake(bytes32, address) external view returns (uint256) {
        return stakeForValue;
    }

    function stakeAt(bytes32, address, uint48, bytes memory) external view returns (uint256) {
        return stakeAtValue;
    }

    function onSlash(bytes32 subnetwork, address operator, uint256 amount) external returns (uint256) {
        lastSlashSubnetwork = subnetwork;
        lastSlashOperator = operator;
        lastSlashAmount = amount;
        ++onSlashCalls;
        return useExplicitOnSlashReturnValue ? onSlashReturnValue : amount;
    }

    function onSlashLegacy(bytes32 subnetwork, address operator, uint256 amount) external returns (uint256) {
        lastLegacySlashSubnetwork = subnetwork;
        lastLegacySlashOperator = operator;
        lastLegacySlashAmount = amount;
        ++onSlashLegacyCalls;
        return amount;
    }

    function getIsNoAdapters(bytes32) external view returns (bool) {
        if (revertOnGetIsNoAdapters) {
            revert("NOT_ASSIGNED");
        }
        return isNoAdapters;
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
    bool public lastOnSlashWithAdapters;
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

    function onSlash(uint256 amount, bool withAdapters) external returns (uint256, uint256) {
        ++onSlashCalls;
        lastOnSlashAmount = amount;
        lastOnSlashWithAdapters = withAdapters;

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
    uint48 public resolverSwitchTimestamp_;
    address public resolverAtBefore_;
    address public resolverAtAfter_;
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
        resolverSwitchTimestamp_ = 0;
        resolverAtBefore_ = value;
        resolverAtAfter_ = value;
    }

    function setResolverTimeline(uint48 switchTimestamp, address beforeValue, address afterValue) external {
        resolverSwitchTimestamp_ = switchTimestamp;
        resolverAtBefore_ = beforeValue;
        resolverAtAfter_ = afterValue;
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

    function resolverAt(bytes32, uint48 timestamp, bytes memory) external view returns (address) {
        return
            resolverSwitchTimestamp_ > 0 && timestamp >= resolverSwitchTimestamp_ ? resolverAtAfter_ : resolverAtBefore_;
    }

    function resolver(bytes32, bytes memory) external view returns (address) {
        return resolverSwitchTimestamp_ > 0 && block.timestamp >= resolverSwitchTimestamp_
            ? resolverAtAfter_
            : resolverAtBefore_;
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

    function setOldSlasherRaw(address oldSlasher_) external {
        oldSlasher = oldSlasher_;
    }

    function setMigrateTimestampRaw(uint48 migrateTimestamp_) external {
        migrateTimestamp = migrateTimestamp_;
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

    function setTotalOwedRaw(uint256 value) external {
        totalOwed = value;
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
    uint256 internal constant SUPPLY_CAP = (uint256(1) << 255) - 1;

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

    function test_migrateReverts_NotVault() public {
        vm.expectRevert(IUniversalSlasher.NotVault.selector);
        slasher.migrate(address(legacySlasher));
    }

    function test_migrateReverts_NotMigrating() public {
        legacySlasher.setType(slasher.TYPE());
        vm.prank(address(vault));
        vm.expectRevert(IUniversalSlasher.NotMigrating.selector);
        slasher.migrate(address(legacySlasher));
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

    function test_resolver_ignoresLegacyResolverWhenOldSlasherIsNotVeto() public {
        legacySlasher.setType(0);
        legacySlasher.setResolverAt(resolver1);
        slasher.setOldSlasherRaw(address(legacySlasher));
        slasher.setResolverRaw(subnetwork, resolver2);

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
        assertTrue(slasher.isResolverSet(subnetwork));
        assertEq(slasher.resolver(subnetwork), resolver1);
        assertEq(slasher.pendingResolverData(subnetwork), bytes32(0));

        vm.prank(network);
        slasher.setResolver(0, resolver2);
        assertEq(
            slasher.pendingResolverData(subnetwork),
            bytes32((uint256(uint160(resolver2)) << 48) | (uint256(block.timestamp + slasher.resolverSetDelay())))
        );
        assertEq(slasher.resolver(subnetwork), resolver1);

        vm.warp(block.timestamp + slasher.resolverSetDelay());
        vm.prank(network);
        slasher.setResolver(0, makeAddr("resolver-3"));

        assertEq(slasher.resolver(subnetwork), resolver2);
    }

    function test_setResolver_onMigratedVetoResolverQueuesFirstUpdateAndMarksLocalState() public {
        legacySlasher.setType(VETO_SLASHER_TYPE);
        legacySlasher.setResolverAt(resolver1);
        slasher.setOldSlasherRaw(address(legacySlasher));

        assertFalse(slasher.isResolverSet(subnetwork));
        assertEq(slasher.resolver(subnetwork), resolver1);

        vm.prank(network);
        slasher.setResolver(0, resolver2);

        assertTrue(slasher.isResolverSet(subnetwork));
        assertEq(slasher.resolver(subnetwork), resolver1);
        assertEq(
            slasher.pendingResolverData(subnetwork),
            bytes32((uint256(uint160(resolver2)) << 48) | (uint256(block.timestamp + slasher.resolverSetDelay())))
        );

        vm.warp(block.timestamp + slasher.resolverSetDelay());
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

    function test_slash_capsToCurrentSlashableStakeAndExecutesImmediately() public {
        vm.prank(middleware);
        uint256 slashedAmount = slasher.slash(subnetwork, operator, 150, 0, "");

        assertEq(slashedAmount, 100);
        assertEq(slasher.slashRequestsLength(), 1);

        IUniversalSlasher.SlashRequest memory request = slasher.slashRequests(0);
        assertEq(request.subnetwork, subnetwork);
        assertEq(request.operator, operator);
        assertEq(request.amount, 100);
        assertEq(request.createdAt, uint48(block.timestamp));
        assertEq(request.resolver, address(0));
        assertEq(request.vetoDeadline, uint48(block.timestamp));
        assertTrue(request.completed);

        assertEq(delegator.onSlashCalls(), 1);
        assertEq(delegator.lastSlashSubnetwork(), subnetwork);
        assertEq(delegator.lastSlashOperator(), operator);
        assertEq(delegator.lastSlashAmount(), 100);
        assertEq(vault.onSlashCalls(), 1);
        assertEq(vault.lastOnSlashAmount(), 100);
    }

    function test_slashReverts_InsufficientSlash() public {
        delegator.setStakeForValue(0);

        vm.prank(middleware);
        vm.expectRevert(IUniversalSlasher.InsufficientSlash.selector);
        slasher.slash(subnetwork, operator, 10, 0, "");

        assertEq(slasher.slashRequestsLength(), 0);
        assertEq(delegator.onSlashCalls(), 0);
        assertEq(vault.onSlashCalls(), 0);
    }

    function test_slashReverts_VetoPeriodNotEnded() public {
        vm.prank(network);
        slasher.setResolver(0, resolver1);

        vm.prank(middleware);
        vm.expectRevert(IUniversalSlasher.VetoPeriodNotEnded.selector);
        slasher.slash(subnetwork, operator, 10, 0, "");

        assertEq(slasher.slashRequestsLength(), 0);
        assertEq(delegator.onSlashCalls(), 0);
        assertEq(vault.onSlashCalls(), 0);
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

    function test_slashableStake_newPath_LastPossibleSecondBoundary() public {
        vm.warp(1000);

        assertEq(slasher.slashableStake(subnetwork, operator, uint48(block.timestamp - EPOCH_DURATION), ""), 0);
        assertEq(slasher.slashableStake(subnetwork, operator, uint48(block.timestamp - EPOCH_DURATION + 1), ""), 100);
    }

    function test_executeSlash_WithVetoDurationEpochMinusOne_LastPossibleSecondSucceeds() public {
        vm.warp(1000);
        slasher.setVetoDurationRaw(EPOCH_DURATION - 1);

        vm.prank(network);
        slasher.setResolver(0, resolver1);

        vm.prank(middleware);
        uint256 slashIndex = slasher.requestSlash(subnetwork, operator, 10, 0, "");
        IUniversalSlasher.SlashRequest memory request = slasher.slashRequests(slashIndex);
        assertEq(request.createdAt, uint48(1000));
        assertEq(request.vetoDeadline, uint48(1000 + EPOCH_DURATION - 1));

        vm.warp(request.vetoDeadline);
        vm.prank(middleware);
        assertEq(slasher.executeSlash(slashIndex, ""), 10);
    }

    function test_executeSlash_WithVetoDurationEpochMinusOne_OneSecondLateReverts() public {
        vm.warp(1000);
        slasher.setVetoDurationRaw(EPOCH_DURATION - 1);

        vm.prank(network);
        slasher.setResolver(0, resolver1);

        vm.prank(middleware);
        uint256 slashIndex = slasher.requestSlash(subnetwork, operator, 10, 0, "");
        IUniversalSlasher.SlashRequest memory request = slasher.slashRequests(slashIndex);

        vm.warp(uint256(request.vetoDeadline) + 1);
        vm.prank(middleware);
        vm.expectRevert(IUniversalSlasher.InsufficientSlash.selector);
        slasher.executeSlash(slashIndex, "");
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

    function test_executeSlashReverts_InsufficientSlashForStaleMigratedRequest() public {
        vm.warp(1000);
        slasher.setOldSlasherRaw(address(legacySlasher));
        slasher.setMigrateTimestampRaw(900);
        legacySlasher.setSlashRequestsLength(1);
        legacySlasher.setResolverAt(resolver1);
        legacySlasher.setSlashRequest(subnetwork, operator, 10, 800, 0, false);
        _pushRequest(0, 0, 0, address(0), false);

        vm.prank(middleware);
        vm.expectRevert(IUniversalSlasher.InsufficientSlash.selector);
        slasher.executeSlash(0, "");
    }

    function test_executeSlash_usesFreshRequestAfterMigrationAndReReadsAllocation() public {
        vm.warp(1000);
        slasher.setOldSlasherRaw(address(legacySlasher));
        slasher.setMigrateTimestampRaw(900);
        legacySlasher.setSlashRequest(subnetwork, operator, 999, 1, 2, true);

        delegator.setStakeForValue(100);

        vm.prank(middleware);
        uint256 slashIndex = slasher.requestSlash(subnetwork, operator, 80, 0, "");

        IUniversalSlasher.SlashRequest memory request = slasher.slashRequests(slashIndex);
        assertEq(request.amount, 80);
        assertEq(request.createdAt, 1000);
        assertEq(request.subnetwork, subnetwork);
        assertEq(request.operator, operator);

        delegator.setStakeForValue(30);

        vm.prank(middleware);
        uint256 slashedAmount = slasher.executeSlash(slashIndex, "");

        assertEq(slashedAmount, 30);
        assertEq(vault.lastOnSlashAmount(), 30);
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
        delegator.setRevertOnGetIsNoAdapters(true);
        legacySlasher.setCumulativeSlash(0);
        legacySlasher.setCumulativeSlashAt(0);
        vm.warp(120);
        _pushRequest(30, 90, 0, resolver1, false);

        vm.prank(middleware);
        assertEq(slasher.executeSlash(0, ""), 30);

        assertEq(slasher.exposeLatestSlashedCaptureTimestamp(subnetwork, operator), 90);
        assertEq(slasher.exposeCumulativeSlash(subnetwork, operator), 30);
        assertEq(delegator.onSlashCalls(), 0);
        assertEq(delegator.onSlashLegacyCalls(), 1);
        assertEq(delegator.lastLegacySlashSubnetwork(), subnetwork);
        assertEq(delegator.lastLegacySlashOperator(), operator);
        assertEq(delegator.lastLegacySlashAmount(), 30);
        assertFalse(vault.lastOnSlashWithAdapters());
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

    function test_executeSlash_postMigrateAdapterBackedPathPassesWithAdapters() public {
        slasher.setMigrateTimestampRaw(10);
        delegator.setIsNoAdapters(false);
        vm.warp(20);
        _pushRequest(40, 15, 0, resolver1, false);

        vm.prank(middleware);
        slasher.executeSlash(0, "");

        assertTrue(vault.lastOnSlashWithAdapters());
    }

    function test_executeSlash_postMigrateNoAdaptersFullyOwed_callsBurnerHookWithZeroAmount() public {
        slasher.setMigrateTimestampRaw(10);
        slasher.setIsBurnerHookRaw(true);
        delegator.setIsNoAdapters(true);
        vault.setOnSlashResult(true, 0, 40);
        vm.warp(20);
        _pushRequest(40, 15, 0, resolver1, false);

        vm.prank(middleware);
        uint256 slashedAmount = slasher.executeSlash(0, "");

        assertEq(slashedAmount, 40);
        assertFalse(vault.lastOnSlashWithAdapters());
        assertEq(slasher.totalOwed(), 40);
        assertEq(slasher.owed(subnetwork, operator), 40);
        assertEq(burner.calls(), 1);
        assertEq(burner.lastAmount(), 0);
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

    function test_executeSlash_tracksOwedAcrossMultipleEntries() public {
        address operator2 = makeAddr("operator-2");

        vm.prank(middleware);
        uint256 slashIndex1 = slasher.requestSlash(subnetwork, operator, 40, 0, "");

        vm.prank(middleware);
        uint256 slashIndex2 = slasher.requestSlash(subnetwork, operator2, 30, 0, "");

        vault.setOnSlashResult(true, 0, 7);
        vm.prank(middleware);
        assertEq(slasher.executeSlash(slashIndex1, ""), 40);

        vault.setOnSlashResult(true, 0, 11);
        vm.prank(middleware);
        assertEq(slasher.executeSlash(slashIndex2, ""), 30);

        assertEq(slasher.totalOwed(), 18);
        assertEq(slasher.owed(subnetwork, operator), 7);
        assertEq(slasher.owed(subnetwork, operator2), 11);

        vault.setSyncOwedReturn(7);
        assertEq(slasher.syncOwedSlash(subnetwork, operator), 7);
        assertEq(slasher.totalOwed(), 11);
        assertEq(slasher.owed(subnetwork, operator), 0);
        assertEq(slasher.owed(subnetwork, operator2), 11);
        assertEq(vault.lastSyncOwedAmount(), 7);

        vault.setSyncOwedReturn(11);
        assertEq(slasher.syncOwedSlash(subnetwork, operator2), 11);
        assertEq(slasher.totalOwed(), 0);
        assertEq(slasher.owed(subnetwork, operator2), 0);
        assertEq(vault.lastSyncOwedAmount(), 11);
    }

    function test_executeSlash_doesNotBookSharedGuaranteeGapAsOwed() public {
        delegator.setStakeForValue(10);
        delegator.setOnSlashReturnValue(0);
        _pushRequest(10, uint48(block.timestamp), 0, resolver1, false);

        vm.prank(middleware);
        assertEq(slasher.executeSlash(0, ""), 0);

        assertEq(delegator.onSlashCalls(), 1);
        assertEq(delegator.lastSlashAmount(), 10);
        assertEq(vault.lastOnSlashAmount(), 0);
        assertEq(slasher.owed(subnetwork, operator), 0);
    }

    function test_executeSlash_burnerReentrancy_executeSlashAttemptIsBlockedAndSwallowed() public {
        MockReentrantBurner reentrantBurner = new MockReentrantBurner();
        vault.setBurner(address(reentrantBurner));
        middlewareService.setMiddleware(network, address(reentrantBurner));
        slasher.setIsBurnerHookRaw(true);

        reentrantBurner.armReentry(address(slasher), abi.encodeCall(UniversalSlasher.executeSlash, (0, bytes(""))));
        _pushRequest(40, uint48(block.timestamp), 0, resolver1, false);

        vm.prank(address(reentrantBurner));
        uint256 slashedAmount = slasher.executeSlash(0, "");

        assertEq(slashedAmount, 40);
        assertEq(reentrantBurner.calls(), 1);
        assertEq(reentrantBurner.reentryCalls(), 1);
        assertFalse(reentrantBurner.lastCallSuccess());
        assertTrue(slasher.slashRequests(0).completed);
    }

    function test_executeSlash_burnerReentrancy_syncOwedSlashAttemptRollsBackUnderBurnerGasCap() public {
        MockReentrantBurner reentrantBurner = new MockReentrantBurner();
        vault.setBurner(address(reentrantBurner));
        slasher.setIsBurnerHookRaw(true);
        vault.setOnSlashResult(true, 0, 7);
        vault.setSyncOwedReturn(5);

        reentrantBurner.armReentry(
            address(slasher), abi.encodeCall(UniversalSlasher.syncOwedSlash, (subnetwork, operator))
        );
        _pushRequest(40, uint48(block.timestamp), 0, resolver1, false);

        vm.prank(middleware);
        uint256 slashedAmount = slasher.executeSlash(0, "");

        assertEq(slashedAmount, 40);
        assertEq(reentrantBurner.calls(), 1);
        assertEq(reentrantBurner.reentryCalls(), 1);
        assertFalse(reentrantBurner.lastCallSuccess());
        assertEq(vault.lastSyncOwedAmount(), 0);
        assertEq(slasher.owed(subnetwork, operator), 7);
        assertEq(slasher.totalOwed(), 7);
        assertTrue(slasher.slashRequests(0).completed);
    }

    function testFuzz_executeSlash_uncheckedBurnerSubtractionIsSafe(
        uint256 slashableStake,
        uint256 requestedAmount,
        uint256 delegatedSlashAmount,
        uint256 owedAmount
    ) public {
        slashableStake = bound(slashableStake, 1, SUPPLY_CAP);
        requestedAmount = bound(requestedAmount, 1, slashableStake);
        delegatedSlashAmount = bound(delegatedSlashAmount, 0, requestedAmount);
        owedAmount = bound(owedAmount, 0, delegatedSlashAmount);

        slasher.setIsBurnerHookRaw(true);
        delegator.setStakeForValue(slashableStake);
        delegator.setOnSlashReturnValue(delegatedSlashAmount);
        vault.setOnSlashResult(true, 0, owedAmount);
        _pushRequest(requestedAmount, uint48(block.timestamp), 0, resolver1, false);

        vm.prank(middleware);
        uint256 slashedAmount = slasher.executeSlash(0, "");

        assertEq(slashedAmount, delegatedSlashAmount);
        assertEq(vault.lastOnSlashAmount(), delegatedSlashAmount);
        assertEq(burner.lastAmount(), delegatedSlashAmount - owedAmount);
        assertEq(slasher.totalOwed(), owedAmount);
        assertEq(slasher.owed(subnetwork, operator), owedAmount);
    }

    function testFuzz_executeSlash_burnerReentrantSyncOwedSlashAttempt_rollsBackUnderBurnerGasCap(
        uint256 slashableStake,
        uint256 requestedAmount,
        uint256 delegatedSlashAmount,
        uint256 owedAmount,
        uint256 syncedAmount
    ) public {
        slashableStake = bound(slashableStake, 1, SUPPLY_CAP);
        requestedAmount = bound(requestedAmount, 1, slashableStake);
        delegatedSlashAmount = bound(delegatedSlashAmount, 1, requestedAmount);
        owedAmount = bound(owedAmount, 0, delegatedSlashAmount);
        syncedAmount = bound(syncedAmount, 0, owedAmount);

        MockReentrantBurner reentrantBurner = new MockReentrantBurner();
        vault.setBurner(address(reentrantBurner));
        slasher.setIsBurnerHookRaw(true);
        delegator.setStakeForValue(slashableStake);
        delegator.setOnSlashReturnValue(delegatedSlashAmount);
        vault.setOnSlashResult(true, 0, owedAmount);
        vault.setSyncOwedReturn(syncedAmount);

        reentrantBurner.armReentry(
            address(slasher), abi.encodeCall(UniversalSlasher.syncOwedSlash, (subnetwork, operator))
        );
        _pushRequest(requestedAmount, uint48(block.timestamp), 0, resolver1, false);

        vm.prank(middleware);
        uint256 slashedAmount = slasher.executeSlash(0, "");

        assertEq(slashedAmount, delegatedSlashAmount);
        assertEq(reentrantBurner.reentryCalls(), 1);

        if (reentrantBurner.lastCallSuccess()) {
            assertEq(reentrantBurner.calls(), 2);
            assertEq(vault.lastSyncOwedAmount(), owedAmount);
            assertEq(slasher.owed(subnetwork, operator), owedAmount - syncedAmount);
            assertEq(slasher.totalOwed(), owedAmount - syncedAmount);
        } else {
            assertEq(reentrantBurner.calls(), 1);
            assertEq(vault.lastSyncOwedAmount(), 0);
            assertEq(slasher.owed(subnetwork, operator), owedAmount);
            assertEq(slasher.totalOwed(), owedAmount);
        }
    }

    function testFuzz_syncOwedSlash_uncheckedSubtractionsAreSafe(
        uint256 curOwed,
        uint256 syncedAmount,
        uint256 totalOwedAmount
    ) public {
        curOwed = bound(curOwed, 0, SUPPLY_CAP);
        syncedAmount = bound(syncedAmount, 0, curOwed);
        totalOwedAmount = bound(totalOwedAmount, curOwed, SUPPLY_CAP);

        slasher.setIsBurnerHookRaw(true);
        slasher.setOwedRaw(subnetwork, operator, curOwed);
        slasher.setTotalOwedRaw(totalOwedAmount);
        vault.setSyncOwedReturn(syncedAmount);

        uint256 slashedAmount = slasher.syncOwedSlash(subnetwork, operator);

        assertEq(slashedAmount, syncedAmount);
        assertEq(vault.lastSyncOwedAmount(), curOwed);
        assertEq(slasher.owed(subnetwork, operator), curOwed - syncedAmount);
        assertEq(slasher.totalOwed(), totalOwedAmount - syncedAmount);
        assertEq(burner.lastAmount(), syncedAmount);
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

    function test_slashRequests_legacyKeepsCaptureResolverWhenCurrentResolverChanges() public {
        vm.warp(20);
        slasher.setOldSlasherRaw(address(legacySlasher));
        legacySlasher.setSlashRequest(subnetwork, operator, 33, 11, 15, true);
        legacySlasher.setResolverTimeline(12, resolver1, resolver2);

        _pushRequest(0, 0, 0, address(0), false);

        IUniversalSlasher.SlashRequest memory request = slasher.slashRequests(0);
        assertEq(request.resolver, resolver1);
    }

    function test_slashRequests_legacyClearsResolverWhenCurrentResolverRemoved() public {
        vm.warp(20);
        slasher.setOldSlasherRaw(address(legacySlasher));
        legacySlasher.setSlashRequest(subnetwork, operator, 33, 11, 15, true);
        legacySlasher.setResolverTimeline(12, resolver1, address(0));

        _pushRequest(0, 0, 0, address(0), false);

        IUniversalSlasher.SlashRequest memory request = slasher.slashRequests(0);
        assertEq(request.resolver, address(0));
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
