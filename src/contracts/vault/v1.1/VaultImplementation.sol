// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {VaultStorage} from "./VaultStorage.sol";

import {IBaseDelegator} from "../../../interfaces/delegator/IBaseDelegator.sol";
import {IBaseSlasher} from "../../../interfaces/slasher/IBaseSlasher.sol";
import {IRegistry} from "../../../interfaces/common/IRegistry.sol";
import {IVault} from "../../../interfaces/vault/v1.1/IVault.sol";

import {Checkpoints} from "../../libraries/Checkpoints.sol";
import {ERC4626Math} from "../../libraries/ERC4626Math.sol";

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";

contract VaultImplementation is VaultStorage, AccessControlUpgradeable, ReentrancyGuardUpgradeable, IVault {
    using Checkpoints for Checkpoints.Trace256;
    using Math for uint256;
    using Math for uint48;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    constructor(address delegatorFactory, address slasherFactory) VaultStorage(delegatorFactory, slasherFactory) {}

    /**
     * @inheritdoc IVault
     */
    function epochDuration() public view returns (uint48) {
        if (nextEpochDurationInitInternal == 0 || Time.timestamp() < nextEpochDurationInitInternal) {
            return epochDurationInternal;
        }
        return nextEpochDurationInternal;
    }

    /**
     * @inheritdoc IVault
     */
    function epochDurationInit() public view returns (uint48) {
        if (nextEpochDurationInitInternal == 0 || Time.timestamp() < nextEpochDurationInitInternal) {
            return epochDurationInitInternal;
        }
        return nextEpochDurationInitInternal;
    }

    /**
     * @inheritdoc IVault
     */
    function epochAt(
        uint48 timestamp
    ) public view returns (uint256) {
        if (timestamp < epochDurationInitInternal) {
            if (prevEpochDurationInitInternal == 0 || timestamp < prevEpochDurationInitInternal) {
                revert InvalidTimestamp();
            }
            return prevEpochInitInternal + (timestamp - prevEpochDurationInitInternal) / prevEpochDurationInternal;
        } else if (nextEpochDurationInitInternal == 0 || timestamp < nextEpochDurationInitInternal) {
            return epochInitInternal + (timestamp - epochDurationInitInternal) / epochDurationInternal;
        } else {
            return nextEpochInitInternal + (timestamp - nextEpochDurationInitInternal) / nextEpochDurationInternal;
        }
    }

    function epochStart(
        uint256 epoch
    ) public view returns (uint48) {
        if (epoch < prevEpochInitInternal) {
            revert();
        }

        if (epoch < epochInitInternal) {
            return
                (prevEpochDurationInitInternal + (epoch - prevEpochInitInternal) * prevEpochDurationInternal).toUint48();
        } else if (nextEpochInitInternal == 0 || epoch < nextEpochInitInternal) {
            return (epochDurationInitInternal + (epoch - epochInitInternal) * epochDurationInternal).toUint48();
        } else {
            return
                (nextEpochDurationInitInternal + (epoch - nextEpochInitInternal) * nextEpochDurationInternal).toUint48();
        }
    }

    /**
     * @inheritdoc IVault
     */
    function currentEpoch() public view returns (uint256) {
        return epochAt(Time.timestamp());
    }

    /**
     * @inheritdoc IVault
     */
    function currentEpochStart() public view returns (uint48) {
        return epochStart(currentEpoch());
    }

    /**
     * @inheritdoc IVault
     */
    function previousEpochStart() public view returns (uint48) {
        uint256 epoch = currentEpoch();
        if (epoch == 0) {
            revert NoPreviousEpoch();
        }
        return epochStart(epoch - 1);
    }

    /**
     * @inheritdoc IVault
     */
    function nextEpochStart() public view returns (uint48) {
        return epochStart(currentEpoch() + 1);
    }

    /**
     * @inheritdoc IVault
     */
    function activeSharesAt(uint48 timestamp, bytes memory hint) public view returns (uint256) {
        return _activeShares.upperLookupRecent(timestamp, hint);
    }

    /**
     * @inheritdoc IVault
     */
    function activeShares() public view returns (uint256) {
        return _activeShares.latest();
    }

    /**
     * @inheritdoc IVault
     */
    function activeStakeAt(uint48 timestamp, bytes memory hint) public view returns (uint256) {
        return _activeStake.upperLookupRecent(timestamp, hint);
    }

    /**
     * @inheritdoc IVault
     */
    function activeStake() public view returns (uint256) {
        return _activeStake.latest();
    }

    /**
     * @inheritdoc IVault
     */
    function activeSharesOfAt(address account, uint48 timestamp, bytes memory hint) public view returns (uint256) {
        return _activeSharesOf[account].upperLookupRecent(timestamp, hint);
    }

    /**
     * @inheritdoc IVault
     */
    function activeSharesOf(
        address account
    ) public view returns (uint256) {
        return _activeSharesOf[account].latest();
    }

    /**
     * @inheritdoc IVault
     */
    function isInitialized() external view returns (bool) {
        return isDelegatorInitialized && isSlasherInitialized;
    }

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
     * @inheritdoc IERC3156FlashLender
     */
    function maxFlashLoan(
        address token
    ) public view returns (uint256) {
        address collateral_ = collateral;
        return token == collateral_ ? IERC20(collateral_).balanceOf(address(this)) : 0;
    }

    /**
     * @inheritdoc IERC3156FlashLender
     */
    function flashFee(address token, uint256 value) public view returns (uint256) {
        if (token != collateral) {
            revert UnsupportedToken();
        }
        return value.mulDiv(flashFeeRate, FLASH_FEE_BASE);
    }

    /**
     * @inheritdoc IVault
     */
    function deposit(
        address onBehalfOf,
        uint256 amount
    ) external nonReentrant returns (uint256 depositedAmount, uint256 mintedShares) {
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

        if (isDepositLimit && activeStake() + depositedAmount > depositLimit) {
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
    ) external nonReentrant returns (uint256 burnedShares, uint256 mintedShares) {
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
    }

    /**
     * @inheritdoc IVault
     */
    function redeem(
        address claimer,
        uint256 shares
    ) external nonReentrant returns (uint256 withdrawnAssets, uint256 mintedShares) {
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
    }

    /**
     * @inheritdoc IVault
     */
    function claim(address recipient, uint256 epoch) external nonReentrant returns (uint256 amount) {
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
    function claimBatch(address recipient, uint256[] calldata epochs) external nonReentrant returns (uint256 amount) {
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
     * @inheritdoc IERC3156FlashLender
     */
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 value,
        bytes calldata data
    ) public nonReentrant returns (bool) {
        if (value > maxFlashLoan(token)) {
            revert MaxLoanExceeded();
        }
        uint256 fee = flashFee(token, value);
        address collateral_ = collateral;
        uint256 balanceBefore = IERC20(collateral_).balanceOf(address(this));

        IERC20(collateral_).safeTransfer(address(receiver), value);

        if (receiver.onFlashLoan(msg.sender, token, value, fee, data) != RETURN_VALUE) {
            revert InvalidReceiver();
        }

        if (IERC20(collateral_).balanceOf(address(this)) - balanceBefore != fee) {
            revert InvalidReturnAmount();
        }

        if (flashFeeReceiver != address(0)) {
            IERC20(collateral_).safeTransfer(flashFeeReceiver, fee);
        }

        return true;
    }

    /**
     * @inheritdoc IVault
     */
    function onSlash(uint256 amount, uint48 captureTimestamp) external nonReentrant returns (uint256 slashedAmount) {
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
            slashedAmount = Math.min(amount, slashableStake);
            if (slashedAmount > 0) {
                uint256 activeSlashed = slashedAmount.mulDiv(activeStake_, slashableStake);
                uint256 nextWithdrawalsSlashed = slashedAmount - activeSlashed;

                _activeStake.push(Time.timestamp(), activeStake_ - activeSlashed);
                withdrawals[captureEpoch + 1] = nextWithdrawals - nextWithdrawalsSlashed;
            }
        } else {
            uint256 withdrawals_ = withdrawals[currentEpoch_];
            uint256 slashableStake = activeStake_ + withdrawals_ + nextWithdrawals;
            slashedAmount = Math.min(amount, slashableStake);
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

        emit OnSlash(amount, captureTimestamp, slashedAmount);
    }

    /**
     * @inheritdoc IVault
     */
    function setDepositWhitelist(
        bool status
    ) external nonReentrant onlyRole(DEPOSIT_WHITELIST_SET_ROLE) {
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
    ) external nonReentrant onlyRole(DEPOSITOR_WHITELIST_ROLE) {
        if (account == address(0)) {
            revert InvalidAccount();
        }

        if (isDepositorWhitelisted[account] == status) {
            revert AlreadySet();
        }

        isDepositorWhitelisted[account] = status;

        emit SetDepositorWhitelistStatus(account, status);
    }

    /**
     * @inheritdoc IVault
     */
    function setIsDepositLimit(
        bool status
    ) external nonReentrant onlyRole(IS_DEPOSIT_LIMIT_SET_ROLE) {
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
    ) external nonReentrant onlyRole(DEPOSIT_LIMIT_SET_ROLE) {
        if (depositLimit == limit) {
            revert AlreadySet();
        }

        depositLimit = limit;

        emit SetDepositLimit(limit);
    }

    /**
     * @inheritdoc IVault
     */
    function setEpochDuration(
        uint48 epochDuration_
    ) external nonReentrant onlyRole(EPOCH_DURATION_SET_ROLE) {
        if (nextEpochDurationInitInternal != 0 && nextEpochDurationInitInternal <= Time.timestamp()) {
            uint256 currentEpoch_ = currentEpoch();
            uint48 currentEpochStart_ = currentEpochStart();

            prevEpochInitInternal = epochInitInternal;
            prevEpochDurationInternal = epochDurationInternal;
            prevEpochDurationInitInternal = epochDurationInitInternal;
            epochInitInternal = currentEpoch_;
            epochDurationInternal = nextEpochDurationInternal;
            epochDurationInitInternal = currentEpochStart_;
            nextEpochInitInternal = 0;
            nextEpochDurationInternal = 0;
            nextEpochDurationInitInternal = 0;
        }

        if (epochDurationInternal > epochDuration_) {
            revert InvalidNewEpochDuration();
        }

        if (nextEpochDurationInitInternal != 0) {
            nextEpochInitInternal = 0;
            nextEpochDurationInternal = 0;
            nextEpochDurationInitInternal = 0;
        } else if (epochDurationInternal == epochDuration_) {
            revert AlreadySet();
        }

        if (epochDurationInternal != epochDuration_) {
            nextEpochInitInternal = currentEpoch() + epochDurationSetEpochsDelay;
            nextEpochDurationInternal = epochDuration_;
            nextEpochDurationInitInternal =
                (currentEpochStart() + epochDurationSetEpochsDelay * epochDurationInternal).toUint48();
        }

        emit SetEpochDuration(epochDuration_);
    }

    /**
     * @inheritdoc IVault
     */
    function setFlashFeeRate(
        uint256 flashFeeRate_
    ) external nonReentrant onlyRole(FLASH_FEE_RATE_SET_ROLE) {
        if (flashFeeRate == flashFeeRate_) {
            revert AlreadySet();
        }
        flashFeeRate = flashFeeRate_;

        emit SetFlashFeeRate(flashFeeRate_);
    }

    /**
     * @inheritdoc IVault
     */
    function setFlashFeeReceiver(
        address flashFeeReceiver_
    ) external nonReentrant onlyRole(FLASH_FEE_RECEIVER_SET_ROLE) {
        if (flashFeeReceiver == flashFeeReceiver_) {
            revert AlreadySet();
        }
        flashFeeReceiver = flashFeeReceiver_;

        emit SetFlashFeeReceiver(flashFeeReceiver_);
    }

    /**
     * @inheritdoc IVault
     */
    function setDelegator(
        address delegator_
    ) external nonReentrant {
        if (isDelegatorInitialized) {
            revert DelegatorAlreadyInitialized();
        }

        if (!IRegistry(DELEGATOR_FACTORY).isEntity(delegator_)) {
            revert NotDelegator();
        }

        if (IBaseDelegator(delegator_).vault() != address(this)) {
            revert InvalidDelegator();
        }

        delegator = delegator_;

        isDelegatorInitialized = true;

        emit SetDelegator(delegator_);
    }

    /**
     * @inheritdoc IVault
     */
    function setSlasher(
        address slasher_
    ) external nonReentrant {
        if (isSlasherInitialized) {
            revert SlasherAlreadyInitialized();
        }

        if (slasher_ != address(0)) {
            if (!IRegistry(SLASHER_FACTORY).isEntity(slasher_)) {
                revert NotSlasher();
            }

            if (IBaseSlasher(slasher_).vault() != address(this)) {
                revert InvalidSlasher();
            }

            slasher = slasher_;
        }

        isSlasherInitialized = true;

        emit SetSlasher(slasher_);
    }

    function _withdraw(
        address claimer,
        uint256 withdrawnAssets,
        uint256 burnedShares
    ) internal returns (uint256 mintedShares) {
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

        emit Withdraw(msg.sender, claimer, withdrawnAssets, burnedShares, mintedShares);
    }

    function _claim(
        uint256 epoch
    ) internal returns (uint256 amount) {
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

    function _Vault_init() external {}
}
