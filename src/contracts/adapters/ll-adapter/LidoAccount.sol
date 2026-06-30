// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Account} from "./common/Account.sol";

import {ILidoAccount} from "../../../interfaces/adapters/ll-adapter/lido/ILidoAccount.sol";
import {ILidoWithdrawalQueue} from "../../../interfaces/adapters/ll-adapter/lido/ILidoWithdrawalQueue.sol";
import {IWETH} from "../../../interfaces/adapters/ll-adapter/etherfi/IWETH.sol";
import {IWstETH} from "../../../interfaces/adapters/ll-adapter/lido/IWstETH.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title LidoAccount
/// @notice Account for Lido wstETH redemptions.
contract LidoAccount is Account, ILidoAccount {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* IMMUTABLES */

    /// @inheritdoc ILidoAccount
    address public immutable WITHDRAWAL_QUEUE;
    /// @inheritdoc ILidoAccount
    address public immutable WSTETH;
    /// @inheritdoc ILidoAccount
    address public immutable STETH;
    /// @inheritdoc ILidoAccount
    address public immutable WETH;

    /* STATE VARIABLES */

    /// @inheritdoc ILidoAccount
    uint64[] public requestIds;

    /* CONSTRUCTOR */

    /// @notice Creates the Lido account implementation.
    constructor(
        address stETH,
        address weth,
        address oracle,
        address wstETH,
        address factory,
        address withdrawalQueue,
        address cowSwapSettlement
    ) Account(oracle, factory, wstETH, cowSwapSettlement) {
        WITHDRAWAL_QUEUE = withdrawalQueue;
        WSTETH = wstETH;
        STETH = stETH;
        WETH = weth;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc ILidoAccount
    function pendingAssets() public view returns (uint256 assets) {
        uint256 length = requestIds.length;
        if (length == 0) {
            return 0;
        }

        uint256[] memory ids = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            uint256 requestId = requestIds[i];
            uint256 index = i;
            while (index > 0 && ids[index - 1] > requestId) {
                ids[index] = ids[index - 1];
                --index;
            }
            ids[index] = requestId;
        }

        address withdrawalQueue = WITHDRAWAL_QUEUE;
        ILidoWithdrawalQueue.WithdrawalRequestStatus[] memory statuses =
            ILidoWithdrawalQueue(withdrawalQueue).getWithdrawalStatus(ids);

        uint256[] memory claimableEther;
        bool hasClaimableEther;
        uint256 lastCheckpointIndex = ILidoWithdrawalQueue(withdrawalQueue).getLastCheckpointIndex();
        if (lastCheckpointIndex > 0) {
            uint256 finalizedLength;
            for (uint256 i; i < length; ++i) {
                if (statuses[i].isFinalized && !statuses[i].isClaimed && statuses[i].owner == address(this)) {
                    ++finalizedLength;
                }
            }

            if (finalizedLength > 0) {
                uint256[] memory finalizedIds = new uint256[](finalizedLength);
                uint256 finalizedIndex;
                for (uint256 i; i < length; ++i) {
                    if (statuses[i].isFinalized && !statuses[i].isClaimed && statuses[i].owner == address(this)) {
                        finalizedIds[finalizedIndex++] = ids[i];
                    }
                }

                try ILidoWithdrawalQueue(withdrawalQueue)
                    .findCheckpointHints(finalizedIds, 1, lastCheckpointIndex) returns (
                    uint256[] memory hints
                ) {
                    try ILidoWithdrawalQueue(withdrawalQueue).getClaimableEther(finalizedIds, hints) returns (
                        uint256[] memory amounts
                    ) {
                        if (amounts.length == finalizedLength) {
                            claimableEther = amounts;
                            hasClaimableEther = true;
                        }
                    } catch {}
                } catch {}
            }
        }

        uint256 claimableIndex;
        for (uint256 i; i < length; ++i) {
            if (!statuses[i].isClaimed && statuses[i].owner == address(this)) {
                uint256 requestAssets = statuses[i].amountOfStETH;
                if (statuses[i].isFinalized) {
                    if (hasClaimableEther) {
                        requestAssets = claimableEther[claimableIndex];
                    }
                    ++claimableIndex;
                }
                assets += _redemptionTokenToAssets(WETH, requestAssets);
            }
        }
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns held stETH value plus pending request value in vault assets.
    function _totalAssets() internal view override returns (uint256 assets) {
        assets = pendingAssets();

        uint256 stETHBalance = IERC20(STETH).balanceOf(address(this));
        if (stETHBalance > 0) {
            assets += _redemptionTokenToAssets(STETH, stETHBalance);
        }
    }

    /// @dev Claims finalized withdrawals and submits held wstETH or stETH inventory.
    function _sync() internal override {
        uint256 length = requestIds.length;
        for (uint256 i = length; i > 0; --i) {
            uint256 index = i - 1;
            uint256 ethBalanceBefore = address(this).balance;
            try ILidoWithdrawalQueue(WITHDRAWAL_QUEUE).claimWithdrawal(requestIds[index]) {
                uint256 claimed = address(this).balance - ethBalanceBefore;
                if (claimed > 0) {
                    IWETH(WETH).deposit{value: claimed}();
                }
                --length;
                requestIds[index] = requestIds[length];
                requestIds.pop();
            } catch {}
        }

        uint256 amountToRedeem = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        uint256 minStETHAmount = ILidoWithdrawalQueue(WITHDRAWAL_QUEUE).MIN_STETH_WITHDRAWAL_AMOUNT();
        uint256 maxStETHAmount = ILidoWithdrawalQueue(WITHDRAWAL_QUEUE).MAX_STETH_WITHDRAWAL_AMOUNT();
        if (amountToRedeem > 0 && IWstETH(WSTETH).getStETHByWstETH(amountToRedeem) >= minStETHAmount) {
            uint256 maxWstETHAmount = IWstETH(WSTETH).getWstETHByStETH(maxStETHAmount);
            uint256[] memory amounts = _splitAmounts(amountToRedeem, maxWstETHAmount);
            uint256[] memory ids =
                ILidoWithdrawalQueue(WITHDRAWAL_QUEUE).requestWithdrawalsWstETH(amounts, address(this));
            length = ids.length;
            for (uint256 i; i < length; ++i) {
                requestIds.push(uint64(ids[i]));
            }
        }

        uint256 stETHBalance = IERC20(STETH).balanceOf(address(this));
        if (stETHBalance >= minStETHAmount) {
            uint256[] memory amounts = _splitAmounts(stETHBalance, maxStETHAmount);
            uint256[] memory ids = ILidoWithdrawalQueue(WITHDRAWAL_QUEUE).requestWithdrawals(amounts, address(this));
            length = ids.length;
            for (uint256 i; i < length; ++i) {
                requestIds.push(uint64(ids[i]));
            }
        }
    }

    /// @dev Splits an amount into Lido queue-sized requests.
    function _splitAmounts(uint256 amount, uint256 maxAmount) internal pure returns (uint256[] memory amounts) {
        amounts = new uint256[](amount.ceilDiv(maxAmount));
        uint256 length = amounts.length;
        for (uint256 i; i < length; ++i) {
            amounts[i] = amount > maxAmount ? maxAmount : amount;
            amount -= amounts[i];
        }
    }

    /* INITIALIZATION */

    /// @dev Initializes the account for an adapter and vault.
    function _initialize(uint64 initialVersion, address initOwner, bytes memory data) internal override {
        super._initialize(initialVersion, initOwner, data);
        if (_asset != WETH) {
            revert InvalidAsset();
        }

        IERC20(WSTETH).forceApprove(WITHDRAWAL_QUEUE, type(uint256).max);
        IERC20(STETH).forceApprove(WITHDRAWAL_QUEUE, type(uint256).max);
    }

    /* RECEIVE */

    receive() external payable {}
}
