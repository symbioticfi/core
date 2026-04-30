// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {VaultV2} from "../../../src/contracts/vault/VaultV2.sol";
import {VaultV2Migrate} from "../../../src/contracts/vault/VaultV2Migrate.sol";
import {UniversalDelegator} from "../../../src/contracts/delegator/UniversalDelegator.sol";
import {UniversalSlasher} from "../../../src/contracts/slasher/UniversalSlasher.sol";

import {
    IUniversalDelegator,
    UNIVERSAL_DELEGATOR_TYPE,
    WITHDRAWAL_BUFFER_INDEX
} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IUniversalSlasher, UNIVERSAL_SLASHER_TYPE} from "../../../src/interfaces/slasher/IUniversalSlasher.sol";
import {
    IVaultV2,
    VAULT_V2_VERSION,
    DEPOSIT_WHITELIST_SET_ROLE,
    DEPOSITOR_WHITELIST_ROLE,
    SET_ADAPTER_LIMIT_ROLE
} from "../../../src/interfaces/vault/IVaultV2.sol";

import {DeployCoreBaseScript} from "../../../script/deploy/base/DeployCoreBase.s.sol";
import {DeployVaultV2Script} from "../../../script/DeployVaultV2.s.sol";
import {DeployVaultV2Base} from "../../../script/base/DeployVaultV2Base.sol";
import {SymbioticCoreConstants} from "../SymbioticCoreConstants.sol";

contract DeployCoreScriptHarness is DeployCoreBaseScript {
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

contract DeployVaultV2ScriptHarness is DeployVaultV2Base {
    address internal immutable broadcaster;
    SymbioticCoreConstants.Core internal core;

    constructor(address broadcaster_, SymbioticCoreConstants.Core memory core_) {
        broadcaster = broadcaster_;
        core = core_;
    }

    function _startBroadcast() internal override {
        vm.startBroadcast(broadcaster);
    }

    function _stopBroadcast() internal override {
        vm.stopBroadcast();
    }

    function _core() internal view override returns (SymbioticCoreConstants.Core memory) {
        return core;
    }
}

contract DeployVaultV2ScriptConstantsHarness is DeployVaultV2Script {
    function configuredWithdrawalBufferSize() external view returns (uint128) {
        return WITHDRAWAL_BUFFER_SIZE;
    }
}

contract DeployVaultV2ScriptTest is Test {
    address internal broadcaster;
    address internal owner;
    address internal collateral;
    address internal depositor;
    address internal burner;

    SymbioticCoreConstants.Core internal core;

    function setUp() public {
        broadcaster = makeAddr("broadcaster");
        owner = makeAddr("owner");
        collateral = makeAddr("collateral");
        depositor = makeAddr("depositor");
        burner = makeAddr("burner");

        DeployCoreBaseScript.CoreDeploymentData memory coreData =
            new DeployCoreScriptHarness(broadcaster).run(address(this));
        _whitelistV2Core(coreData);

        core = SymbioticCoreConstants.Core({
            vaultFactory: coreData.vaultFactory,
            delegatorFactory: coreData.delegatorFactory,
            slasherFactory: coreData.slasherFactory,
            networkRegistry: coreData.networkRegistry,
            networkMetadataService: coreData.networkMetadataService,
            networkMiddlewareService: coreData.networkMiddlewareService,
            operatorRegistry: coreData.operatorRegistry,
            operatorMetadataService: coreData.operatorMetadataService,
            operatorVaultOptInService: coreData.operatorVaultOptInService,
            operatorNetworkOptInService: coreData.operatorNetworkOptInService,
            vaultConfigurator: coreData.vaultConfigurator
        });
    }

    function test_DeployVaultV2ScriptDeploysConfiguredVault() public {
        DeployVaultV2ScriptHarness script = new DeployVaultV2ScriptHarness(broadcaster, core);

        (address vault, address delegator, address slasher) = script.runBase(
            DeployVaultV2Base.DeployVaultV2Params({
                owner: owner,
                vaultParams: IVaultV2.InitParams({
                    name: "Test Vault V2",
                    symbol: "tvV2",
                    collateral: collateral,
                    burner: burner,
                    epochDuration: 7 days,
                    adapters: new address[](0),
                    adaptersAllowDelay: 7 days + 1,
                    depositWhitelist: true,
                    depositorToWhitelist: depositor,
                    isDepositLimit: true,
                    depositLimit: 100 ether,
                    defaultAdminRoleHolder: owner,
                    depositWhitelistSetRoleHolder: owner,
                    depositorWhitelistRoleHolder: owner,
                    isDepositLimitSetRoleHolder: owner,
                    depositLimitSetRoleHolder: owner,
                    setAdapterLimitRoleHolder: owner,
                    swapAdaptersRoleHolder: owner,
                    allocateAdapterRoleHolder: owner,
                    deallocateAdapterRoleHolder: owner
                }),
                delegatorParams: IUniversalDelegator.InitParams({
                    defaultAdminRoleHolder: owner,
                    createSlotRoleHolder: owner,
                    setSizeRoleHolder: owner,
                    swapSlotsRoleHolder: owner,
                    removeSlotRoleHolder: owner,
                    setWithdrawalBufferSizeRoleHolder: owner,
                    withdrawalBufferSize: 1 ether
                }),
                withSlasher: true,
                slasherParams: IUniversalSlasher.InitParams({
                    isBurnerHook: true, vetoDuration: 1 days, resolverSetDelay: 21 days
                })
            })
        );

        assertEq(IVaultV2(vault).version(), VAULT_V2_VERSION, "vault version mismatch");
        assertEq(VaultV2(vault).name(), "Test Vault V2", "vault name mismatch");
        assertEq(VaultV2(vault).symbol(), "tvV2", "vault symbol mismatch");
        assertEq(VaultV2(vault).owner(), owner, "vault owner mismatch");
        assertEq(VaultV2(vault).collateral(), collateral, "collateral mismatch");
        assertEq(VaultV2(vault).burner(), burner, "burner mismatch");
        assertEq(VaultV2(vault).depositLimit(), 100 ether, "deposit limit mismatch");
        assertTrue(VaultV2(vault).isDepositorWhitelisted(depositor), "depositor not whitelisted");
        assertTrue(VaultV2(vault).hasRole(DEPOSIT_WHITELIST_SET_ROLE, owner), "missing whitelist set role");
        assertTrue(VaultV2(vault).hasRole(DEPOSITOR_WHITELIST_ROLE, owner), "missing depositor role");
        assertTrue(VaultV2(vault).hasRole(SET_ADAPTER_LIMIT_ROLE, owner), "missing adapter role");
        assertFalse(VaultV2(vault).hasRole(DEPOSITOR_WHITELIST_ROLE, broadcaster), "broadcaster kept depositor role");

        assertEq(VaultV2(vault).delegator(), delegator, "delegator mismatch");
        assertEq(UniversalDelegator(delegator).TYPE(), UNIVERSAL_DELEGATOR_TYPE, "delegator type mismatch");
        assertEq(UniversalDelegator(delegator).vault(), vault, "delegator vault mismatch");
        assertEq(
            IUniversalDelegator(delegator).getSlot(WITHDRAWAL_BUFFER_INDEX).size, 1 ether, "withdrawal buffer mismatch"
        );

        assertEq(VaultV2(vault).slasher(), slasher, "slasher mismatch");
        assertEq(UniversalSlasher(slasher).TYPE(), UNIVERSAL_SLASHER_TYPE, "slasher type mismatch");
        assertEq(UniversalSlasher(slasher).vault(), vault, "slasher vault mismatch");
        assertTrue(UniversalSlasher(slasher).isBurnerHook(), "burner hook mismatch");
        assertEq(UniversalSlasher(slasher).vetoDuration(), 1 days, "veto duration mismatch");
        assertEq(UniversalSlasher(slasher).resolverSetDelay(), 21 days, "resolver delay mismatch");
    }

    function test_DeployVaultV2ScriptDefaultsWithdrawalBufferToMax() public {
        DeployVaultV2ScriptConstantsHarness script = new DeployVaultV2ScriptConstantsHarness();

        assertEq(script.configuredWithdrawalBufferSize(), type(uint128).max, "withdrawal buffer default mismatch");
    }

    function _whitelistV2Core(DeployCoreBaseScript.CoreDeploymentData memory coreData) internal {
        address adapterRegistry = makeAddr("adapterRegistry");
        address feeRegistry = address(0);
        address rewards = address(0);

        address vaultV2Migrate = address(
            new VaultV2Migrate(
                address(coreData.delegatorFactory),
                address(coreData.slasherFactory),
                feeRegistry,
                rewards,
                adapterRegistry
            )
        );
        coreData.vaultFactory
            .whitelist(
                address(
                    new VaultV2(
                        address(coreData.delegatorFactory),
                        address(coreData.slasherFactory),
                        address(coreData.vaultFactory),
                        feeRegistry,
                        rewards,
                        adapterRegistry,
                        vaultV2Migrate
                    )
                )
            );
        coreData.delegatorFactory
            .whitelist(
                address(
                    new UniversalDelegator(
                        address(coreData.networkRegistry),
                        address(coreData.vaultFactory),
                        address(coreData.delegatorFactory),
                        coreData.delegatorFactory.totalTypes(),
                        address(coreData.networkMiddlewareService)
                    )
                )
            );
        coreData.slasherFactory
            .whitelist(
                address(
                    new UniversalSlasher(
                        address(coreData.vaultFactory),
                        address(coreData.networkMiddlewareService),
                        address(coreData.networkRegistry),
                        address(coreData.slasherFactory),
                        coreData.slasherFactory.totalTypes()
                    )
                )
            );
    }
}
