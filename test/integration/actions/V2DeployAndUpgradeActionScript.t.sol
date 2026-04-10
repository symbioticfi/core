// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import "../SymbioticCoreInit.sol";
import "../SymbioticCoreImports.sol";
import "../base/SymbioticCoreInitBase.sol";

import {Subnetwork} from "../../../src/contracts/libraries/Subnetwork.sol";
import {UniversalDelegatorIndex} from "../../../src/contracts/libraries/UniversalDelegatorIndex.sol";

import {IEntity} from "../../../src/interfaces/common/IEntity.sol";
import {IMigratableEntity} from "../../../src/interfaces/common/IMigratableEntity.sol";
import {
    CREATE_SLOT_ROLE,
    IUniversalDelegator,
    REMOVE_SLOT_ROLE,
    SET_SIZE_ROLE,
    SWAP_SLOTS_ROLE,
    UNIVERSAL_DELEGATOR_TYPE
} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IUniversalSlasher, UNIVERSAL_SLASHER_TYPE} from "../../../src/interfaces/slasher/IUniversalSlasher.sol";
import {IVault} from "../../../src/interfaces/vault/IVault.sol";
import {IVaultV2, VAULT_V2_VERSION} from "../../../src/interfaces/vault/IVaultV2.sol";

import {ScriptBase} from "../../../script/utils/ScriptBase.s.sol";
import {V2DeployBaseScript} from "../../../script/deploy/base/V2DeployBase.s.sol";
import {MigrateToVaultV2BaseScript} from "../../../script/actions/base/MigrateToVaultV2Base.s.sol";
import {V2UpgradeBaseScript} from "../../../script/upgrade/base/V2UpgradeBase.s.sol";
import {ScriptBaseHarness} from "./ScriptBaseHarness.s.sol";

import {MockRewards} from "../../mocks/MockRewards.sol";

contract V2DeployScriptHarness is V2DeployBaseScript {
    address internal immutable broadcaster;

    constructor(address broadcaster_) {
        broadcaster = broadcaster_;
    }

    function _startBroadcast() internal override {
        vm.startBroadcast(broadcaster);
    }

    function _stopBroadcast() internal override {
        vm.stopBroadcast();
    }
}

contract V2UpgradeScriptHarness is V2UpgradeBaseScript, ScriptBaseHarness {
    constructor(address broadcaster_) ScriptBaseHarness(broadcaster_) {}

    function sendTransaction(address target, bytes memory data) public override(ScriptBase, ScriptBaseHarness) {
        ScriptBaseHarness.sendTransaction(target, data);
    }
}

contract MigrateToVaultV2ScriptHarness is MigrateToVaultV2BaseScript, ScriptBaseHarness {
    constructor(address broadcaster_) ScriptBaseHarness(broadcaster_) {}

    function _getScriptCaller() internal override returns (address caller) {
        caller = broadcaster;
    }

    function sendTransaction(address target, bytes memory data) public override(ScriptBase, ScriptBaseHarness) {
        ScriptBaseHarness.sendTransaction(target, data);
    }
}

contract V2DeployAndUpgradeActionScriptTest is SymbioticCoreInit {
    using Subnetwork for address;
    using UniversalDelegatorIndex for uint96;

    uint96 internal constant IDENTIFIER = 0;
    uint96 internal constant MIGRATED_SUBVAULT_INDEX = uint96(1) << 64;

    Vm.Wallet internal curator;
    Vm.Wallet internal network1;
    Vm.Wallet internal network2;
    Vm.Wallet internal operator1;
    Vm.Wallet internal operator2;

    address internal collateral;
    address internal coreOwner;
    MockRewards internal rewards;

    function setUp() public virtual override {
        vm.selectFork(vm.createFork(vm.rpcUrl("mainnet")));
        SYMBIOTIC_CORE_USE_EXISTING_DEPLOYMENT = true;

        super.setUp();

        curator = _getAccount_Symbiotic();
        network1 = _getNetwork_SymbioticCore();
        network2 = _getNetwork_SymbioticCore();
        operator1 = _getOperator_SymbioticCore();
        operator2 = _getOperator_SymbioticCore();

        collateral = _getToken_SymbioticCore();
        rewards = new MockRewards();

        coreOwner = Ownable(address(symbioticCore.vaultFactory)).owner();
        assertEq(Ownable(address(symbioticCore.delegatorFactory)).owner(), coreOwner, "delegator owner mismatch");
        assertEq(Ownable(address(symbioticCore.slasherFactory)).owner(), coreOwner, "slasher owner mismatch");
    }

    function test_MainnetCore_V2DeployThenV2Upgrade() public {
        assertEq(symbioticCore.vaultFactory.lastVersion(), VAULT_V2_VERSION - 1, "unexpected mainnet vault version");
        assertEq(
            symbioticCore.delegatorFactory.totalTypes(),
            UNIVERSAL_DELEGATOR_TYPE,
            "unexpected mainnet delegator type count"
        );
        assertEq(
            symbioticCore.slasherFactory.totalTypes(), UNIVERSAL_SLASHER_TYPE, "unexpected mainnet slasher type count"
        );

        V2DeployScriptHarness deployScript = new V2DeployScriptHarness(curator.addr);
        V2DeployBaseScript.DeploymentData memory deployment =
            deployScript.runBase(curator.addr, address(0), address(rewards));

        assertEq(Ownable(address(deployment.adapterRegistry)).owner(), curator.addr, "adapter registry owner mismatch");
        assertEq(symbioticCore.vaultFactory.lastVersion(), VAULT_V2_VERSION - 1, "deploy should not whitelist vault");
        assertEq(
            symbioticCore.delegatorFactory.totalTypes(),
            UNIVERSAL_DELEGATOR_TYPE,
            "deploy should not whitelist delegator"
        );
        assertEq(
            symbioticCore.slasherFactory.totalTypes(), UNIVERSAL_SLASHER_TYPE, "deploy should not whitelist slasher"
        );

        V2UpgradeScriptHarness coreUpgradeScript = new V2UpgradeScriptHarness(coreOwner);
        (bytes memory whitelistVaultData, address whitelistVaultTarget) =
            coreUpgradeScript.whitelistVaultV2(address(deployment.vaultV2));
        (bytes memory whitelistDelegatorData, address whitelistDelegatorTarget) =
            coreUpgradeScript.whitelistUniversalDelegator(address(deployment.universalDelegator));
        (bytes memory whitelistSlasherData, address whitelistSlasherTarget) =
            coreUpgradeScript.whitelistUniversalSlasher(address(deployment.universalSlasher));

        assertGt(whitelistVaultData.length, 0, "missing whitelist vault calldata");
        assertGt(whitelistDelegatorData.length, 0, "missing whitelist delegator calldata");
        assertGt(whitelistSlasherData.length, 0, "missing whitelist slasher calldata");
        assertEq(whitelistVaultTarget, address(symbioticCore.vaultFactory), "vaultFactory target mismatch");
        assertEq(whitelistDelegatorTarget, address(symbioticCore.delegatorFactory), "delegatorFactory target mismatch");
        assertEq(whitelistSlasherTarget, address(symbioticCore.slasherFactory), "slasherFactory target mismatch");
        assertEq(symbioticCore.vaultFactory.implementation(VAULT_V2_VERSION), address(deployment.vaultV2));
        assertEq(
            symbioticCore.delegatorFactory.implementation(UNIVERSAL_DELEGATOR_TYPE),
            address(deployment.universalDelegator)
        );
        assertEq(
            symbioticCore.slasherFactory.implementation(UNIVERSAL_SLASHER_TYPE), address(deployment.universalSlasher)
        );

        address vault = _createV1Vault();

        _networkSetMaxNetworkLimit_SymbioticCore(network1.addr, vault, IDENTIFIER, 1 ether);
        _networkSetMaxNetworkLimit_SymbioticCore(network2.addr, vault, IDENTIFIER, 1 ether);

        MigrateToVaultV2ScriptHarness upgradeScript = new MigrateToVaultV2ScriptHarness(curator.addr);
        MigrateToVaultV2BaseScript.Config memory config = _config(vault);
        MigrateToVaultV2BaseScript.NetworkAllocation[] memory networks = _networkAllocations();

        (bytes memory migrateData, address migrateTarget, bytes memory createSlotsData, address createSlotsTarget,,) =
            upgradeScript.runBase(config, networks, _allocators());

        assertGt(migrateData.length, 0, "missing migrate calldata");
        assertGt(createSlotsData.length, 0, "missing create slots calldata");
        assertEq(migrateTarget, address(symbioticCore.vaultFactory), "factory target mismatch");
        assertEq(createSlotsTarget, IVault(vault).delegator(), "delegator target mismatch");
        assertEq(IMigratableEntity(vault).version(), VAULT_V2_VERSION, "vault version mismatch");
        assertTrue(IVaultV2(vault).isInitialized(), "vault not initialized");

        address newDelegator = IVault(vault).delegator();
        address newSlasher = IVault(vault).slasher();

        assertEq(IEntity(newDelegator).TYPE(), UNIVERSAL_DELEGATOR_TYPE, "delegator type mismatch");
        assertEq(IEntity(newSlasher).TYPE(), UNIVERSAL_SLASHER_TYPE, "slasher type mismatch");

        IUniversalDelegator delegator = IUniversalDelegator(newDelegator);

        IUniversalDelegator.Slot memory root = delegator.getSlot(0);
        assertEq(root.existChildren, 1, "unexpected root children");

        IUniversalDelegator.Slot memory migratedSubvault = delegator.getSlot(MIGRATED_SUBVAULT_INDEX);
        assertTrue(migratedSubvault.exists, "migrated subvault missing");
        assertTrue(migratedSubvault.noAdapters, "migrated subvault should be no-adapters");
        assertEq(migratedSubvault.existChildren, 2, "network slot count mismatch");

        bytes32 subnetwork1 = network1.addr.subnetwork(IDENTIFIER);
        bytes32 subnetwork2 = network2.addr.subnetwork(IDENTIFIER);

        uint96 networkSlot1 = MIGRATED_SUBVAULT_INDEX.createIndex(1);
        uint96 networkSlot2 = MIGRATED_SUBVAULT_INDEX.createIndex(2);

        assertEq(delegator.getSlotOfNetwork(subnetwork1), networkSlot1, "network1 slot mismatch");
        assertEq(delegator.getSlotOfNetwork(subnetwork2), networkSlot2, "network2 slot mismatch");
        assertEq(uint256(delegator.getSlot(networkSlot1).size), 100 ether, "network1 size mismatch");
        assertEq(uint256(delegator.getSlot(networkSlot2).size), 60 ether, "network2 size mismatch");
        assertEq(delegator.maxNetworkLimit(subnetwork1), type(uint208).max, "network1 max limit mismatch");
        assertEq(delegator.maxNetworkLimit(subnetwork2), type(uint208).max, "network2 max limit mismatch");

        uint96 operatorSlot1 = networkSlot1.createIndex(1);
        uint96 operatorSlot2 = networkSlot1.createIndex(2);
        uint96 operatorSlot3 = networkSlot2.createIndex(1);

        assertEq(delegator.getSlotOfOperator(networkSlot1, operator1.addr), operatorSlot1, "operator1 slot mismatch");
        assertEq(delegator.getSlotOfOperator(networkSlot1, operator2.addr), operatorSlot2, "operator2 slot mismatch");
        assertEq(delegator.getSlotOfOperator(networkSlot2, operator2.addr), operatorSlot3, "operator3 slot mismatch");
        assertEq(uint256(delegator.getSlot(operatorSlot1).size), 40 ether, "operator1 size mismatch");
        assertEq(uint256(delegator.getSlot(operatorSlot2).size), 60 ether, "operator2 size mismatch");
        assertEq(uint256(delegator.getSlot(operatorSlot3).size), 60 ether, "operator3 size mismatch");

        _assertAllocatorRoles(newDelegator, operator1.addr);
    }

    function _createV1Vault() internal returns (address vault) {
        vm.startPrank(curator.addr);

        SymbioticCoreInitBase.VaultParams memory vaultParams = SymbioticCoreInitBase.VaultParams({
            owner: curator.addr,
            collateral: collateral,
            burner: address(0x000000000000000000000000000000000000dEaD),
            epochDuration: uint48(7 days),
            whitelistedDepositors: new address[](0),
            depositLimit: 0,
            delegatorIndex: 0,
            hook: address(0),
            network: address(0),
            withSlasher: true,
            slasherIndex: 1,
            vetoDuration: uint48(1 days)
        });

        vault = _getVault_SymbioticCore(vaultParams);

        vm.stopPrank();
    }

    function _config(address vault) internal view returns (MigrateToVaultV2BaseScript.Config memory) {
        return MigrateToVaultV2BaseScript.Config({
            vault: vault,
            name: "Migrated Vault V2",
            symbol: "mV2",
            defaultAdminRoleHolder: curator.addr,
            setAdapterLimitRoleHolder: curator.addr,
            swapAdaptersRoleHolder: curator.addr,
            allocateAdapterRoleHolder: curator.addr,
            deallocateAdapterRoleHolder: curator.addr,
            delegatorParams: IUniversalDelegator.InitParams({
                defaultAdminRoleHolder: curator.addr,
                hook: address(0),
                hookSetRoleHolder: curator.addr,
                createSlotRoleHolder: curator.addr,
                setSizeRoleHolder: curator.addr,
                swapSlotsRoleHolder: curator.addr,
                removeSlotRoleHolder: curator.addr,
                setWithdrawalBufferSizeRoleHolder: curator.addr,
                withdrawalBufferSize: type(uint128).max
            }),
            slasherParams: IUniversalSlasher.InitParams({
                isBurnerHook: false, vetoDuration: 1 days, resolverSetDelay: 21 days
            })
        });
    }

    function _networkAllocations()
        internal
        view
        returns (MigrateToVaultV2BaseScript.NetworkAllocation[] memory networks)
    {
        networks = new MigrateToVaultV2BaseScript.NetworkAllocation[](2);

        networks[0].network = network1.addr;
        networks[0].identifier = IDENTIFIER;
        networks[0].size = uint128(100 ether);
        networks[0].operators = new MigrateToVaultV2BaseScript.OperatorAllocation[](2);
        networks[0].operators[0] =
            MigrateToVaultV2BaseScript.OperatorAllocation({operator: operator1.addr, size: uint128(40 ether)});
        networks[0].operators[1] =
            MigrateToVaultV2BaseScript.OperatorAllocation({operator: operator2.addr, size: uint128(60 ether)});

        networks[1].network = network2.addr;
        networks[1].identifier = IDENTIFIER;
        networks[1].size = uint128(60 ether);
        networks[1].operators = new MigrateToVaultV2BaseScript.OperatorAllocation[](1);
        networks[1].operators[0] =
            MigrateToVaultV2BaseScript.OperatorAllocation({operator: operator2.addr, size: uint128(60 ether)});
    }

    function _allocators() internal view returns (address[] memory allocators) {
        allocators = new address[](1);
        allocators[0] = operator1.addr;
    }

    function _assertAllocatorRoles(address delegator, address allocator) internal view {
        assertTrue(IAccessControl(delegator).hasRole(CREATE_SLOT_ROLE, allocator), "missing create role");
        assertTrue(IAccessControl(delegator).hasRole(SET_SIZE_ROLE, allocator), "missing set size role");
        assertTrue(IAccessControl(delegator).hasRole(SWAP_SLOTS_ROLE, allocator), "missing swap role");
        assertTrue(IAccessControl(delegator).hasRole(REMOVE_SLOT_ROLE, allocator), "missing remove role");
    }
}
