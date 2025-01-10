// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../test/integration/SymbioticCoreImports.sol";

import {SymbioticCoreConstants} from "../../test/integration/SymbioticCoreConstants.sol";

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {Test} from "forge-std/Test.sol";

contract SymbioticCoreBindings is Test {
    using SafeERC20 for IERC20;

    function _createVault_SymbioticCore(
        SymbioticCoreConstants.Core memory symbioticCore,
        address who,
        uint64 version,
        address owner,
        bytes memory vaultParams,
        uint64 delegatorIndex,
        bytes memory delegatorParams,
        bool withSlasher,
        uint64 slasherIndex,
        bytes memory slasherParams
    ) internal virtual returns (address vault, address delegator, address slasher) {
        vm.startBroadcast(who);
        (vault, delegator, slasher) = symbioticCore.vaultConfigurator.create(
            ISymbioticVaultConfigurator.InitParams({
                version: version,
                owner: owner,
                vaultParams: vaultParams,
                delegatorIndex: delegatorIndex,
                delegatorParams: delegatorParams,
                withSlasher: withSlasher,
                slasherIndex: slasherIndex,
                slasherParams: slasherParams
            })
        );
        vm.stopBroadcast();
    }

    function _registerOperator_SymbioticCore(
        SymbioticCoreConstants.Core memory symbioticCore,
        address who
    ) internal virtual {
        vm.startBroadcast(who);
        symbioticCore.operatorRegistry.registerOperator();
        vm.stopBroadcast();
    }

    function _registerNetwork_SymbioticCore(
        SymbioticCoreConstants.Core memory symbioticCore,
        address who
    ) internal virtual {
        vm.startBroadcast(who);
        symbioticCore.networkRegistry.registerNetwork();
        vm.stopBroadcast();
    }

    function _optInVault_SymbioticCore(
        SymbioticCoreConstants.Core memory symbioticCore,
        address who,
        address vault
    ) internal virtual {
        vm.startBroadcast(who);
        symbioticCore.operatorVaultOptInService.optIn(vault);
        vm.stopBroadcast();
    }

    function _optInVault_SymbioticCore(
        SymbioticCoreConstants.Core memory symbioticCore,
        address who,
        address account,
        address vault,
        uint48 deadline,
        bytes memory signature
    ) internal virtual {
        vm.startBroadcast(who);
        symbioticCore.operatorVaultOptInService.optIn(account, vault, deadline, signature);
        vm.stopBroadcast();
    }

    function _optInVault_SymbioticCore(
        SymbioticCoreConstants.Core memory symbioticCore,
        address who,
        address vault,
        uint48 deadline,
        bytes memory signature
    ) internal virtual {
        _optInVault_SymbioticCore(symbioticCore, who, who, vault, deadline, signature);
    }

    function _optInNetwork_SymbioticCore(
        SymbioticCoreConstants.Core memory symbioticCore,
        address who,
        address network
    ) internal virtual {
        vm.startBroadcast(who);
        symbioticCore.operatorNetworkOptInService.optIn(network);
        vm.stopBroadcast();
    }

    function _optInNetwork_SymbioticCore(
        SymbioticCoreConstants.Core memory symbioticCore,
        address who,
        address account,
        address network,
        uint48 deadline,
        bytes memory signature
    ) internal virtual {
        vm.startBroadcast(who);
        symbioticCore.operatorNetworkOptInService.optIn(account, network, deadline, signature);
        vm.stopBroadcast();
    }

    function _optInNetwork_SymbioticCore(
        SymbioticCoreConstants.Core memory symbioticCore,
        address who,
        address network,
        uint48 deadline,
        bytes memory signature
    ) internal virtual {
        _optInNetwork_SymbioticCore(symbioticCore, who, who, network, deadline, signature);
    }

    function _optOutVault_SymbioticCore(
        SymbioticCoreConstants.Core memory symbioticCore,
        address who,
        address vault
    ) internal virtual {
        vm.startBroadcast(who);
        symbioticCore.operatorVaultOptInService.optOut(vault);
        vm.stopBroadcast();
    }

    function _optOutVault_SymbioticCore(
        SymbioticCoreConstants.Core memory symbioticCore,
        address who,
        address account,
        address vault,
        uint48 deadline,
        bytes memory signature
    ) internal virtual {
        vm.startBroadcast(who);
        symbioticCore.operatorVaultOptInService.optOut(account, vault, deadline, signature);
        vm.stopBroadcast();
    }

    function _optOutVault_SymbioticCore(
        SymbioticCoreConstants.Core memory symbioticCore,
        address who,
        address vault,
        uint48 deadline,
        bytes memory signature
    ) internal virtual {
        _optOutVault_SymbioticCore(symbioticCore, who, who, vault, deadline, signature);
    }

    function _optOutNetwork_SymbioticCore(
        SymbioticCoreConstants.Core memory symbioticCore,
        address who,
        address network
    ) internal virtual {
        vm.startBroadcast(who);
        symbioticCore.operatorNetworkOptInService.optOut(network);
        vm.stopBroadcast();
    }

    function _optOutNetwork_SymbioticCore(
        SymbioticCoreConstants.Core memory symbioticCore,
        address who,
        address account,
        address network,
        uint48 deadline,
        bytes memory signature
    ) internal virtual {
        vm.startBroadcast(who);
        symbioticCore.operatorNetworkOptInService.optOut(account, network, deadline, signature);
        vm.stopBroadcast();
    }

    function _optOutNetwork_SymbioticCore(
        SymbioticCoreConstants.Core memory symbioticCore,
        address who,
        address network,
        uint48 deadline,
        bytes memory signature
    ) internal virtual {
        _optOutNetwork_SymbioticCore(symbioticCore, who, who, network, deadline, signature);
    }

    function _setOperatorMetadata_SymbioticCore(
        SymbioticCoreConstants.Core memory symbioticCore,
        address who,
        string memory metadataURL
    ) internal virtual {
        vm.startBroadcast(who);
        symbioticCore.operatorMetadataService.setMetadataURL(metadataURL);
        vm.stopBroadcast();
    }

    function _setNetworkMetadata_SymbioticCore(
        SymbioticCoreConstants.Core memory symbioticCore,
        address who,
        string memory metadataURL
    ) internal virtual {
        vm.startBroadcast(who);
        symbioticCore.networkMetadataService.setMetadataURL(metadataURL);
        vm.stopBroadcast();
    }

    function _setMiddleware_SymbioticCore(
        SymbioticCoreConstants.Core memory symbioticCore,
        address who,
        address middleware
    ) internal virtual {
        vm.startBroadcast(who);
        symbioticCore.networkMiddlewareService.setMiddleware(middleware);
        vm.stopBroadcast();
    }

    function _deposit_SymbioticCore(
        address who,
        address vault,
        address onBehalfOf,
        uint256 amount
    ) internal virtual returns (uint256 depositedAmount, uint256 mintedShares) {
        vm.startBroadcast(who);
        IERC20(ISymbioticVault(vault).collateral()).forceApprove(vault, amount);
        (depositedAmount, mintedShares) = ISymbioticVault(vault).deposit(onBehalfOf, amount);
        vm.stopBroadcast();
    }

    function _deposit_SymbioticCore(
        address who,
        address vault,
        uint256 amount
    ) internal virtual returns (uint256 depositedAmount, uint256 mintedShares) {
        _deposit_SymbioticCore(who, vault, who, amount);
    }

    function _withdraw_SymbioticCore(
        address who,
        address vault,
        address claimer,
        uint256 amount
    ) internal virtual returns (uint256 burnedShares, uint256 mintedShares) {
        vm.startBroadcast(who);
        (burnedShares, mintedShares) = ISymbioticVault(vault).withdraw(claimer, amount);
        vm.stopBroadcast();
    }

    function _withdraw_SymbioticCore(
        address who,
        address vault,
        uint256 amount
    ) internal virtual returns (uint256 burnedShares, uint256 mintedShares) {
        _withdraw_SymbioticCore(who, vault, who, amount);
    }

    function _redeem_SymbioticCore(
        address who,
        address vault,
        address claimer,
        uint256 shares
    ) internal virtual returns (uint256 withdrawnAssets, uint256 mintedShares) {
        vm.startBroadcast(who);
        (withdrawnAssets, mintedShares) = ISymbioticVault(vault).redeem(claimer, shares);
        vm.stopBroadcast();
    }

    function _redeem_SymbioticCore(
        address who,
        address vault,
        uint256 shares
    ) internal virtual returns (uint256 withdrawnAssets, uint256 mintedShares) {
        _redeem_SymbioticCore(who, vault, who, shares);
    }

    function _claim_SymbioticCore(
        address who,
        address vault,
        address recipient,
        uint256 epoch
    ) internal virtual returns (uint256 amount) {
        vm.startBroadcast(who);
        amount = ISymbioticVault(vault).claim(recipient, epoch);
        vm.stopBroadcast();
    }

    function _claim_SymbioticCore(
        address who,
        address vault,
        uint256 epoch
    ) internal virtual returns (uint256 amount) {
        _claim_SymbioticCore(who, vault, who, epoch);
    }

    function _claimBatch_SymbioticCore(
        address who,
        address vault,
        address recipient,
        uint256[] memory epochs
    ) internal virtual returns (uint256 amount) {
        vm.startBroadcast(who);
        amount = ISymbioticVault(vault).claimBatch(recipient, epochs);
        vm.stopBroadcast();
    }

    function _claimBatch_SymbioticCore(
        address who,
        address vault,
        uint256[] memory epochs
    ) internal virtual returns (uint256 amount) {
        _claimBatch_SymbioticCore(who, vault, who, epochs);
    }

    function _setDepositWhitelist_SymbioticCore(address who, address vault, bool status) internal virtual {
        vm.startBroadcast(who);
        ISymbioticVault(vault).setDepositWhitelist(status);
        vm.stopBroadcast();
    }

    function _setDepositorWhitelistStatus_SymbioticCore(
        address who,
        address vault,
        address account,
        bool status
    ) internal virtual {
        vm.startBroadcast(who);
        ISymbioticVault(vault).setDepositorWhitelistStatus(account, status);
        vm.stopBroadcast();
    }

    function _setIsDepositLimit_SymbioticCore(address who, address vault, bool status) internal virtual {
        vm.startBroadcast(who);
        ISymbioticVault(vault).setIsDepositLimit(status);
        vm.stopBroadcast();
    }

    function _setDepositLimit_SymbioticCore(address who, address vault, uint256 limit) internal virtual {
        vm.startBroadcast(who);
        ISymbioticVault(vault).setDepositLimit(limit);
        vm.stopBroadcast();
    }

    function _setMaxNetworkLimit_SymbioticCore(
        address who,
        address vault,
        uint96 identifier,
        uint256 amount
    ) internal virtual {
        vm.startBroadcast(who);
        ISymbioticBaseDelegator(ISymbioticVault(vault).delegator()).setMaxNetworkLimit(identifier, amount);
        vm.stopBroadcast();
    }

    function _setHook_SymbioticCore(address who, address vault, address hook) internal virtual {
        vm.startBroadcast(who);
        ISymbioticBaseDelegator(ISymbioticVault(vault).delegator()).setHook(hook);
        vm.stopBroadcast();
    }

    function _setNetworkLimit_SymbioticCore(
        address who,
        address vault,
        bytes32 subnetwork,
        uint256 amount
    ) internal virtual {
        vm.startBroadcast(who);
        ISymbioticNetworkRestakeDelegator(ISymbioticVault(vault).delegator()).setNetworkLimit(subnetwork, amount);
        // ISymbioticFullRestakeDelegator(ISymbioticVault(vault).delegator()).setNetworkLimit(subnetwork, amount);
        // ISymbioticOperatorSpecificDelegator(ISymbioticVault(vault).delegator()).setNetworkLimit(subnetwork, amount);
        vm.stopBroadcast();
    }

    function _setOperatorNetworkShares_SymbioticCore(
        address who,
        address vault,
        bytes32 subnetwork,
        address operator,
        uint256 shares
    ) internal virtual {
        vm.startBroadcast(who);
        ISymbioticNetworkRestakeDelegator(ISymbioticVault(vault).delegator()).setOperatorNetworkShares(
            subnetwork, operator, shares
        );
        vm.stopBroadcast();
    }

    function _setOperatorNetworkLimit_SymbioticCore(
        address who,
        address vault,
        bytes32 subnetwork,
        address operator,
        uint256 amount
    ) internal virtual {
        vm.startBroadcast(who);
        ISymbioticFullRestakeDelegator(ISymbioticVault(vault).delegator()).setOperatorNetworkLimit(
            subnetwork, operator, amount
        );
        vm.stopBroadcast();
    }

    function _slash_SymbioticCore(
        address who,
        address vault,
        bytes32 subnetwork,
        address operator,
        uint256 amount,
        uint48 captureTimestamp
    ) internal virtual returns (uint256 slashedAmount) {
        vm.startBroadcast(who);
        slashedAmount = ISymbioticSlasher(ISymbioticVault(vault).slasher()).slash(
            subnetwork, operator, amount, captureTimestamp, new bytes(0)
        );
        vm.stopBroadcast();
    }

    function _requestSlash_SymbioticCore(
        address who,
        address vault,
        bytes32 subnetwork,
        address operator,
        uint256 amount,
        uint48 captureTimestamp
    ) internal virtual returns (uint256 slashIndex) {
        vm.startBroadcast(who);
        slashIndex = ISymbioticVetoSlasher(ISymbioticVault(vault).slasher()).requestSlash(
            subnetwork, operator, amount, captureTimestamp, new bytes(0)
        );
        vm.stopBroadcast();
    }

    function _executeSlash_SymbioticCore(
        address who,
        address vault,
        uint256 slashIndex
    ) internal virtual returns (uint256 slashedAmount) {
        vm.startBroadcast(who);
        slashedAmount = ISymbioticVetoSlasher(ISymbioticVault(vault).slasher()).executeSlash(slashIndex, new bytes(0));
        vm.stopBroadcast();
    }

    function _vetoSlash_SymbioticCore(address who, address vault, uint256 slashIndex) internal virtual {
        vm.startBroadcast(who);
        ISymbioticVetoSlasher(ISymbioticVault(vault).slasher()).vetoSlash(slashIndex, new bytes(0));
        vm.stopBroadcast();
    }

    function _setResolver_SymbioticCore(
        address who,
        address vault,
        uint96 identifier,
        address resolver
    ) internal virtual {
        vm.startBroadcast(who);
        ISymbioticVetoSlasher(ISymbioticVault(vault).slasher()).setResolver(identifier, resolver, new bytes(0));
        vm.stopBroadcast();
    }

    function _grantRole_SymbioticCore(address who, address where, bytes32 role, address account) internal virtual {
        vm.startBroadcast(who);
        AccessControl(where).grantRole(role, account);
        vm.stopBroadcast();
    }

    function _grantRoleDefaultAdmin_SymbioticCore(address who, address where, address account) internal virtual {
        _grantRole_SymbioticCore(who, where, AccessControl(where).DEFAULT_ADMIN_ROLE(), account);
    }

    function _grantRoleDepositWhitelistSet_SymbioticCore(
        address who,
        address vault,
        address account
    ) internal virtual {
        _grantRole_SymbioticCore(who, vault, ISymbioticVault(vault).DEPOSIT_WHITELIST_SET_ROLE(), account);
    }

    function _grantRoleDepositorWhitelist_SymbioticCore(address who, address vault, address account) internal virtual {
        _grantRole_SymbioticCore(who, vault, ISymbioticVault(vault).DEPOSITOR_WHITELIST_ROLE(), account);
    }

    function _grantRoleIsDepositLimitSet_SymbioticCore(address who, address vault, address account) internal virtual {
        _grantRole_SymbioticCore(who, vault, ISymbioticVault(vault).IS_DEPOSIT_LIMIT_SET_ROLE(), account);
    }

    function _grantRoleDepositLimitSet_SymbioticCore(address who, address vault, address account) internal virtual {
        _grantRole_SymbioticCore(who, vault, ISymbioticVault(vault).DEPOSIT_LIMIT_SET_ROLE(), account);
    }

    function _grantRoleHookSet_SymbioticCore(address who, address vault, address account) internal virtual {
        _grantRole_SymbioticCore(
            who, vault, ISymbioticBaseDelegator(ISymbioticVault(vault).delegator()).HOOK_SET_ROLE(), account
        );
    }

    function _grantRole_NetworkLimitSet_SymbioticCore(address who, address vault, address account) internal virtual {
        _grantRole_SymbioticCore(
            who,
            vault,
            ISymbioticNetworkRestakeDelegator(ISymbioticVault(vault).delegator()).NETWORK_LIMIT_SET_ROLE(),
            account
        );
        // _grantRole_SymbioticCore(who, vault, ISymbioticFullRestakeDelegator(ISymbioticVault(vault).delegator()).NETWORK_LIMIT_SET_ROLE(), account);
        // _grantRole_SymbioticCore(who, vault, ISymbioticOperatorSpecificDelegator(ISymbioticVault(vault).delegator()).NETWORK_LIMIT_SET_ROLE(), account);
    }

    function _grantRole_OperatorNetworkSharesSet_SymbioticCore(
        address who,
        address vault,
        address account
    ) internal virtual {
        _grantRole_SymbioticCore(
            who,
            vault,
            ISymbioticNetworkRestakeDelegator(ISymbioticVault(vault).delegator()).OPERATOR_NETWORK_SHARES_SET_ROLE(),
            account
        );
    }

    function _grantRole_OperatorNetworkLimitSet_SymbioticCore(
        address who,
        address vault,
        address account
    ) internal virtual {
        _grantRole_SymbioticCore(
            who,
            vault,
            ISymbioticFullRestakeDelegator(ISymbioticVault(vault).delegator()).OPERATOR_NETWORK_LIMIT_SET_ROLE(),
            account
        );
    }
}
