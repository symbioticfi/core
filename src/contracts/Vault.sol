// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IVault} from "src/interfaces/IVault.sol";
import {IRegistry} from "src/interfaces/base/IRegistry.sol";
import {IMigratableEntity} from "src/interfaces/base/IMigratableEntity.sol";
import {ICollateral} from "src/interfaces/base/ICollateral.sol";
import {IMiddlewarePlugin} from "src/interfaces/plugins/IMiddlewarePlugin.sol";
import {INetworkOptInPlugin} from "src/interfaces/plugins/INetworkOptInPlugin.sol";
import {IOperatorOptInPlugin} from "src/interfaces/plugins/IOperatorOptInPlugin.sol";

import {VaultStorage} from "./VaultStorage.sol";
import {MigratableEntity} from "./base/MigratableEntity.sol";

import {ERC4626Math} from "./libraries/ERC4626Math.sol";
import {Checkpoints} from "./libraries/Checkpoints.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract Vault is VaultStorage, MigratableEntity, AccessControlUpgradeable, IVault {
    using Checkpoints for Checkpoints.Trace256;
    using Math for uint256;

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
    function withdrawalsBalanceOf(uint256 epoch, address account) public view returns (uint256) {
        return
            ERC4626Math.previewRedeem(withdrawalsSharesOf[epoch][account], withdrawals[epoch], withdrawalsShares[epoch]);
    }

    /**
     * @inheritdoc IVault
     */
    function maxSlash(address network, address resolver, address operator) public view returns (uint256) {
        return Math.min(
            totalSupply(), Math.min(networkResolverLimit(network, resolver), operatorNetworkLimit(operator, network))
        );
    }

    /**
     * @inheritdoc IVault
     */
    function networkResolverLimit(address network, address resolver) public view returns (uint256) {
        return _getLimit(_networkResolverLimit[network][resolver], nextNetworkResolverLimit[network][resolver]);
    }

    /**
     * @inheritdoc IVault
     */
    function operatorNetworkLimit(address operator, address network) public view returns (uint256) {
        return _getLimit(_operatorNetworkLimit[operator][network], nextOperatorNetworkLimit[operator][network]);
    }

    constructor(
        address networkRegistry,
        address operatorRegistry,
        address networkMiddlewarePlugin,
        address networkVaultOptInPlugin,
        address operatorVaultOptInPlugin,
        address operatorNetworkOptInPlugin
    )
        VaultStorage(
            networkRegistry,
            operatorRegistry,
            networkMiddlewarePlugin,
            networkVaultOptInPlugin,
            operatorVaultOptInPlugin,
            operatorNetworkOptInPlugin
        )
    {}

    /**
     * @inheritdoc IMigratableEntity
     */
    function initialize(uint64 version_, bytes memory data) public override reinitializer(version_) {
        (IVault.InitParams memory params) = abi.decode(data, (IVault.InitParams));

        if (params.epochDuration == 0) {
            revert InvalidEpochDuration();
        }

        if (params.vetoDuration + params.slashDuration > params.epochDuration) {
            revert InvalidSlashDuration();
        }

        if (params.adminFee > ADMIN_FEE_BASE) {
            revert InvalidAdminFee();
        }

        _initialize(params.owner);

        collateral = params.collateral;

        epochDurationInit = Time.timestamp();
        epochDuration = params.epochDuration;

        vetoDuration = params.vetoDuration;
        slashDuration = params.slashDuration;

        adminFee = params.adminFee;
        depositWhitelist = params.depositWhitelist;

        _grantRole(DEFAULT_ADMIN_ROLE, params.owner);
        _grantRole(NETWORK_RESOLVER_LIMIT_SET_ROLE, params.owner);
        _grantRole(OPERATOR_NETWORK_LIMIT_SET_ROLE, params.owner);
        if (params.depositWhitelist) {
            _grantRole(DEPOSITOR_WHITELIST_ROLE, params.owner);
        }
    }

    /**
     * @inheritdoc IVault
     */
    function deposit(address onBehalfOf, uint256 amount) external returns (uint256 shares) {
        if (depositWhitelist && !isDepositorWhitelisted[msg.sender]) {
            revert NotWhitelistedDepositor();
        }

        if (amount == 0) {
            revert InsufficientDeposit();
        }

        IERC20(collateral).transferFrom(msg.sender, address(this), amount);

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
        uint256 withdrawalsShares_ = withdrawalsShares[epoch];

        mintedShares = ERC4626Math.previewDeposit(amount, withdrawalsShares_, withdrawals_);

        withdrawals[epoch] = withdrawals_ + amount;
        withdrawalsShares[epoch] = withdrawalsShares_ + mintedShares;
        withdrawalsSharesOf[epoch][claimer] += mintedShares;

        emit Withdraw(msg.sender, claimer, amount, burnedShares, mintedShares);
    }

    /**
     * @inheritdoc IVault
     */
    function claim(address recipient, uint256 epoch) external returns (uint256 amount) {
        if (epoch >= currentEpoch()) {
            revert InvalidEpoch();
        }

        amount = withdrawalsBalanceOf(epoch, msg.sender);

        if (amount == 0) {
            revert InsufficientClaim();
        }

        withdrawalsSharesOf[epoch][msg.sender] = 0;

        IERC20(collateral).transfer(recipient, amount);

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
        if (IMiddlewarePlugin(NETWORK_MIDDLEWARE_PLUGIN).middleware(network) != msg.sender) {
            revert NotNetworkMiddleware();
        }

        uint256 maxSlash_ = maxSlash(network, resolver, operator);

        if (amount == 0 || maxSlash_ == 0) {
            revert InsufficientSlash();
        }

        if (!INetworkOptInPlugin(NETWORK_VAULT_OPT_IN_PLUGIN).isOptedIn(network, resolver, address(this))) {
            revert NetworkNotOptedInVault();
        }

        if (
            !IOperatorOptInPlugin(OPERATOR_VAULT_OPT_IN_PLUGIN).wasOptedIn(operator, address(this), previousEpochStart())
        ) {
            revert OperatorNotOptedInVault();
        }

        if (!IOperatorOptInPlugin(OPERATOR_NETWORK_OPT_IN_PLUGIN).wasOptedIn(operator, network, previousEpochStart())) {
            revert OperatorNotOptedInNetwork();
        }

        if (amount > maxSlash_) {
            amount = maxSlash_;
        }
        uint48 vetoDeadline = Time.timestamp() + vetoDuration;
        uint48 slashDeadline = vetoDeadline + slashDuration;

        slashIndex = slashRequests.length;
        slashRequests.push(
            SlashRequest({
                network: network,
                resolver: resolver,
                operator: operator,
                amount: amount,
                vetoDeadline: vetoDeadline,
                slashDeadline: slashDeadline,
                completed: false
            })
        );

        emit RequestSlash(slashIndex, network, resolver, operator, amount, vetoDeadline, slashDeadline);
    }

    /**
     * @inheritdoc IVault
     */
    function executeSlash(uint256 slashIndex) external returns (uint256 slashedAmount) {
        if (slashIndex >= slashRequests.length) {
            revert SlashRequestNotExist();
        }

        SlashRequest storage request = slashRequests[slashIndex];

        if (request.vetoDeadline > Time.timestamp()) {
            revert VetoPeriodNotEnded();
        }

        if (request.slashDeadline <= Time.timestamp()) {
            revert SlashPeriodEnded();
        }

        if (request.completed) {
            revert SlashCompleted();
        }

        request.completed = true;

        slashedAmount = Math.min(request.amount, maxSlash(request.network, request.resolver, request.operator));

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
        if (isDepositorWhitelisted[account] == status) {
            revert AlreadySet();
        }

        if (status && !depositWhitelist) {
            revert NoDepositWhitelist();
        }

        isDepositorWhitelisted[account] = status;

        emit SetDepositorWhitelistStatus(account, status);
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

    function _getLimit(Limit storage limit, DelayedLimit storage nextLimit) private view returns (uint256) {
        if (nextLimit.timestamp == 0 || Time.timestamp() < nextLimit.timestamp) {
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

    /**
     * @inheritdoc IMigratableEntity
     */
    function migrate(bytes memory) public override {
        revert();
    }
}
