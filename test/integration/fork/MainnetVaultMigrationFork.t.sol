// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {AdapterRegistry} from "../../../src/contracts/AdapterRegistry.sol";
import {DelegatorFactory} from "../../../src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "../../../src/contracts/SlasherFactory.sol";
import {UniversalDelegator} from "../../../src/contracts/delegator/UniversalDelegator.sol";
import {UniversalSlasher} from "../../../src/contracts/slasher/UniversalSlasher.sol";
import {VaultFactory} from "../../../src/contracts/VaultFactory.sol";
import {VaultV2} from "../../../src/contracts/vault/VaultV2.sol";
import {VaultV2Migrate} from "../../../src/contracts/vault/VaultV2Migrate.sol";

import {IEntity} from "../../../src/interfaces/common/IEntity.sol";
import {IMigratableEntity} from "../../../src/interfaces/common/IMigratableEntity.sol";
import {IBaseDelegator} from "../../../src/interfaces/delegator/IBaseDelegator.sol";
import {IUniversalDelegator, UNIVERSAL_DELEGATOR_TYPE} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IUniversalSlasher, UNIVERSAL_SLASHER_TYPE} from "../../../src/interfaces/slasher/IUniversalSlasher.sol";
import {IVault} from "../../../src/interfaces/vault/IVault.sol";
import {IVaultV2, VAULT_V2_VERSION} from "../../../src/interfaces/vault/IVaultV2.sol";

import {MockFeeRegistry} from "../../mocks/MockFeeRegistry.sol";
import {MockRewards} from "../../mocks/MockRewards.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MainnetVaultMigrationForkTest is Test {
    uint256 internal constant MAINNET_FORK_BLOCK = 24_976_277;

    address internal constant VAULT = 0xd4E20ECA1f996Dab35883dC0AD5E3428AF888D45;
    address internal constant VAULT_OWNER = 0x2aCA71020De61bb532008049e1Bd41E451aE8AdC;
    address internal constant CORE_OWNER = 0x5721ce64Ee0D772Ce613b62D411350091C544cD0;
    address internal constant DEPOSITOR = 0x657e8C867D8B37dCC18fA4Caead9C45EB088C642;

    address internal constant VAULT_FACTORY = 0xAEb6bdd95c502390db8f52c8909F703E9Af6a346;
    address internal constant DELEGATOR_FACTORY = 0x985Ed57AF9D475f1d83c1c1c8826A0E5A34E8C7B;
    address internal constant SLASHER_FACTORY = 0x685c2eD7D59814d2a597409058Ee7a92F21e48Fd;
    address internal constant NETWORK_REGISTRY = 0xC773b1011461e7314CF05f97d95aa8e92C1Fd8aA;
    address internal constant NETWORK_MIDDLEWARE_SERVICE = 0xD7dC9B366c027743D90761F71858BCa83C6899Ad;
    address internal constant LBTC = 0x8236a87084f8B84306f72007F36F2618A5634494;

    address internal constant OLD_DELEGATOR = 0xA32E5868713CBeb1880578F5626ED53cc3E1A2fD;
    address internal constant OLD_SLASHER = 0x1CE8feA70f85A195dca0eBf137df8DF2d423994a;

    bytes32 internal constant NETWORK_1 = 0x8560c667ae72f28d09465b342a480dab28821f6b000000000000000000000000;
    bytes32 internal constant NETWORK_2 = 0x59cf937ea9fa9d7398223e3aa33d92f7f5f986a2000000000000000000000000;
    bytes32 internal constant NETWORK_3 = 0x759d4335cb712aa188935c2bd3aa6d205ac61305000000000000000000000000;

    address internal constant OPERATOR_1 = 0x087c25f83ED20bda587CFA035ED0c96338D4660f;
    address internal constant OPERATOR_2 = 0x51B6D824bd35AeD4FD1a9E253E41Dc7C9feeFa30;

    uint256 internal constant PRE_MIGRATION_ACTIVE_STAKE = 50_000_000_000;
    uint256 internal constant NETWORK_1_SIZE = 50_000_000_000;
    uint256 internal constant NETWORK_2_SIZE = 10_000_000_000;
    uint256 internal constant NETWORK_3_SIZE = 26_600_000_000;
    uint256 internal constant PRE_MIGRATION_CURRENT_WITHDRAW = 100_000_000;
    uint256 internal constant PRE_MIGRATION_NEXT_WITHDRAW = 150_000_000;
    uint256 internal constant NETWORK_1_OPERATOR_SIZE_AFTER_WITHDRAWALS = 24_875_000_000;
    uint256 internal constant NETWORK_2_OPERATOR_SIZE = 5_000_000_000;
    uint256 internal constant POST_MIGRATION_DEPOSIT = 100_000_000;
    uint256 internal constant POST_MIGRATION_WITHDRAW = 50_000_000;

    string internal constant MIGRATED_NAME = "Migrated LBTC Symbiotic Vault";
    string internal constant MIGRATED_SYMBOL = "mLBTC-SYM";

    VaultFactory internal vaultFactory;
    DelegatorFactory internal delegatorFactory;
    SlasherFactory internal slasherFactory;
    IERC20 internal collateral;

    struct LiveVaultSnapshot {
        address oldDelegator;
        address oldSlasher;
        address burner;
        uint256 activeStake;
        uint256 activeShares;
        uint256 depositorShares;
        uint256 depositorBalance;
        uint256 claimedLegacyWithdrawal;
        uint256 activeWithdrawals;
        uint256 currentEpochWithdrawal;
        uint256 nextEpochWithdrawal;
        uint256 currentEpochDepositorWithdrawal;
        uint256 nextEpochDepositorWithdrawal;
        uint48 currentEpochWithdrawalUnlockAt;
        uint48 nextEpochWithdrawalUnlockAt;
        uint256 currentEpoch;
        uint256 totalStake;
    }

    struct LiveStakeSnapshot {
        uint256 network1Operator1Stake;
        uint256 network1Operator2Stake;
        uint256 network2Operator1Stake;
        uint256 network2Operator2Stake;
    }

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), MAINNET_FORK_BLOCK);

        vaultFactory = VaultFactory(VAULT_FACTORY);
        delegatorFactory = DelegatorFactory(DELEGATOR_FACTORY);
        slasherFactory = SlasherFactory(SLASHER_FACTORY);
        collateral = IERC20(LBTC);
    }

    function testFork_MainnetVault_MigrationPreservesLiveStateAndSupportsPostMigrationUserFlow() public {
        _assertLivePreconditions();
        _createPreMigrationLegacyWithdrawals();

        LiveVaultSnapshot memory vaultSnapshot = _snapshotLiveVault();
        LiveStakeSnapshot memory stakeSnapshot = _snapshotLiveDelegation(vaultSnapshot.oldDelegator);

        _deployAndWhitelistV2();
        _migrateVault();

        IVaultV2 migratedVault = IVaultV2(VAULT);
        IUniversalDelegator migratedDelegator = IUniversalDelegator(migratedVault.delegator());
        IUniversalSlasher migratedSlasher = IUniversalSlasher(migratedVault.slasher());

        _assertMigratedVaultState(migratedVault, vaultSnapshot);
        _assertMigratedDelegatorAndSlasher(migratedDelegator, migratedSlasher, vaultSnapshot);

        _createLiveAllocationSlots(migratedDelegator);
        _assertMigratedStake(migratedDelegator, stakeSnapshot);
        _assertMigratedLegacyWithdrawals(migratedVault, vaultSnapshot);
        _assertPostMigrationDepositorFlow(migratedVault);
    }

    function _assertLivePreconditions() internal view {
        assertEq(block.chainid, 1, "not mainnet fork");
        assertEq(IMigratableEntity(VAULT).version(), 1, "vault should start as V1");
        assertEq(IMigratableEntity(VAULT).FACTORY(), VAULT_FACTORY, "vault factory mismatch");
        assertEq(Ownable(VAULT).owner(), VAULT_OWNER, "vault owner mismatch");
        assertEq(Ownable(VAULT_FACTORY).owner(), CORE_OWNER, "core owner mismatch");
        assertEq(IVault(VAULT).delegator(), OLD_DELEGATOR, "old delegator mismatch");
        assertEq(IVault(VAULT).slasher(), OLD_SLASHER, "old slasher mismatch");
        assertEq(vaultFactory.lastVersion(), VAULT_V2_VERSION - 1, "unexpected vault factory version");
        assertEq(delegatorFactory.totalTypes(), UNIVERSAL_DELEGATOR_TYPE, "unexpected delegator type count");
        assertEq(slasherFactory.totalTypes(), UNIVERSAL_SLASHER_TYPE, "unexpected slasher type count");
        assertEq(IVault(VAULT).collateral(), LBTC, "collateral mismatch");
        assertEq(IERC20Metadata(LBTC).symbol(), "LBTC", "collateral symbol mismatch");
        assertEq(IERC20Metadata(LBTC).decimals(), 8, "collateral decimals mismatch");
        assertEq(IVault(VAULT).activeStake(), PRE_MIGRATION_ACTIVE_STAKE, "active stake drifted");
        assertEq(IVault(VAULT).activeSharesOf(DEPOSITOR), PRE_MIGRATION_ACTIVE_STAKE, "depositor shares drifted");
        assertTrue(IVault(VAULT).depositWhitelist(), "deposit whitelist should be enabled");
        assertTrue(IVault(VAULT).isDepositorWhitelisted(DEPOSITOR), "real depositor should be whitelisted");
        assertGe(collateral.balanceOf(DEPOSITOR), POST_MIGRATION_DEPOSIT, "depositor needs live LBTC balance");
    }

    function _createPreMigrationLegacyWithdrawals() internal {
        IVault vault = IVault(VAULT);

        uint256 firstWithdrawalEpoch = vault.currentEpoch() + 1;
        vm.prank(DEPOSITOR);
        vault.withdraw(DEPOSITOR, PRE_MIGRATION_CURRENT_WITHDRAW);
        assertEq(
            vault.withdrawalsOf(firstWithdrawalEpoch, DEPOSITOR),
            PRE_MIGRATION_CURRENT_WITHDRAW,
            "first V1 withdrawal mismatch"
        );

        vm.warp(vault.nextEpochStart() + 1 days);
        assertEq(vault.currentEpoch(), firstWithdrawalEpoch, "first withdrawal should be in current epoch");

        uint256 secondWithdrawalEpoch = vault.currentEpoch() + 1;
        vm.prank(DEPOSITOR);
        vault.withdraw(DEPOSITOR, PRE_MIGRATION_NEXT_WITHDRAW);
        assertEq(
            vault.withdrawalsOf(firstWithdrawalEpoch, DEPOSITOR),
            PRE_MIGRATION_CURRENT_WITHDRAW,
            "current epoch V1 withdrawal mismatch"
        );
        assertEq(
            vault.withdrawalsOf(secondWithdrawalEpoch, DEPOSITOR),
            PRE_MIGRATION_NEXT_WITHDRAW,
            "next epoch V1 withdrawal mismatch"
        );
        assertGt(vault.nextEpochStart(), vm.getBlockTimestamp(), "migration should happen mid-epoch");
    }

    function _snapshotLiveVault() internal view returns (LiveVaultSnapshot memory snapshot) {
        IVault vault = IVault(VAULT);
        uint256 currentEpoch = vault.currentEpoch();
        uint48 currentEpochWithdrawalUnlockAt = vault.nextEpochStart();

        snapshot = LiveVaultSnapshot({
            oldDelegator: vault.delegator(),
            oldSlasher: vault.slasher(),
            burner: vault.burner(),
            activeStake: vault.activeStake(),
            activeShares: vault.activeShares(),
            depositorShares: vault.activeSharesOf(DEPOSITOR),
            depositorBalance: vault.activeBalanceOf(DEPOSITOR),
            claimedLegacyWithdrawal: vault.withdrawalsOf(1, DEPOSITOR),
            activeWithdrawals: vault.withdrawals(currentEpoch) + vault.withdrawals(currentEpoch + 1),
            currentEpochWithdrawal: vault.withdrawals(currentEpoch),
            nextEpochWithdrawal: vault.withdrawals(currentEpoch + 1),
            currentEpochDepositorWithdrawal: vault.withdrawalsOf(currentEpoch, DEPOSITOR),
            nextEpochDepositorWithdrawal: vault.withdrawalsOf(currentEpoch + 1, DEPOSITOR),
            currentEpochWithdrawalUnlockAt: currentEpochWithdrawalUnlockAt,
            nextEpochWithdrawalUnlockAt: uint48(vm.getBlockTimestamp()) + vault.epochDuration(),
            currentEpoch: currentEpoch,
            totalStake: vault.totalStake()
        });

        assertEq(snapshot.currentEpochWithdrawal, PRE_MIGRATION_CURRENT_WITHDRAW, "current V1 withdrawal missing");
        assertEq(snapshot.nextEpochWithdrawal, PRE_MIGRATION_NEXT_WITHDRAW, "next V1 withdrawal missing");
        assertEq(
            snapshot.activeWithdrawals,
            PRE_MIGRATION_CURRENT_WITHDRAW + PRE_MIGRATION_NEXT_WITHDRAW,
            "active V1 withdrawals mismatch"
        );
        assertEq(snapshot.totalStake, PRE_MIGRATION_ACTIVE_STAKE, "V1 total stake should include active withdrawals");
    }

    function _snapshotLiveDelegation(address oldDelegator) internal view returns (LiveStakeSnapshot memory snapshot) {
        snapshot = LiveStakeSnapshot({
            network1Operator1Stake: IBaseDelegator(oldDelegator).stake(NETWORK_1, OPERATOR_1),
            network1Operator2Stake: IBaseDelegator(oldDelegator).stake(NETWORK_1, OPERATOR_2),
            network2Operator1Stake: IBaseDelegator(oldDelegator).stake(NETWORK_2, OPERATOR_1),
            network2Operator2Stake: IBaseDelegator(oldDelegator).stake(NETWORK_2, OPERATOR_2)
        });

        assertEq(
            snapshot.network1Operator1Stake,
            NETWORK_1_OPERATOR_SIZE_AFTER_WITHDRAWALS,
            "network1 operator1 live stake drifted"
        );
        assertEq(
            snapshot.network1Operator2Stake,
            NETWORK_1_OPERATOR_SIZE_AFTER_WITHDRAWALS,
            "network1 operator2 live stake drifted"
        );
        assertEq(snapshot.network2Operator1Stake, NETWORK_2_OPERATOR_SIZE, "network2 operator1 live stake drifted");
        assertEq(snapshot.network2Operator2Stake, NETWORK_2_OPERATOR_SIZE, "network2 operator2 live stake drifted");
        assertEq(IBaseDelegator(oldDelegator).stake(NETWORK_3, OPERATOR_1), 0, "network3 should have no operator stake");
    }

    function _deployAndWhitelistV2() internal {
        MockFeeRegistry feeRegistry = new MockFeeRegistry();
        MockRewards rewards = new MockRewards();
        AdapterRegistry adapterRegistry = new AdapterRegistry(VAULT_OWNER);

        VaultV2Migrate vaultV2Migrate = new VaultV2Migrate(
            DELEGATOR_FACTORY, SLASHER_FACTORY, address(feeRegistry), address(rewards), address(adapterRegistry)
        );
        VaultV2 vaultV2 = new VaultV2(
            DELEGATOR_FACTORY,
            SLASHER_FACTORY,
            VAULT_FACTORY,
            address(feeRegistry),
            address(rewards),
            address(adapterRegistry),
            address(vaultV2Migrate)
        );
        UniversalDelegator universalDelegator = new UniversalDelegator(
            NETWORK_REGISTRY,
            VAULT_FACTORY,
            DELEGATOR_FACTORY,
            delegatorFactory.totalTypes(),
            NETWORK_MIDDLEWARE_SERVICE
        );
        UniversalSlasher universalSlasher = new UniversalSlasher(
            VAULT_FACTORY, NETWORK_MIDDLEWARE_SERVICE, NETWORK_REGISTRY, SLASHER_FACTORY, slasherFactory.totalTypes()
        );

        assertEq(IMigratableEntity(address(vaultV2)).FACTORY(), VAULT_FACTORY, "new vault factory mismatch");
        assertEq(IEntity(address(universalDelegator)).TYPE(), UNIVERSAL_DELEGATOR_TYPE, "new delegator type mismatch");
        assertEq(IEntity(address(universalSlasher)).TYPE(), UNIVERSAL_SLASHER_TYPE, "new slasher type mismatch");

        vm.startPrank(CORE_OWNER);
        vaultFactory.whitelist(address(vaultV2));
        delegatorFactory.whitelist(address(universalDelegator));
        slasherFactory.whitelist(address(universalSlasher));
        vm.stopPrank();

        assertEq(vaultFactory.implementation(VAULT_V2_VERSION), address(vaultV2), "V2 vault not whitelisted");
        assertEq(
            delegatorFactory.implementation(UNIVERSAL_DELEGATOR_TYPE),
            address(universalDelegator),
            "universal delegator not whitelisted"
        );
        assertEq(
            slasherFactory.implementation(UNIVERSAL_SLASHER_TYPE),
            address(universalSlasher),
            "universal slasher not whitelisted"
        );
    }

    function _migrateVault() internal {
        IVaultV2.MigrateParams memory params = IVaultV2.MigrateParams({
            name: MIGRATED_NAME,
            symbol: MIGRATED_SYMBOL,
            adaptersAllowDelay: 8 days,
            defaultAdminRoleHolder: VAULT_OWNER,
            setAdapterLimitRoleHolder: VAULT_OWNER,
            swapAdaptersRoleHolder: VAULT_OWNER,
            allocateAdapterRoleHolder: VAULT_OWNER,
            deallocateAdapterRoleHolder: VAULT_OWNER,
            delegatorParams: abi.encode(
                IUniversalDelegator.InitParams({
                    defaultAdminRoleHolder: VAULT_OWNER,
                    createSlotRoleHolder: VAULT_OWNER,
                    setSizeRoleHolder: VAULT_OWNER,
                    swapSlotsRoleHolder: VAULT_OWNER,
                    removeSlotRoleHolder: VAULT_OWNER,
                    setWithdrawalBufferSizeRoleHolder: VAULT_OWNER,
                    withdrawalBufferSize: type(uint128).max
                })
            ),
            slasherParams: abi.encode(
                IUniversalSlasher.InitParams({isBurnerHook: true, vetoDuration: 2 days, resolverSetDelay: 21 days})
            )
        });

        vm.prank(VAULT_OWNER);
        vaultFactory.migrate(VAULT, VAULT_V2_VERSION, abi.encode(params));
    }

    function _assertMigratedVaultState(IVaultV2 migratedVault, LiveVaultSnapshot memory snapshot) internal view {
        assertEq(IMigratableEntity(VAULT).version(), VAULT_V2_VERSION, "vault version mismatch");
        assertTrue(migratedVault.isInitialized(), "vault not initialized");
        assertEq(migratedVault.migrateTimestamp(), uint48(vm.getBlockTimestamp()), "vault migration timestamp mismatch");
        assertEq(migratedVault.collateral(), LBTC, "collateral not preserved");
        assertEq(migratedVault.burner(), snapshot.burner, "burner not preserved");
        assertEq(migratedVault.epochDuration(), 7 days, "epoch duration not preserved");
        assertEq(migratedVault.activeStake(), snapshot.activeStake, "active stake not preserved");
        assertEq(migratedVault.activeShares(), snapshot.activeShares, "active shares not preserved");
        assertEq(migratedVault.activeSharesOf(DEPOSITOR), snapshot.depositorShares, "depositor shares not preserved");
        assertEq(migratedVault.activeBalanceOf(DEPOSITOR), snapshot.depositorBalance, "depositor balance not preserved");
        assertEq(migratedVault.totalStake(), snapshot.totalStake, "total stake not preserved");
        assertEq(migratedVault.activeWithdrawals(), snapshot.activeWithdrawals, "active withdrawals not preserved");
        assertEq(
            migratedVault.activeWithdrawalShares(),
            snapshot.activeWithdrawals,
            "active withdrawal shares not migrated as assets"
        );
        assertEq(
            migratedVault.withdrawalsOf(1, DEPOSITOR),
            snapshot.claimedLegacyWithdrawal,
            "legacy withdrawal not readable"
        );
        assertTrue(migratedVault.isWithdrawalsClaimed(1, DEPOSITOR), "legacy claimed status not preserved");
        assertEq(
            migratedVault.withdrawalsOfLength(DEPOSITOR), snapshot.currentEpoch + 2, "legacy withdrawal length mismatch"
        );
        assertEq(migratedVault.delegator() == snapshot.oldDelegator, false, "delegator should be replaced");
        assertEq(migratedVault.slasher() == snapshot.oldSlasher, false, "slasher should be replaced");
        assertEq(IERC20Metadata(VAULT).name(), MIGRATED_NAME, "ERC20 name mismatch");
        assertEq(IERC20Metadata(VAULT).symbol(), MIGRATED_SYMBOL, "ERC20 symbol mismatch");
        assertEq(IERC20Metadata(VAULT).decimals(), 8, "migrated vault decimals mismatch");
        assertEq(IERC20(VAULT).balanceOf(DEPOSITOR), snapshot.depositorShares, "ERC20 balance mismatch");
    }

    function _assertMigratedDelegatorAndSlasher(
        IUniversalDelegator migratedDelegator,
        IUniversalSlasher migratedSlasher,
        LiveVaultSnapshot memory snapshot
    ) internal view {
        assertEq(IEntity(address(migratedDelegator)).TYPE(), UNIVERSAL_DELEGATOR_TYPE, "delegator type mismatch");
        assertEq(IEntity(address(migratedSlasher)).TYPE(), UNIVERSAL_SLASHER_TYPE, "slasher type mismatch");
        assertEq(migratedDelegator.oldDelegator(), snapshot.oldDelegator, "old delegator mismatch");
        assertEq(migratedSlasher.oldSlasher(), snapshot.oldSlasher, "old slasher mismatch");
        assertEq(
            migratedDelegator.migrateTimestamp(),
            uint48(vm.getBlockTimestamp()),
            "delegator migration timestamp mismatch"
        );
        assertEq(
            migratedSlasher.migrateTimestamp(), uint48(vm.getBlockTimestamp()), "slasher migration timestamp mismatch"
        );
        assertTrue(migratedSlasher.isBurnerHook(), "burner hook not migrated");
        assertEq(migratedSlasher.vetoDuration(), 2 days, "veto duration not migrated");
        assertEq(migratedSlasher.resolverSetDelay(), 21 days, "resolver delay not migrated");

        assertEq(migratedDelegator.totalSlots(), 0, "migration should not preseed flat slots");
    }

    function _createLiveAllocationSlots(IUniversalDelegator migratedDelegator) internal {
        vm.startPrank(VAULT_OWNER);
        uint32 network1Operator1Slot =
            migratedDelegator.createSlot(NETWORK_1, OPERATOR_1, uint128(NETWORK_1_OPERATOR_SIZE_AFTER_WITHDRAWALS));
        uint32 network2Operator1Slot =
            migratedDelegator.createSlot(NETWORK_2, OPERATOR_1, uint128(NETWORK_2_OPERATOR_SIZE));
        uint32 network2Operator2Slot =
            migratedDelegator.createSlot(NETWORK_2, OPERATOR_2, uint128(NETWORK_2_OPERATOR_SIZE));
        vm.stopPrank();

        assertEq(migratedDelegator.getSlotOf(NETWORK_1, OPERATOR_1), network1Operator1Slot, "network1 op1 slot");
        assertEq(migratedDelegator.getSlotOf(NETWORK_1, OPERATOR_2), 0, "network1 op2 should remain legacy-only");
        assertEq(migratedDelegator.getSlotOf(NETWORK_2, OPERATOR_1), network2Operator1Slot, "network2 op1 slot");
        assertEq(migratedDelegator.getSlotOf(NETWORK_2, OPERATOR_2), network2Operator2Slot, "network2 op2 slot");
        assertEq(migratedDelegator.getSlotOf(NETWORK_3, OPERATOR_1), 0, "network3 should not have an op1 slot");
        assertEq(migratedDelegator.totalSlots(), 3, "flat slot count mismatch");
    }

    function _assertMigratedStake(IUniversalDelegator migratedDelegator, LiveStakeSnapshot memory snapshot)
        internal
        view
    {
        uint48 legacyTimestamp = migratedDelegator.migrateTimestamp() - 1;
        IBaseDelegator oldDelegator = IBaseDelegator(migratedDelegator.oldDelegator());
        assertEq(
            migratedDelegator.stakeAt(NETWORK_1, OPERATOR_1, legacyTimestamp, ""),
            oldDelegator.stakeAt(NETWORK_1, OPERATOR_1, legacyTimestamp, ""),
            "legacy network1 operator1 stake mismatch"
        );
        assertEq(
            migratedDelegator.stakeAt(NETWORK_1, OPERATOR_2, legacyTimestamp, ""),
            oldDelegator.stakeAt(NETWORK_1, OPERATOR_2, legacyTimestamp, ""),
            "legacy network1 operator2 stake mismatch"
        );
        assertEq(
            migratedDelegator.stakeAt(NETWORK_2, OPERATOR_1, legacyTimestamp, ""),
            oldDelegator.stakeAt(NETWORK_2, OPERATOR_1, legacyTimestamp, ""),
            "legacy network2 operator1 stake mismatch"
        );
        assertEq(
            migratedDelegator.stakeAt(NETWORK_2, OPERATOR_2, legacyTimestamp, ""),
            oldDelegator.stakeAt(NETWORK_2, OPERATOR_2, legacyTimestamp, ""),
            "legacy network2 operator2 stake mismatch"
        );
        assertEq(
            migratedDelegator.stake(NETWORK_1, OPERATOR_1),
            snapshot.network1Operator1Stake,
            "network1 operator1 stake mismatch"
        );
        assertEq(migratedDelegator.stake(NETWORK_1, OPERATOR_2), 0, "network1 operator2 should remain legacy-only");
        assertEq(
            migratedDelegator.stake(NETWORK_2, OPERATOR_1),
            snapshot.network2Operator1Stake,
            "network2 operator1 stake mismatch"
        );
        assertEq(
            migratedDelegator.stake(NETWORK_2, OPERATOR_2),
            snapshot.network2Operator2Stake,
            "network2 operator2 stake mismatch"
        );
        assertEq(migratedDelegator.stake(NETWORK_3, OPERATOR_1), 0, "network3 should still have no operator stake");
    }

    function _assertMigratedLegacyWithdrawals(IVaultV2 migratedVault, LiveVaultSnapshot memory snapshot) internal {
        address currentRecipient = makeAddr("current-legacy-withdrawal-recipient");
        address nextRecipient = makeAddr("next-legacy-withdrawal-recipient");

        assertEq(
            migratedVault.withdrawalsOf(snapshot.currentEpoch, DEPOSITOR),
            snapshot.currentEpochDepositorWithdrawal,
            "current legacy withdrawal not migrated"
        );
        assertEq(
            migratedVault.withdrawalUnlockAt(snapshot.currentEpoch, DEPOSITOR),
            snapshot.currentEpochWithdrawalUnlockAt,
            "current legacy withdrawal unlock mismatch"
        );
        assertEq(
            migratedVault.withdrawalsOf(snapshot.currentEpoch + 1, DEPOSITOR),
            snapshot.nextEpochDepositorWithdrawal,
            "next legacy withdrawal not migrated"
        );
        assertEq(
            migratedVault.withdrawalUnlockAt(snapshot.currentEpoch + 1, DEPOSITOR),
            snapshot.nextEpochWithdrawalUnlockAt,
            "next legacy withdrawal unlock mismatch"
        );

        vm.startPrank(DEPOSITOR);
        vm.expectRevert(IVaultV2.WithdrawalNotMatured.selector);
        migratedVault.claim(currentRecipient, snapshot.currentEpoch);

        vm.warp(snapshot.currentEpochWithdrawalUnlockAt);
        uint256 currentClaimed = migratedVault.claim(currentRecipient, snapshot.currentEpoch);
        assertEq(currentClaimed, snapshot.currentEpochDepositorWithdrawal, "current legacy claim mismatch");
        assertEq(
            collateral.balanceOf(currentRecipient),
            snapshot.currentEpochDepositorWithdrawal,
            "current legacy recipient balance mismatch"
        );
        assertEq(
            migratedVault.activeWithdrawals(),
            snapshot.nextEpochWithdrawal,
            "next withdrawal should remain active after current claim"
        );

        vm.expectRevert(IVaultV2.WithdrawalNotMatured.selector);
        migratedVault.claim(nextRecipient, snapshot.currentEpoch + 1);

        vm.warp(snapshot.nextEpochWithdrawalUnlockAt);
        uint256 nextClaimed = migratedVault.claim(nextRecipient, snapshot.currentEpoch + 1);
        vm.stopPrank();

        assertEq(nextClaimed, snapshot.nextEpochDepositorWithdrawal, "next legacy claim mismatch");
        assertEq(
            collateral.balanceOf(nextRecipient),
            snapshot.nextEpochDepositorWithdrawal,
            "next legacy recipient balance mismatch"
        );
        assertEq(migratedVault.activeWithdrawals(), 0, "legacy active withdrawals should be exhausted");
        assertTrue(
            migratedVault.isWithdrawalsClaimed(snapshot.currentEpoch, DEPOSITOR),
            "current legacy withdrawal not marked claimed"
        );
        assertTrue(
            migratedVault.isWithdrawalsClaimed(snapshot.currentEpoch + 1, DEPOSITOR),
            "next legacy withdrawal not marked claimed"
        );
    }

    function _assertPostMigrationDepositorFlow(IVaultV2 migratedVault) internal {
        address recipient = makeAddr("post-migration-claim-recipient");
        uint256 preActiveStake = migratedVault.activeStake();
        uint256 withdrawalIndex = migratedVault.withdrawalsOfLength(DEPOSITOR);

        vm.startPrank(DEPOSITOR);
        collateral.approve(VAULT, POST_MIGRATION_DEPOSIT);
        (uint256 depositedAmount, uint256 mintedShares) = migratedVault.deposit(DEPOSITOR, POST_MIGRATION_DEPOSIT);
        assertEq(depositedAmount, POST_MIGRATION_DEPOSIT, "post-migration deposit amount mismatch");
        assertGt(mintedShares, 0, "post-migration deposit minted no shares");

        (uint256 burnedShares, uint256 withdrawalShares) = migratedVault.withdraw(DEPOSITOR, POST_MIGRATION_WITHDRAW);
        assertGt(burnedShares, 0, "post-migration withdraw burned no shares");
        assertGt(withdrawalShares, 0, "post-migration withdraw minted no withdrawal shares");
        assertEq(migratedVault.withdrawalsOfLength(DEPOSITOR), withdrawalIndex + 1, "withdrawal length mismatch");
        assertEq(
            migratedVault.withdrawalsOf(withdrawalIndex, DEPOSITOR),
            POST_MIGRATION_WITHDRAW,
            "withdrawal amount mismatch"
        );

        uint48 unlockAt = migratedVault.withdrawalUnlockAt(withdrawalIndex, DEPOSITOR);
        assertEq(unlockAt, uint48(vm.getBlockTimestamp()) + migratedVault.epochDuration(), "withdrawal unlock mismatch");

        vm.expectRevert(IVaultV2.WithdrawalNotMatured.selector);
        migratedVault.claim(recipient, withdrawalIndex);

        vm.warp(unlockAt);
        uint256 claimedAmount = migratedVault.claim(recipient, withdrawalIndex);
        vm.stopPrank();

        assertEq(claimedAmount, POST_MIGRATION_WITHDRAW, "claimed amount mismatch");
        assertEq(collateral.balanceOf(recipient), POST_MIGRATION_WITHDRAW, "recipient claim balance mismatch");
        assertEq(
            migratedVault.activeStake(),
            preActiveStake + POST_MIGRATION_DEPOSIT - POST_MIGRATION_WITHDRAW,
            "active stake after user flow mismatch"
        );
        assertTrue(migratedVault.isWithdrawalsClaimed(withdrawalIndex, DEPOSITOR), "withdrawal not marked claimed");
    }
}
