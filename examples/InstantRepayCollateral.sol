// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ICollateral} from "src/interfaces/ICollateral.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract InstantRepayCollateral is ERC20, ICollateral {
    using SafeERC20 for IERC20;

    uint8 private immutable DECIMALS;

    /**
     * @inheritdoc ICollateral
     */
    address public asset;

    /**
     * @inheritdoc ICollateral
     */
    uint256 public totalRepaidDebt;

    /**
     * @inheritdoc ICollateral
     */
    mapping(address issuer => uint256 amount) public issuerRepaidDebt;

    /**
     * @inheritdoc ICollateral
     */
    mapping(address recipient => uint256 amount) public recipientRepaidDebt;

    /**
     * @inheritdoc ICollateral
     */
    mapping(address issuer => mapping(address recipient => uint256 amount)) public repaidDebt;

    /**
     * @inheritdoc ICollateral
     */
    uint256 public totalDebt;

    /**
     * @inheritdoc ICollateral
     */
    mapping(address issuer => uint256 amount) public issuerDebt;

    /**
     * @inheritdoc ICollateral
     */
    mapping(address recipient => uint256 amount) public recipientDebt;

    /**
     * @inheritdoc ICollateral
     */
    mapping(address issuer => mapping(address recipient => uint256 amount)) public debt;

    constructor(address asset_)
        ERC20(string.concat("DefaultCollateral_", ERC20(asset_).name()), string.concat("DB_", ERC20(asset_).symbol()))
    {
        asset = asset_;

        DECIMALS = ERC20(asset).decimals();
    }

    function decimals() public view override returns (uint8) {
        return DECIMALS;
    }

    function deposit(uint256 amount) external {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        if (amount == 0) {
            revert();
        }

        _mint(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        if (amount == 0) {
            revert();
        }

        _burn(msg.sender, amount);

        IERC20(asset).safeTransfer(msg.sender, amount);
    }

    /**
     * @inheritdoc ICollateral
     */
    function issueDebt(address recipient, uint256 amount) external {
        if (amount == 0) {
            revert();
        }

        _burn(msg.sender, amount);

        emit IssueDebt(msg.sender, recipient, amount);

        totalRepaidDebt += amount;
        issuerRepaidDebt[msg.sender] += amount;
        recipientRepaidDebt[recipient] += amount;
        repaidDebt[msg.sender][recipient] += amount;

        IERC20(asset).safeTransfer(recipient, amount);

        emit RepayDebt(msg.sender, recipient, amount);
    }
}
