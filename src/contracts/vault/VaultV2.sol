// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {DelegatorFactory} from "../DelegatorFactory.sol";
import {MigratableEntity} from "../common/MigratableEntity.sol";
import {SlasherFactory} from "../SlasherFactory.sol";
import {UniversalDelegator} from "../delegator/UniversalDelegator.sol";
import {UniversalSlasher} from "../slasher/UniversalSlasher.sol";
import {VaultV2Storage} from "./VaultV2Storage.sol";

import {Checkpoints as CheckpointsV2} from "../libraries/CheckpointsV2.sol";
import {Checkpoints} from "../libraries/Checkpoints.sol";
import {ERC4626Math} from "../libraries/ERC4626Math.sol";

import {IBaseDelegator} from "../../interfaces/delegator/IBaseDelegator.sol";
import {IBaseSlasher} from "../../interfaces/slasher/IBaseSlasher.sol";
import {IPluginBase} from "../../interfaces/vault/IPluginBase.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {IUniversalDelegator} from "../../interfaces/delegator/IUniversalDelegator.sol";
import {
    IVaultV2,
    MAX_DURATION,
    MAX_PLUGINS,
    DEPOSIT_WHITELIST_SET_ROLE,
    DEPOSITOR_WHITELIST_ROLE,
    IS_DEPOSIT_LIMIT_SET_ROLE,
    DEPOSIT_LIMIT_SET_ROLE,
    SET_PLUGIN_LIMIT_ROLE,
    SWAP_PLUGINS_ROLE,
    ALLOCATE_PLUGIN_ROLE,
    DEALLOCATE_PLUGIN_ROLE
} from "../../interfaces/vault/IVaultV2.sol";
import {UNIVERSAL_DELEGATOR_TYPE} from "../../interfaces/delegator/IUniversalDelegator.sol";
import {UNIVERSAL_SLASHER_TYPE} from "../../interfaces/slasher/IUniversalSlasher.sol";
import {VAULT_VERSION} from "../../interfaces/vault/IVault.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {FixedPointMathLib as Math} from "@solady/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib as SafeERC20} from "@solady/src/utils/SafeTransferLib.sol";

/// @title VaultV2
/// @notice Contract for upgradeable vault collateral, withdrawals, plugins, and migrations.
contract VaultV2 is VaultV2Storage, MigratableEntity, AccessControlUpgradeable, ERC20Upgradeable, IVaultV2 {
    using Checkpoints for Checkpoints.Trace208;
    using Checkpoints for Checkpoints.Trace256;
    using CheckpointsV2 for CheckpointsV2.Trace208;
    using CheckpointsV2 for CheckpointsV2.Trace256;
    using Math for uint256;
    using SafeERC20 for address;

    /* MODIFIERS */

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

    /* MULTICALL */

    /// @inheritdoc IVaultV2
    function multicall(bytes[] calldata data) public {
        for (uint256 i; i < data.length; ++i) {
            (bool success, bytes memory returnData) = address(this).delegatecall(data[i]);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(32, returnData), mload(returnData))
                }
            }
        }
    }

    /* CONSTRUCTOR */

    constructor(
        address delegatorFactory,
        address slasherFactory,
        address vaultFactory,
        address rewards,
        address pluginRegistry
    ) VaultV2Storage(delegatorFactory, slasherFactory, rewards, pluginRegistry) MigratableEntity(vaultFactory) {}

    /* VIEW FUNCTIONS */

    /// @inheritdoc IVaultV2
    function isInitialized() public view returns (bool) {
        return _isDelegatorInitialized && _isSlasherInitialized;
    }

    /// @inheritdoc IVaultV2
    function totalStake() public view returns (uint256) {
        unchecked {
            return activeStake() + activeWithdrawals();
        }
    }

    /// @inheritdoc IVaultV2
    function activeWithdrawalsForAt(uint48 duration, uint48 timestamp) public view returns (uint256) {
        unchecked {
            if (duration > epochDuration) {
                return 0;
            }
            uint208 curWithdrawalBucket = _unlockToBucket.upperLookupRecent(timestamp);
            uint256 curWithdrawalShares = _withdrawalShares[curWithdrawalBucket].upperLookupRecent(timestamp);
            return curWithdrawalShares > 0
                ? _activeWithdrawalSharesForAt(duration, timestamp)
                    .fullMulDiv(_withdrawals[curWithdrawalBucket].upperLookupRecent(timestamp), curWithdrawalShares)
                : 0;
        }
    }

    /// @inheritdoc IVaultV2
    function activeWithdrawalsFor(uint48 duration) public view returns (uint256 amount) {
        unchecked {
            if (duration > epochDuration) {
                return 0;
            }
            uint208 curWithdrawalBucket = withdrawalBucket();
            uint256 curWithdrawalShares = withdrawalShares(curWithdrawalBucket);
            return curWithdrawalShares > 0
                ? _activeWithdrawalSharesFor(duration).fullMulDiv(withdrawals(curWithdrawalBucket), curWithdrawalShares)
                : 0;
        }
    }

    /// @inheritdoc IVaultV2
    function activeWithdrawalsAt(uint48 timestamp) public view returns (uint256) {
        return activeWithdrawalsForAt(0, timestamp);
    }

    /// @inheritdoc IVaultV2
    function activeWithdrawals() public view returns (uint256) {
        return activeWithdrawalsFor(0);
    }

    /// @inheritdoc IVaultV2
    function activeBalanceOfAt(address account, uint48 timestamp, bytes memory) public view returns (uint256) {
        return ERC4626Math.previewRedeem(
            activeSharesOfAt(account, timestamp, ""), activeStakeAt(timestamp, ""), activeSharesAt(timestamp, "")
        );
    }

    /// @inheritdoc IVaultV2
    function activeBalanceOf(address account) public view returns (uint256) {
        return ERC4626Math.previewRedeem(activeSharesOf(account), activeStake(), activeShares());
    }

    /// @inheritdoc IVaultV2
    function withdrawalsOfLength(address account) public view returns (uint256) {
        unchecked {
            if (__migrateTimestamp == 0 || _withdrawalsOfLength[account] > 0) {
                return _withdrawalsOfLength[account];
            }

            // Legacy support.
            return __migrateEpoch + 2;
        }
    }

    /// @inheritdoc IVaultV2
    function withdrawalSharesOf(uint256 index, address account) public view returns (uint256 shares) {
        unchecked {
            shares = _withdrawalSharesOf[index][account];

            // Legacy support.
            if (__migrateTimestamp > 0) {
                uint48 migrateEpoch = __migrateEpoch;
                if (index == migrateEpoch || index == migrateEpoch + 1) {
                    shares = ERC4626Math.previewRedeem(shares, __withdrawals[index], __withdrawalShares[index]);
                }
            }
        }
    }

    /// @inheritdoc IVaultV2
    function withdrawalUnlockAfter(uint256 index, address account) public view returns (uint48 timestamp) {
        unchecked {
            if (__migrateTimestamp > 0) {
                // Legacy support.
                uint48 migrateEpoch = __migrateEpoch;
                if (index == migrateEpoch) {
                    return __migrateNextEpochTimestamp;
                }
                if (index == migrateEpoch + 1) {
                    return __migrateTimestamp + epochDuration;
                }
            }

            return _withdrawalUnlockAfter[index][account];
        }
    }

    /// @inheritdoc IVaultV2
    function withdrawalsOf(uint256 index, address account) public view returns (uint256 amount) {
        unchecked {
            uint48 migrateEpoch = __migrateEpoch;
            if (migrateEpoch == 0 || index >= migrateEpoch) {
                uint256 bucketIndex = _unlockToBucket.upperLookupRecent(withdrawalUnlockAfter(index, account));
                uint256 withdrawalShares_ = withdrawalShares(bucketIndex);
                return withdrawalShares_ > 0
                    ? ERC4626Math.previewRedeem(
                        withdrawalSharesOf(index, account), withdrawals(bucketIndex), withdrawalShares_
                    )
                    : 0;
            }

            // Legacy support.
            return ERC4626Math.previewRedeem(
                _withdrawalSharesOf[index][account], __withdrawals[index], __withdrawalShares[index]
            );
        }
    }

    /// @inheritdoc ERC20Upgradeable
    function decimals() public view override returns (uint8) {
        return IERC20Metadata(collateral).decimals();
    }

    /// @inheritdoc ERC20Upgradeable
    function totalSupply() public view override returns (uint256) {
        return activeShares();
    }

    /// @inheritdoc ERC20Upgradeable
    function balanceOf(address account) public view override returns (uint256) {
        return activeSharesOf(account);
    }

    /// @inheritdoc IVaultV2
    function allocatable() public view returns (uint256) {
        return
            totalStake().saturatingSub(IUniversalDelegator(delegator).getNoPluginsSize())
                .saturatingSub(pluginsAllocated);
    }

    /* PUBLIC FUNCTIONS (ACCOUNTING) */

    /// @inheritdoc IVaultV2
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

            uint256 balanceBefore = collateral.balanceOf(address(this));
            collateral.safeTransferFrom(msg.sender, address(this), amount);
            depositedAmount = collateral.balanceOf(address(this)) - balanceBefore;

            _revertIfZero(depositedAmount);

            if (isDepositLimit && activeStake() + depositedAmount > depositLimit) {
                revert DepositLimitReached();
            }

            uint256 curActiveStake = activeStake();
            uint256 curActiveShares = activeShares();

            mintedShares = ERC4626Math.previewDeposit(depositedAmount, curActiveShares, curActiveStake);
            _revertIfZero(mintedShares);

            uint256 newActiveShares = curActiveShares + mintedShares;
            require(newActiveShares >= curActiveShares);
            _activeShares.push(uint48(block.timestamp), newActiveShares);
            _activeStake.push(uint48(block.timestamp), curActiveStake + depositedAmount);
            _activeSharesOf[onBehalfOf].push(uint48(block.timestamp), activeSharesOf(onBehalfOf) + mintedShares);

            emit Deposit(msg.sender, onBehalfOf, depositedAmount, mintedShares);
            emit Transfer(address(0), onBehalfOf, mintedShares);

            // Allocate only non-fee-on-transfer tokens.
            if (depositedAmount == amount && plugins.length > 0) {
                _allocatePlugin(plugins[0], depositedAmount);
            }
        }
    }

    /// @inheritdoc IVaultV2
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
            _revertIfZero(burnedShares);
            if (burnedShares > activeSharesOf(msg.sender)) {
                revert TooMuchWithdraw();
            }
            mintedShares = _withdraw(claimer, amount, burnedShares);
        }
    }

    /// @inheritdoc IVaultV2
    function redeem(address claimer, uint256 shares)
        public
        withSkimPlugins
        nonReentrant
        returns (uint256 withdrawnAssets, uint256 mintedShares)
    {
        unchecked {
            _revertIfZero(claimer);
            _revertIfZero(shares);
            if (shares > activeSharesOf(msg.sender)) {
                revert TooMuchRedeem();
            }

            withdrawnAssets = ERC4626Math.previewRedeem(shares, activeStake(), activeShares());
            _revertIfZero(withdrawnAssets);
            mintedShares = _withdraw(claimer, withdrawnAssets, shares);
        }
    }

    /// @inheritdoc IVaultV2
    function instantWithdraw(address recipient, uint256 amount)
        public
        withDeallocatePlugins(true)
        nonReentrant
        returns (uint256 withdrawnAssets, uint256 burnedShares)
    {
        unchecked {
            withdrawnAssets =
                Math.min(Math.min(amount, _availableToSlash()), IUniversalDelegator(delegator).getWithdrawalBuffer());

            _revertIfZero(withdrawnAssets);

            uint256 curActiveStake = activeStake();
            uint256 curActiveShares = activeShares();
            uint256 curActiveSharesOf = activeSharesOf(msg.sender);

            burnedShares = ERC4626Math.previewWithdraw(withdrawnAssets, curActiveShares, curActiveStake);
            if (burnedShares > curActiveSharesOf) {
                revert TooMuchWithdraw();
            }

            _activeSharesOf[msg.sender].push(uint48(block.timestamp), curActiveSharesOf - burnedShares);
            _activeStake.push(uint48(block.timestamp), curActiveStake - withdrawnAssets);
            _activeShares.push(uint48(block.timestamp), curActiveShares - burnedShares);

            collateral.safeTransfer(recipient, withdrawnAssets);

            emit InstantWithdraw(msg.sender, withdrawnAssets, burnedShares);
            emit Transfer(msg.sender, address(0), burnedShares);
        }
    }

    /// @inheritdoc IVaultV2
    function claim(address recipient, uint256 index)
        public
        withDeallocatePlugins(true)
        nonReentrant
        returns (uint256 amount)
    {
        unchecked {
            _revertIfZero(recipient);

            if (isWithdrawalsClaimed[index][msg.sender]) {
                revert AlreadyClaimed();
            }
            if (block.timestamp <= withdrawalUnlockAfter(index, msg.sender)) {
                revert WithdrawalNotMatured();
            }

            amount = withdrawalsOf(index, msg.sender);
            _revertIfZero(amount);

            isWithdrawalsClaimed[index][msg.sender] = true;
            _unclaimedRaw -= int256(amount);

            collateral.safeTransfer(recipient, amount);

            emit Claim(msg.sender, recipient, index, amount);
        }
    }

    /// @inheritdoc IVaultV2
    function claimBatch(address recipient, uint256[] calldata indexes) public returns (uint256 amount) {
        unchecked {
            for (uint256 i; i < indexes.length; ++i) {
                amount += claim(recipient, indexes[i]);
            }
        }
    }

    /// @dev Credit rewards donation into active stake after pulling collateral from the rewards address.
    function donate(uint256 amount) public nonReentrant {
        unchecked {
            if (REWARDS != msg.sender) {
                revert NotRewards();
            }

            uint256 balanceBefore = collateral.balanceOf(address(this));
            collateral.safeTransferFrom(msg.sender, address(this), amount);
            amount = collateral.balanceOf(address(this)) - balanceBefore;

            _revertIfZero(amount);

            uint256 curActiveStake = activeStake();
            uint256 curActiveWithdrawals = activeWithdrawals();
            uint256 withdrawalsDonated = amount.fullMulDiv(curActiveWithdrawals, curActiveStake + curActiveWithdrawals);

            if (withdrawalsDonated > 0) {
                _updateWithdrawalsSharePrice(curActiveWithdrawals + withdrawalsDonated);
            }
            _activeStake.push(uint48(block.timestamp), amount - withdrawalsDonated + curActiveStake);

            emit Donate(amount);
        }
    }

    // @dev Internal dev function to handle slashing.
    function onSlash(uint256 amount, bool withPlugins)
        public
        withDeallocatePlugins(withPlugins)
        nonReentrant
        returns (uint256 slashedAmount, uint256 owedAmount)
    {
        unchecked {
            if (slasher != msg.sender) {
                revert NotSlasher();
            }

            uint256 curActiveStake = activeStake();
            uint256 curActiveWithdrawals = activeWithdrawals();
            uint256 slashableStake = curActiveStake + curActiveWithdrawals;

            slashedAmount = Math.min(amount, slashableStake);
            if (slashedAmount > 0) {
                uint256 activeSlashed = slashedAmount.fullMulDiv(curActiveStake, slashableStake);
                _activeStake.push(uint48(block.timestamp), curActiveStake - activeSlashed);
                if (curActiveWithdrawals > 0) {
                    _updateWithdrawalsSharePrice(curActiveWithdrawals - (slashedAmount - activeSlashed));
                }

                owedAmount = slashedAmount.saturatingSub(_availableToSlash());

                if (owedAmount < slashedAmount) {
                    collateral.safeTransfer(burner, slashedAmount - owedAmount);
                }
            }
        }

        emit OnSlash(amount, slashedAmount);
    }

    /* INTERNAL FUNCTIONS (ACCOUNTING) */

    /// @dev Return active withdrawal shares for a duration at a timestamp.
    function _activeWithdrawalSharesForAt(uint48 duration, uint48 timestamp) internal view returns (uint256) {
        unchecked {
            return _withdrawalSharesCumulative.upperLookupRecent(timestamp + epochDuration)
                - _withdrawalSharesCumulative.upperLookupRecent(timestamp + duration);
        }
    }

    /// @dev Return active withdrawal shares for a duration at the current timestamp.
    function _activeWithdrawalSharesFor(uint48 duration) internal view returns (uint256) {
        unchecked {
            return _withdrawalSharesCumulative.latest()
                - _withdrawalSharesCumulative.upperLookupRecent(uint48(block.timestamp) + duration);
        }
    }

    /// @dev Convert active shares into a withdrawal request.
    function _withdraw(address claimer, uint256 withdrawnAssets, uint256 burnedShares)
        internal
        virtual
        returns (uint256 mintedShares)
    {
        unchecked {
            _activeSharesOf[msg.sender].push(uint48(block.timestamp), activeSharesOf(msg.sender) - burnedShares);
            _activeShares.push(uint48(block.timestamp), activeShares() - burnedShares);
            _activeStake.push(uint48(block.timestamp), activeStake() - withdrawnAssets);

            uint208 curWithdrawalBucket = withdrawalBucket();
            uint256 curWithdrawals = withdrawals(curWithdrawalBucket);
            uint256 curWithdrawalShares = withdrawalShares(curWithdrawalBucket);

            mintedShares = ERC4626Math.previewDeposit(withdrawnAssets, curWithdrawalShares, curWithdrawals);
            _revertIfZero(mintedShares);

            uint256 newWithdrawalShares = curWithdrawalShares + mintedShares;
            require(newWithdrawalShares >= curWithdrawalShares);
            _withdrawalShares[curWithdrawalBucket].push(uint48(block.timestamp), newWithdrawalShares);
            _withdrawals[curWithdrawalBucket].push(uint48(block.timestamp), curWithdrawals + withdrawnAssets);

            uint48 unlockAfter = uint48(block.timestamp) + epochDuration;
            uint256 curWithdrawalsOfLength = withdrawalsOfLength(claimer);

            _withdrawalsOfLength[claimer] = curWithdrawalsOfLength + 1;
            _withdrawalSharesOf[curWithdrawalsOfLength][claimer] = mintedShares;
            _withdrawalUnlockAfter[curWithdrawalsOfLength][claimer] = unlockAfter;
            _withdrawalSharesCumulative.push(unlockAfter, _withdrawalSharesCumulative.latest() + mintedShares);

            emit Withdraw(msg.sender, claimer, withdrawnAssets, burnedShares, mintedShares);
            emit Transfer(msg.sender, address(0), burnedShares);
        }
    }

    function _updateWithdrawalsSharePrice(uint256 newActiveWithdrawals) internal {
        unchecked {
            uint208 curWithdrawalBucket = withdrawalBucket();
            uint256 curActiveWithdrawalShares = _activeWithdrawalSharesFor(0);
            uint256 curClaimableWithdrawals = withdrawals(curWithdrawalBucket) - activeWithdrawals();
            uint256 curClaimableWithdrawalShares = withdrawalShares(curWithdrawalBucket) - curActiveWithdrawalShares;

            if (curClaimableWithdrawalShares > 0) {
                _withdrawalShares[curWithdrawalBucket].push(uint48(block.timestamp), curClaimableWithdrawalShares);
                _withdrawals[curWithdrawalBucket].push(uint48(block.timestamp), curClaimableWithdrawals);
                _unclaimedRaw += int256(curClaimableWithdrawals);

                ++curWithdrawalBucket;
                _withdrawalShares[curWithdrawalBucket].push(uint48(block.timestamp), curActiveWithdrawalShares);
                _unlockToBucket.push(uint48(block.timestamp), curWithdrawalBucket);
            }
            _withdrawals[curWithdrawalBucket].push(uint48(block.timestamp), newActiveWithdrawals);
        }
    }

    /* PUBLIC FUNCTIONS (CURATOR) */

    /// @inheritdoc IVaultV2
    function setDepositWhitelist(bool newStatus) public nonReentrant onlyRole(DEPOSIT_WHITELIST_SET_ROLE) {
        depositWhitelist = newStatus;
        emit SetDepositWhitelist(newStatus);
    }

    /// @inheritdoc IVaultV2
    function setDepositorWhitelistStatus(address account, bool newStatus)
        public
        nonReentrant
        onlyRole(DEPOSITOR_WHITELIST_ROLE)
    {
        _revertIfZero(account);
        isDepositorWhitelisted[account] = newStatus;
        emit SetDepositorWhitelistStatus(account, newStatus);
    }

    /// @inheritdoc IVaultV2
    function setIsDepositLimit(bool newStatus) public nonReentrant onlyRole(IS_DEPOSIT_LIMIT_SET_ROLE) {
        isDepositLimit = newStatus;
        emit SetIsDepositLimit(newStatus);
    }

    /// @inheritdoc IVaultV2
    function setDepositLimit(uint256 newLimit) public nonReentrant onlyRole(DEPOSIT_LIMIT_SET_ROLE) {
        depositLimit = newLimit;
        emit SetDepositLimit(newLimit);
    }

    /// @inheritdoc IVaultV2
    function setPluginLimit(address plugin, uint208 newLimit) public nonReentrant onlyRole(SET_PLUGIN_LIMIT_ROLE) {
        unchecked {
            _revertIfZero(plugin);

            if (pluginAllocated[plugin] > newLimit) {
                revert PluginAllocated();
            }

            uint256 numPlugins = plugins.length;
            if (newLimit > 0) {
                uint256 i;
                for (; i < numPlugins; ++i) {
                    if (plugin == plugins[i]) {
                        break;
                    }
                }
                if (i == numPlugins) {
                    if (numPlugins + 1 > MAX_PLUGINS) {
                        revert TooManyPlugins();
                    }
                    if (!IRegistry(PLUGIN_REGISTRY).isEntity(plugin)) {
                        revert NotPlugin();
                    }
                    plugins.push(plugin);
                    _grantRole(ALLOCATE_PLUGIN_ROLE, plugin);
                    _grantRole(DEALLOCATE_PLUGIN_ROLE, plugin);
                }
            } else {
                for (uint256 i; i < numPlugins; ++i) {
                    if (plugin == plugins[i]) {
                        plugins[i] = plugins[numPlugins - 1];
                        plugins.pop();
                        _revokeRole(ALLOCATE_PLUGIN_ROLE, plugin);
                        _revokeRole(DEALLOCATE_PLUGIN_ROLE, plugin);
                        break;
                    }
                }
            }
            pluginLimit[plugin] = newLimit;

            emit SetPluginLimit(plugin, newLimit);
        }
    }

    /// @inheritdoc IVaultV2
    function swapPlugins(address plugin1, address plugin2) public nonReentrant onlyRole(SWAP_PLUGINS_ROLE) {
        unchecked {
            uint256 index1 = type(uint256).max;
            uint256 index2 = type(uint256).max;
            uint256 numPlugins = plugins.length;
            for (uint256 i; i < numPlugins; ++i) {
                if (plugin1 == plugins[i]) {
                    index1 = i;
                } else if (plugin2 == plugins[i]) {
                    index2 = i;
                }
            }
            (plugins[index1], plugins[index2]) = (plugins[index2], plugins[index1]);

            emit SwapPlugins(plugin1, plugin2);
        }
    }

    /// @inheritdoc IVaultV2
    function allocatePlugin(address plugin, uint256 amount)
        public
        onlyRole(ALLOCATE_PLUGIN_ROLE)
        returns (uint256 allocated)
    {
        return _allocatePlugin(plugin, amount);
    }

    /// @dev Allocate collateral to a plugin within configured limits.
    function _allocatePlugin(address plugin, uint256 amount) internal returns (uint256 allocated) {
        unchecked {
            allocated = Math.min(
                Math.min(Math.min(amount, pluginLimit[plugin] - pluginAllocated[plugin]), allocatable()),
                IPluginBase(plugin).allocatable()
            );

            if (allocated > 0) {
                pluginsAllocated += allocated;
                pluginAllocated[plugin] += allocated;

                uint256 balanceBefore = collateral.balanceOf(plugin);
                collateral.safeTransfer(plugin, allocated);
                if (collateral.balanceOf(plugin) - balanceBefore < allocated) {
                    revert FeeOnTransferNotSupported();
                }
                IPluginBase(plugin).allocate(allocated);
            }

            emit Allocate(plugin, allocated);
        }
    }

    /// @inheritdoc IVaultV2
    function deallocatePlugin(address plugin, uint256 amount)
        public
        onlyRole(DEALLOCATE_PLUGIN_ROLE)
        returns (uint256)
    {
        return _deallocatePlugin(plugin, amount);
    }

    /// @dev Deallocate collateral from a plugin and update accounting.
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

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc IVaultV2
    function skimPlugins() public {
        unchecked {
            for (uint256 i; i < plugins.length; ++i) {
                IPluginBase(plugins[i]).skim(address(this));
            }
        }
    }

    /// @inheritdoc IVaultV2
    function deallocatePlugins() public {
        unchecked {
            for (uint256 i; i < plugins.length; ++i) {
                uint256 toDeallocate = pluginsAllocated.saturatingSub(totalStake());
                if (toDeallocate == uint256(0)) {
                    break;
                }
                address plugin = plugins[i];
                uint256 curPluginAllocated = pluginAllocated[plugin];
                if (curPluginAllocated > 0) {
                    _deallocatePlugin(plugin, Math.min(curPluginAllocated, toDeallocate));
                }
            }
        }
    }

    /* INTERNAL FUNCTIONS (PLUGINS) */

    /// @dev Return collateral currently available for slashing.
    function _availableToSlash() internal view returns (uint256) {
        unchecked {
            return collateral.balanceOf(address(this))
                .saturatingSub(uint256(_unclaimedRaw + int256(withdrawals(withdrawalBucket()) - activeWithdrawals())));
        }
    }

    /* PUBLIC FUNCTIONS (INTERNAL LOGIC) */

    // @dev Internal dev function to handle owed slashing.
    function syncOwedSlash(uint256 amount) public nonReentrant returns (uint256 slashedAmount) {
        if (slasher != msg.sender) {
            revert NotSlasher();
        }

        // Use only unclaimable (either active stake or active _withdrawals) funds for slashing.
        slashedAmount = Math.min(amount, _availableToSlash());
        _revertIfZero(slashedAmount);
        collateral.safeTransfer(burner, slashedAmount);

        emit SyncOwedSlash(slashedAmount);
    }

    /// @dev Set the vault delegator once after validating registry membership and vault linkage.
    function setDelegator(address newDelegator) public nonReentrant {
        if (_isDelegatorInitialized) {
            revert DelegatorAlreadyInitialized();
        }

        if (!IRegistry(DELEGATOR_FACTORY).isEntity(newDelegator)) {
            revert NotDelegator();
        }

        if (IBaseDelegator(newDelegator).vault() != address(this)) {
            revert InvalidDelegator();
        }

        delegator = newDelegator;

        _isDelegatorInitialized = true;

        emit SetDelegator(newDelegator);
    }

    /// @dev Set the vault slasher once after validating registry membership and vault linkage.
    function setSlasher(address newSlasher) public nonReentrant {
        if (_isSlasherInitialized) {
            revert SlasherAlreadyInitialized();
        }

        if (newSlasher != address(0)) {
            if (!IRegistry(SLASHER_FACTORY).isEntity(newSlasher)) {
                revert NotSlasher();
            }

            if (IBaseSlasher(newSlasher).vault() != address(this)) {
                revert InvalidSlasher();
            }

            slasher = newSlasher;
        }

        _isSlasherInitialized = true;

        emit SetSlasher(newSlasher);
    }

    /* INTERNAL FUNCTIONS (ERC20) */

    /// @inheritdoc ERC20Upgradeable
    /// @dev Mirror ERC20 transfers into active share checkpoints.
    function _update(address from, address to, uint256 value) internal override {
        // _Update() is called only on transfers, so from == address(0) or to == address(0) is not possible.
        _activeSharesOf[from].push(uint48(block.timestamp), balanceOf(from) - value);
        unchecked {
            _activeSharesOf[to].push(uint48(block.timestamp), balanceOf(to) + value);
        }

        emit Transfer(from, to, value);
    }

    /* INITIALIZATION */

    /// @dev Initialize vault state from encoded initialization parameters.
    function _initialize(uint64, address, bytes memory data) internal virtual override {
        unchecked {
            InitParams memory params = abi.decode(data, (InitParams));

            if (params.collateral == address(0)) {
                revert InvalidCollateral();
            }

            if (params.epochDuration == uint48(0) || params.epochDuration > MAX_DURATION) {
                revert TooLongDuration();
            }

            if (params.depositorToWhitelist == address(0)) {
                revert InvalidDepositorToWhitelist();
            }

            __ERC20_init(params.name, params.symbol);

            collateral = params.collateral;

            burner = params.burner;

            epochDuration = params.epochDuration;

            depositWhitelist = params.depositWhitelist;
            isDepositorWhitelisted[params.depositorToWhitelist] = true;

            isDepositLimit = params.isDepositLimit;
            depositLimit = params.depositLimit;

            _grantRoleIfNotZero(DEFAULT_ADMIN_ROLE, params.defaultAdminRoleHolder);
            _grantRoleIfNotZero(DEPOSIT_WHITELIST_SET_ROLE, params.depositWhitelistSetRoleHolder);
            _grantRoleIfNotZero(DEPOSITOR_WHITELIST_ROLE, params.depositorWhitelistRoleHolder);
            _grantRoleIfNotZero(IS_DEPOSIT_LIMIT_SET_ROLE, params.isDepositLimitSetRoleHolder);
            _grantRoleIfNotZero(DEPOSIT_LIMIT_SET_ROLE, params.depositLimitSetRoleHolder);
            _grantRoleIfNotZero(SET_PLUGIN_LIMIT_ROLE, params.setPluginLimitRoleHolder);
            _grantRoleIfNotZero(ALLOCATE_PLUGIN_ROLE, params.allocatePluginRoleHolder);

            emit Initialize(params);
        }
    }

    /* MIGRATION */

    /// @dev Migrate vault state and deploy V2 delegator and slasher contracts.
    function _migrate(uint64 oldVersion, uint64, bytes calldata data) internal override {
        unchecked {
            if (epochDuration > MAX_DURATION) {
                revert TooLongDuration();
            }

            __migrateTimestamp = uint48(block.timestamp);
            uint48 migrateEpoch = uint48((block.timestamp - __epochDurationInit) / epochDuration);
            uint48 migrateNextEpochTimestamp = __epochDurationInit + (migrateEpoch + 1) * epochDuration;
            __migrateEpoch = migrateEpoch;
            __migrateNextEpochTimestamp = migrateNextEpochTimestamp;

            MigrateParams memory params = abi.decode(data, (MigrateParams));
            if (oldVersion == VAULT_VERSION) {
                __ERC20_init(params.name, params.symbol);
            }

            uint256 curActiveWithdrawals;
            if (migrateEpoch > 0) {
                curActiveWithdrawals = __withdrawals[migrateEpoch];
                if (curActiveWithdrawals > 0) {
                    _withdrawalSharesCumulative.push(migrateNextEpochTimestamp, curActiveWithdrawals);
                }
            }
            curActiveWithdrawals += __withdrawals[migrateEpoch + 1];
            if (curActiveWithdrawals > 0) {
                _withdrawalSharesCumulative.push(uint48(block.timestamp) + epochDuration, curActiveWithdrawals);
                _withdrawals[0].push(uint48(block.timestamp), curActiveWithdrawals);
                _withdrawalShares[0].push(uint48(block.timestamp), curActiveWithdrawals);
            }

            _unclaimedRaw = int256(collateral.balanceOf(address(this)) - activeStake() - curActiveWithdrawals);

            address oldDelegator = delegator;
            delegator = DelegatorFactory(DELEGATOR_FACTORY)
                .create(UNIVERSAL_DELEGATOR_TYPE, abi.encode(address(this), params.delegatorParams));
            UniversalDelegator(delegator).migrate(oldDelegator);

            if (slasher != address(0)) {
                address oldSlasher = slasher;
                slasher = SlasherFactory(SLASHER_FACTORY)
                    .create(UNIVERSAL_SLASHER_TYPE, abi.encode(address(this), params.slasherParams));
                UniversalSlasher(slasher).migrate(oldSlasher);
            }

            emit Migrate(params, delegator, slasher);
        }
    }

    /* UTILITY FUNCTIONS */

    /// @dev Revert when an address argument is zero.
    function _revertIfZero(address value) internal pure {
        if (value == address(0)) {
            revert InvalidAddress();
        }
    }

    /// @dev Revert when an amount argument is zero.
    function _revertIfZero(uint256 amount) internal pure {
        if (amount == uint256(0)) {
            revert InsufficientAmount();
        }
    }

    /// @dev Grant a role when the holder address is not zero.
    function _grantRoleIfNotZero(bytes32 role, address holder) internal {
        if (holder != address(0)) {
            _grantRole(role, holder);
        }
    }
}
