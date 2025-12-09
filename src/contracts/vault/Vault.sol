// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {MigratableEntity} from "../common/MigratableEntity.sol";
import {VaultStorage} from "./VaultStorage.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";
import {ERC4626Math} from "../libraries/ERC4626Math.sol";

import {IBaseDelegator} from "../../interfaces/delegator/IBaseDelegator.sol";
import {IBaseSlasher} from "../../interfaces/slasher/IBaseSlasher.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {IVault} from "../../interfaces/vault/IVault.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract Vault is VaultStorage, MigratableEntity, AccessControlUpgradeable, IVault {
    using Checkpoints for Checkpoints.Trace256;
    using Checkpoints for Checkpoints.Trace208;
    using Math for uint256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    constructor(address delegatorFactory, address slasherFactory, address vaultFactory)
        VaultStorage(delegatorFactory, slasherFactory)
        MigratableEntity(vaultFactory)
    {}

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
        return activeStake() + unmaturedWithdrawals(uint48(block.timestamp));
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
    function activeBalanceOf(address account) public view returns (uint256) {
        return ERC4626Math.previewRedeem(activeSharesOf(account), activeStake(), activeShares());
    }

    /**
     * @inheritdoc IVault
     */
    function withdrawalsOf(uint256 index, address account) public view returns (uint256) {
        Withdrawal memory withdrawal = _withdrawalsOf[account][index];
        uint256 bucketIndex = timeToBucket.upperLookupRecent(withdrawal.unlockAt);
        return ERC4626Math.previewRedeem(withdrawal.shares, _withdrawals[bucketIndex], _withdrawalShares[bucketIndex]);
    }

    /**
     * @inheritdoc IVault
     */
    function slashableBalanceOf(address account) external view returns (uint256) {
        uint256 amount;
        Withdrawal[] storage withdrawals_ = _withdrawalsOf[account];
        if (withdrawals_.length == 0) {
            return activeBalanceOf(account);
        }
        for (uint256 i = withdrawals_.length; i > 0;) {
            --i;
            Withdrawal memory withdrawal = withdrawals_[i];
            if (withdrawal.unlockAt <= block.timestamp) {
                break;
            }
            uint256 bucketIndex = timeToBucket.upperLookupRecent(withdrawal.unlockAt);
            amount += ERC4626Math.previewRedeem(
                withdrawal.shares, _withdrawals[bucketIndex], _withdrawalShares[bucketIndex]
            );
        }

        return activeBalanceOf(account) + amount;
    }

    /**
     * @inheritdoc IVault
     */
    function deposit(address onBehalfOf, uint256 amount)
        public
        virtual
        nonReentrant
        returns (uint256 depositedAmount, uint256 mintedShares)
    {
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

        _activeStake.push(uint48(block.timestamp), activeStake_ + depositedAmount);
        _activeShares.push(uint48(block.timestamp), activeShares_ + mintedShares);
        _activeSharesOf[onBehalfOf].push(uint48(block.timestamp), activeSharesOf(onBehalfOf) + mintedShares);

        emit Deposit(msg.sender, onBehalfOf, depositedAmount, mintedShares);
    }

    /**
     * @inheritdoc IVault
     */
    function withdraw(address claimer, uint256 amount)
        external
        nonReentrant
        returns (uint256 burnedShares, uint256 mintedShares)
    {
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
    function redeem(address claimer, uint256 shares)
        external
        nonReentrant
        returns (uint256 withdrawnAssets, uint256 mintedShares)
    {
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
    function claim(address recipient, uint256 index) external nonReentrant returns (uint256 amount) {
        if (recipient == address(0)) {
            revert InvalidRecipient();
        }

        amount = _claim(index);

        IERC20(collateral).safeTransfer(recipient, amount);

        emit Claim(msg.sender, recipient, index, amount);
    }

    /**
     * @inheritdoc IVault
     */
    function claimBatch(address recipient, uint256[] calldata indexes) external nonReentrant returns (uint256 amount) {
        if (recipient == address(0)) {
            revert InvalidRecipient();
        }

        uint256 length = indexes.length;
        if (length == 0) {
            revert InvalidLengthEpochs();
        }

        for (uint256 i; i < length; ++i) {
            amount += _claim(indexes[i]);
        }

        IERC20(collateral).safeTransfer(recipient, amount);

        emit ClaimBatch(msg.sender, recipient, indexes, amount);
    }

    /**
     * @inheritdoc IVault
     */
    function onSlash(uint256 amount, uint48 captureTimestamp) external nonReentrant returns (uint256 slashedAmount) {
        if (msg.sender != slasher) {
            revert NotSlasher();
        }

        if (captureTimestamp + epochDuration < uint48(block.timestamp) || captureTimestamp >= uint48(block.timestamp)) {
            revert InvalidCaptureEpoch();
        }

        uint256 unmaturedWithdrawals = unmaturedWithdrawals(uint48(block.timestamp));
        uint256 unmaturedWithdrawalShares = unmaturedWithdrawalShares(uint48(block.timestamp));
        uint208 lastBucket = timeToBucket.latest();
        _withdrawals[lastBucket] -= unmaturedWithdrawals;
        _withdrawalShares[lastBucket] -= unmaturedWithdrawalShares;
        _withdrawalShares[lastBucket + 1] = unmaturedWithdrawalShares;
        timeToBucket.push(uint48(block.timestamp), lastBucket + 1);

        uint256 activeStake_ = activeStake();
        uint256 slashableStake = activeStake_ + unmaturedWithdrawals;
        slashedAmount = Math.min(amount, slashableStake);

        if (slashedAmount > 0) {
            uint256 activeSlashed = slashedAmount.mulDiv(activeStake_, slashableStake);
            uint256 withdrawalsSlashed = slashedAmount - activeSlashed;

            _activeStake.push(uint48(block.timestamp), activeStake_ - activeSlashed);
            unmaturedWithdrawals -= withdrawalsSlashed;

            IERC20(collateral).safeTransfer(burner, slashedAmount);
        }
        _withdrawals[lastBucket + 1] = unmaturedWithdrawals;

        emit OnSlash(amount, captureTimestamp, slashedAmount);
    }

    /**
     * @inheritdoc IVault
     */
    function setDepositWhitelist(bool status) external nonReentrant onlyRole(DEPOSIT_WHITELIST_SET_ROLE) {
        if (depositWhitelist == status) {
            revert AlreadySet();
        }

        depositWhitelist = status;

        emit SetDepositWhitelist(status);
    }

    /**
     * @inheritdoc IVault
     */
    function setDepositorWhitelistStatus(address account, bool status)
        external
        nonReentrant
        onlyRole(DEPOSITOR_WHITELIST_ROLE)
    {
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
    function setIsDepositLimit(bool status) external nonReentrant onlyRole(IS_DEPOSIT_LIMIT_SET_ROLE) {
        if (isDepositLimit == status) {
            revert AlreadySet();
        }

        isDepositLimit = status;

        emit SetIsDepositLimit(status);
    }

    /**
     * @inheritdoc IVault
     */
    function setDepositLimit(uint256 limit) external nonReentrant onlyRole(DEPOSIT_LIMIT_SET_ROLE) {
        if (depositLimit == limit) {
            revert AlreadySet();
        }

        depositLimit = limit;

        emit SetDepositLimit(limit);
    }

    function setDelegator(address delegator_) external nonReentrant {
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

    function setSlasher(address slasher_) external nonReentrant {
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

    function _withdraw(address claimer, uint256 withdrawnAssets, uint256 burnedShares)
        internal
        virtual
        returns (uint256 mintedShares)
    {
        _activeSharesOf[msg.sender].push(uint48(block.timestamp), activeSharesOf(msg.sender) - burnedShares);
        _activeShares.push(uint48(block.timestamp), activeShares() - burnedShares);
        _activeStake.push(uint48(block.timestamp), activeStake() - withdrawnAssets);

        uint256 lastBucket = timeToBucket.latest();
        mintedShares =
            ERC4626Math.previewDeposit(withdrawnAssets, _withdrawalShares[lastBucket], _withdrawals[lastBucket]);
        _withdrawals[lastBucket] += withdrawnAssets;
        _withdrawalShares[lastBucket] += mintedShares;

        uint48 unlockAt = uint48(block.timestamp) + epochDuration;
        _withdrawalsOf[msg.sender].push(Withdrawal(false, unlockAt, mintedShares));
        withdrawalsPrefixes.push(unlockAt, withdrawalsPrefixes.latest() + withdrawnAssets);
        withdrawalSharesPrefixes.push(unlockAt, withdrawalSharesPrefixes.latest() + mintedShares);

        emit Withdraw(msg.sender, claimer, withdrawnAssets, burnedShares, mintedShares);
    }

    function _claim(uint256 index) internal returns (uint256 amount) {
        if (index >= _withdrawalsOf[msg.sender].length) {
            revert InvalidEpoch();
        }
        Withdrawal memory withdrawal = _withdrawalsOf[msg.sender][index];

        if (withdrawal.claimed) {
            revert AlreadyClaimed();
        }

        if (withdrawal.unlockAt >= block.timestamp) {
            revert WithdrawalNotMatured();
        }
        uint256 bucketIndex = timeToBucket.upperLookupRecent(withdrawal.unlockAt);
        _withdrawalsOf[msg.sender][index].claimed = true;
        amount = ERC4626Math.previewRedeem(withdrawal.shares, _withdrawals[bucketIndex], _withdrawalShares[bucketIndex]);
    }

    function _initialize(uint64, address, bytes memory data) internal virtual override {
        (InitParams memory params) = abi.decode(data, (InitParams));

        if (params.collateral == address(0)) {
            revert InvalidCollateral();
        }

        if (params.epochDuration == 0) {
            revert InvalidEpochDuration();
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

        burner = params.burner;

        epochDurationInit = uint48(block.timestamp);
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

    function _migrate(
        uint64,
        /* oldVersion */
        uint64,
        /* newVersion */
        bytes calldata /* data */
    )
        internal
        override
    {
        revert();
    }
}
