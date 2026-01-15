// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {MigratableEntity} from "../common/MigratableEntity.sol";
import {VaultV2Storage} from "./VaultV2Storage.sol";
import {DelegatorFactory} from "../DelegatorFactory.sol";
import {SlasherFactory} from "../SlasherFactory.sol";
import {UniversalSlasher} from "../slasher/UniversalSlasher.sol";
import {UniversalDelegator} from "../delegator/UniversalDelegator.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";
import {ERC4626Math} from "../libraries/ERC4626Math.sol";
import {Math512} from "../libraries/Math512.sol";

import {IBaseDelegator} from "../../interfaces/delegator/IBaseDelegator.sol";
import {IBaseSlasher} from "../../interfaces/slasher/IBaseSlasher.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {IVaultV2} from "../../interfaces/vault/IVaultV2.sol";
import {IBasePlugin} from "../../interfaces/vault/IBasePlugin.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

contract VaultV2 is VaultV2Storage, MigratableEntity, AccessControlUpgradeable, ERC20PermitUpgradeable, IVaultV2 {
    using Checkpoints for Checkpoints.Trace256;
    using Checkpoints for Checkpoints.Trace208;
    using Checkpoints for Checkpoints.Trace512;
    using Math for uint256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;
    using Math512 for uint256[2];

    /* CONSTRUCTOR */

    constructor(address delegatorFactory, address slasherFactory, address pluginRegistry, address vaultFactory)
        VaultV2Storage(delegatorFactory, slasherFactory, pluginRegistry)
        MigratableEntity(vaultFactory)
    {}

    /**
     * @inheritdoc IVaultV2
     */
    function isInitialized() external view returns (bool) {
        return isDelegatorInitialized && isSlasherInitialized;
    }

    /* ACCOUNTING FUNCTIONS */

    /* * PUBLIC FUNCTIONS * */

    /**
     * @inheritdoc IVaultV2
     */
    function totalStake() public view returns (uint256) {
        uint208 lastBucket = _timeToBucket.latest();
        uint256 lastWithdrawalShares = withdrawalShares[lastBucket];
        return activeStake()
            + (lastWithdrawalShares > 0
                    ? _withdrawalSharesCumulative.latest()
                        .sub(_withdrawalSharesCumulative.upperLookupRecent(uint48(block.timestamp)))
                        .mulDiv(withdrawals[lastBucket], lastWithdrawalShares)
                    : 0);
    }

    /**
     * @inheritdoc IVaultV2
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
     * @inheritdoc IVaultV2
     */
    function activeBalanceOf(address account) public view returns (uint256) {
        return ERC4626Math.previewRedeem(activeSharesOf(account), activeStake(), activeShares());
    }

    /**
     * @inheritdoc IVaultV2
     */
    function withdrawalsOf(uint256 index, address account) public view returns (uint256) {
        uint256 bucketIndex = _timeToBucket.upperLookupRecent(withdrawalUnlockAt(index, account));
        return ERC4626Math.previewRedeem(
            withdrawalSharesOf(index, account), withdrawals[bucketIndex], withdrawalShares[bucketIndex]
        );
    }

    /**
     * @inheritdoc ERC20Upgradeable
     */
    function decimals() public view override returns (uint8) {
        return IERC20Metadata(collateral).decimals();
    }

    /**
     * @inheritdoc ERC20Upgradeable
     */
    function totalSupply() public view override returns (uint256) {
        return activeShares();
    }

    /**
     * @inheritdoc ERC20Upgradeable
     */
    function balanceOf(address account) public view override returns (uint256) {
        return activeSharesOf(account);
    }

    /**
     * @inheritdoc IVaultV2
     */
    function deposit(address onBehalfOf, uint256 amount)
        public
        virtual
        nonReentrant
        returns (uint256 depositedAmount, uint256 mintedShares)
    {
        if (onBehalfOf != address(0) && depositWhitelist && !isDepositorWhitelisted[msg.sender]) {
            revert NotWhitelistedDepositor();
        }

        uint256 balanceBefore = IERC20(collateral).balanceOf(address(this));
        IERC20(collateral).safeTransferFrom(msg.sender, address(this), amount);
        depositedAmount = IERC20(collateral).balanceOf(address(this)) - balanceBefore;

        if (depositedAmount == 0) {
            revert InsufficientAmount();
        }

        if (onBehalfOf == address(0)) {
            _activeStake.push(uint48(block.timestamp), activeStake() + depositedAmount);
            emit Deposit(msg.sender, address(0), depositedAmount, 0);
            return (depositedAmount, 0);
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
        emit Transfer(address(0), onBehalfOf, mintedShares);
    }

    /**
     * @inheritdoc IVaultV2
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
     * @inheritdoc IVaultV2
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
     * @inheritdoc IVaultV2
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
     * @inheritdoc IVaultV2
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

    // @dev Internal dev function to handle slashing.
    function onSlash(uint256 amount, uint48 captureTimestamp)
        external
        nonReentrant
        returns (uint256 slashedAmount, uint256 owed)
    {
        if (msg.sender != slasher) {
            revert NotSlasher();
        }
        if (captureTimestamp + epochDuration < uint48(block.timestamp) || captureTimestamp >= uint48(block.timestamp)) {
            revert InvalidCaptureEpoch();
        }
        uint208 lastBucket = _timeToBucket.latest();
        uint256 lastWithdrawals = withdrawals[lastBucket];
        uint256 lastWithdrawalShares = withdrawalShares[lastBucket];
        uint256 unmaturedWithdrawalShares = _withdrawalSharesCumulative.latest()
            .sub(_withdrawalSharesCumulative.upperLookupRecent(uint48(block.timestamp)));
        uint256 unmaturedWithdrawals =
            lastWithdrawalShares > 0 ? unmaturedWithdrawalShares.mulDiv(lastWithdrawals, lastWithdrawalShares) : 0;

        uint256 activeStake_ = activeStake();
        uint256 slashableStake = activeStake_ + unmaturedWithdrawals;
        slashedAmount = Math.min(amount, slashableStake);
        if (slashedAmount > 0) {
            _timeToBucket.push(uint48(block.timestamp), lastBucket + 1);
            withdrawals[lastBucket] = lastWithdrawals - unmaturedWithdrawals;
            withdrawalShares[lastBucket] = lastWithdrawalShares - unmaturedWithdrawalShares;
            withdrawalShares[lastBucket + 1] = unmaturedWithdrawalShares;

            uint256 activeSlashed = slashedAmount.mulDiv(activeStake_, slashableStake);
            _activeStake.push(uint48(block.timestamp), activeStake_ - activeSlashed);
            withdrawals[lastBucket + 1] = unmaturedWithdrawals - (slashedAmount - activeSlashed);

            _pullPlugins();

            uint256 instantSlashableStake = IERC20(collateral).balanceOf(address(this)).saturatingSub(_unclaimed);
            owed = slashedAmount.saturatingSub(instantSlashableStake);
            if (owed < slashedAmount) {
                IERC20(collateral).safeTransfer(burner, slashedAmount - owed);
            }
        }

        emit OnSlash(amount, captureTimestamp, slashedAmount);
    }

    /* * INTERNAL FUNCTIONS * */

    function _withdraw(address claimer, uint256 withdrawnAssets, uint256 burnedShares)
        internal
        virtual
        returns (uint256 mintedShares)
    {
        _activeSharesOf[msg.sender].push(uint48(block.timestamp), activeSharesOf(msg.sender) - burnedShares);
        _activeShares.push(uint48(block.timestamp), activeShares() - burnedShares);
        _activeStake.push(uint48(block.timestamp), activeStake() - withdrawnAssets);

        uint256 lastBucket = _timeToBucket.latest();
        mintedShares =
            ERC4626Math.previewDeposit(withdrawnAssets, withdrawalShares[lastBucket], withdrawals[lastBucket]);
        withdrawals[lastBucket] += withdrawnAssets;
        withdrawalShares[lastBucket] += mintedShares;

        uint48 unlockAt = uint48(block.timestamp) + epochDuration;
        _withdrawalsOf[claimer].push(Withdrawal(false, unlockAt, mintedShares));
        _withdrawalSharesCumulative.push(unlockAt, _withdrawalSharesCumulative.latest().add(mintedShares));

        _pullPlugins();

        emit Withdraw(msg.sender, claimer, withdrawnAssets, burnedShares, mintedShares);
        emit Transfer(msg.sender, address(0), burnedShares);
    }

    function _claim(uint256 index) internal returns (uint256 amount) {
        _pullPlugins();

        Withdrawal storage withdrawal = _withdrawalsOf[msg.sender][index];
        if (withdrawal.claimed) {
            revert AlreadyClaimed();
        }
        if (withdrawal.unlockAt >= block.timestamp) {
            revert WithdrawalNotMatured();
        }
        amount = withdrawalsOf(index, msg.sender);
        if (amount == 0) {
            revert InsufficientClaim();
        }
        withdrawal.claimed = true;
    }

    /* OWNER FUNCTIONS */

    /* * PUBLIC FUNCTIONS * */

    /**
     * @inheritdoc IVaultV2
     */
    function setDepositWhitelist(bool status) external nonReentrant onlyRole(DEPOSIT_WHITELIST_SET_ROLE) {
        if (depositWhitelist == status) {
            revert AlreadySet();
        }

        depositWhitelist = status;

        emit SetDepositWhitelist(status);
    }

    /**
     * @inheritdoc IVaultV2
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
     * @inheritdoc IVaultV2
     */
    function setIsDepositLimit(bool status) external nonReentrant onlyRole(IS_DEPOSIT_LIMIT_SET_ROLE) {
        if (isDepositLimit == status) {
            revert AlreadySet();
        }

        isDepositLimit = status;

        emit SetIsDepositLimit(status);
    }

    /**
     * @inheritdoc IVaultV2
     */
    function setDepositLimit(uint256 limit) external nonReentrant onlyRole(DEPOSIT_LIMIT_SET_ROLE) {
        if (depositLimit == limit) {
            revert AlreadySet();
        }

        depositLimit = limit;

        emit SetDepositLimit(limit);
    }

    /**
     * @inheritdoc IVaultV2
     */
    function addPlugin(address plugin) external nonReentrant onlyRole(ADD_PLUGIN_ROLE) {
        if (!IRegistry(PLUGIN_REGISTRY).isEntity(plugin)) {
            revert NotPlugin();
        }
        if (pluginActiveSince[plugin] > 0) {
            revert AlreadySet();
        }
        plugins.push(plugin);
        pluginActiveSince[plugin] = uint48(block.timestamp);

        emit AddPlugin(plugin);
    }

    /**
     * @inheritdoc IVaultV2
     */
    function removePlugin(address plugin) external nonReentrant onlyRole(REMOVE_PLUGIN_ROLE) {
        for (uint256 i; i < plugins.length; ++i) {
            if (plugins[i] == plugin) {
                if (pluginOwe[plugin] > 0) {
                    revert PluginOwe();
                }

                plugins[i] = plugins[plugins.length - 1];
                plugins.pop();
                pluginActiveSince[plugin] = 0;

                emit RemovePlugin(plugin);

                return;
            }
        }
        revert AlreadySet();
    }

    /* EXTERNAL LIQUIDITY FUNCTIONS */

    /* * PUBLIC FUNCTIONS * */

    /**
     * @inheritdoc IVaultV2
     */
    function pull(uint256 amount) external nonReentrant returns (uint256 pulled) {
        if (amount == 0) {
            revert InsufficientAmount();
        }
        if (pluginActiveSince[msg.sender] < block.timestamp) {
            revert PluginNotActive();
        }
        pulled = Math.min(amount, activeStake().saturatingSub(pluginsOwe));

        uint256 balanceBefore = IERC20(collateral).balanceOf(msg.sender);
        IERC20(collateral).safeTransfer(msg.sender, pulled);
        if (IERC20(collateral).balanceOf(msg.sender) - balanceBefore < pulled) {
            revert FeeOnTransferNotSupported();
        }

        pluginsOwe += pulled;
        pluginOwe[msg.sender] += pulled;

        emit Pull(msg.sender, pulled);
    }

    /**
     * @inheritdoc IVaultV2
     */
    function push(uint256 amount) external nonReentrant {
        if (amount == 0) {
            revert InsufficientAmount();
        }
        IERC20(collateral).safeTransferFrom(msg.sender, address(this), amount);

        pluginsOwe -= amount;
        pluginOwe[msg.sender] -= amount;

        emit Push(msg.sender, amount);
    }

    // @dev Internal dev function to handle owed slashing.
    function syncOwedSlash(uint256 amount) public nonReentrant returns (uint256 owed) {
        _pullPlugins();

        uint256 instantSlashableStake = IERC20(collateral).balanceOf(address(this)).saturatingSub(_unclaimed);
        owed = amount.saturatingSub(instantSlashableStake);
        if (owed == amount) {
            revert InsufficientAmount();
        }
        IERC20(collateral).safeTransfer(burner, amount - owed);
    }

    /* * INTERNAL FUNCTIONS * */

    function _pullPlugins() internal {
        uint256 amount = activeStake().saturatingSub(pluginsOwe);
        if (amount > 0) {
            for (uint256 i; i < plugins.length; ++i) {
                address plugin = plugins[i];
                if (pluginOwe[plugin] > 0) {
                    uint256 pullAmount = Math.min(pluginOwe[plugin], amount);
                    bool success = IBasePlugin(plugin).triggerPush(pullAmount);
                    if (success) {
                        pluginOwe[plugin] -= pullAmount;
                        pluginsOwe -= pullAmount;
                        amount -= pullAmount;
                        if (amount == 0) {
                            break;
                        }
                    }
                }
            }
        }
    }

    /* ERC20 FUNCTIONS */

    /* * INTERNAL FUNCTIONS * */

    /**
     * @inheritdoc ERC20Upgradeable
     */
    function _update(address from, address to, uint256 value) internal override {
        // _update() is called only on transfers, so from == address(0) or to == address(0) is not possible.
        uint256 fromBalance = balanceOf(from);
        if (fromBalance < value) {
            revert ERC20InsufficientBalance(from, fromBalance, value);
        }
        unchecked {
            // Overflow not possible: value <= fromBalance <= totalSupply.
            _activeSharesOf[from].push(uint48(block.timestamp), fromBalance - value);
        }

        unchecked {
            // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
            _activeSharesOf[to].push(uint48(block.timestamp), balanceOf(to) + value);
        }

        emit Transfer(from, to, value);
    }

    /* * INITIALIZE/MIGRATE FUNCTIONS * */

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

        __ERC20_init(params.name, params.symbol);
        __ERC20Permit_init(params.name);

        collateral = params.collateral;

        burner = params.burner;

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

    /**
     * @inheritdoc IVaultV2
     */
    function migrateWithdrawalsOf(address account, uint48 epoch) public {
        if (_isEpochWithdrawalsClaimed[epoch][account]) {
            revert();
        }
        uint256 shares = _epochWithdrawalSharesOf[epoch][account];
        uint48 unlockAt = _epochDurationInit + (epoch + 1) * epochDuration;
        if (unlockAt >= _withdrawalSharesCumulative.at(0)._key) {
            shares = ERC4626Math.previewRedeem(shares, _epochWithdrawals[epoch], _epochWithdrawalShares[epoch]);
        } else if (withdrawalShares[epoch] == 0) {
            withdrawals[epoch] = _epochWithdrawals[epoch];
            withdrawalShares[epoch] = _epochWithdrawalShares[epoch];
            _timeToBucket._trace._checkpoints[epoch]._key = unlockAt;
            _timeToBucket._trace._checkpoints[epoch]._value = epoch;
        }
        _withdrawalsOf[account].push(Withdrawal(false, unlockAt, shares));
        _isEpochWithdrawalsClaimed[epoch][account] = true;
    }

    function _migrate(
        uint64 oldVersion,
        uint64,
        /* newVersion */
        bytes calldata data
    )
        internal
        override
    {
        (MigrateParams memory params) = abi.decode(data, (IVaultV2.MigrateParams));
        if (oldVersion == 1) {
            __ERC20_init(params.name, params.symbol);
        }
        uint48 epoch = (block.timestamp - _epochDurationInit).toUint48() / epochDuration;
        uint256 epochWithdrawals = _epochWithdrawals[epoch];
        uint48 nextEpochStart = _epochDurationInit + (epoch + 1) * epochDuration;
        _withdrawalSharesCumulative.push(nextEpochStart, [0, epochWithdrawals]);
        epochWithdrawals += _epochWithdrawals[epoch + 1];
        _withdrawalSharesCumulative.push(nextEpochStart + epochDuration, [0, epochWithdrawals]);
        assembly ("memory-safe") {
            sstore(_timeToBucket.slot, epoch)
        }
        _timeToBucket.push(nextEpochStart, epoch);
        withdrawals[epoch] = epochWithdrawals;
        withdrawalShares[epoch] = epochWithdrawals;

        address newDelegator =
            DelegatorFactory(DELEGATOR_FACTORY).create(4, abi.encode(address(this), params.delegatorParams));
        UniversalDelegator(newDelegator).migrate();
        delegator = newDelegator;
        if (slasher != address(0)) {
            address newSlasher =
                SlasherFactory(SLASHER_FACTORY).create(2, abi.encode(address(this), params.slasherParams));
            UniversalSlasher(newSlasher).migrate();
            slasher = newSlasher;
        }
    }

    /* INTERNAL DEV FUNCTIONS */

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
}
