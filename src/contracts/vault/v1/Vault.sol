// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {MigratableEntity} from "src/contracts/base/MigratableEntity.sol";
import {VaultStorage} from "./VaultStorage.sol";

import {ICollateral} from "src/interfaces/base/ICollateral.sol";
import {IRegistry} from "src/interfaces/base/IRegistry.sol";
import {IVault} from "src/interfaces/vault/v1/IVault.sol";
import {IStakingControllerFactory} from "src/interfaces/stakingController/v1/IStakingControllerFactory.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";
import {ERC4626Math} from "src/contracts/libraries/ERC4626Math.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract Vault is VaultStorage, MigratableEntity, AccessControlUpgradeable, IVault {
    using Checkpoints for Checkpoints.Trace256;
    using Math for uint256;

    modifier onlyStakingController() {
        if (msg.sender != stakingController) {
            revert NotStakingController();
        }
        _;
    }

    /**
     * @inheritdoc IVault
     */
    function totalSupplyIn(uint48 duration) public view returns (uint256) {
        uint256 epoch = currentEpoch();
        uint256 futureEpoch = epochAt(Time.timestamp() + duration);

        if (futureEpoch > epoch + 1) {
            return activeSupply();
        }

        if (futureEpoch > epoch) {
            return activeSupply() + withdrawals[futureEpoch];
        }

        return activeSupply() + withdrawals[epoch] + withdrawals[epoch + 1];
    }

    /**
     * @inheritdoc IVault
     */
    function totalSupply() public view returns (uint256) {
        uint256 epoch = currentEpoch();
        return activeSupply() + withdrawals[epoch] + withdrawals[epoch + 1];
    }

    /**
     * @inheritdoc IVault
     */
    function activeBalanceOfAt(address account, uint48 timestamp) public view returns (uint256) {
        return ERC4626Math.previewRedeem(
            activeSharesOfAt(account, timestamp), activeSupplyAt(timestamp), activeSharesAt(timestamp)
        );
    }

    /**
     * @inheritdoc IVault
     */
    function activeBalanceOf(address account) public view returns (uint256) {
        return ERC4626Math.previewRedeem(activeSharesOf(account), activeSupply(), activeShares());
    }

    /**
     * @inheritdoc IVault
     */
    function pendingWithdrawalsOf(uint256 epoch, address account) public view returns (uint256) {
        return ERC4626Math.previewRedeem(
            pendingWithdrawalSharesOf[epoch][account], withdrawals[epoch], withdrawalShares[epoch]
        );
    }

    constructor(address vaultFactory) MigratableEntity(vaultFactory) {
        _disableInitializers();
    }

    /**
     * @inheritdoc IVault
     */
    function deposit(address onBehalfOf, uint256 amount) external returns (uint256 shares) {
        if (depositWhitelist && !isDepositorWhitelisted[msg.sender]) {
            revert NotWhitelistedDepositor();
        }

        if (amount == 0) {
            revert InsufficientDeposit();
        }

        IERC20(collateral).transferFrom(msg.sender, address(this), amount);

        uint256 activeSupply_ = activeSupply();
        uint256 activeShares_ = activeShares();

        shares = ERC4626Math.previewDeposit(amount, activeShares_, activeSupply_);

        _activeSupplies.push(Time.timestamp(), activeSupply_ + amount);
        _activeShares.push(Time.timestamp(), activeShares_ + shares);
        _activeSharesOf[onBehalfOf].push(Time.timestamp(), activeSharesOf(onBehalfOf) + shares);

        if (firstDepositAt[onBehalfOf] == 0) {
            firstDepositAt[onBehalfOf] = Time.timestamp();
        }

        emit Deposit(msg.sender, onBehalfOf, amount, shares);
    }

    /**
     * @inheritdoc IVault
     */
    function withdraw(address claimer, uint256 amount) external returns (uint256 burnedShares, uint256 mintedShares) {
        if (amount == 0) {
            revert InsufficientWithdrawal();
        }

        uint256 activeSupply_ = activeSupply();
        uint256 activeShares_ = activeShares();
        uint256 activeSharesOf_ = activeSharesOf(msg.sender);

        burnedShares = ERC4626Math.previewWithdraw(amount, activeShares_, activeSupply_);
        if (burnedShares > activeSharesOf_) {
            revert TooMuchWithdraw();
        }

        _activeSupplies.push(Time.timestamp(), activeSupply_ - amount);
        _activeShares.push(Time.timestamp(), activeShares_ - burnedShares);
        _activeSharesOf[msg.sender].push(Time.timestamp(), activeSharesOf_ - burnedShares);

        uint256 epoch = currentEpoch() + 1;
        uint256 withdrawals_ = withdrawals[epoch];
        uint256 withdrawalsShares_ = withdrawalShares[epoch];

        mintedShares = ERC4626Math.previewDeposit(amount, withdrawalsShares_, withdrawals_);

        withdrawals[epoch] = withdrawals_ + amount;
        withdrawalShares[epoch] = withdrawalsShares_ + mintedShares;
        pendingWithdrawalSharesOf[epoch][claimer] += mintedShares;

        emit Withdraw(msg.sender, claimer, amount, burnedShares, mintedShares);
    }

    /**
     * @inheritdoc IVault
     */
    function claim(address recipient, uint256 epoch) external returns (uint256 amount) {
        if (epoch >= currentEpoch()) {
            revert InvalidEpoch();
        }

        amount = pendingWithdrawalsOf(epoch, msg.sender);

        if (amount == 0) {
            revert InsufficientClaim();
        }

        pendingWithdrawalSharesOf[epoch][msg.sender] = 0;

        IERC20(collateral).transfer(recipient, amount);

        emit Claim(msg.sender, recipient, amount);
    }

    /**
     * @inheritdoc IVault
     */
    function onSlash(uint256 slashedAmount) external onlyStakingController returns (uint256) {
        uint256 epoch = currentEpoch();
        uint256 totalSupply_ = totalSupply();
        uint256 activeSupply_ = activeSupply();
        uint256 withdrawals_ = withdrawals[epoch];
        uint256 nextWithdrawals_ = withdrawals[epoch + 1];

        uint256 activeSlashed = slashedAmount.mulDiv(activeSupply_, totalSupply_);
        uint256 withdrawalsSlashed = slashedAmount.mulDiv(withdrawals_, totalSupply_);
        uint256 nextWithdrawalsSlashed = slashedAmount - activeSlashed - withdrawalsSlashed;
        if (nextWithdrawals_ < nextWithdrawalsSlashed) {
            nextWithdrawalsSlashed = nextWithdrawals_;
            slashedAmount = activeSlashed + withdrawalsSlashed + nextWithdrawalsSlashed;
        }

        if (slashedAmount == 0) {
            return 0;
        }

        _activeSupplies.push(Time.timestamp(), activeSupply_ - activeSlashed);
        withdrawals[epoch] = withdrawals_ - withdrawalsSlashed;
        withdrawals[epoch + 1] = nextWithdrawals_ - nextWithdrawalsSlashed;
        return slashedAmount;
    }

    /**
     * @inheritdoc IVault
     */
    function setAdminFee(uint256 adminFee_) external onlyRole(ADMIN_FEE_SET_ROLE) {
        if (adminFee == adminFee_) {
            revert AlreadySet();
        }

        if (adminFee_ > ADMIN_FEE_BASE) {
            revert InvalidAdminFee();
        }

        adminFee = adminFee_;

        emit SetAdminFee(adminFee_);
    }

    /**
     * @inheritdoc IVault
     */
    function setDepositWhitelist(bool status) external onlyRole(DEPOSIT_WHITELIST_SET_ROLE) {
        if (depositWhitelist == status) {
            revert AlreadySet();
        }

        depositWhitelist = status;

        emit SetDepositWhitelist(status);
    }

    /**
     * @inheritdoc IVault
     */
    function setDepositorWhitelistStatus(address account, bool status) external onlyRole(DEPOSITOR_WHITELIST_ROLE) {
        if (isDepositorWhitelisted[account] == status) {
            revert AlreadySet();
        }

        if (status && !depositWhitelist) {
            revert NoDepositWhitelist();
        }

        isDepositorWhitelisted[account] = status;

        emit SetDepositorWhitelistStatus(account, status);
    }

    function _initialize(uint64, address owner, bytes memory data) internal override {
        (IVault.InitParams memory params) = abi.decode(data, (IVault.InitParams));

        if (params.epochDuration == 0) {
            revert InvalidEpochDuration();
        }

        if (params.adminFee > ADMIN_FEE_BASE) {
            revert InvalidAdminFee();
        }

        collateral = params.collateral;

        epochDurationInit = Time.timestamp();
        epochDuration = params.epochDuration;

        adminFee = params.adminFee;
        depositWhitelist = params.depositWhitelist;

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        if (params.depositWhitelist) {
            _grantRole(DEPOSITOR_WHITELIST_ROLE, owner);
        }

        IStakingControllerFactory(params.stakingControllerFactory).create(
            address(this), params.vetoDuration, params.executeDuration
        );
    }

    function _migrate(uint64, bytes memory) internal override {
        revert();
    }
}
