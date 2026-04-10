// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {DelegatorFactory} from "../DelegatorFactory.sol";
import {MigratableEntity} from "../common/MigratableEntity.sol";
import {SlasherFactory} from "../SlasherFactory.sol";
import {UniversalDelegator} from "../delegator/UniversalDelegator.sol";
import {UniversalSlasher} from "../slasher/UniversalSlasher.sol";
import {VaultV2Migrate} from "./VaultV2Migrate.sol";
import {VaultV2Storage} from "./VaultV2Storage.sol";

import {Checkpoints as CheckpointsV2} from "../libraries/CheckpointsV2.sol";
import {Checkpoints} from "../libraries/Checkpoints.sol";
import {ERC4626Math} from "../libraries/ERC4626Math.sol";

import {IAdapterBase} from "../../interfaces/vault/IAdapterBase.sol";
import {IEntity} from "../../interfaces/common/IEntity.sol";
import {IFeeRegistry, MAX_FEE} from "../../interfaces/vault/IFeeRegistry.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {IRewards} from "../../interfaces/vault/IRewards.sol";
import {
    IVaultV2,
    MAX_DURATION,
    MAX_ADAPTERS,
    DEPOSIT_WHITELIST_SET_ROLE,
    DEPOSITOR_WHITELIST_ROLE,
    IS_DEPOSIT_LIMIT_SET_ROLE,
    DEPOSIT_LIMIT_SET_ROLE,
    SET_ADAPTER_LIMIT_ROLE,
    SWAP_ADAPTERS_ROLE,
    ALLOCATE_ADAPTER_ROLE,
    DEALLOCATE_ADAPTER_ROLE
} from "../../interfaces/vault/IVaultV2.sol";
import {UNIVERSAL_DELEGATOR_TYPE} from "../../interfaces/delegator/IUniversalDelegator.sol";
import {UNIVERSAL_SLASHER_TYPE} from "../../interfaces/slasher/IUniversalSlasher.sol";
import {VAULT_VERSION} from "../../interfaces/vault/IVault.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Calldata} from "@openzeppelin/contracts/utils/Calldata.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {FixedPointMathLib as Math} from "@solady/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib as SafeERC20} from "@solady/src/utils/SafeTransferLib.sol";

/// @title VaultV2
/// @notice Contract for upgradeable vault collateral, withdrawals, adapters, and migrations.
/// @dev Priority over funds utilization:
///      1. No-adapters subvaults can always slash full amount.
///      2. Firstly, incoming funds are used for claimable withdrawals.
///      3. Secondly, incoming funds are used to sync owed slashes.
///      4. Remaining funds are used for instant withdrawals and adapters allocation simultaneously.
contract VaultV2 is VaultV2Storage, MigratableEntity, AccessControlUpgradeable, ERC20Upgradeable, IVaultV2 {
    using Math for uint256;
    using SafeERC20 for address;
    using Checkpoints for Checkpoints.Trace208;
    using Checkpoints for Checkpoints.Trace256;
    using CheckpointsV2 for CheckpointsV2.Trace208;
    using CheckpointsV2 for CheckpointsV2.Trace256;

    /* IMMUTABLES */

    address internal immutable VAULT_V2_MIGRATE;

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
        address feeRegistry,
        address rewards,
        address adapterRegistry,
        address vaultV2Migrate
    )
        VaultV2Storage(delegatorFactory, slasherFactory, feeRegistry, rewards, adapterRegistry)
        MigratableEntity(vaultFactory)
    {
        VAULT_V2_MIGRATE = vaultV2Migrate;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IVaultV2
    function isInitialized() public view returns (bool) {
        return _isDelegatorInitialized && _isSlasherInitialized;
    }

    /// @inheritdoc IVaultV2
    function totalStake() public view returns (uint256) {
        return activeStake() + activeWithdrawals();
    }

    /// @inheritdoc IVaultV2
    function activeBalanceOfAt(address account, uint48 timestamp, bytes calldata) public view returns (uint256) {
        return ERC4626Math.previewRedeem(
            activeSharesOfAt(account, timestamp, Calldata.emptyBytes()),
            activeStakeAt(timestamp, Calldata.emptyBytes()),
            activeSharesAt(timestamp, Calldata.emptyBytes())
        );
    }

    /// @inheritdoc IVaultV2
    function activeBalanceOf(address account) public view returns (uint256) {
        return ERC4626Math.previewRedeem(activeSharesOf(account), activeStake(), activeShares());
    }

    /// @inheritdoc IVaultV2
    function activeWithdrawalsForAt(uint48 duration, uint48 timestamp) public view returns (uint256) {
        if (duration > epochDuration) {
            return 0;
        }
        uint208 curWithdrawalBucket = _unlockToBucket.upperLookupRecent(timestamp);
        uint256 curWithdrawalShares = _withdrawalShares[curWithdrawalBucket].upperLookupRecent(timestamp);
        return curWithdrawalShares > 0
            ? activeWithdrawalSharesForAt(duration, timestamp)
                .fullMulDiv(_withdrawals[curWithdrawalBucket].upperLookupRecent(timestamp), curWithdrawalShares)
            : 0;
    }

    /// @inheritdoc IVaultV2
    function activeWithdrawalsFor(uint48 duration) public view returns (uint256 amount) {
        if (duration > epochDuration) {
            return 0;
        }
        uint208 curWithdrawalBucket = withdrawalBucket();
        uint256 curWithdrawalShares = withdrawalShares(curWithdrawalBucket);
        return curWithdrawalShares > 0
            ? activeWithdrawalSharesFor(duration).fullMulDiv(withdrawals(curWithdrawalBucket), curWithdrawalShares)
            : 0;
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
    function activeWithdrawalSharesForAt(uint48 duration, uint48 timestamp) public view returns (uint256) {
        return _withdrawalSharesCumulative.upperLookupRecent(timestamp + epochDuration)
            - _withdrawalSharesCumulative.upperLookupRecent(timestamp + duration);
    }

    /// @inheritdoc IVaultV2
    function activeWithdrawalSharesFor(uint48 duration) public view returns (uint256) {
        return _withdrawalSharesCumulative.latest()
            - _withdrawalSharesCumulative.upperLookupRecent(uint48(block.timestamp + duration));
    }

    /// @inheritdoc IVaultV2
    function activeWithdrawalSharesAt(uint48 timestamp) public view returns (uint256) {
        return activeWithdrawalSharesForAt(0, timestamp);
    }

    /// @inheritdoc IVaultV2
    function activeWithdrawalShares() public view returns (uint256) {
        return activeWithdrawalSharesFor(0);
    }

    /// @inheritdoc IVaultV2
    function activeWithdrawalSharesOfAt(address account, uint48 timestamp) public view returns (uint256 shares) {
        shares = _withdrawalSharesCumulativeOf[account].upperLookupRecent(timestamp + epochDuration)
            - _withdrawalSharesCumulativeOf[account].upperLookupRecent(timestamp);

        // Legacy support.
        uint48 curMigrateTimestamp = migrateTimestamp;
        if (curMigrateTimestamp > 0 && timestamp >= curMigrateTimestamp) {
            uint48 migrateEpoch = __migrateEpoch;
            if (timestamp < __migrateNextEpochTimestamp) {
                shares += withdrawalSharesOf(migrateEpoch, account);
            }
            if (timestamp < curMigrateTimestamp + epochDuration) {
                shares += withdrawalSharesOf(migrateEpoch + 1, account);
            }
        }
    }

    /// @inheritdoc IVaultV2
    function withdrawalsOfLength(address account) public view returns (uint256) {
        if (migrateTimestamp == 0 || _withdrawalsOfLength[account] > 0) {
            return _withdrawalsOfLength[account];
        }

        // Legacy support.
        return __migrateEpoch + 2;
    }

    /// @inheritdoc IVaultV2
    function withdrawalSharesOf(uint256 index, address account) public view returns (uint256 shares) {
        shares = _withdrawalSharesOf[index][account];

        // Legacy support.
        if (migrateTimestamp > 0) {
            uint48 migrateEpoch = __migrateEpoch;
            if (index == migrateEpoch || index == migrateEpoch + 1) {
                shares = ERC4626Math.previewRedeem(shares, __withdrawals[index], __withdrawalShares[index]);
            }
        }
    }

    /// @inheritdoc IVaultV2
    function withdrawalUnlockAt(uint256 index, address account) public view returns (uint48 timestamp) {
        uint48 curMigrateTimestamp = migrateTimestamp;
        if (curMigrateTimestamp > 0) {
            // Legacy support.
            uint48 migrateEpoch = __migrateEpoch;
            if (index == migrateEpoch) {
                return __migrateNextEpochTimestamp;
            }
            if (index == migrateEpoch + 1) {
                return curMigrateTimestamp + epochDuration;
            }
        }

        return _withdrawalUnlockAt[index][account];
    }

    /// @inheritdoc IVaultV2
    function withdrawalsOf(uint256 index, address account) public view returns (uint256 amount) {
        uint48 migrateEpoch = __migrateEpoch;
        if (index >= migrateEpoch) {
            uint48 unlockAt = withdrawalUnlockAt(index, account);
            uint256 bucketIndex = _unlockToBucket.upperLookupRecent(unlockAt > 0 ? unlockAt - 1 : 0);
            return ERC4626Math.previewRedeem(
                withdrawalSharesOf(index, account), withdrawals(bucketIndex), withdrawalShares(bucketIndex)
            );
        }

        // Legacy support.
        return
            ERC4626Math.previewRedeem(
                _withdrawalSharesOf[index][account], __withdrawals[index], __withdrawalShares[index]
            );
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
        return _maxAllocatable().saturatingSub(adaptersAllocated);
    }

    /// @inheritdoc IVaultV2
    function adaptersOwe() public view returns (uint256) {
        return adaptersAllocated.saturatingSub(_maxAllocatable());
    }

    /// @inheritdoc IVaultV2
    function unclaimed() public view returns (uint256) {
        return uint256(int256(withdrawals(withdrawalBucket()) - activeWithdrawals()) + _unclaimedRaw);
    }

    /* PUBLIC FUNCTIONS (ACCOUNTING) */

    /// @inheritdoc IVaultV2
    function deposit(address onBehalfOf, uint256 amount)
        public
        nonReentrant
        returns (uint256 depositedAmount, uint256 mintedShares)
    {
        skimAdapters();

        _revertIfZero(onBehalfOf);
        if (depositWhitelist && !isDepositorWhitelisted[msg.sender]) {
            revert NotWhitelistedDepositor();
        }

        depositedAmount = _safeTransferIn(msg.sender, amount);

        if (isDepositLimit && activeStake() + depositedAmount > depositLimit) {
            revert DepositLimitReached();
        }

        uint256 curActiveStake = activeStake();
        uint256 curActiveShares = activeShares();

        mintedShares = ERC4626Math.previewDeposit(depositedAmount, curActiveShares, curActiveStake);
        _revertIfZero(mintedShares);

        _activeShares.push(uint48(block.timestamp), curActiveShares + mintedShares);
        _activeStake.push(uint48(block.timestamp), curActiveStake + depositedAmount);
        _activeSharesOf[onBehalfOf].push(uint48(block.timestamp), activeSharesOf(onBehalfOf) + mintedShares);

        emit Deposit(msg.sender, onBehalfOf, depositedAmount, mintedShares);
        emit Transfer(address(0), onBehalfOf, mintedShares);

        // Allocate only non-fee-on-transfer tokens.
        if (depositedAmount == amount && adapters.length > 0) {
            _allocateAdapter(adapters[0], depositedAmount);
        }
    }

    /// @inheritdoc IVaultV2
    function withdraw(address claimer, uint256 amount)
        public
        nonReentrant
        returns (uint256 burnedShares, uint256 mintedShares)
    {
        skimAdapters();

        _revertIfZero(claimer);
        _revertIfZero(amount);

        burnedShares = ERC4626Math.previewWithdraw(amount, activeShares(), activeStake());
        _revertIfZero(burnedShares);
        if (burnedShares > activeSharesOf(msg.sender)) {
            revert TooMuchWithdraw();
        }
        mintedShares = _withdraw(claimer, amount, burnedShares);
    }

    /// @inheritdoc IVaultV2
    function redeem(address claimer, uint256 shares)
        public
        nonReentrant
        returns (uint256 withdrawnAssets, uint256 mintedShares)
    {
        skimAdapters();

        _revertIfZero(claimer);
        _revertIfZero(shares);
        if (shares > activeSharesOf(msg.sender)) {
            revert TooMuchRedeem();
        }

        withdrawnAssets = ERC4626Math.previewRedeem(shares, activeStake(), activeShares());
        _revertIfZero(withdrawnAssets);
        mintedShares = _withdraw(claimer, withdrawnAssets, shares);
    }

    /// @inheritdoc IVaultV2
    function instantWithdraw(address recipient, uint256 amount)
        public
        nonReentrant
        returns (uint256 withdrawnAssets, uint256 burnedShares)
    {
        skimAdapters();

        _revertIfZero(recipient);

        uint256 curActiveStake = activeStake();
        uint256 curActiveShares = activeShares();
        uint256 curActiveSharesOf = activeSharesOf(msg.sender);

        withdrawnAssets = Math.min(amount, UniversalDelegator(delegator).getWithdrawalBuffer());

        burnedShares = ERC4626Math.previewWithdraw(withdrawnAssets, curActiveShares, curActiveStake);
        if (burnedShares > curActiveSharesOf) {
            revert TooMuchWithdraw();
        }

        _activeSharesOf[msg.sender].push(uint48(block.timestamp), curActiveSharesOf - burnedShares);
        _activeStake.push(uint48(block.timestamp), curActiveStake - withdrawnAssets);
        _activeShares.push(uint48(block.timestamp), curActiveShares - burnedShares);

        deallocateAdapters();

        if (_maxAllocatable() < adaptersAllocated) {
            revert InsufficientAmount();
        }

        uint256 fees =
            withdrawnAssets.fullMulDivUp(IFeeRegistry(FEE_REGISTRY).getInstantWithdrawFee(address(this)), MAX_FEE);
        if (fees > 0 && totalStake() > 0) {
            collateral.safeApprove(REWARDS, fees);
            IRewards(REWARDS).distributeDonationRewards(address(this), fees);
        }

        _safeTransferOut(recipient, withdrawnAssets - fees);

        emit InstantWithdraw(msg.sender, withdrawnAssets, burnedShares);
        emit Transfer(msg.sender, address(0), burnedShares);
    }

    /// @inheritdoc IVaultV2
    function claim(address recipient, uint256 index) public nonReentrant returns (uint256 amount) {
        deallocateAdapters();

        _revertIfZero(recipient);

        if (isWithdrawalsClaimed[index][msg.sender]) {
            revert AlreadyClaimed();
        }
        if (block.timestamp < withdrawalUnlockAt(index, msg.sender)) {
            revert WithdrawalNotMatured();
        }

        amount = withdrawalsOf(index, msg.sender);

        isWithdrawalsClaimed[index][msg.sender] = true;
        _unclaimedRaw -= int256(amount);

        // Keep claimable withdrawals from consuming liquidity reserved for
        // no-adapters backing and outstanding owed slashes.
        uint256 reserve = adaptersOwe();
        if (slasher != address(0)) {
            reserve = Math.max(reserve, UniversalSlasher(slasher).totalOwed());
        }
        if (unclaimed() < reserve) {
            revert InsufficientAmount();
        }

        _safeTransferOut(recipient, amount);

        emit Claim(msg.sender, recipient, index, amount);
    }

    /// @inheritdoc IVaultV2
    function claimBatch(address recipient, uint256[] calldata indexes) public returns (uint256 amount) {
        for (uint256 i; i < indexes.length; ++i) {
            amount += claim(recipient, indexes[i]);
        }
    }

    /// @dev Credit rewards donation into active stake after pulling collateral from the rewards address.
    function donate(uint256 amount) public {
        if (REWARDS != msg.sender) {
            revert NotRewards();
        }

        amount = _safeTransferIn(msg.sender, amount);

        uint256 curActiveStake = activeStake();
        uint256 curActiveWithdrawals = activeWithdrawals();
        uint256 withdrawalsDonated = amount.fullMulDiv(curActiveWithdrawals, curActiveStake + curActiveWithdrawals);

        if (withdrawalsDonated > 0) {
            _updateWithdrawalsSharePrice(curActiveWithdrawals + withdrawalsDonated);
        }
        _activeStake.push(uint48(block.timestamp), amount - withdrawalsDonated + curActiveStake);

        emit Donate(amount);
    }

    // @dev Internal dev function to handle slashing.
    function onSlash(uint256 amount, bool withAdapters)
        public
        nonReentrant
        returns (uint256 slashedAmount, uint256 owedAmount)
    {
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

            if (withAdapters) {
                deallocateAdapters();
                owedAmount = Math.min(slashedAmount, adaptersOwe());
            }
            if (slashedAmount > owedAmount) {
                _safeTransferOut(burner, slashedAmount - owedAmount);
            }
        }

        emit OnSlash(amount, slashedAmount);
    }

    /* INTERNAL FUNCTIONS (ACCOUNTING) */

    /// @dev Convert active shares into a withdrawal request.
    function _withdraw(address claimer, uint256 withdrawnAssets, uint256 burnedShares)
        internal
        virtual
        returns (uint256 mintedShares)
    {
        _activeSharesOf[msg.sender].push(uint48(block.timestamp), activeSharesOf(msg.sender) - burnedShares);
        _activeShares.push(uint48(block.timestamp), activeShares() - burnedShares);
        _activeStake.push(uint48(block.timestamp), activeStake() - withdrawnAssets);

        uint208 curWithdrawalBucket = withdrawalBucket();
        uint256 curWithdrawals = withdrawals(curWithdrawalBucket);
        uint256 curWithdrawalShares = withdrawalShares(curWithdrawalBucket);

        mintedShares = ERC4626Math.previewDeposit(withdrawnAssets, curWithdrawalShares, curWithdrawals);
        _revertIfZero(mintedShares);

        _withdrawalShares[curWithdrawalBucket].push(uint48(block.timestamp), curWithdrawalShares + mintedShares);
        _withdrawals[curWithdrawalBucket].push(uint48(block.timestamp), curWithdrawals + withdrawnAssets);

        uint48 unlockAt = uint48(block.timestamp) + epochDuration;
        uint256 curWithdrawalsOfLength = withdrawalsOfLength(claimer);

        _withdrawalsOfLength[claimer] = curWithdrawalsOfLength + 1;
        _withdrawalSharesOf[curWithdrawalsOfLength][claimer] = mintedShares;
        _withdrawalUnlockAt[curWithdrawalsOfLength][claimer] = unlockAt;
        _withdrawalSharesCumulative.push(unlockAt, _withdrawalSharesCumulative.latest() + mintedShares);
        _withdrawalSharesCumulativeOf[claimer].push(
            unlockAt, _withdrawalSharesCumulativeOf[claimer].latest() + mintedShares
        );

        emit Withdraw(msg.sender, claimer, withdrawnAssets, burnedShares, mintedShares, curWithdrawalsOfLength);
        emit Transfer(msg.sender, address(0), burnedShares);
    }

    /// @dev Reprice active withdrawals and roll claimable shares into a new bucket when a boundary is crossed.
    function _updateWithdrawalsSharePrice(uint256 newActiveWithdrawals) internal {
        uint208 curWithdrawalBucket = withdrawalBucket();
        uint256 curActiveWithdrawalShares = activeWithdrawalShares();
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
    function setAdapterLimit(address adapter, uint208 newLimit) public nonReentrant onlyRole(SET_ADAPTER_LIMIT_ROLE) {
        _revertIfZero(adapter);

        if (adapterAllocated[adapter] > newLimit) {
            revert AdapterAllocated();
        }

        uint256 numAdapters = adapters.length;
        if (newLimit > 0) {
            if (adapterLimit[adapter] == 0) {
                if (numAdapters + 1 > MAX_ADAPTERS) {
                    revert TooManyAdapters();
                }
                if (!IRegistry(ADAPTER_REGISTRY).isEntity(adapter)) {
                    revert NotAdapter();
                }
                adapters.push(adapter);
                _grantRoleIfNotZero(ALLOCATE_ADAPTER_ROLE, adapter);
                _grantRoleIfNotZero(DEALLOCATE_ADAPTER_ROLE, adapter);
            }
        } else {
            for (uint256 i; i < numAdapters; ++i) {
                if (adapter == adapters[i]) {
                    adapters[i] = adapters[numAdapters - 1];
                    adapters.pop();
                    super._revokeRole(ALLOCATE_ADAPTER_ROLE, adapter);
                    super._revokeRole(DEALLOCATE_ADAPTER_ROLE, adapter);
                    break;
                }
            }
        }
        adapterLimit[adapter] = newLimit;

        emit SetAdapterLimit(adapter, newLimit);
    }

    /// @inheritdoc IVaultV2
    function swapAdapters(address adapter1, address adapter2) public nonReentrant onlyRole(SWAP_ADAPTERS_ROLE) {
        uint256 index1 = type(uint256).max;
        uint256 index2 = type(uint256).max;
        uint256 numAdapters = adapters.length;
        for (uint256 i; i < numAdapters; ++i) {
            address curAdapter = adapters[i];
            if (adapter1 == curAdapter) {
                index1 = i;
            } else if (adapter2 == curAdapter) {
                index2 = i;
            }
        }
        require(index1 < type(uint256).max);
        require(index2 < type(uint256).max);
        (adapters[index1], adapters[index2]) = (adapters[index2], adapters[index1]);

        emit SwapAdapters(adapter1, adapter2);
    }

    /// @inheritdoc IVaultV2
    function allocateAdapter(address adapter, uint256 amount)
        public
        onlyRole(ALLOCATE_ADAPTER_ROLE)
        returns (uint256 allocated)
    {
        return _allocateAdapter(adapter, amount);
    }

    /// @dev Allocate collateral to a adapter within configured limits.
    function _allocateAdapter(address adapter, uint256 amount) internal returns (uint256 allocated) {
        allocated = Math.min(
            Math.min(Math.min(amount, adapterLimit[adapter] - adapterAllocated[adapter]), allocatable()),
            IAdapterBase(adapter).allocatable(address(this))
        );

        if (allocated > 0) {
            adaptersAllocated += allocated;
            adapterAllocated[adapter] += allocated;

            uint256 balanceBefore = collateral.balanceOf(adapter);
            _safeTransferOut(adapter, allocated);
            if (collateral.balanceOf(adapter) - balanceBefore < allocated) {
                revert FeeOnTransferNotSupported();
            }
            IAdapterBase(adapter).allocate(allocated);
        }

        emit Allocate(adapter, allocated);
    }

    /// @inheritdoc IVaultV2
    function deallocateAdapter(address adapter, uint256 amount)
        public
        onlyRole(DEALLOCATE_ADAPTER_ROLE)
        returns (uint256)
    {
        return _deallocateAdapter(adapter, amount);
    }

    /// @dev Deallocate collateral from a adapter and update accounting.
    function _deallocateAdapter(address adapter, uint256 amount) internal returns (uint256 deallocated) {
        deallocated = IAdapterBase(adapter).deallocate(amount);
        if (deallocated > 0) {
            _safeTransferIn(adapter, deallocated);

            adapterAllocated[adapter] -= deallocated;
            adaptersAllocated -= deallocated;
        }

        emit Deallocate(adapter, deallocated);
    }

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc IVaultV2
    function skimAdapters() public {
        for (uint256 i; i < adapters.length; ++i) {
            IAdapterBase(adapters[i]).skim(address(this));
        }
    }

    /// @inheritdoc IVaultV2
    function deallocateAdapters() public {
        for (uint256 i; i < adapters.length; ++i) {
            uint256 toDeallocate = adaptersOwe();
            if (toDeallocate == uint256(0)) {
                break;
            }
            address adapter = adapters[i];
            uint256 curAdapterAllocated = adapterAllocated[adapter];
            if (curAdapterAllocated > 0) {
                _deallocateAdapter(adapter, Math.min(curAdapterAllocated, toDeallocate));
            }
        }
    }

    /* INTERNAL FUNCTIONS (ADAPTERS) */

    /// @dev Get the vault stake that may still be allocated after reserving no-adapters capacity.
    function _maxAllocatable() internal view returns (uint256) {
        return totalStake().saturatingSub(UniversalDelegator(delegator).getNoAdaptersSize());
    }

    /// @inheritdoc AccessControlUpgradeable
    function _revokeRole(bytes32 role, address account) internal override returns (bool) {
        if (adapterLimit[account] > 0 && (role == ALLOCATE_ADAPTER_ROLE || role == DEALLOCATE_ADAPTER_ROLE)) {
            return false;
        }
        return super._revokeRole(role, account);
    }

    /* PUBLIC FUNCTIONS (INTERNAL LOGIC) */

    // @dev Internal dev function to handle owed slashing.
    function syncOwedSlash(uint256 amount) public nonReentrant returns (uint256 slashedAmount) {
        if (slasher != msg.sender) {
            revert NotSlasher();
        }

        deallocateAdapters();

        slashedAmount = Math.min(amount, UniversalSlasher(slasher).totalOwed().saturatingSub(adaptersOwe()));
        _safeTransferOut(burner, slashedAmount);

        emit SyncOwedSlash(slashedAmount);
    }

    /// @dev Set the vault delegator once after validating registry membership and vault linkage.
    function setDelegator(address newDelegator) public nonReentrant {
        if (_isDelegatorInitialized) {
            revert DelegatorAlreadyInitialized();
        }

        _validateEntity(newDelegator, DELEGATOR_FACTORY, UNIVERSAL_DELEGATOR_TYPE, InvalidDelegator.selector);

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
            _validateEntity(newSlasher, SLASHER_FACTORY, UNIVERSAL_SLASHER_TYPE, InvalidSlasher.selector);

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
        _activeSharesOf[to].push(uint48(block.timestamp), balanceOf(to) + value);

        emit Transfer(from, to, value);
    }

    /* INITIALIZATION */

    /// @dev Initialize vault state from encoded initialization parameters.
    function _initialize(uint64, address, bytes memory data) internal virtual override {
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
        _grantRoleIfNotZero(SET_ADAPTER_LIMIT_ROLE, params.setAdapterLimitRoleHolder);
        _grantRoleIfNotZero(SWAP_ADAPTERS_ROLE, params.swapAdaptersRoleHolder);
        _grantRoleIfNotZero(ALLOCATE_ADAPTER_ROLE, params.allocateAdapterRoleHolder);
        _grantRoleIfNotZero(DEALLOCATE_ADAPTER_ROLE, params.deallocateAdapterRoleHolder);

        emit Initialize(params);
    }

    /* MIGRATION */

    /// @dev Migrate vault state and deploy V2 delegator and slasher contracts.
    function _migrate(uint64 oldVersion, uint64, bytes calldata data) internal override {
        (bool success, bytes memory returnData) =
            VAULT_V2_MIGRATE.delegatecall(abi.encodeCall(VaultV2Migrate.migrate, (oldVersion, data)));
        if (!success) {
            assembly ("memory-safe") {
                revert(add(32, returnData), mload(returnData))
            }
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

    /// @dev Revert when an entity is invalid.
    function _validateEntity(address entity, address factory, uint64 minType, bytes4 errorSelector) internal view {
        if (
            !IRegistry(factory).isEntity(entity) || UniversalDelegator(entity).vault() != address(this)
                || IEntity(entity).TYPE() < minType
        ) {
            assembly ("memory-safe") {
                mstore(0x00, errorSelector)
                revert(0x00, 0x04)
            }
        }
    }

    /// @dev Grant a role when the holder address is not zero.
    function _grantRoleIfNotZero(bytes32 role, address holder) internal {
        if (holder != address(0)) {
            _grantRole(role, holder);
        }
    }

    /// @dev Transfer collateral from a source address to the vault.
    function _safeTransferIn(address from, uint256 amount) internal returns (uint256 amountIn) {
        uint256 balanceBefore = collateral.balanceOf(address(this));
        collateral.safeTransferFrom(from, address(this), amount);
        amountIn = collateral.balanceOf(address(this)) - balanceBefore;
        _revertIfZero(amountIn);
    }

    /// @dev Transfer collateral from the vault to a recipient address.
    function _safeTransferOut(address to, uint256 amount) internal {
        _revertIfZero(amount);
        collateral.safeTransfer(to, amount);
    }
}
