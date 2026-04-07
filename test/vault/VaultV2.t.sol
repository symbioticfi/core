// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test, stdError} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {VaultFactory} from "../../src/contracts/VaultFactory.sol";
import {DelegatorFactory} from "../../src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "../../src/contracts/SlasherFactory.sol";
import {NetworkRegistry} from "../../src/contracts/NetworkRegistry.sol";
import {OperatorRegistry} from "../../src/contracts/OperatorRegistry.sol";
import {MetadataService} from "../../src/contracts/service/MetadataService.sol";
import {NetworkMiddlewareService} from "../../src/contracts/service/NetworkMiddlewareService.sol";
import {OptInService} from "../../src/contracts/service/OptInService.sol";
import {Checkpoints} from "../../src/contracts/libraries/Checkpoints.sol";
import {Checkpoints as CheckpointsV2Lib} from "../../src/contracts/libraries/CheckpointsV2.sol";

import {VaultV2} from "../../src/contracts/vault/VaultV2.sol";
import {Vault as VaultV1} from "../../src/contracts/vault/Vault.sol";
import {VaultTokenized} from "../../src/contracts/vault/VaultTokenized.sol";
import {NetworkRestakeDelegator} from "../../src/contracts/delegator/NetworkRestakeDelegator.sol";
import {FullRestakeDelegator} from "../../src/contracts/delegator/FullRestakeDelegator.sol";
import {OperatorSpecificDelegator} from "../../src/contracts/delegator/OperatorSpecificDelegator.sol";
import {OperatorNetworkSpecificDelegator} from "../../src/contracts/delegator/OperatorNetworkSpecificDelegator.sol";
import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";
import {Slasher} from "../../src/contracts/slasher/Slasher.sol";
import {VetoSlasher} from "../../src/contracts/slasher/VetoSlasher.sol";
import {UniversalSlasher} from "../../src/contracts/slasher/UniversalSlasher.sol";
import {AdapterRegistry} from "../../src/contracts/AdapterRegistry.sol";

import {IVault} from "../../src/interfaces/vault/IVault.sol";
import {IVaultTokenized} from "../../src/interfaces/vault/IVaultTokenized.sol";
import {
    IVaultV2,
    DEPOSIT_WHITELIST_SET_ROLE,
    DEPOSITOR_WHITELIST_ROLE,
    VAULT_V2_VERSION,
    IS_DEPOSIT_LIMIT_SET_ROLE,
    DEPOSIT_LIMIT_SET_ROLE,
    SET_ADAPTER_LIMIT_ROLE,
    SWAP_ADAPTERS_ROLE,
    ALLOCATE_ADAPTER_ROLE,
    DEALLOCATE_ADAPTER_ROLE,
    MAX_ADAPTERS,
    MAX_DURATION
} from "../../src/interfaces/vault/IVaultV2.sol";
import {MAX_FEE} from "../../src/interfaces/vault/IFeeRegistry.sol";
import {UNIVERSAL_DELEGATOR_TYPE} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IEntity} from "../../src/interfaces/common/IEntity.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {Token} from "../mocks/Token.sol";
import {FeeOnTransferToken} from "../mocks/FeeOnTransferToken.sol";
import {VaultConfigurator} from "../../src/contracts/VaultConfigurator.sol";
import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";
import {INetworkRestakeDelegator} from "../../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IFullRestakeDelegator} from "../../src/interfaces/delegator/IFullRestakeDelegator.sol";
import {IBaseDelegator} from "../../src/interfaces/delegator/IBaseDelegator.sol";
import {IUniversalDelegator} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {ISlasher} from "../../src/interfaces/slasher/ISlasher.sol";
import {IBaseSlasher} from "../../src/interfaces/slasher/IBaseSlasher.sol";
import {IVetoSlasher} from "../../src/interfaces/slasher/IVetoSlasher.sol";
import {IUniversalSlasher} from "../../src/interfaces/slasher/IUniversalSlasher.sol";
import {UNIVERSAL_SLASHER_TYPE} from "../../src/interfaces/slasher/IUniversalSlasher.sol";

import {IVaultStorage} from "../../src/interfaces/vault/IVaultStorage.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626Math} from "../../src/contracts/libraries/ERC4626Math.sol";

import {VaultHints} from "../../src/contracts/hints/VaultHints.sol";
import {Subnetwork} from "../../src/contracts/libraries/Subnetwork.sol";
import {UniversalDelegatorIndex} from "../../src/contracts/libraries/UniversalDelegatorIndex.sol";
import {VaultV2TestHelper} from "../helpers/VaultV2TestHelper.sol";
import {MockAdapter} from "../mocks/MockAdapter.sol";
import {MockMorphoAllocateAdapter} from "../mocks/MockMorphoAllocateAdapter.sol";
import {MockMorphoBorrowAdapter} from "../mocks/MockMorphoBorrowAdapter.sol";
import {MockMorphoVault} from "../mocks/MockMorphoVault.sol";
import {MockFeeRegistry} from "../mocks/MockFeeRegistry.sol";
import {MockRewards} from "../mocks/MockRewards.sol";

contract MockCuratorRegistryHarnessVaultV2 {
    mapping(address vault => address curator) public curators;

    function setCurator(address vault, address curator) external {
        curators[vault] = curator;
    }

    function getCurator(address vault) external view returns (address) {
        return curators[vault];
    }
}

contract VaultV2CoverageHarness is VaultV2 {
    using Checkpoints for Checkpoints.Trace256;
    using CheckpointsV2Lib for CheckpointsV2Lib.Trace256;

    constructor() VaultV2(address(0), address(0), address(0), address(0), address(0), address(0)) {}

    function setCollateralRaw(address collateral_) external {
        collateral = collateral_;
    }

    function setBurnerRaw(address burner_) external {
        burner = burner_;
    }

    function setSlasherRaw(address slasher_) external {
        slasher = slasher_;
    }

    function setEpochDurationRaw(uint48 epochDuration_) external {
        epochDuration = epochDuration_;
    }

    function setEpochDurationInitRaw(uint48 epochDurationInit_) external {
        __epochDurationInit = epochDurationInit_;
    }

    function pushActiveStakeRaw(uint48 timestamp, uint256 value) external {
        _activeStake.push(timestamp, value);
    }

    function pushWithdrawalsRaw(uint256 bucket, uint48 timestamp, uint256 value) external {
        _withdrawals[bucket].push(timestamp, value);
    }

    function pushWithdrawalSharesRaw(uint256 bucket, uint48 timestamp, uint256 value) external {
        _withdrawalShares[bucket].push(timestamp, value);
    }

    function pushWithdrawalSharesCumulativeRaw(uint48 timestamp, uint256 value) external {
        _withdrawalSharesCumulative.push(timestamp, value);
    }

    function setLegacyWithdrawalRaw(uint256 epoch, uint256 value) external {
        __withdrawals[epoch] = value;
    }

    function exposeUpdateWithdrawalsSharePrice(uint256 newActiveWithdrawals) external {
        _updateWithdrawalsSharePrice(newActiveWithdrawals);
    }

    function exposeMigrate(bytes calldata data) external {
        _migrate(1, VAULT_V2_VERSION, data);
    }
}

contract VaultV2Test is Test {
    using Math for uint256;
    using Subnetwork for bytes32;
    using Subnetwork for address;
    using Checkpoints for Checkpoints.Trace208;
    using UniversalDelegatorIndex for uint96;

    uint256 internal constant SUPPLY_CAP = (uint256(1) << 255) - 1;

    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    VaultFactory vaultFactory;
    DelegatorFactory delegatorFactory;
    SlasherFactory slasherFactory;
    NetworkRegistry networkRegistry;
    OperatorRegistry operatorRegistry;
    MetadataService operatorMetadataService;
    MetadataService networkMetadataService;
    NetworkMiddlewareService networkMiddlewareService;
    OptInService operatorVaultOptInService;
    OptInService operatorNetworkOptInService;

    Token collateral;
    FeeOnTransferToken feeOnTransferCollateral;
    VaultConfigurator vaultConfigurator;
    VaultV2TestHelper vaultTestHelper;
    MockFeeRegistry feeRegistry;
    MockRewards rewards;
    AdapterRegistry adapterRegistry;
    MockCuratorRegistryHarnessVaultV2 curatorRegistry;

    IVaultV2 vault;
    FullRestakeDelegator delegator;
    Slasher slasher;

    string internal constant VAULT_NAME = "Test";
    string internal constant VAULT_SYMBOL = "TEST";

    struct SlashNotMaturedState {
        uint256 blockTimestamp;
        uint256 activeStake;
        uint256 lastBucket;
        uint256 lastWithdrawals;
        uint256 lastWithdrawalShares;
        uint256 unmaturedWithdrawalShares;
        uint256 unmaturedWithdrawals;
        uint256 slashableStake;
        uint256 slashAmountReal;
        uint256 tokensBeforeBurner;
        uint256 activeSlashed;
        uint256 activeStakeAfter;
        uint256 unmaturedSlashed;
        uint256 withdrawalsAfter;
    }

    struct MigrateWithdrawalsState {
        uint256 blockTimestamp;
        uint256 aliceDeposit;
        uint256 bobDeposit;
        uint256 aliceWithdrawEpoch0;
        uint256 bobWithdrawEpoch0;
        uint256 epoch1Start;
        uint256 aliceWithdrawEpoch1;
        uint256 bobWithdrawEpoch1;
        uint256 epoch2Start;
        uint256 epoch1Withdrawals;
        uint256 epoch2Withdrawals;
        uint256 expectedAliceEpoch1;
        uint256 expectedBobEpoch1;
        uint256 expectedAliceEpoch2;
        uint256 expectedBobEpoch2;
        uint256 migrateTimestamp;
        uint48 nextEpochStart;
    }

    struct MigrateClaimAfterUpgradeState {
        uint256 blockTimestamp;
        uint256 aliceDeposit;
        uint256 withdrawEpoch0;
        uint256 epoch1Start;
        uint256 withdrawEpoch1;
        uint256 epoch2Start;
        uint256 expectedEpoch1;
        uint256 expectedEpoch2;
        uint48 nextEpochStart;
    }

    struct CreateInitializedVaultParams {
        uint48 epochDuration;
        address[] networkLimitSetRoleHolders;
        address[] operatorNetworkSharesSetRoleHolders;
        uint64 version;
        address burner;
        bool depositWhitelist;
        bool isDepositLimit;
        uint256 depositLimit;
        address owner;
        uint64 slasherIndex;
        bytes slasherParams;
    }

    function setUp() public virtual {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        vaultFactory = new VaultFactory(owner);
        delegatorFactory = new DelegatorFactory(owner);
        slasherFactory = new SlasherFactory(owner);
        networkRegistry = new NetworkRegistry();
        operatorRegistry = new OperatorRegistry();
        operatorMetadataService = new MetadataService(address(operatorRegistry));
        networkMetadataService = new MetadataService(address(networkRegistry));
        networkMiddlewareService = new NetworkMiddlewareService(address(networkRegistry));
        operatorVaultOptInService =
            new OptInService(address(operatorRegistry), address(vaultFactory), "OperatorVaultOptInService");
        operatorNetworkOptInService =
            new OptInService(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService");
        feeRegistry = new MockFeeRegistry();
        rewards = new MockRewards();
        adapterRegistry = new AdapterRegistry(owner);
        curatorRegistry = new MockCuratorRegistryHarnessVaultV2();

        vaultTestHelper = new VaultV2TestHelper();

        address vaultImplV1 =
            _createVaultV1Impl(address(delegatorFactory), address(slasherFactory), address(vaultFactory));
        vaultFactory.whitelist(vaultImplV1);

        address vaultImplTokenized =
            _createVaultTokenizedImpl(address(delegatorFactory), address(slasherFactory), address(vaultFactory));
        vaultFactory.whitelist(vaultImplTokenized);

        address vaultImpl = _createVaultImpl(address(delegatorFactory), address(slasherFactory), address(vaultFactory));

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
        feeOnTransferCollateral = new FeeOnTransferToken("FeeOnTransferToken");

        vaultConfigurator =
            new VaultConfigurator(address(vaultFactory), address(delegatorFactory), address(slasherFactory));
    }

    function test_Create2(
        address burner,
        uint48 epochDuration,
        bool depositWhitelist,
        bool isDepositLimit,
        uint256 depositLimit
    ) public virtual {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
        (IVaultV2 vault_, address delegator_, address slasher_) = _createInitializedVault(
            epochDuration,
            networkLimitSetRoleHolders,
            operatorNetworkSharesSetRoleHolders,
            vaultFactory.lastVersion(),
            burner,
            depositWhitelist,
            isDepositLimit,
            depositLimit
        );
        vault = vault_;

        assertEq(DEPOSIT_WHITELIST_SET_ROLE, keccak256("DEPOSIT_WHITELIST_SET_ROLE"));
        assertEq(DEPOSITOR_WHITELIST_ROLE, keccak256("DEPOSITOR_WHITELIST_ROLE"));

        assertEq(VaultV2(address(vault)).owner(), address(0));
        assertEq(vault.collateral(), address(collateral));
        assertEq(vault.delegator(), delegator_);
        assertEq(vault.slasher(), slasher_);
        assertEq(vault.burner(), burner);
        assertEq(vault.epochDuration(), epochDuration);
        assertEq(vault.depositWhitelist(), depositWhitelist);
        assertEq(VaultV2(address(vault)).hasRole(VaultV2(address(vault)).DEFAULT_ADMIN_ROLE(), alice), true);
        assertEq(VaultV2(address(vault)).hasRole(DEPOSITOR_WHITELIST_ROLE, alice), true);
        assertEq(vault.epochDuration(), epochDuration);
        assertEq(vault.totalStake(), 0);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), ""), 0);
        assertEq(vault.activeShares(), 0);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), ""), 0);
        assertEq(vault.activeStake(), 0);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp), ""), 0);
        assertEq(vault.activeSharesOf(alice), 0);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp), ""), 0);
        assertEq(vault.activeBalanceOf(alice), 0);
        assertEq(vault.withdrawalsOfLength(alice), 0);
        assertEq(vault.withdrawals(0), 0);
        assertEq(vault.withdrawalShares(0), 0);
        assertEq(vault.depositWhitelist(), depositWhitelist);
        assertEq(vault.isDepositorWhitelisted(alice), false);
        assertEq(vault.isInitialized(), true);
    }

    function test_CreateRevertInvalidEpochDuration() public {
        uint48 epochDuration = 0;

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
        uint64 lastVersion = vaultFactory.lastVersion();
        vm.expectRevert(IVaultV2.TooLongDuration.selector);
        _createInitializedVault(
            epochDuration,
            networkLimitSetRoleHolders,
            operatorNetworkSharesSetRoleHolders,
            lastVersion,
            address(0xdEaD),
            false,
            false,
            0
        );
    }

    function test_activeWithdrawalsFor_returnsZeroAboveEpochDuration() public {
        vault = _getUniversalVault(7 days);
        _deposit(alice, 100);
        _withdraw(alice, 40);

        assertEq(VaultV2(address(vault)).activeWithdrawalsFor(7 days + 1), 0);
        assertEq(VaultV2(address(vault)).activeWithdrawalsForAt(7 days + 1, uint48(block.timestamp)), 0);
    }

    function test_activeWithdrawalSharesFor_returnsZeroAboveEpochDuration() public {
        vault = _getUniversalVault(7 days);
        _deposit(alice, 100);
        _withdraw(alice, 40);

        assertEq(VaultV2(address(vault)).activeWithdrawalSharesFor(7 days + 1), 0);
        assertEq(VaultV2(address(vault)).activeWithdrawalSharesForAt(7 days + 1, uint48(block.timestamp)), 0);
    }

    function test_CreateRevertInvalidCollateral(uint48 epochDuration) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
        uint64 lastVersion = vaultFactory.lastVersion();
        collateral = Token(address(0));
        vm.expectRevert(IVaultV2.InvalidCollateral.selector);
        _createInitializedVault(
            epochDuration,
            networkLimitSetRoleHolders,
            operatorNetworkSharesSetRoleHolders,
            lastVersion,
            address(0xdEaD),
            false,
            false,
            0
        );
    }

    function test_CreateAllowsMissingRoles1(uint48 epochDuration) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        uint64 lastVersion = vaultFactory.lastVersion();

        vault = IVaultV2(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
                    IVaultV2.InitParams({
                        name: VAULT_NAME,
                        symbol: VAULT_SYMBOL,
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: epochDuration,
                        depositWhitelist: true,
                        depositorToWhitelist: address(0xBEEF),
                        isDepositLimit: false,
                        depositLimit: 0,
                        defaultAdminRoleHolder: address(0),
                        depositWhitelistSetRoleHolder: address(0),
                        depositorWhitelistRoleHolder: address(0),
                        isDepositLimitSetRoleHolder: alice,
                        depositLimitSetRoleHolder: address(0),
                        setAdapterLimitRoleHolder: address(0),
                        allocateAdapterRoleHolder: address(0)
                    })
                )
            )
        );
    }

    function test_CreateAllowsMissingRoles2(uint48 epochDuration) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        uint64 lastVersion = vaultFactory.lastVersion();

        vault = IVaultV2(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
                    IVaultV2.InitParams({
                        name: VAULT_NAME,
                        symbol: VAULT_SYMBOL,
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: epochDuration,
                        depositWhitelist: false,
                        depositorToWhitelist: address(0xBEEF),
                        isDepositLimit: true,
                        depositLimit: 0,
                        defaultAdminRoleHolder: address(0),
                        depositWhitelistSetRoleHolder: alice,
                        depositorWhitelistRoleHolder: address(0),
                        isDepositLimitSetRoleHolder: address(0),
                        depositLimitSetRoleHolder: address(0),
                        setAdapterLimitRoleHolder: address(0),
                        allocateAdapterRoleHolder: address(0)
                    })
                )
            )
        );
    }

    function test_CreateAllowsMissingRoles3(uint48 epochDuration) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        uint64 lastVersion = vaultFactory.lastVersion();

        vault = IVaultV2(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
                    IVaultV2.InitParams({
                        name: VAULT_NAME,
                        symbol: VAULT_SYMBOL,
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: epochDuration,
                        depositWhitelist: false,
                        depositorToWhitelist: address(0xBEEF),
                        isDepositLimit: false,
                        depositLimit: 0,
                        defaultAdminRoleHolder: address(0),
                        depositWhitelistSetRoleHolder: alice,
                        depositorWhitelistRoleHolder: address(0),
                        isDepositLimitSetRoleHolder: address(0),
                        depositLimitSetRoleHolder: alice,
                        setAdapterLimitRoleHolder: address(0),
                        allocateAdapterRoleHolder: address(0)
                    })
                )
            )
        );
    }

    function test_CreateAllowsMissingRoles4(uint48 epochDuration) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        uint64 lastVersion = vaultFactory.lastVersion();

        vault = IVaultV2(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
                    IVaultV2.InitParams({
                        name: VAULT_NAME,
                        symbol: VAULT_SYMBOL,
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: epochDuration,
                        depositWhitelist: false,
                        depositorToWhitelist: address(0xBEEF),
                        isDepositLimit: false,
                        depositLimit: 1,
                        defaultAdminRoleHolder: address(0),
                        depositWhitelistSetRoleHolder: alice,
                        depositorWhitelistRoleHolder: address(0),
                        isDepositLimitSetRoleHolder: address(0),
                        depositLimitSetRoleHolder: address(0),
                        setAdapterLimitRoleHolder: address(0),
                        allocateAdapterRoleHolder: address(0)
                    })
                )
            )
        );
    }

    function test_CreateAllowsMissingRoles5(uint48 epochDuration) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        uint64 lastVersion = vaultFactory.lastVersion();

        vault = IVaultV2(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
                    IVaultV2.InitParams({
                        name: VAULT_NAME,
                        symbol: VAULT_SYMBOL,
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: epochDuration,
                        depositWhitelist: false,
                        depositorToWhitelist: address(0xBEEF),
                        isDepositLimit: false,
                        depositLimit: 0,
                        defaultAdminRoleHolder: address(0),
                        depositWhitelistSetRoleHolder: address(0),
                        depositorWhitelistRoleHolder: alice,
                        isDepositLimitSetRoleHolder: alice,
                        depositLimitSetRoleHolder: address(0),
                        setAdapterLimitRoleHolder: address(0),
                        allocateAdapterRoleHolder: address(0)
                    })
                )
            )
        );
    }

    function test_AdapterRoleConstantsMatchAdapterRoleHashes() public pure {
        assertEq(SET_ADAPTER_LIMIT_ROLE, keccak256("SET_ADAPTER_LIMIT_ROLE"));
        assertEq(SWAP_ADAPTERS_ROLE, keccak256("SWAP_ADAPTERS_ROLE"));
        assertEq(ALLOCATE_ADAPTER_ROLE, keccak256("ALLOCATE_ADAPTER_ROLE"));
        assertEq(DEALLOCATE_ADAPTER_ROLE, keccak256("DEALLOCATE_ADAPTER_ROLE"));
    }

    function test_SetDelegator() public {
        uint64 lastVersion = vaultFactory.lastVersion();

        vault = IVaultV2(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
                    IVaultV2.InitParams({
                        name: VAULT_NAME,
                        symbol: VAULT_SYMBOL,
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: 7 days,
                        depositWhitelist: false,
                        depositorToWhitelist: address(0xBEEF),
                        isDepositLimit: false,
                        depositLimit: 0,
                        defaultAdminRoleHolder: alice,
                        depositWhitelistSetRoleHolder: alice,
                        depositorWhitelistRoleHolder: alice,
                        isDepositLimitSetRoleHolder: alice,
                        depositLimitSetRoleHolder: alice,
                        setAdapterLimitRoleHolder: alice,
                        allocateAdapterRoleHolder: alice
                    })
                )
            )
        );

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](1);
        operatorNetworkLimitSetRoleHolders[0] = alice;
        IUniversalDelegator.InitParams memory delegatorParams = IUniversalDelegator.InitParams({
            defaultAdminRoleHolder: alice,
            hook: address(0),
            hookSetRoleHolder: alice,
            createSlotRoleHolder: alice,
            setSizeRoleHolder: alice,
            swapSlotsRoleHolder: alice,
            withdrawalBufferSize: type(uint128).max
        });
        UniversalDelegator delegator_ = UniversalDelegator(
            delegatorFactory.create(UNIVERSAL_DELEGATOR_TYPE, abi.encode(address(vault), abi.encode(delegatorParams)))
        );

        VaultV2(address(vault)).setDelegator(address(delegator_));

        assertEq(vault.delegator(), address(delegator_));
        assertEq(vault.isInitialized(), false);
    }

    function test_SetDelegatorRevertDelegatorAlreadyInitialized() public {
        uint64 lastVersion = vaultFactory.lastVersion();

        vault = IVaultV2(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
                    IVaultV2.InitParams({
                        name: VAULT_NAME,
                        symbol: VAULT_SYMBOL,
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: 7 days,
                        depositWhitelist: false,
                        depositorToWhitelist: address(0xBEEF),
                        isDepositLimit: false,
                        depositLimit: 0,
                        defaultAdminRoleHolder: alice,
                        depositWhitelistSetRoleHolder: alice,
                        depositorWhitelistRoleHolder: alice,
                        isDepositLimitSetRoleHolder: alice,
                        depositLimitSetRoleHolder: alice,
                        setAdapterLimitRoleHolder: alice,
                        allocateAdapterRoleHolder: alice
                    })
                )
            )
        );

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](1);
        operatorNetworkLimitSetRoleHolders[0] = alice;
        IUniversalDelegator.InitParams memory delegatorParams = IUniversalDelegator.InitParams({
            defaultAdminRoleHolder: alice,
            hook: address(0),
            hookSetRoleHolder: alice,
            createSlotRoleHolder: alice,
            setSizeRoleHolder: alice,
            swapSlotsRoleHolder: alice,
            withdrawalBufferSize: type(uint128).max
        });
        UniversalDelegator delegator_ = UniversalDelegator(
            delegatorFactory.create(UNIVERSAL_DELEGATOR_TYPE, abi.encode(address(vault), abi.encode(delegatorParams)))
        );

        VaultV2(address(vault)).setDelegator(address(delegator_));

        vm.expectRevert(IVaultV2.DelegatorAlreadyInitialized.selector);
        VaultV2(address(vault)).setDelegator(address(delegator_));
    }

    function test_SetDelegatorRevertInvalidDelegatorWhenNotFactoryEntity() public {
        uint64 lastVersion = vaultFactory.lastVersion();

        vault = IVaultV2(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
                    IVaultV2.InitParams({
                        name: VAULT_NAME,
                        symbol: VAULT_SYMBOL,
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: 7 days,
                        depositWhitelist: false,
                        depositorToWhitelist: address(0xBEEF),
                        isDepositLimit: false,
                        depositLimit: 0,
                        defaultAdminRoleHolder: alice,
                        depositWhitelistSetRoleHolder: alice,
                        depositorWhitelistRoleHolder: alice,
                        isDepositLimitSetRoleHolder: alice,
                        depositLimitSetRoleHolder: alice,
                        setAdapterLimitRoleHolder: alice,
                        allocateAdapterRoleHolder: alice
                    })
                )
            )
        );

        vm.expectRevert(IVaultV2.InvalidDelegator.selector);
        VaultV2(address(vault)).setDelegator(address(1));
    }

    function test_SetDelegatorRevertInvalidDelegator() public {
        uint64 lastVersion = vaultFactory.lastVersion();

        vault = IVaultV2(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
                    IVaultV2.InitParams({
                        name: VAULT_NAME,
                        symbol: VAULT_SYMBOL,
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: 7 days,
                        depositWhitelist: false,
                        depositorToWhitelist: address(0xBEEF),
                        isDepositLimit: false,
                        depositLimit: 0,
                        defaultAdminRoleHolder: alice,
                        depositWhitelistSetRoleHolder: alice,
                        depositorWhitelistRoleHolder: alice,
                        isDepositLimitSetRoleHolder: alice,
                        depositLimitSetRoleHolder: alice,
                        setAdapterLimitRoleHolder: alice,
                        allocateAdapterRoleHolder: alice
                    })
                )
            )
        );

        address vault2 = vaultFactory.create(
            lastVersion,
            alice,
            _getEncodedVaultParams(
                IVaultV2.InitParams({
                    name: VAULT_NAME,
                    symbol: VAULT_SYMBOL,
                    collateral: address(collateral),
                    burner: address(0xdEaD),
                    epochDuration: 7 days,
                    depositWhitelist: false,
                    depositorToWhitelist: address(0xBEEF),
                    isDepositLimit: false,
                    depositLimit: 0,
                    defaultAdminRoleHolder: alice,
                    depositWhitelistSetRoleHolder: alice,
                    depositorWhitelistRoleHolder: alice,
                    isDepositLimitSetRoleHolder: alice,
                    depositLimitSetRoleHolder: alice,
                    setAdapterLimitRoleHolder: alice,
                    allocateAdapterRoleHolder: alice
                })
            )
        );

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](1);
        operatorNetworkLimitSetRoleHolders[0] = alice;
        delegator = FullRestakeDelegator(
            delegatorFactory.create(
                1,
                abi.encode(
                    address(vault2),
                    abi.encode(
                        IFullRestakeDelegator.InitParams({
                            baseParams: IBaseDelegator.BaseParams({
                                defaultAdminRoleHolder: alice, hook: address(0), hookSetRoleHolder: alice
                            }),
                            networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                            operatorNetworkLimitSetRoleHolders: operatorNetworkLimitSetRoleHolders
                        })
                    )
                )
            )
        );

        vm.expectRevert(IVaultV2.InvalidDelegator.selector);
        VaultV2(address(vault)).setDelegator(address(delegator));
    }

    function test_SetSlasher() public {
        uint64 lastVersion = vaultFactory.lastVersion();

        vault = IVaultV2(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
                    IVaultV2.InitParams({
                        name: VAULT_NAME,
                        symbol: VAULT_SYMBOL,
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: 7 days,
                        depositWhitelist: false,
                        depositorToWhitelist: address(0xBEEF),
                        isDepositLimit: false,
                        depositLimit: 0,
                        defaultAdminRoleHolder: alice,
                        depositWhitelistSetRoleHolder: alice,
                        depositorWhitelistRoleHolder: alice,
                        isDepositLimitSetRoleHolder: alice,
                        depositLimitSetRoleHolder: alice,
                        setAdapterLimitRoleHolder: alice,
                        allocateAdapterRoleHolder: alice
                    })
                )
            )
        );

        UniversalSlasher slasher_ = UniversalSlasher(
            slasherFactory.create(
                UNIVERSAL_SLASHER_TYPE,
                abi.encode(
                    address(vault),
                    abi.encode(
                        IUniversalSlasher.InitParams({
                            isBurnerHook: false, vetoDuration: 1, resolverSetDelay: 7 days * 3
                        })
                    )
                )
            )
        );

        VaultV2(address(vault)).setSlasher(address(slasher_));

        assertEq(vault.slasher(), address(slasher_));
        assertEq(vault.isInitialized(), false);
    }

    function test_SetSlasherRevertSlasherAlreadyInitialized() public {
        uint64 lastVersion = vaultFactory.lastVersion();

        vault = IVaultV2(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
                    IVaultV2.InitParams({
                        name: VAULT_NAME,
                        symbol: VAULT_SYMBOL,
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: 7 days,
                        depositWhitelist: false,
                        depositorToWhitelist: address(0xBEEF),
                        isDepositLimit: false,
                        depositLimit: 0,
                        defaultAdminRoleHolder: alice,
                        depositWhitelistSetRoleHolder: alice,
                        depositorWhitelistRoleHolder: alice,
                        isDepositLimitSetRoleHolder: alice,
                        depositLimitSetRoleHolder: alice,
                        setAdapterLimitRoleHolder: alice,
                        allocateAdapterRoleHolder: alice
                    })
                )
            )
        );

        UniversalSlasher slasher_ = UniversalSlasher(
            slasherFactory.create(
                UNIVERSAL_SLASHER_TYPE,
                abi.encode(
                    address(vault),
                    abi.encode(
                        IUniversalSlasher.InitParams({
                            isBurnerHook: false, vetoDuration: 1, resolverSetDelay: 7 days * 3
                        })
                    )
                )
            )
        );

        VaultV2(address(vault)).setSlasher(address(slasher_));

        vm.expectRevert(IVaultV2.SlasherAlreadyInitialized.selector);
        VaultV2(address(vault)).setSlasher(address(slasher_));
    }

    function test_SetSlasherRevertInvalidSlasherWhenNotFactoryEntity() public {
        uint64 lastVersion = vaultFactory.lastVersion();

        vault = IVaultV2(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
                    IVaultV2.InitParams({
                        name: VAULT_NAME,
                        symbol: VAULT_SYMBOL,
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: 7 days,
                        depositWhitelist: false,
                        depositorToWhitelist: address(0xBEEF),
                        isDepositLimit: false,
                        depositLimit: 0,
                        defaultAdminRoleHolder: alice,
                        depositWhitelistSetRoleHolder: alice,
                        depositorWhitelistRoleHolder: alice,
                        isDepositLimitSetRoleHolder: alice,
                        depositLimitSetRoleHolder: alice,
                        setAdapterLimitRoleHolder: alice,
                        allocateAdapterRoleHolder: alice
                    })
                )
            )
        );

        vm.expectRevert(IVaultV2.InvalidSlasher.selector);
        VaultV2(address(vault)).setSlasher(address(1));
    }

    function test_SetSlasherRevertInvalidSlasher() public {
        uint64 lastVersion = vaultFactory.lastVersion();

        vault = IVaultV2(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
                    IVaultV2.InitParams({
                        name: VAULT_NAME,
                        symbol: VAULT_SYMBOL,
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: 7 days,
                        depositWhitelist: false,
                        depositorToWhitelist: address(0xBEEF),
                        isDepositLimit: false,
                        depositLimit: 0,
                        defaultAdminRoleHolder: alice,
                        depositWhitelistSetRoleHolder: alice,
                        depositorWhitelistRoleHolder: alice,
                        isDepositLimitSetRoleHolder: alice,
                        depositLimitSetRoleHolder: alice,
                        setAdapterLimitRoleHolder: alice,
                        allocateAdapterRoleHolder: alice
                    })
                )
            )
        );

        address vault2 = vaultFactory.create(
            lastVersion,
            alice,
            _getEncodedVaultParams(
                IVaultV2.InitParams({
                    name: VAULT_NAME,
                    symbol: VAULT_SYMBOL,
                    collateral: address(collateral),
                    burner: address(0xdEaD),
                    epochDuration: 7 days,
                    depositWhitelist: false,
                    depositorToWhitelist: address(0xBEEF),
                    isDepositLimit: false,
                    depositLimit: 0,
                    defaultAdminRoleHolder: alice,
                    depositWhitelistSetRoleHolder: alice,
                    depositorWhitelistRoleHolder: alice,
                    isDepositLimitSetRoleHolder: alice,
                    depositLimitSetRoleHolder: alice,
                    setAdapterLimitRoleHolder: alice,
                    allocateAdapterRoleHolder: alice
                })
            )
        );

        UniversalSlasher slasher_ = UniversalSlasher(
            slasherFactory.create(
                UNIVERSAL_SLASHER_TYPE,
                abi.encode(
                    address(vault2),
                    abi.encode(
                        IUniversalSlasher.InitParams({
                            isBurnerHook: false, vetoDuration: 1, resolverSetDelay: 7 days * 3
                        })
                    )
                )
            )
        );

        vm.expectRevert(IVaultV2.InvalidSlasher.selector);
        VaultV2(address(vault)).setSlasher(address(slasher_));
    }

    function test_SetSlasherZeroAddress() public {
        uint64 lastVersion = vaultFactory.lastVersion();

        vault = IVaultV2(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
                    IVaultV2.InitParams({
                        name: VAULT_NAME,
                        symbol: VAULT_SYMBOL,
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: 7 days,
                        depositWhitelist: false,
                        depositorToWhitelist: address(0xBEEF),
                        isDepositLimit: false,
                        depositLimit: 0,
                        defaultAdminRoleHolder: alice,
                        depositWhitelistSetRoleHolder: alice,
                        depositorWhitelistRoleHolder: alice,
                        isDepositLimitSetRoleHolder: alice,
                        depositLimitSetRoleHolder: alice,
                        setAdapterLimitRoleHolder: alice,
                        allocateAdapterRoleHolder: alice
                    })
                )
            )
        );

        VaultV2(address(vault)).setSlasher(address(0));
    }

    function test_DepositTwice(uint256 amount1, uint256 amount2) public virtual {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        uint256 tokensBefore = collateral.balanceOf(address(vault));
        uint256 shares1;
        {
            uint256 prevShares = vault.activeShares();
            uint256 prevStake = vault.activeStake();
            (uint256 depositedAmount, uint256 mintedShares) = _deposit(alice, amount1);
            shares1 = mintedShares;
            assertEq(depositedAmount, amount1);
            assertEq(mintedShares, ERC4626Math.previewDeposit(depositedAmount, prevShares, prevStake));
        }
        assertEq(collateral.balanceOf(address(vault)) - tokensBefore, amount1);

        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1), ""), 0);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), ""), shares1);
        assertEq(vault.activeShares(), shares1);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), ""), 0);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), ""), amount1);
        assertEq(vault.activeStake(), amount1);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1), ""), 0);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp), ""), shares1);
        assertEq(vault.activeSharesOf(alice), shares1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1), ""), 0);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp), ""), amount1);
        assertEq(vault.activeBalanceOf(alice), amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 shares2;
        {
            uint256 prevShares = vault.activeShares();
            uint256 prevStake = vault.activeStake();
            (uint256 depositedAmount, uint256 mintedShares) = _deposit(alice, amount2);
            shares2 = mintedShares;
            assertEq(depositedAmount, amount2);
            assertEq(mintedShares, ERC4626Math.previewDeposit(depositedAmount, prevShares, prevStake));
        }

        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1), ""), shares1);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), ""), shares1 + shares2);
        assertEq(vault.activeShares(), shares1 + shares2);
        uint256 gasLeft = gasleft();
        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1), abi.encode(1)), shares1);
        uint256 gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1), abi.encode(0)), shares1);
        assertGt(gasSpent, gasLeft - gasleft());
        gasLeft = gasleft();
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), abi.encode(0)), shares1 + shares2);
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), abi.encode(1)), shares1 + shares2);
        assertGt(gasSpent, gasLeft - gasleft());
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), ""), amount1);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), ""), amount1 + amount2);
        assertEq(vault.activeStake(), amount1 + amount2);
        gasLeft = gasleft();
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), abi.encode(1)), amount1);
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), abi.encode(0)), amount1);
        assertGt(gasSpent, gasLeft - gasleft());
        gasLeft = gasleft();
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), abi.encode(0)), amount1 + amount2);
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), abi.encode(1)), amount1 + amount2);
        assertGt(gasSpent, gasLeft - gasleft());
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), ""), shares1);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), ""), shares1 + shares2);
        assertEq(vault.activeSharesOf(alice), shares1 + shares2);
        gasLeft = gasleft();
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1), abi.encode(1)), shares1);
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1), abi.encode(0)), shares1);
        assertGt(gasSpent, gasLeft - gasleft());
        gasLeft = gasleft();
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp), abi.encode(0)), shares1 + shares2);
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp), abi.encode(1)), shares1 + shares2);
        assertGt(gasSpent, gasLeft - gasleft());
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1), ""), amount1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp), ""), amount1 + amount2);
        assertEq(vault.activeBalanceOf(alice), amount1 + amount2);
        assertEq(
            vault.activeBalanceOfAt(
                alice, uint48(blockTimestamp - 1), abi.encode(abi.encode(1), abi.encode(1), abi.encode(1))
            ),
            amount1
        );
        assertEq(
            vault.activeBalanceOfAt(
                alice, uint48(blockTimestamp - 1), abi.encode(abi.encode(0), abi.encode(0), abi.encode(0))
            ),
            amount1
        );
        assertEq(
            vault.activeBalanceOfAt(
                alice, uint48(blockTimestamp), abi.encode(abi.encode(0), abi.encode(0), abi.encode(0))
            ),
            amount1 + amount2
        );
        assertEq(
            vault.activeBalanceOfAt(
                alice, uint48(blockTimestamp), abi.encode(abi.encode(1), abi.encode(1), abi.encode(1))
            ),
            amount1 + amount2
        );
    }

    function test_DepositTwiceFeeOnTransferCollateral(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 2, 100 * 10 ** 18);
        amount2 = bound(amount2, 2, 100 * 10 ** 18);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        {
            address[] memory networkLimitSetRoleHolders = new address[](1);
            networkLimitSetRoleHolders[0] = alice;
            address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
            operatorNetworkSharesSetRoleHolders[0] = alice;
            collateral = Token(address(feeOnTransferCollateral));
            (vault,,) = _createInitializedVault(
                epochDuration,
                networkLimitSetRoleHolders,
                operatorNetworkSharesSetRoleHolders,
                vaultFactory.lastVersion(),
                address(0xdEaD),
                false,
                false,
                0
            );
        }

        uint256 tokensBefore = feeOnTransferCollateral.balanceOf(address(vault));
        uint256 shares1;
        feeOnTransferCollateral.transfer(alice, amount1 + 1);
        vm.startPrank(alice);
        feeOnTransferCollateral.approve(address(vault), amount1);
        {
            uint256 prevShares = vault.activeShares();
            uint256 prevStake = vault.activeStake();
            (uint256 depositedAmount, uint256 mintedShares) = vault.deposit(alice, amount1);
            shares1 = mintedShares;
            assertEq(depositedAmount, amount1 - 1);
            assertEq(mintedShares, ERC4626Math.previewDeposit(depositedAmount, prevShares, prevStake));
        }
        vm.stopPrank();
        assertEq(feeOnTransferCollateral.balanceOf(address(vault)) - tokensBefore, amount1 - 1);

        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1), ""), 0);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), ""), shares1);
        assertEq(vault.activeShares(), shares1);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), ""), 0);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), ""), amount1 - 1);
        assertEq(vault.activeStake(), amount1 - 1);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1), ""), 0);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp), ""), shares1);
        assertEq(vault.activeSharesOf(alice), shares1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1), ""), 0);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp), ""), amount1 - 1);
        assertEq(vault.activeBalanceOf(alice), amount1 - 1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 shares2;
        feeOnTransferCollateral.transfer(alice, amount2 + 1);
        vm.startPrank(alice);
        feeOnTransferCollateral.approve(address(vault), amount2);
        {
            uint256 prevShares = vault.activeShares();
            uint256 prevStake = vault.activeStake();
            (uint256 depositedAmount, uint256 mintedShares) = vault.deposit(alice, amount2);
            shares2 = mintedShares;
            assertEq(depositedAmount, amount2 - 1);
            assertEq(mintedShares, ERC4626Math.previewDeposit(depositedAmount, prevShares, prevStake));
        }
        vm.stopPrank();

        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1), ""), shares1);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), ""), shares1 + shares2);
        assertEq(vault.activeShares(), shares1 + shares2);
        uint256 gasLeft = gasleft();
        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1), abi.encode(1)), shares1);
        uint256 gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1), abi.encode(0)), shares1);
        assertGt(gasSpent, gasLeft - gasleft());
        gasLeft = gasleft();
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), abi.encode(0)), shares1 + shares2);
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), abi.encode(1)), shares1 + shares2);
        assertGt(gasSpent, gasLeft - gasleft());
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), ""), amount1 - 1);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), ""), amount1 - 1 + amount2 - 1);
        assertEq(vault.activeStake(), amount1 - 1 + amount2 - 1);
        gasLeft = gasleft();
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), abi.encode(1)), amount1 - 1);
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), abi.encode(0)), amount1 - 1);
        assertGt(gasSpent, gasLeft - gasleft());
        gasLeft = gasleft();
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), abi.encode(0)), amount1 - 1 + amount2 - 1);
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), abi.encode(1)), amount1 - 1 + amount2 - 1);
        assertGt(gasSpent, gasLeft - gasleft());
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), ""), shares1);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), ""), shares1 + shares2);
        assertEq(vault.activeSharesOf(alice), shares1 + shares2);
        gasLeft = gasleft();
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1), abi.encode(1)), shares1);
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1), abi.encode(0)), shares1);
        assertGt(gasSpent, gasLeft - gasleft());
        gasLeft = gasleft();
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp), abi.encode(0)), shares1 + shares2);
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp), abi.encode(1)), shares1 + shares2);
        assertGt(gasSpent, gasLeft - gasleft());
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1), ""), amount1 - 1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp), ""), amount1 - 1 + amount2 - 1);
        assertEq(vault.activeBalanceOf(alice), amount1 - 1 + amount2 - 1);
        assertEq(
            vault.activeBalanceOfAt(
                alice, uint48(blockTimestamp - 1), abi.encode(abi.encode(1), abi.encode(1), abi.encode(1))
            ),
            amount1 - 1
        );
        assertEq(
            vault.activeBalanceOfAt(
                alice, uint48(blockTimestamp - 1), abi.encode(abi.encode(0), abi.encode(0), abi.encode(0))
            ),
            amount1 - 1
        );
        assertEq(
            vault.activeBalanceOfAt(
                alice, uint48(blockTimestamp), abi.encode(abi.encode(0), abi.encode(0), abi.encode(0))
            ),
            amount1 - 1 + amount2 - 1
        );
        assertEq(
            vault.activeBalanceOfAt(
                alice, uint48(blockTimestamp), abi.encode(abi.encode(1), abi.encode(1), abi.encode(1))
            ),
            amount1 - 1 + amount2 - 1
        );
    }

    function test_DepositBoth(uint256 amount1, uint256 amount2) public virtual {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        uint256 shares1;
        {
            uint256 prevShares = vault.activeShares();
            uint256 prevStake = vault.activeStake();
            (uint256 depositedAmount, uint256 mintedShares) = _deposit(alice, amount1);
            shares1 = mintedShares;
            assertEq(depositedAmount, amount1);
            assertEq(mintedShares, ERC4626Math.previewDeposit(depositedAmount, prevShares, prevStake));
        }

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 shares2;
        {
            uint256 prevShares = vault.activeShares();
            uint256 prevStake = vault.activeStake();
            (uint256 depositedAmount, uint256 mintedShares) = _deposit(bob, amount2);
            shares2 = mintedShares;
            assertEq(depositedAmount, amount2);
            assertEq(mintedShares, ERC4626Math.previewDeposit(depositedAmount, prevShares, prevStake));
        }

        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1), ""), shares1);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), ""), shares1 + shares2);
        assertEq(vault.activeShares(), shares1 + shares2);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), ""), amount1);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), ""), amount1 + amount2);
        assertEq(vault.activeStake(), amount1 + amount2);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1), ""), shares1);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp), ""), shares1);
        assertEq(vault.activeSharesOf(alice), shares1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1), ""), amount1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp), ""), amount1);
        assertEq(vault.activeBalanceOf(alice), amount1);
        assertEq(vault.activeSharesOfAt(bob, uint48(blockTimestamp - 1), ""), 0);
        assertEq(vault.activeSharesOfAt(bob, uint48(blockTimestamp), ""), shares2);
        assertEq(vault.activeSharesOf(bob), shares2);
        assertEq(vault.activeBalanceOfAt(bob, uint48(blockTimestamp - 1), ""), 0);
        assertEq(vault.activeBalanceOfAt(bob, uint48(blockTimestamp), ""), amount2);
        assertEq(vault.activeBalanceOf(bob), amount2);
    }

    function test_DepositDonation(uint256 amount1) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        (, uint256 mintedShares) = _deposit(alice, 1);
        assertEq(mintedShares, 1);

        collateral.transfer(address(rewards), amount1);
        vm.startPrank(address(rewards));
        collateral.approve(address(vault), amount1);
        VaultV2(address(vault)).donate(amount1);
        vm.stopPrank();

        assertEq(vault.activeStake(), amount1 + 1);
        assertEq(vault.activeShares(), 1);
        assertEq(vault.activeSharesOf(alice), 1);
    }

    function test_DepositRevertWhenMintedSharesRoundDownToZero() public {
        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        (, uint256 mintedShares) = _deposit(alice, 1);
        assertEq(mintedShares, 1);

        uint256 donation = collateral.balanceOf(address(this)) - 1;
        collateral.transfer(address(rewards), donation);
        vm.startPrank(address(rewards));
        collateral.approve(address(vault), donation);
        VaultV2(address(vault)).donate(donation);
        vm.stopPrank();

        collateral.transfer(bob, 1);
        vm.startPrank(bob);
        collateral.approve(address(vault), 1);
        vm.expectRevert(IVaultV2.InsufficientAmount.selector);
        vault.deposit(bob, 1);
        vm.stopPrank();
    }

    function test_DonateRevertNotRewards() public {
        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        uint256 amount = 1;
        collateral.transfer(alice, amount);

        vm.startPrank(alice);
        collateral.approve(address(vault), amount);
        vm.expectRevert(IVaultV2.NotRewards.selector);
        VaultV2(address(vault)).donate(amount);
        vm.stopPrank();
    }

    function test_Donate_syncsClaimableAndActiveWithdrawalsBuckets() public {
        vault = _getUniversalVault(7 days);

        _deposit(alice, 100);
        _deposit(bob, 100);

        vm.warp(block.timestamp + 1);
        _withdraw(alice, 40);

        vm.warp(block.timestamp + uint256(vault.epochDuration()) + 1);
        _withdraw(bob, 30);

        uint256 donation = 20;
        uint48 aliceUnlockAfter = vault.withdrawalUnlockAt(0, alice);
        uint48 bobUnlockAfter = vault.withdrawalUnlockAt(0, bob);
        uint256 bucketBefore = _latestWithdrawalBucket();
        uint256 claimableBefore = vault.withdrawalsOf(0, alice);
        uint256 activeStakeBefore = vault.activeStake();
        uint256 expectedWithdrawalsDonated;
        uint256 expectedNewActiveWithdrawals;
        uint256 expectedBobWithdrawalsAfter;
        {
            uint256 curActiveWithdrawals = vault.activeWithdrawals();
            uint256 curActiveWithdrawalShares = _unmaturedWithdrawalShares(uint48(block.timestamp));
            uint256 bobSharesBefore = vault.withdrawalSharesOf(0, bob);

            expectedWithdrawalsDonated = donation.mulDiv(curActiveWithdrawals, activeStakeBefore + curActiveWithdrawals);
            expectedNewActiveWithdrawals = curActiveWithdrawals + expectedWithdrawalsDonated;
            expectedBobWithdrawalsAfter =
                ERC4626Math.previewRedeem(bobSharesBefore, expectedNewActiveWithdrawals, curActiveWithdrawalShares);
        }

        collateral.transfer(address(rewards), donation);
        vm.startPrank(address(rewards));
        collateral.approve(address(vault), donation);
        VaultV2(address(vault)).donate(donation);
        vm.stopPrank();

        uint256 bucketAfter = _latestWithdrawalBucket();
        assertEq(bucketAfter, bucketBefore + 1);

        assertEq(vaultTestHelper.unlockToBucketUpperLookupRecent(address(vault), aliceUnlockAfter), bucketBefore);
        assertEq(vaultTestHelper.unlockToBucketUpperLookupRecent(address(vault), bobUnlockAfter), bucketAfter);

        assertEq(vault.withdrawalsOf(0, alice), claimableBefore);
        assertEq(vault.withdrawalsOf(0, bob), expectedBobWithdrawalsAfter);
        assertEq(vault.withdrawals(bucketBefore), claimableBefore);
        assertEq(vault.withdrawals(bucketAfter), expectedNewActiveWithdrawals);
        assertEq(vaultTestHelper.unclaimedRaw(address(vault)), int256(claimableBefore));
        assertEq(vault.activeStake(), activeStakeBefore + donation - expectedWithdrawalsDonated);
    }

    function test_Donate_atUnlockBoundary_doesNotAffectCurrentClaimableWithdrawal() public {
        vault = _getUniversalVault(7 days);
        (uint48 aliceUnlockAfter,) = _prepareAdjacentUnlockWithdrawals();

        uint256 donation = 20;
        uint256 claimableBefore = vault.withdrawalsOf(0, alice);

        collateral.transfer(address(rewards), donation);
        vm.startPrank(address(rewards));
        collateral.approve(address(vault), donation);
        VaultV2(address(vault)).donate(donation);
        vm.stopPrank();

        assertEq(vault.withdrawalsOf(0, alice), claimableBefore);
        assertEq(_claim(alice, 0), claimableBefore);
        assertEq(vault.withdrawalUnlockAt(0, alice), aliceUnlockAfter);
    }

    function test_Donate_atUnlockBoundary_affectsNextTimestampWithdrawal() public {
        vault = _getUniversalVault(7 days);
        (, uint48 bobUnlockAfter) = _prepareAdjacentUnlockWithdrawals();

        uint256 donation = 20;
        uint256 bobBefore = vault.withdrawalsOf(0, bob);
        uint256 expectedNewActiveWithdrawals;
        uint256 expectedActiveStakeAfter;
        uint256 expectedBobWithdrawalsAfter;
        {
            uint256 curActiveWithdrawals = vault.activeWithdrawals();
            uint256 activeStakeBefore = vault.activeStake();
            uint256 curActiveWithdrawalShares = _unmaturedWithdrawalShares(uint48(block.timestamp));
            uint256 bobSharesBefore = vault.withdrawalSharesOf(0, bob);
            uint256 expectedWithdrawalsDonated =
                donation.mulDiv(curActiveWithdrawals, activeStakeBefore + curActiveWithdrawals);

            expectedNewActiveWithdrawals = curActiveWithdrawals + expectedWithdrawalsDonated;
            expectedActiveStakeAfter = activeStakeBefore + donation - expectedWithdrawalsDonated;
            expectedBobWithdrawalsAfter =
                ERC4626Math.previewRedeem(bobSharesBefore, expectedNewActiveWithdrawals, curActiveWithdrawalShares);
        }

        collateral.transfer(address(rewards), donation);
        vm.startPrank(address(rewards));
        collateral.approve(address(vault), donation);
        VaultV2(address(vault)).donate(donation);
        vm.stopPrank();

        assertEq(vault.withdrawalUnlockAt(0, bob), uint48(block.timestamp) + 1);
        assertGt(expectedBobWithdrawalsAfter, bobBefore);
        assertEq(vault.withdrawalsOf(0, bob), expectedBobWithdrawalsAfter);
        assertEq(vault.activeWithdrawals(), expectedNewActiveWithdrawals);
        assertEq(vault.activeStake(), expectedActiveStakeAfter);

        vm.warp(bobUnlockAfter);
        assertEq(_claim(bob, 0), expectedBobWithdrawalsAfter);
    }

    function test_Donate_atUnlockBoundary_historicalCurrentTimestampTracksUpdatedState() public {
        vault = _getUniversalVault(7 days);
        (uint48 aliceUnlockAfter,) = _prepareAdjacentUnlockWithdrawals();

        uint256 donation = 20;
        uint48 previousTimestamp = aliceUnlockAfter - 1;
        uint256 historicalPrevActiveBefore = vault.activeWithdrawalsAt(previousTimestamp);
        uint256 historicalPrevStakeBefore = vault.activeStakeAt(previousTimestamp, "");
        uint256 expectedNewActiveWithdrawals;
        uint256 expectedActiveStakeAfter;
        {
            uint256 curActiveWithdrawals = vault.activeWithdrawals();
            uint256 activeStakeBefore = vault.activeStake();
            uint256 expectedWithdrawalsDonated =
                donation.mulDiv(curActiveWithdrawals, activeStakeBefore + curActiveWithdrawals);
            expectedNewActiveWithdrawals = curActiveWithdrawals + expectedWithdrawalsDonated;
            expectedActiveStakeAfter = activeStakeBefore + donation - expectedWithdrawalsDonated;
        }

        collateral.transfer(address(rewards), donation);
        vm.startPrank(address(rewards));
        collateral.approve(address(vault), donation);
        VaultV2(address(vault)).donate(donation);
        vm.stopPrank();

        assertEq(vault.activeWithdrawals(), expectedNewActiveWithdrawals);
        assertEq(vault.activeStake(), expectedActiveStakeAfter);
        assertEq(vault.activeWithdrawalsAt(previousTimestamp), historicalPrevActiveBefore);
        assertEq(vault.activeStakeAt(previousTimestamp, ""), historicalPrevStakeBefore);
        assertEq(vault.activeWithdrawalsAt(aliceUnlockAfter), expectedNewActiveWithdrawals);
        assertEq(vault.activeStakeAt(aliceUnlockAfter, ""), expectedActiveStakeAfter);
    }

    function test_WithdrawalsBoundary_durationWindows_alignWithDelegatorBalanceAt() public {
        UniversalDelegator universalDelegator;
        uint48 aliceUnlockAfter;
        (universalDelegator,, aliceUnlockAfter,) = _prepareAdjacentUnlockWithdrawalsWithUniversalNetwork();

        uint48 previousTimestamp = aliceUnlockAfter - 1;
        uint256 activeStakeBefore = vault.activeStakeAt(previousTimestamp, "");
        uint256 activeStakeAtBoundary = vault.activeStakeAt(aliceUnlockAfter, "");

        assertEq(vault.activeWithdrawalSharesOfAt(alice, previousTimestamp), 40);
        assertEq(vault.activeWithdrawalSharesOfAt(bob, previousTimestamp), 30);
        assertEq(vault.withdrawalsOf(0, alice), 40);
        assertEq(vault.activeWithdrawalSharesForAt(0, previousTimestamp), 70);
        assertEq(vault.activeWithdrawalSharesForAt(1, previousTimestamp), 30);
        assertEq(vault.activeWithdrawalsForAt(0, previousTimestamp), 70);
        assertEq(vault.activeWithdrawalsForAt(1, previousTimestamp), 30);
        assertEq(vault.activeWithdrawalSharesOfAt(alice, aliceUnlockAfter), 0);
        assertEq(vault.activeWithdrawalSharesOfAt(bob, aliceUnlockAfter), 30);
        assertEq(vault.activeWithdrawalSharesForAt(0, aliceUnlockAfter), 30);
        assertEq(vault.activeWithdrawalSharesForAt(1, aliceUnlockAfter), 0);
        assertEq(vault.activeWithdrawalsForAt(0, aliceUnlockAfter), 30);
        assertEq(vault.activeWithdrawalsForAt(1, aliceUnlockAfter), 0);

        assertEq(universalDelegator.getBalanceAt(0, 0, previousTimestamp), activeStakeBefore + 70);
        assertEq(universalDelegator.getBalanceAt(0, 1, previousTimestamp), activeStakeBefore + 30);
        assertEq(universalDelegator.getBalanceAt(0, 0, aliceUnlockAfter), activeStakeAtBoundary + 30);
        assertEq(universalDelegator.getBalanceAt(0, 1, aliceUnlockAfter), activeStakeAtBoundary);
    }

    function test_Donate_atUnlockBoundary_durationWindows_alignWithDelegatorBalanceAt() public {
        UniversalDelegator universalDelegator;
        uint48 aliceUnlockAfter;
        (universalDelegator,, aliceUnlockAfter,) = _prepareAdjacentUnlockWithdrawalsWithUniversalNetwork();
        uint256 donation = 20;
        uint256 claimableBefore = vault.withdrawalsOf(0, alice);
        uint256 expectedNewActiveWithdrawals;
        uint256 expectedActiveStakeAfter;
        {
            uint256 curActiveWithdrawals = vault.activeWithdrawals();
            uint256 activeStakeBefore = vault.activeStake();
            uint256 expectedWithdrawalsDonated =
                donation.mulDiv(curActiveWithdrawals, activeStakeBefore + curActiveWithdrawals);
            expectedNewActiveWithdrawals = curActiveWithdrawals + expectedWithdrawalsDonated;
            expectedActiveStakeAfter = activeStakeBefore + donation - expectedWithdrawalsDonated;
        }

        collateral.transfer(address(rewards), donation);
        vm.startPrank(address(rewards));
        collateral.approve(address(vault), donation);
        VaultV2(address(vault)).donate(donation);
        vm.stopPrank();

        assertEq(vault.withdrawalsOf(0, alice), claimableBefore);
        assertEq(vault.activeWithdrawalSharesOfAt(alice, aliceUnlockAfter), 0);
        assertEq(vault.activeWithdrawalSharesOfAt(bob, aliceUnlockAfter), 30);
        assertEq(vault.activeWithdrawalSharesForAt(0, aliceUnlockAfter), 30);
        assertEq(vault.activeWithdrawalSharesForAt(1, aliceUnlockAfter), 0);
        assertEq(vault.activeWithdrawalsForAt(0, aliceUnlockAfter), expectedNewActiveWithdrawals);
        assertEq(vault.activeWithdrawalsForAt(1, aliceUnlockAfter), 0);
        assertEq(
            universalDelegator.getBalanceAt(0, 0, aliceUnlockAfter),
            expectedActiveStakeAfter + expectedNewActiveWithdrawals
        );
        assertEq(universalDelegator.getBalanceAt(0, 1, aliceUnlockAfter), expectedActiveStakeAfter);
    }

    function test_ActiveWithdrawalShares_matchesSumOfCurrentUnclaimableRequestShares_throughLifecycle() public {
        vault = _getUniversalVault(7 days);

        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;

        _assertActiveWithdrawalSharesMatchesCurrentUnclaimableRequestShares(accounts);
        _assertActiveWithdrawalSharesOfMatchesCurrentUnclaimableRequestShares(accounts);

        _deposit(alice, 100);
        _deposit(bob, 100);

        _assertActiveWithdrawalSharesMatchesCurrentUnclaimableRequestShares(accounts);
        _assertActiveWithdrawalSharesOfMatchesCurrentUnclaimableRequestShares(accounts);

        vm.warp(block.timestamp + 1);
        _withdraw(alice, 40);

        _assertActiveWithdrawalSharesMatchesCurrentUnclaimableRequestShares(accounts);
        _assertActiveWithdrawalSharesOfMatchesCurrentUnclaimableRequestShares(accounts);

        vm.warp(block.timestamp + 1);
        _withdraw(bob, 30);

        _assertActiveWithdrawalSharesMatchesCurrentUnclaimableRequestShares(accounts);
        _assertActiveWithdrawalSharesOfMatchesCurrentUnclaimableRequestShares(accounts);

        uint256 donation = 20;
        collateral.transfer(address(rewards), donation);
        vm.startPrank(address(rewards));
        collateral.approve(address(vault), donation);
        VaultV2(address(vault)).donate(donation);
        vm.stopPrank();

        _assertActiveWithdrawalSharesMatchesCurrentUnclaimableRequestShares(accounts);
        _assertActiveWithdrawalSharesOfMatchesCurrentUnclaimableRequestShares(accounts);

        uint48 aliceUnlockAfter = vault.withdrawalUnlockAt(0, alice);
        vm.warp(aliceUnlockAfter);

        _assertActiveWithdrawalSharesMatchesCurrentUnclaimableRequestShares(accounts);
        _assertActiveWithdrawalSharesOfMatchesCurrentUnclaimableRequestShares(accounts);

        _claim(alice, 0);

        _assertActiveWithdrawalSharesMatchesCurrentUnclaimableRequestShares(accounts);
        _assertActiveWithdrawalSharesOfMatchesCurrentUnclaimableRequestShares(accounts);

        uint48 bobUnlockAfter = vault.withdrawalUnlockAt(0, bob);
        vm.warp(bobUnlockAfter);

        _assertActiveWithdrawalSharesMatchesCurrentUnclaimableRequestShares(accounts);
        _assertActiveWithdrawalSharesOfMatchesCurrentUnclaimableRequestShares(accounts);

        _claim(bob, 0);

        _assertActiveWithdrawalSharesMatchesCurrentUnclaimableRequestShares(accounts);
        _assertActiveWithdrawalSharesOfMatchesCurrentUnclaimableRequestShares(accounts);
    }

    function test_Donate_withoutClaimableWithdrawals_keepsCurrentBucketAndUpdatesActive() public {
        vault = _getUniversalVault(7 days);
        _deposit(alice, 100);

        vm.warp(block.timestamp + 1);
        _withdraw(alice, 40);

        uint256 donation = 20;
        uint256 bucketBefore = _latestWithdrawalBucket();
        uint256 activeBefore = vault.activeWithdrawals();
        uint256 activeStakeBefore = vault.activeStake();
        uint256 balanceBefore = collateral.balanceOf(address(vault));
        uint256 totalStakeBefore = vault.totalStake();
        uint256 aliceSharesBefore = vault.withdrawalSharesOf(0, alice);
        uint256 totalWithdrawalSharesBefore = vault.withdrawalShares(bucketBefore);
        uint256 expectedWithdrawalsDonated = donation.mulDiv(activeBefore, activeStakeBefore + activeBefore);
        uint256 expectedActiveAfter = activeBefore + expectedWithdrawalsDonated;
        uint256 expectedAliceWithdrawalsAfter =
            ERC4626Math.previewRedeem(aliceSharesBefore, expectedActiveAfter, totalWithdrawalSharesBefore);

        collateral.transfer(address(rewards), donation);
        vm.startPrank(address(rewards));
        collateral.approve(address(vault), donation);
        VaultV2(address(vault)).donate(donation);
        vm.stopPrank();

        assertEq(_latestWithdrawalBucket(), bucketBefore);
        assertEq(vault.withdrawals(bucketBefore), expectedActiveAfter);
        assertEq(vault.withdrawals(bucketBefore + 1), 0);
        assertEq(vault.withdrawalsOf(0, alice), expectedAliceWithdrawalsAfter);
        assertEq(vault.activeStake(), activeStakeBefore + donation - expectedWithdrawalsDonated);
        assertEq(vault.totalStake(), totalStakeBefore + donation);
        assertEq(collateral.balanceOf(address(vault)), balanceBefore + donation);
    }

    function test_DepositRevertInsufficientDeposit() public {
        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        vm.startPrank(alice);
        vm.expectRevert(IVaultV2.InsufficientAmount.selector);
        vault.deposit(alice, 0);
        vm.stopPrank();
    }

    function test_WithdrawTwice(uint256 amount1, uint256 amount2, uint256 amount3) public virtual {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount3, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2 + amount3);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        // uint48 epochDuration = 1;
        vault = _getVault(1);

        (, uint256 shares) = _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 burnedShares = amount2 * (shares + 10 ** 0) / (amount1 + 1);
        uint256 mintedShares = amount2 * 10 ** 0;
        (uint256 burnedShares_, uint256 mintedShares_) = _withdraw(alice, amount2);
        assertEq(burnedShares_, burnedShares);
        assertEq(mintedShares_, mintedShares);

        assertEq(vault.totalStake(), _expectedTotalStake(uint48(blockTimestamp)));
        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1), ""), shares);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), ""), shares - burnedShares);
        assertEq(vault.activeShares(), shares - burnedShares);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), ""), amount1);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), ""), amount1 - amount2);
        assertEq(vault.activeStake(), amount1 - amount2);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1), ""), shares);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp), ""), shares - burnedShares);
        assertEq(vault.activeSharesOf(alice), shares - burnedShares);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1), ""), amount1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp), ""), amount1 - amount2);
        assertEq(vault.activeBalanceOf(alice), amount1 - amount2);
        uint256 lastBucket = _latestWithdrawalBucket();
        assertEq(vault.withdrawals(lastBucket), amount2);
        assertEq(vault.withdrawalShares(lastBucket), mintedShares);
        assertEq(vault.withdrawalSharesOf(0, alice), amount2);

        shares -= burnedShares;

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        burnedShares = amount3 * (shares + 10 ** 0) / (amount1 - amount2 + 1);
        mintedShares = amount3 * 10 ** 0;
        (burnedShares_, mintedShares_) = _withdraw(alice, amount3);
        assertEq(burnedShares_, burnedShares);
        assertEq(mintedShares_, mintedShares);

        assertEq(vault.totalStake(), _expectedTotalStake(uint48(blockTimestamp)));
        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1), ""), shares);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), ""), shares - burnedShares);
        assertEq(vault.activeShares(), shares - burnedShares);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), ""), amount1 - amount2);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), ""), amount1 - amount2 - amount3);
        assertEq(vault.activeStake(), amount1 - amount2 - amount3);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1), ""), shares);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp), ""), shares - burnedShares);
        assertEq(vault.activeSharesOf(alice), shares - burnedShares);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1), ""), amount1 - amount2);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp), ""), amount1 - amount2 - amount3);
        assertEq(vault.activeBalanceOf(alice), amount1 - amount2 - amount3);
        assertEq(vault.withdrawals(lastBucket), amount2 + amount3);
        assertEq(vault.withdrawalShares(lastBucket), amount2 + amount3);
        assertEq(vault.withdrawalSharesOf(1, alice), amount3);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(vault.totalStake(), _expectedTotalStake(uint48(blockTimestamp)));
    }

    function test_WithdrawUnlockAfterAndLength(uint256 amount1, uint256 amount2, uint256 amount3) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount3, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2 + amount3);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 7;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 3;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        assertEq(vault.withdrawalsOfLength(alice), 1);
        assertEq(vault.withdrawalUnlockAt(0, alice), uint48(blockTimestamp + epochDuration));

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount3);

        assertEq(vault.withdrawalsOfLength(alice), 2);
        assertEq(vault.withdrawalUnlockAt(1, alice), uint48(blockTimestamp + epochDuration));
    }

    function test_WithdrawalsOf_NonMigrated_UsesCurrentPathForAnyIndex() public {
        uint48 epochDuration = 7;
        vault = _getVault(epochDuration);

        _deposit(alice, 100);
        _withdraw(alice, 10);

        assertGt(vault.withdrawalsOf(0, alice), 0);
        assertEq(vault.withdrawalsOf(type(uint256).max, alice), 0);
    }

    function test_WithdrawRecordsClaimer(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, amount1);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 5;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.startPrank(alice);
        (, uint256 mintedShares) = vault.withdraw(bob, amount2);
        vm.stopPrank();

        assertEq(vault.withdrawalsOfLength(alice), 0);
        assertEq(vault.withdrawalsOfLength(bob), 1);
        assertEq(vault.withdrawalUnlockAt(0, bob), uint48(blockTimestamp + epochDuration));
        assertEq(vault.withdrawalSharesOf(0, bob), mintedShares);
    }

    function test_WithdrawRevertInvalidClaimer(uint256 amount1) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        vm.expectRevert(IVaultV2.InvalidAddress.selector);
        vm.startPrank(alice);
        vault.withdraw(address(0), amount1);
        vm.stopPrank();
    }

    function test_WithdrawRevertInsufficientWithdrawal(uint256 amount1) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        vm.expectRevert(IVaultV2.InsufficientAmount.selector);
        _withdraw(alice, 0);
    }

    function test_WithdrawRevertTooMuchWithdraw(uint256 amount1) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        vm.expectRevert(IVaultV2.TooMuchWithdraw.selector);
        _withdraw(alice, amount1 + 1);
    }

    function test_RedeemTwice(uint256 amount1, uint256 amount2, uint256 amount3) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount3, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2 + amount3);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        // uint48 epochDuration = 1;
        vault = _getVault(1);

        (, uint256 shares) = _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 withdrawnAssets2 = amount2 * (amount1 + 1) / (shares + 10 ** 0);
        uint256 mintedShares = amount2 * 10 ** 0;
        (uint256 withdrawnAssets_, uint256 mintedShares_) = _redeem(alice, amount2);
        assertEq(withdrawnAssets_, withdrawnAssets2);
        assertEq(mintedShares_, mintedShares);

        assertEq(vault.totalStake(), _expectedTotalStake(uint48(blockTimestamp)));
        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1), ""), shares);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), ""), shares - amount2);
        assertEq(vault.activeShares(), shares - amount2);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), ""), amount1);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), ""), amount1 - withdrawnAssets2);
        assertEq(vault.activeStake(), amount1 - withdrawnAssets2);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1), ""), shares);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp), ""), shares - amount2);
        assertEq(vault.activeSharesOf(alice), shares - amount2);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1), ""), amount1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp), ""), amount1 - withdrawnAssets2);
        assertEq(vault.activeBalanceOf(alice), amount1 - withdrawnAssets2);
        uint256 lastBucket = _latestWithdrawalBucket();
        assertEq(vault.withdrawals(lastBucket), withdrawnAssets2);
        assertEq(vault.withdrawalShares(lastBucket), mintedShares);
        assertEq(vault.withdrawalSharesOf(0, alice), mintedShares);

        shares -= amount2;

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 withdrawnAssets3 = amount3 * (amount1 - withdrawnAssets2 + 1) / (shares + 10 ** 0);
        mintedShares = amount3 * 10 ** 0;
        (withdrawnAssets_, mintedShares_) = _redeem(alice, amount3);
        assertEq(withdrawnAssets_, withdrawnAssets3);
        assertEq(mintedShares_, mintedShares);

        assertEq(vault.totalStake(), _expectedTotalStake(uint48(blockTimestamp)));
        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1), ""), shares);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), ""), shares - amount3);
        assertEq(vault.activeShares(), shares - amount3);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), ""), amount1 - withdrawnAssets2);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), ""), amount1 - withdrawnAssets2 - withdrawnAssets3);
        assertEq(vault.activeStake(), amount1 - withdrawnAssets2 - withdrawnAssets3);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1), ""), shares);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp), ""), shares - amount3);
        assertEq(vault.activeSharesOf(alice), shares - amount3);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1), ""), amount1 - withdrawnAssets2);
        assertEq(
            vault.activeBalanceOfAt(alice, uint48(blockTimestamp), ""), amount1 - withdrawnAssets2 - withdrawnAssets3
        );
        assertEq(vault.activeBalanceOf(alice), amount1 - withdrawnAssets2 - withdrawnAssets3);
        assertEq(vault.withdrawals(lastBucket), withdrawnAssets2 + withdrawnAssets3);
        assertEq(vault.withdrawalShares(lastBucket), withdrawnAssets2 + withdrawnAssets3);
        assertEq(vault.withdrawalSharesOf(1, alice), withdrawnAssets3);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(vault.totalStake(), _expectedTotalStake(uint48(blockTimestamp)));
    }

    function test_RedeemRevertInvalidClaimer(uint256 amount1) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        vm.expectRevert(IVaultV2.InvalidAddress.selector);
        vm.startPrank(alice);
        vault.redeem(address(0), amount1);
        vm.stopPrank();
    }

    function test_RedeemRevertInsufficientRedeemption(uint256 amount1) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        vm.expectRevert(IVaultV2.InsufficientAmount.selector);
        _redeem(alice, 0);
    }

    function test_RedeemRevertWhenWithdrawnAssetsRoundDownToZeroAfterSlash() public {
        (vault,, slasher) = _getUniversalVaultAndDelegatorAndSlasher(7 days);
        _deposit(alice, 100);

        vm.prank(address(slasher));
        VaultV2(address(vault)).onSlash(100, false);

        vm.startPrank(alice);
        vm.expectRevert(IVaultV2.InsufficientAmount.selector);
        vault.redeem(alice, 1);
        vm.stopPrank();
    }

    function test_RedeemRevertTooMuchRedeem(uint256 amount1) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        vm.expectRevert(IVaultV2.TooMuchRedeem.selector);
        _redeem(alice, amount1 + 1);
    }

    function test_Claim(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        uint256 tokensBefore = collateral.balanceOf(address(vault));
        uint256 tokensBeforeAlice = collateral.balanceOf(alice);
        assertEq(_claim(alice, 0), amount2);
        assertEq(tokensBefore - collateral.balanceOf(address(vault)), amount2);
        assertEq(collateral.balanceOf(alice) - tokensBeforeAlice, amount2);

        assertEq(vault.isWithdrawalsClaimed(0, alice), true);
    }

    function test_ClaimRevertInvalidRecipient(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        vm.startPrank(alice);
        vm.expectRevert(IVaultV2.InvalidAddress.selector);
        vault.claim(address(0), 0);
        vm.stopPrank();
    }

    function test_ClaimRevertInvalidIndex(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        vm.expectRevert(IVaultV2.InsufficientAmount.selector);
        _claim(alice, 10);
    }

    function test_ClaimRevertAlreadyClaimed(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        _claim(alice, 0);

        vm.expectRevert(IVaultV2.AlreadyClaimed.selector);
        _claim(alice, 0);
    }

    function test_ClaimRevertWithdrawalNotMatured(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 7;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        vm.expectRevert(IVaultV2.WithdrawalNotMatured.selector);
        _claim(alice, 0);
    }

    function test_ClaimBatch(uint256 amount1, uint256 amount2, uint256 amount3) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount3, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2 + amount3);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount3);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        uint256[] memory indexes = new uint256[](2);
        indexes[0] = 0;
        indexes[1] = 1;

        uint256 tokensBefore = collateral.balanceOf(address(vault));
        uint256 tokensBeforeAlice = collateral.balanceOf(alice);
        assertEq(_claimBatch(alice, indexes), amount2 + amount3);
        assertEq(tokensBefore - collateral.balanceOf(address(vault)), amount2 + amount3);
        assertEq(collateral.balanceOf(alice) - tokensBeforeAlice, amount2 + amount3);

        assertEq(vault.isWithdrawalsClaimed(0, alice), true);
    }

    function test_ClaimBatchRevertInvalidRecipient(uint256 amount1, uint256 amount2, uint256 amount3) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount3, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2 + amount3);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount3);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        uint256[] memory indexes = new uint256[](2);
        indexes[0] = 0;
        indexes[1] = 1;

        vm.expectRevert(IVaultV2.InvalidAddress.selector);
        vm.startPrank(alice);
        vault.claimBatch(address(0), indexes);
        vm.stopPrank();
    }

    function test_ClaimBatchEmptyIndexesNoop(uint256 amount1, uint256 amount2, uint256 amount3) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount3, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2 + amount3);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount3);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        uint256[] memory indexes = new uint256[](0);
        assertEq(_claimBatch(alice, indexes), 0);
        assertEq(vault.isWithdrawalsClaimed(0, alice), false);
    }

    function test_ClaimBatchRevertInvalidEpoch(uint256 amount1, uint256 amount2, uint256 amount3) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount3, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2 + amount3);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount3);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        uint256[] memory indexes = new uint256[](2);
        indexes[0] = 0;
        indexes[1] = 2;

        vm.expectRevert(IVaultV2.InsufficientAmount.selector);
        _claimBatch(alice, indexes);
    }

    function test_ClaimBatchRevertAlreadyClaimed(uint256 amount1, uint256 amount2, uint256 amount3) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount3, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2 + amount3);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount3);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        uint256[] memory indexes = new uint256[](2);
        indexes[0] = 0;
        indexes[1] = 0;

        vm.expectRevert(IVaultV2.AlreadyClaimed.selector);
        _claimBatch(alice, indexes);
    }

    function test_ClaimBatchRevertInsufficientClaim(uint256 amount1, uint256 amount2, uint256 amount3) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount3, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2 + amount3);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount3);

        uint256[] memory indexes = new uint256[](2);
        indexes[0] = 0;
        indexes[1] = 1;

        vm.expectRevert(IVaultV2.WithdrawalNotMatured.selector);
        _claimBatch(alice, indexes);
    }

    function test_Claim_deallocatesAdaptersWhenNeeded() public {
        vault = _getUniversalVault(7 days);

        MockMorphoVault morphoVault = new MockMorphoVault(address(collateral));
        MockMorphoBorrowAdapter adapter =
            new MockMorphoBorrowAdapter(address(vault), address(collateral), address(morphoVault), address(rewards));
        adapterRegistry.whitelistAdapter(address(adapter));

        uint256 minTimestamp = uint256(vault.epochDuration()) + 1;
        if (block.timestamp < minTimestamp) {
            vm.warp(minTimestamp);
        }
        _grantAddAdapterRole(alice, alice);
        vm.prank(alice);
        VaultV2(address(vault)).setAdapterLimit(address(adapter), type(uint208).max);

        _deposit(alice, 100);
        assertEq(vault.adapterAllocated(address(adapter)), 100);
        assertEq(collateral.balanceOf(address(vault)), 0);

        vm.warp(block.timestamp + 1);
        _withdraw(alice, 60);
        assertEq(collateral.balanceOf(address(vault)), 0);
        assertEq(vault.adapterAllocated(address(adapter)), 100);

        vm.warp(block.timestamp + 8 days);

        uint256 aliceBalanceBefore = collateral.balanceOf(alice);
        assertEq(_claim(alice, 0), 60);
        assertEq(collateral.balanceOf(alice) - aliceBalanceBefore, 60);
        assertEq(vault.adapterAllocated(address(adapter)), 40);
        assertEq(collateral.balanceOf(address(vault)), 0);
    }

    function test_Claim_revertsWhenAdaptersCannotDeallocateEnough() public {
        vault = _getUniversalVault(7 days);

        MockMorphoVault morphoVault = new MockMorphoVault(address(collateral));
        MockMorphoBorrowAdapter adapter =
            new MockMorphoBorrowAdapter(address(vault), address(collateral), address(morphoVault), address(rewards));
        adapterRegistry.whitelistAdapter(address(adapter));

        uint256 minTimestamp = uint256(vault.epochDuration()) + 1;
        if (block.timestamp < minTimestamp) {
            vm.warp(minTimestamp);
        }
        _grantAddAdapterRole(alice, alice);
        vm.prank(alice);
        VaultV2(address(vault)).setAdapterLimit(address(adapter), type(uint208).max);

        _deposit(alice, 100);
        assertEq(vault.adapterAllocated(address(adapter)), 100);
        assertEq(collateral.balanceOf(address(vault)), 0);

        vm.warp(block.timestamp + 1);
        _withdraw(alice, 60);

        // Drain adapter liquidity so claim-time deallocation is insufficient.
        vm.prank(address(morphoVault));
        collateral.transfer(address(0xBEEF), 50);

        vm.warp(block.timestamp + 8 days);

        vm.expectRevert();
        _claim(alice, 0);
    }

    function test_TotalStakeUnlockBoundary(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, amount1);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 10;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        uint48 unlockAt = vault.withdrawalUnlockAt(0, alice);
        assertEq(unlockAt, uint48(blockTimestamp + epochDuration));
        assertEq(vault.totalStake(), amount1);

        vm.warp(uint256(unlockAt) - 1);
        vm.expectRevert(IVaultV2.WithdrawalNotMatured.selector);
        _claim(alice, 0);

        vm.warp(unlockAt);
        assertEq(vault.totalStake(), amount1 - amount2);
        assertEq(_claim(alice, 0), amount2);
    }

    function test_OnSlashAtUnlockAt_DoesNotSlashFreshlyMaturedWithdrawal() public {
        uint48 epochDuration = 10;
        vault = _getVault(epochDuration);

        _deposit(alice, 100);

        vm.warp(block.timestamp + 1);
        _withdraw(alice, 40);

        uint48 unlockAt = vault.withdrawalUnlockAt(0, alice);
        vm.warp(unlockAt);

        uint256 claimableBefore = vault.withdrawalsOf(0, alice);
        uint256 activeStakeBefore = vault.activeStake();
        assertEq(claimableBefore, 40);
        assertEq(activeStakeBefore, 60);

        vm.prank(vault.slasher());
        (uint256 slashedAmount,) = VaultV2(address(vault)).onSlash(10, false);
        assertEq(slashedAmount, 10);

        assertEq(vault.withdrawalsOf(0, alice), claimableBefore);
        assertEq(vault.activeStake(), activeStakeBefore - slashedAmount);
        assertEq(_claim(alice, 0), claimableBefore);
    }

    function test_OnSlashOneSecondBeforeUnlockAt_SlashesWithdrawalThenClaimsReducedAmount() public {
        uint48 epochDuration = 10;
        vault = _getVault(epochDuration);

        _deposit(alice, 100);

        vm.warp(block.timestamp + 1);
        _withdraw(alice, 40);

        uint48 unlockAt = vault.withdrawalUnlockAt(0, alice);
        vm.warp(uint256(unlockAt) - 1);

        uint256 claimableBefore = vault.withdrawalsOf(0, alice);
        uint256 activeStakeBefore = vault.activeStake();
        assertEq(claimableBefore, 40);
        assertEq(activeStakeBefore, 60);

        vm.prank(vault.slasher());
        (uint256 slashedAmount,) = VaultV2(address(vault)).onSlash(10, false);
        assertEq(slashedAmount, 10);

        uint256 claimableAfterSlash = vault.withdrawalsOf(0, alice);
        assertEq(claimableAfterSlash, 36);

        vm.warp(unlockAt);
        assertEq(_claim(alice, 0), claimableAfterSlash);
    }

    function test_SetDepositWhitelist() public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);
        assertEq(vault.depositWhitelist(), true);

        _setDepositWhitelist(alice, false);
        assertEq(vault.depositWhitelist(), false);
    }

    function test_SetDepositWhitelistRevertNotWhitelistedDepositor() public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        _deposit(alice, 1);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);

        vm.startPrank(alice);
        vm.expectRevert(IVaultV2.NotWhitelistedDepositor.selector);
        vault.deposit(alice, 1);
        vm.stopPrank();
    }

    function test_SetDepositWhitelistIdempotent() public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);

        _setDepositWhitelist(alice, true);
        assertEq(vault.depositWhitelist(), true);
    }

    function test_Multicall_executesCallsSequentially() public {
        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _grantDepositWhitelistSetRole(alice, alice);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(VaultV2.setDepositWhitelist, (true));
        calls[1] = abi.encodeCall(VaultV2.setDepositWhitelist, (false));

        vm.prank(alice);
        VaultV2(address(vault)).multicall(calls);

        assertEq(vault.depositWhitelist(), false);
    }

    function test_Multicall_bubblesRevertReason() public {
        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(VaultV2.setDepositWhitelist, (true));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, owner, DEPOSIT_WHITELIST_SET_ROLE
            )
        );
        VaultV2(address(vault)).multicall(calls);
    }

    function test_SetDepositorWhitelistStatus() public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);

        _grantDepositorWhitelistRole(alice, alice);

        _setDepositorWhitelistStatus(alice, bob, true);
        assertEq(vault.isDepositorWhitelisted(bob), true);

        _deposit(bob, 1);

        _setDepositWhitelist(alice, false);

        _deposit(bob, 1);
    }

    function test_SetDepositorWhitelistStatusReverts_ZeroAddress() public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);

        _grantDepositorWhitelistRole(alice, alice);

        vm.expectRevert(IVaultV2.InvalidAddress.selector);
        _setDepositorWhitelistStatus(alice, address(0), true);
    }

    function test_SetDepositorWhitelistStatusIdempotent() public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);

        _grantDepositorWhitelistRole(alice, alice);

        _setDepositorWhitelistStatus(alice, bob, true);

        _setDepositorWhitelistStatus(alice, bob, true);
        assertEq(vault.isDepositorWhitelisted(bob), true);
    }

    function test_SetIsDepositLimit() public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        _grantIsDepositLimitSetRole(alice, alice);
        _setIsDepositLimit(alice, true);
        assertEq(vault.isDepositLimit(), true);

        _setIsDepositLimit(alice, false);
        assertEq(vault.isDepositLimit(), false);
    }

    function test_SetIsDepositLimitIdempotent() public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        _grantIsDepositLimitSetRole(alice, alice);
        _setIsDepositLimit(alice, true);

        _setIsDepositLimit(alice, true);
        assertEq(vault.isDepositLimit(), true);
    }

    function test_SetDepositLimit(uint256 limit1, uint256 limit2, uint256 depositAmount) public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        _grantIsDepositLimitSetRole(alice, alice);
        _setIsDepositLimit(alice, true);
        assertEq(vault.depositLimit(), 0);

        limit1 = bound(limit1, 1, type(uint256).max);
        _grantDepositLimitSetRole(alice, alice);
        _setDepositLimit(alice, limit1);
        assertEq(vault.depositLimit(), limit1);

        limit2 = bound(limit2, 1, 1000 ether);
        vm.assume(limit2 != limit1);
        _setDepositLimit(alice, limit2);
        assertEq(vault.depositLimit(), limit2);

        depositAmount = bound(depositAmount, 1, limit2);
        _deposit(alice, depositAmount);
    }

    function test_SetDepositLimitToNull(uint256 limit1) public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        limit1 = bound(limit1, 1, type(uint256).max);
        _grantIsDepositLimitSetRole(alice, alice);
        _setIsDepositLimit(alice, true);
        _grantDepositLimitSetRole(alice, alice);
        _setDepositLimit(alice, limit1);

        _setIsDepositLimit(alice, false);

        _setDepositLimit(alice, 0);

        assertEq(vault.depositLimit(), 0);
    }

    function test_SetDepositLimitRevertDepositLimitReached(uint256 depositAmount, uint256 limit) public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        _deposit(alice, 1);

        limit = bound(limit, 2, 1000 ether);
        _grantIsDepositLimitSetRole(alice, alice);
        _setIsDepositLimit(alice, true);
        _grantDepositLimitSetRole(alice, alice);
        _setDepositLimit(alice, limit);

        depositAmount = bound(depositAmount, limit, 2000 ether);

        collateral.transfer(alice, depositAmount);
        vm.startPrank(alice);
        collateral.approve(address(vault), depositAmount);
        vm.expectRevert(IVaultV2.DepositLimitReached.selector);
        vault.deposit(alice, depositAmount);
        vm.stopPrank();
    }

    function test_SetDepositLimitIdempotent(uint256 limit) public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        limit = bound(limit, 1, type(uint256).max);
        _grantIsDepositLimitSetRole(alice, alice);
        _setIsDepositLimit(alice, true);
        _grantDepositLimitSetRole(alice, alice);
        _setDepositLimit(alice, limit);

        _setDepositLimit(alice, limit);
        assertEq(vault.depositLimit(), limit);
    }

    function test_MigrateReverts_TooLongDurationOnLegacyVault() public {
        VaultV2CoverageHarness harness = new VaultV2CoverageHarness();
        harness.setEpochDurationRaw(MAX_DURATION + 1);
        vm.expectRevert(IVaultV2.TooLongDuration.selector);
        harness.exposeMigrate("");
    }

    function testFuzz_OnSlash_arithmeticIsSafeUpToSupplyCap(
        uint256 activeStakeAmount,
        uint256 activeWithdrawalAmount,
        uint256 claimableWithdrawalAmount,
        uint256 slashAmount
    ) public {
        VaultV2CoverageHarness harness = new VaultV2CoverageHarness();
        Token mathCollateral = new Token("OverflowMath");
        uint256 availableSupply = SUPPLY_CAP - mathCollateral.totalSupply();

        activeStakeAmount = bound(activeStakeAmount, 0, availableSupply);
        activeWithdrawalAmount = bound(activeWithdrawalAmount, 0, availableSupply - activeStakeAmount);
        claimableWithdrawalAmount =
            bound(claimableWithdrawalAmount, 0, availableSupply - activeStakeAmount - activeWithdrawalAmount);
        slashAmount = bound(slashAmount, 0, availableSupply);
        vm.assume(activeStakeAmount + activeWithdrawalAmount > 0);

        uint48 timestamp = uint48(block.timestamp);
        uint48 epochDuration_ = 7 days;

        harness.setCollateralRaw(address(mathCollateral));
        harness.setBurnerRaw(address(0xBEEF));
        harness.setSlasherRaw(address(this));
        harness.setEpochDurationRaw(epochDuration_);
        harness.pushActiveStakeRaw(timestamp, activeStakeAmount);

        uint256 bucketWithdrawals = activeWithdrawalAmount + claimableWithdrawalAmount;
        if (bucketWithdrawals > 0) {
            harness.pushWithdrawalsRaw(0, timestamp, bucketWithdrawals);
            harness.pushWithdrawalSharesRaw(0, timestamp, bucketWithdrawals);
            harness.pushWithdrawalSharesCumulativeRaw(timestamp + epochDuration_, activeWithdrawalAmount);
        }

        deal(address(mathCollateral), address(harness), activeStakeAmount + bucketWithdrawals);

        uint256 slashableStake = activeStakeAmount + activeWithdrawalAmount;
        uint256 expectedSlashedAmount = Math.min(slashAmount, slashableStake);
        uint256 expectedActiveSlashed =
            expectedSlashedAmount > 0 ? expectedSlashedAmount.mulDiv(activeStakeAmount, slashableStake) : 0;
        uint256 expectedActiveStakeAfter = activeStakeAmount - expectedActiveSlashed;
        uint256 expectedActiveWithdrawalsAfter =
            activeWithdrawalAmount - (expectedSlashedAmount - expectedActiveSlashed);

        (uint256 slashedAmount, uint256 owedAmount) = harness.onSlash(slashAmount, false);

        assertEq(slashedAmount, expectedSlashedAmount);
        assertEq(owedAmount, 0);
        assertEq(harness.activeStake(), expectedActiveStakeAfter);
        assertEq(harness.activeWithdrawals(), expectedActiveWithdrawalsAfter);

        uint256 bucket = harness.withdrawalBucket();
        assertGe(harness.withdrawals(bucket), harness.activeWithdrawals());
        assertGe(harness.withdrawalShares(bucket), harness.activeWithdrawalShares());
        assertLe(harness.activeStake() + harness.activeWithdrawals(), availableSupply);
    }

    function testFuzz_Migrate_accountingSubtractionIsSafeUpToSupplyCap(
        uint256 depositAmount,
        uint256 firstWithdrawal,
        uint256 secondWithdrawal
    ) public {
        uint48 epochDuration_ = 10;
        uint256 maxDeposit = SUPPLY_CAP - collateral.totalSupply();

        depositAmount = bound(depositAmount, 2, maxDeposit);
        firstWithdrawal = bound(firstWithdrawal, 0, depositAmount);
        secondWithdrawal = bound(secondWithdrawal, 0, depositAmount - firstWithdrawal);

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
        (IVaultV2 legacyVault,,) = _createInitializedVaultWithOwner(
            epochDuration_,
            networkLimitSetRoleHolders,
            operatorNetworkSharesSetRoleHolders,
            1,
            address(0xdEaD),
            false,
            false,
            0,
            address(this)
        );

        deal(address(collateral), alice, depositAmount);
        vm.startPrank(alice);
        collateral.approve(address(legacyVault), depositAmount);
        legacyVault.deposit(alice, depositAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + 1);
        if (firstWithdrawal > 0) {
            vm.prank(alice);
            legacyVault.withdraw(alice, firstWithdrawal);
        }

        vm.warp(block.timestamp + epochDuration_ + 1);
        if (secondWithdrawal > 0) {
            vm.prank(alice);
            legacyVault.withdraw(alice, secondWithdrawal);
        }

        bytes memory migrateData = abi.encode(_buildMigrateParams(epochDuration_));
        vaultFactory.migrate(address(legacyVault), vaultFactory.lastVersion(), migrateData);

        IVaultV2 migratedVault = IVaultV2(address(legacyVault));
        int256 unclaimedRaw = vaultTestHelper.unclaimedRaw(address(migratedVault));

        assertGe(unclaimedRaw, 0);
        assertEq(
            collateral.balanceOf(address(migratedVault)),
            migratedVault.activeStake() + migratedVault.activeWithdrawals() + uint256(unclaimedRaw)
        );
        assertLe(migratedVault.activeStake() + migratedVault.activeWithdrawals() + uint256(unclaimedRaw), SUPPLY_CAP);
    }

    function test_MigrateWithdrawals_FactoryUpgradePath() public {
        uint48 epochDuration = 10;

        MigrateWithdrawalsState memory state;
        state.blockTimestamp = vm.getBlockTimestamp();
        state.blockTimestamp = state.blockTimestamp + 1_720_700_948;
        vm.warp(state.blockTimestamp);

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
        uint48 vetoDuration = epochDuration > 1 ? 1 : 0;
        bytes memory vetoSlasherParams = abi.encode(
            IVetoSlasher.InitParams({
                baseParams: IBaseSlasher.BaseParams({isBurnerHook: false}),
                vetoDuration: vetoDuration,
                resolverSetEpochsDelay: uint48(epochDuration * 3)
            })
        );
        (IVaultV2 vault_,,) = _createInitializedVaultWithOwnerAndSlasher(
            epochDuration,
            networkLimitSetRoleHolders,
            operatorNetworkSharesSetRoleHolders,
            1,
            address(0xdEaD),
            false,
            false,
            0,
            address(this),
            1,
            vetoSlasherParams
        );
        VaultV1 vaultV1 = VaultV1(address(vault_));
        vault = IVaultV2(address(vaultV1));
        address oldSlasher = vaultV1.slasher();

        state.aliceDeposit = 1000;
        state.bobDeposit = 500;
        _deposit(alice, state.aliceDeposit);
        _deposit(bob, state.bobDeposit);

        state.aliceWithdrawEpoch0 = 200;
        state.bobWithdrawEpoch0 = 100;
        _withdraw(alice, state.aliceWithdrawEpoch0);
        _withdraw(bob, state.bobWithdrawEpoch0);

        state.epoch1Start = state.blockTimestamp + epochDuration;
        vm.warp(state.epoch1Start + 1);

        state.aliceWithdrawEpoch1 = 150;
        state.bobWithdrawEpoch1 = 60;
        _withdraw(alice, state.aliceWithdrawEpoch1);
        _withdraw(bob, state.bobWithdrawEpoch1);

        state.epoch2Start = state.blockTimestamp + 2 * epochDuration;
        vm.warp(state.epoch2Start + 1);

        state.epoch1Withdrawals = state.aliceWithdrawEpoch0 + state.bobWithdrawEpoch0;
        state.epoch2Withdrawals = state.aliceWithdrawEpoch1 + state.bobWithdrawEpoch1;
        state.expectedAliceEpoch1 =
            Math.mulDiv(state.aliceWithdrawEpoch0, state.epoch1Withdrawals + 1, state.epoch1Withdrawals + 1);

        vm.startPrank(alice);
        assertEq(vault.claim(alice, 1), state.expectedAliceEpoch1);
        vm.stopPrank();

        state.migrateTimestamp = state.epoch2Start + epochDuration / 2;
        vm.warp(state.migrateTimestamp);

        bytes memory migrateData = abi.encode(_buildMigrateParams(epochDuration));
        vaultFactory.migrate(address(vaultV1), vaultFactory.lastVersion(), migrateData);

        IVaultV2 vaultV2 = IVaultV2(address(vaultV1));
        _assertMigrationState(vaultV2, oldSlasher);
        assertEq(VaultV2(address(vaultV2)).name(), VAULT_NAME);
        assertEq(VaultV2(address(vaultV2)).symbol(), VAULT_SYMBOL);

        uint256 legacyEpochIndex = (state.migrateTimestamp - state.blockTimestamp) / epochDuration;
        state.nextEpochStart = uint48(
            state.blockTimestamp + ((state.migrateTimestamp - state.blockTimestamp) / epochDuration + 1) * epochDuration
        );
        uint48 postMigrateUnlockAfter = uint48(state.migrateTimestamp + epochDuration);

        assertEq(vaultTestHelper.withdrawalSharesCumulativeLength(address(vaultV2)), 2);

        {
            (uint48 prefixKey0, uint256 prefixVal0) = vaultTestHelper.withdrawalSharesCumulativeAt(address(vaultV2), 0);
            assertEq(prefixKey0, state.nextEpochStart);
            assertEq(prefixVal0, state.epoch2Withdrawals);
        }

        {
            (uint48 prefixKey1, uint256 prefixVal1) = vaultTestHelper.withdrawalSharesCumulativeAt(address(vaultV2), 1);
            assertEq(prefixKey1, postMigrateUnlockAfter);
            assertEq(prefixVal1, state.epoch2Withdrawals);
        }

        assertEq(vaultTestHelper.unlockToBucketLength(address(vaultV2)), 0);

        assertEq(vaultV2.withdrawalsOfLength(bob), legacyEpochIndex + 2);
        assertEq(vaultV2.withdrawalsOfLength(alice), legacyEpochIndex + 2);

        {
            assertEq(vaultV2.withdrawalUnlockAt(legacyEpochIndex, bob), state.nextEpochStart);
            assertEq(vaultV2.withdrawalUnlockAt(legacyEpochIndex, alice), state.nextEpochStart);
            assertEq(vaultV2.withdrawalUnlockAt(legacyEpochIndex + 1, bob), postMigrateUnlockAfter);

            assertEq(vaultTestHelper.unlockToBucketLength(address(vaultV2)), 0);
        }

        state.expectedBobEpoch1 =
            Math.mulDiv(state.bobWithdrawEpoch0, state.epoch1Withdrawals + 1, state.epoch1Withdrawals + 1);
        state.expectedAliceEpoch2 =
            Math.mulDiv(state.aliceWithdrawEpoch1, state.epoch2Withdrawals + 1, state.epoch2Withdrawals + 1);
        state.expectedBobEpoch2 =
            Math.mulDiv(state.bobWithdrawEpoch1, state.epoch2Withdrawals + 1, state.epoch2Withdrawals + 1);

        assertEq(vaultV2.withdrawalSharesOf(legacyEpochIndex - 1, bob), state.bobWithdrawEpoch0);
        assertEq(vaultV2.withdrawalSharesOf(legacyEpochIndex, bob), state.expectedBobEpoch2);
        assertEq(vaultV2.withdrawalSharesOf(legacyEpochIndex, alice), state.expectedAliceEpoch2);

        assertEq(vaultV2.withdrawalsOf(legacyEpochIndex - 1, bob), state.expectedBobEpoch1);
        assertEq(vaultV2.withdrawalsOf(legacyEpochIndex, bob), state.expectedBobEpoch2);
        assertEq(vaultV2.withdrawalsOf(legacyEpochIndex, alice), state.expectedAliceEpoch2);

        vm.startPrank(bob);
        vm.expectRevert(IVaultV2.WithdrawalNotMatured.selector);
        vaultV2.claim(bob, legacyEpochIndex);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(IVaultV2.WithdrawalNotMatured.selector);
        vaultV2.claim(alice, legacyEpochIndex);
        vm.stopPrank();

        uint256 bobBalanceBefore = collateral.balanceOf(bob);
        vm.startPrank(bob);
        vaultV2.claim(bob, legacyEpochIndex - 1);
        vm.stopPrank();
        assertEq(collateral.balanceOf(bob) - bobBalanceBefore, state.expectedBobEpoch1);

        vm.warp(uint256(state.nextEpochStart) + 1);

        bobBalanceBefore = collateral.balanceOf(bob);
        vm.startPrank(bob);
        vaultV2.claim(bob, legacyEpochIndex);
        vm.stopPrank();
        assertEq(collateral.balanceOf(bob) - bobBalanceBefore, state.expectedBobEpoch2);

        uint256 aliceBalanceBefore = collateral.balanceOf(alice);
        vm.startPrank(alice);
        vaultV2.claim(alice, legacyEpochIndex);
        vm.stopPrank();
        assertEq(collateral.balanceOf(alice) - aliceBalanceBefore, state.expectedAliceEpoch2);
    }

    function test_MigrateWithdrawals_ClaimAfterUpgrade() public {
        uint48 epochDuration = 5;

        MigrateClaimAfterUpgradeState memory state;
        state.blockTimestamp = vm.getBlockTimestamp();
        state.blockTimestamp = state.blockTimestamp + 1_720_700_948;
        vm.warp(state.blockTimestamp);

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
        (IVaultV2 vault_,,) = _createInitializedVaultWithOwner(
            epochDuration,
            networkLimitSetRoleHolders,
            operatorNetworkSharesSetRoleHolders,
            1,
            address(0xdEaD),
            false,
            false,
            0,
            address(this)
        );
        VaultV1 vaultV1 = VaultV1(address(vault_));
        vault = IVaultV2(address(vaultV1));
        address oldSlasher = vaultV1.slasher();

        state.aliceDeposit = 1000;
        _deposit(alice, state.aliceDeposit);

        state.withdrawEpoch0 = 250;
        _withdraw(alice, state.withdrawEpoch0);

        state.epoch1Start = state.blockTimestamp + epochDuration;
        vm.warp(state.epoch1Start + 1);

        state.withdrawEpoch1 = 180;
        _withdraw(alice, state.withdrawEpoch1);

        state.epoch2Start = state.blockTimestamp + 2 * epochDuration;
        vm.warp(state.epoch2Start + epochDuration / 2);

        bytes memory migrateData = abi.encode(_buildMigrateParams(epochDuration));
        vaultFactory.migrate(address(vaultV1), vaultFactory.lastVersion(), migrateData);

        IVaultV2 vaultV2 = IVaultV2(address(vaultV1));
        _assertMigrationState(vaultV2, oldSlasher);

        uint256 legacyEpochIndex = (state.epoch2Start + epochDuration / 2 - state.blockTimestamp) / epochDuration;

        state.expectedEpoch1 = Math.mulDiv(state.withdrawEpoch0, state.withdrawEpoch0 + 1, state.withdrawEpoch0 + 1);
        state.expectedEpoch2 = Math.mulDiv(state.withdrawEpoch1, state.withdrawEpoch1 + 1, state.withdrawEpoch1 + 1);

        vm.startPrank(alice);
        vm.expectRevert(IVaultV2.WithdrawalNotMatured.selector);
        vaultV2.claim(alice, legacyEpochIndex);
        vm.stopPrank();

        uint256 aliceBalanceBefore = collateral.balanceOf(alice);
        vm.startPrank(alice);
        vaultV2.claim(alice, legacyEpochIndex - 1);
        vm.stopPrank();
        assertEq(collateral.balanceOf(alice) - aliceBalanceBefore, state.expectedEpoch1);
        assertEq(vaultV2.isWithdrawalsClaimed(legacyEpochIndex - 1, alice), true);

        uint48 firstUnlockAfter = vaultV2.withdrawalUnlockAt(legacyEpochIndex, alice);
        state.nextEpochStart = firstUnlockAfter;
        vm.warp(uint256(state.nextEpochStart) + 1);

        aliceBalanceBefore = collateral.balanceOf(alice);
        vm.startPrank(alice);
        vaultV2.claim(alice, legacyEpochIndex);
        vm.stopPrank();
        assertEq(collateral.balanceOf(alice) - aliceBalanceBefore, state.expectedEpoch2);
        assertEq(vaultV2.isWithdrawalsClaimed(legacyEpochIndex, alice), true);
    }

    function test_MigrateWithdrawals_LegacyBucketAndInsufficientWithdrawal() public {
        uint48 epochDuration = 10;
        uint256 blockTimestamp = vm.getBlockTimestamp() + 1_720_700_948;
        vm.warp(blockTimestamp);

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;

        (IVaultV2 vault_,,) = _createInitializedVaultWithOwner(
            epochDuration,
            networkLimitSetRoleHolders,
            operatorNetworkSharesSetRoleHolders,
            1,
            address(0xdEaD),
            false,
            false,
            0,
            address(this)
        );
        VaultV1 vaultV1 = VaultV1(address(vault_));
        vault = IVaultV2(address(vaultV1));

        _deposit(bob, 500);
        _withdraw(bob, 100);

        vm.warp(blockTimestamp + epochDuration + 1);
        _withdraw(bob, 60);

        uint256 migrateTimestamp = blockTimestamp + 2 * epochDuration + epochDuration / 2;
        vm.warp(migrateTimestamp);

        bytes memory migrateData = abi.encode(_buildMigrateParams(epochDuration));
        vaultFactory.migrate(address(vaultV1), vaultFactory.lastVersion(), migrateData);

        IVaultV2 vaultV2 = IVaultV2(address(vaultV1));
        uint256 legacyEpochIndex = (migrateTimestamp - blockTimestamp) / epochDuration;
        uint48 expectedUnlockAfter = uint48(blockTimestamp + (legacyEpochIndex + 1) * epochDuration);
        uint256 expectedLegacyCurrentEpochWithdrawals = 60;
        uint256 expectedLegacyPrevEpochWithdrawals = 100;

        vm.startPrank(alice);
        vm.expectRevert(IVaultV2.InsufficientAmount.selector);
        vaultV2.claim(alice, legacyEpochIndex - 1);
        vm.stopPrank();

        assertEq(vaultV2.withdrawals(0), expectedLegacyCurrentEpochWithdrawals);
        assertEq(vaultV2.withdrawalShares(0), expectedLegacyCurrentEpochWithdrawals);
        assertEq(
            vaultTestHelper.unclaimedRaw(address(vaultV2)), int256(expectedLegacyPrevEpochWithdrawals)
        );

        assertEq(vaultV2.withdrawalsOfLength(bob), legacyEpochIndex + 2);
        assertEq(vaultV2.withdrawalUnlockAt(legacyEpochIndex, bob), expectedUnlockAfter);
        assertEq(vaultV2.withdrawalsOf(legacyEpochIndex - 1, bob), expectedLegacyPrevEpochWithdrawals);
        assertEq(vaultV2.withdrawalsOf(legacyEpochIndex, bob), expectedLegacyCurrentEpochWithdrawals);

        uint256 bobBalanceBefore = collateral.balanceOf(bob);
        vm.startPrank(bob);
        vaultV2.claim(bob, legacyEpochIndex - 1);
        vm.stopPrank();
        assertEq(vaultTestHelper.unclaimedRaw(address(vaultV2)), 0);
        assertEq(collateral.balanceOf(bob) - bobBalanceBefore, expectedLegacyPrevEpochWithdrawals);

        vm.startPrank(bob);
        vm.expectRevert(IVaultV2.WithdrawalNotMatured.selector);
        vaultV2.claim(bob, legacyEpochIndex);
        vm.stopPrank();

        vm.warp(uint256(expectedUnlockAfter) + 1);
        bobBalanceBefore = collateral.balanceOf(bob);
        vm.startPrank(bob);
        vaultV2.claim(bob, legacyEpochIndex);
        vm.stopPrank();
        assertEq(collateral.balanceOf(bob) - bobBalanceBefore, expectedLegacyCurrentEpochWithdrawals);
    }

    function test_MigrateWithdrawals_activeWithdrawalSharesMatchesSumOfCurrentUnclaimableRequestShares() public {
        uint48 epochDuration = 10;
        uint256 blockTimestamp = vm.getBlockTimestamp() + 1_720_700_948;
        vm.warp(blockTimestamp);

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;

        (IVaultV2 vault_,,) = _createInitializedVaultWithOwner(
            epochDuration,
            networkLimitSetRoleHolders,
            operatorNetworkSharesSetRoleHolders,
            1,
            address(0xdEaD),
            false,
            false,
            0,
            address(this)
        );
        VaultV1 vaultV1 = VaultV1(address(vault_));
        vault = IVaultV2(address(vaultV1));

        _deposit(bob, 500);
        _withdraw(bob, 100);

        vm.warp(blockTimestamp + epochDuration + 1);
        _withdraw(bob, 60);

        uint256 migrateTimestamp = blockTimestamp + 2 * epochDuration + epochDuration / 2;
        vm.warp(migrateTimestamp);

        bytes memory migrateData = abi.encode(_buildMigrateParams(epochDuration));
        vaultFactory.migrate(address(vaultV1), vaultFactory.lastVersion(), migrateData);

        IVaultV2 vaultV2 = IVaultV2(address(vaultV1));
        vault = vaultV2;

        address[] memory accounts = new address[](1);
        accounts[0] = bob;

        _assertActiveWithdrawalSharesMatchesCurrentUnclaimableRequestShares(accounts);
        _assertActiveWithdrawalSharesOfMatchesCurrentUnclaimableRequestShares(accounts);

        uint256 legacyEpochIndex = (migrateTimestamp - blockTimestamp) / epochDuration;
        _claim(bob, legacyEpochIndex - 1);
        _assertActiveWithdrawalSharesMatchesCurrentUnclaimableRequestShares(accounts);
        _assertActiveWithdrawalSharesOfMatchesCurrentUnclaimableRequestShares(accounts);

        uint48 expectedUnlockAfter = uint48(blockTimestamp + (legacyEpochIndex + 1) * epochDuration);
        vm.warp(expectedUnlockAfter);
        _assertActiveWithdrawalSharesMatchesCurrentUnclaimableRequestShares(accounts);
        _assertActiveWithdrawalSharesOfMatchesCurrentUnclaimableRequestShares(accounts);
    }

    function test_MigrateWithdrawals_activeWithdrawalSharesOfAt_returnsZeroBeforeMigration() public {
        uint48 epochDuration = 10;
        uint256 blockTimestamp = vm.getBlockTimestamp() + 1_720_700_948;
        vm.warp(blockTimestamp);

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;

        (IVaultV2 vault_,,) = _createInitializedVaultWithOwner(
            epochDuration,
            networkLimitSetRoleHolders,
            operatorNetworkSharesSetRoleHolders,
            1,
            address(0xdEaD),
            false,
            false,
            0,
            address(this)
        );
        VaultV1 vaultV1 = VaultV1(address(vault_));
        vault = IVaultV2(address(vaultV1));

        _deposit(bob, 500);
        _withdraw(bob, 100);

        vm.warp(blockTimestamp + epochDuration + 1);
        _withdraw(bob, 60);

        uint256 migrateTimestamp = blockTimestamp + 2 * epochDuration + epochDuration / 2;
        vm.warp(migrateTimestamp);

        bytes memory migrateData = abi.encode(_buildMigrateParams(epochDuration));
        vaultFactory.migrate(address(vaultV1), vaultFactory.lastVersion(), migrateData);

        IVaultV2 vaultV2 = IVaultV2(address(vaultV1));
        vault = vaultV2;

        uint48 historicalTimestamp = uint48(migrateTimestamp - 1);
        assertEq(vaultV2.activeWithdrawalSharesOfAt(bob, historicalTimestamp), 0);
    }

    function test_MigrateWithdrawals_activeWithdrawalSharesOfAt_respectsSyntheticUnlockBoundary() public {
        uint48 epochDuration = 10;
        uint256 blockTimestamp = vm.getBlockTimestamp() + 1_720_700_948;
        vm.warp(blockTimestamp);

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;

        (IVaultV2 vault_,,) = _createInitializedVaultWithOwner(
            epochDuration,
            networkLimitSetRoleHolders,
            operatorNetworkSharesSetRoleHolders,
            1,
            address(0xdEaD),
            false,
            false,
            0,
            address(this)
        );
        VaultV1 vaultV1 = VaultV1(address(vault_));
        vault = IVaultV2(address(vaultV1));

        _deposit(bob, 500);

        vm.warp(blockTimestamp + 2 * epochDuration + 1);
        _withdraw(bob, 80);

        uint256 migrateTimestamp = blockTimestamp + 2 * epochDuration + epochDuration / 2;
        vm.warp(migrateTimestamp);

        bytes memory migrateData = abi.encode(_buildMigrateParams(epochDuration));
        vaultFactory.migrate(address(vaultV1), vaultFactory.lastVersion(), migrateData);

        IVaultV2 vaultV2 = IVaultV2(address(vaultV1));
        vault = vaultV2;

        uint256 legacyEpochIndex = (migrateTimestamp - blockTimestamp) / epochDuration;
        uint48 syntheticUnlockAfter = uint48(migrateTimestamp + epochDuration);
        assertEq(vaultV2.withdrawalUnlockAt(legacyEpochIndex + 1, bob), syntheticUnlockAfter);

        uint48 beforeUnlockTimestamp = syntheticUnlockAfter - 1;
        uint256 expectedBeforeUnlock = _sumUnclaimableWithdrawalRequestSharesAt(bob, beforeUnlockTimestamp);
        assertGt(expectedBeforeUnlock, 0);
        assertEq(vaultV2.activeWithdrawalSharesOfAt(bob, beforeUnlockTimestamp), expectedBeforeUnlock);

        uint256 expectedAtUnlock = _sumUnclaimableWithdrawalRequestSharesAt(bob, syntheticUnlockAfter);
        assertEq(expectedAtUnlock, 0);
        assertEq(vaultV2.activeWithdrawalSharesOfAt(bob, syntheticUnlockAfter), expectedAtUnlock);
    }

    function test_MigrateWithdrawals_SecondPostMigrationWithdrawalHasNonZeroUnlockAfter() public {
        uint48 epochDuration = 10;
        uint256 blockTimestamp = vm.getBlockTimestamp() + 1_720_700_948;
        vm.warp(blockTimestamp);

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;

        (IVaultV2 vault_,,) = _createInitializedVaultWithOwner(
            epochDuration,
            networkLimitSetRoleHolders,
            operatorNetworkSharesSetRoleHolders,
            1,
            address(0xdEaD),
            false,
            false,
            0,
            address(this)
        );
        VaultV1 vaultV1 = VaultV1(address(vault_));
        vault = IVaultV2(address(vaultV1));

        _deposit(bob, 500);

        uint256 migrateTimestamp = blockTimestamp + 2 * epochDuration + epochDuration / 2;
        vm.warp(migrateTimestamp);
        bytes memory migrateData = abi.encode(_buildMigrateParams(epochDuration));
        vaultFactory.migrate(address(vaultV1), vaultFactory.lastVersion(), migrateData);

        IVaultV2 vaultV2 = IVaultV2(address(vaultV1));
        vault = vaultV2;

        _withdraw(bob, 100);

        vm.warp(block.timestamp + 1);
        uint256 secondWithdrawAmount = 40;
        _withdraw(bob, secondWithdrawAmount);

        assertEq(vaultV2.activeWithdrawalSharesOfAt(bob, uint48(block.timestamp)), 100 + secondWithdrawAmount);

        uint256 secondIndex = vaultV2.withdrawalsOfLength(bob) - 1;
        uint48 secondUnlockAfter = vaultV2.withdrawalUnlockAt(secondIndex, bob);
        assertEq(secondUnlockAfter, uint48(block.timestamp + epochDuration));

        vm.startPrank(bob);
        vm.expectRevert(IVaultV2.WithdrawalNotMatured.selector);
        vaultV2.claim(bob, secondIndex);
        vm.stopPrank();

        vm.warp(uint256(secondUnlockAfter) + 1);

        uint256 bobBalanceBefore = collateral.balanceOf(bob);
        vm.startPrank(bob);
        vaultV2.claim(bob, secondIndex);
        vm.stopPrank();
        assertEq(collateral.balanceOf(bob) - bobBalanceBefore, secondWithdrawAmount);
    }

    function test_OnSlashRevertNotSlasher() public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        vm.startPrank(alice);
        vm.expectRevert(IVaultV2.NotSlasher.selector);
        VaultV2(address(vault)).onSlash(0, false);
        vm.stopPrank();
    }

    struct Test_SlashStruct {
        uint256 slashAmountReal1;
        uint256 tokensBeforeBurner;
        uint256 activeStake1;
        uint256 withdrawals1;
        uint256 nextWithdrawals1;
        uint256 slashAmountSlashed2;
    }

    function test_Slash_NoWithdrawals(
        // uint48 withdrawalDelay,
        uint256 depositAmount,
        uint256 withdrawAmount1,
        uint256 withdrawAmount2,
        uint256 slashAmount1,
        uint256 slashAmount2,
        uint256 captureAgo
    ) public {
        // withdrawalDelay = uint48(bound(withdrawalDelay, 2, 10 days));
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        captureAgo = bound(captureAgo, 1, 7 days);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max / 2);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(7 days);

        _prepareVault();

        _deposit(alice, depositAmount);
        blockTimestamp = blockTimestamp + captureAgo;
        vm.warp(blockTimestamp);

        assertEq(
            _slash(alice, alice, alice, slashAmount1, uint48(blockTimestamp - captureAgo), ""),
            Math.min(slashAmount1, depositAmount)
        );
    }

    function test_Slash_MaturedWithdrawals(
        uint256 depositAmount,
        uint256 withdrawAmount1,
        uint256 withdrawAmount2,
        uint256 slashAmount1,
        uint256 slashAmount2,
        uint256 captureAgo
    ) public {
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        withdrawAmount1 = bound(withdrawAmount1, 1, 100 * 10 ** 18);
        withdrawAmount2 = bound(withdrawAmount2, 1, 100 * 10 ** 18);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max / 2);
        slashAmount2 = bound(slashAmount2, 1, type(uint256).max / 2);
        captureAgo = bound(captureAgo, 1, 10 days);
        vm.assume(captureAgo <= 7 days);
        vm.assume(depositAmount > withdrawAmount1 + withdrawAmount2);
        vm.assume(depositAmount > slashAmount1);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(7 days);

        _prepareVault();

        _deposit(alice, depositAmount);
        _withdraw(alice, withdrawAmount1);

        blockTimestamp = blockTimestamp + 10;
        vm.warp(blockTimestamp);

        _withdraw(alice, withdrawAmount2);

        blockTimestamp = blockTimestamp + 7 days + 1;
        vm.warp(blockTimestamp);

        uint256 activeStake = depositAmount - withdrawAmount1 - withdrawAmount2;
        assertEq(vault.totalStake(), _expectedTotalStake(uint48(blockTimestamp)));
        assertEq(vault.activeStake(), activeStake);
        uint256 lastBucket = _latestWithdrawalBucket();
        assertEq(vault.withdrawals(lastBucket), withdrawAmount1 + withdrawAmount2);

        blockTimestamp = blockTimestamp + vault.epochDuration();
        vm.warp(blockTimestamp);

        uint256 slashAmountReal = Math.min(slashAmount1, activeStake);
        uint256 tokensBeforeBurner = collateral.balanceOf(address(vault.burner()));
        assertEq(_slash(alice, alice, alice, slashAmount1, uint48(blockTimestamp - captureAgo), ""), slashAmountReal);
        assertEq(collateral.balanceOf(address(vault.burner())) - tokensBeforeBurner, slashAmountReal);
        assertEq(vault.activeStake(), activeStake - slashAmountReal);
    }

    function test_Slash_NotMaturedWithdrawals(
        uint256 depositAmount,
        uint256 withdrawAmount1,
        uint256 withdrawAmount2,
        uint256 slashAmount1,
        uint256 slashAmount2,
        uint256 captureAgo
    ) public {
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        withdrawAmount1 = bound(withdrawAmount1, 1, 100 * 10 ** 18);
        withdrawAmount2 = bound(withdrawAmount2, 1, 100 * 10 ** 18);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max / 2);
        slashAmount2 = bound(slashAmount2, 1, type(uint256).max / 2);
        captureAgo = 1 days;
        vm.assume(depositAmount > withdrawAmount1 + withdrawAmount2);
        vm.assume(depositAmount > slashAmount1);

        SlashNotMaturedState memory state;
        state.blockTimestamp = vm.getBlockTimestamp();
        state.blockTimestamp = state.blockTimestamp + 1_720_700_948;
        vm.warp(state.blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(7 days);

        _prepareVault();

        _deposit(alice, depositAmount);
        _withdraw(alice, withdrawAmount1);

        state.blockTimestamp = state.blockTimestamp + 10;
        vm.warp(state.blockTimestamp);

        _withdraw(alice, withdrawAmount2);

        state.blockTimestamp = state.blockTimestamp + captureAgo;
        vm.warp(state.blockTimestamp);

        state.activeStake = vault.activeStake();
        state.lastBucket = _latestWithdrawalBucket();
        state.lastWithdrawals = vault.withdrawals(state.lastBucket);
        state.lastWithdrawalShares = vault.withdrawalShares(state.lastBucket);
        state.unmaturedWithdrawalShares = _unmaturedWithdrawalShares(uint48(state.blockTimestamp));
        state.unmaturedWithdrawals = state.lastWithdrawalShares == 0
            ? 0
            : state.unmaturedWithdrawalShares.mulDiv(state.lastWithdrawals, state.lastWithdrawalShares);
        state.slashableStake = state.activeStake + state.unmaturedWithdrawals;
        state.slashAmountReal = Math.min(slashAmount1, state.slashableStake);
        state.tokensBeforeBurner = collateral.balanceOf(address(vault.burner()));
        assertEq(
            _slash(alice, alice, alice, slashAmount1, uint48(state.blockTimestamp - captureAgo), ""),
            state.slashAmountReal
        );
        assertEq(collateral.balanceOf(address(vault.burner())) - state.tokensBeforeBurner, state.slashAmountReal);

        state.activeSlashed = state.slashAmountReal.mulDiv(state.activeStake, state.slashableStake);
        state.activeStakeAfter = state.activeStake - state.activeSlashed;
        assertEq(vault.activeStake(), state.activeStakeAfter);

        state.unmaturedSlashed = state.slashAmountReal - state.activeSlashed;
        state.withdrawalsAfter = state.unmaturedWithdrawals - state.unmaturedSlashed;
        uint256 claimableWithdrawalShares = state.lastWithdrawalShares - state.unmaturedWithdrawalShares;
        if (claimableWithdrawalShares > 0) {
            assertEq(_latestWithdrawalBucket(), state.lastBucket + 1);
            assertEq(vault.withdrawals(state.lastBucket + 1), state.withdrawalsAfter);
        } else {
            assertEq(_latestWithdrawalBucket(), state.lastBucket);
            assertEq(vault.withdrawals(state.lastBucket), state.withdrawalsAfter);
            assertEq(vault.withdrawals(state.lastBucket + 1), 0);
        }
    }

    function test_SlashTwice(
        uint256 depositAmount,
        uint256 withdrawAmount1,
        uint256 withdrawAmount2,
        uint256 slashAmount1,
        uint256 slashAmount2,
        uint256 captureAgo
    ) public {
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        withdrawAmount1 = bound(withdrawAmount1, 1, 100 * 10 ** 18);
        withdrawAmount2 = bound(withdrawAmount2, 1, 100 * 10 ** 18);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max / 2);
        slashAmount2 = bound(slashAmount2, 1, type(uint256).max / 2);
        captureAgo = 1 days;
        vm.assume(depositAmount > withdrawAmount1 + withdrawAmount2);
        vm.assume(depositAmount > slashAmount1 + slashAmount2);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(7 days);

        _prepareVault();

        _deposit(alice, depositAmount);
        _withdraw(alice, withdrawAmount1);

        blockTimestamp = blockTimestamp + 10;
        vm.warp(blockTimestamp);

        _withdraw(alice, withdrawAmount2);

        blockTimestamp = blockTimestamp + captureAgo;
        vm.warp(blockTimestamp);

        // First slash
        _slash(alice, alice, alice, slashAmount1, uint48(blockTimestamp - captureAgo), "");

        blockTimestamp = blockTimestamp + captureAgo;
        vm.warp(blockTimestamp);

        // Second slash
        // Calculate unmatured withdrawals the same way the slash function does
        uint256 lastBucket2 = _latestWithdrawalBucket();
        uint256 lastWithdrawals2 = vault.withdrawals(lastBucket2);
        uint256 lastWithdrawalShares2 = vault.withdrawalShares(lastBucket2);
        uint256 unmaturedWithdrawalShares2 = vaultTestHelper.withdrawalSharesCumulativeLatest(address(vault))
            - vaultTestHelper.withdrawalSharesCumulativeUpperLookupRecent(address(vault), uint48(blockTimestamp));
        uint256 unmaturedWithdrawals2 =
            lastWithdrawalShares2 == 0 ? 0 : unmaturedWithdrawalShares2.mulDiv(lastWithdrawals2, lastWithdrawalShares2);

        uint256 activeStake2 = vault.activeStake();
        uint256 slashableStake2 = activeStake2 + unmaturedWithdrawals2;

        uint256 slashAmountReal2 = _slash(alice, alice, alice, slashAmount2, uint48(blockTimestamp - captureAgo), "");

        // Calculate state after second slash
        uint256 activeSlashed2 = slashAmountReal2.mulDiv(activeStake2, slashableStake2);
        uint256 activeStakeAfter = activeStake2 - activeSlashed2;
        assertEq(vault.activeStake(), activeStakeAfter);

        // The unmatured withdrawals are slashed proportionally
        uint256 unmaturedSlashed2 = slashAmountReal2 - activeSlashed2;
        uint256 withdrawalsAfter = unmaturedWithdrawals2 - unmaturedSlashed2;
        if (lastWithdrawalShares2 > unmaturedWithdrawalShares2) {
            assertEq(_latestWithdrawalBucket(), lastBucket2 + 1);
            assertEq(vault.withdrawals(lastBucket2 + 1), withdrawalsAfter);
        } else {
            assertEq(_latestWithdrawalBucket(), lastBucket2);
            assertEq(vault.withdrawals(lastBucket2), withdrawalsAfter);
            assertEq(vault.withdrawals(lastBucket2 + 1), 0);
        }
    }

    function test_AddRemoveAdapter() public {
        vault = _getVault(7 days);
        MockAdapter adapter = _createAdapter();

        _addAdapter(adapter);

        assertEq(vault.adaptersLength(), 1);
        assertEq(vault.adapters(0), address(adapter));
        assertEq(vault.adapterLimit(address(adapter)), type(uint208).max);
        assertTrue(IAccessControl(address(vault)).hasRole(ALLOCATE_ADAPTER_ROLE, address(adapter)));
        assertTrue(IAccessControl(address(vault)).hasRole(DEALLOCATE_ADAPTER_ROLE, address(adapter)));

        _grantRemoveAdapterRole(alice, alice);
        vm.prank(alice);
        VaultV2(address(vault)).setAdapterLimit(address(adapter), 0);

        assertEq(vault.adaptersLength(), 0);
        assertEq(vault.adapterLimit(address(adapter)), 0);
        assertFalse(IAccessControl(address(vault)).hasRole(ALLOCATE_ADAPTER_ROLE, address(adapter)));
        assertFalse(IAccessControl(address(vault)).hasRole(DEALLOCATE_ADAPTER_ROLE, address(adapter)));
    }

    function test_RevokeAdapterRolesBlockedWhileLimitIsNonZero() public {
        vault = _getVault(7 days);
        MockAdapter adapter = _createAdapter();
        _addAdapter(adapter);

        vm.prank(alice);
        VaultV2(address(vault)).revokeRole(ALLOCATE_ADAPTER_ROLE, address(adapter));
        vm.prank(alice);
        VaultV2(address(vault)).revokeRole(DEALLOCATE_ADAPTER_ROLE, address(adapter));

        assertTrue(IAccessControl(address(vault)).hasRole(ALLOCATE_ADAPTER_ROLE, address(adapter)));
        assertTrue(IAccessControl(address(vault)).hasRole(DEALLOCATE_ADAPTER_ROLE, address(adapter)));
    }

    function test_RevokeAdapterRolesAfterLimitBecomesZero() public {
        vault = _getVault(7 days);
        MockAdapter adapter = _createAdapter();
        _addAdapter(adapter);

        _grantRemoveAdapterRole(alice, alice);
        vm.prank(alice);
        VaultV2(address(vault)).setAdapterLimit(address(adapter), 0);

        // setAdapterLimit(0) removes adapter roles via super._revokeRole.
        assertFalse(IAccessControl(address(vault)).hasRole(ALLOCATE_ADAPTER_ROLE, address(adapter)));
        assertFalse(IAccessControl(address(vault)).hasRole(DEALLOCATE_ADAPTER_ROLE, address(adapter)));

        // Re-grant roles to hit VaultV2._revokeRole allow-path when adapterLimit == 0.
        vm.prank(alice);
        VaultV2(address(vault)).grantRole(ALLOCATE_ADAPTER_ROLE, address(adapter));
        vm.prank(alice);
        VaultV2(address(vault)).grantRole(DEALLOCATE_ADAPTER_ROLE, address(adapter));
        assertTrue(IAccessControl(address(vault)).hasRole(ALLOCATE_ADAPTER_ROLE, address(adapter)));
        assertTrue(IAccessControl(address(vault)).hasRole(DEALLOCATE_ADAPTER_ROLE, address(adapter)));

        vm.prank(alice);
        VaultV2(address(vault)).revokeRole(ALLOCATE_ADAPTER_ROLE, address(adapter));
        vm.prank(alice);
        VaultV2(address(vault)).revokeRole(DEALLOCATE_ADAPTER_ROLE, address(adapter));

        assertFalse(IAccessControl(address(vault)).hasRole(ALLOCATE_ADAPTER_ROLE, address(adapter)));
        assertFalse(IAccessControl(address(vault)).hasRole(DEALLOCATE_ADAPTER_ROLE, address(adapter)));
    }

    function test_RevokeNonAdapterRoleNotBlockedWhenAdapterLimitNonZero() public {
        vault = _getVault(7 days);
        MockAdapter adapter = _createAdapter();
        _addAdapter(adapter);

        vm.prank(alice);
        VaultV2(address(vault)).grantRole(DEPOSITOR_WHITELIST_ROLE, address(adapter));
        assertTrue(IAccessControl(address(vault)).hasRole(DEPOSITOR_WHITELIST_ROLE, address(adapter)));

        vm.prank(alice);
        VaultV2(address(vault)).revokeRole(DEPOSITOR_WHITELIST_ROLE, address(adapter));
        assertFalse(IAccessControl(address(vault)).hasRole(DEPOSITOR_WHITELIST_ROLE, address(adapter)));
    }

    function test_DepositAutoAllocatesFirstAdapter() public {
        vault = _getUniversalVault(7 days);

        MockAdapter adapter1 = _createAdapter();
        MockAdapter adapter2 = _createAdapter();
        _addAdapter(adapter1);
        _addAdapter(adapter2);

        (uint256 depositedAmount,) = _deposit(alice, 100);

        assertEq(vault.adaptersAllocated(), depositedAmount);
        assertEq(vault.adapterAllocated(address(adapter1)), depositedAmount);
        assertEq(vault.adapterAllocated(address(adapter2)), 0);
    }

    function test_SetAdapterLimitRemoveNonLastSwapsAndPops() public {
        vault = _getVault(7 days);
        MockAdapter adapter1 = _createAdapter();
        MockAdapter adapter2 = _createAdapter();
        MockAdapter adapter3 = _createAdapter();

        _addAdapter(adapter1);
        _addAdapter(adapter2);
        _addAdapter(adapter3);

        _grantRemoveAdapterRole(alice, alice);
        vm.prank(alice);
        VaultV2(address(vault)).setAdapterLimit(address(adapter1), 0);

        assertEq(vault.adaptersLength(), 2);
        assertEq(vault.adapters(0), address(adapter3));
        assertEq(vault.adapters(1), address(adapter2));
        assertEq(vault.adapterLimit(address(adapter1)), 0);
        assertFalse(IAccessControl(address(vault)).hasRole(ALLOCATE_ADAPTER_ROLE, address(adapter1)));
        assertFalse(IAccessControl(address(vault)).hasRole(DEALLOCATE_ADAPTER_ROLE, address(adapter1)));
    }

    function test_SetAdapterLimitExistingAdapterKeepsListUnchanged() public {
        vault = _getUniversalVault(7 days);

        MockAdapter adapter1 = _createAdapter();
        MockAdapter adapter2 = _createAdapter();
        _addAdapter(adapter1);
        _addAdapter(adapter2);

        vm.prank(alice);
        VaultV2(address(vault)).setAdapterLimit(address(adapter1), 321);

        assertEq(vault.adaptersLength(), 2);
        assertEq(vault.adapters(0), address(adapter1));
        assertEq(vault.adapters(1), address(adapter2));
        assertEq(vault.adapterLimit(address(adapter1)), 321);
    }

    function test_SetAdapterLimitZeroForUnknownAdapterNoop() public {
        vault = _getUniversalVault(7 days);
        MockAdapter adapter = _createAdapter();
        _grantAddAdapterRole(alice, alice);

        vm.startPrank(alice);
        VaultV2(address(vault)).setAdapterLimit(address(adapter), 0);
        vm.stopPrank();

        assertEq(vault.adaptersLength(), 0);
        assertEq(vault.adapterLimit(address(adapter)), 0);
        assertFalse(IAccessControl(address(vault)).hasRole(ALLOCATE_ADAPTER_ROLE, address(adapter)));
        assertFalse(IAccessControl(address(vault)).hasRole(DEALLOCATE_ADAPTER_ROLE, address(adapter)));
    }

    function test_SetAdapterLimitRevertNotAdapter() public {
        vault = _getUniversalVault(7 days);

        MockAdapter adapter = new MockAdapter(address(vault), address(collateral));
        _grantAddAdapterRole(alice, alice);

        vm.startPrank(alice);
        vm.expectRevert(IVaultV2.NotAdapter.selector);
        VaultV2(address(vault)).setAdapterLimit(address(adapter), 10);
        vm.stopPrank();
    }

    function test_SwapAdapters() public {
        vault = _getVault(7 days);
        MockAdapter adapter1 = _createAdapter();
        MockAdapter adapter2 = _createAdapter();
        _addAdapter(adapter1);
        _addAdapter(adapter2);

        vm.prank(alice);
        VaultV2(address(vault)).grantRole(SWAP_ADAPTERS_ROLE, alice);

        vm.prank(alice);
        VaultV2(address(vault)).swapAdapters(address(adapter1), address(adapter2));

        assertEq(vault.adapters(0), address(adapter2));
        assertEq(vault.adapters(1), address(adapter1));
    }

    function test_SwapAdaptersRevertAdaptersNotFound() public {
        vault = _getVault(7 days);
        MockAdapter adapter1 = _createAdapter();
        MockAdapter adapter2 = _createAdapter();
        _addAdapter(adapter1);

        vm.prank(alice);
        VaultV2(address(vault)).grantRole(SWAP_ADAPTERS_ROLE, alice);

        vm.startPrank(alice);
        vm.expectRevert(stdError.indexOOBError);
        VaultV2(address(vault)).swapAdapters(address(adapter1), address(adapter2));
        vm.stopPrank();
    }

    function test_AllocateAdapterRevertMissingRoles() public {
        vault = _getUniversalVault(7 days);
        MockAdapter adapter = _createAdapter();
        _addAdapter(adapter);

        vm.prank(bob);
        vm.expectRevert();
        vault.allocateAdapter(address(adapter), 1);
    }

    function test_DeallocateAdapterRevertMissingRoles() public {
        vault = _getUniversalVault(7 days);
        MockAdapter adapter = _createAdapter();
        _addAdapter(adapter);

        vm.prank(bob);
        vm.expectRevert();
        vault.deallocateAdapter(address(adapter), 1);
    }

    function test_AllocateAdapterReturnsZeroWhenNotActive() public {
        vault = _getUniversalVault(7 days);
        MockAdapter adapter = _createAdapter();
        _addAdapter(adapter);

        vm.prank(address(adapter));
        uint256 allocated = vault.allocateAdapter(address(adapter), 1);
        assertEq(allocated, 0);
    }

    function test_AllocateAdapter_respectsRemainingAdapterLimit() public {
        vault = _getUniversalVault(7 days);
        _deposit(alice, 100);

        MockAdapter adapter = _createAdapter();
        _addAdapter(adapter);

        _grantAddAdapterRole(alice, alice);
        vm.prank(alice);
        VaultV2(address(vault)).setAdapterLimit(address(adapter), 60);

        vm.prank(address(adapter));
        uint256 allocated = vault.allocateAdapter(address(adapter), 50);
        assertEq(allocated, 50);

        vm.prank(address(adapter));
        allocated = vault.allocateAdapter(address(adapter), 50);
        assertEq(allocated, 10);

        vm.prank(address(adapter));
        allocated = vault.allocateAdapter(address(adapter), 1);
        assertEq(allocated, 0);

        assertEq(vault.adapterAllocated(address(adapter)), 60);
        assertEq(vault.adaptersAllocated(), 60);
    }

    function test_RemoveAdapter_revertsWhenOwed() public {
        vault = _getUniversalVault(7 days);
        _deposit(alice, 100);

        MockAdapter adapter = _createAdapter();
        _addAdapter(adapter);
        _activateAdapterLimit();

        vm.prank(address(adapter));
        vault.allocateAdapter(address(adapter), 40);

        _grantRemoveAdapterRole(alice, alice);
        vm.startPrank(alice);
        vm.expectRevert(IVaultV2.AdapterAllocated.selector);
        VaultV2(address(vault)).setAdapterLimit(address(adapter), 0);
        vm.stopPrank();
    }

    function test_PullPush_tracksOwed() public {
        vault = _getUniversalVault(7 days);
        _deposit(alice, 100);

        MockAdapter adapter = _createAdapter();
        _addAdapter(adapter);
        _activateAdapterLimit();

        vm.prank(address(adapter));
        uint256 pulled = vault.allocateAdapter(address(adapter), 80);
        assertEq(pulled, 80);
        assertEq(vault.adaptersAllocated(), 80);
        assertEq(vault.adapterAllocated(address(adapter)), 80);

        vm.prank(address(adapter));
        pulled = vault.allocateAdapter(address(adapter), 50);
        assertEq(pulled, 20);
        assertEq(vault.adaptersAllocated(), 100);
        assertEq(vault.adapterAllocated(address(adapter)), 100);

        vm.prank(address(adapter));
        vault.deallocateAdapter(address(adapter), 30);

        assertEq(vault.adaptersAllocated(), 70);
        assertEq(vault.adapterAllocated(address(adapter)), 70);
    }

    function test_PullAdapters_duringWithdrawKeepsOwed() public {
        vault = _getUniversalVault(7 days);
        _deposit(alice, 100);

        MockAdapter adapter = _createAdapter();
        _addAdapter(adapter);
        _activateAdapterLimit();

        vm.prank(address(adapter));
        vault.allocateAdapter(address(adapter), 50);

        _withdraw(alice, 10);

        assertEq(vault.adapterAllocated(address(adapter)), 50);
        assertEq(vault.adaptersAllocated(), 50);
    }

    function test_OnSlash_returnsOwedWhenAdaptersShort() public {
        uint256 blockTimestamp = vm.getBlockTimestamp();
        if (blockTimestamp == 0) {
            vm.warp(1_720_700_948);
        }

        (vault,, slasher) = _getUniversalVaultAndDelegatorAndSlasher(7 days);
        _deposit(alice, 100);

        MockAdapter adapter = _createAdapter();
        _addAdapter(adapter);
        _activateAdapterLimit();

        vm.prank(address(adapter));
        vault.allocateAdapter(address(adapter), 80);

        adapter.setShouldFail(true);

        uint256 burnerBalanceBefore = collateral.balanceOf(address(0xdEaD));
        uint48 captureTimestamp = uint48(block.timestamp - 1);

        vm.prank(address(slasher));
        (uint256 slashedAmount, uint256 owed) = VaultV2(address(vault)).onSlash(60, true);

        assertEq(slashedAmount, 60);
        assertEq(owed, 40);
        assertEq(collateral.balanceOf(address(0xdEaD)) - burnerBalanceBefore, 20);
        assertEq(vault.adapterAllocated(address(adapter)), 80);
    }

    function test_OnSlash_withAdaptersDeallocatesToAvoidOwedWhenVaultLiquidityIsInsufficient() public {
        (vault,, slasher) = _getUniversalVaultAndDelegatorAndSlasher(7 days);
        _deposit(alice, 100);

        MockAdapter adapter = _createAdapter();
        _addAdapter(adapter);
        _activateAdapterLimit();

        vm.prank(address(adapter));
        vault.allocateAdapter(address(adapter), 80);

        assertEq(collateral.balanceOf(address(vault)), 20);
        assertEq(vault.adapterAllocated(address(adapter)), 80);

        uint256 burnerBalanceBefore = collateral.balanceOf(address(0xdEaD));

        vm.prank(address(slasher));
        (uint256 slashedAmount, uint256 owed) = VaultV2(address(vault)).onSlash(60, true);

        assertEq(slashedAmount, 60);
        assertEq(owed, 0);
        assertEq(collateral.balanceOf(address(0xdEaD)) - burnerBalanceBefore, 60);
        assertEq(vault.adapterAllocated(address(adapter)), 40);
        assertEq(vault.adaptersAllocated(), 40);
        assertEq(collateral.balanceOf(address(vault)), 0);
    }

    function test_OnSlash_withAdaptersFullyOwed_skipsZeroBurnerTransfer() public {
        (vault,, slasher) = _getUniversalVaultAndDelegatorAndSlasher(7 days);
        _deposit(alice, 100);

        MockAdapter adapter = _createAdapter();
        _addAdapter(adapter);
        _activateAdapterLimit();

        vm.prank(address(adapter));
        vault.allocateAdapter(address(adapter), 100);

        adapter.setShouldFail(true);
        assertEq(collateral.balanceOf(address(vault)), 0);

        uint256 burnerBalanceBefore = collateral.balanceOf(address(0xdEaD));

        vm.prank(address(slasher));
        (uint256 slashedAmount, uint256 owed) = VaultV2(address(vault)).onSlash(60, true);

        assertEq(slashedAmount, 60);
        assertEq(owed, 60);
        assertEq(collateral.balanceOf(address(0xdEaD)) - burnerBalanceBefore, 0);
        assertEq(vault.adapterAllocated(address(adapter)), 100);
        assertEq(vault.adaptersAllocated(), 100);
        assertEq(collateral.balanceOf(address(vault)), 0);
    }

    function test_AdapterNoDeallocate_acrossInstantWithdrawAndSyncOwedSlash() public {
        (vault,, slasher) = _getUniversalVaultAndDelegatorAndSlasher(7 days);
        _deposit(alice, 100);

        MockAdapter adapter = _createAdapter();
        _addAdapter(adapter);
        _activateAdapterLimit();

        vm.prank(address(adapter));
        vault.allocateAdapter(address(adapter), 80);

        adapter.setShouldFail(true);

        vm.prank(alice);
        vm.expectRevert(IVaultV2.InsufficientAmount.selector);
        VaultV2(address(vault)).instantWithdraw(alice, 60);

        assertEq(vault.adapterAllocated(address(adapter)), 80);
        assertEq(vault.adaptersAllocated(), 80);
        assertEq(collateral.balanceOf(address(vault)), 20);

        uint256 burnerBalanceBefore = collateral.balanceOf(address(0xdEaD));
        vm.prank(address(slasher));
        (uint256 slashedAmount, uint256 owed) = VaultV2(address(vault)).onSlash(60, true);

        assertEq(slashedAmount, 60);
        assertEq(owed, 40);
        assertEq(collateral.balanceOf(address(0xdEaD)) - burnerBalanceBefore, 20);
        assertEq(vault.adapterAllocated(address(adapter)), 80);
        assertEq(vault.adaptersAllocated(), 80);
        assertEq(collateral.balanceOf(address(vault)), 0);

        vm.prank(address(slasher));
        vm.expectRevert(IVaultV2.InsufficientAmount.selector);
        VaultV2(address(vault)).syncOwedSlash(1);
    }

    function test_AdapterPartialDeallocate_acrossInstantWithdrawAndSyncOwedSlash() public {
        (vault,, slasher) = _getUniversalVaultAndDelegatorAndSlasher(7 days);
        _deposit(alice, 100);

        MockAdapter adapter = _createAdapter();
        _addAdapter(adapter);
        _activateAdapterLimit();

        vm.prank(address(adapter));
        vault.allocateAdapter(address(adapter), 80);

        vm.prank(address(adapter));
        collateral.transfer(bob, 50);
        assertEq(collateral.balanceOf(address(adapter)), 30);
        assertEq(vault.adapterAllocated(address(adapter)), 80);

        vm.prank(alice);
        vm.expectRevert(IVaultV2.InsufficientAmount.selector);
        VaultV2(address(vault)).instantWithdraw(alice, 60);

        assertEq(collateral.balanceOf(address(adapter)), 30);
        assertEq(vault.adapterAllocated(address(adapter)), 80);
        assertEq(vault.adaptersAllocated(), 80);
        assertEq(collateral.balanceOf(address(vault)), 20);

        uint256 burnerBalanceBefore = collateral.balanceOf(address(0xdEaD));
        vm.prank(address(slasher));
        (uint256 slashedAmount, uint256 owed) = VaultV2(address(vault)).onSlash(60, true);

        assertEq(slashedAmount, 60);
        assertEq(owed, 10);
        assertEq(collateral.balanceOf(address(0xdEaD)) - burnerBalanceBefore, 50);
        assertEq(vault.adapterAllocated(address(adapter)), 50);
        assertEq(vault.adaptersAllocated(), 50);
        assertEq(collateral.balanceOf(address(vault)), 0);

        vm.prank(address(slasher));
        vm.expectRevert(IVaultV2.InsufficientAmount.selector);
        VaultV2(address(vault)).syncOwedSlash(1);
    }

    function test_UniversalSlasher_syncOwedSlash_closesOutstandingOwedAfterDeposit() public {
        UniversalDelegator universalDelegator;
        UniversalSlasher universalSlasher;
        (vault, universalDelegator, slasher) = _getUniversalVaultAndDelegatorAndSlasher(7 days);
        universalSlasher = UniversalSlasher(address(slasher));

        address network = makeAddr("sync-owed-network");
        address middleware = makeAddr("sync-owed-middleware");
        _registerNetwork(network, middleware);
        _registerOperator(alice);
        _optInOperatorVault(alice);
        _optInOperatorNetwork(alice, network);

        vm.prank(network);
        universalDelegator.setMaxNetworkLimit(0, type(uint256).max);

        vm.startPrank(alice);
        uint96 subvaultSlot = universalDelegator.createSlot(bytes32("subvault"), 0, false, false, 100);
        uint96 networkSlot = universalDelegator.createSlot(network.subnetwork(0), subvaultSlot, false, false, 100);
        universalDelegator.createSlot(bytes32(bytes20(alice)), networkSlot, false, false, 100);
        vm.stopPrank();

        MockMorphoVault morphoVault = new MockMorphoVault(address(collateral));
        MockMorphoBorrowAdapter adapter =
            new MockMorphoBorrowAdapter(address(vault), address(collateral), address(morphoVault), address(rewards));
        adapterRegistry.whitelistAdapter(address(adapter));

        uint256 minTimestamp = uint256(vault.epochDuration()) + 1;
        if (block.timestamp < minTimestamp) {
            vm.warp(minTimestamp);
        }
        _grantAddAdapterRole(alice, alice);
        vm.prank(alice);
        VaultV2(address(vault)).setAdapterLimit(address(adapter), type(uint208).max);

        _deposit(alice, 100);
        assertEq(vault.adapterAllocated(address(adapter)), 100);
        assertEq(collateral.balanceOf(address(vault)), 0);
        assertEq(collateral.balanceOf(address(morphoVault)), 100);

        vm.prank(address(morphoVault));
        collateral.transfer(address(0xBEEF), 40);
        assertEq(collateral.balanceOf(address(morphoVault)), 60);

        vm.prank(middleware);
        uint256 slashIndex = universalSlasher.requestSlash(network.subnetwork(0), alice, 80, 0, "");
        vm.warp(block.timestamp + 1);
        vm.prank(middleware);
        uint256 slashedAmount = universalSlasher.executeSlash(slashIndex, "");

        assertEq(slashedAmount, 80);
        assertEq(universalSlasher.totalOwed(), 20);
        assertEq(universalSlasher.owed(network.subnetwork(0), alice), 20);
        assertEq(vault.adapterAllocated(address(adapter)), 40);
        assertEq(vault.adaptersAllocated(), 40);
        assertEq(collateral.balanceOf(address(vault)), 0);

        _deposit(bob, 30);

        assertEq(vault.adapterAllocated(address(adapter)), 50);
        assertEq(vault.adaptersAllocated(), 50);
        assertEq(collateral.balanceOf(address(vault)), 20);

        uint256 burnerBalanceBefore = collateral.balanceOf(address(0xdEaD));
        uint256 synced = universalSlasher.syncOwedSlash(network.subnetwork(0), alice);

        assertEq(synced, 20);
        assertEq(universalSlasher.totalOwed(), 0);
        assertEq(universalSlasher.owed(network.subnetwork(0), alice), 0);
        assertEq(collateral.balanceOf(address(0xdEaD)) - burnerBalanceBefore, 20);
        assertEq(collateral.balanceOf(address(vault)), 0);
    }

    function test_UniversalSlasher_executeSlash_withFullyOwedAdapterShortfall_skipsZeroBurnerTransfer() public {
        UniversalDelegator universalDelegator;
        UniversalSlasher universalSlasher;
        (vault, universalDelegator, slasher) = _getUniversalVaultAndDelegatorAndSlasher(7 days);
        universalSlasher = UniversalSlasher(address(slasher));

        address network = makeAddr("full-owed-network");
        address middleware = makeAddr("full-owed-middleware");
        _registerNetwork(network, middleware);
        _registerOperator(alice);
        _optInOperatorVault(alice);
        _optInOperatorNetwork(alice, network);

        vm.prank(network);
        universalDelegator.setMaxNetworkLimit(0, type(uint256).max);

        vm.startPrank(alice);
        uint96 subvaultSlot = universalDelegator.createSlot(bytes32("subvault"), 0, false, false, 100);
        uint96 networkSlot = universalDelegator.createSlot(network.subnetwork(0), subvaultSlot, false, false, 100);
        universalDelegator.createSlot(bytes32(bytes20(alice)), networkSlot, false, false, 100);
        vm.stopPrank();

        MockAdapter adapter = _createAdapter();
        _addAdapter(adapter);

        _deposit(alice, 100);

        vm.prank(address(adapter));
        vault.allocateAdapter(address(adapter), 100);

        adapter.setShouldFail(true);
        assertEq(collateral.balanceOf(address(vault)), 0);

        uint256 burnerBalanceBefore = collateral.balanceOf(address(0xdEaD));

        vm.prank(middleware);
        uint256 slashIndex = universalSlasher.requestSlash(network.subnetwork(0), alice, 60, 0, "");

        vm.warp(block.timestamp + 1);

        vm.prank(middleware);
        uint256 slashedAmount = universalSlasher.executeSlash(slashIndex, "");

        assertEq(slashedAmount, 60);
        assertEq(universalSlasher.totalOwed(), 60);
        assertEq(universalSlasher.owed(network.subnetwork(0), alice), 60);
        assertEq(collateral.balanceOf(address(0xdEaD)) - burnerBalanceBefore, 0);
        assertEq(vault.adapterAllocated(address(adapter)), 100);
        assertEq(vault.adaptersAllocated(), 100);
        assertEq(collateral.balanceOf(address(vault)), 0);
    }

    function test_SyncOwedSlash_revertsWhenOnlyUnclaimed() public {
        uint256 blockTimestamp = vm.getBlockTimestamp();
        if (blockTimestamp == 0) {
            vm.warp(1_720_700_948);
            blockTimestamp = vm.getBlockTimestamp();
        }

        uint48 epochDuration = 1;
        (vault,, slasher) = _getUniversalVaultAndDelegatorAndSlasher(epochDuration);

        _deposit(alice, 100);
        _withdraw(alice, 100);

        vm.warp(blockTimestamp + epochDuration + 1);

        vm.expectRevert(IVaultV2.InsufficientAmount.selector);
        vm.prank(address(slasher));
        VaultV2(address(vault)).syncOwedSlash(1);
    }

    function test_OnSlash_accountsForUnclaimedWithAdapter() public {
        uint256 blockTimestamp = vm.getBlockTimestamp();
        if (blockTimestamp == 0) {
            vm.warp(1_720_700_948);
            blockTimestamp = vm.getBlockTimestamp();
        }

        uint48 epochDuration = 1;
        (vault,, slasher) = _getUniversalVaultAndDelegatorAndSlasher(epochDuration);

        _deposit(alice, 100);
        _withdraw(alice, 30);

        MockAdapter adapter = _createAdapter();
        _addAdapter(adapter);
        _activateAdapterLimit();

        vm.prank(address(adapter));
        vault.allocateAdapter(address(adapter), 40);

        adapter.setShouldFail(true);

        vm.warp(blockTimestamp + epochDuration + 1);

        uint256 burnerBalanceBefore = collateral.balanceOf(address(0xdEaD));
        uint48 captureTimestamp = uint48(block.timestamp - 1);

        vm.prank(address(slasher));
        (uint256 slashedAmount, uint256 owed) = VaultV2(address(vault)).onSlash(60, true);

        assertEq(slashedAmount, 60);
        assertEq(owed, 30);
        assertEq(collateral.balanceOf(address(0xdEaD)) - burnerBalanceBefore, 30);
        assertEq(vault.adapterAllocated(address(adapter)), 40);
    }

    function test_OnSlash_syncsClaimableAndActiveWithdrawalsBuckets() public {
        (vault,, slasher) = _getUniversalVaultAndDelegatorAndSlasher(7 days);
        _deposit(alice, 100);
        _deposit(bob, 100);

        vm.warp(block.timestamp + 1);
        _withdraw(alice, 40);

        vm.warp(block.timestamp + uint256(vault.epochDuration()) + 1);
        _withdraw(bob, 30);

        uint256 slashAmount = 20;
        uint48 aliceUnlockAfter = vault.withdrawalUnlockAt(0, alice);
        uint48 bobUnlockAfter = vault.withdrawalUnlockAt(0, bob);
        uint256 bucketBefore = _latestWithdrawalBucket();
        uint256 claimableBefore = vault.withdrawalsOf(0, alice);
        uint256 activeBefore = vault.withdrawalsOf(0, bob);
        uint256 activeStakeBefore = vault.activeStake();
        uint256 burnerBalanceBefore = collateral.balanceOf(address(0xdEaD));
        uint256 expectedActiveSlashed = slashAmount.mulDiv(activeStakeBefore, activeStakeBefore + activeBefore);
        uint256 expectedActiveAfter = activeBefore - (slashAmount - expectedActiveSlashed);

        vm.prank(address(slasher));
        (uint256 slashedAmount, uint256 owed) = VaultV2(address(vault)).onSlash(slashAmount, false);

        uint256 bucketAfter = _latestWithdrawalBucket();
        assertEq(slashedAmount, slashAmount);
        assertEq(owed, 0);
        assertEq(collateral.balanceOf(address(0xdEaD)) - burnerBalanceBefore, slashAmount);
        assertEq(bucketAfter, bucketBefore + 1);

        assertEq(vaultTestHelper.unlockToBucketUpperLookupRecent(address(vault), aliceUnlockAfter), bucketBefore);
        assertEq(vaultTestHelper.unlockToBucketUpperLookupRecent(address(vault), bobUnlockAfter), bucketAfter);

        assertEq(vault.withdrawalsOf(0, alice), claimableBefore);
        assertEq(vault.withdrawalsOf(0, bob), expectedActiveAfter);
        assertEq(vault.withdrawals(bucketBefore), claimableBefore);
        assertEq(vault.withdrawals(bucketAfter), expectedActiveAfter);
        assertEq(vault.activeStake(), activeStakeBefore - expectedActiveSlashed);
    }

    function test_OnSlash_atUnlockBoundary_doesNotAffectCurrentClaimableWithdrawal() public {
        (vault,, slasher) = _getUniversalVaultAndDelegatorAndSlasher(7 days);
        (uint48 aliceUnlockAfter,) = _prepareAdjacentUnlockWithdrawals();

        uint256 slashAmount = 20;
        uint256 claimableBefore = vault.withdrawalsOf(0, alice);

        vm.prank(address(slasher));
        VaultV2(address(vault)).onSlash(slashAmount, false);

        assertEq(vault.withdrawalsOf(0, alice), claimableBefore);
        assertEq(_claim(alice, 0), claimableBefore);
        assertEq(vault.withdrawalUnlockAt(0, alice), aliceUnlockAfter);
    }

    function test_OnSlash_atUnlockBoundary_affectsNextTimestampWithdrawal() public {
        (vault,, slasher) = _getUniversalVaultAndDelegatorAndSlasher(7 days);
        (, uint48 bobUnlockAfter) = _prepareAdjacentUnlockWithdrawals();

        uint256 slashAmount = 20;
        uint256 burnerBalanceBefore = collateral.balanceOf(address(0xdEaD));
        uint256 bobBefore = vault.withdrawalsOf(0, bob);
        uint256 expectedActiveAfter;
        uint256 expectedActiveStakeAfter;
        {
            uint256 activeBefore = vault.activeWithdrawals();
            uint256 activeStakeBefore = vault.activeStake();
            uint256 expectedActiveSlashed = slashAmount.mulDiv(activeStakeBefore, activeStakeBefore + activeBefore);
            expectedActiveAfter = activeBefore - (slashAmount - expectedActiveSlashed);
            expectedActiveStakeAfter = activeStakeBefore - expectedActiveSlashed;
        }

        vm.prank(address(slasher));
        (uint256 slashedAmount, uint256 owed) = VaultV2(address(vault)).onSlash(slashAmount, false);

        assertEq(slashedAmount, slashAmount);
        assertEq(owed, 0);
        assertEq(collateral.balanceOf(address(0xdEaD)) - burnerBalanceBefore, slashAmount);
        assertEq(vault.withdrawalUnlockAt(0, bob), uint48(block.timestamp) + 1);
        assertLt(expectedActiveAfter, bobBefore);
        assertEq(vault.withdrawalsOf(0, bob), expectedActiveAfter);
        assertEq(vault.activeWithdrawals(), expectedActiveAfter);
        assertEq(vault.activeStake(), expectedActiveStakeAfter);

        vm.warp(bobUnlockAfter);
        assertEq(_claim(bob, 0), expectedActiveAfter);
    }

    function test_OnSlash_atUnlockBoundary_historicalCurrentTimestampTracksUpdatedState() public {
        (vault,, slasher) = _getUniversalVaultAndDelegatorAndSlasher(7 days);
        (uint48 aliceUnlockAfter,) = _prepareAdjacentUnlockWithdrawals();

        uint256 slashAmount = 20;
        uint48 previousTimestamp = aliceUnlockAfter - 1;
        uint256 historicalPrevActiveBefore = vault.activeWithdrawalsAt(previousTimestamp);
        uint256 historicalPrevStakeBefore = vault.activeStakeAt(previousTimestamp, "");
        uint256 expectedActiveAfter;
        uint256 expectedActiveStakeAfter;
        {
            uint256 activeBefore = vault.activeWithdrawals();
            uint256 activeStakeBefore = vault.activeStake();
            uint256 expectedActiveSlashed = slashAmount.mulDiv(activeStakeBefore, activeStakeBefore + activeBefore);
            expectedActiveAfter = activeBefore - (slashAmount - expectedActiveSlashed);
            expectedActiveStakeAfter = activeStakeBefore - expectedActiveSlashed;
        }

        vm.prank(address(slasher));
        VaultV2(address(vault)).onSlash(slashAmount, false);

        assertEq(vault.activeWithdrawalsAt(previousTimestamp), historicalPrevActiveBefore);
        assertEq(vault.activeStakeAt(previousTimestamp, ""), historicalPrevStakeBefore);
        assertEq(vault.activeWithdrawalsAt(aliceUnlockAfter), expectedActiveAfter);
        assertEq(vault.activeStakeAt(aliceUnlockAfter, ""), expectedActiveStakeAfter);
    }

    function test_OnSlash_atUnlockBoundary_durationWindows_alignWithDelegatorBalanceAt() public {
        UniversalDelegator universalDelegator;
        uint48 aliceUnlockAfter;
        (universalDelegator, slasher, aliceUnlockAfter,) = _prepareAdjacentUnlockWithdrawalsWithUniversalNetwork();

        uint256 slashAmount = 20;
        uint256 claimableBefore = vault.withdrawalsOf(0, alice);
        uint256 expectedActiveAfter;
        uint256 expectedActiveStakeAfter;
        {
            uint256 activeBefore = vault.activeWithdrawals();
            uint256 activeStakeBefore = vault.activeStake();
            uint256 expectedActiveSlashed = slashAmount.mulDiv(activeStakeBefore, activeStakeBefore + activeBefore);
            expectedActiveAfter = activeBefore - (slashAmount - expectedActiveSlashed);
            expectedActiveStakeAfter = activeStakeBefore - expectedActiveSlashed;
        }

        vm.prank(address(slasher));
        VaultV2(address(vault)).onSlash(slashAmount, false);

        assertEq(vault.withdrawalsOf(0, alice), claimableBefore);
        assertEq(vault.activeWithdrawalsForAt(0, aliceUnlockAfter), expectedActiveAfter);
        assertEq(vault.activeWithdrawalsForAt(1, aliceUnlockAfter), 0);
        assertEq(
            universalDelegator.getBalanceAt(0, 0, aliceUnlockAfter), expectedActiveStakeAfter + expectedActiveAfter
        );
        assertEq(universalDelegator.getBalanceAt(0, 1, aliceUnlockAfter), expectedActiveStakeAfter);
    }

    function test_OnSlash_withoutClaimableWithdrawals_keepsCurrentBucket() public {
        (vault,, slasher) = _getUniversalVaultAndDelegatorAndSlasher(7 days);
        _deposit(alice, 100);

        vm.warp(block.timestamp + 1);
        _withdraw(alice, 40);

        uint256 slashAmount = 20;
        uint256 bucketBefore = _latestWithdrawalBucket();
        uint256 activeBefore = vault.withdrawalsOf(0, alice);
        uint256 activeStakeBefore = vault.activeStake();
        uint256 burnerBalanceBefore = collateral.balanceOf(address(0xdEaD));
        uint256 expectedActiveSlashed = slashAmount.mulDiv(activeStakeBefore, activeStakeBefore + activeBefore);
        uint256 expectedActiveAfter = activeBefore - (slashAmount - expectedActiveSlashed);

        vm.prank(address(slasher));
        (uint256 slashedAmount, uint256 owed) = VaultV2(address(vault)).onSlash(slashAmount, false);

        assertEq(slashedAmount, slashAmount);
        assertEq(owed, 0);
        assertEq(collateral.balanceOf(address(0xdEaD)) - burnerBalanceBefore, slashAmount);
        assertEq(_latestWithdrawalBucket(), bucketBefore);
        assertEq(vault.withdrawals(bucketBefore), expectedActiveAfter);
        assertEq(vault.withdrawals(bucketBefore + 1), 0);
        assertEq(vault.withdrawalsOf(0, alice), expectedActiveAfter);
        assertEq(vault.activeStake(), activeStakeBefore - expectedActiveSlashed);
    }

    function test_ViewWrappersAndERC20Views() public {
        vault = _getUniversalVault(7 days);
        _deposit(alice, 100);
        _withdraw(alice, 40);

        uint48 timestamp = uint48(block.timestamp);
        assertEq(vault.withdrawalBucket(), vaultTestHelper.unlockToBucketLatest(address(vault)));
        assertEq(VaultV2(address(vault)).activeWithdrawalsFor(0), VaultV2(address(vault)).activeWithdrawals());
        assertEq(
            VaultV2(address(vault)).activeWithdrawalsAt(timestamp),
            VaultV2(address(vault)).activeWithdrawalsForAt(0, timestamp)
        );
        assertEq(
            VaultV2(address(vault)).activeWithdrawalSharesAt(timestamp),
            VaultV2(address(vault)).activeWithdrawalSharesForAt(0, timestamp)
        );
        assertEq(VaultV2(address(vault)).activeWithdrawalShares(), VaultV2(address(vault)).activeWithdrawalSharesFor(0));
        assertEq(
            VaultV2(address(vault)).activeWithdrawalSharesFor(0),
            VaultV2(address(vault)).activeWithdrawalSharesForAt(0, timestamp)
        );
        assertEq(
            VaultV2(address(vault)).activeWithdrawalSharesOfAt(alice, timestamp), vault.withdrawalSharesOf(0, alice)
        );
        assertGt(VaultV2(address(vault)).withdrawalsOf(0, alice), 0);
        assertEq(VaultV2(address(vault)).decimals(), collateral.decimals());
        assertEq(VaultV2(address(vault)).totalSupply(), vault.activeShares());
        assertEq(VaultV2(address(vault)).balanceOf(alice), vault.activeSharesOf(alice));

        uint256 expectedAllocatable = vault.totalStake()
            .saturatingSub(IUniversalDelegator(vault.delegator()).getNoAdaptersSize())
            .saturatingSub(vault.adaptersAllocated());
        assertEq(vault.allocatable(), expectedAllocatable);
        assertEq(vault.adapterLimit(address(uint160(0xBEEF))), 0);
    }

    function test_InstantWithdraw() public {
        vault = _getUniversalVault(7 days);
        _deposit(alice, 100);

        uint256 buffer = IUniversalDelegator(vault.delegator()).getWithdrawalBuffer();
        assertGt(buffer, 0);
        uint256 amount = Math.min(buffer, uint256(10));

        uint256 bobBalanceBefore = collateral.balanceOf(bob);
        vm.prank(alice);
        (uint256 withdrawnAssets, uint256 burnedShares) = VaultV2(address(vault)).instantWithdraw(bob, amount);

        assertEq(withdrawnAssets, amount);
        assertGt(burnedShares, 0);
        assertEq(collateral.balanceOf(bob) - bobBalanceBefore, amount);
    }

    function test_InstantWithdraw_eventEmitsWithdrawer() public {
        vault = _getUniversalVault(7 days);
        _deposit(alice, 100);

        uint256 amount = Math.min(IUniversalDelegator(vault.delegator()).getWithdrawalBuffer(), uint256(10));
        assertGt(amount, 0);

        vm.recordLogs();
        vm.prank(alice);
        (uint256 withdrawnAssets, uint256 burnedShares) = VaultV2(address(vault)).instantWithdraw(bob, amount);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 instantWithdrawSig = keccak256("InstantWithdraw(address,uint256,uint256)");
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter != address(vault) || logs[i].topics.length < 2
                    || logs[i].topics[0] != instantWithdrawSig
            ) {
                continue;
            }

            found = true;
            assertEq(address(uint160(uint256(logs[i].topics[1]))), alice);
            (uint256 amountLogged, uint256 burnedSharesLogged) = abi.decode(logs[i].data, (uint256, uint256));
            assertEq(amountLogged, withdrawnAssets);
            assertEq(burnedSharesLogged, burnedShares);
            break;
        }

        assertTrue(found);
    }

    function test_InstantWithdraw_withFee_distributesRewardsAndTransfersNetAmount() public {
        vault = _getUniversalVault(7 days);
        _deposit(alice, 100);

        uint256 amount = Math.min(IUniversalDelegator(vault.delegator()).getWithdrawalBuffer(), uint256(10));
        assertGt(amount, 0);

        feeRegistry.setInstantWithdrawFee(address(vault), 1000);
        uint256 expectedFee = amount.mulDiv(1000, MAX_FEE, Math.Rounding.Ceil);
        uint256 bobBalanceBefore = collateral.balanceOf(bob);
        uint256 vaultBalanceBefore = collateral.balanceOf(address(vault));

        vm.prank(alice);
        (uint256 withdrawnAssets, uint256 burnedShares) = VaultV2(address(vault)).instantWithdraw(bob, amount);

        assertEq(withdrawnAssets, amount);
        assertGt(burnedShares, 0);
        assertEq(collateral.balanceOf(bob) - bobBalanceBefore, amount - expectedFee);
        assertEq(collateral.balanceOf(address(vault)), vaultBalanceBefore - amount + expectedFee);
        assertEq(rewards.donationRewardCalls(), 1);
        assertEq(rewards.lastDonationVault(), address(vault));
        assertEq(rewards.lastDonationAmount(), expectedFee);
    }

    function test_InstantWithdraw_withFee_usesCappedWithdrawnAmountNotRequestedAmount() public {
        vault = _getUniversalVault(7 days);
        _deposit(alice, 100);

        uint256 buffer = IUniversalDelegator(vault.delegator()).getWithdrawalBuffer();
        assertEq(buffer, 100);

        feeRegistry.setInstantWithdrawFee(address(vault), 1000);
        uint256 expectedFee = buffer.mulDiv(1000, MAX_FEE, Math.Rounding.Ceil);
        uint256 aliceBalanceBefore = collateral.balanceOf(alice);

        vm.prank(alice);
        (uint256 withdrawnAssets, uint256 burnedShares) = VaultV2(address(vault)).instantWithdraw(alice, buffer + 50);

        assertEq(withdrawnAssets, buffer);
        assertEq(collateral.balanceOf(alice) - aliceBalanceBefore, buffer - expectedFee);
        assertEq(rewards.donationRewardCalls(), 0);
        assertEq(vault.activeSharesOf(alice), 0);
        assertGt(burnedShares, 0);
    }

    function test_InstantWithdraw_withFee_skipsDonationWhenWithdrawalEmptiesVault() public {
        vault = _getUniversalVault(7 days);
        _deposit(alice, 100);

        feeRegistry.setInstantWithdrawFee(address(vault), 1000);

        uint256 amount = IUniversalDelegator(vault.delegator()).getWithdrawalBuffer();
        uint256 expectedFee = amount.mulDiv(1000, MAX_FEE, Math.Rounding.Ceil);
        uint256 aliceBalanceBefore = collateral.balanceOf(alice);
        uint256 vaultBalanceBefore = collateral.balanceOf(address(vault));

        vm.prank(alice);
        (uint256 withdrawnAssets, uint256 burnedShares) = VaultV2(address(vault)).instantWithdraw(alice, amount);

        assertEq(withdrawnAssets, amount);
        assertGt(burnedShares, 0);
        assertEq(collateral.balanceOf(alice) - aliceBalanceBefore, amount - expectedFee);
        assertEq(collateral.balanceOf(address(vault)), vaultBalanceBefore - amount + expectedFee);
        assertEq(rewards.donationRewardCalls(), 0);
        assertEq(vault.activeStake(), 0);
        assertEq(vault.activeWithdrawals(), 0);
    }

    function test_InstantWithdraw_capsByAvailableToSlash() public {
        vault = _getUniversalVault(7 days);
        _deposit(alice, 100);

        MockAdapter adapter = _createAdapter();
        _addAdapter(adapter);
        _activateAdapterLimit();

        vm.prank(address(adapter));
        vault.allocateAdapter(address(adapter), 80);
        assertEq(vault.adapterAllocated(address(adapter)), 80);

        uint256 buffer = IUniversalDelegator(vault.delegator()).getWithdrawalBuffer();
        assertEq(buffer, 100);

        uint256 liquidBefore = collateral.balanceOf(address(vault));
        assertEq(liquidBefore, 20);

        vm.prank(alice);
        (uint256 withdrawnAssets, uint256 burnedShares) = VaultV2(address(vault)).instantWithdraw(alice, 60);

        assertEq(withdrawnAssets, 60);
        assertGt(burnedShares, 0);
        assertEq(collateral.balanceOf(address(vault)), 0);
        assertEq(vault.adapterAllocated(address(adapter)), 40);
    }

    function test_InstantWithdraw_revertsWhenItWouldConsumeNoAdaptersReserve() public {
        (vault,,) = _getUniversalVaultAndDelegatorAndSlasher(7 days);
        _deposit(alice, 100);

        IUniversalDelegator universalDelegator = IUniversalDelegator(vault.delegator());
        vm.prank(alice);
        universalDelegator.createSlot(address(0xA11CE).subnetwork(0), 0, false, true, 40);
        assertEq(universalDelegator.getNoAdaptersSize(), 40);

        MockAdapter adapter = _createAdapter();
        _addAdapter(adapter);
        _activateAdapterLimit();

        vm.prank(address(adapter));
        vault.allocateAdapter(address(adapter), 80);
        assertEq(vault.adapterAllocated(address(adapter)), 60);
        assertEq(collateral.balanceOf(address(vault)), 40);

        adapter.setShouldFail(true);

        vm.prank(alice);
        vm.expectRevert(IVaultV2.InsufficientAmount.selector);
        VaultV2(address(vault)).instantWithdraw(alice, 10);
    }

    function test_InstantWithdraw_deallocatesAdapterToPreserveNoAdaptersReserve() public {
        (vault,,) = _getUniversalVaultAndDelegatorAndSlasher(7 days);
        _deposit(alice, 100);

        IUniversalDelegator universalDelegator = IUniversalDelegator(vault.delegator());
        vm.prank(alice);
        universalDelegator.createSlot(address(0xA11CE).subnetwork(0), 0, false, true, 40);
        assertEq(universalDelegator.getNoAdaptersSize(), 40);

        MockAdapter adapter = _createAdapter();
        _addAdapter(adapter);
        _activateAdapterLimit();

        vm.prank(address(adapter));
        vault.allocateAdapter(address(adapter), 80);

        assertEq(vault.adapterAllocated(address(adapter)), 60);
        assertEq(collateral.balanceOf(address(vault)), 40);
        assertEq(adapter.deallocatable(address(vault)), 60);

        vm.prank(alice);
        (uint256 withdrawnAssets, uint256 burnedShares) = VaultV2(address(vault)).instantWithdraw(alice, 10);

        assertEq(withdrawnAssets, 10);
        assertGt(burnedShares, 0);
        assertEq(vault.adapterAllocated(address(adapter)), 50);
        assertEq(collateral.balanceOf(address(vault)), 40);
        assertEq(universalDelegator.getNoAdaptersSize(), 40);
    }

    function test_InstantWithdraw_allowsLiquidityAboveNoAdaptersReserve() public {
        (vault,,) = _getUniversalVaultAndDelegatorAndSlasher(7 days);
        _deposit(alice, 100);

        IUniversalDelegator universalDelegator = IUniversalDelegator(vault.delegator());
        vm.prank(alice);
        universalDelegator.createSlot(address(0xB0B).subnetwork(0), 0, false, true, 40);
        assertEq(universalDelegator.getNoAdaptersSize(), 40);

        MockAdapter adapter = _createAdapter();
        _addAdapter(adapter);
        _activateAdapterLimit();

        vm.prank(address(adapter));
        vault.allocateAdapter(address(adapter), 50);
        assertEq(vault.adapterAllocated(address(adapter)), 50);
        assertEq(collateral.balanceOf(address(vault)), 50);

        vm.prank(alice);
        (uint256 withdrawnAssets, uint256 burnedShares) = VaultV2(address(vault)).instantWithdraw(alice, 10);

        assertEq(withdrawnAssets, 10);
        assertGt(burnedShares, 0);
        assertEq(vault.adapterAllocated(address(adapter)), 50);
        assertEq(collateral.balanceOf(address(vault)), 40);
        assertEq(universalDelegator.getNoAdaptersSize(), 40);
    }

    function test_InstantWithdrawRevertInsufficientAmount() public {
        vault = _getUniversalVault(7 days);
        _deposit(alice, 100);

        vm.prank(alice);
        vm.expectRevert(IVaultV2.InsufficientAmount.selector);
        VaultV2(address(vault)).instantWithdraw(alice, 0);
    }

    function test_InstantWithdrawRevertInvalidRecipient() public {
        vault = _getUniversalVault(7 days);
        _deposit(alice, 100);

        vm.prank(alice);
        vm.expectRevert(IVaultV2.InvalidAddress.selector);
        VaultV2(address(vault)).instantWithdraw(address(0), 1);
    }

    function test_InstantWithdrawRevertTooMuchWithdraw() public {
        vault = _getUniversalVault(7 days);
        _deposit(alice, 100);

        vm.prank(bob);
        vm.expectRevert(IVaultV2.TooMuchWithdraw.selector);
        VaultV2(address(vault)).instantWithdraw(bob, 1);
    }

    function test_SetAdapterLimitRevertTooManyAdapters() public {
        vault = _getUniversalVault(7 days);
        vm.warp(block.timestamp + vault.epochDuration() + 1);
        _grantAddAdapterRole(alice, alice);

        for (uint256 i; i < MAX_ADAPTERS; ++i) {
            MockAdapter adapter = _createAdapter();
            vm.prank(alice);
            VaultV2(address(vault)).setAdapterLimit(address(adapter), 1);
        }

        MockAdapter extraAdapter = _createAdapter();
        vm.startPrank(alice);
        vm.expectRevert(IVaultV2.TooManyAdapters.selector);
        VaultV2(address(vault)).setAdapterLimit(address(extraAdapter), 1);
        vm.stopPrank();
    }

    function test_AllocateAdapterRevertFeeOnTransferNotSupported() public {
        collateral = Token(address(feeOnTransferCollateral));
        vault = _getUniversalVault(7 days);

        uint256 depositAmount = 100;
        feeOnTransferCollateral.transfer(alice, depositAmount + 1);
        vm.startPrank(alice);
        feeOnTransferCollateral.approve(address(vault), depositAmount);
        vault.deposit(alice, depositAmount);
        vm.stopPrank();

        MockAdapter adapter = _createAdapter();
        _addAdapter(adapter);
        _activateAdapterLimit();

        vm.prank(address(adapter));
        vm.expectRevert(IVaultV2.FeeOnTransferNotSupported.selector);
        vault.allocateAdapter(address(adapter), 10);
    }

    function test_SyncOwedSlashRevertNotSlasher() public {
        vault = _getUniversalVault(7 days);

        vm.expectRevert(IVaultV2.NotSlasher.selector);
        VaultV2(address(vault)).syncOwedSlash(1);
    }

    function test_SkimAdapters() public {
        vault = _getUniversalVault(7 days);
        _deposit(alice, 100);

        MockAdapter adapter = _createAdapter();
        _addAdapter(adapter);
        _activateAdapterLimit();

        vm.prank(address(adapter));
        vault.allocateAdapter(address(adapter), 30);
        assertEq(collateral.balanceOf(address(adapter)), 30);

        VaultV2(address(vault)).skimAdapters();
        assertEq(collateral.balanceOf(address(adapter)), 0);
    }

    function test_MorphoAllocateAdapter_deallocateSkimsAndDonatesRewards() public {
        vault = _getUniversalVault(7 days);
        _deposit(alice, 100);

        MockMorphoVault morphoVault = new MockMorphoVault(address(collateral));
        MockMorphoAllocateAdapter adapter = new MockMorphoAllocateAdapter(address(rewards), address(curatorRegistry));
        _setMorphoVaultAndAdapter(adapter, address(vault), address(morphoVault));

        uint256 minTimestamp = uint256(vault.epochDuration()) + 1;
        if (block.timestamp < minTimestamp) {
            vm.warp(minTimestamp);
        }
        _grantAddAdapterRole(alice, alice);
        vm.prank(alice);
        VaultV2(address(vault)).setAdapterLimit(address(adapter), type(uint208).max);

        vm.prank(address(adapter));
        vault.allocateAdapter(address(adapter), 80);
        assertEq(vault.adapterAllocated(address(adapter)), 80);

        collateral.approve(address(morphoVault), 20);
        morphoVault.donateYield(20);

        uint256 activeStakeBefore = vault.activeStake();
        uint256 vaultBalanceBefore = collateral.balanceOf(address(vault));
        uint256 expectedSkimmed = adapter.skimmable(address(vault));

        vm.prank(address(adapter));
        uint256 deallocated = vault.deallocateAdapter(address(adapter), 10);

        assertEq(deallocated, 10);
        assertEq(vault.adapterAllocated(address(adapter)), 70);
        assertEq(vault.activeStake(), activeStakeBefore + expectedSkimmed);
        assertEq(collateral.balanceOf(address(vault)), vaultBalanceBefore + expectedSkimmed + deallocated);
        assertEq(collateral.balanceOf(address(rewards)), 0);
    }

    function test_MorphoAllocateAdapter_skimAdaptersDonatesRewards() public {
        vault = _getUniversalVault(7 days);
        _deposit(alice, 100);

        MockMorphoVault morphoVault = new MockMorphoVault(address(collateral));
        MockMorphoAllocateAdapter adapter = new MockMorphoAllocateAdapter(address(rewards), address(curatorRegistry));
        _setMorphoVaultAndAdapter(adapter, address(vault), address(morphoVault));

        uint256 minTimestamp = uint256(vault.epochDuration()) + 1;
        if (block.timestamp < minTimestamp) {
            vm.warp(minTimestamp);
        }
        _grantAddAdapterRole(alice, alice);
        vm.prank(alice);
        VaultV2(address(vault)).setAdapterLimit(address(adapter), type(uint208).max);

        vm.prank(address(adapter));
        vault.allocateAdapter(address(adapter), 80);
        assertEq(vault.adapterAllocated(address(adapter)), 80);

        collateral.approve(address(morphoVault), 20);
        morphoVault.donateYield(20);

        uint256 activeStakeBefore = vault.activeStake();
        uint256 vaultBalanceBefore = collateral.balanceOf(address(vault));
        uint256 expectedSkimmed = adapter.skimmable(address(vault));

        VaultV2(address(vault)).skimAdapters();

        assertEq(vault.adapterAllocated(address(adapter)), 80);
        assertEq(vault.activeStake(), activeStakeBefore + expectedSkimmed);
        assertEq(collateral.balanceOf(address(vault)), vaultBalanceBefore + expectedSkimmed);
        assertEq(collateral.balanceOf(address(rewards)), 0);
    }

    function test_MorphoAllocateAdapter_instantWithdrawDeallocatesAndDonatesRewards() public {
        (vault,,) = _getUniversalVaultAndDelegatorAndSlasher(7 days);
        _deposit(alice, 100);

        MockMorphoVault morphoVault = new MockMorphoVault(address(collateral));
        MockMorphoAllocateAdapter adapter = new MockMorphoAllocateAdapter(address(rewards), address(curatorRegistry));
        _setMorphoVaultAndAdapter(adapter, address(vault), address(morphoVault));

        uint256 minTimestamp = uint256(vault.epochDuration()) + 1;
        if (block.timestamp < minTimestamp) {
            vm.warp(minTimestamp);
        }
        _grantAddAdapterRole(alice, alice);
        vm.prank(alice);
        VaultV2(address(vault)).setAdapterLimit(address(adapter), type(uint208).max);

        IUniversalDelegator universalDelegator = IUniversalDelegator(vault.delegator());
        vm.prank(alice);
        universalDelegator.createSlot(address(0xD00D).subnetwork(0), 0, false, true, 40);
        assertEq(universalDelegator.getNoAdaptersSize(), 40);

        vm.prank(address(adapter));
        vault.allocateAdapter(address(adapter), 80);
        assertEq(vault.adapterAllocated(address(adapter)), 60);

        collateral.approve(address(morphoVault), 20);
        morphoVault.donateYield(20);

        uint256 activeStakeBefore = vault.activeStake();
        uint256 vaultBalanceBefore = collateral.balanceOf(address(vault));
        uint256 expectedSkimmed = adapter.skimmable(address(vault));

        vm.prank(alice);
        (uint256 withdrawnAssets, uint256 burnedShares) = VaultV2(address(vault)).instantWithdraw(alice, 10);

        assertEq(withdrawnAssets, 10);
        assertGt(burnedShares, 0);
        assertEq(vault.adapterAllocated(address(adapter)), 50);
        assertEq(vault.activeStake(), activeStakeBefore - withdrawnAssets + expectedSkimmed);
        assertEq(collateral.balanceOf(address(vault)), vaultBalanceBefore + expectedSkimmed + 10 - withdrawnAssets);
        assertEq(collateral.balanceOf(address(rewards)), 0);
    }

    function test_MorphoAllocateAdapter_donatesDuringDepositAndWithdrawOperations() public {
        vault = _getUniversalVault(7 days);

        MockMorphoVault morphoVault = new MockMorphoVault(address(collateral));
        MockMorphoAllocateAdapter morphoAdapter =
            new MockMorphoAllocateAdapter(address(rewards), address(curatorRegistry));
        _setMorphoVaultAndAdapter(morphoAdapter, address(vault), address(morphoVault));

        _grantAddAdapterRole(alice, alice);
        vm.prank(alice);
        VaultV2(address(vault)).setAdapterLimit(address(morphoAdapter), type(uint208).max);

        _deposit(alice, 100);
        assertEq(vault.adapterAllocated(address(morphoAdapter)), 100);
        assertEq(vault.activeStake(), 100);
        uint256 activeStakeBeforeBob = vault.activeStake();

        collateral.approve(address(morphoVault), 20);
        morphoVault.donateYield(20);
        uint256 expectedSkimmedDeposit = morphoAdapter.skimmable(address(vault));

        _deposit(bob, 10);
        assertEq(vault.activeStake(), activeStakeBeforeBob + 10 + expectedSkimmedDeposit);
        assertEq(vault.adapterAllocated(address(morphoAdapter)), 110);
        assertEq(collateral.balanceOf(address(rewards)), 0);

        collateral.approve(address(morphoVault), 10);
        morphoVault.donateYield(10);
        uint256 activeStakeBeforeWithdraw = vault.activeStake();
        uint256 expectedSkimmedWithdraw = morphoAdapter.skimmable(address(vault));

        _withdraw(alice, 30);
        assertEq(vault.activeStake(), activeStakeBeforeWithdraw + expectedSkimmedWithdraw - 30);
        assertEq(vault.activeWithdrawals(), 30);
        assertEq(vault.adapterAllocated(address(morphoAdapter)), 110);
        assertEq(collateral.balanceOf(address(rewards)), 0);
    }

    function test_MorphoAdapterSkimDuringDeposit_doesNotDiluteClaimableWithdrawals() public {
        vault = _getUniversalVault(7 days);

        MockMorphoVault morphoVault = new MockMorphoVault(address(collateral));
        MockMorphoAllocateAdapter morphoAdapter =
            new MockMorphoAllocateAdapter(address(rewards), address(curatorRegistry));
        _setMorphoVaultAndAdapter(morphoAdapter, address(vault), address(morphoVault));

        _grantAddAdapterRole(alice, alice);
        vm.prank(alice);
        VaultV2(address(vault)).setAdapterLimit(address(morphoAdapter), type(uint208).max);

        _deposit(alice, 100);
        _deposit(bob, 100);

        vm.warp(block.timestamp + 1);
        _withdraw(alice, 40);

        vm.warp(block.timestamp + uint256(vault.epochDuration()) + 1);
        _withdraw(bob, 30);

        uint256 donation = 20;
        uint48 aliceUnlockAfter = vault.withdrawalUnlockAt(0, alice);
        uint48 bobUnlockAfter = vault.withdrawalUnlockAt(0, bob);
        uint256 aliceClaimableBefore = vault.withdrawalsOf(0, alice);
        uint256 bucketBefore = _latestWithdrawalBucket();
        uint256 expectedBobAfter;
        {
            uint256 curActiveStake = vault.activeStake();
            uint256 curActiveWithdrawals = vault.activeWithdrawals();
            uint256 curActiveWithdrawalShares = _unmaturedWithdrawalShares(uint48(block.timestamp));
            uint256 bobSharesBefore = vault.withdrawalSharesOf(0, bob);
            uint256 expectedWithdrawalsDonated =
                donation.mulDiv(curActiveWithdrawals, curActiveStake + curActiveWithdrawals);
            uint256 expectedNewActiveWithdrawals = curActiveWithdrawals + expectedWithdrawalsDonated;
            expectedBobAfter =
                ERC4626Math.previewRedeem(bobSharesBefore, expectedNewActiveWithdrawals, curActiveWithdrawalShares);
        }

        collateral.approve(address(morphoVault), donation);
        morphoVault.donateYield(donation);

        _deposit(alice, 2);

        uint256 aliceClaimableAfter = vault.withdrawalsOf(0, alice);
        uint256 bobActiveAfter = vault.withdrawalsOf(0, bob);
        uint256 bucketAfter = _latestWithdrawalBucket();

        assertEq(aliceClaimableAfter, aliceClaimableBefore);
        assertEq(bobActiveAfter, expectedBobAfter);
        assertEq(bucketAfter, bucketBefore + 1);
        assertEq(vaultTestHelper.unlockToBucketUpperLookupRecent(address(vault), aliceUnlockAfter), bucketBefore);
        assertEq(vaultTestHelper.unlockToBucketUpperLookupRecent(address(vault), bobUnlockAfter), bucketAfter);
        assertEq(collateral.balanceOf(address(rewards)), 0);
    }

    function test_MorphoBorrowAdapter_deallocateSkimsAndDonatesRewards() public {
        vault = _getUniversalVault(7 days);
        _deposit(alice, 100);

        MockMorphoVault morphoVault = new MockMorphoVault(address(collateral));
        MockMorphoAllocateAdapter adapter1 = new MockMorphoAllocateAdapter(address(rewards), address(curatorRegistry));
        MockMorphoBorrowAdapter adapter2 =
            new MockMorphoBorrowAdapter(address(vault), address(collateral), address(morphoVault), address(rewards));
        _setMorphoVaultAndAdapter(adapter1, address(vault), address(morphoVault));
        adapterRegistry.whitelistAdapter(address(adapter2));

        uint256 minTimestamp = uint256(vault.epochDuration()) + 1;
        if (block.timestamp < minTimestamp) {
            vm.warp(minTimestamp);
        }
        _grantAddAdapterRole(alice, alice);
        vm.startPrank(alice);
        VaultV2(address(vault)).setAdapterLimit(address(adapter1), type(uint208).max);
        VaultV2(address(vault)).setAdapterLimit(address(adapter2), type(uint208).max);
        vm.stopPrank();

        vm.prank(address(adapter1));
        vault.allocateAdapter(address(adapter1), 80);
        assertEq(vault.adapterAllocated(address(adapter1)), 80);

        collateral.approve(address(morphoVault), 20);
        morphoVault.donateYield(20);

        uint256 activeStakeBefore = vault.activeStake();
        uint256 vaultBalanceBefore = collateral.balanceOf(address(vault));
        uint256 expectedSkimmed = adapter1.skimmable(address(vault));

        vm.prank(address(adapter2));
        adapter2.borrow(30);

        assertEq(vault.activeStake(), activeStakeBefore + expectedSkimmed);
        assertEq(collateral.balanceOf(address(vault)), vaultBalanceBefore + expectedSkimmed);
        assertEq(vault.adapterAllocated(address(adapter1)), 50);
        assertEq(vault.adapterAllocated(address(adapter2)), 30);
        assertEq(collateral.balanceOf(address(rewards)), 0);
    }

    function test_MorphoBorrowAdapter_borrowDeallocatesMorphoThenAllocatesBorrow() public {
        vault = _getUniversalVault(7 days);

        MockMorphoVault morphoVault = new MockMorphoVault(address(collateral));
        MockMorphoAllocateAdapter morphoAdapter =
            new MockMorphoAllocateAdapter(address(rewards), address(curatorRegistry));
        MockMorphoBorrowAdapter borrowAdapter =
            new MockMorphoBorrowAdapter(address(vault), address(collateral), address(morphoVault), address(rewards));
        _setMorphoVaultAndAdapter(morphoAdapter, address(vault), address(morphoVault));
        adapterRegistry.whitelistAdapter(address(borrowAdapter));

        _grantAddAdapterRole(alice, alice);
        vm.startPrank(alice);
        VaultV2(address(vault)).setAdapterLimit(address(morphoAdapter), type(uint208).max);
        VaultV2(address(vault)).setAdapterLimit(address(borrowAdapter), type(uint208).max);
        vm.stopPrank();

        _deposit(alice, 100);
        assertEq(vault.adapterAllocated(address(morphoAdapter)), 100);
        assertEq(vault.adapterAllocated(address(borrowAdapter)), 0);

        vm.recordLogs();
        vm.prank(address(borrowAdapter));
        uint256 borrowed = borrowAdapter.borrow(30);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 deallocateSig = keccak256("Deallocate(address,uint256)");
        bytes32 allocateSig = keccak256("Allocate(address,uint256)");
        uint8[2] memory kinds;
        address[2] memory adapters_;
        uint256[2] memory amounts;
        uint256 found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(vault) || logs[i].topics.length < 2) {
                continue;
            }
            bytes32 sig = logs[i].topics[0];
            if (sig != deallocateSig && sig != allocateSig) {
                continue;
            }

            kinds[found] = sig == deallocateSig ? 1 : 2;
            adapters_[found] = address(uint160(uint256(logs[i].topics[1])));
            amounts[found] = abi.decode(logs[i].data, (uint256));
            ++found;
            if (found == 2) {
                break;
            }
        }

        assertEq(borrowed, 30);
        assertEq(found, 2);
        assertEq(kinds[0], 1);
        assertEq(adapters_[0], address(morphoAdapter));
        assertEq(amounts[0], 30);
        assertEq(kinds[1], 2);
        assertEq(adapters_[1], address(borrowAdapter));
        assertEq(amounts[1], 30);
        assertEq(vault.adapterAllocated(address(morphoAdapter)), 70);
        assertEq(vault.adapterAllocated(address(borrowAdapter)), 30);
    }

    function test_DeallocateAdapters() public {
        (vault,, slasher) = _getUniversalVaultAndDelegatorAndSlasher(7 days);
        _deposit(alice, 100);

        MockAdapter adapter = _createAdapter();
        _addAdapter(adapter);
        _activateAdapterLimit();

        vm.prank(address(adapter));
        vault.allocateAdapter(address(adapter), 80);

        adapter.setShouldFail(true);
        vm.prank(address(slasher));
        VaultV2(address(vault)).onSlash(60, true);

        uint256 totalStakeAfterSlash = vault.totalStake();
        assertEq(totalStakeAfterSlash, 40);

        adapter.setShouldFail(false);
        VaultV2(address(vault)).deallocateAdapters();

        assertEq(vault.adaptersAllocated(), totalStakeAfterSlash);
        assertEq(vault.adapterAllocated(address(adapter)), totalStakeAfterSlash);
    }

    function test_TransferUpdatesActiveShares() public {
        vault = _getVault(7 days);
        _deposit(alice, 100);

        uint256 sharesToTransfer = vault.activeSharesOf(alice) / 2;
        vm.prank(alice);
        VaultV2(address(vault)).transfer(bob, sharesToTransfer);

        assertEq(vault.activeSharesOf(bob), sharesToTransfer);
        assertEq(vault.activeSharesOf(alice), VaultV2(address(vault)).balanceOf(alice));
    }

    function test_SetAdapterLimitAfterMigration() public {
        uint48 epochDuration = 7 days;
        uint256 blockTimestamp = vm.getBlockTimestamp() + 1_720_700_948;
        vm.warp(blockTimestamp);

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
        (IVaultV2 vault_,,) = _createInitializedVaultWithOwner(
            epochDuration,
            networkLimitSetRoleHolders,
            operatorNetworkSharesSetRoleHolders,
            1,
            address(0xdEaD),
            false,
            false,
            0,
            address(this)
        );
        VaultV1 vaultV1 = VaultV1(address(vault_));

        bytes memory migrateData = abi.encode(_buildMigrateParams(epochDuration));
        vaultFactory.migrate(address(vaultV1), vaultFactory.lastVersion(), migrateData);

        IVaultV2 vaultV2 = IVaultV2(address(vaultV1));
        vm.prank(alice);
        VaultV2(address(vaultV2)).grantRole(SET_ADAPTER_LIMIT_ROLE, alice);

        MockAdapter adapter = new MockAdapter(address(vaultV2), address(collateral));
        adapterRegistry.whitelistAdapter(address(adapter));

        vm.prank(alice);
        VaultV2(address(vaultV2)).setAdapterLimit(address(adapter), 1);

        assertEq(vaultV2.adaptersLength(), 1);
        assertEq(vaultV2.adapters(0), address(adapter));
    }

    function test_CreateRevertDepositorToWhitelistInvalidAddress() public {
        IVaultV2.InitParams memory params = _defaultVaultInitParams(7 days);
        params.depositorToWhitelist = address(0);
        uint64 lastVersion = vaultFactory.lastVersion();

        vm.expectRevert(IVaultV2.InvalidDepositorToWhitelist.selector);
        vaultFactory.create(lastVersion, alice, _getEncodedVaultParams(params));
    }

    function test_CreateSetsDepositorToWhitelist() public {
        IVaultV2.InitParams memory params = _defaultVaultInitParams(7 days);
        params.depositorToWhitelist = bob;

        vault = IVaultV2(vaultFactory.create(vaultFactory.lastVersion(), alice, _getEncodedVaultParams(params)));
        assertEq(vault.isDepositorWhitelisted(bob), true);
    }

    function test_CreateWithDepositorWhitelisted() public {
        IVaultV2.InitParams memory params = _defaultVaultInitParams(7 days);
        params.depositWhitelist = true;
        params.depositorToWhitelist = bob;

        vault = IVaultV2(vaultFactory.create(vaultFactory.lastVersion(), alice, _getEncodedVaultParams(params)));
        assertEq(vault.isDepositorWhitelisted(bob), true);

        _deposit(bob, 1);

        address notWhitelisted = makeAddr("notWhitelisted");
        collateral.transfer(notWhitelisted, 1);
        vm.startPrank(notWhitelisted);
        collateral.approve(address(vault), 1);
        vm.expectRevert(IVaultV2.NotWhitelistedDepositor.selector);
        vault.deposit(notWhitelisted, 1);
        vm.stopPrank();
    }

    function test_TokenizedMetadataAndErc20Views() public {
        uint48 epochDuration = 7 days;
        vault = _getVault(epochDuration);

        VaultV2 tokenizedVault = VaultV2(address(vault));
        assertEq(tokenizedVault.balanceOf(alice), 0);
        assertEq(tokenizedVault.totalSupply(), 0);
        assertEq(tokenizedVault.allowance(alice, alice), 0);
        assertEq(tokenizedVault.decimals(), collateral.decimals());
        assertEq(tokenizedVault.symbol(), VAULT_SYMBOL);
        assertEq(tokenizedVault.name(), VAULT_NAME);
    }

    function test_TokenizedBalances_matchSharesAfterDepositTwice(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        (, uint256 shares1) = _deposit(alice, amount1);
        vm.warp(block.timestamp + 1);
        (, uint256 shares2) = _deposit(alice, amount2);

        VaultV2 tokenizedVault = VaultV2(address(vault));
        assertEq(tokenizedVault.balanceOf(alice), shares1 + shares2);
        assertEq(tokenizedVault.totalSupply(), shares1 + shares2);
    }

    function test_TokenizedBalances_matchSharesAfterDepositBoth(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        (, uint256 shares1) = _deposit(alice, amount1);
        vm.warp(block.timestamp + 1);
        (, uint256 shares2) = _deposit(bob, amount2);

        VaultV2 tokenizedVault = VaultV2(address(vault));
        assertEq(tokenizedVault.balanceOf(alice), shares1);
        assertEq(tokenizedVault.balanceOf(bob), shares2);
        assertEq(tokenizedVault.totalSupply(), shares1 + shares2);
    }

    function test_TokenizedBalances_matchSharesAfterWithdrawTwice(uint256 amount1, uint256 amount2, uint256 amount3)
        public
    {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount3, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2 + amount3);

        vault = _getVault(1);

        _deposit(alice, amount1);
        vm.warp(block.timestamp + 1);
        _withdraw(alice, amount2);
        vm.warp(block.timestamp + 1);
        _withdraw(alice, amount3);

        VaultV2 tokenizedVault = VaultV2(address(vault));
        assertEq(tokenizedVault.balanceOf(alice), vault.activeSharesOf(alice));
        assertEq(tokenizedVault.totalSupply(), vault.activeShares());
    }

    function test_Transfer(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        vault = _getVault(1);

        (, uint256 mintedShares) = _deposit(alice, amount1);

        VaultV2 tokenizedVault = VaultV2(address(vault));
        assertEq(tokenizedVault.balanceOf(alice), mintedShares);
        assertEq(tokenizedVault.totalSupply(), mintedShares);
        assertEq(vault.activeSharesOf(alice), mintedShares);
        assertEq(vault.activeShares(), mintedShares);

        if (amount2 > mintedShares) {
            vm.startPrank(alice);
            vm.expectRevert();
            tokenizedVault.transfer(bob, amount2);
            vm.stopPrank();
            return;
        }

        vm.startPrank(alice);
        tokenizedVault.transfer(bob, amount2);
        vm.stopPrank();

        assertEq(tokenizedVault.balanceOf(alice), mintedShares - amount2);
        assertEq(tokenizedVault.totalSupply(), mintedShares);
        assertEq(vault.activeSharesOf(alice), mintedShares - amount2);
        assertEq(vault.activeShares(), mintedShares);

        assertEq(tokenizedVault.balanceOf(bob), amount2);
        assertEq(vault.activeSharesOf(bob), amount2);

        vm.startPrank(bob);
        tokenizedVault.approve(alice, amount2);
        vm.stopPrank();

        assertEq(tokenizedVault.allowance(bob, alice), amount2);

        vm.startPrank(alice);
        tokenizedVault.transferFrom(bob, alice, amount2);
        vm.stopPrank();

        assertEq(tokenizedVault.balanceOf(alice), mintedShares);
        assertEq(tokenizedVault.totalSupply(), mintedShares);
        assertEq(vault.activeSharesOf(alice), mintedShares);
        assertEq(vault.activeShares(), mintedShares);
    }

    function test_Migrate_FactoryUpgradePath_preservesNameAndSymbol() public {
        uint48 epochDuration = 10;

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;

        uint48 vetoDuration = epochDuration > 1 ? 1 : 0;
        bytes memory vetoSlasherParams = abi.encode(
            IVetoSlasher.InitParams({
                baseParams: IBaseSlasher.BaseParams({isBurnerHook: false}),
                vetoDuration: vetoDuration,
                resolverSetEpochsDelay: 3
            })
        );
        (IVaultV2 vault_,,) = _createInitializedVaultWithOwnerAndSlasher(
            epochDuration,
            networkLimitSetRoleHolders,
            operatorNetworkSharesSetRoleHolders,
            2,
            address(0xdEaD),
            false,
            false,
            0,
            address(this),
            1,
            vetoSlasherParams
        );
        vault = IVaultV2(address(vault_));
        address oldSlasher = vault.slasher();

        assertEq(VaultV2(address(vault)).name(), VAULT_NAME);
        assertEq(VaultV2(address(vault)).symbol(), VAULT_SYMBOL);

        bytes memory migrateData = abi.encode(_buildMigrateParams(epochDuration));
        vaultFactory.migrate(address(vault), vaultFactory.lastVersion(), migrateData);

        IVaultV2 vaultV2 = IVaultV2(address(vault));
        _assertMigrationState(vaultV2, oldSlasher);
        assertEq(VaultV2(address(vaultV2)).name(), VAULT_NAME);
        assertEq(VaultV2(address(vaultV2)).symbol(), VAULT_SYMBOL);
    }

    function _latestWithdrawalBucket() internal view returns (uint256) {
        return vaultTestHelper.unlockToBucketLatest(address(vault));
    }

    function _unmaturedWithdrawalShares(uint48 timestamp) internal view returns (uint256) {
        return vaultTestHelper.withdrawalSharesCumulativeLatest(address(vault))
            - vaultTestHelper.withdrawalSharesCumulativeUpperLookupRecent(address(vault), timestamp);
    }

    function _sumUnclaimableWithdrawalRequestSharesAt(address account, uint48 timestamp)
        internal
        view
        returns (uint256 total)
    {
        uint256 length = vault.withdrawalsOfLength(account);
        for (uint256 i; i < length; ++i) {
            if (vault.withdrawalUnlockAt(i, account) > timestamp) {
                total += vault.withdrawalSharesOf(i, account);
            }
        }
    }

    function _sumCurrentUnclaimableWithdrawalRequestShares(address account) internal view returns (uint256 total) {
        return _sumUnclaimableWithdrawalRequestSharesAt(account, uint48(block.timestamp));
    }

    function _sumCurrentUnclaimableWithdrawalRequestShares(address[] memory accounts)
        internal
        view
        returns (uint256 total)
    {
        for (uint256 i; i < accounts.length; ++i) {
            total += _sumCurrentUnclaimableWithdrawalRequestShares(accounts[i]);
        }
    }

    function _assertActiveWithdrawalSharesMatchesCurrentUnclaimableRequestShares(address[] memory accounts)
        internal
        view
    {
        uint256 expectedShares = _sumCurrentUnclaimableWithdrawalRequestShares(accounts);
        assertEq(vault.activeWithdrawalShares(), expectedShares);
        assertEq(vault.activeWithdrawalSharesAt(uint48(block.timestamp)), expectedShares);
    }

    function _assertActiveWithdrawalSharesOfMatchesCurrentUnclaimableRequestShares(address[] memory accounts)
        internal
        view
    {
        uint48 timestamp = uint48(block.timestamp);
        for (uint256 i; i < accounts.length; ++i) {
            uint256 expectedShares = _sumCurrentUnclaimableWithdrawalRequestShares(accounts[i]);
            assertEq(vault.activeWithdrawalSharesOfAt(accounts[i], timestamp), expectedShares);
        }
    }

    function _prepareAdjacentUnlockWithdrawals() internal returns (uint48 aliceUnlockAfter, uint48 bobUnlockAfter) {
        _deposit(alice, 100);
        _deposit(bob, 100);

        vm.warp(block.timestamp + 1);
        _withdraw(alice, 40);
        aliceUnlockAfter = vault.withdrawalUnlockAt(0, alice);

        vm.warp(block.timestamp + 1);
        _withdraw(bob, 30);
        bobUnlockAfter = vault.withdrawalUnlockAt(0, bob);

        vm.warp(aliceUnlockAfter);
    }

    function _prepareAdjacentUnlockWithdrawalsWithUniversalNetwork()
        internal
        returns (
            UniversalDelegator universalDelegator,
            Slasher slasher_,
            uint48 aliceUnlockAfter,
            uint48 bobUnlockAfter
        )
    {
        (vault, universalDelegator, slasher_) = _getUniversalVaultAndDelegatorAndSlasher(7 days);
        delegator = FullRestakeDelegator(address(universalDelegator));
        slasher = slasher_;
        _deposit(alice, 100);
        _deposit(bob, 100);

        vm.warp(block.timestamp + 1);
        _withdraw(alice, 40);
        aliceUnlockAfter = vault.withdrawalUnlockAt(0, alice);

        vm.warp(block.timestamp + 1);
        _withdraw(bob, 30);
        bobUnlockAfter = vault.withdrawalUnlockAt(0, bob);

        vm.warp(aliceUnlockAfter);
    }

    function _expectedTotalStake(uint48 timestamp) internal view returns (uint256) {
        uint256 lastBucket = _latestWithdrawalBucket();
        uint256 lastWithdrawalShares = vault.withdrawalShares(lastBucket);
        uint256 activeStake_ = vault.activeStake();
        if (lastWithdrawalShares == 0) {
            return activeStake_;
        }
        uint256 unmaturedShares = _unmaturedWithdrawalShares(timestamp);
        return activeStake_ + unmaturedShares.mulDiv(vault.withdrawals(lastBucket), lastWithdrawalShares);
    }

    function _prepareVault() internal {
        _registerNetwork(alice, alice);
        _setMaxNetworkLimit(alice, 0, type(uint256).max);

        _registerOperator(alice);
        _registerOperator(bob);

        _optInOperatorVault(alice);
        _optInOperatorVault(bob);

        _optInOperatorNetwork(alice, address(alice));
        _optInOperatorNetwork(bob, address(alice));

        _setNetworkLimit(alice, alice, type(uint256).max);

        _setOperatorNetworkLimit(alice, alice, alice, type(uint256).max / 2);
        _setOperatorNetworkLimit(alice, alice, bob, type(uint256).max / 2);
    }

    function _getVault(uint48 epochDuration) internal returns (IVaultV2) {
        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
        (IVaultV2 vault_,,) = _createInitializedVault(
            epochDuration,
            networkLimitSetRoleHolders,
            operatorNetworkSharesSetRoleHolders,
            vaultFactory.lastVersion(),
            address(0xdEaD),
            false,
            false,
            0
        );
        return vault_;
    }

    function _getUniversalVault(uint48 epochDuration) internal returns (IVaultV2) {
        (IVaultV2 vault_,,) = _createInitializedUniversalVault(
            epochDuration, vaultFactory.lastVersion(), address(0xdEaD), false, false, 0
        );
        return vault_;
    }

    function _getUniversalVaultAndDelegatorAndSlasher(uint48 epochDuration)
        internal
        returns (IVaultV2, UniversalDelegator, Slasher)
    {
        (IVaultV2 vault_, address delegator_, address slasher_) = _createInitializedUniversalVault(
            epochDuration, vaultFactory.lastVersion(), address(0xdEaD), false, false, 0
        );
        return (vault_, UniversalDelegator(delegator_), Slasher(slasher_));
    }

    function _getVaultAndDelegatorAndSlasher(uint48 epochDuration)
        internal
        returns (IVaultV2, FullRestakeDelegator, Slasher)
    {
        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](1);
        operatorNetworkLimitSetRoleHolders[0] = alice;
        (IVaultV2 vault_, address delegator_, address slasher_) = _createInitializedVault(
            epochDuration,
            networkLimitSetRoleHolders,
            operatorNetworkLimitSetRoleHolders,
            vaultFactory.lastVersion(),
            address(0xdEaD),
            false,
            false,
            0
        );

        return (IVaultV2(vault_), FullRestakeDelegator(delegator_), Slasher(slasher_));
    }

    function _registerOperator(address user) internal {
        vm.startPrank(user);
        operatorRegistry.registerOperator();
        vm.stopPrank();
    }

    function _registerNetwork(address user, address middleware) internal {
        vm.startPrank(user);
        networkRegistry.registerNetwork();
        networkMiddlewareService.setMiddleware(middleware);
        vm.stopPrank();
    }

    function _grantDepositorWhitelistRole(address user, address account) internal virtual {
        vm.startPrank(user);
        VaultV2(address(vault)).grantRole(DEPOSITOR_WHITELIST_ROLE, account);
        vm.stopPrank();
    }

    function _grantDepositWhitelistSetRole(address user, address account) internal virtual {
        vm.startPrank(user);
        VaultV2(address(vault)).grantRole(DEPOSIT_WHITELIST_SET_ROLE, account);
        vm.stopPrank();
    }

    function _grantIsDepositLimitSetRole(address user, address account) internal virtual {
        vm.startPrank(user);
        VaultV2(address(vault)).grantRole(IS_DEPOSIT_LIMIT_SET_ROLE, account);
        vm.stopPrank();
    }

    function _grantDepositLimitSetRole(address user, address account) internal virtual {
        vm.startPrank(user);
        VaultV2(address(vault)).grantRole(DEPOSIT_LIMIT_SET_ROLE, account);
        vm.stopPrank();
    }

    function _grantAddAdapterRole(address user, address account) internal virtual {
        vm.startPrank(user);
        VaultV2(address(vault)).grantRole(SET_ADAPTER_LIMIT_ROLE, account);
        vm.stopPrank();
    }

    function _grantRemoveAdapterRole(address user, address account) internal virtual {
        vm.startPrank(user);
        VaultV2(address(vault)).grantRole(SET_ADAPTER_LIMIT_ROLE, account);
        vm.stopPrank();
    }

    function _createAdapter() internal returns (MockAdapter) {
        MockAdapter adapter = new MockAdapter(address(vault), address(collateral));
        adapterRegistry.whitelistAdapter(address(adapter));
        return adapter;
    }

    function _addAdapter(MockAdapter adapter) internal {
        uint256 minTimestamp = uint256(vault.epochDuration()) + 1;
        if (block.timestamp < minTimestamp) {
            vm.warp(minTimestamp);
        }

        _grantAddAdapterRole(alice, alice);
        vm.prank(alice);
        VaultV2(address(vault)).setAdapterLimit(address(adapter), type(uint208).max);
    }

    function _activateAdapterLimit() internal {
        // no-op: adapter activation delay was removed from the vault
    }

    function _deposit(address user, uint256 amount) internal returns (uint256 depositedAmount, uint256 mintedShares) {
        collateral.transfer(user, amount);
        vm.startPrank(user);
        collateral.approve(address(vault), amount);
        (depositedAmount, mintedShares) = vault.deposit(user, amount);
        vm.stopPrank();
    }

    function _withdraw(address user, uint256 amount) internal returns (uint256 burnedShares, uint256 mintedShares) {
        vm.startPrank(user);
        (burnedShares, mintedShares) = vault.withdraw(user, amount);
        vm.stopPrank();
    }

    function _redeem(address user, uint256 shares) internal returns (uint256 withdrawnAssets, uint256 mintedShares) {
        vm.startPrank(user);
        (withdrawnAssets, mintedShares) = vault.redeem(user, shares);
        vm.stopPrank();
    }

    function _claim(address user, uint256 epoch) internal returns (uint256 amount) {
        vm.startPrank(user);
        amount = vault.claim(user, epoch);
        vm.stopPrank();
    }

    function _claimBatch(address user, uint256[] memory indexes) internal returns (uint256 amount) {
        vm.startPrank(user);
        amount = vault.claimBatch(user, indexes);
        vm.stopPrank();
    }

    function _optInOperatorVault(address user) internal {
        vm.startPrank(user);
        operatorVaultOptInService.optIn(address(vault));
        vm.stopPrank();
    }

    function _optOutOperatorVault(address user) internal {
        vm.startPrank(user);
        operatorVaultOptInService.optOut(address(vault));
        vm.stopPrank();
    }

    function _optInOperatorNetwork(address user, address network) internal {
        vm.startPrank(user);
        operatorNetworkOptInService.optIn(network);
        vm.stopPrank();
    }

    function _optOutOperatorNetwork(address user, address network) internal {
        vm.startPrank(user);
        operatorNetworkOptInService.optOut(network);
        vm.stopPrank();
    }

    function _setDepositWhitelist(address user, bool status) internal {
        vm.startPrank(user);
        vault.setDepositWhitelist(status);
        vm.stopPrank();
    }

    function _setDepositorWhitelistStatus(address user, address depositor, bool status) internal {
        vm.startPrank(user);
        vault.setDepositorWhitelistStatus(depositor, status);
        vm.stopPrank();
    }

    function _setIsDepositLimit(address user, bool status) internal {
        vm.startPrank(user);
        vault.setIsDepositLimit(status);
        vm.stopPrank();
    }

    function _setDepositLimit(address user, uint256 amount) internal {
        vm.startPrank(user);
        vault.setDepositLimit(amount);
        vm.stopPrank();
    }

    function _setNetworkLimit(address user, address network, uint256 amount) internal {
        vm.startPrank(user);
        if (IEntity(address(delegator)).TYPE() == UNIVERSAL_DELEGATOR_TYPE) {
            IUniversalDelegator universalDelegator = IUniversalDelegator(address(delegator));
            bytes32 subnetwork = network.subnetwork(0);
            uint96 networkSlot = universalDelegator.getSlotOfNetwork(subnetwork);
            uint128 amount128 = _toUint128(amount);

            if (networkSlot == 0) {
                universalDelegator.createSlot(subnetwork, 0, false, false, amount128);
            } else {
                universalDelegator.setSize(networkSlot, amount128);
            }
        } else {
            delegator.setNetworkLimit(network.subnetwork(0), amount);
        }
        vm.stopPrank();
    }

    function _setOperatorNetworkLimit(address user, address network, address operator, uint256 amount) internal {
        vm.startPrank(user);
        if (IEntity(address(delegator)).TYPE() == UNIVERSAL_DELEGATOR_TYPE) {
            IUniversalDelegator universalDelegator = IUniversalDelegator(address(delegator));
            bytes32 subnetwork = network.subnetwork(0);
            uint96 networkSlot = universalDelegator.getSlotOfNetwork(subnetwork);
            uint128 amount128 = _toUint128(amount);

            if (networkSlot == 0) {
                networkSlot = universalDelegator.createSlot(subnetwork, 0, false, false, amount128);
            }

            uint96 operatorSlot = universalDelegator.getSlotOfOperator(networkSlot, operator);
            if (operatorSlot == 0) {
                universalDelegator.createSlot(bytes32(bytes20(operator)), networkSlot, false, false, amount128);
            } else {
                universalDelegator.setSize(operatorSlot, amount128);
            }
        } else {
            delegator.setOperatorNetworkLimit(network.subnetwork(0), operator, amount);
        }
        vm.stopPrank();
    }

    function _setMorphoVaultAndAdapter(MockMorphoAllocateAdapter adapter, address vaultAddress, address morphoVault)
        internal
    {
        adapterRegistry.whitelistAdapter(address(adapter));
        curatorRegistry.setCurator(vaultAddress, alice);
        vm.prank(alice);
        adapter.setMorhpoVault(vaultAddress, morphoVault);
        adapter.setGlobalLimit(address(collateral), type(uint256).max);
    }

    function _toUint128(uint256 amount) internal pure returns (uint128 amount128) {
        return amount > type(uint128).max ? type(uint128).max : uint128(amount);
    }

    function _slash(
        address user,
        address network,
        address operator,
        uint256 amount,
        uint48 captureTimestamp,
        bytes memory hints
    ) internal returns (uint256 slashAmount) {
        user;
        network;
        operator;
        hints;

        vm.startPrank(address(slasher));
        (slashAmount,) = VaultV2(address(vault)).onSlash(amount, false);
        vm.stopPrank();
    }

    function _setMaxNetworkLimit(address user, uint96 identifier, uint256 amount) internal {
        vm.startPrank(user);
        delegator.setMaxNetworkLimit(identifier, amount);
        vm.stopPrank();
    }

    function _createVaultImpl(address delegatorFactory, address slasherFactory, address vaultFactory)
        internal
        virtual
        returns (address)
    {
        return address(
            new VaultV2(
                delegatorFactory,
                slasherFactory,
                vaultFactory,
                address(feeRegistry),
                address(rewards),
                address(adapterRegistry)
            )
        );
    }

    function _createVaultV1Impl(address delegatorFactory, address slasherFactory, address vaultFactory)
        internal
        virtual
        returns (address)
    {
        return address(new VaultV1(delegatorFactory, slasherFactory, vaultFactory));
    }

    function _createVaultTokenizedImpl(address delegatorFactory, address slasherFactory, address vaultFactory)
        internal
        virtual
        returns (address)
    {
        return address(new VaultTokenized(delegatorFactory, slasherFactory, vaultFactory));
    }

    function _createInitializedVault(
        uint48 epochDuration,
        address[] memory networkLimitSetRoleHolders,
        address[] memory operatorNetworkSharesSetRoleHolders,
        uint64 version,
        address burner,
        bool depositWhitelist,
        bool isDepositLimit,
        uint256 depositLimit
    ) internal virtual returns (IVaultV2, address, address) {
        return _createInitializedVaultWithOwner(
            epochDuration,
            networkLimitSetRoleHolders,
            operatorNetworkSharesSetRoleHolders,
            version,
            burner,
            depositWhitelist,
            isDepositLimit,
            depositLimit,
            address(0)
        );
    }

    function _createInitializedVaultWithOwner(
        uint48 epochDuration,
        address[] memory networkLimitSetRoleHolders,
        address[] memory operatorNetworkSharesSetRoleHolders,
        uint64 version,
        address burner,
        bool depositWhitelist,
        bool isDepositLimit,
        uint256 depositLimit,
        address owner_
    ) internal virtual returns (IVaultV2, address, address) {
        uint64 slasherIndex = 0;
        if (version == VAULT_V2_VERSION) {
            slasherIndex = UNIVERSAL_SLASHER_TYPE;
        }
        return _createInitializedVaultWithOwnerAndSlasher(
            epochDuration,
            networkLimitSetRoleHolders,
            operatorNetworkSharesSetRoleHolders,
            version,
            burner,
            depositWhitelist,
            isDepositLimit,
            depositLimit,
            owner_,
            slasherIndex,
            ""
        );
    }

    function _defaultUniversalSlasherParams(uint48 epochDuration) internal pure returns (bytes memory) {
        uint48 vetoDuration = epochDuration > 1 ? 1 : 0;
        return abi.encode(
            IUniversalSlasher.InitParams({
                isBurnerHook: false, vetoDuration: vetoDuration, resolverSetDelay: uint48(epochDuration * 3)
            })
        );
    }

    function _createInitializedVaultWithOwnerAndSlasher(
        uint48 epochDuration,
        address[] memory networkLimitSetRoleHolders,
        address[] memory operatorNetworkSharesSetRoleHolders,
        uint64 version,
        address burner,
        bool depositWhitelist,
        bool isDepositLimit,
        uint256 depositLimit,
        address owner_,
        uint64 slasherIndex,
        bytes memory slasherParams
    ) internal virtual returns (IVaultV2, address, address) {
        CreateInitializedVaultParams memory params;
        params.epochDuration = epochDuration;
        params.networkLimitSetRoleHolders = networkLimitSetRoleHolders;
        params.operatorNetworkSharesSetRoleHolders = operatorNetworkSharesSetRoleHolders;
        params.version = version;
        params.burner = burner;
        params.depositWhitelist = depositWhitelist;
        params.isDepositLimit = isDepositLimit;
        params.depositLimit = depositLimit;
        params.owner = owner_;
        params.slasherIndex = slasherIndex;
        params.slasherParams = slasherParams;

        return _createInitializedVaultWithOwnerAndSlasherParams(params);
    }

    function _createInitializedVaultWithOwnerAndSlasherParams(CreateInitializedVaultParams memory params)
        internal
        virtual
        returns (IVaultV2, address, address)
    {
        if (params.version == VAULT_V2_VERSION) {
            if (params.slasherIndex == 0) {
                params.slasherIndex = UNIVERSAL_SLASHER_TYPE;
            }
            if (params.slasherParams.length == 0) {
                params.slasherParams = _defaultUniversalSlasherParams(params.epochDuration);
            }
            return _createInitializedUniversalVault(
                params.epochDuration,
                params.version,
                params.burner,
                params.depositWhitelist,
                params.isDepositLimit,
                params.depositLimit,
                params.owner,
                params.slasherIndex,
                params.slasherParams
            );
        }

        if (params.slasherIndex == 0 && params.slasherParams.length == 0) {
            params.slasherParams =
                abi.encode(ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})}));
        }

        IVault.InitParams memory baseParams;
        baseParams.collateral = address(collateral);
        baseParams.burner = params.burner;
        baseParams.epochDuration = params.epochDuration;
        baseParams.depositWhitelist = params.depositWhitelist;
        baseParams.isDepositLimit = params.isDepositLimit;
        baseParams.depositLimit = params.depositLimit;
        baseParams.defaultAdminRoleHolder = alice;
        baseParams.depositWhitelistSetRoleHolder = alice;
        baseParams.depositorWhitelistRoleHolder = alice;
        baseParams.isDepositLimitSetRoleHolder = alice;
        baseParams.depositLimitSetRoleHolder = alice;

        bytes memory vaultParams;
        if (params.version == 1) {
            vaultParams = abi.encode(baseParams);
        } else if (params.version == 2) {
            vaultParams = abi.encode(
                IVaultTokenized.InitParamsTokenized({baseParams: baseParams, name: VAULT_NAME, symbol: VAULT_SYMBOL})
            );
        } else {
            vaultParams = abi.encode(
                IVaultV2.InitParams({
                    name: VAULT_NAME,
                    symbol: VAULT_SYMBOL,
                    collateral: baseParams.collateral,
                    burner: baseParams.burner,
                    epochDuration: baseParams.epochDuration,
                    depositWhitelist: baseParams.depositWhitelist,
                    depositorToWhitelist: address(0xBEEF),
                    isDepositLimit: baseParams.isDepositLimit,
                    depositLimit: baseParams.depositLimit,
                    defaultAdminRoleHolder: baseParams.defaultAdminRoleHolder,
                    depositWhitelistSetRoleHolder: baseParams.depositWhitelistSetRoleHolder,
                    depositorWhitelistRoleHolder: baseParams.depositorWhitelistRoleHolder,
                    isDepositLimitSetRoleHolder: baseParams.isDepositLimitSetRoleHolder,
                    depositLimitSetRoleHolder: baseParams.depositLimitSetRoleHolder,
                    setAdapterLimitRoleHolder: alice,
                    allocateAdapterRoleHolder: alice
                })
            );
        }

        (address vault_, address delegator_, address slasher_) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: params.version,
                owner: params.owner,
                vaultParams: vaultParams,
                delegatorIndex: params.version == VAULT_V2_VERSION
                    ? uint64(delegatorFactory.totalTypes() - 1)
                    : uint64(1),
                delegatorParams: abi.encode(
                    INetworkRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: alice, hook: address(0), hookSetRoleHolder: alice
                        }),
                        networkLimitSetRoleHolders: params.networkLimitSetRoleHolders,
                        operatorNetworkSharesSetRoleHolders: params.operatorNetworkSharesSetRoleHolders
                    })
                ),
                withSlasher: true,
                slasherIndex: params.slasherIndex,
                slasherParams: params.slasherParams
            })
        );

        return (IVaultV2(vault_), address(delegator_), address(slasher_));
    }

    function _createInitializedUniversalVault(
        uint48 epochDuration,
        uint64 version,
        address burner,
        bool depositWhitelist,
        bool isDepositLimit,
        uint256 depositLimit
    ) internal returns (IVaultV2, address, address) {
        return _createInitializedUniversalVault(
            epochDuration,
            version,
            burner,
            depositWhitelist,
            isDepositLimit,
            depositLimit,
            address(0),
            UNIVERSAL_SLASHER_TYPE,
            ""
        );
    }

    function _createInitializedUniversalVault(
        uint48 epochDuration,
        uint64 version,
        address burner,
        bool depositWhitelist,
        bool isDepositLimit,
        uint256 depositLimit,
        address owner,
        uint64 slasherIndex,
        bytes memory slasherParams
    ) internal returns (IVaultV2, address, address) {
        if (slasherIndex == 0) {
            slasherIndex = UNIVERSAL_SLASHER_TYPE;
        }
        if (slasherParams.length == 0) {
            slasherParams = _defaultUniversalSlasherParams(epochDuration);
        }

        CreateInitializedVaultParams memory params;
        params.epochDuration = epochDuration;
        params.version = version;
        params.burner = burner;
        params.depositWhitelist = depositWhitelist;
        params.isDepositLimit = isDepositLimit;
        params.depositLimit = depositLimit;
        params.owner = owner;
        params.slasherIndex = slasherIndex;
        params.slasherParams = slasherParams;

        return _createInitializedVaultWithUniversalDelegatorParams(params);
    }

    function _createInitializedVaultWithUniversalDelegatorParams(CreateInitializedVaultParams memory params)
        internal
        returns (IVaultV2, address, address)
    {
        IVault.InitParams memory baseParams;
        baseParams.collateral = address(collateral);
        baseParams.burner = params.burner;
        baseParams.epochDuration = params.epochDuration;
        baseParams.depositWhitelist = params.depositWhitelist;
        baseParams.isDepositLimit = params.isDepositLimit;
        baseParams.depositLimit = params.depositLimit;
        baseParams.defaultAdminRoleHolder = alice;
        baseParams.depositWhitelistSetRoleHolder = alice;
        baseParams.depositorWhitelistRoleHolder = alice;
        baseParams.isDepositLimitSetRoleHolder = alice;
        baseParams.depositLimitSetRoleHolder = alice;

        bytes memory vaultParams;
        if (params.version == 1) {
            vaultParams = abi.encode(baseParams);
        } else if (params.version == 2) {
            vaultParams = abi.encode(
                IVaultTokenized.InitParamsTokenized({baseParams: baseParams, name: VAULT_NAME, symbol: VAULT_SYMBOL})
            );
        } else {
            vaultParams = abi.encode(
                IVaultV2.InitParams({
                    name: VAULT_NAME,
                    symbol: VAULT_SYMBOL,
                    collateral: baseParams.collateral,
                    burner: baseParams.burner,
                    epochDuration: baseParams.epochDuration,
                    depositWhitelist: baseParams.depositWhitelist,
                    depositorToWhitelist: address(0xBEEF),
                    isDepositLimit: baseParams.isDepositLimit,
                    depositLimit: baseParams.depositLimit,
                    defaultAdminRoleHolder: baseParams.defaultAdminRoleHolder,
                    depositWhitelistSetRoleHolder: baseParams.depositWhitelistSetRoleHolder,
                    depositorWhitelistRoleHolder: baseParams.depositorWhitelistRoleHolder,
                    isDepositLimitSetRoleHolder: baseParams.isDepositLimitSetRoleHolder,
                    depositLimitSetRoleHolder: baseParams.depositLimitSetRoleHolder,
                    setAdapterLimitRoleHolder: alice,
                    allocateAdapterRoleHolder: alice
                })
            );
        }

        IUniversalDelegator.InitParams memory delegatorParams = IUniversalDelegator.InitParams({
            defaultAdminRoleHolder: alice,
            hook: address(0),
            hookSetRoleHolder: alice,
            createSlotRoleHolder: alice,
            setSizeRoleHolder: alice,
            swapSlotsRoleHolder: alice,
            withdrawalBufferSize: type(uint128).max
        });

        (address vault_, address delegator_, address slasher_) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: params.version,
                owner: params.owner,
                vaultParams: vaultParams,
                delegatorIndex: UNIVERSAL_DELEGATOR_TYPE,
                delegatorParams: abi.encode(delegatorParams),
                withSlasher: true,
                slasherIndex: params.slasherIndex,
                slasherParams: params.slasherParams
            })
        );

        return (IVaultV2(vault_), address(delegator_), address(slasher_));
    }

    function _buildMigrateParams(uint48 epochDuration) internal view returns (IVaultV2.MigrateParams memory) {
        uint48 vetoDuration = epochDuration > 1 ? 1 : 0;
        IUniversalDelegator.InitParams memory delegatorParams = IUniversalDelegator.InitParams({
            defaultAdminRoleHolder: alice,
            hook: address(0),
            hookSetRoleHolder: alice,
            createSlotRoleHolder: alice,
            setSizeRoleHolder: alice,
            swapSlotsRoleHolder: alice,
            withdrawalBufferSize: type(uint128).max
        });
        IUniversalSlasher.InitParams memory slasherParams = IUniversalSlasher.InitParams({
            isBurnerHook: false, vetoDuration: vetoDuration, resolverSetDelay: uint48(epochDuration * 3)
        });
        return IVaultV2.MigrateParams({
            name: VAULT_NAME,
            symbol: VAULT_SYMBOL,
            delegatorParams: abi.encode(delegatorParams),
            slasherParams: abi.encode(slasherParams)
        });
    }

    function _defaultVaultInitParams(uint48 epochDuration) internal view returns (IVaultV2.InitParams memory params) {
        params = IVaultV2.InitParams({
            name: VAULT_NAME,
            symbol: VAULT_SYMBOL,
            collateral: address(collateral),
            burner: address(0xdEaD),
            epochDuration: epochDuration,
            depositWhitelist: false,
            depositorToWhitelist: address(0xBEEF),
            isDepositLimit: false,
            depositLimit: 0,
            defaultAdminRoleHolder: alice,
            depositWhitelistSetRoleHolder: alice,
            depositorWhitelistRoleHolder: alice,
            isDepositLimitSetRoleHolder: alice,
            depositLimitSetRoleHolder: alice,
            setAdapterLimitRoleHolder: alice,
            allocateAdapterRoleHolder: alice
        });
    }

    function _assertMigrationState(IVaultV2 vaultV2, address oldSlasher) internal view {
        assertEq(vaultV2.migrateTimestamp(), uint48(block.timestamp));
        assertEq(IEntity(vaultV2.delegator()).TYPE(), delegatorFactory.totalTypes() - 1);
        assertEq(IEntity(vaultV2.slasher()).TYPE(), slasherFactory.totalTypes() - 1);
        assertEq(IUniversalSlasher(vaultV2.slasher()).migrateTimestamp(), uint48(block.timestamp));
        assertEq(IUniversalSlasher(vaultV2.slasher()).oldSlasher(), oldSlasher);
        IUniversalDelegator.Slot memory root = IUniversalDelegator(vaultV2.delegator()).getSlot(0);
        assertEq(root.existChildren, 1);
        IUniversalDelegator.Slot memory noAdaptersSubvault =
            IUniversalDelegator(vaultV2.delegator()).getSlot(uint96(0).createIndex(root.firstChild));
        assertTrue(noAdaptersSubvault.noAdapters);
        assertEq(uint256(noAdaptersSubvault.size), IUniversalDelegator(vaultV2.delegator()).getNoAdaptersSize());
        uint256 expectedSlashRequestsLength = 0;
        if (oldSlasher != address(0) && IEntity(oldSlasher).TYPE() == 1) {
            expectedSlashRequestsLength = IVetoSlasher(oldSlasher).slashRequestsLength();
        }
        assertEq(IUniversalSlasher(vaultV2.slasher()).slashRequestsLength(), expectedSlashRequestsLength);
    }

    function _getEncodedVaultParams(IVaultV2.InitParams memory params) internal pure virtual returns (bytes memory) {
        return abi.encode(params);
    }
}
