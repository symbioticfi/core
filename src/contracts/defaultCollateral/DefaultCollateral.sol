// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IDefaultCollateral} from "src/interfaces/defaultCollateral/IDefaultCollateral.sol";
import {ICollateral} from "src/interfaces/ICollateral.sol";
import {Permit2Lib} from "src/contracts/libraries/Permit2Lib.sol";

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract DefaultCollateral is ERC20Upgradeable, ReentrancyGuardUpgradeable, IDefaultCollateral {
    using SafeERC20 for IERC20;
    using Permit2Lib for IERC20;

    uint8 private DECIMALS;

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

    /**
     * @inheritdoc IDefaultCollateral
     */
    uint256 public limit;

    /**
     * @inheritdoc IDefaultCollateral
     */
    address public limitIncreaser;

    modifier onlyLimitIncreaser() {
        if (msg.sender != limitIncreaser) {
            revert NotLimitIncreaser();
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address asset_, uint256 initialLimit, address limitIncreaser_) external initializer {
        __ERC20_init(
            string.concat("DefaultCollateral_", IERC20Metadata(asset_).name()),
            string.concat("DC_", IERC20Metadata(asset_).symbol())
        );
        __ReentrancyGuard_init();

        asset = asset_;

        limit = initialLimit;
        limitIncreaser = limitIncreaser_;

        DECIMALS = IERC20Metadata(asset).decimals();
    }

    /**
     * @inheritdoc ERC20Upgradeable
     */
    function decimals() public view override returns (uint8) {
        return DECIMALS;
    }

    /**
     * @inheritdoc IDefaultCollateral
     */
    function deposit(address recipient, uint256 amount) public nonReentrant returns (uint256) {
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));
        IERC20(asset).transferFrom2(msg.sender, address(this), amount);
        amount = IERC20(asset).balanceOf(address(this)) - balanceBefore;

        if (amount == 0) {
            revert InsufficientDeposit();
        }

        if (totalSupply() + amount > limit) {
            revert ExceedsLimit();
        }

        _mint(recipient, amount);

        emit Deposit(msg.sender, recipient, amount);

        return amount;
    }

    /**
     * @inheritdoc IDefaultCollateral
     */
    function deposit(
        address recipient,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256) {
        IERC20(asset).tryPermit2(msg.sender, address(this), amount, deadline, v, r, s);

        return deposit(recipient, amount);
    }

    /**
     * @inheritdoc IDefaultCollateral
     */
    function withdraw(address recipient, uint256 amount) external {
        if (amount == 0) {
            revert InsufficientWithdraw();
        }

        _burn(msg.sender, amount);

        IERC20(asset).safeTransfer(recipient, amount);

        emit Withdraw(msg.sender, recipient, amount);
    }

    /**
     * @inheritdoc ICollateral
     */
    function issueDebt(address recipient, uint256 amount) external {
        if (amount == 0) {
            revert InsufficientIssueDebt();
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

    /**
     * @inheritdoc IDefaultCollateral
     */
    function increaseLimit(uint256 amount) external onlyLimitIncreaser {
        limit += amount;

        emit IncreaseLimit(amount);
    }

    /**
     * @inheritdoc IDefaultCollateral
     */
    function setLimitIncreaser(address limitIncreaser_) external onlyLimitIncreaser {
        limitIncreaser = limitIncreaser_;

        emit SetLimitIncreaser(limitIncreaser_);
    }
}
