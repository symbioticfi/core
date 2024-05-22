// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICollateral is IERC20 {
    /**
     * @notice Emitted when debt is issued.
     * @param issuer address of the debt's issuer
     * @param recipient address that should receive the underlying asset
     * @param debtIssued amount of the debt issued
     */
    event IssueDebt(address indexed issuer, address indexed recipient, uint256 debtIssued);

    /**
     * @notice Emitted when debt is repaid.
     * @param issuer address of the debt's issuer
     * @param recipient address that received the underlying asset
     * @param debtRepaid amount of the debt repaid
     */
    event RepayDebt(address indexed issuer, address indexed recipient, uint256 debtRepaid);

    /**
     * @notice Get the collateral's underlying asset.
     * @return asset address of the underlying asset
     */
    function asset() external view returns (address);

    /**
     * @notice Get a total amount of repaid debt.
     * @return total repaid debt
     */
    function totalRepaidDebt() external view returns (uint256);

    /**
     * @notice Get an amount of repaid debt created by a particular issuer.
     * @param issuer address of the debt's issuer
     * @return particular issuer's repaid debt
     */
    function issuerRepaidDebt(address issuer) external view returns (uint256);

    /**
     * @notice Get an amount of repaid debt to a particular recipient.
     * @param recipient address that received the underlying asset
     * @return particular recipient's repaid debt
     */
    function recipientRepaidDebt(address recipient) external view returns (uint256);

    /**
     * @notice Get an amount of repaid debt for a particular issuer-recipient pair.
     * @param issuer address of the debt's issuer
     * @param recipient address that received the underlying asset
     * @return particular pair's repaid debt
     */
    function repaidDebt(address issuer, address recipient) external view returns (uint256);

    /**
     * @notice Get a total amount of debt.
     * @return total debt
     */
    function totalDebt() external view returns (uint256);

    /**
     * @notice Get a current debt created by a particular issuer.
     * @param issuer address of the debt's issuer
     * @return particular issuer's debt
     */
    function issuerDebt(address issuer) external view returns (uint256);

    /**
     * @notice Get a current debt to a particular recipient.
     * @param recipient address that should receive the underlying asset
     * @return particular recipient's debt
     */
    function recipientDebt(address recipient) external view returns (uint256);

    /**
     * @notice Get a current debt for a particular issuer-recipient pair.
     * @param issuer address of the debt's issuer
     * @param recipient address that should receive the underlying asset
     * @return particular pair's debt
     */
    function debt(address issuer, address recipient) external view returns (uint256);

    /**
     * @notice Burn a given amount of the collateral, and increase a debt of the underlying asset for the caller.
     * @param recipient address that should receive the underlying asset
     * @param amount amount of the collateral
     */
    function issueDebt(address recipient, uint256 amount) external;
}
