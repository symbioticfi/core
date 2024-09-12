// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {MigratableEntity} from "../common/MigratableEntity.sol";
import {VaultStorage} from "./VaultStorage.sol";

import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {IVault} from "../../interfaces/vault/IVault.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";
import {ERC4626Math} from "../libraries/ERC4626Math.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract Vault is VaultStorage, MigratableEntity, AccessControlUpgradeable, IVault {
    using Checkpoints for Checkpoints.Trace256;
    using Math for uint256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    constructor(
        address delegatorFactory,
        address slasherFactory,
        address vaultFactory
    ) VaultStorage(delegatorFactory, slasherFactory) MigratableEntity(vaultFactory) {}

    /**
     * @inheritdoc IVault
     */
    function totalStake() public view returns (uint256) {
        uint256 epoch = currentEpoch();
        return activeStake() + withdrawals[epoch] + withdrawals[epoch + 1];
    }

    /**
     * @inheritdoc IVault
     */
    function activeBalanceOfAt(address account, uint48 timestamp, bytes calldata hints) public view returns (uint256) {
        ActiveBalanceOfHints memory activeBalanceOfHints;
        if (hints.length > 0) {
            activeBalanceOfHints = abi.decode(hints, (ActiveBalanceOfHints));
        }
        return ERC4626Math.previewRedeem(
            activeSharesOfAt(account, timestamp, activeBalanceOfHints.activeSharesOfHint),
            activeStakeAt(timestamp, activeBalanceOfHints.activeStakeHint),
            activeSharesAt(timestamp, activeBalanceOfHints.activeSharesHint)
        );
    }

    /**
     * @inheritdoc IVault
     */
    function activeBalanceOf(
        address account
    ) public view returns (uint256) {
        return ERC4626Math.previewRedeem(activeSharesOf(account), activeStake(), activeShares());
    }

    /**
     * @inheritdoc IVault
     */
    function withdrawalsOf(uint256 epoch, address account) public view returns (uint256) {
        return
            ERC4626Math.previewRedeem(withdrawalSharesOf[epoch][account], withdrawals[epoch], withdrawalShares[epoch]);
    }

    /**
     * @inheritdoc IVault
     */
    function slashableBalanceOf(
        address account
    ) external view returns (uint256) {
        uint256 epoch = currentEpoch();
        return activeBalanceOf(account) + withdrawalsOf(epoch, account) + withdrawalsOf(epoch + 1, account);
    }

    /**
     * @inheritdoc IVault
     */
    function deposit(
        address onBehalfOf,
        uint256 amount
    ) external initialized nonReentrant returns (uint256 depositedAmount, uint256 mintedShares) {
        if (onBehalfOf == address(0)) {
            revert InvalidOnBehalfOf();
        }

        if (depositWhitelist && !isDepositorWhitelisted[msg.sender]) {
            revert NotWhitelistedDepositor();
        }

        uint256 balanceBefore = IERC20(collateral).balanceOf(address(this));
        IERC20(collateral).safeTransferFrom(msg.sender, address(this), amount);
        depositedAmount = IERC20(collateral).balanceOf(address(this)) - balanceBefore;

        if (depositedAmount == 0) {
            revert InsufficientDeposit();
        }

        if (isDepositLimit && totalStake() + depositedAmount > depositLimit) {
            revert DepositLimitReached();
        }

        uint256 activeStake_ = activeStake();
        uint256 activeShares_ = activeShares();

        mintedShares = ERC4626Math.previewDeposit(depositedAmount, activeShares_, activeStake_);

        _activeStake.push(Time.timestamp(), activeStake_ + depositedAmount);
        _activeShares.push(Time.timestamp(), activeShares_ + mintedShares);
        _activeSharesOf[onBehalfOf].push(Time.timestamp(), activeSharesOf(onBehalfOf) + mintedShares);

        emit Deposit(msg.sender, onBehalfOf, depositedAmount, mintedShares);
    }

    /**
     * @inheritdoc IVault
     */
    function withdraw(
        address claimer,
        uint256 amount
    ) external initialized nonReentrant returns (uint256 burnedShares, uint256 mintedShares) {
        if (claimer == address(0)) {
            revert InvalidClaimer();
        }

        if (amount == 0) {
            revert InsufficientWithdrawal();
        }

        burnedShares = ERC4626Math.previewWithdraw(amount, activeShares(), activeStake());

        if (burnedShares > activeSharesOf(msg.sender)) {
            revert TooMuchWithdraw();
        }

        mintedShares = _withdraw(claimer, amount, burnedShares);

        emit Withdraw(msg.sender, claimer, amount, burnedShares, mintedShares);
    }

    /**
     * @inheritdoc IVault
     */
    function redeem(
        address claimer,
        uint256 shares
    ) external initialized nonReentrant returns (uint256 withdrawnAssets, uint256 mintedShares) {
        if (claimer == address(0)) {
            revert InvalidClaimer();
        }

        if (shares > activeSharesOf(msg.sender)) {
            revert TooMuchRedeem();
        }

        withdrawnAssets = ERC4626Math.previewRedeem(shares, activeStake(), activeShares());

        if (withdrawnAssets == 0) {
            revert InsufficientRedemption();
        }

        mintedShares = _withdraw(claimer, withdrawnAssets, shares);

        emit Redeem(msg.sender, claimer, shares, withdrawnAssets, mintedShares);
    }

    /**
     * @inheritdoc IVault
     */
    function claim(address recipient, uint256 epoch) external initialized nonReentrant returns (uint256 amount) {
        if (recipient == address(0)) {
            revert InvalidRecipient();
        }

        amount = _claim(epoch);

        IERC20(collateral).safeTransfer(recipient, amount);

        emit Claim(msg.sender, recipient, epoch, amount);
    }

    /**
     * @inheritdoc IVault
     */
    function claimBatch(
        address recipient,
        uint256[] calldata epochs
    ) external initialized nonReentrant returns (uint256 amount) {
        if (recipient == address(0)) {
            revert InvalidRecipient();
        }

        uint256 length = epochs.length;
        if (length == 0) {
            revert InvalidLengthEpochs();
        }

        for (uint256 i; i < length; ++i) {
            amount += _claim(epochs[i]);
        }

        IERC20(collateral).safeTransfer(recipient, amount);

        emit ClaimBatch(msg.sender, recipient, epochs, amount);
    }

    /**
     * @inheritdoc IVault
     */
    function onSlash(uint256 slashedAmount, uint48 captureTimestamp) external initialized nonReentrant {
        if (msg.sender != slasher) {
            revert NotSlasher();
        }

        uint256 currentEpoch_ = currentEpoch();
        uint256 captureEpoch = epochAt(captureTimestamp);
        if ((currentEpoch_ > 0 && captureEpoch < currentEpoch_ - 1) || captureEpoch > currentEpoch_) {
            revert InvalidCaptureEpoch();
        }

        uint256 activeStake_ = activeStake();
        uint256 nextWithdrawals = withdrawals[currentEpoch_ + 1];
        if (captureEpoch == currentEpoch_) {
            uint256 slashableStake = activeStake_ + nextWithdrawals;
            slashedAmount = Math.min(slashedAmount, slashableStake);
            if (slashedAmount > 0) {
                uint256 activeSlashed = slashedAmount.mulDiv(activeStake_, slashableStake);
                uint256 nextWithdrawalsSlashed = slashedAmount - activeSlashed;

                _activeStake.push(Time.timestamp(), activeStake_ - activeSlashed);
                withdrawals[captureEpoch + 1] = nextWithdrawals - nextWithdrawalsSlashed;
            }
        } else {
            uint256 withdrawals_ = withdrawals[currentEpoch_];
            uint256 slashableStake = activeStake_ + withdrawals_ + nextWithdrawals;
            slashedAmount = Math.min(slashedAmount, slashableStake);
            if (slashedAmount > 0) {
                uint256 activeSlashed = slashedAmount.mulDiv(activeStake_, slashableStake);
                uint256 nextWithdrawalsSlashed = slashedAmount.mulDiv(nextWithdrawals, slashableStake);
                uint256 withdrawalsSlashed = slashedAmount - activeSlashed - nextWithdrawalsSlashed;

                if (withdrawals_ < withdrawalsSlashed) {
                    nextWithdrawalsSlashed += withdrawalsSlashed - withdrawals_;
                    withdrawalsSlashed = withdrawals_;
                }

                _activeStake.push(Time.timestamp(), activeStake_ - activeSlashed);
                withdrawals[currentEpoch_ + 1] = nextWithdrawals - nextWithdrawalsSlashed;
                withdrawals[currentEpoch_] = withdrawals_ - withdrawalsSlashed;
            }
        }

        if (slashedAmount > 0) {
            IERC20(collateral).safeTransfer(burner, slashedAmount);
        }

        emit OnSlash(msg.sender, slashedAmount);
    }

    /**
     * @inheritdoc IVault
     */
    function setDepositWhitelist(
        bool status
    ) external initialized nonReentrant onlyRole(DEPOSIT_WHITELIST_SET_ROLE) {
        if (depositWhitelist == status) {
            revert AlreadySet();
        }

        depositWhitelist = status;

        emit SetDepositWhitelist(status);
    }

    /**
     * @inheritdoc IVault
     */
    function setDepositorWhitelistStatus(
        address account,
        bool status
    ) external initialized nonReentrant onlyRole(DEPOSITOR_WHITELIST_ROLE) {
        if (account == address(0)) {
            revert InvalidAccount();
        }

        if (isDepositorWhitelisted[account] == status) {
            revert AlreadySet();
        }

        if (status && !depositWhitelist) {
            revert NoDepositWhitelist();
        }

        isDepositorWhitelisted[account] = status;

        emit SetDepositorWhitelistStatus(account, status);
    }

    /**
     * @inheritdoc IVault
     */
    function setIsDepositLimit(
        bool status
    ) external initialized nonReentrant onlyRole(IS_DEPOSIT_LIMIT_SET_ROLE) {
        if (isDepositLimit == status) {
            revert AlreadySet();
        }

        isDepositLimit = status;

        emit SetIsDepositLimit(status);
    }

    /**
     * @inheritdoc IVault
     */
    function setDepositLimit(
        uint256 limit
    ) external initialized nonReentrant onlyRole(DEPOSIT_LIMIT_SET_ROLE) {
        if (limit != 0 && !isDepositLimit) {
            revert NoDepositLimit();
        }

        if (depositLimit == limit) {
            revert AlreadySet();
        }

        depositLimit = limit;

        emit SetDepositLimit(limit);
    }

    function _withdraw(
        address claimer,
        uint256 withdrawnAssets,
        uint256 burnedShares
    ) private returns (uint256 mintedShares) {
        _activeSharesOf[msg.sender].push(Time.timestamp(), activeSharesOf(msg.sender) - burnedShares);
        _activeShares.push(Time.timestamp(), activeShares() - burnedShares);
        _activeStake.push(Time.timestamp(), activeStake() - withdrawnAssets);

        uint256 epoch = currentEpoch() + 1;
        uint256 withdrawals_ = withdrawals[epoch];
        uint256 withdrawalsShares_ = withdrawalShares[epoch];

        mintedShares = ERC4626Math.previewDeposit(withdrawnAssets, withdrawalsShares_, withdrawals_);

        withdrawals[epoch] = withdrawals_ + withdrawnAssets;
        withdrawalShares[epoch] = withdrawalsShares_ + mintedShares;
        withdrawalSharesOf[epoch][claimer] += mintedShares;
    }

    function _claim(
        uint256 epoch
    ) private returns (uint256 amount) {
        if (epoch >= currentEpoch()) {
            revert InvalidEpoch();
        }

        if (isWithdrawalsClaimed[epoch][msg.sender]) {
            revert AlreadyClaimed();
        }

        amount = withdrawalsOf(epoch, msg.sender);

        if (amount == 0) {
            revert InsufficientClaim();
        }

        isWithdrawalsClaimed[epoch][msg.sender] = true;
    }

    function _initialize(uint64, address, bytes calldata data) internal override {
        (IVault.InitParams memory params) = abi.decode(data, (IVault.InitParams));

        if (params.collateral == address(0)) {
            revert InvalidCollateral();
        }

        if (params.epochDuration == 0) {
            revert InvalidEpochDuration();
        }

        if (!IRegistry(DELEGATOR_FACTORY).isEntity(params.delegator)) {
            revert NotDelegator();
        }

        if (params.slasher != address(0) && !IRegistry(SLASHER_FACTORY).isEntity(params.slasher)) {
            revert NotSlasher();
        }

        if (params.defaultAdminRoleHolder == address(0)) {
            if (params.depositWhitelistSetRoleHolder == address(0)) {
                if (params.depositWhitelist) {
                    if (params.depositorWhitelistRoleHolder == address(0)) {
                        revert MissingRoles();
                    }
                } else if (params.depositorWhitelistRoleHolder != address(0)) {
                    revert MissingRoles();
                }
            }

            if (params.isDepositLimitSetRoleHolder == address(0)) {
                if (params.isDepositLimit) {
                    if (params.depositLimit == 0 && params.depositLimitSetRoleHolder == address(0)) {
                        revert MissingRoles();
                    }
                } else if (params.depositLimit != 0 || params.depositLimitSetRoleHolder != address(0)) {
                    revert MissingRoles();
                }
            }
        }

        collateral = params.collateral;

        delegator = params.delegator;

        slasher = params.slasher;

        burner = params.burner;

        epochDurationInit = Time.timestamp();
        epochDuration = params.epochDuration;

        depositWhitelist = params.depositWhitelist;

        isDepositLimit = params.isDepositLimit;
        depositLimit = params.depositLimit;

        if (params.defaultAdminRoleHolder != address(0)) {
            _grantRole(DEFAULT_ADMIN_ROLE, params.defaultAdminRoleHolder);
        }
        if (params.depositWhitelistSetRoleHolder != address(0)) {
            _grantRole(DEPOSIT_WHITELIST_SET_ROLE, params.depositWhitelistSetRoleHolder);
        }
        if (params.depositorWhitelistRoleHolder != address(0)) {
            _grantRole(DEPOSITOR_WHITELIST_ROLE, params.depositorWhitelistRoleHolder);
        }
        if (params.isDepositLimitSetRoleHolder != address(0)) {
            _grantRole(IS_DEPOSIT_LIMIT_SET_ROLE, params.isDepositLimitSetRoleHolder);
        }
        if (params.depositLimitSetRoleHolder != address(0)) {
            _grantRole(DEPOSIT_LIMIT_SET_ROLE, params.depositLimitSetRoleHolder);
        }
    }

    function _migrate(uint64, uint64, bytes calldata) internal override {
        revert();
    }
}
