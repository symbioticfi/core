// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MigratableEntity} from "../common/MigratableEntity.sol";
import {WithdrawalQueue} from "./WithdrawalQueue.sol";

import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

import {IDelegator} from "../../interfaces/delegator/IDelegator.sol";
import {IEntity} from "../../interfaces/common/IEntity.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {
    IVaultV2,
    MAX_DURATION,
    DEPOSIT_WHITELIST_SET_ROLE,
    DEPOSITOR_WHITELIST_ROLE,
    IS_DEPOSIT_LIMIT_SET_ROLE,
    DEPOSIT_LIMIT_SET_ROLE,
    PERFORMANCE_FEE_SET_ROLE,
    PERFORMANCE_FEE_RECIPIENT_SET_ROLE,
    MANAGEMENT_FEE_SET_ROLE,
    MANAGEMENT_FEE_RECIPIENT_SET_ROLE,
    MAX_PERFORMANCE_FEE,
    MAX_MANAGEMENT_FEE,
    DECIMALS_OFFSET,
    WAD
} from "../../interfaces/vault/IVaultV2.sol";
import {GUARANTEES_DELEGATOR_TYPE} from "../../interfaces/delegator/IGuaranteesDelegator.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/// @title VaultV2
contract VaultV2 is MigratableEntity, AccessControlUpgradeable, ERC4626Upgradeable, IVaultV2 {
    using Math for uint256;
    using SafeERC20 for IERC20;
    using Checkpoints for Checkpoints.Trace208;
    using Checkpoints for Checkpoints.Trace256;

    /* IMMUTABLES */

    /// @dev Address of the rewards contract.
    address internal immutable REWARDS;
    /// @dev Address of the fee registry.
    address internal immutable FEE_REGISTRY;
    /// @dev Address of the slasher factory.
    address internal immutable SLASHER_FACTORY;
    /// @dev Address of the adapter registry.
    address internal immutable ADAPTER_REGISTRY;
    /// @dev Address of the delegator factory.
    address internal immutable DELEGATOR_FACTORY;
    /// @dev Address of the withdrawal queue implementation.
    address internal immutable WITHDRAWAL_QUEUE_IMPL;

    /* STATE VARIABLES */

    /// @inheritdoc IVaultV2
    address public burner;
    /// @inheritdoc IVaultV2
    address public delegator;
    /// @inheritdoc IVaultV2
    bool public isDepositLimit;
    /// @inheritdoc IVaultV2
    uint48 public epochDuration; // TODO: Remove?
    /// @inheritdoc IVaultV2
    uint256 public depositLimit;
    /// @inheritdoc IVaultV2
    bool public depositWhitelist;
    /// @inheritdoc IVaultV2
    address public withdrawalQueue;
    /// @inheritdoc IVaultV2
    mapping(address account => bool value) public isDepositorWhitelisted;

    /// @inheritdoc IVaultV2
    uint48 public lastUpdate;
    /// @inheritdoc IVaultV2
    uint96 public managementFee;
    /// @inheritdoc IVaultV2
    uint96 public performanceFee;
    /// @inheritdoc IVaultV2
    address public managementFeeRecipient;
    /// @inheritdoc IVaultV2
    address public performanceFeeRecipient;

    /// @dev Total assets cached from delegator accounting.
    uint256 internal _totalAssets;
    /// @dev Checkpointed total active shares.
    Checkpoints.Trace256 internal _totalSupply;
    /// @dev Checkpointed active shares per account.
    mapping(address account => Checkpoints.Trace256 shares) internal _balanceOf;

    /// @dev Reserved storage gap for future upgrades.
    uint256[50] internal __gap;

    /* MODIFIERS */

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
        address rewards,
        address feeRegistry,
        address vaultFactory,
        address slasherFactory,
        address adapterRegistry,
        address delegatorFactory,
        address withdrawalQueueImpl
    ) MigratableEntity(vaultFactory) {
        REWARDS = rewards;
        FEE_REGISTRY = feeRegistry;
        SLASHER_FACTORY = slasherFactory;
        ADAPTER_REGISTRY = adapterRegistry;
        DELEGATOR_FACTORY = delegatorFactory;
        WITHDRAWAL_QUEUE_IMPL = withdrawalQueueImpl;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IVaultV2
    function isInitialized() public view returns (bool) {
        return delegator != address(0);
    }

    /// @inheritdoc IVaultV2
    function slasher() public view returns (address) {
        return delegator;
    }

    /// @inheritdoc IVaultV2
    function collateral() public view returns (address) {
        return asset();
    }

    /// @inheritdoc IVaultV2
    function totalAssets() public view override(ERC4626Upgradeable, IVaultV2) returns (uint256 assets) {
        (assets,,) = getAccrueInterest();
    }

    /// @inheritdoc IVaultV2
    function activeStake() public view returns (uint256) {
        return totalAssets();
    }

    /// @inheritdoc IVaultV2
    function totalStake() public view returns (uint256) {
        return activeStake();
    }

    /// @inheritdoc IVaultV2
    function activeSharesAt(uint48 timestamp, bytes calldata) public view returns (uint256) {
        return _totalSupply.upperLookupRecent(timestamp);
    }

    /// @inheritdoc IVaultV2
    function activeShares() public view returns (uint256) {
        return totalSupply();
    }

    /// @inheritdoc IVaultV2
    function activeSharesOfAt(address account, uint48 timestamp, bytes calldata) public view returns (uint256) {
        return _balanceOf[account].upperLookupRecent(timestamp);
    }

    /// @inheritdoc IVaultV2
    function activeSharesOf(address account) public view returns (uint256) {
        return balanceOf(account);
    }

    /// @inheritdoc IVaultV2
    function activeBalanceOf(address account) public view returns (uint256) {
        return previewRedeem(balanceOf(account));
    }

    /// @inheritdoc IVaultV2
    function isWithdrawalsClaimed(uint256 tokenId, address) public view virtual returns (bool) {
        (, uint256 shares, uint256 claimedShares,) = WithdrawalQueue(withdrawalQueue).requests(tokenId);
        return claimedShares == shares;
    }

    /// @inheritdoc IVaultV2
    function withdrawalsOf(uint256, address) public pure returns (uint256) {
        return 0; // TODO
    }

    /// @inheritdoc IVaultV2
    function getAccrueInterest()
        public
        view
        returns (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares)
    {
        newTotalAssets = IDelegator(delegator).totalAssets();
        uint256 elapsed = block.timestamp - lastUpdate;
        uint256 interest = newTotalAssets.saturatingSub(_totalAssets);

        uint256 performanceFeeAssets = interest > 0 && performanceFee > 0 ? interest.mulDiv(performanceFee, WAD) : 0;
        uint256 managementFeeAssets =
            elapsed > 0 && managementFee > 0 ? (newTotalAssets * elapsed).mulDiv(managementFee, WAD) : 0;

        uint256 newTotalAssetsWithoutFees = newTotalAssets - performanceFeeAssets - managementFeeAssets;
        performanceFeeShares =
            performanceFeeAssets.mulDiv(totalSupply + 10 ** _decimalsOffset(), newTotalAssetsWithoutFees + 1);
        managementFeeShares =
            managementFeeAssets.mulDiv(totalSupply + 10 ** _decimalsOffset(), newTotalAssetsWithoutFees + 1);
    }

    /// @inheritdoc ERC4626Upgradeable
    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = getAccrueInterest();
        return assets.mulDiv(
            totalSupply + performanceFeeShares + managementFeeShares + 10 ** _decimalsOffset(), newTotalAssets + 1
        );
    }

    /// @inheritdoc ERC4626Upgradeable
    function previewMint(uint256 shares) public view virtual returns (uint256) {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = getAccrueInterest();
        return shares.mulDiv(
            newTotalAssets + 1,
            totalSupply + performanceFeeShares + managementFeeShares + 10 ** _decimalsOffset(),
            Math.Rounding.Ceil
        );
    }

    /// @inheritdoc ERC4626Upgradeable
    function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = getAccrueInterest();
        return assets.mulDiv(
            totalSupply + performanceFeeShares + managementFeeShares + 10 ** _decimalsOffset(),
            newTotalAssets + 1,
            Math.Rounding.Ceil
        );
    }

    /// @inheritdoc ERC4626Upgradeable
    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = getAccrueInterest();
        return shares.mulDiv(
            newTotalAssets + 1, totalSupply + performanceFeeShares + managementFeeShares + 10 ** _decimalsOffset()
        );
    }

    /* PUBLIC FUNCTIONS (ACCOUNTING) */

    /// @inheritdoc IVaultV2
    function accrueInterest() public {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = getAccrueInterest();

        _totalAssets = newTotalAssets;
        lastUpdate = uint48(block.timestamp);
        if (performanceFeeShares > 0) {
            _mint(performanceFeeRecipient, performanceFeeShares);
        }
        if (managementFeeShares > 0) {
            _mint(managementFeeRecipient, managementFeeShares);
        }

        emit AccrueInterest(newTotalAssets, performanceFeeShares, managementFeeShares);
    }

    /// @inheritdoc IVaultV2
    function deposit(address onBehalfOf, uint256 assets)
        public
        returns (uint256 depositedAmount, uint256 mintedShares)
    {
        return (assets, deposit(assets, onBehalfOf));
    }

    /// @inheritdoc IVaultV2
    function withdraw(address receiver, uint256 assets) public returns (uint256 burnedShares, uint256 mintedShares) {
        return (withdraw(assets, receiver, msg.sender), 0);
    }

    /// @inheritdoc IVaultV2
    function redeem(address receiver, uint256 shares) public returns (uint256 withdrawnAssets, uint256 mintedShares) {
        return (redeem(shares, receiver, msg.sender), 0);
    }

    /// @inheritdoc IVaultV2
    function claim(address receiver, uint256 tokenId) public returns (uint256 assets) {
        (assets,) = WithdrawalQueue(withdrawalQueue).claim(tokenId, type(uint256).max);
        emit Claim(msg.sender, receiver, tokenId, assets);
    }

    /// @inheritdoc IVaultV2
    function claimBatch(address receiver, uint256[] calldata indexes) public returns (uint256 assets) {
        for (uint256 i; i < indexes.length; ++i) {
            assets += claim(receiver, indexes[i]);
        }
    }

    /// @inheritdoc IVaultV2
    function pull(uint256 assets, address receiver) public {
        if (delegator != msg.sender) {
            revert NotDelegator();
        }

        IERC20(asset()).safeTransfer(receiver, assets);

        emit Pull(assets, receiver);
    }

    /// @inheritdoc IVaultV2
    function push(uint256 assets, address owner) public {
        if (delegator != msg.sender) {
            revert NotDelegator();
        }

        IERC20(asset()).safeTransferFrom(owner, address(this), assets);

        emit Push(assets, owner);
    }

    /// @dev Apply a delegator slash to vault accounting.
    function onSlash(uint256 assets) public returns (uint256 slashedAssets) {
        if (delegator != msg.sender) {
            revert NotDelegator();
        }

        slashedAssets = Math.min(assets, _totalAssets);
        _totalAssets -= slashedAssets;
    }

    /// @inheritdoc ERC4626Upgradeable
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        accrueInterest();

        super._deposit(caller, receiver, assets, shares);
        _totalAssets += assets;

        IDelegator(delegator).onDeposit(caller, receiver, assets, shares);

        WithdrawalQueue(withdrawalQueue).fill(assets);
    }

    /// @inheritdoc ERC4626Upgradeable
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        accrueInterest();

        IDelegator(delegator).onWithdraw(caller, receiver, owner, assets, shares);

        _totalAssets -= assets;
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    /* PUBLIC FUNCTIONS (CURATOR) */

    /// @inheritdoc IVaultV2
    function setDepositWhitelist(bool newStatus) public onlyRole(DEPOSIT_WHITELIST_SET_ROLE) {
        depositWhitelist = newStatus;
        emit SetDepositWhitelist(newStatus);
    }

    /// @inheritdoc IVaultV2
    function setDepositorWhitelistStatus(address account, bool newStatus) public onlyRole(DEPOSITOR_WHITELIST_ROLE) {
        if (account == address(0)) {
            revert InvalidAddress();
        }
        isDepositorWhitelisted[account] = newStatus;
        emit SetDepositorWhitelistStatus(account, newStatus);
    }

    /// @inheritdoc IVaultV2
    function setIsDepositLimit(bool newStatus) public onlyRole(IS_DEPOSIT_LIMIT_SET_ROLE) {
        isDepositLimit = newStatus;
        emit SetIsDepositLimit(newStatus);
    }

    /// @inheritdoc IVaultV2
    function setDepositLimit(uint256 newLimit) public onlyRole(DEPOSIT_LIMIT_SET_ROLE) {
        depositLimit = newLimit;
        emit SetDepositLimit(newLimit);
    }

    /// @inheritdoc IVaultV2
    function setPerformanceFee(uint256 newPerformanceFee) public onlyRole(PERFORMANCE_FEE_SET_ROLE) {
        if (newPerformanceFee > MAX_PERFORMANCE_FEE) {
            revert FeeTooHigh();
        }
        if (performanceFeeRecipient == address(0) && newPerformanceFee != 0) {
            revert FeeInvariantBroken();
        }

        accrueFees();

        performanceFee = uint96(newPerformanceFee);

        emit SetPerformanceFee(newPerformanceFee);
    }

    /// @inheritdoc IVaultV2
    function setPerformanceFeeRecipient(address newPerformanceFeeRecipient)
        public
        onlyRole(PERFORMANCE_FEE_RECIPIENT_SET_ROLE)
    {
        if (newPerformanceFeeRecipient == address(0) && performanceFee != 0) {
            revert FeeInvariantBroken();
        }

        accrueFees();

        performanceFeeRecipient = newPerformanceFeeRecipient;

        emit SetPerformanceFeeRecipient(newPerformanceFeeRecipient);
    }

    /// @inheritdoc IVaultV2
    function setManagementFee(uint256 newManagementFee) public onlyRole(MANAGEMENT_FEE_SET_ROLE) {
        if (newManagementFee > MAX_MANAGEMENT_FEE) {
            revert FeeTooHigh();
        }
        if (managementFeeRecipient == address(0) && newManagementFee != 0) {
            revert FeeInvariantBroken();
        }

        accrueFees();

        managementFee = uint96(newManagementFee);

        emit SetManagementFee(newManagementFee);
    }

    /// @inheritdoc IVaultV2
    function setManagementFeeRecipient(address newManagementFeeRecipient)
        public
        onlyRole(MANAGEMENT_FEE_RECIPIENT_SET_ROLE)
    {
        if (newManagementFeeRecipient == address(0) && managementFee != 0) {
            revert FeeInvariantBroken();
        }

        accrueFees();

        managementFeeRecipient = newManagementFeeRecipient;

        emit SetManagementFeeRecipient(newManagementFeeRecipient);
    }

    /* PUBLIC FUNCTIONS (INTERNAL) */

    /// @dev Set the vault delegator once after deployment.
    function setDelegator(address newDelegator) public {
        if (delegator != address(0)) {
            revert DelegatorAlreadyInitialized();
        }

        if (
            !IRegistry(DELEGATOR_FACTORY).isEntity(newDelegator) || IDelegator(newDelegator).vault() != address(this)
                || IEntity(newDelegator).TYPE() < GUARANTEES_DELEGATOR_TYPE
        ) {
            revert InvalidDelegator();
        }

        delegator = newDelegator;

        emit SetDelegator(newDelegator);
    }

    /* INITIALIZATION */

    /// @dev Initialize vault state from encoded initialization parameters.
    function _initialize(uint64, address, bytes memory data) internal virtual override {
        InitParams memory params = abi.decode(data, (InitParams));

        if (params.asset == address(0)) {
            revert InvalidCollateral();
        }

        if (params.epochDuration == uint48(0) || params.epochDuration > MAX_DURATION) {
            revert TooLongDuration();
        }
        if (params.depositorToWhitelist == address(0)) {
            revert InvalidDepositorToWhitelist();
        }

        __ERC20_init(params.name, params.symbol);
        __ERC4626_init(IERC20(params.asset));
        lastUpdate = uint48(block.timestamp);

        burner = params.burner;
        withdrawalQueue = address(
            new TransparentUpgradeableProxy(
                WITHDRAWAL_QUEUE_IMPL, address(this), abi.encodeCall(WithdrawalQueue.initialize, ())
            )
        );

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
        _grantRoleIfNotZero(PERFORMANCE_FEE_SET_ROLE, params.performanceFeeSetRoleHolder);
        _grantRoleIfNotZero(PERFORMANCE_FEE_RECIPIENT_SET_ROLE, params.performanceFeeRecipientSetRoleHolder);
        _grantRoleIfNotZero(MANAGEMENT_FEE_SET_ROLE, params.managementFeeSetRoleHolder);
        _grantRoleIfNotZero(MANAGEMENT_FEE_RECIPIENT_SET_ROLE, params.managementFeeRecipientSetRoleHolder);

        emit Initialize(params);
    }

    /* MIGRATION */

    /// @dev Migrate vault state and deploy V2 delegator and slasher contracts.
    function _migrate(uint64 oldVersion, uint64, bytes calldata data) internal override {
        revert();
    }

    /* UTILITY FUNCTIONS */

    /// @dev Update ERC20 balances and active share checkpoints.
    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);

        _totalSupply.push(uint48(block.timestamp), totalSupply());
        if (from != address(0)) {
            _balanceOf[from].push(uint48(block.timestamp), balanceOf(from));
        }
        if (to != address(0) && to != from) {
            _balanceOf[to].push(uint48(block.timestamp), balanceOf(to));
        }
    }

    /// @dev Grant a role when the holder address is not zero.
    function _grantRoleIfNotZero(bytes32 role, address holder) internal {
        if (holder != address(0)) {
            _grantRole(role, holder);
        }
    }

    /// @inheritdoc ERC4626Upgradeable
    function _decimalsOffset() internal view virtual override returns (uint8) {
        return DECIMALS_OFFSET;
    }
}
