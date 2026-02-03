// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {DelegatorFactory} from "../DelegatorFactory.sol";
import {MigratableEntity} from "../common/MigratableEntity.sol";
import {MigratorV1V2} from "./MigratorV1V2.sol";
import {SlasherFactory} from "../SlasherFactory.sol";
import {VaultV2Storage} from "./VaultV2Storage.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";
import {ERC4626Math} from "../libraries/ERC4626Math.sol";

import {IBaseDelegator} from "../../interfaces/delegator/IBaseDelegator.sol";
import {IBasePlugin} from "../../interfaces/vault/IBasePlugin.sol";
import {IBaseSlasher} from "../../interfaces/slasher/IBaseSlasher.sol";
import {IFeeRegistry} from "../../interfaces/vault/IFeeRegistry.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {IRewards} from "../../interfaces/vault/IRewards.sol";
import {
    IVaultV2,
    DEPOSIT_WHITELIST_SET_ROLE,
    DEPOSITOR_WHITELIST_ROLE,
    IS_DEPOSIT_LIMIT_SET_ROLE,
    DEPOSIT_LIMIT_SET_ROLE,
    ADD_PLUGIN_ROLE,
    REMOVE_PLUGIN_ROLE,
    MAX_FEE,
    MAX_PLUGINS
} from "../../interfaces/vault/IVaultV2.sol";
import {IUniversalDelegator} from "../../interfaces/delegator/IUniversalDelegator.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

import {FixedPointMathLib as Math} from "@solady/src/utils/FixedPointMathLib.sol";
import {SafeCastLib as SafeCast} from "@solady/src/utils/SafeCastLib.sol";
import {SafeTransferLib as SafeERC20} from "@solady/src/utils/SafeTransferLib.sol";
import {LibCall as Address} from "@solady/src/utils/LibCall.sol";

/// @dev total supply of `collateral()` must be <= 2^255 - 1 from the VaultV2 perspective
/// @dev total supply of `collateral()` must be <= 2^128 - 1 from the UniversalDelegator perspective
contract VaultV2 is VaultV2Storage, MigratableEntity, AccessControlUpgradeable, ERC20Upgradeable, IVaultV2 {
    using Checkpoints for Checkpoints.Trace208;
    using Checkpoints for Checkpoints.Trace256;
    using Address for address;
    using Math for uint256;
    using SafeCast for uint256;
    using SafeERC20 for address;

    /* CONSTRUCTOR */

    constructor(
        address delegatorFactory,
        address slasherFactory,
        address vaultFactory,
        address rewards,
        address feeRegistry,
        address migratorV1V2
    ) VaultV2Storage(delegatorFactory, slasherFactory) MigratableEntity(vaultFactory) {
        REWARDS = rewards;
        FEE_REGISTRY = feeRegistry;
        MIGRATOR_V1V2 = migratorV1V2;
    }

    /**
     * @inheritdoc IVaultV2
     */
    function isInitialized() public view returns (bool) {
        return _isDelegatorInitialized && _isSlasherInitialized;
    }

    /* ACCOUNTING FUNCTIONS */

    /* * PUBLIC FUNCTIONS * */

    /**
     * @inheritdoc IVaultV2
     */
    function totalStake() public view returns (uint256) {
        unchecked {
            return activeStake() + activeWithdrawals();
        }
    }

    /**
     * @inheritdoc IVaultV2
     */
    function activeWithdrawalsForAt(uint48 duration, uint48 timestamp, bytes memory hints)
        public
        view
        returns (uint256)
    {
        // forgefmt: disable-start 
        bytes memory unlockToBucketHint; bytes memory withdrawalSharesHint; bytes memory withdrawalSharesCumulativeHintNew; bytes memory withdrawalSharesCumulativeHintOld; bytes memory withdrawalsHint;
        if (hints.length > 0) {
            (unlockToBucketHint, withdrawalSharesHint, withdrawalSharesCumulativeHintNew, withdrawalSharesCumulativeHintOld, withdrawalsHint) = abi.decode(hints, (bytes, bytes, bytes, bytes, bytes));
        }
        // forgefmt: disable-end 
        uint208 lastBucket = _unlockToBucket.upperLookupRecent(timestamp, unlockToBucketHint);
        uint256 lastWithdrawalShares = _withdrawalShares[lastBucket].upperLookupRecent(timestamp, withdrawalSharesHint);
        return lastWithdrawalShares > 0
            ? (_withdrawalSharesCumulative.upperLookupRecent(
                        timestamp + epochDuration, withdrawalSharesCumulativeHintNew
                    )
                    - _withdrawalSharesCumulative.upperLookupRecent(
                        timestamp + duration, withdrawalSharesCumulativeHintOld
                    ))
            .fullMulDivUnchecked(
                _withdrawals[lastBucket].upperLookupRecent(timestamp, withdrawalsHint), lastWithdrawalShares
            )
            : 0;
    }

    /**
     * @inheritdoc IVaultV2
     */
    function activeWithdrawalsFor(uint48 duration, bytes memory hint) public view returns (uint256) {
        uint208 lastBucket = _unlockToBucket.latest();
        uint256 lastWithdrawalShares = _withdrawalShares[lastBucket].latest();
        return lastWithdrawalShares > 0
            ? (_withdrawalSharesCumulative.latest()
                    - _withdrawalSharesCumulative.upperLookupRecent(uint48(block.timestamp) + duration, hint))
            .fullMulDivUnchecked(_withdrawals[lastBucket].latest(), lastWithdrawalShares)
            : 0;
    }

    /**
     * @inheritdoc IVaultV2
     */
    function activeWithdrawalsAt(uint48 timestamp, bytes memory hints) public view returns (uint256) {
        return activeWithdrawalsForAt(0, timestamp, hints);
    }

    /**
     * @inheritdoc IVaultV2
     */
    function activeWithdrawals() public view returns (uint256) {
        return activeWithdrawalsFor(0, "");
    }

    /**
     * @inheritdoc IVaultV2
     */
    function activeBalanceOfAt(address account, uint48 timestamp, bytes memory hints) public view returns (uint256) {
        // forgefmt: disable-start 
        bytes memory activeSharesOfHint; bytes memory activeStakeHint; bytes memory activeSharesHint;
        if (hints.length > 0) {
            (activeSharesOfHint, activeStakeHint, activeSharesHint) = abi.decode(hints, (bytes, bytes, bytes));
        }
        // forgefmt: disable-end 
        return ERC4626Math.previewRedeem(
            activeSharesOfAt(account, timestamp, activeSharesOfHint),
            activeStakeAt(timestamp, activeStakeHint),
            activeSharesAt(timestamp, activeSharesHint)
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
        uint256 bucketIndex = _unlockToBucket.upperLookupRecent(withdrawalUnlockAfter(index, account));
        return ERC4626Math.previewRedeem(
            withdrawalSharesOf(index, account),
            _withdrawals[bucketIndex].latest(),
            _withdrawalShares[bucketIndex].latest()
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
    function flashFee(address token, uint256 amount) public view returns (uint256) {
        if (token != collateral) {
            revert UnsupportedToken();
        }
        return amount.mulDivUp(IFeeRegistry(FEE_REGISTRY).getFlashloanFee(address(this)), MAX_FEE);
    }

    /**
     * @inheritdoc IVaultV2
     */
    function pullable() public view returns (uint256) {
        return totalStake().saturatingSub(IUniversalDelegator(delegator).getNoPluginsSize()).saturatingSub(pluginsOwe);
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
        unchecked {
            if (onBehalfOf == address(0)) {
                revert InvalidOnBehalfOf();
            }

            if (depositWhitelist && !isDepositorWhitelisted[msg.sender]) {
                revert NotWhitelistedDepositor();
            }

            uint256 balanceBefore = IERC20(collateral).balanceOf(address(this));
            collateral.safeTransferFrom(msg.sender, address(this), amount);
            depositedAmount = IERC20(collateral).balanceOf(address(this)) - balanceBefore;

            _revertIfZero(depositedAmount);

            if (isDepositLimit && activeStake() + depositedAmount > depositLimit) {
                revert DepositLimitReached();
            }

            uint256 activeStake_ = activeStake();
            uint256 activeShares_ = activeShares();

            mintedShares = ERC4626Math.previewDeposit(depositedAmount, activeShares_, activeStake_);

            _activeStake.push(uint48(block.timestamp), activeStake_ + depositedAmount);
            _activeShares.push(uint48(block.timestamp), activeShares_ + mintedShares);
            require(_activeShares.latest() >= mintedShares);
            _activeSharesOf[onBehalfOf].push(uint48(block.timestamp), activeSharesOf(onBehalfOf) + mintedShares);

            emit Deposit(msg.sender, onBehalfOf, depositedAmount, mintedShares);
            emit Transfer(address(0), onBehalfOf, mintedShares);
        }
    }

    /**
     * @inheritdoc IVaultV2
     */
    function withdraw(address claimer, uint256 amount)
        public
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
        public
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
    function instantWithdraw(address recipient, uint256 amount) public returns (uint256 burnedShares) {
        unchecked {
            _revertIfZero(amount);

            uint256 activeStake_ = activeStake();
            uint256 activeShares_ = activeShares();
            uint256 activeSharesOf_ = activeSharesOf(msg.sender);

            burnedShares = ERC4626Math.previewWithdraw(amount, activeShares_, activeStake_);
            if (burnedShares > activeSharesOf_) {
                revert TooMuchWithdraw();
            }

            _activeSharesOf[msg.sender].push(uint48(block.timestamp), activeSharesOf_ - burnedShares);
            _activeShares.push(uint48(block.timestamp), activeShares_ - burnedShares);
            _activeStake.push(uint48(block.timestamp), activeStake_ - amount);

            collateral.safeTransfer(recipient, amount);

            emit InstantWithdraw(msg.sender, amount);
        }
    }

    /**
     * @inheritdoc IVaultV2
     */
    function claim(address recipient, uint256 index) public nonReentrant returns (uint256 amount) {
        unchecked {
            if (recipient == address(0)) {
                revert InvalidRecipient();
            }

            _pullPlugins();

            Withdrawal storage withdrawal = _withdrawalsOf[msg.sender][index];
            if (withdrawal.claimed) {
                revert AlreadyClaimed();
            }
            if (withdrawal.unlockAfter >= block.timestamp) {
                revert WithdrawalNotMatured();
            }
            amount = withdrawalsOf(index, msg.sender);
            if (amount == 0) {
                revert InsufficientClaim();
            }
            withdrawal.claimed = true;
            _unclaimedRaw -= int256(amount);

            collateral.safeTransfer(recipient, amount);

            emit Claim(msg.sender, recipient, index, amount);
        }
    }

    /**
     * @inheritdoc IVaultV2
     */
    function claimBatch(address recipient, uint256[] calldata indexes) public returns (uint256 amount) {
        unchecked {
            for (uint256 i; i < indexes.length; ++i) {
                amount += claim(recipient, indexes[i]);
            }
        }
    }

    function donate(uint256 amount) public nonReentrant {
        unchecked {
            uint256 balanceBefore = IERC20(collateral).balanceOf(address(this));
            collateral.safeTransferFrom(msg.sender, address(this), amount);
            amount = IERC20(collateral).balanceOf(address(this)) - balanceBefore;

            _revertIfZero(amount);

            uint256 activeStake_ = activeStake();
            uint256 withdrawals_ = activeWithdrawals();

            uint256 withdrawalsAmount = amount.mulDiv(withdrawals_, activeStake_ + withdrawals_);
            _withdrawals[_unlockToBucket.latest()].push(
                uint48(block.timestamp), _withdrawals[_unlockToBucket.latest()].latest() + withdrawalsAmount
            );
            _activeStake.push(uint48(block.timestamp), amount - withdrawalsAmount + activeStake_);

            emit Donate(amount);
        }
    }

    // @dev Internal dev function to handle slashing.
    function onSlash(uint256 amount, bytes calldata hints)
        public
        nonReentrant
        returns (uint256 slashedAmount, uint256 owed)
    {
        unchecked {
            if (slasher != msg.sender) {
                revert NotSlasher();
            }

            uint208 lastBucket = _unlockToBucket.latest();
            uint256 lastWithdrawals = _withdrawals[lastBucket].latest();
            uint256 lastWithdrawalShares = _withdrawalShares[lastBucket].latest();
            uint256 unmaturedWithdrawalShares = _withdrawalSharesCumulative.latest()
                - _withdrawalSharesCumulative.upperLookupRecent(uint48(block.timestamp), hints);
            uint256 unmaturedWithdrawals = lastWithdrawalShares > 0
                ? unmaturedWithdrawalShares.fullMulDivUnchecked(lastWithdrawals, lastWithdrawalShares)
                : 0;
            uint256 maturedWithdrawals = lastWithdrawals - unmaturedWithdrawals;

            uint256 activeStake_ = activeStake();
            uint256 slashableStake = activeStake_ + unmaturedWithdrawals;

            slashedAmount = Math.min(amount, slashableStake);
            if (slashedAmount > 0) {
                _unlockToBucket.push(uint48(block.timestamp), lastBucket + 1);
                _withdrawals[lastBucket].push(uint48(block.timestamp), maturedWithdrawals);
                _withdrawalShares[lastBucket].push(
                    uint48(block.timestamp), lastWithdrawalShares - unmaturedWithdrawalShares
                );
                _withdrawalShares[lastBucket + 1].push(uint48(block.timestamp), unmaturedWithdrawalShares);
                _unclaimedRaw += int256(maturedWithdrawals);

                uint256 activeSlashed = slashedAmount.mulDiv(activeStake_, slashableStake);
                _activeStake.push(uint48(block.timestamp), activeStake_ - activeSlashed);
                _withdrawals[lastBucket
                        + 1].push(uint48(block.timestamp), unmaturedWithdrawals - (slashedAmount - activeSlashed));

                uint256 available = IERC20(collateral).balanceOf(address(this)).saturatingSub(uint256(_unclaimedRaw));
                if (available < slashedAmount) {
                    _pullPlugins();
                    available = IERC20(collateral).balanceOf(address(this)).saturatingSub(uint256(_unclaimedRaw));
                }
                owed = slashedAmount.saturatingSub(available);

                if (owed < slashedAmount) {
                    collateral.safeTransfer(burner, slashedAmount - owed);
                }
            }
        }

        emit OnSlash(amount, slashedAmount);
    }

    /* * INTERNAL FUNCTIONS * */

    function _withdraw(address claimer, uint256 withdrawnAssets, uint256 burnedShares)
        internal
        virtual
        returns (uint256 mintedShares)
    {
        unchecked {
            _activeSharesOf[msg.sender].push(uint48(block.timestamp), activeSharesOf(msg.sender) - burnedShares);
            _activeShares.push(uint48(block.timestamp), activeShares() - burnedShares);
            _activeStake.push(uint48(block.timestamp), activeStake() - withdrawnAssets);

            uint256 lastBucket = _unlockToBucket.latest();
            mintedShares = ERC4626Math.previewDeposit(
                withdrawnAssets, _withdrawalShares[lastBucket].latest(), _withdrawals[lastBucket].latest()
            );

            _withdrawals[lastBucket].push(uint48(block.timestamp), _withdrawals[lastBucket].latest() + withdrawnAssets);
            _withdrawalShares[lastBucket].push(
                uint48(block.timestamp), _withdrawalShares[lastBucket].latest() + mintedShares
            );
            require(_withdrawalShares[lastBucket].latest() >= mintedShares);
            uint48 unlockAfter = uint48(block.timestamp) + epochDuration;
            require(unlockAfter >= block.timestamp);
            _withdrawalsOf[claimer].push(Withdrawal(false, unlockAfter, mintedShares));
            _withdrawalSharesCumulative.push(unlockAfter, _withdrawalSharesCumulative.latest() + mintedShares);

            _pullPlugins();

            emit Withdraw(msg.sender, claimer, withdrawnAssets, burnedShares, mintedShares);
            emit Transfer(msg.sender, address(0), burnedShares);
        }
    }

    /* OWNER FUNCTIONS */

    /* * PUBLIC FUNCTIONS * */

    /**
     * @inheritdoc IVaultV2
     */
    function setDepositWhitelist(bool status) public nonReentrant onlyRole(DEPOSIT_WHITELIST_SET_ROLE) {
        depositWhitelist = status;
        emit SetDepositWhitelist(status);
    }

    /**
     * @inheritdoc IVaultV2
     */
    function setDepositorWhitelistStatus(address account, bool status)
        public
        nonReentrant
        onlyRole(DEPOSITOR_WHITELIST_ROLE)
    {
        if (account == address(0)) {
            revert InvalidAccount();
        }
        isDepositorWhitelisted[account] = status;
        emit SetDepositorWhitelistStatus(account, status);
    }

    /**
     * @inheritdoc IVaultV2
     */
    function setIsDepositLimit(bool status) public nonReentrant onlyRole(IS_DEPOSIT_LIMIT_SET_ROLE) {
        isDepositLimit = status;
        emit SetIsDepositLimit(status);
    }

    /**
     * @inheritdoc IVaultV2
     */
    function setDepositLimit(uint256 limit) public nonReentrant onlyRole(DEPOSIT_LIMIT_SET_ROLE) {
        depositLimit = limit;
        emit SetDepositLimit(limit);
    }

    /**
     * @inheritdoc IVaultV2
     */
    function addPlugin(address plugin) public nonReentrant onlyRole(ADD_PLUGIN_ROLE) {
        if (pluginActiveSince[plugin] > 0) {
            revert AlreadySet();
        }
        unchecked {
            if (plugins.length + 1 >= MAX_PLUGINS) {
                revert TooManyPlugins();
            }
        }
        plugins.push(plugin);
        pluginActiveSince[plugin] = uint48(block.timestamp) + pluginActiveDelay;

        emit AddPlugin(plugin);
    }

    /**
     * @inheritdoc IVaultV2
     */
    function removePlugin(address plugin) public nonReentrant onlyRole(REMOVE_PLUGIN_ROLE) {
        unchecked {
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
    }

    /**
     * @inheritdoc IVaultV2
     */
    function flashLoan(address token, uint256 amount, bytes memory data) external nonReentrant {
        _revertIfZero(amount);
        uint256 fee = flashFee(token, amount);
        address collateral_ = collateral;
        uint256 balanceBefore = IERC20(collateral_).balanceOf(address(this));

        collateral_.safeTransfer(msg.sender, amount);

        IERC3156FlashBorrower(msg.sender).onFlashLoan(msg.sender, token, amount, fee, data);

        collateral_.safeTransferFrom(msg.sender, address(this), amount + fee);

        uint256 actualFee = IERC20(collateral_).balanceOf(address(this)) - balanceBefore;
        if (actualFee < fee) {
            revert InvalidReturnAmount();
        }

        if (actualFee > 0) {
            collateral.safeApprove(REWARDS, actualFee);
            IRewards(REWARDS).distributeDonationRewards(address(this), actualFee);
        }
    }

    /* EXTERNAL LIQUIDITY FUNCTIONS */

    /* * PUBLIC FUNCTIONS * */

    /**
     * @inheritdoc IVaultV2
     */
    function pull(uint256 amount) public nonReentrant returns (uint256 pulled) {
        unchecked {
            _revertIfZero(amount);
            if (pluginActiveSince[msg.sender] < block.timestamp) {
                revert PluginNotActive();
            }
            pulled = Math.min(amount, pullable());

            pluginsOwe += pulled;
            pluginOwe[msg.sender] += pulled;

            uint256 balanceBefore = IERC20(collateral).balanceOf(msg.sender);
            collateral.safeTransfer(msg.sender, pulled);
            if (IERC20(collateral).balanceOf(msg.sender) - balanceBefore < pulled) {
                revert FeeOnTransferNotSupported();
            }

            emit Pull(msg.sender, pulled);
        }
    }

    /**
     * @inheritdoc IVaultV2
     */
    function push(uint256 amount) public nonReentrant {
        _revertIfZero(amount);
        collateral.safeTransferFrom(msg.sender, address(this), amount);

        pluginOwe[msg.sender] -= amount;
        unchecked {
            pluginsOwe -= amount;
        }

        emit Push(msg.sender, amount);
    }

    // @dev Internal dev function to handle owed slashing.
    function syncOwedSlash(uint256 amount) public nonReentrant returns (uint256 slashed) {
        unchecked {
            if (slasher != msg.sender) {
                revert NotSlasher();
            }

            _pullPlugins();

            // use only unclaimable (either active stake or active withdrawals) funds for slashing
            slashed = Math.min(
                amount,
                IERC20(collateral).balanceOf(address(this))
                    .saturatingSub(
                        uint256(
                            _unclaimedRaw
                                + int256(_withdrawals[_unlockToBucket.latest()].latest() - activeWithdrawals())
                        )
                    )
            );
            _revertIfZero(slashed);
            collateral.safeTransfer(burner, slashed);

            emit SyncOwedSlash(slashed);
        }
    }

    /* * INTERNAL FUNCTIONS * */

    /// @dev first plugins in the list are pulled first
    function _pullPlugins() internal {
        unchecked {
            uint256 toPull = pluginsOwe.saturatingSub(totalStake());
            if (toPull > 0) {
                for (uint256 i; i < plugins.length; ++i) {
                    address plugin = plugins[i];
                    uint256 pluginOwe_ = pluginOwe[plugin];
                    if (pluginOwe_ > 0) {
                        uint256 pulled = IBasePlugin(plugin).pull(Math.min(pluginOwe_, toPull));
                        if (pulled > 0) {
                            pluginOwe[plugin] = pluginOwe_ - pulled;
                            pluginsOwe -= pulled;
                            toPull -= pulled;
                            if (toPull == 0) {
                                break;
                            }
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
        _activeSharesOf[from].push(uint48(block.timestamp), balanceOf(from) - value);
        unchecked {
            _activeSharesOf[to].push(uint48(block.timestamp), balanceOf(to) + value);
        }

        emit Transfer(from, to, value);
    }

    /* * INITIALIZE FUNCTIONS * */

    function _initialize(uint64, address, bytes memory data) internal virtual override {
        InitParams memory params = abi.decode(data, (InitParams));

        if (params.collateral == address(0)) {
            revert InvalidCollateral();
        }

        if (params.epochDuration == 0) {
            revert InvalidEpochDuration();
        }

        if (params.pluginActiveDelay <= params.epochDuration) {
            revert InvalidPluginActiveDelay();
        }

        __ERC20_init(params.name, params.symbol);

        collateral = params.collateral;

        burner = params.burner;

        epochDuration = params.epochDuration;

        depositWhitelist = params.depositWhitelist;

        isDepositLimit = params.isDepositLimit;
        depositLimit = params.depositLimit;

        pluginActiveDelay = params.pluginActiveDelay;

        _grantRoleIfNotZero(DEFAULT_ADMIN_ROLE, params.defaultAdminRoleHolder);
        _grantRoleIfNotZero(DEPOSIT_WHITELIST_SET_ROLE, params.depositWhitelistSetRoleHolder);
        _grantRoleIfNotZero(DEPOSITOR_WHITELIST_ROLE, params.depositorWhitelistRoleHolder);
        _grantRoleIfNotZero(IS_DEPOSIT_LIMIT_SET_ROLE, params.isDepositLimitSetRoleHolder);
        _grantRoleIfNotZero(DEPOSIT_LIMIT_SET_ROLE, params.depositLimitSetRoleHolder);
        _grantRoleIfNotZero(ADD_PLUGIN_ROLE, params.addPluginRoleHolder);
        _grantRoleIfNotZero(REMOVE_PLUGIN_ROLE, params.removePluginRoleHolder);

        for (uint256 i; i < params.plugins.length; ++i) {
            address plugin = params.plugins[i];
            if (pluginActiveSince[plugin] > 0) {
                revert PluginAlreadyAdded();
            }
            plugins.push(plugin);
            pluginActiveSince[plugin] = uint48(block.timestamp);
        }

        emit Initialize(params);
    }

    /* INTERNAL HELPERS */

    // TODO: remove second if enough bytecode
    function _revertIfZero(uint256 amount) internal pure {
        if (amount == 0) {
            revert InsufficientAmount();
        }
    }

    // TODO: remove first if enough bytecode
    function _grantRoleIfNotZero(bytes32 role, address holder) internal {
        if (holder != address(0)) {
            _grantRole(role, holder);
        }
    }

    /* INTERNAL DEV FUNCTIONS */

    function setDelegator(address delegator_) public nonReentrant {
        if (_isDelegatorInitialized) {
            revert DelegatorAlreadyInitialized();
        }

        if (!IRegistry(DELEGATOR_FACTORY).isEntity(delegator_)) {
            revert NotDelegator();
        }

        if (IBaseDelegator(delegator_).vault() != address(this)) {
            revert InvalidDelegator();
        }

        delegator = delegator_;

        _isDelegatorInitialized = true;

        emit SetDelegator(delegator_);
    }

    function setSlasher(address slasher_) public nonReentrant {
        if (_isSlasherInitialized) {
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

        _isSlasherInitialized = true;

        emit SetSlasher(slasher_);
    }

    /* MIGRATE FUNCTIONS */

    /**
     * @inheritdoc IVaultV2
     */
    function migrateWithdrawalOf(address account, uint48 epoch) public {
        MIGRATOR_V1V2.delegateCallContract(abi.encodeCall(MigratorV1V2.migrateWithdrawalOf, (account, epoch)));
    }

    function _migrate(uint64 oldVersion, uint64, bytes calldata data) internal override {
        MIGRATOR_V1V2.delegateCallContract(abi.encodeCall(MigratorV1V2.migrate, (oldVersion, data)));
    }
}
