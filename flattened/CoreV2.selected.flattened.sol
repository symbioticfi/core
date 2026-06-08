// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

// Flattened review artifact generated from selected core/V2 adapter contracts only.
// External dependencies, interfaces, and OpenZeppelin sources are intentionally omitted.

// ============================================================================
// Source: src/contracts/vault/VaultV2.sol
// ============================================================================





/// @title VaultV2
/// @dev Supports standard ERC20 assets only; fee-on-transfer, rebasing, and other nonstandard balance-changing assets are unsupported.
contract VaultV2 is
    MigratableEntity,
    AccessControlUpgradeable,
    ERC4626Upgradeable,
    ERC20PermitUpgradeable,
    Multicallable,
    IVaultV2
{
    using Checkpoints for Checkpoints.Trace256;
    using Checkpoints for Checkpoints.Trace208;
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* IMMUTABLES */

    /// @dev Address of the delegator factory.
    address internal immutable DELEGATOR_FACTORY;
    /// @dev Address of the protocol fee registry.
    address internal immutable PROTOCOL_FEE_REGISTRY;
    /// @dev Address of the withdrawal queue factory.
    address internal immutable WITHDRAWAL_QUEUE_FACTORY;

    /* STATE VARIABLES */

    /// @inheritdoc IVaultV2
    address public withdrawalQueue;
    /// @inheritdoc IVaultV2
    address public delegator;

    /// @dev Decimal offset between assets and vault shares.
    uint8 internal __decimalsOffset;

    /// @inheritdoc IVaultV2
    uint48 public lastUpdate;
    /// @inheritdoc IVaultV2
    bool public isDepositLimit;
    /// @inheritdoc IVaultV2
    bool public depositWhitelist;
    /// @inheritdoc IVaultV2
    uint256 public depositLimit;
    /// @inheritdoc IVaultV2
    mapping(address account => bool value) public isDepositorWhitelisted;

    /// @inheritdoc IVaultV2
    uint96 public managementFee;
    /// @inheritdoc IVaultV2
    address public managementFeeReceiver;
    /// @inheritdoc IVaultV2
    uint96 public performanceFee;
    /// @inheritdoc IVaultV2
    address public performanceFeeReceiver;
    /// @inheritdoc IVaultV2
    uint96 public lastProtocolManagementFee;
    /// @inheritdoc IVaultV2
    address public lastProtocolFeeReceiver;
    /// @inheritdoc IVaultV2
    uint96 public lastProtocolPerformanceFee;

    /// @dev Total assets cached from delegator accounting.
    uint256 internal _totalAssets;
    /// @dev Total active share checkpoints.
    Checkpoints.Trace256 internal _totalSupply;
    /// @dev Active share checkpoints by account.
    mapping(address account => Checkpoints.Trace256) internal _balances;

    /// @dev Reserved storage gap for future upgrades.
    uint256[50] internal __gap;

    /* CONSTRUCTOR */

    constructor(
        address vaultFactory,
        address delegatorFactory,
        address protocolFeeRegistry,
        address withdrawalQueueFactory
    ) MigratableEntity(vaultFactory) {
        DELEGATOR_FACTORY = delegatorFactory;
        PROTOCOL_FEE_REGISTRY = protocolFeeRegistry;
        WITHDRAWAL_QUEUE_FACTORY = withdrawalQueueFactory;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IVaultV2
    function isInitialized() public view returns (bool) {
        return delegator != address(0);
    }

    /// @inheritdoc IERC20
    function totalSupply() public view override(ERC20Upgradeable, IERC20) returns (uint256) {
        (, uint256 managementFeeShares, uint256 performanceFeeShares, uint256 protocolFeeShares) = getAccrueInterest();
        return _totalSupply.latest() + managementFeeShares + performanceFeeShares + protocolFeeShares;
    }

    /// @inheritdoc IVaultV2
    function totalSupplyAt(uint48 timestamp) public view returns (uint256) {
        return _totalSupply.upperLookupRecent(timestamp);
    }

    /// @inheritdoc ERC4626Upgradeable
    function totalAssets() public view override returns (uint256 assets) {
        (assets,,,) = getAccrueInterest();
    }

    /// @inheritdoc ERC20Upgradeable
    function balanceOf(address account) public view override(ERC20Upgradeable, IERC20) returns (uint256) {
        return _balances[account].latest();
    }

    /// @inheritdoc IVaultV2
    function balanceOfAt(address account, uint48 timestamp) public view returns (uint256) {
        return _balances[account].upperLookupRecent(timestamp);
    }

    /// @inheritdoc IVaultV2
    function getAccrueInterest()
        public
        view
        returns (
            uint256 newTotalAssets,
            uint256 managementFeeShares,
            uint256 performanceFeeShares,
            uint256 protocolFeeShares
        )
    {
        newTotalAssets = freeAssets() + UniversalDelegator(delegator).totalAssets();
        uint256 elapsed = block.timestamp - lastUpdate;
        uint256 interest = newTotalAssets.saturatingSub(_totalAssets);

        uint256 managementFeeAssets = elapsed > 0 && managementFee > 0 && managementFeeReceiver != address(0)
            ? (newTotalAssets * elapsed).mulDiv(managementFee, MAX_FEE)
            : 0;
        uint256 performanceFeeAssets = interest > 0 && performanceFee > 0 && performanceFeeReceiver != address(0)
            ? interest.mulDiv(performanceFee, MAX_FEE)
            : 0;
        uint256 protocolManagementFeeAssets = elapsed > 0 && lastProtocolManagementFee > 0
            && lastProtocolFeeReceiver != address(0)
            ? (newTotalAssets * elapsed).mulDiv(lastProtocolManagementFee, MAX_FEE)
            : 0;
        uint256 protocolPerformanceFeeAssets = interest > 0 && lastProtocolPerformanceFee > 0
            && lastProtocolFeeReceiver != address(0)
            ? interest.mulDiv(lastProtocolPerformanceFee, MAX_FEE)
            : 0;
        uint256 protocolFeeAssets = protocolManagementFeeAssets + protocolPerformanceFeeAssets;

        uint256 newTotalAssetsWithoutFees =
            newTotalAssets - managementFeeAssets - performanceFeeAssets - protocolFeeAssets;
        managementFeeShares =
            managementFeeAssets.mulDiv(_totalSupply.latest() + 10 ** _decimalsOffset(), newTotalAssetsWithoutFees + 1);
        performanceFeeShares =
            performanceFeeAssets.mulDiv(_totalSupply.latest() + 10 ** _decimalsOffset(), newTotalAssetsWithoutFees + 1);
        protocolFeeShares =
            protocolFeeAssets.mulDiv(_totalSupply.latest() + 10 ** _decimalsOffset(), newTotalAssetsWithoutFees + 1);
    }

    /// @inheritdoc ERC4626Upgradeable
    function maxDeposit(address) public view override returns (uint256) {
        if (depositWhitelist && !isDepositorWhitelisted[msg.sender]) {
            return 0;
        }
        return isDepositLimit ? depositLimit.saturatingSub(totalAssets()) : type(uint256).max;
    }

    /// @inheritdoc ERC4626Upgradeable
    function maxMint(address receiver) public view override returns (uint256) {
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

    /// @inheritdoc IVaultV2
    function redeemable() public returns (uint256) {
        return previewWithdraw(withdrawable());
    }

    /// @inheritdoc IVaultV2
    function freeAssets() public view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    /// @inheritdoc ERC4626Upgradeable
    function _decimalsOffset() internal view virtual override returns (uint8) {
        return __decimalsOffset;
    }

    /// @inheritdoc ERC4626Upgradeable
    function decimals() public view override(ERC4626Upgradeable, ERC20Upgradeable) returns (uint8) {
        return super.decimals();
    }

    /* PUBLIC FUNCTIONS (ACCOUNTING) */

    /// @inheritdoc IVaultV2
    function accrueInterest()
        public
        returns (uint256 managementFeeShares, uint256 performanceFeeShares, uint256 protocolFeeShares)
    {
        (_totalAssets, managementFeeShares, performanceFeeShares, protocolFeeShares) = getAccrueInterest();
        if (managementFeeShares > 0) {
            _mint(managementFeeReceiver, managementFeeShares);
        }
        if (performanceFeeShares > 0) {
            _mint(performanceFeeReceiver, performanceFeeShares);
        }
        if (protocolFeeShares > 0) {
            _mint(lastProtocolFeeReceiver, protocolFeeShares);
        }

        lastUpdate = uint48(block.timestamp);
        _updateProtocolFee();

        emit AccrueInterest(_totalAssets, managementFeeShares, performanceFeeShares, protocolFeeShares);
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
    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        accrueInterest();
        return super.withdraw(assets, receiver, owner);
    }

    /// @inheritdoc ERC4626Upgradeable
    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
        accrueInterest();
        return super.redeem(shares, receiver, owner);
    }

    /// @inheritdoc ERC4626Upgradeable
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        // Fulfill withdrawal queue requests before allowing to do an instant redeem.
        // msg.sender check - to avoid recursion.
        if (withdrawalQueue != msg.sender) {
            if (UniversalDelegator(delegator).sweepPending() > 0) {
                revert PendingWithdrawalQueue();
            }
        }
        uint256 toWithdraw = assets.saturatingSub(freeAssets());
        if (toWithdraw > 0) {
            UniversalDelegator(delegator).onWithdraw(toWithdraw);
        }
        super._withdraw(caller, receiver, owner, assets, shares);
        _totalAssets -= assets;
    }

    /// @inheritdoc ERC20Upgradeable
    function _update(address from, address to, uint256 value) internal override {
        if (from == address(0)) {
            // Overflow check required: The rest of the code assumes that totalSupply never overflows
            _totalSupply.push(uint48(block.timestamp), _totalSupply.latest() + value);
        } else {
            uint256 fromBalance = _balances[from].latest();
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                // Overflow not possible: value <= fromBalance <= totalSupply.
                _balances[from].push(uint48(block.timestamp), fromBalance - value);
            }
        }

        if (to == address(0)) {
            unchecked {
                // Overflow not possible: value <= totalSupply or value <= fromBalance <= totalSupply.
                _totalSupply.push(uint48(block.timestamp), _totalSupply.latest() - value);
            }
        } else {
            unchecked {
                // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
                _balances[to].push(uint48(block.timestamp), _balances[to].latest() + value);
            }
        }

        emit Transfer(from, to, value);
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
    function setManagementFee(uint96 newManagementFee, address newManagementFeeReceiver)
        public
        onlyRole(MANAGEMENT_FEE_ROLE)
    {
        if (newManagementFeeReceiver == address(0) && newManagementFee > 0) {
            revert InvalidAddress();
        }
        if (newManagementFee > MAX_MANAGEMENT_FEE) {
            revert FeeTooHigh();
        }
        accrueInterest();
        managementFee = newManagementFee;
        managementFeeReceiver = newManagementFeeReceiver;
        emit SetManagementFee(newManagementFee, newManagementFeeReceiver);
    }

    /// @inheritdoc IVaultV2
    function setPerformanceFee(uint96 newPerformanceFee, address newPerformanceFeeReceiver)
        public
        onlyRole(PERFORMANCE_FEE_ROLE)
    {
        if (newPerformanceFeeReceiver == address(0) && newPerformanceFee > 0) {
            revert InvalidAddress();
        }
        if (newPerformanceFee > MAX_PERFORMANCE_FEE) {
            revert FeeTooHigh();
        }
        accrueInterest();
        performanceFee = newPerformanceFee;
        performanceFeeReceiver = newPerformanceFeeReceiver;
        emit SetPerformanceFee(newPerformanceFee, newPerformanceFeeReceiver);
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
            revert InvalidAddress();
        }

        if (owner == address(0)) {
            revert InvalidAddress();
        }

        __ERC20_init(params.name, params.symbol);
        __ERC4626_init(IERC20(params.asset));
        __ERC20Permit_init(params.name);

        withdrawalQueue = WithdrawalQueueFactory(WITHDRAWAL_QUEUE_FACTORY)
            .create(WITHDRAWAL_QUEUE_VERSION, address(this), abi.encode(name(), symbol()));
        emit SetWithdrawalQueue(withdrawalQueue);

        __decimalsOffset = uint8(uint256(SHARES_DECIMALS).saturatingSub(IERC20Metadata(params.asset).decimals()));

        _updateProtocolFee();
        lastUpdate = uint48(block.timestamp);

        depositWhitelist = params.depositWhitelist;
        isDepositorWhitelisted[params.depositorToWhitelist] = true;

        depositLimit = params.depositLimit;
        isDepositLimit = params.isDepositLimit;

        _grantRoleIfNotZero(DEFAULT_ADMIN_ROLE, params.defaultAdminRoleHolder);
        _grantRoleIfNotZero(MANAGEMENT_FEE_ROLE, params.managementFeeRoleHolder);
        _grantRoleIfNotZero(PERFORMANCE_FEE_ROLE, params.performanceFeeRoleHolder);
        _grantRoleIfNotZero(DEPOSIT_LIMIT_SET_ROLE, params.depositLimitSetRoleHolder);
        _grantRoleIfNotZero(DEPOSITOR_WHITELIST_ROLE, params.depositorWhitelistRoleHolder);
        _grantRoleIfNotZero(IS_DEPOSIT_LIMIT_SET_ROLE, params.isDepositLimitSetRoleHolder);
        _grantRoleIfNotZero(DEPOSIT_WHITELIST_SET_ROLE, params.depositWhitelistSetRoleHolder);

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
        (address protocolFeeReceiver, uint96 protocolManagementFee, uint96 protocolPerformanceFee) =
            IProtocolFeeRegistry(PROTOCOL_FEE_REGISTRY).getFee(address(this));
        lastProtocolFeeReceiver = protocolFeeReceiver;
        lastProtocolManagementFee = protocolManagementFee;
        lastProtocolPerformanceFee = protocolPerformanceFee;

        emit UpdateProtocolFee(protocolFeeReceiver, protocolManagementFee, protocolPerformanceFee);
    }
}

// ============================================================================
// Source: src/contracts/vault/WithdrawalQueue.sol
// ============================================================================





/// @title Withdrawal Queue
/// @notice Holds pending share withdrawal requests as ERC721 positions.
contract WithdrawalQueue is MigratableEntity, ERC721Upgradeable, IWithdrawalQueue, Multicallable {
    using Checkpoints for Checkpoints.Trace256;
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using Math for uint256;

    /* STATE VARIABLES */

    /// @inheritdoc IWithdrawalQueue
    address public vault;
    /// @inheritdoc IWithdrawalQueue
    uint256 public totalRequested;
    /// @inheritdoc IWithdrawalQueue
    mapping(uint256 tokenId => WithdrawalRequest) public requests;
    /// @inheritdoc IWithdrawalQueue
    uint256 public totalRequests;

    /// @dev Cumulative filled shares to packed fill index and cumulative assets.
    Checkpoints.Trace256 internal _cumulSharesToCumulAssets;

    /* CONSTRUCTOR */

    constructor(address factory) MigratableEntity(factory) {}

    /* VIEW FUNCTIONS */

    /// @inheritdoc IWithdrawalQueue
    function totalFilled() public view returns (uint256) {
        return _cumulSharesToCumulAssets.at(uint32(_cumulSharesToCumulAssets.length() - 1))._key;
    }

    /// @inheritdoc IWithdrawalQueue
    function pendingShares() public view returns (uint256) {
        return totalRequested - totalFilled();
    }

    /// @inheritdoc IWithdrawalQueue
    function pendingAssets() public view returns (uint256) {
        return IERC4626(vault).previewRedeem(pendingShares());
    }

    /// @inheritdoc IWithdrawalQueue
    function isClaimed(uint256 tokenId) public view returns (bool) {
        WithdrawalRequest storage request = requests[tokenId];
        return request.sharesClaimed == request.shares;
    }

    /// @inheritdoc IWithdrawalQueue
    function claimable(uint256 tokenId) public view returns (uint256 assets, uint256 shares) {
        WithdrawalRequest storage request = requests[tokenId];

        if (request.sharesClaimed == request.shares) {
            return (0, 0);
        }

        uint256 startShares = request.prevRequestSum + request.sharesClaimed;
        uint256 endShares = Math.min(request.prevRequestSum + request.shares, totalFilled());
        shares = endShares.saturatingSub(startShares);
        if (shares == 0) {
            return (0, 0);
        }

        uint32 pos = uint32(_cumulSharesToCumulAssets.upperLookupRecent(startShares) >> 224);
        Checkpoints.Checkpoint256 memory checkpoint = _cumulSharesToCumulAssets.at(pos);
        Checkpoints.Checkpoint256 memory nextCheckpoint = _cumulSharesToCumulAssets.at(pos + 1);
        uint256 startAssets = uint224(checkpoint._value)
            + (startShares - checkpoint._key)
            .mulDiv(uint224(nextCheckpoint._value) - uint224(checkpoint._value), nextCheckpoint._key - checkpoint._key);

        pos = uint32(_cumulSharesToCumulAssets.upperLookupRecent(endShares - 1) >> 224);
        checkpoint = _cumulSharesToCumulAssets.at(pos);
        nextCheckpoint = _cumulSharesToCumulAssets.at(pos + 1);
        uint256 endAssets = uint224(checkpoint._value)
            + (endShares - checkpoint._key)
            .mulDiv(uint224(nextCheckpoint._value) - uint224(checkpoint._value), nextCheckpoint._key - checkpoint._key);

        assets = endAssets - startAssets;
    }

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc IWithdrawalQueue
    function requestRedeem(uint256 shares, address receiver) public returns (uint256 tokenId) {
        if (shares == 0) {
            revert ZeroShares();
        }

        IERC20(vault).safeTransferFrom(msg.sender, address(this), shares);

        tokenId = totalRequests++;
        requests[tokenId] = WithdrawalRequest({shares: shares, sharesClaimed: 0, prevRequestSum: totalRequested});
        totalRequested += shares;

        _mint(receiver, tokenId);

        emit RequestWithdraw(msg.sender, receiver, shares, tokenId);

        UniversalDelegator(VaultV2(vault).delegator()).sweepPending();
    }

    /// @inheritdoc IWithdrawalQueue
    function claim(uint256 tokenId) public returns (uint256 assets, uint256 shares) {
        (assets, shares) = claimable(tokenId);

        requests[tokenId].sharesClaimed += shares;

        IERC20(IERC4626(vault).asset()).safeTransfer(ownerOf(tokenId), assets);

        emit Claim(tokenId, assets, shares);
    }

    /// @inheritdoc IWithdrawalQueue
    function fill() public returns (uint256 assets, uint256 shares) {
        shares = pendingShares();
        if (shares == 0) {
            return (0, 0);
        }
        shares = Math.min(shares, IERC4626(vault).previewDeposit(VaultV2(vault).withdrawable()));
        if (shares == 0) {
            return (0, 0);
        }

        assets = IERC4626(vault).redeem(shares, address(this), address(this));

        _cumulSharesToCumulAssets.push(
            totalFilled() + shares,
            _cumulSharesToCumulAssets.length() << 224
                | (uint224(_cumulSharesToCumulAssets.latest()) + assets).toUint224()
        );

        emit Fill(assets, shares);
    }

    /* INITIALIZATION */

    /// @dev Initialize withdrawal queue metadata and bind it to a vault.
    function _initialize(uint64, address owner, bytes memory data) internal override {
        (string memory vaultName, string memory vaultSymbol) = abi.decode(data, (string, string));

        __ERC721_init(string.concat(vaultName, "(WQ)"), string.concat(vaultSymbol, "_WQ"));

        vault = owner;

        _cumulSharesToCumulAssets.push(0, 0);
    }

    /// @dev Migration is intentionally unsupported for this implementation.
    function _migrate(uint64, uint64, bytes calldata) internal pure override {
        revert();
    }
}

// ============================================================================
// Source: src/contracts/WithdrawalQueueFactory.sol
// ============================================================================




/// @title WithdrawalQueueFactory
/// @notice Factory contract for migratable withdrawal queue deployments.
contract WithdrawalQueueFactory is MigratablesFactory, IWithdrawalQueueFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

// ============================================================================
// Source: src/contracts/delegator/UniversalDelegator.sol
// ============================================================================





/// @title UniversalDelegator
/// @notice Simple delegator that allocates vault assets across ordered adapters.
contract UniversalDelegator is
    Entity,
    StaticDelegateCallable,
    Multicallable,
    AccessControlUpgradeable,
    ReentrancyGuardTransient,
    IUniversalDelegator
{
    using Math for uint256;

    /* IMMUTABLES */

    /// @dev Address of the vault factory.
    address internal immutable VAULT_FACTORY;
    /// @dev Address of the adapter registry.
    address internal immutable ADAPTER_REGISTRY;

    /* STATE VARIABLES */

    /// @inheritdoc IUniversalDelegator
    address public vault;
    /// @inheritdoc IUniversalDelegator
    uint16 public totalAdapters;
    /// @inheritdoc IUniversalDelegator
    address[] public adapters;
    /// @inheritdoc IUniversalDelegator
    uint16[] public adaptersWithPending;
    /// @inheritdoc IUniversalDelegator
    address[] public autoAllocateAdapters;
    /// @inheritdoc IUniversalDelegator
    mapping(uint16 index => address adapter) public indexToAdapter;
    /// @inheritdoc IUniversalDelegator
    mapping(address adapter => uint16 index) public adapterToIndex;

    /// @inheritdoc IUniversalDelegator
    mapping(address adapter => uint256 share) public shareLimitOf;
    /// @inheritdoc IUniversalDelegator
    mapping(address adapter => uint256 assets) public absoluteLimitOf;

    /// @dev Whether an adapter is currently configured.
    mapping(address adapter => bool status) internal _isAdapterAdded;

    /* CONSTRUCTOR */

    constructor(uint64 entityType, address vaultFactory, address adapterRegistry, address delegatorFactory)
        Entity(delegatorFactory, entityType)
    {
        VAULT_FACTORY = vaultFactory;
        ADAPTER_REGISTRY = adapterRegistry;
    }

    /// @inheritdoc IUniversalDelegator
    function VERSION() public pure returns (uint64) {
        return 2;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IUniversalDelegator
    function getAdaptersLength() public view returns (uint256) {
        return adapters.length;
    }

    /// @inheritdoc IUniversalDelegator
    function totalAssets() public view returns (uint256 assets) {
        for (uint256 i; i < adapters.length; ++i) {
            assets += IAdapter(adapters[i]).totalAssets();
        }
    }

    /// @inheritdoc IUniversalDelegator
    function limitOf(address adapter) public view returns (uint256) {
        return Math.min(absoluteLimitOf[adapter], VaultV2(vault).totalAssets().mulDiv(shareLimitOf[adapter], MAX_SHARE));
    }

    /// @inheritdoc IUniversalDelegator
    function deallocatable() public returns (uint256) {
        (, bytes memory returnDataInternal) = address(this)
            .call(abi.encodeCall(this.staticDelegateCall, (address(this), abi.encodeCall(this.__deallocateAll, ()))));
        (bool success, bytes memory returnData) = abi.decode(returnDataInternal, (bool, bytes));
        if (!success) {
            if (returnData.length == 0) revert();
            assembly {
                revert(add(32, returnData), mload(returnData))
            }
        }
        return abi.decode(returnData, (uint256));
    }

    /* PUBLIC FUNCTIONS (CURATOR) */

    /// @inheritdoc IUniversalDelegator
    function addAdapter(address adapter) public onlyRole(ADD_ADAPTER_ROLE) nonReentrant returns (uint16 index) {
        if (!IAdapterRegistry(ADAPTER_REGISTRY).isWhitelisted(vault, adapter)) {
            revert InvalidAdapter();
        }
        if (_isAdapterAdded[adapter]) {
            revert AlreadyAdded();
        }
        if (adapters.length == MAX_ADAPTERS) {
            revert TooManyAdapters();
        }
        index = adapterToIndex[adapter];
        if (index == 0) {
            index = ++totalAdapters;
            indexToAdapter[index] = adapter;
            adapterToIndex[adapter] = index;
        }
        adapters.push(adapter);
        _isAdapterAdded[adapter] = true;

        _grantRole(ALLOCATE_ROLE, adapter);
        _grantRole(DEALLOCATE_ROLE, adapter);

        emit AddAdapter(adapter, index);
    }

    /// @inheritdoc IUniversalDelegator
    function removeAdapter(address adapter) public onlyRole(REMOVE_ADAPTER_ROLE) nonReentrant {
        if (!_isAdapterAdded[adapter]) {
            revert InvalidAdapter();
        }
        if (IAdapter(adapter).totalAssets() > 0) {
            revert AdapterHasAssets();
        }
        _isAdapterAdded[adapter] = false;
        _removeOrdered(adapters, adapter);
        _removeOrdered(autoAllocateAdapters, adapter);

        uint16 index = adapterToIndex[adapter];
        for (uint256 i; i < adaptersWithPending.length; ++i) {
            if (adaptersWithPending[i] == index) {
                adaptersWithPending[i] = adaptersWithPending[adaptersWithPending.length - 1];
                adaptersWithPending.pop();
                break;
            }
        }

        _revokeRole(ALLOCATE_ROLE, adapter);
        _revokeRole(DEALLOCATE_ROLE, adapter);

        absoluteLimitOf[adapter] = 0;
        shareLimitOf[adapter] = 0;

        emit RemoveAdapter(adapter, index);
    }

    /// @inheritdoc IUniversalDelegator
    function setLimits(address adapter, uint256 assets, uint256 share)
        public
        onlyRole(SET_ADAPTER_LIMITS_ROLE)
        nonReentrant
    {
        _setLimits(adapter, assets, share);
    }

    /// @dev Set adapter limits and add the adapter to the ordered list on first use.
    function _setLimits(address adapter, uint256 assets, uint256 share) internal {
        if (!_isAdapterAdded[adapter]) {
            revert InvalidAdapter();
        }
        if (share > MAX_SHARE) {
            revert InvalidShareLimit();
        }

        absoluteLimitOf[adapter] = assets;
        shareLimitOf[adapter] = share;

        emit SetLimits(adapter, assets, share);
    }

    /// @inheritdoc IUniversalDelegator
    function swapAdapters(address adapter1, address adapter2) public onlyRole(SWAP_ADAPTERS_ROLE) nonReentrant {
        uint256 adapter1Pos = type(uint256).max;
        uint256 adapter2Pos = type(uint256).max;
        for (uint256 i; i < adapters.length; ++i) {
            if (adapters[i] == adapter1) {
                adapter1Pos = i;
            }
            if (adapters[i] == adapter2) {
                adapter2Pos = i;
            }
        }
        (adapters[adapter1Pos], adapters[adapter2Pos]) = (adapters[adapter2Pos], adapters[adapter1Pos]);
        emit SwapAdapters(adapter1, adapter2);
    }

    /// @inheritdoc IUniversalDelegator
    function setAutoAllocateAdapters(address[] calldata newAutoAllocateAdapters)
        public
        onlyRole(SET_AUTO_ALLOCATE_ADAPTERS_ROLE)
        nonReentrant
    {
        for (uint256 i; i < newAutoAllocateAdapters.length; ++i) {
            if (!_isAdapterAdded[newAutoAllocateAdapters[i]]) {
                revert InvalidAdapter();
            }
            for (uint256 j; j < i; ++j) {
                if (newAutoAllocateAdapters[j] == newAutoAllocateAdapters[i]) {
                    revert InvalidAdapter();
                }
            }
        }

        autoAllocateAdapters = newAutoAllocateAdapters;

        emit SetAutoAllocateAdapters(newAutoAllocateAdapters);
    }

    /// @inheritdoc IUniversalDelegator
    function allocate(address adapter, uint256 assets)
        public
        onlyRole(ALLOCATE_ROLE)
        nonReentrant
        returns (uint256 allocated)
    {
        if (sweepPending() > 0) {
            return 0;
        }
        return _allocate(adapter, assets);
    }

    /// @inheritdoc IUniversalDelegator
    function allocateAll(uint256 assets) public onlyRole(ALLOCATE_ROLE) nonReentrant returns (uint256 allocated) {
        if (sweepPending() > 0) {
            return 0;
        }
        return _allocateAll(assets);
    }

    /// @inheritdoc IUniversalDelegator
    function allocateExact(address adapter, uint256 assets)
        public
        onlyRole(ALLOCATE_ROLE)
        nonReentrant
        returns (uint256 allocated)
    {
        if (sweepPending() > 0) {
            return 0;
        }
        uint256 toDeallocate = assets.saturatingSub(VaultV2(vault).freeAssets());
        if (toDeallocate > _deallocateAll(toDeallocate)) {
            return 0;
        }
        return _allocate(adapter, assets);
    }

    /// @inheritdoc IUniversalDelegator
    function deallocate(address adapter, uint256 assets)
        public
        onlyRole(DEALLOCATE_ROLE)
        nonReentrant
        returns (uint256 deallocated)
    {
        deallocated = _deallocate(adapter, assets);
        sweepPending();
    }

    /// @inheritdoc IUniversalDelegator
    function deallocateAll(uint256 assets) public onlyRole(DEALLOCATE_ROLE) nonReentrant returns (uint256 deallocated) {
        deallocated = _deallocateAll(assets);
        sweepPending();
    }

    /// @inheritdoc IUniversalDelegator
    function deallocateExact(uint256 assets)
        public
        onlyRole(DEALLOCATE_ROLE)
        nonReentrant
        returns (uint256 deallocated)
    {
        if (sweepPending() > 0) {
            return 0;
        }
        return _deallocateAll(assets);
    }

    /// @inheritdoc IUniversalDelegator
    function forceDeallocate(address adapter, uint256 assets)
        public
        onlyRole(DEALLOCATE_ROLE)
        nonReentrant
        returns (uint256 deallocated, uint256 pending)
    {
        uint256 adapterTotalAssets = IAdapter(adapter).totalAssets();
        assets = Math.min(assets, adapterTotalAssets);

        // Try to deallocate full amount.
        deallocated = _deallocate(adapter, assets);

        // Request the remaining assets if deallocated is less than expected.
        if (deallocated < assets) {
            pending = assets - deallocated;
            _requestDeallocate(adapter, pending);
        }

        // Update the adapter's absolute limit to avoid new allocations.
        _setLimits(
            adapter,
            Math.min(absoluteLimitOf[adapter], adapterTotalAssets - deallocated - pending),
            shareLimitOf[adapter]
        );

        sweepPending();
    }

    /* PUBLIC FUNCTIONS (ADAPTER) */

    /// @inheritdoc IUniversalDelegator
    function decreaseLimits(uint256 assets, uint256 share) public nonReentrant {
        absoluteLimitOf[msg.sender] = absoluteLimitOf[msg.sender].saturatingSub(assets);
        shareLimitOf[msg.sender] = shareLimitOf[msg.sender].saturatingSub(share);

        emit DecreaseLimits(assets, share);
    }

    /* PUBLIC FUNCTIONS (INTERNAL) */

    /// @dev Called after all pending tried to be filled.
    /// @inheritdoc IUniversalDelegator
    function onDeposit() public nonReentrant {
        if (vault != msg.sender) {
            revert NotVault();
        }

        // Skip allocation while pending assets remain.
        if (sweepPending() > 0) {
            return;
        }

        _allocateAll(type(uint256).max);
    }

    /// @inheritdoc IUniversalDelegator
    function onWithdraw(uint256 assets) public nonReentrant {
        if (vault != msg.sender) {
            revert NotVault();
        }

        _deallocateAll(assets);
    }

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc IUniversalDelegator
    function sweepPending() public returns (uint256 pendingAssets) {
        address withdrawalQueue = VaultV2(vault).withdrawalQueue();

        // Try to sweep free assets as much as possible.
        for (uint256 i; i < adapters.length; ++i) {
            _deallocate(adapters[i], IAdapter(adapters[i]).freeAssets());
        }

        // Try to deallocate assets as much as possible to fill the queue.
        _deallocateAll(WithdrawalQueue(withdrawalQueue).pendingAssets().saturatingSub(VaultV2(vault).freeAssets()));
        WithdrawalQueue(withdrawalQueue).fill();

        // Fetch actual pending assets after filling the queue.
        pendingAssets = WithdrawalQueue(withdrawalQueue).pendingAssets();

        // Update requests or reset them.
        uint16[] memory previousAdaptersWithPending = adaptersWithPending;
        delete adaptersWithPending;

        // Request deallocation for remaining pending assets.
        uint256 remainingPendingAssets = pendingAssets;
        for (uint256 i; remainingPendingAssets > 0 && i < adapters.length; ++i) {
            address adapter = adapters[i];
            uint256 toRequest = Math.min(remainingPendingAssets, IAdapter(adapter).totalAssets());
            if (toRequest == 0) {
                continue;
            }
            _requestDeallocate(adapter, toRequest);
            adaptersWithPending.push(adapterToIndex[adapter]);
            remainingPendingAssets -= toRequest;
        }

        // Reset requests for adapters that are no longer pending.
        for (uint256 i; i < previousAdaptersWithPending.length; ++i) {
            bool found;
            for (uint256 j; j < adaptersWithPending.length; ++j) {
                if (previousAdaptersWithPending[i] == adaptersWithPending[j]) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                _requestDeallocate(indexToAdapter[previousAdaptersWithPending[i]], 0);
            }
        }
    }

    /* INITIALIZATION */

    /// @dev Initialize delegator state from encoded initialization parameters.
    function _initialize(bytes calldata data) internal override {
        (address initVault, bytes memory initData) = abi.decode(data, (address, bytes));

        if (!IRegistry(VAULT_FACTORY).isEntity(initVault)) {
            revert NotVault();
        }
        if (IMigratableEntity(initVault).version() < VAULT_V2_VERSION) {
            revert OldVault();
        }

        InitParams memory params = abi.decode(initData, (InitParams));

        vault = initVault;

        _grantRoleIfNotZero(ALLOCATE_ROLE, params.allocateRoleHolder);
        _grantRoleIfNotZero(DEALLOCATE_ROLE, params.deallocateRoleHolder);
        _grantRoleIfNotZero(ADD_ADAPTER_ROLE, params.addAdapterRoleHolder);
        _grantRoleIfNotZero(SWAP_ADAPTERS_ROLE, params.swapAdaptersRoleHolder);
        _grantRoleIfNotZero(DEFAULT_ADMIN_ROLE, params.defaultAdminRoleHolder);
        _grantRoleIfNotZero(REMOVE_ADAPTER_ROLE, params.removeAdapterRoleHolder);
        _grantRoleIfNotZero(SET_ADAPTER_LIMITS_ROLE, params.setAdapterLimitsRoleHolder);
        _grantRoleIfNotZero(SET_AUTO_ALLOCATE_ADAPTERS_ROLE, params.setAutoAllocateAdaptersRoleHolder);

        emit Initialize(params);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Allocate assets through the configured auto-allocation route.
    function _allocateAll(uint256 assets) internal returns (uint256 allocated) {
        for (uint256 i; i < autoAllocateAdapters.length && assets > 0; ++i) {
            uint256 curAllocated = _allocate(autoAllocateAdapters[i], assets);
            allocated += curAllocated;
            assets -= curAllocated;
        }
    }

    /// @dev Deallocate assets through the ordered adapter route.
    function _deallocateAll(uint256 assets) internal returns (uint256 deallocated) {
        for (uint256 i; i < adapters.length && assets > 0; ++i) {
            uint256 curDeallocated = _deallocate(adapters[i], assets);
            deallocated += curDeallocated;
            assets = assets.saturatingSub(curDeallocated);
        }
    }

    /// @dev Allocate vault assets to an adapter.
    function _allocate(address adapter, uint256 assets) internal returns (uint256 allocated) {
        assets = Math.min(assets, limitOf(adapter).saturatingSub(IAdapter(adapter).totalAssets()));
        assets = Math.min(assets, VaultV2(vault).freeAssets());
        assets = Math.min(assets, IAdapter(adapter).allocatable());

        VaultV2(vault).pull(assets, adapter);
        allocated = IAdapter(adapter).allocate(assets);
        if (allocated < assets) {
            VaultV2(vault).push(assets - allocated, adapter);
        }

        emit Allocate(adapter, allocated, IAdapter(adapter).totalAssets());
    }

    /// @dev Deallocate adapter assets back into the vault.
    function _deallocate(address adapter, uint256 assets) internal returns (uint256 deallocated) {
        deallocated = IAdapter(adapter).deallocate(assets);
        if (deallocated > 0) {
            VaultV2(vault).push(deallocated, adapter);
        }

        emit Deallocate(adapter, deallocated, IAdapter(adapter).totalAssets());
    }

    /// @dev Forwards a delayed deallocation request to an adapter and emits the request event.
    function _requestDeallocate(address adapter, uint256 assets) internal {
        IAdapter(adapter).requestDeallocate(assets);

        emit RequestDeallocate(adapter, assets);
    }

    /// @dev Grant a role when the holder address is not zero.
    function _grantRoleIfNotZero(bytes32 role, address holder) internal {
        if (holder != address(0)) {
            _grantRole(role, holder);
        }
    }

    /// @dev Remove a value from an ordered address array.
    function _removeOrdered(address[] storage values, address value) internal {
        for (uint256 i; i < values.length; ++i) {
            if (values[i] == value) {
                for (uint256 j = i; j < values.length - 1; ++j) {
                    values[j] = values[j + 1];
                }
                values.pop();
                return;
            }
        }
    }

    /// @dev Prevent manual adapter role revocation while an adapter is configured.
    function _revokeRole(bytes32 role, address account) internal override returns (bool) {
        if ((role == ALLOCATE_ROLE || role == DEALLOCATE_ROLE) && _isAdapterAdded[account]) {
            revert InvalidRole();
        }
        return super._revokeRole(role, account);
    }

    /// @dev Internal self-call target used by deallocatable().
    function __deallocateAll() public returns (uint256) {
        if (address(this) != msg.sender) {
            revert NotSelf();
        }
        return _deallocateAll(type(uint256).max);
    }
}

// ============================================================================
// Source: src/contracts/AdapterRegistry.sol
// ============================================================================




/// @title AdapterRegistry
/// @notice Registry contract for vault-scoped whitelisted adapter factories.
contract AdapterRegistry is Ownable, IAdapterRegistry {
    /* STATE VARIABLES */

    /// @inheritdoc IAdapterRegistry
    mapping(address vault => mapping(address adapter => bool status)) public isWhitelisted;

    /* CONSTRUCTOR */

    constructor(address newOwner) Ownable(newOwner) {}

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc IAdapterRegistry
    function setWhitelistedStatus(address vault, address adapter, bool status) public onlyOwner {
        isWhitelisted[vault][adapter] = status;

        emit SetWhitelistedStatus(vault, adapter, status);
    }
}

// ============================================================================
// Source: src/contracts/ProtocolFeeRegistry.sol
// ============================================================================




contract ProtocolFeeRegistry is Ownable, IProtocolFeeRegistry {
    /* STATE VARIABLES */

    /// @inheritdoc IProtocolFeeRegistry
    address public globalReceiver;
    /// @inheritdoc IProtocolFeeRegistry
    uint96 public globalManagementFee;
    /// @inheritdoc IProtocolFeeRegistry
    uint96 public globalPerformanceFee;
    /// @dev Vault-specific fee override data.
    mapping(address vault => Fee) public vaultFee;

    /* CONSTRUCTOR */

    constructor(address newOwner) Ownable(newOwner) {}

    /* VIEW FUNCTIONS */

    /// @inheritdoc IProtocolFeeRegistry
    function getFee(address vault) public view returns (address, uint96, uint96) {
        Fee storage fee = vaultFee[vault];
        if (fee.isEnabled) {
            return (fee.receiver, fee.managementFee, fee.performanceFee);
        }
        return (globalReceiver, globalManagementFee, globalPerformanceFee);
    }

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc IProtocolFeeRegistry
    function setGlobalFee(uint96 newGlobalManagementFee, uint96 newGlobalPerformanceFee) public onlyOwner {
        if (newGlobalManagementFee > MAX_MANAGEMENT_FEE || newGlobalPerformanceFee > MAX_PERFORMANCE_FEE) {
            revert FeeTooHigh();
        }
        if ((newGlobalManagementFee > 0 || newGlobalPerformanceFee > 0) && globalReceiver == address(0)) {
            revert InvalidReceiver();
        }
        globalManagementFee = newGlobalManagementFee;
        globalPerformanceFee = newGlobalPerformanceFee;
        emit SetGlobalFee(newGlobalManagementFee, newGlobalPerformanceFee);
    }

    /// @inheritdoc IProtocolFeeRegistry
    function setGlobalReceiver(address newGlobalReceiver) public onlyOwner {
        if (newGlobalReceiver == address(0)) {
            revert InvalidReceiver();
        }
        globalReceiver = newGlobalReceiver;
        emit SetGlobalReceiver(newGlobalReceiver);
    }

    /// @inheritdoc IProtocolFeeRegistry
    function setVaultFee(
        address vault,
        bool isEnabled,
        address newVaultReceiver,
        uint96 newVaultManagementFee,
        uint96 newVaultPerformanceFee
    ) public onlyOwner {
        if (newVaultManagementFee > MAX_MANAGEMENT_FEE || newVaultPerformanceFee > MAX_PERFORMANCE_FEE) {
            revert FeeTooHigh();
        }
        if (isEnabled && (newVaultManagementFee > 0 || newVaultPerformanceFee > 0) && newVaultReceiver == address(0)) {
            revert InvalidReceiver();
        }
        vaultFee[vault] = Fee({
            isEnabled: isEnabled,
            receiver: newVaultReceiver,
            managementFee: newVaultManagementFee,
            performanceFee: newVaultPerformanceFee
        });
        emit SetVaultFee(vault, isEnabled, newVaultReceiver, newVaultManagementFee, newVaultPerformanceFee);
    }
}

// ============================================================================
// Source: src/contracts/adapters/AdapterFactory.sol
// ============================================================================




/// @title AdapterFactory
/// @notice Migratable factory for one adapter family.
contract AdapterFactory is MigratablesFactory, IAdapterFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

// ============================================================================
// Source: src/contracts/adapters/Adapter.sol
// ============================================================================





/// @title Adapter
/// @notice Base contract for vault adapters with shared vault validation.
abstract contract Adapter is MigratableEntity, Multicallable, IAdapter {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @dev Vault factory used to validate adapter initialization vaults.
    address internal immutable VAULT_FACTORY;

    /* STATE VARIABLES */

    /// @inheritdoc IAdapter
    address public vault;

    /* MODIFIERS */

    modifier onlyDelegator() {
        if (IVaultV2(vault).delegator() != msg.sender) {
            revert NotVault();
        }
        _;
    }

    /* CONSTRUCTOR */

    constructor(address vaultFactory, address adapterFactory) MigratableEntity(adapterFactory) {
        VAULT_FACTORY = vaultFactory;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAdapter
    function allocatable() public view virtual returns (uint256) {
        return type(uint256).max;
    }

    /// @inheritdoc IAdapter
    function totalAssets() public view virtual returns (uint256);

    /// @inheritdoc IAdapter
    function freeAssets() public view virtual returns (uint256) {
        return IERC20(IERC4626(vault).asset()).balanceOf(address(this));
    }

    /* PUBLIC FUNCTIONS (INTERNAL) */

    /// @inheritdoc IAdapter
    function allocate(uint256 amount) public onlyDelegator returns (uint256) {
        return amount > 0 ? _allocate(amount) : 0;
    }

    /// @inheritdoc IAdapter
    function deallocate(uint256 amount) public virtual onlyDelegator returns (uint256) {
        uint256 curFreeAssets = freeAssets();
        return curFreeAssets + (curFreeAssets < amount ? _deallocate(amount - curFreeAssets) : 0);
    }

    /// @inheritdoc IAdapter
    function requestDeallocate(uint256 amount) public onlyDelegator {
        return _requestDeallocate(amount);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Allocates asset from the vault into the adapter position.
    function _allocate(uint256 amount) internal virtual returns (uint256) {}

    /// @dev Deallocates asset from the vault's adapter position.
    function _deallocate(uint256 amount) internal virtual returns (uint256) {}

    /// @dev Synchronizes adapter pending deallocation accounting.
    function _requestDeallocate(uint256 amount) internal virtual {}

    /* INITIALIZATION */

    /// @dev Initializes the adapter vault and adapter-specific state.
    function _initialize(uint64, address, bytes memory data) internal override {
        (address initVault, bytes memory initData) = abi.decode(data, (address, bytes));

        if (!IRegistry(VAULT_FACTORY).isEntity(initVault)) {
            revert InvalidVault();
        }

        vault = initVault;
        emit SetVault(initVault);

        IERC20(IERC4626(vault).asset()).forceApprove(initVault, type(uint256).max);

        __initialize(initVault, initData);
    }

    /// @dev Initializes adapter-specific state.
    function __initialize(address, bytes memory) internal virtual {}

    /* MIGRATION */

    /// @dev Migration is intentionally unsupported for this implementation.
    function _migrate(uint64, uint64, bytes calldata) internal pure override {
        revert();
    }

    /* STORAGE GAP */

    /// @dev Reserved storage gap for future upgrades.
    uint256[50] internal __gap;
}

// ============================================================================
// Source: src/contracts/adapters/AppAdapter.sol
// ============================================================================






/// @title AppAdapter
/// @notice Single network-operator guarantee adapter.
contract AppAdapter is Adapter, CoWSwapConverter, IAppAdapter {
    using Checkpoints for Checkpoints.Trace208;
    using Checkpoints for Checkpoints.Trace256;
    using Subnetwork for bytes32;
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* IMMUTABLES */

    /// @dev Network middleware service used to authorize slashes.
    address internal immutable NETWORK_MIDDLEWARE_SERVICE;

    /* STATE VARIABLES */

    /// @inheritdoc IAppAdapter
    address public burner;
    /// @inheritdoc IAppAdapter
    uint48 public duration;
    /// @inheritdoc IAppAdapter
    address public operator;
    /// @inheritdoc IAppAdapter
    bytes32 public subnetwork;
    /// @inheritdoc IAppAdapter
    address public asset;

    /// @dev Stakes for the configured pair.
    Stake[] internal _stakes;
    /// @dev Position of the current stake in the _stakes array.
    Checkpoints.Trace208 internal _stakePos;

    /* CONSTRUCTOR */

    constructor(
        address vaultFactory,
        address adapterFactory,
        address cowSwapSettlement,
        address networkMiddlewareService
    ) Adapter(vaultFactory, adapterFactory) CoWSwapConverter(cowSwapSettlement) {
        NETWORK_MIDDLEWARE_SERVICE = networkMiddlewareService;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAdapter
    function freeAssets() public view virtual override(Adapter, IAdapter) returns (uint256) {
        return totalAssets() - slashable();
    }

    /// @inheritdoc IAdapter
    function totalAssets() public view virtual override(Adapter, IAdapter) returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    /// @inheritdoc IAppAdapter
    function slashable() public view virtual returns (uint256) {
        return _slashable();
    }

    /// @dev Computes the slashable stake for the current stake.
    function _slashable() internal view returns (uint256) {
        Stake storage curStake = _stakes[_stakePos.latest()];
        return curStake.initialStake.saturatingSub(curStake.slashed.latest())
            .saturatingSub(curStake.debt.upperLookupRecent(uint48(block.timestamp)));
    }

    /// @inheritdoc IAppAdapter
    function stake() public view virtual returns (uint256) {
        Stake storage curStake = _stakes[_stakePos.latest()];
        return curStake.initialStake.saturatingSub(curStake.slashed.latest())
            .saturatingSub(curStake.debt.upperLookupRecent(uint48(block.timestamp) + duration - 1));
    }

    /// @inheritdoc IAppAdapter
    function stakeAt(uint48 timestamp) public view virtual returns (uint256) {
        Stake storage curStake = _stakes[_stakePos.upperLookupRecent(timestamp)];
        return curStake.initialStake.saturatingSub(curStake.slashed.upperLookupRecent(timestamp))
            .saturatingSub(curStake.debt.upperLookupRecent(uint48(timestamp) + duration - 1));
    }

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc IConverter
    function convert(address tokenIn, uint256 amountIn, address tokenOut, bytes calldata data)
        public
        virtual
        override(CoWSwapConverter, IConverter)
    {
        if (tokenIn == IERC4626(vault).asset()) {
            revert InvalidTokenIn();
        }
        if (tokenOut != IERC4626(vault).asset()) {
            revert InvalidTokenOut();
        }
        super.convert(tokenIn, amountIn, tokenOut, data);
    }

    /// @inheritdoc IAppAdapter
    function reward(address token, uint256 amount) public virtual override {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    /* PUBLIC FUNCTIONS (NETWORK) */

    /// @inheritdoc IAppAdapter
    function slash(uint256 amount) public virtual {
        if (INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).middleware(subnetwork.network()) != msg.sender) {
            revert NotNetworkMiddleware();
        }

        amount = Math.min(amount, _slashable());
        if (amount == 0) {
            revert InsufficientSlash();
        }

        Stake storage curStake = _stakes[_stakePos.latest()];
        curStake.slashed.push(uint48(block.timestamp), curStake.slashed.latest() + amount);

        // Decrease the adapter limits to avoid new allocations.
        IUniversalDelegator(IVaultV2(vault).delegator()).decreaseLimits(amount, 0);

        // Send slashed amount to the burner.
        _sendToBurner(amount);

        emit Slash(amount);
    }

    /// @inheritdoc IAppAdapter
    function release(uint256 amount) public virtual {
        if (
            subnetwork.network() != msg.sender
                && INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).middleware(subnetwork.network()) != msg.sender
        ) {
            revert NotNetworkOrMiddleware();
        }

        amount = Math.min(amount, _slashable());

        Stake storage curStake = _stakes[_stakePos.latest()];
        curStake.slashed.push(uint48(block.timestamp), curStake.slashed.latest() + amount);

        address delegator = IVaultV2(vault).delegator();
        // Stop new allocations by setting absolute limit to adjusted slashable amount.
        IUniversalDelegator(delegator)
            .decreaseLimits(
                IUniversalDelegator(delegator).absoluteLimitOf(address(this)).saturatingSub(_slashable()), 0
            );

        emit Release(amount);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Allocates an amount into a fresh stake checkpoint.
    function _allocate(uint256 amount) internal override returns (uint256) {
        if (amount == 0) {
            return 0;
        }

        _stakePos.push(uint48(block.timestamp), uint208(_stakes.length));
        _stakes.push().initialStake = totalAssets();

        return amount;
    }

    /// @dev Deallocates an amount that is not slashable.
    function _deallocate(uint256) internal pure override returns (uint256) {
        return 0;
    }

    /// @dev Requests delayed deallocation debt accounting.
    function _requestDeallocate(uint256 amount) internal virtual override {
        uint256 curSlashable = _slashable();

        // Reset stake, debt, and slashed when the debt was reduced enough.
        if (
            Math.min(IUniversalDelegator(IVaultV2(vault).delegator()).limitOf(address(this)), totalAssets())
                    .saturatingSub(amount) >= curSlashable
        ) {
            _stakePos.push(uint48(block.timestamp), uint208(_stakes.length));
            _stakes.push().initialStake = curSlashable;
        } else {
            Stake storage curStake = _stakes[_stakePos.latest()];
            // Keep increasing debt when the request grows.
            if (curStake.debt.latest() < amount) {
                curStake.debt.push(uint48(block.timestamp) + duration, amount);
            }
            // Keep existing debt when the request shrinks but cannot release the amount yet.
        }
    }

    /// @dev Sends slashed amount to the burner and invokes its hook.
    function _sendToBurner(uint256 amount) internal virtual {
        address curBurner = burner;
        IERC20(asset).safeTransfer(curBurner, amount);
        bytes memory burnerCalldata = abi.encodeCall(IBurner.onSlash, (subnetwork, operator, amount, 0));
        if (gasleft() < BURNER_RESERVE + BURNER_GAS_LIMIT * 64 / 63) {
            revert InsufficientBurnerGas();
        }
        assembly ("memory-safe") {
            pop(call(BURNER_GAS_LIMIT, curBurner, 0, add(burnerCalldata, 0x20), mload(burnerCalldata), 0, 0))
        }
    }

    /* INITIALIZATION */

    /// @dev Initializes the configured network-operator pair.
    function __initialize(address, bytes memory data) internal virtual override {
        InitParams memory params = abi.decode(data, (InitParams));

        __CoWSwapConverter_init(params.converters);

        asset = IERC4626(vault).asset();

        if (params.subnetwork == bytes32(0) || params.operator == address(0)) {
            revert InvalidNetOrOp();
        }
        if (params.duration == 0) {
            revert InvalidDuration();
        }
        if (params.burner == address(0)) {
            revert NoBurner();
        }

        burner = params.burner;
        duration = params.duration;
        operator = params.operator;
        subnetwork = params.subnetwork;

        _stakes.push();

        emit Initialize(params);
    }
}

// ============================================================================
// Source: src/contracts/adapters/MorphoVaultV2Adapter.sol
// ============================================================================





/// @title MorphoVaultV2Adapter
/// @notice VaultV2 adapter for Morpho ERC4626 vaults.
contract MorphoVaultV2Adapter is Adapter, CoWSwapConverter, MerklClaimer, IMorphoVaultV2Adapter {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* IMMUTABLES */

    /// @dev Morpho vault factory used for curator-side vault validation.
    address internal immutable MORPHO_VAULT_FACTORY;
    /// @dev Required Morpho adapter registry for configured vaults.
    address internal immutable MORPHO_ADAPTER_REGISTRY;

    /* STATE VARIABLES */

    /// @inheritdoc IMorphoVaultV2Adapter
    address public morphoVault;

    /* CONSTRUCTOR */

    constructor(
        address vaultFactory,
        address adapterFactory,
        address merklDistributor,
        address cowSwapSettlement,
        address morphoVaultFactory,
        address morphoAdapterRegistry
    ) Adapter(vaultFactory, adapterFactory) CoWSwapConverter(cowSwapSettlement) MerklClaimer(merklDistributor) {
        MORPHO_VAULT_FACTORY = morphoVaultFactory;
        MORPHO_ADAPTER_REGISTRY = morphoAdapterRegistry;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAdapter
    function totalAssets() public view override(Adapter, IAdapter) returns (uint256) {
        return
            freeAssets()
                + IMorphoVaultV2(morphoVault).previewRedeem(IMorphoVaultV2(morphoVault).balanceOf(address(this)));
    }

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc CoWSwapConverter
    function convert(address tokenIn, uint256 amountIn, address tokenOut, bytes calldata data) public virtual override {
        if (tokenIn == morphoVault || tokenIn == IERC4626(vault).asset()) {
            revert InvalidTokenIn();
        }
        if (tokenOut != IERC4626(vault).asset()) {
            revert InvalidTokenOut();
        }
        super.convert(tokenIn, amountIn, tokenOut, data);
    }

    /* PUBLIC FUNCTIONS (INTERNAL) */

    /// @dev Uses a self-call so zero-share deposits revert and roll back the Morpho transfer.
    function deposit(uint256 amount) public {
        if (address(this) != msg.sender) {
            revert NotSelf();
        }
        if (IMorphoVaultV2(morphoVault).deposit(amount, address(this)) == 0) {
            revert InsufficientAmount();
        }
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Deposits asset from the calling vault into the configured Morpho vault.
    function _allocate(uint256 amount) internal override returns (uint256) {
        try this.deposit(amount) {
            return amount;
        } catch {}
        return 0;
    }

    /// @dev Withdraws asset for the calling vault from the configured Morpho vault.
    function _deallocate(uint256 amount) internal override returns (uint256) {
        address liquidityAdapter = IMorphoVaultV2(morphoVault).liquidityAdapter();
        amount = Math.min(
            amount,
            Math.min(
                IMorphoVaultV2(morphoVault).previewRedeem(IMorphoVaultV2(morphoVault).balanceOf(address(this))),
                IERC20(IERC4626(vault).asset()).balanceOf(morphoVault)
                    + (liquidityAdapter == address(0) ? 0 : IMorphoLiquidityAdapter(liquidityAdapter).realAssets())
            )
        );
        if (amount == 0) {
            return 0;
        }

        try IMorphoVaultV2(morphoVault).withdraw(amount, address(this), address(this)) returns (uint256) {
            return amount;
        } catch {}
        return 0;
    }

    /* INITIALIZATION */

    /// @dev Initializes and permanently binds the Morpho vault.
    function __initialize(address, bytes memory data) internal override {
        InitParams memory params = abi.decode(data, (InitParams));

        __CoWSwapConverter_init(params.converters);

        if (
            params.morphoVault == address(0)
                || !IMorphoVaultV2Factory(MORPHO_VAULT_FACTORY).isVaultV2(params.morphoVault)
                || !IMorphoVaultV2(params.morphoVault).abdicated(IMorphoVaultV2.setAdapterRegistry.selector)
                || IMorphoVaultV2(params.morphoVault).adapterRegistry() != MORPHO_ADAPTER_REGISTRY
                || IMorphoVaultV2(params.morphoVault).asset() != IERC4626(vault).asset()
        ) {
            revert InvalidMorphoVault();
        }

        morphoVault = params.morphoVault;

        IERC20(IERC4626(vault).asset()).forceApprove(params.morphoVault, type(uint256).max);

        emit Initialize(params.morphoVault);
    }
}

// ============================================================================
// Source: src/contracts/adapters/AaveV3Adapter.sol
// ============================================================================





/// @title AaveV3Adapter
/// @notice VaultV2 adapter for Aave V3 supply positions.
contract AaveV3Adapter is Adapter, CoWSwapConverter, MerklClaimer, IAaveV3Adapter {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* IMMUTABLES */

    /// @dev Core Aave V3 pool.
    address internal immutable AAVE_POOL;

    /* STATE VARIABLES */

    /// @inheritdoc IAaveV3Adapter
    address public aToken;

    /* CONSTRUCTOR */

    constructor(
        address aavePool,
        address vaultFactory,
        address adapterFactory,
        address merklDistributor,
        address cowSwapSettlement
    ) Adapter(vaultFactory, adapterFactory) CoWSwapConverter(cowSwapSettlement) MerklClaimer(merklDistributor) {
        AAVE_POOL = aavePool;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAdapter
    function totalAssets() public view override(Adapter, IAdapter) returns (uint256) {
        return freeAssets() + IERC20(aToken).balanceOf(address(this));
    }

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc CoWSwapConverter
    function convert(address tokenIn, uint256 amountIn, address tokenOut, bytes calldata data) public virtual override {
        if (tokenIn == aToken || tokenIn == IERC4626(vault).asset()) {
            revert InvalidTokenIn();
        }
        if (tokenOut != IERC4626(vault).asset()) {
            revert InvalidTokenOut();
        }
        super.convert(tokenIn, amountIn, tokenOut, data);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Supplies asset from the calling vault into Aave.
    function _allocate(uint256 amount) internal override returns (uint256) {
        try IAaveV3Pool(AAVE_POOL).supply(IERC4626(vault).asset(), amount, address(this), REFERRAL_CODE) {
            return amount;
        } catch {}
        return 0;
    }

    /// @dev Withdraws asset for the calling vault from Aave when liquidity is available.
    function _deallocate(uint256 amount) internal override returns (uint256) {
        amount = Math.min(
            amount,
            Math.min(
                IERC20(aToken).balanceOf(address(this)),
                IAaveV3Pool(AAVE_POOL).getVirtualUnderlyingBalance(IERC4626(vault).asset())
            )
        );
        if (amount == 0) {
            return 0;
        }

        try IAaveV3Pool(AAVE_POOL).withdraw(IERC4626(vault).asset(), amount, address(this)) returns (uint256) {
            return amount;
        } catch {}
        return 0;
    }

    /* INITIALIZATION */

    /// @dev Approves the Aave pool to pull the adapter asset.
    function __initialize(address, bytes memory data) internal override {
        InitParams memory params = abi.decode(data, (InitParams));

        __CoWSwapConverter_init(params.converters);

        aToken = IAaveV3Pool(AAVE_POOL).getReserveAToken(IERC4626(vault).asset());
        if (aToken == address(0)) {
            revert InvalidAToken();
        }
        IERC20(IERC4626(vault).asset()).forceApprove(AAVE_POOL, type(uint256).max);
    }
}

