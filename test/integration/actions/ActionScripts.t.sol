// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../SymbioticCoreInit.sol";
import "../base/SymbioticCoreInitBase.sol";
import {Subnetwork} from "../../../src/contracts/libraries/Subnetwork.sol";

import {IVault} from "../../../src/interfaces/vault/IVault.sol";
import {IFullRestakeDelegator} from "../../../src/interfaces/delegator/IFullRestakeDelegator.sol";
import {INetworkRestakeDelegator} from "../../../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IBaseDelegator} from "../../../src/interfaces/delegator/IBaseDelegator.sol";
import {ISlasher} from "../../../src/interfaces/slasher/ISlasher.sol";
import {IVetoSlasher} from "../../../src/interfaces/slasher/IVetoSlasher.sol";
import {IEntity} from "../../../src/interfaces/common/IEntity.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {ScriptBase} from "../../../script/utils/ScriptBase.s.sol";
import {ScriptBaseHarness} from "./ScriptBaseHarness.s.sol";

import {OptInNetworkBaseScript} from "../../../script/actions/base/OptInNetworkBase.s.sol";
import {OptInVaultBaseScript} from "../../../script/actions/base/OptInVaultBase.s.sol";
import {RegisterOperatorBaseScript} from "../../../script/actions/base/RegisterOperatorBase.s.sol";
import {SetHookBaseScript} from "../../../script/actions/base/SetHookBase.s.sol";
import {SetMaxNetworkLimitBaseScript} from "../../../script/actions/base/SetMaxNetworkLimitBase.s.sol";
import {SetNetworkLimitBaseScript} from "../../../script/actions/base/SetNetworkLimitBase.s.sol";
import {SetOperatorNetworkSharesBaseScript} from "../../../script/actions/base/SetOperatorNetworkSharesBase.s.sol";
import {SetResolverBaseScript} from "../../../script/actions/base/SetResolverBase.s.sol";
import {VetoSlashBaseScript} from "../../../script/actions/base/VetoSlashBase.s.sol";

interface IVetoSlasherExtended is IVetoSlasher {
    function slashRequests(uint256 index)
        external
        view
        returns (
            bytes32 subnetwork,
            address operator,
            uint256 amount,
            uint48 captureTimestamp,
            uint48 vetoDeadline,
            bool completed
        );
}

contract RegisterOperatorScriptHarness is RegisterOperatorBaseScript, ScriptBaseHarness {
    constructor(address broadcaster_) ScriptBaseHarness(broadcaster_) {}

    function sendTransaction(address target, bytes memory data) public override(ScriptBase, ScriptBaseHarness) {
        ScriptBaseHarness.sendTransaction(target, data);
    }
}

contract OptInVaultScriptHarness is OptInVaultBaseScript, ScriptBaseHarness {
    constructor(address broadcaster_) ScriptBaseHarness(broadcaster_) {}

    function sendTransaction(address target, bytes memory data) public override(ScriptBase, ScriptBaseHarness) {
        ScriptBaseHarness.sendTransaction(target, data);
    }
}

contract OptInNetworkScriptHarness is OptInNetworkBaseScript, ScriptBaseHarness {
    constructor(address broadcaster_) ScriptBaseHarness(broadcaster_) {}

    function sendTransaction(address target, bytes memory data) public override(ScriptBase, ScriptBaseHarness) {
        ScriptBaseHarness.sendTransaction(target, data);
    }
}

contract SetHookScriptHarness is SetHookBaseScript, ScriptBaseHarness {
    constructor(address broadcaster_) ScriptBaseHarness(broadcaster_) {}

    function sendTransaction(address target, bytes memory data) public override(ScriptBase, ScriptBaseHarness) {
        ScriptBaseHarness.sendTransaction(target, data);
    }
}

contract SetMaxNetworkLimitScriptHarness is SetMaxNetworkLimitBaseScript, ScriptBaseHarness {
    constructor(address broadcaster_) ScriptBaseHarness(broadcaster_) {}

    function sendTransaction(address target, bytes memory data) public override(ScriptBase, ScriptBaseHarness) {
        ScriptBaseHarness.sendTransaction(target, data);
    }
}

contract SetNetworkLimitScriptHarness is SetNetworkLimitBaseScript, ScriptBaseHarness {
    constructor(address broadcaster_) ScriptBaseHarness(broadcaster_) {}

    function sendTransaction(address target, bytes memory data) public override(ScriptBase, ScriptBaseHarness) {
        ScriptBaseHarness.sendTransaction(target, data);
    }
}

contract SetOperatorNetworkSharesScriptHarness is SetOperatorNetworkSharesBaseScript, ScriptBaseHarness {
    constructor(address broadcaster_) ScriptBaseHarness(broadcaster_) {}

    function sendTransaction(address target, bytes memory data) public override(ScriptBase, ScriptBaseHarness) {
        ScriptBaseHarness.sendTransaction(target, data);
    }
}

contract SetResolverScriptHarness is SetResolverBaseScript, ScriptBaseHarness {
    constructor(address broadcaster_) ScriptBaseHarness(broadcaster_) {}

    function sendTransaction(address target, bytes memory data) public override(ScriptBase, ScriptBaseHarness) {
        ScriptBaseHarness.sendTransaction(target, data);
    }
}

contract VetoSlashScriptHarness is VetoSlashBaseScript, ScriptBaseHarness {
    constructor(address broadcaster_) ScriptBaseHarness(broadcaster_) {}

    function sendTransaction(address target, bytes memory data) public override(ScriptBase, ScriptBaseHarness) {
        ScriptBaseHarness.sendTransaction(target, data);
    }
}

contract ActionScriptsTest is SymbioticCoreInit {
    using Subnetwork for address;

    Vm.Wallet internal curator;
    Vm.Wallet internal network;
    Vm.Wallet internal resolver;
    Vm.Wallet internal operatorWallet;
    Vm.Wallet internal staker;

    address internal collateral;
    address internal vaultNetworkRestakeVeto;
    address internal vaultNetworkRestakeNonVeto;
    address internal vaultFullRestake;

    uint96 internal constant SUBNETWORK_ID = 1;
    uint256 internal constant DEFAULT_MAX_LIMIT = 1000 ether;
    uint256 internal constant DEFAULT_NETWORK_LIMIT = 500 ether;
    uint256 internal constant DEFAULT_OPERATOR_LIMIT = 400 ether;
    uint256 internal constant DEFAULT_OPERATOR_SHARES = 1000;
    uint256 internal constant DEFAULT_REQUEST_AMOUNT = 200 ether;
    uint256 internal constant DEFAULT_DEPOSIT = 800 ether;

    function setUp() public virtual override {
        vm.selectFork(vm.createFork(vm.rpcUrl("mainnet")));
        SYMBIOTIC_CORE_USE_EXISTING_DEPLOYMENT = true;

        super.setUp();

        curator = _getAccount_Symbiotic();
        network = _getNetwork_SymbioticCore();
        resolver = _getAccount_Symbiotic();
        operatorWallet = _getOperator_SymbioticCore();
        staker = _getAccount_Symbiotic();

        vm.label(curator.addr, "curator");
        vm.label(network.addr, "network");
        vm.label(resolver.addr, "resolver");
        vm.label(operatorWallet.addr, "operator");
        vm.label(staker.addr, "staker");

        _networkSetMiddleware_SymbioticCore(network.addr, network.addr);

        collateral = _getToken_SymbioticCore();

        // Let _getVault_SymbioticCore handle the caller management
        // It will use vm.readCallers() to determine the owner
        // Keep prank active for all vault creations
        vm.startPrank(curator.addr);
        vaultNetworkRestakeVeto = _getVault_SymbioticCore(collateral);

        // Grant required roles to curator for the first vault
        _grantRolesForNetworkRestakeDelegator(vaultNetworkRestakeVeto);

        SymbioticCoreInitBase.VaultParams memory nonVetoParams = SymbioticCoreInitBase.VaultParams({
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
            slasherIndex: 0,
            vetoDuration: uint48(1 days)
        });

        vaultNetworkRestakeNonVeto = _getVault_SymbioticCore(nonVetoParams);
        _grantRolesForNetworkRestakeDelegator(vaultNetworkRestakeNonVeto);

        SymbioticCoreInitBase.VaultParams memory fullRestakeParams = SymbioticCoreInitBase.VaultParams({
            owner: curator.addr,
            collateral: collateral,
            burner: address(0x000000000000000000000000000000000000dEaD),
            epochDuration: uint48(7 days),
            whitelistedDepositors: new address[](0),
            depositLimit: 0,
            delegatorIndex: 1,
            hook: address(0),
            network: address(0),
            withSlasher: true,
            slasherIndex: 1,
            vetoDuration: uint48(1 days)
        });

        vaultFullRestake = _getVault_SymbioticCore(fullRestakeParams);
        _grantRolesForFullRestakeDelegator(vaultFullRestake);

        vm.stopPrank();

        _labelVault(vaultNetworkRestakeVeto, "vaultNetworkRestakeVeto");
        _labelVault(vaultNetworkRestakeNonVeto, "vaultNetworkRestakeNonVeto");
        _labelVault(vaultFullRestake, "vaultFullRestake");
    }

    function _subnetwork() internal view returns (bytes32) {
        return network.addr.subnetwork(SUBNETWORK_ID);
    }

    function _labelVault(address vaultAddr, string memory label) internal {
        vm.label(vaultAddr, label);
        vm.label(IVault(vaultAddr).delegator(), string.concat(label, "_delegator"));
        vm.label(IVault(vaultAddr).slasher(), string.concat(label, "_slasher"));
    }

    function _grantRolesForNetworkRestakeDelegator(address vaultAddr) internal {
        address delegator = IVault(vaultAddr).delegator();

        // The admin is the curator who was the caller when the vault was created
        // Roles should already be granted during initialization, but grant them explicitly to be safe
        IAccessControl(delegator).grantRole(IBaseDelegator(delegator).HOOK_SET_ROLE(), curator.addr);
        IAccessControl(delegator).grantRole(INetworkRestakeDelegator(delegator).NETWORK_LIMIT_SET_ROLE(), curator.addr);
        IAccessControl(delegator)
            .grantRole(INetworkRestakeDelegator(delegator).OPERATOR_NETWORK_SHARES_SET_ROLE(), curator.addr);
    }

    function _grantRolesForFullRestakeDelegator(address vaultAddr) internal {
        address delegator = IVault(vaultAddr).delegator();

        IAccessControl(delegator).grantRole(IBaseDelegator(delegator).HOOK_SET_ROLE(), curator.addr);
        IAccessControl(delegator).grantRole(IFullRestakeDelegator(delegator).NETWORK_LIMIT_SET_ROLE(), curator.addr);
        IAccessControl(delegator)
            .grantRole(IFullRestakeDelegator(delegator).OPERATOR_NETWORK_LIMIT_SET_ROLE(), curator.addr);
    }

    function _ensureOperatorOptIn(address vaultAddr) internal {
        if (!symbioticCore.operatorVaultOptInService.isOptedIn(operatorWallet.addr, vaultAddr)) {
            _operatorOptIn_SymbioticCore(operatorWallet.addr, vaultAddr);
        }
        if (!symbioticCore.operatorNetworkOptInService.isOptedIn(operatorWallet.addr, network.addr)) {
            _operatorOptIn_SymbioticCore(operatorWallet.addr, network.addr);
        }
    }

    function _setupStakeForNetworkRestake(
        address vaultAddr,
        uint96 identifier,
        uint256 maxLimit,
        uint256 networkLimit,
        uint256 shares,
        uint256 depositAmount
    ) internal returns (bytes32 subnetwork, uint48 captureTimestamp) {
        subnetwork = network.addr.subnetwork(identifier);

        _networkSetMaxNetworkLimit_SymbioticCore(network.addr, vaultAddr, identifier, maxLimit);

        _curatorSetNetworkLimit_SymbioticCore(curator.addr, vaultAddr, subnetwork, networkLimit);
        _curatorSetOperatorNetworkShares_SymbioticCore(curator.addr, vaultAddr, subnetwork, operatorWallet.addr, shares);

        _ensureOperatorOptIn(vaultAddr);

        _deal_Symbiotic(collateral, staker.addr, depositAmount, true);
        _stakerDeposit_SymbioticCore(staker.addr, vaultAddr, depositAmount);

        vm.warp(block.timestamp + 10);
        captureTimestamp = uint48(block.timestamp - 1);
    }

    function _setupStakeForFullRestake(
        address vaultAddr,
        uint96 identifier,
        uint256 maxLimit,
        uint256 networkLimit,
        uint256 operatorLimit,
        uint256 depositAmount
    ) internal returns (bytes32 subnetwork, uint48 captureTimestamp) {
        subnetwork = network.addr.subnetwork(identifier);

        _networkSetMaxNetworkLimit_SymbioticCore(network.addr, vaultAddr, identifier, maxLimit);

        _curatorSetNetworkLimit_SymbioticCore(curator.addr, vaultAddr, subnetwork, networkLimit);
        _setOperatorNetworkLimit_SymbioticCore(curator.addr, vaultAddr, subnetwork, operatorWallet.addr, operatorLimit);

        _ensureOperatorOptIn(vaultAddr);

        _deal_Symbiotic(collateral, staker.addr, depositAmount, true);
        _stakerDeposit_SymbioticCore(staker.addr, vaultAddr, depositAmount);

        vm.warp(block.timestamp + 10);
        captureTimestamp = uint48(block.timestamp - 1);
    }

    function test_RegisterOperator() public {
        Vm.Wallet memory newOperator = _getAccount_Symbiotic();
        RegisterOperatorScriptHarness script = new RegisterOperatorScriptHarness(newOperator.addr);

        script.runBase();

        assertTrue(symbioticCore.operatorRegistry.isEntity(newOperator.addr), "operator not registered");
    }

    function test_OptInVault() public {
        OptInVaultScriptHarness script = new OptInVaultScriptHarness(operatorWallet.addr);

        script.runBase(vaultNetworkRestakeVeto);

        assertTrue(
            symbioticCore.operatorVaultOptInService.isOptedIn(operatorWallet.addr, vaultNetworkRestakeVeto),
            "operator not opted in"
        );
    }

    function test_OptInNetwork() public {
        OptInNetworkScriptHarness script = new OptInNetworkScriptHarness(operatorWallet.addr);

        script.runBase(network.addr);

        assertTrue(
            symbioticCore.operatorNetworkOptInService.isOptedIn(operatorWallet.addr, network.addr),
            "operator not opted in"
        );
    }

    function test_SetHook() public {
        address hook = address(0xdead);
        SetHookScriptHarness script = new SetHookScriptHarness(curator.addr);

        script.runBase(vaultNetworkRestakeVeto, hook);

        address delegator = IVault(vaultNetworkRestakeVeto).delegator();
        assertEq(IBaseDelegator(delegator).hook(), hook, "hook not set");
    }

    function test_SetMaxNetworkLimit() public {
        uint256 amount = DEFAULT_MAX_LIMIT;
        SetMaxNetworkLimitScriptHarness script = new SetMaxNetworkLimitScriptHarness(network.addr);

        script.runBase(vaultNetworkRestakeVeto, SUBNETWORK_ID, amount);

        bytes32 subnetwork = _subnetwork();
        uint256 value = IBaseDelegator(IVault(vaultNetworkRestakeVeto).delegator()).maxNetworkLimit(subnetwork);
        assertEq(value, amount, "max network limit mismatch");
    }

    function test_SetNetworkLimit() public {
        _networkSetMaxNetworkLimit_SymbioticCore(
            network.addr, vaultNetworkRestakeVeto, SUBNETWORK_ID, DEFAULT_MAX_LIMIT
        );

        uint256 amount = DEFAULT_NETWORK_LIMIT;
        bytes32 subnetwork = _subnetwork();
        SetNetworkLimitScriptHarness script = new SetNetworkLimitScriptHarness(curator.addr);

        script.runBase(vaultNetworkRestakeVeto, subnetwork, amount);

        uint256 value = INetworkRestakeDelegator(IVault(vaultNetworkRestakeVeto).delegator()).networkLimit(subnetwork);
        assertEq(value, amount, "network limit mismatch");
    }

    function test_SetOperatorNetworkShares() public {
        _networkSetMaxNetworkLimit_SymbioticCore(
            network.addr, vaultNetworkRestakeVeto, SUBNETWORK_ID, DEFAULT_MAX_LIMIT
        );
        bytes32 subnetwork = _subnetwork();
        uint256 shares = DEFAULT_OPERATOR_SHARES;
        SetOperatorNetworkSharesScriptHarness script = new SetOperatorNetworkSharesScriptHarness(curator.addr);

        script.runBase(vaultNetworkRestakeVeto, subnetwork, operatorWallet.addr, shares);

        uint256 value = INetworkRestakeDelegator(IVault(vaultNetworkRestakeVeto).delegator())
            .operatorNetworkShares(subnetwork, operatorWallet.addr);
        assertEq(value, shares, "operator network shares mismatch");
    }

    function test_SetResolver() public {
        SetResolverScriptHarness script = new SetResolverScriptHarness(network.addr);

        script.runBase(vaultNetworkRestakeVeto, SUBNETWORK_ID, resolver.addr);

        bytes32 subnetwork = _subnetwork();
        address currentResolver =
            IVetoSlasher(IVault(vaultNetworkRestakeVeto).slasher()).resolver(subnetwork, new bytes(0));
        assertEq(currentResolver, resolver.addr, "resolver mismatch");
    }

    function test_VetoSlash() public {
        SetResolverScriptHarness resolverScript = new SetResolverScriptHarness(network.addr);
        resolverScript.runBase(vaultNetworkRestakeVeto, SUBNETWORK_ID, resolver.addr);

        (bytes32 subnetwork, uint48 captureTimestamp) = _setupStakeForNetworkRestake(
            vaultNetworkRestakeVeto,
            SUBNETWORK_ID,
            DEFAULT_MAX_LIMIT,
            DEFAULT_NETWORK_LIMIT,
            DEFAULT_OPERATOR_SHARES,
            DEFAULT_DEPOSIT
        );

        _requestSlash_SymbioticCore(
            network.addr,
            vaultNetworkRestakeVeto,
            subnetwork,
            operatorWallet.addr,
            DEFAULT_REQUEST_AMOUNT,
            captureTimestamp
        );

        VetoSlashScriptHarness vetoScript = new VetoSlashScriptHarness(resolver.addr);
        vetoScript.runBase(vaultNetworkRestakeVeto, 0);

        IVetoSlasherExtended slasher = IVetoSlasherExtended(IVault(vaultNetworkRestakeVeto).slasher());
        (,,,,, bool completed) = slasher.slashRequests(0);
        assertTrue(completed, "slash not vetoed");

        uint256 cumulative =
            IVetoSlasher(IVault(vaultNetworkRestakeVeto).slasher()).cumulativeSlash(subnetwork, operatorWallet.addr);
        assertEq(cumulative, 0, "slash should be vetoed");
    }
}
