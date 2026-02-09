// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {DelegatorFactory} from "../DelegatorFactory.sol";
import {MigratableEntity} from "../common/MigratableEntity.sol";
import {MigratorV1V2} from "./MigratorV1V2.sol";
import {SlasherFactory} from "../SlasherFactory.sol";
import {VaultV2Storage} from "./VaultV2Storage.sol";

import {Checkpoints as CheckpointsLegacy} from "../libraries/Checkpoints.sol";
import {Checkpoints as Checkpoints} from "../libraries/CheckpointsV2.sol";
import {ERC4626Math} from "../libraries/ERC4626MathV2.sol";

import {IBaseDelegator} from "../../interfaces/delegator/IBaseDelegator.sol";
import {IBaseSlasher} from "../../interfaces/slasher/IBaseSlasher.sol";
import {IPluginBase} from "../../interfaces/vault/IPluginBase.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {IUniversalDelegator} from "../../interfaces/delegator/IUniversalDelegator.sol";
import {
    IVaultV2,
    DEPOSIT_WHITELIST_SET_ROLE,
    DEPOSITOR_WHITELIST_ROLE,
    IS_DEPOSIT_LIMIT_SET_ROLE,
    DEPOSIT_LIMIT_SET_ROLE,
    SET_PLUGIN_LIMIT_ROLE,
    SWAP_PLUGINS_ROLE,
    ALLOCATE_PLUGIN_ROLE,
    DEALLOCATE_PLUGIN_ROLE,
    MAX_PLUGINS
} from "../../interfaces/vault/IVaultV2.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {FixedPointMathLib as Math} from "@solady/src/utils/FixedPointMathLib.sol";
import {LibCall as Address} from "@solady/src/utils/LibCall.sol";
import {SafeTransferLib as SafeERC20} from "@solady/src/utils/SafeTransferLib.sol";

/// @dev total supply of `collateral()` must be <= 2^255 - 1 from the VaultV2 perspective
/// @dev total supply of `collateral()` must be <= 2^128 - 1 from the UniversalDelegator perspective
contract VaultV2 is VaultV2Storage, MigratableEntity, AccessControlUpgradeable, ERC20Upgradeable, IVaultV2 {
    using CheckpointsLegacy for CheckpointsLegacy.Trace208;
    using CheckpointsLegacy for CheckpointsLegacy.Trace256;
    using Checkpoints for Checkpoints.Trace208;
    using Checkpoints for Checkpoints.Trace256;
    using Address for address;
    using Math for uint256;
    using SafeERC20 for address;

    modifier withDeallocatePlugins(bool withPlugins) {
        if (withPlugins) {
            deallocatePlugins();
        }
        _;
    }

    modifier withSkimPlugins() {
        skimPlugins();
        _;
    }

    /* CONSTRUCTOR */

    constructor(
        address delegatorFactory,
        address slasherFactory,
        address vaultFactory,
        address rewards,
        address migratorV1V2
    ) VaultV2Storage(delegatorFactory, slasherFactory) MigratableEntity(vaultFactory) {
        REWARDS = rewards;
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
        uint208 withdrawalBucket_ = _unlockToBucket.upperLookupRecent(timestamp, unlockToBucketHint);
        uint256 withdrawalShares_ =
            _withdrawalShares[withdrawalBucket_].upperLookupRecent(timestamp, withdrawalSharesHint);
        return withdrawalShares_ > 0
            ? (_withdrawalSharesCumulative.upperLookupRecent(
                        timestamp + epochDuration, withdrawalSharesCumulativeHintNew
                    )
                    - _withdrawalSharesCumulative.upperLookupRecent(
                        timestamp + duration, withdrawalSharesCumulativeHintOld
                    ))
            .fullMulDiv(
                _withdrawals[withdrawalBucket_].upperLookupRecent(timestamp, withdrawalsHint), withdrawalShares_
            )
            : 0;
    }

    /**
     * @inheritdoc IVaultV2
     */
    function activeWithdrawalsFor(uint48 duration, bytes memory hint) public view returns (uint256) {
        uint208 withdrawalBucket_ = withdrawalBucket();
        uint256 withdrawalShares_ = withdrawalShares(withdrawalBucket_);
        return withdrawalShares_ > 0
            ? (_withdrawalSharesCumulative.latest()
                    - _withdrawalSharesCumulative.upperLookupRecent(uint48(block.timestamp) + duration, hint))
            .fullMulDiv(withdrawals(withdrawalBucket_), withdrawalShares_)
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
            withdrawalSharesOf(index, account), withdrawals(bucketIndex), withdrawalShares(bucketIndex)
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
    function allocatable() public view returns (uint256) {
        return
            totalStake().saturatingSub(IUniversalDelegator(delegator).getNoPluginsSize())
                .saturatingSub(pluginsAllocated);
    }

    /**
     * @inheritdoc IVaultV2
     */
    function deposit(address onBehalfOf, uint256 amount)
        public
        withSkimPlugins
        nonReentrant
        returns (uint256 depositedAmount, uint256 mintedShares)
    {
        unchecked {
            _revertIfZero(onBehalfOf);
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
            require(activeShares() >= mintedShares);
            _activeSharesOf[onBehalfOf].push(uint48(block.timestamp), activeSharesOf(onBehalfOf) + mintedShares);

            emit Deposit(msg.sender, onBehalfOf, depositedAmount, mintedShares);
            emit Transfer(address(0), onBehalfOf, mintedShares);

            // allocate only non-fee-on-transfer tokens
            if (depositedAmount == amount && plugins.length > 0) {
                _allocatePlugin(plugins[0], depositedAmount);
            }
        }
    }

    /**
     * @inheritdoc IVaultV2
     */
    function withdraw(address claimer, uint256 amount)
        public
        withSkimPlugins
        nonReentrant
        returns (uint256 burnedShares, uint256 mintedShares)
    {
        unchecked {

            _revertIfZero(claimer);
            _revertIfZero(amount);

            burnedShares = ERC4626Math.previewWithdraw(amount, activeShares(), activeStake());
            if (burnedShares > activeSharesOf(msg.sender)) {
                revert TooMuchWithdraw();
            }
            mintedShares = _withdraw(claimer, amount, burnedShares);
        }
    }

    /**
     * @inheritdoc IVaultV2
     */
    function redeem(address claimer, uint256 shares)
        public
        withSkimPlugins
        nonReentrant
        returns (uint256 withdrawnAssets, uint256 mintedShares)
    {
        unchecked {
            _revertIfZero(claimer);
            if (shares > activeSharesOf(msg.sender)) {
                revert TooMuchRedeem();
            }

            withdrawnAssets = ERC4626Math.previewRedeem(shares, activeStake(), activeShares());
            _revertIfZero(withdrawnAssets);
            mintedShares = _withdraw(claimer, withdrawnAssets, shares);
        }
    }

    /**
     * @inheritdoc IVaultV2
     */
    function instantWithdraw(address recipient, uint256 amount)
        public
        returns (uint256 withdrawnAssets, uint256 burnedShares)
    {
        unchecked {
            withdrawnAssets = Math.min(amount, IUniversalDelegator(delegator).getWithdrawalBuffer());

            _revertIfZero(withdrawnAssets);

            uint256 activeStake_ = activeStake();
            uint256 activeShares_ = activeShares();
            uint256 activeSharesOf_ = activeSharesOf(msg.sender);

            burnedShares = ERC4626Math.previewWithdraw(withdrawnAssets, activeShares_, activeStake_);
            if (burnedShares > activeSharesOf_) {
                revert TooMuchWithdraw();
            }

            _activeSharesOf[msg.sender].push(uint48(block.timestamp), activeSharesOf_ - burnedShares);
            _activeStake.push(uint48(block.timestamp), activeStake_ - withdrawnAssets);
            _activeShares.push(uint48(block.timestamp), activeShares_ - burnedShares);

            collateral.safeTransfer(recipient, withdrawnAssets);

            emit InstantWithdraw(msg.sender, withdrawnAssets);
        }
    }

    /**
     * @inheritdoc IVaultV2
     */
    function claim(address recipient, uint256 index)
        public
        withDeallocatePlugins(true)
        nonReentrant
        returns (uint256 amount)
    {
        unchecked {
            _revertIfZero(recipient);

            Withdrawal storage withdrawal = _withdrawalsOf[msg.sender][index];
            if (withdrawal.claimed) {
                revert AlreadyClaimed();
            }
            if (withdrawal.unlockAfter >= block.timestamp) {
                revert WithdrawalNotMatured();
            }
            amount = withdrawalsOf(index, msg.sender);
            _revertIfZero(amount);
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
            uint256 withdrawalBucket_ = withdrawalBucket();
            uint256 withdrawalsAmount = amount.mulDiv(withdrawals_, activeStake_ + withdrawals_);
            _withdrawals[withdrawalBucket_].push(
                uint48(block.timestamp), withdrawals(withdrawalBucket_) + withdrawalsAmount
            );
            _activeStake.push(uint48(block.timestamp), amount - withdrawalsAmount + activeStake_);

            emit Donate(amount);
        }
    }

    // @dev Internal dev function to handle slashing.
    function onSlash(uint256 amount, bool withPlugins, bytes calldata hint)
        public
        withDeallocatePlugins(withPlugins)
        nonReentrant
        returns (uint256 slashedAmount, uint256 owed)
    {
        unchecked {
            if (slasher != msg.sender) {
                revert NotSlasher();
            }

            uint256 activeStake_ = activeStake();
            uint208 withdrawalBucket_ = withdrawalBucket();
            uint256 activeWithdrawalShares = _withdrawalSharesCumulative.latest()
                - _withdrawalSharesCumulative.upperLookupRecent(uint48(block.timestamp), hint);
            uint256 activeWithdrawals_ = activeWithdrawals();
            uint256 claimableWithdrawals = withdrawals(withdrawalBucket_) - activeWithdrawals();
            uint256 slashableStake = activeStake_ + activeWithdrawals_;

            slashedAmount = Math.min(amount, slashableStake);
            if (slashedAmount > 0) {
                _unlockToBucket.push(uint48(block.timestamp), withdrawalBucket_ + 1);
                _withdrawals[withdrawalBucket_].push(uint48(block.timestamp), claimableWithdrawals);
                _withdrawalShares[withdrawalBucket_].push(
                    uint48(block.timestamp), withdrawalShares(withdrawalBucket_) - activeWithdrawalShares
                );
                _withdrawalShares[withdrawalBucket_ + 1].push(uint48(block.timestamp), activeWithdrawalShares);
                _unclaimedRaw += int256(claimableWithdrawals);

                uint256 activeSlashed = slashedAmount.mulDiv(activeStake_, slashableStake);
                _activeStake.push(uint48(block.timestamp), activeStake_ - activeSlashed);
                _withdrawals[withdrawalBucket_
                        + 1].push(uint48(block.timestamp), activeWithdrawals_ - (slashedAmount - activeSlashed));

                owed = slashedAmount.saturatingSub(_availableToSlash());

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

            uint208 withdrawalBucket_ = withdrawalBucket();
            uint256 withdrawals_ = withdrawals(withdrawalBucket_);
            uint256 withdrawalShares_ = withdrawalShares(withdrawalBucket_);
            mintedShares = ERC4626Math.previewDeposit(withdrawnAssets, withdrawalShares_, withdrawals_);

            _withdrawals[withdrawalBucket_].push(uint48(block.timestamp), withdrawals_ + withdrawnAssets);
            _withdrawalShares[withdrawalBucket_].push(uint48(block.timestamp), withdrawalShares_ + mintedShares);
            require(withdrawalShares(withdrawalBucket_) >= mintedShares);

            uint48 unlockAfter = uint48(block.timestamp) + epochDuration;
            require(unlockAfter >= block.timestamp);
            _withdrawalsOf[claimer].push(Withdrawal({claimed: false, unlockAfter: unlockAfter, shares: mintedShares}));
            _withdrawalSharesCumulative.push(unlockAfter, _withdrawalSharesCumulative.latest() + mintedShares);

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

    /* EXTERNAL LIQUIDITY FUNCTIONS */

    /* * PUBLIC FUNCTIONS * */

    /**
     * @inheritdoc IVaultV2
     */
    function setPluginLimit(address plugin, uint208 newLimit) public nonReentrant onlyRole(SET_PLUGIN_LIMIT_ROLE) {
        _revertIfZero(plugin);

        if (pluginAllocated[plugin] > newLimit) {
            revert PluginAllocated();
        }

        uint256 nPlugins = plugins.length;
        if (newLimit > 0) {
            uint256 i;
            for (; i < nPlugins; ++i) {
                if (plugins[i] == plugin) {
                    break;
                }
            }
            if (i == nPlugins) {
                plugins.push(plugin);
                if (plugins.length > MAX_PLUGINS) {
                    revert TooManyPlugins();
                }
                _grantRole(ALLOCATE_PLUGIN_ROLE, plugin);
                _grantRole(DEALLOCATE_PLUGIN_ROLE, plugin);
            }
        } else {
            for (uint256 i; i < nPlugins; ++i) {
                if (plugins[i] == plugin) {
                    plugins[i] = plugins[nPlugins - 1];
                    plugins.pop();
                    break;
                }
            }
        }
        pluginLimit[plugin] = newLimit;

        emit SetPluginLimit(plugin, newLimit);
    }

    /**
     * @inheritdoc IVaultV2
     */
    function swapPlugins(address plugin1, address plugin2) public nonReentrant onlyRole(SWAP_PLUGINS_ROLE) {
        uint256 index1 = type(uint256).max;
        uint256 index2 = type(uint256).max;
        uint256 nPlugins = plugins.length;
        for (uint256 i; i < nPlugins; ++i) {
            if (plugins[i] == plugin1) {
                index1 = i;
            } else if (plugins[i] == plugin2) {
                index2 = i;
            }
        }
        (plugins[index1], plugins[index2]) = (plugins[index2], plugins[index1]);

        emit SwapPlugins(plugin1, plugin2);
    }

    /**
     * @inheritdoc IVaultV2
     */
    function allocatePlugin(address plugin, uint256 amount)
        public
        nonReentrant
        onlyRole(ALLOCATE_PLUGIN_ROLE)
        returns (uint256 allocated)
    {
        return _allocatePlugin(plugin, amount);
    }

    function _allocatePlugin(address plugin, uint256 amount) internal returns (uint256 allocated) {
        unchecked {
            allocated = Math.min(
                Math.min(Math.min(amount, pluginLimit[plugin]), allocatable()), IPluginBase(plugin).allocatable()
            );

            if (allocated > 0) {
                pluginsAllocated += allocated;
                pluginAllocated[plugin] += allocated;

                uint256 balanceBefore = IERC20(collateral).balanceOf(plugin);
                collateral.safeTransfer(plugin, allocated);
                if (IERC20(collateral).balanceOf(plugin) - balanceBefore < allocated) {
                    revert FeeOnTransferNotSupported();
                }
                IPluginBase(plugin).allocate(allocated);
            }

            emit Allocate(plugin, allocated);
        }
    }

    /**
     * @inheritdoc IVaultV2
     */
    function deallocatePlugin(address plugin, uint256 amount)
        public
        nonReentrant
        onlyRole(DEALLOCATE_PLUGIN_ROLE)
        returns (uint256)
    {
        return _deallocatePlugin(plugin, amount);
    }

    function _deallocatePlugin(address plugin, uint256 amount) internal returns (uint256 deallocated) {
        deallocated = IPluginBase(plugin).deallocate(amount);
        if (deallocated > 0) {
            collateral.safeTransferFrom(plugin, address(this), deallocated);

            pluginAllocated[plugin] -= deallocated;
            unchecked {
                pluginsAllocated -= deallocated;
            }
        }

        emit Deallocate(plugin, deallocated);
    }

    // @dev Internal dev function to handle owed slashing.
    function syncOwedSlash(uint256 amount) public nonReentrant returns (uint256 slashed) {
        unchecked {
            if (slasher != msg.sender) {
                revert NotSlasher();
            }

            // use only unclaimable (either active stake or active _withdrawals) funds for slashing
            slashed = Math.min(amount, _availableToSlash());
            _revertIfZero(slashed);
            collateral.safeTransfer(burner, slashed);

            emit SyncOwedSlash(slashed);
        }
    }

    function _availableToSlash() internal view returns (uint256) {
        return IERC20(collateral).balanceOf(address(this))
            .saturatingSub(uint256(_unclaimedRaw + int256(withdrawals(withdrawalBucket()) - activeWithdrawals())));
    }

    /* * INTERNAL FUNCTIONS * */

    /**
     * @inheritdoc IVaultV2
     */
    function skimPlugins() public {
        unchecked {
            for (uint256 i; i < plugins.length; ++i) {
                IPluginBase(plugins[i]).skim(address(this));
            }
        }
    }

    /**
     * @inheritdoc IVaultV2
     */
    function deallocatePlugins() public nonReentrant {
        unchecked {
            uint256 toDeallocate = pluginsAllocated.saturatingSub(totalStake());
            if (toDeallocate > 0) {
                for (uint256 i; i < plugins.length; ++i) {
                    address plugin = plugins[i];
                    uint256 pluginAllocated_ = pluginAllocated[plugin];
                    if (pluginAllocated_ > 0) {
                        uint256 deallocated = _deallocatePlugin(plugin, Math.min(pluginAllocated_, toDeallocate));
                        if (deallocated > 0) {
                            toDeallocate -= deallocated;
                            if (toDeallocate == uint256(0)) {
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

        if (params.epochDuration == uint48(0)) {
            revert InvalidEpochDuration();
        }

        if (params.pluginLimitSetDelay <= params.epochDuration) {
            revert InvalidPluginActiveDelay();
        }

        __ERC20_init(params.name, params.symbol);

        collateral = params.collateral;

        burner = params.burner;

        epochDuration = params.epochDuration;

        depositWhitelist = params.depositWhitelist;

        isDepositLimit = params.isDepositLimit;
        depositLimit = params.depositLimit;

        pluginLimitSetDelay = params.pluginLimitSetDelay;

        _grantRoleIfNotZero(DEFAULT_ADMIN_ROLE, params.defaultAdminRoleHolder);
        _grantRoleIfNotZero(DEPOSIT_WHITELIST_SET_ROLE, params.depositWhitelistSetRoleHolder);
        _grantRoleIfNotZero(DEPOSITOR_WHITELIST_ROLE, params.depositorWhitelistRoleHolder);
        _grantRoleIfNotZero(IS_DEPOSIT_LIMIT_SET_ROLE, params.isDepositLimitSetRoleHolder);
        _grantRoleIfNotZero(DEPOSIT_LIMIT_SET_ROLE, params.depositLimitSetRoleHolder);
        _grantRoleIfNotZero(SET_PLUGIN_LIMIT_ROLE, params.setPluginLimitRoleHolder);
        _grantRoleIfNotZero(ALLOCATE_PLUGIN_ROLE, params.allocatePluginRoleHolder);

        for (uint256 i; i < params.pluginsData.length; ++i) {
            address plugin = params.pluginsData[i].plugin;
            uint208 limit = params.pluginsData[i].limit;
            _revertIfZero(plugin);
            _revertIfZero(limit);
            if (pluginLimit[plugin] > 0) {
                revert DuplicatePlugin();
            }
            plugins.push(plugin);
            pluginLimit[plugin] = limit;
        }

        emit Initialize(params);
    }

    /* INTERNAL HELPERS */

    function _revertIfZero(address value) internal pure {
        if (value == address(0)) {
            revert InvalidAddress();
        }
    }

    function _revertIfZero(uint256 amount) internal pure {
        if (amount == uint256(0)) {
            revert InsufficientAmount();
        }
    }

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
    function migrateWithdrawalOf(address account, uint48 epoch) public nonReentrant {
        MIGRATOR_V1V2.delegateCallContract(abi.encodeCall(MigratorV1V2.migrateWithdrawalOf, (account, epoch)));
    }

    function _migrate(uint64 oldVersion, uint64, bytes calldata data) internal override {
        MIGRATOR_V1V2.delegateCallContract(abi.encodeCall(MigratorV1V2.migrate, (oldVersion, data)));
    }
}
