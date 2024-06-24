// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {MigratableEntity} from "src/contracts/base/MigratableEntity.sol";
import {VaultStorage} from "./VaultStorage.sol";

import {ICollateral} from "src/interfaces/base/ICollateral.sol";
import {INetworkMiddlewareService} from "src/interfaces/INetworkMiddlewareService.sol";
import {INetworkOptInService} from "src/interfaces/INetworkOptInService.sol";
import {IOperatorOptInService} from "src/interfaces/IOperatorOptInService.sol";
import {IRegistry} from "src/interfaces/base/IRegistry.sol";
import {IVault} from "src/interfaces/vault/v1/IVault.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";
import {ERC4626Math} from "src/contracts/libraries/ERC4626Math.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract Vault is VaultStorage, MigratableEntity, AccessControlUpgradeable, IVault {
    using Checkpoints for Checkpoints.Trace256;
    using Math for uint256;
    using SafeERC20 for IERC20;

    /**
     * @inheritdoc IVault
     */
    function totalSupplyIn(uint48 duration) public view returns (uint256) {
        uint256 epoch = currentEpoch();
        uint256 futureEpoch = epochAt(Time.timestamp() + duration);

        if (futureEpoch > epoch + 1) {
            return activeSupply();
        }

        if (futureEpoch > epoch) {
            return activeSupply() + withdrawals[futureEpoch];
        }

        return activeSupply() + withdrawals[epoch] + withdrawals[epoch + 1];
    }

    /**
     * @inheritdoc IVault
     */
    function totalSupply() public view returns (uint256) {
        uint256 epoch = currentEpoch();
        return activeSupply() + withdrawals[epoch] + withdrawals[epoch + 1];
    }

    /**
     * @inheritdoc IVault
     */
    function activeBalanceOfAt(address account, uint48 timestamp) public view returns (uint256) {
        return ERC4626Math.previewRedeem(
            activeSharesOfAt(account, timestamp), activeSupplyAt(timestamp), activeSharesAt(timestamp)
        );
    }

    /**
     * @inheritdoc IVault
     */
    function activeBalanceOf(address account) public view returns (uint256) {
        return ERC4626Math.previewRedeem(activeSharesOf(account), activeSupply(), activeShares());
    }

    /**
     * @inheritdoc IVault
     */
    function pendingWithdrawalsOf(uint256 epoch, address account) public view returns (uint256) {
        return ERC4626Math.previewRedeem(
            pendingWithdrawalSharesOf[epoch][account], withdrawals[epoch], withdrawalShares[epoch]
        );
    }

    /**
     * @inheritdoc IVault
     */
    function slashableAmountIn(
        address network,
        address resolver,
        address operator,
        uint48 duration
    ) public view returns (uint256) {
        return Math.min(
            totalSupplyIn(duration),
            Math.min(
                networkResolverLimitIn(network, resolver, duration), operatorNetworkLimitIn(operator, network, duration)
            )
        );
    }

    /**
     * @inheritdoc IVault
     */
    function slashableAmount(address network, address resolver, address operator) public view returns (uint256) {
        return Math.min(
            totalSupply(), Math.min(networkResolverLimit(network, resolver), operatorNetworkLimit(operator, network))
        );
    }

    /**
     * @inheritdoc IVault
     */
    function networkResolverLimitIn(address network, address resolver, uint48 duration) public view returns (uint256) {
        return _getLimitAt(
            _networkResolverLimit[network][resolver],
            nextNetworkResolverLimit[network][resolver],
            Time.timestamp() + duration
        );
    }

    /**
     * @inheritdoc IVault
     */
    function networkResolverLimit(address network, address resolver) public view returns (uint256) {
        return networkResolverLimitIn(network, resolver, 0);
    }

    /**
     * @inheritdoc IVault
     */
    function operatorNetworkLimitIn(address operator, address network, uint48 duration) public view returns (uint256) {
        return _getLimitAt(
            _operatorNetworkLimit[operator][network],
            nextOperatorNetworkLimit[operator][network],
            Time.timestamp() + duration
        );
    }

    /**
     * @inheritdoc IVault
     */
    function operatorNetworkLimit(address operator, address network) public view returns (uint256) {
        return operatorNetworkLimitIn(operator, network, 0);
    }

    /**
     * @inheritdoc IVault
     */
    function minStakeDuring(
        address network,
        address resolver,
        address operator,
        uint48 duration
    ) external view returns (uint256) {
        return Math.min(
            activeSupply(),
            Math.min(
                Math.min(networkResolverLimit(network, resolver), networkResolverLimitIn(network, resolver, duration)),
                Math.min(operatorNetworkLimit(operator, network), operatorNetworkLimitIn(operator, network, duration))
            )
        );
    }

    constructor(
        address vaultFactory,
        address networkRegistry,
        address networkMiddlewareService,
        address networkVaultOptInService,
        address operatorVaultOptInService,
        address operatorNetworkOptInService
    )
        MigratableEntity(vaultFactory)
        VaultStorage(
            networkRegistry,
            networkMiddlewareService,
            networkVaultOptInService,
            operatorVaultOptInService,
            operatorNetworkOptInService
        )
    {
        _disableInitializers();
    }

    /**
     * @inheritdoc IVault
     */
    function deposit(address onBehalfOf, uint256 amount) external returns (uint256 shares) {
        if (onBehalfOf == address(0)) {
            revert InvalidOnBehalfOf();
        }

        if (depositWhitelist && !isDepositorWhitelisted[msg.sender]) {
            revert NotWhitelistedDepositor();
        }

        if (amount == 0) {
            revert InsufficientDeposit();
        }

        IERC20(collateral).safeTransferFrom(msg.sender, address(this), amount);

        uint256 activeSupply_ = activeSupply();
        uint256 activeShares_ = activeShares();

        shares = ERC4626Math.previewDeposit(amount, activeShares_, activeSupply_);

        _activeSupplies.push(Time.timestamp(), activeSupply_ + amount);
        _activeShares.push(Time.timestamp(), activeShares_ + shares);
        _activeSharesOf[onBehalfOf].push(Time.timestamp(), activeSharesOf(onBehalfOf) + shares);

        if (firstDepositAt[onBehalfOf] == 0) {
            firstDepositAt[onBehalfOf] = Time.timestamp();
        }

        emit Deposit(msg.sender, onBehalfOf, amount, shares);
    }

    /**
     * @inheritdoc IVault
     */
    function withdraw(address claimer, uint256 amount) external returns (uint256 burnedShares, uint256 mintedShares) {
        if (claimer == address(0)) {
            revert InvalidClaimer();
        }

        if (amount == 0) {
            revert InsufficientWithdrawal();
        }

        uint256 activeSupply_ = activeSupply();
        uint256 activeShares_ = activeShares();
        uint256 activeSharesOf_ = activeSharesOf(msg.sender);

        burnedShares = ERC4626Math.previewWithdraw(amount, activeShares_, activeSupply_);
        if (burnedShares > activeSharesOf_) {
            revert TooMuchWithdraw();
        }

        _activeSupplies.push(Time.timestamp(), activeSupply_ - amount);
        _activeShares.push(Time.timestamp(), activeShares_ - burnedShares);
        _activeSharesOf[msg.sender].push(Time.timestamp(), activeSharesOf_ - burnedShares);

        uint256 epoch = currentEpoch() + 1;
        uint256 withdrawals_ = withdrawals[epoch];
        uint256 withdrawalsShares_ = withdrawalShares[epoch];

        mintedShares = ERC4626Math.previewDeposit(amount, withdrawalsShares_, withdrawals_);

        withdrawals[epoch] = withdrawals_ + amount;
        withdrawalShares[epoch] = withdrawalsShares_ + mintedShares;
        pendingWithdrawalSharesOf[epoch][claimer] += mintedShares;

        emit Withdraw(msg.sender, claimer, amount, burnedShares, mintedShares);
    }

    /**
     * @inheritdoc IVault
     */
    function claim(address recipient, uint256 epoch) external returns (uint256 amount) {
        if (recipient == address(0)) {
            revert InvalidRecipient();
        }

        if (epoch >= currentEpoch()) {
            revert InvalidEpoch();
        }

        amount = pendingWithdrawalsOf(epoch, msg.sender);

        if (amount == 0) {
            revert InsufficientClaim();
        }

        pendingWithdrawalSharesOf[epoch][msg.sender] = 0;

        IERC20(collateral).safeTransfer(recipient, amount);

        emit Claim(msg.sender, recipient, amount);
    }

    /**
     * @inheritdoc IVault
     */
    function requestSlash(
        address network,
        address resolver,
        address operator,
        uint256 amount
    ) external returns (uint256 slashIndex) {
        if (INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).middleware(network) != msg.sender) {
            revert NotNetworkMiddleware();
        }

        if (amount == 0) {
            revert InsufficientSlash();
        }

        if (!INetworkOptInService(NETWORK_VAULT_OPT_IN_SERVICE).isOptedIn(network, resolver, address(this))) {
            revert NetworkNotOptedInVault();
        }

        if (
            !IOperatorOptInService(OPERATOR_VAULT_OPT_IN_SERVICE).wasOptedInAfter(
                operator, address(this), currentEpoch() != 0 ? previousEpochStart() : currentEpochStart()
            )
        ) {
            revert OperatorNotOptedInVault();
        }

        if (
            !IOperatorOptInService(OPERATOR_NETWORK_OPT_IN_SERVICE).wasOptedInAfter(
                operator, network, currentEpoch() != 0 ? previousEpochStart() : currentEpochStart()
            )
        ) {
            revert OperatorNotOptedInNetwork();
        }

        uint48 vetoDeadline = Time.timestamp() + vetoDuration;
        uint48 executeDeadline = vetoDeadline + executeDuration;

        slashIndex = slashRequests.length;
        slashRequests.push(
            SlashRequest({
                network: network,
                resolver: resolver,
                operator: operator,
                amount: amount,
                vetoDeadline: vetoDeadline,
                executeDeadline: executeDeadline,
                completed: false
            })
        );

        emit RequestSlash(slashIndex, network, resolver, operator, amount, vetoDeadline, executeDeadline);
    }

    /**
     * @inheritdoc IVault
     */
    function executeSlash(uint256 slashIndex) external returns (uint256 slashedAmount) {
        if (slashIndex >= slashRequests.length) {
            revert SlashRequestNotExist();
        }

        SlashRequest storage request = slashRequests[slashIndex];

        if (request.resolver != address(0) && request.vetoDeadline > Time.timestamp()) {
            revert VetoPeriodNotEnded();
        }

        if (request.executeDeadline <= Time.timestamp()) {
            revert SlashPeriodEnded();
        }

        if (request.completed) {
            revert SlashCompleted();
        }

        request.completed = true;

        slashedAmount = Math.min(request.amount, slashableAmount(request.network, request.resolver, request.operator));

        uint256 epoch = currentEpoch();
        uint256 totalSupply_ = totalSupply();
        uint256 activeSupply_ = activeSupply();
        uint256 withdrawals_ = withdrawals[epoch];
        uint256 nextWithdrawals_ = withdrawals[epoch + 1];
        uint256 networkResolverLimit_ = networkResolverLimit(request.network, request.resolver);
        uint256 operatorNetworkLimit_ = operatorNetworkLimit(request.operator, request.network);

        uint256 activeSlashed = slashedAmount.mulDiv(activeSupply_, totalSupply_);
        uint256 withdrawalsSlashed = slashedAmount.mulDiv(withdrawals_, totalSupply_);
        uint256 nextWithdrawalsSlashed = slashedAmount - activeSlashed - withdrawalsSlashed;
        if (nextWithdrawals_ < nextWithdrawalsSlashed) {
            nextWithdrawalsSlashed = nextWithdrawals_;
            slashedAmount = activeSlashed + withdrawalsSlashed + nextWithdrawalsSlashed;
        }

        emit ExecuteSlash(slashIndex, slashedAmount);

        if (slashedAmount == 0) {
            return 0;
        }

        _activeSupplies.push(Time.timestamp(), activeSupply_ - activeSlashed);
        withdrawals[epoch] = withdrawals_ - withdrawalsSlashed;
        withdrawals[epoch + 1] = nextWithdrawals_ - nextWithdrawalsSlashed;

        _updateLimit(
            _networkResolverLimit[request.network][request.resolver],
            nextNetworkResolverLimit[request.network][request.resolver]
        );
        _updateLimit(
            _operatorNetworkLimit[request.operator][request.network],
            nextOperatorNetworkLimit[request.operator][request.network]
        );

        if (networkResolverLimit_ != type(uint256).max) {
            _networkResolverLimit[request.network][request.resolver].amount = networkResolverLimit_ - slashedAmount;
        }
        if (operatorNetworkLimit_ != type(uint256).max) {
            _operatorNetworkLimit[request.operator][request.network].amount = operatorNetworkLimit_ - slashedAmount;
        }

        ICollateral(collateral).issueDebt(DEAD, slashedAmount);
    }

    /**
     * @inheritdoc IVault
     */
    function vetoSlash(uint256 slashIndex) external {
        if (slashIndex >= slashRequests.length) {
            revert SlashRequestNotExist();
        }

        SlashRequest storage request = slashRequests[slashIndex];

        if (request.resolver != msg.sender) {
            revert NotResolver();
        }

        if (request.vetoDeadline <= Time.timestamp()) {
            revert VetoPeriodEnded();
        }

        if (request.completed) {
            revert SlashCompleted();
        }

        request.completed = true;

        emit VetoSlash(slashIndex);
    }

    /**
     * @inheritdoc IVault
     */
    function setMaxNetworkResolverLimit(address resolver, uint256 amount) external {
        if (maxNetworkResolverLimit[msg.sender][resolver] == amount) {
            revert AlreadySet();
        }

        if (!IRegistry(NETWORK_REGISTRY).isEntity(msg.sender)) {
            revert NotNetwork();
        }

        maxNetworkResolverLimit[msg.sender][resolver] = amount;

        Limit storage limit = _networkResolverLimit[msg.sender][resolver];
        DelayedLimit storage nextLimit = nextNetworkResolverLimit[msg.sender][resolver];

        _updateLimit(limit, nextLimit);

        if (limit.amount > amount) {
            limit.amount = amount;
        }
        if (nextLimit.amount > amount) {
            nextLimit.amount = amount;
        }

        emit SetMaxNetworkResolverLimit(msg.sender, resolver, amount);
    }

    /**
     * @inheritdoc IVault
     */
    function setNetworkResolverLimit(
        address network,
        address resolver,
        uint256 amount
    ) external onlyRole(NETWORK_RESOLVER_LIMIT_SET_ROLE) {
        if (amount > maxNetworkResolverLimit[network][resolver]) {
            revert ExceedsMaxNetworkResolverLimit();
        }

        Limit storage limit = _networkResolverLimit[network][resolver];
        DelayedLimit storage nextLimit = nextNetworkResolverLimit[network][resolver];

        _setLimit(limit, nextLimit, amount);

        emit SetNetworkResolverLimit(network, resolver, amount);
    }

    /**
     * @inheritdoc IVault
     */
    function setOperatorNetworkLimit(
        address operator,
        address network,
        uint256 amount
    ) external onlyRole(OPERATOR_NETWORK_LIMIT_SET_ROLE) {
        Limit storage limit = _operatorNetworkLimit[operator][network];
        DelayedLimit storage nextLimit = nextOperatorNetworkLimit[operator][network];

        _setLimit(limit, nextLimit, amount);

        emit SetOperatorNetworkLimit(operator, network, amount);
    }

    /**
     * @inheritdoc IVault
     */
    function setRewardsDistributor(address rewardsDistributor_) external onlyRole(REWARDS_DISTRIBUTOR_SET_ROLE) {
        if (rewardsDistributor == rewardsDistributor_) {
            revert AlreadySet();
        }

        rewardsDistributor = rewardsDistributor_;

        emit SetRewardsDistributor(rewardsDistributor_);
    }

    /**
     * @inheritdoc IVault
     */
    function setAdminFee(uint256 adminFee_) external onlyRole(ADMIN_FEE_SET_ROLE) {
        if (adminFee == adminFee_) {
            revert AlreadySet();
        }

        if (adminFee_ > ADMIN_FEE_BASE) {
            revert InvalidAdminFee();
        }

        adminFee = adminFee_;

        emit SetAdminFee(adminFee_);
    }

    /**
     * @inheritdoc IVault
     */
    function setDepositWhitelist(bool status) external onlyRole(DEPOSIT_WHITELIST_SET_ROLE) {
        if (depositWhitelist == status) {
            revert AlreadySet();
        }

        depositWhitelist = status;

        emit SetDepositWhitelist(status);
    }

    /**
     * @inheritdoc IVault
     */
    function setDepositorWhitelistStatus(address account, bool status) external onlyRole(DEPOSITOR_WHITELIST_ROLE) {
        if (account == address(0)) {
            revert InvalidAccount();
        }

        if (isDepositorWhitelisted[account] == status) {
            revert AlreadySet();
        }

        if (status && !depositWhitelist) {
            revert NoDepositWhitelist();
        }

        isDepositorWhitelisted[account] = status;

        emit SetDepositorWhitelistStatus(account, status);
    }

    function _initialize(uint64, address owner, bytes memory data) internal override {
        (IVault.InitParams memory params) = abi.decode(data, (IVault.InitParams));

        if (params.collateral == address(0)) {
            revert InvalidCollateral();
        }

        if (params.epochDuration == 0) {
            revert InvalidEpochDuration();
        }

        if (params.executeDuration == 0 && params.vetoDuration != 0) {
            revert InvalidVetoDuration();
        }

        if (params.vetoDuration + params.executeDuration > params.epochDuration) {
            revert InvalidSlashDuration();
        }

        if (params.adminFee > ADMIN_FEE_BASE) {
            revert InvalidAdminFee();
        }

        collateral = params.collateral;

        epochDurationInit = Time.timestamp();
        epochDuration = params.epochDuration;

        vetoDuration = params.vetoDuration;
        executeDuration = params.executeDuration;

        rewardsDistributor = params.rewardsDistributor;
        adminFee = params.adminFee;
        depositWhitelist = params.depositWhitelist;

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(NETWORK_RESOLVER_LIMIT_SET_ROLE, owner);
        _grantRole(OPERATOR_NETWORK_LIMIT_SET_ROLE, owner);
        if (params.depositWhitelist) {
            _grantRole(DEPOSITOR_WHITELIST_ROLE, owner);
        }
    }

    function _migrate(uint64, bytes memory) internal override {
        revert();
    }

    function _getLimitAt(
        Limit storage limit,
        DelayedLimit storage nextLimit,
        uint48 timestamp
    ) private view returns (uint256) {
        if (nextLimit.timestamp == 0 || timestamp < nextLimit.timestamp) {
            return limit.amount;
        }
        return nextLimit.amount;
    }

    function _setLimit(Limit storage limit, DelayedLimit storage nextLimit, uint256 amount) private {
        _updateLimit(limit, nextLimit);

        if (amount < limit.amount) {
            nextLimit.amount = amount;
            nextLimit.timestamp = currentEpochStart() + 2 * epochDuration;
        } else {
            limit.amount = amount;
            nextLimit.amount = 0;
            nextLimit.timestamp = 0;
        }
    }

    function _updateLimit(Limit storage limit, DelayedLimit storage nextLimit) internal {
        if (nextLimit.timestamp != 0 && nextLimit.timestamp <= Time.timestamp()) {
            limit.amount = nextLimit.amount;
            nextLimit.timestamp = 0;
            nextLimit.amount = 0;
        }
    }
}
