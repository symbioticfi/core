// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SymbioticCoreImports.sol";

import {SymbioticCoreConstants} from "./SymbioticCoreConstants.sol";

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract SymbioticCoreBindings is Test {
    using SafeERC20 for IERC20;

    function _registerOperator_SymbioticCore(SymbioticCoreConstants.Core memory symbioticCore, address who) internal {
        vm.startPrank(who);
        symbioticCore.operatorRegistry.registerOperator();
        vm.stopPrank();
    }

    function _registerNetwork_SymbioticCore(SymbioticCoreConstants.Core memory symbioticCore, address who) internal {
        vm.startPrank(who);
        symbioticCore.networkRegistry.registerNetwork();
        vm.stopPrank();
    }

    function _optIn_SymbioticCore(
        SymbioticCoreConstants.Core memory symbioticCore,
        address who,
        address where
    ) internal {
        vm.startPrank(who);
        if (symbioticCore.vaultFactory.isEntity(where)) {
            symbioticCore.operatorVaultOptInService.optIn(where);
        } else if (symbioticCore.networkRegistry.isEntity(where)) {
            symbioticCore.operatorNetworkOptInService.optIn(where);
        } else {
            revert("Invalid address for opt-in");
        }
        vm.stopPrank();
    }

    function _optOut_SymbioticCore(
        SymbioticCoreConstants.Core memory symbioticCore,
        address who,
        address where
    ) internal {
        vm.startPrank(who);
        if (symbioticCore.vaultFactory.isEntity(where)) {
            symbioticCore.operatorVaultOptInService.optOut(where);
        } else if (symbioticCore.networkRegistry.isEntity(where)) {
            symbioticCore.operatorNetworkOptInService.optOut(where);
        } else {
            revert("Invalid address for opt-out");
        }
        vm.stopPrank();
    }

    function _setOperatorMetadata_SymbioticCore(
        SymbioticCoreConstants.Core memory symbioticCore,
        address who,
        string memory metadataURL
    ) internal {
        vm.startPrank(who);
        symbioticCore.operatorMetadataService.setMetadataURL(metadataURL);
        vm.stopPrank();
    }

    function _setNetworkMetadata_SymbioticCore(
        SymbioticCoreConstants.Core memory symbioticCore,
        address who,
        string memory metadataURL
    ) internal {
        vm.startPrank(who);
        symbioticCore.networkMetadataService.setMetadataURL(metadataURL);
        vm.stopPrank();
    }

    function _setMiddleware_SymbioticCore(
        SymbioticCoreConstants.Core memory symbioticCore,
        address who,
        address middleware
    ) internal {
        vm.startPrank(who);
        symbioticCore.networkMiddlewareService.setMiddleware(middleware);
        vm.stopPrank();
    }

    function _deposit_SymbioticCore(
        address who,
        address vault,
        uint256 amount
    ) internal returns (uint256 depositedAmount, uint256 mintedShares) {
        vm.startPrank(who);
        IERC20(ISymbioticVault(vault).collateral()).forceApprove(vault, amount);
        (depositedAmount, mintedShares) = ISymbioticVault(vault).deposit(who, amount);
        vm.stopPrank();
    }

    function _withdraw_SymbioticCore(
        address who,
        address vault,
        uint256 amount
    ) internal returns (uint256 burnedShares, uint256 mintedShares) {
        vm.startPrank(who);
        (burnedShares, mintedShares) = ISymbioticVault(vault).withdraw(who, amount);
        vm.stopPrank();
    }

    function _redeem_SymbioticCore(
        address who,
        address vault,
        uint256 shares
    ) internal returns (uint256 withdrawnAssets, uint256 mintedShares) {
        vm.startPrank(who);
        (withdrawnAssets, mintedShares) = ISymbioticVault(vault).redeem(who, shares);
        vm.stopPrank();
    }

    function _claim_SymbioticCore(address who, address vault, uint256 epoch) internal returns (uint256 amount) {
        vm.startPrank(who);
        amount = ISymbioticVault(vault).claim(who, epoch);
        vm.stopPrank();
    }

    function _claimBatch_SymbioticCore(
        address who,
        address vault,
        uint256[] memory epochs
    ) internal returns (uint256 amount) {
        vm.startPrank(who);
        amount = ISymbioticVault(vault).claimBatch(who, epochs);
        vm.stopPrank();
    }

    function _setDepositWhitelist_SymbioticCore(address who, address vault, bool status) internal {
        vm.startPrank(who);
        ISymbioticVault(vault).setDepositWhitelist(status);
        vm.stopPrank();
    }

    function _setDepositorWhitelistStatus_SymbioticCore(
        address who,
        address vault,
        address account,
        bool status
    ) internal {
        vm.startPrank(who);
        ISymbioticVault(vault).setDepositorWhitelistStatus(account, status);
        vm.stopPrank();
    }

    function _setIsDepositLimit_SymbioticCore(address who, address vault, bool status) internal {
        vm.startPrank(who);
        ISymbioticVault(vault).setIsDepositLimit(status);
        vm.stopPrank();
    }

    function _setDepositLimit_SymbioticCore(address who, address vault, uint256 limit) internal {
        vm.startPrank(who);
        ISymbioticVault(vault).setDepositLimit(limit);
        vm.stopPrank();
    }

    function _setMaxNetworkLimit_SymbioticCore(
        address who,
        address vault,
        uint96 identifier,
        uint256 amount
    ) internal {
        vm.startPrank(who);
        ISymbioticBaseDelegator(ISymbioticVault(vault).delegator()).setMaxNetworkLimit(identifier, amount);
        vm.stopPrank();
    }

    function _setHook_SymbioticCore(address who, address vault, address hook) internal {
        vm.startPrank(who);
        ISymbioticBaseDelegator(ISymbioticVault(vault).delegator()).setHook(hook);
        vm.stopPrank();
    }

    function _setNetworkLimit_SymbioticCore(address who, address vault, bytes32 subnetwork, uint256 amount) internal {
        vm.startPrank(who);
        ISymbioticNetworkRestakeDelegator(ISymbioticVault(vault).delegator()).setNetworkLimit(subnetwork, amount);
        // ISymbioticFullRestakeDelegator(ISymbioticVault(vault).delegator()).setNetworkLimit(subnetwork, amount);
        // ISymbioticOperatorSpecificDelegator(ISymbioticVault(vault).delegator()).setNetworkLimit(subnetwork, amount);
        vm.stopPrank();
    }

    function _setOperatorNetworkShares_SymbioticCore(
        address who,
        address vault,
        bytes32 subnetwork,
        address operator,
        uint256 shares
    ) internal {
        vm.startPrank(who);
        ISymbioticNetworkRestakeDelegator(ISymbioticVault(vault).delegator()).setOperatorNetworkShares(
            subnetwork, operator, shares
        );
        vm.stopPrank();
    }

    function _setOperatorNetworkLimit_SymbioticCore(
        address who,
        address vault,
        bytes32 subnetwork,
        address operator,
        uint256 amount
    ) internal {
        vm.startPrank(who);
        ISymbioticFullRestakeDelegator(ISymbioticVault(vault).delegator()).setOperatorNetworkLimit(
            subnetwork, operator, amount
        );
        vm.stopPrank();
    }

    function _slash_SymbioticCore(
        address who,
        address vault,
        bytes32 subnetwork,
        address operator,
        uint256 amount,
        uint48 captureTimestamp
    ) internal {
        vm.startPrank(who);
        ISymbioticSlasher(ISymbioticVault(vault).slasher()).slash(
            subnetwork, operator, amount, captureTimestamp, new bytes(0)
        );
        vm.stopPrank();
    }

    function _requestSlash_SymbioticCore(
        address who,
        address vault,
        bytes32 subnetwork,
        address operator,
        uint256 amount,
        uint48 captureTimestamp
    ) internal {
        vm.startPrank(who);
        ISymbioticVetoSlasher(ISymbioticVault(vault).slasher()).requestSlash(
            subnetwork, operator, amount, captureTimestamp, new bytes(0)
        );
        vm.stopPrank();
    }

    function _executeSlash_SymbioticCore(address who, address vault, uint256 slashIndex) internal {
        vm.startPrank(who);
        ISymbioticVetoSlasher(ISymbioticVault(vault).slasher()).executeSlash(slashIndex, new bytes(0));
        vm.stopPrank();
    }

    function _vetoSlash_SymbioticCore(address who, address vault, uint256 slashIndex) internal {
        vm.startPrank(who);
        ISymbioticVetoSlasher(ISymbioticVault(vault).slasher()).vetoSlash(slashIndex, new bytes(0));
        vm.stopPrank();
    }

    function _setResolver_SymbioticCore(address who, address vault, uint96 identifier, address resolver) internal {
        vm.startPrank(who);
        ISymbioticVetoSlasher(ISymbioticVault(vault).slasher()).setResolver(identifier, resolver, new bytes(0));
        vm.stopPrank();
    }
}
