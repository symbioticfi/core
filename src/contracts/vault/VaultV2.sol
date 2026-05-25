// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MigratableEntity} from "../common/MigratableEntity.sol";
import {UniversalDelegator} from "../delegator/UniversalDelegator.sol";
import {WithdrawalQueue} from "./WithdrawalQueue.sol";

import {IEntity} from "../../interfaces/common/IEntity.sol";
import {IProtocolFee} from "../../interfaces/vault/IProtocolFee.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {
    IVaultV2,
    DEPOSIT_WHITELIST_SET_ROLE,
    DEPOSITOR_WHITELIST_ROLE,
    IS_DEPOSIT_LIMIT_SET_ROLE,
    DEPOSIT_LIMIT_SET_ROLE,
    PERFORMANCE_FEE_ROLE,
    MANAGEMENT_FEE_ROLE,
    SHARES_DECIMALS,
    MAX_MANAGEMENT_FEE,
    MAX_PERFORMANCE_FEE,
    WAD
} from "../../interfaces/vault/IVaultV2.sol";
import {UNIVERSAL_DELEGATOR_TYPE} from "../../interfaces/delegator/IUniversalDelegator.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/// @title VaultV2
/// @dev Supports standard ERC20 collateral only; fee-on-transfer, rebasing, and other nonstandard balance-changing assets are unsupported.
contract VaultV2 is MigratableEntity, AccessControlUpgradeable, ERC4626Upgradeable, ERC20PermitUpgradeable, IVaultV2 {
    using Checkpoints for Checkpoints.Trace256;
    using Checkpoints for Checkpoints.Trace208;
    using SafeERC20 for IERC20;
    using Math for uint256;

    address internal constant DEAD_SHARES_RECIPIENT = 0x000000000000000000000000000000000000dEaD;
    uint256 internal constant MIN_DEAD_SHARES = 1e9;

    /* IMMUTABLES */

    /// @dev Address of the rewards contract.
    address internal immutable REWARDS;
    /// @inheritdoc IVaultV2
    address public immutable PROTOCOL_FEE;
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
    address public delegator;
    /// @inheritdoc IVaultV2
    bool public isDepositLimit;
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
    uint256 public virtualShares;
    /// @inheritdoc IVaultV2
    uint96 public lastProtocolFee;
    /// @inheritdoc IVaultV2
    address public managementFeeReceiver;
    /// @inheritdoc IVaultV2
    address public performanceFeeReceiver;
    /// @inheritdoc IVaultV2
    address public lastProtocolFeeReceiver;

    /// @dev Total assets cached from delegator accounting.
    uint256 internal _totalAssets;
    /// @dev Decimal offset between collateral and vault shares.
    uint8 internal __decimalsOffset;

    /// @dev Reserved storage gap for future upgrades.
    uint256[50] internal __gap;

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
        address protocolFee,
        address vaultFactory,
        address slasherFactory,
        address adapterRegistry,
        address delegatorFactory,
        address withdrawalQueueImpl
    ) MigratableEntity(vaultFactory) {
        REWARDS = rewards;
        PROTOCOL_FEE = protocolFee;
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
    function collateral() public view returns (address) {
        return asset();
    }

    /// @inheritdoc IERC20
    function totalSupply() public view override(ERC20Upgradeable, IERC20) returns (uint256) {
        (, uint256 performanceFeeShares, uint256 managementFeeShares, uint256 protocolFeeShares) = getAccrueInterest();
        return super.totalSupply() + protocolFeeShares + performanceFeeShares + managementFeeShares;
    }

    /// @inheritdoc IVaultV2
    function totalAssets() public view override(ERC4626Upgradeable, IVaultV2) returns (uint256 assets) {
        (assets,,,) = getAccrueInterest();
    }

    /// @inheritdoc ERC4626Upgradeable
    function decimals() public view override(ERC4626Upgradeable, ERC20Upgradeable, IERC20Metadata) returns (uint8) {
        return super.decimals();
    }

    /// @inheritdoc IERC20Permit
    function nonces(address owner) public view override(ERC20PermitUpgradeable, IERC20Permit) returns (uint256) {
        return super.nonces(owner);
    }

    /// @inheritdoc IVaultV2
    function activeBalanceOf(address account) public view returns (uint256) {
        return previewRedeem(balanceOf(account));
    }

    /// @inheritdoc IVaultV2
    function getAccrueInterest()
        public
        view
        returns (
            uint256 newTotalAssets,
            uint256 performanceFeeShares,
            uint256 managementFeeShares,
            uint256 protocolFeeShares
        )
    {
        newTotalAssets = IERC20(asset()).balanceOf(address(this)) + UniversalDelegator(delegator).totalAssets();
        uint256 elapsed = block.timestamp - lastUpdate;
        uint256 interest = newTotalAssets.saturatingSub(_totalAssets);

        uint256 performanceFeeAssets = interest > 0 && performanceFee > 0 && performanceFeeReceiver != address(0)
            ? interest.mulDiv(performanceFee, WAD)
            : 0;
        uint256 managementFeeAssets = elapsed > 0 && managementFee > 0 && managementFeeReceiver != address(0)
            ? (newTotalAssets * elapsed).mulDiv(managementFee, WAD)
            : 0;
        uint256 protocolFeeAssets = interest > 0 && lastProtocolFee > 0 && lastProtocolFeeReceiver != address(0)
            ? interest.mulDiv(lastProtocolFee, WAD)
            : 0;

        uint256 newTotalAssetsWithoutFees =
            newTotalAssets - performanceFeeAssets - managementFeeAssets - protocolFeeAssets;
        performanceFeeShares =
            performanceFeeAssets.mulDiv(super.totalSupply() + virtualShares, newTotalAssetsWithoutFees + 1);
        managementFeeShares =
            managementFeeAssets.mulDiv(super.totalSupply() + virtualShares, newTotalAssetsWithoutFees + 1);
        protocolFeeShares = protocolFeeAssets.mulDiv(super.totalSupply() + virtualShares, newTotalAssetsWithoutFees + 1);
    }

    /// @inheritdoc ERC4626Upgradeable
    function previewDeposit(uint256 assets)
        public
        view
        virtual
        override(ERC4626Upgradeable, IERC4626)
        returns (uint256)
    {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares, uint256 protocolFeeShares) =
            getAccrueInterest();
        return assets.mulDiv(
            super.totalSupply() + protocolFeeShares + performanceFeeShares + managementFeeShares + virtualShares,
            newTotalAssets + 1
        );
    }

    /// @inheritdoc ERC4626Upgradeable
    function previewMint(uint256 shares) public view virtual override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares, uint256 protocolFeeShares) =
            getAccrueInterest();
        return shares.mulDiv(
            newTotalAssets + 1,
            super.totalSupply() + protocolFeeShares + performanceFeeShares + managementFeeShares + virtualShares,
            Math.Rounding.Ceil
        );
    }

    /// @inheritdoc ERC4626Upgradeable
    function previewWithdraw(uint256 assets)
        public
        view
        virtual
        override(ERC4626Upgradeable, IERC4626)
        returns (uint256)
    {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares, uint256 protocolFeeShares) =
            getAccrueInterest();
        uint256 newTotalSupply = super.totalSupply() + protocolFeeShares + performanceFeeShares + managementFeeShares;
        return assets.mulDiv(newTotalSupply + virtualShares, newTotalAssets + 1, Math.Rounding.Ceil);
    }

    /// @inheritdoc ERC4626Upgradeable
    function previewRedeem(uint256 shares)
        public
        view
        virtual
        override(ERC4626Upgradeable, IERC4626)
        returns (uint256)
    {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares, uint256 protocolFeeShares) =
            getAccrueInterest();
        uint256 newTotalSupply = super.totalSupply() + protocolFeeShares + performanceFeeShares + managementFeeShares;
        return shares.mulDiv(newTotalAssets + 1, newTotalSupply + virtualShares);
    }

    /// @inheritdoc ERC4626Upgradeable
    function maxDeposit(address receiver) public view override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        if (depositWhitelist && !isDepositorWhitelisted[receiver]) {
            return 0;
        }
        return isDepositLimit ? depositLimit.saturatingSub(totalAssets()) : type(uint256).max;
    }

    /// @inheritdoc ERC4626Upgradeable
    function maxMint(address receiver) public view override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        uint256 assets = maxDeposit(receiver);
        if (assets == type(uint256).max) {
            return type(uint256).max;
        }
        return previewDeposit(assets);
    }

    /// @inheritdoc IVaultV2
    function withdrawable() public returns (uint256) {
        return freeAssets() + UniversalDelegator(delegator).deallocatable();
    }

    /* PUBLIC FUNCTIONS (ACCOUNTING) */

    /// @inheritdoc IVaultV2
    function accrueInterest()
        public
        returns (uint256 performanceFeeShares, uint256 managementFeeShares, uint256 protocolFeeShares)
    {
        (_totalAssets, performanceFeeShares, managementFeeShares, protocolFeeShares) = getAccrueInterest();
        if (performanceFeeShares > 0) {
            _mint(performanceFeeReceiver, performanceFeeShares);
        }
        if (managementFeeShares > 0) {
            _mint(managementFeeReceiver, managementFeeShares);
        }
        if (protocolFeeShares > 0) {
            _mint(lastProtocolFeeReceiver, protocolFeeShares);
        }

        _updateProtocolFee();
        lastUpdate = uint48(block.timestamp);

        emit AccrueInterest(_totalAssets, performanceFeeShares, managementFeeShares, protocolFeeShares);
    }

    /// @inheritdoc IVaultV2
    function pull(uint256 assets, address receiver) public {
        if (delegator != msg.sender) {
            revert NotDelegator();
        }
        accrueInterest();

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

    /// @inheritdoc ERC4626Upgradeable
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        accrueInterest();

        super._deposit(caller, receiver, assets, shares);
        _totalAssets += assets;

        UniversalDelegator(delegator).onDeposit();
    }

    /// @inheritdoc ERC4626Upgradeable
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override(ERC4626Upgradeable, IERC4626)
        returns (uint256)
    {
        accrueInterest();
        return super.withdraw(assets, receiver, owner);
    }

    /// @inheritdoc ERC4626Upgradeable
    function redeem(uint256 shares, address receiver, address owner)
        public
        override(ERC4626Upgradeable, IERC4626)
        returns (uint256)
    {
        accrueInterest();
        return super.redeem(shares, receiver, owner);
    }

    /// @inheritdoc ERC4626Upgradeable
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        UniversalDelegator(delegator).onWithdraw(assets.saturatingSub(freeAssets()));
        super._withdraw(caller, receiver, owner, assets, shares);
        _totalAssets -= assets;
    }

    function freeAssets() public view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
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
    function setPerformanceFee(uint96 newPerformanceFee, address newPerformanceFeeReceiver)
        public
        onlyRole(PERFORMANCE_FEE_ROLE)
    {
        if (newPerformanceFee > MAX_PERFORMANCE_FEE) {
            revert FeeTooHigh();
        }
        if (newPerformanceFeeReceiver == address(0) && newPerformanceFee != 0) {
            revert InvalidAddress();
        }
        accrueInterest();
        performanceFee = newPerformanceFee;
        performanceFeeReceiver = newPerformanceFeeReceiver;
        emit SetPerformanceFee(newPerformanceFee);
        emit SetPerformanceFeeReceiver(newPerformanceFeeReceiver);
    }

    /// @inheritdoc IVaultV2
    function setManagementFee(uint96 newManagementFee, address newManagementFeeReceiver)
        public
        onlyRole(MANAGEMENT_FEE_ROLE)
    {
        if (newManagementFee > MAX_MANAGEMENT_FEE) {
            revert FeeTooHigh();
        }
        if (newManagementFeeReceiver == address(0) && newManagementFee != 0) {
            revert InvalidAddress();
        }
        accrueInterest();
        managementFee = newManagementFee;
        managementFeeReceiver = newManagementFeeReceiver;
        emit SetManagementFee(newManagementFee, newManagementFeeReceiver);
    }

    /* PUBLIC FUNCTIONS (INTERNAL) */

    /// @dev Public one-shot initializer for a factory-registered delegator already bound to this vault.
    function setDelegator(address newDelegator) public {
        if (delegator != address(0)) {
            revert DelegatorAlreadyInitialized();
        }

        if (
            !IRegistry(DELEGATOR_FACTORY).isEntity(newDelegator)
                || UniversalDelegator(newDelegator).vault() != address(this)
                || IEntity(newDelegator).TYPE() < UNIVERSAL_DELEGATOR_TYPE
        ) {
            revert InvalidDelegator();
        }

        withdrawalQueue = address(
            new TransparentUpgradeableProxy(
                WITHDRAWAL_QUEUE_IMPL, address(this), abi.encodeCall(WithdrawalQueue.initialize, ())
            )
        );
        delegator = newDelegator;

        emit SetDelegator(newDelegator);
    }

    /// @inheritdoc IVaultV2
    function setSlasher(address) public {}

    /* INITIALIZATION */

    /// @dev Initialize vault state from encoded initialization parameters.
    function _initialize(uint64, address owner, bytes memory data) internal virtual override {
        InitParams memory params = abi.decode(data, (InitParams));

        if (params.asset == address(0)) {
            revert InvalidCollateral();
        }

        if (owner == address(0)) {
            revert InvalidAddress();
        }

        if (params.depositorToWhitelist == address(0)) {
            revert InvalidDepositorToWhitelist();
        }

        __ERC20_init(params.name, params.symbol);
        __ERC4626_init(IERC20(params.asset));
        __ERC20Permit_init(params.name);
        __decimalsOffset = uint8(uint256(SHARES_DECIMALS).saturatingSub(IERC20Metadata(params.asset).decimals()));
        virtualShares = 10 ** __decimalsOffset;
        lastUpdate = uint48(block.timestamp);
        _updateProtocolFee();

        uint256 deadShares = Math.max(MIN_DEAD_SHARES, 10 ** (6 + __decimalsOffset));
        uint256 assets = deadShares.mulDiv(1, virtualShares, Math.Rounding.Ceil);
        IERC20(params.asset).safeTransferFrom(owner, address(this), assets);
        _totalAssets = assets;
        _mint(DEAD_SHARES_RECIPIENT, deadShares);

        depositWhitelist = params.depositWhitelist;
        isDepositorWhitelisted[params.depositorToWhitelist] = true;

        isDepositLimit = params.isDepositLimit;
        depositLimit = params.depositLimit;

        _grantRoleIfNotZero(DEFAULT_ADMIN_ROLE, params.defaultAdminRoleHolder);
        _grantRoleIfNotZero(DEPOSIT_WHITELIST_SET_ROLE, params.depositWhitelistSetRoleHolder);
        _grantRoleIfNotZero(DEPOSITOR_WHITELIST_ROLE, params.depositorWhitelistRoleHolder);
        _grantRoleIfNotZero(IS_DEPOSIT_LIMIT_SET_ROLE, params.isDepositLimitSetRoleHolder);
        _grantRoleIfNotZero(DEPOSIT_LIMIT_SET_ROLE, params.depositLimitSetRoleHolder);
        _grantRoleIfNotZero(PERFORMANCE_FEE_ROLE, params.performanceFeeRoleHolder);
        _grantRoleIfNotZero(MANAGEMENT_FEE_ROLE, params.managementFeeRoleHolder);

        emit Initialize(params);
    }

    /* MIGRATION */

    /// @dev Migration is intentionally unsupported for this implementation.
    function _migrate(uint64, uint64, bytes calldata) internal pure override {
        revert();
    }

    /* UTILITY FUNCTIONS */

    /// @dev Grant a role when the holder address is not zero.
    function _grantRoleIfNotZero(bytes32 role, address holder) internal {
        if (holder != address(0)) {
            _grantRole(role, holder);
        }
    }

    /// @dev Cache protocol fee config for the next accrual window.
    function _updateProtocolFee() internal {
        lastProtocolFee = uint96(IProtocolFee(PROTOCOL_FEE).getFee(address(this)));
        lastProtocolFeeReceiver = IProtocolFee(PROTOCOL_FEE).getReceiver(address(this));
    }

    /// @inheritdoc ERC4626Upgradeable
    function _decimalsOffset() internal view virtual override returns (uint8) {
        return __decimalsOffset;
    }
}
