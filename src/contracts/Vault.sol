// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IVault} from "src/interfaces/IVault.sol";
import {ICollateral} from "src/interfaces/ICollateral.sol";
import {IFactory} from "src/interfaces/IFactory.sol";
import {IMiddlewarePlugin} from "src/interfaces/plugins/IMiddlewarePlugin.sol";
import {INetworkOptInPlugin} from "src/interfaces/plugins/INetworkOptInPlugin.sol";

import {MigratableEntity} from "./MigratableEntity.sol";
import {ERC6372} from "./utils/ERC6372.sol";
import {Checkpoints} from "./libraries/Checkpoints.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import {Test, console2} from "forge-std/Test.sol";

contract Vault is MigratableEntity, ERC6372, ReentrancyGuardUpgradeable, AccessControlUpgradeable, IVault {
    using Checkpoints for Checkpoints.Trace208;
    using Checkpoints for Checkpoints.Trace256;
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;
    using Math for uint256;

    address private constant DEAD = address(0xdEaD);

    /**
     * @inheritdoc IVault
     */
    bytes32 public constant NETWORK_LIMIT_SET_ROLE = keccak256("NETWORK_LIMIT_SET_ROLE");

    /**
     * @inheritdoc IVault
     */
    bytes32 public constant OPERATOR_LIMIT_SET_ROLE = keccak256("OPERATOR_LIMIT_SET_ROLE");

    /**
     * @inheritdoc IVault
     */
    bytes32 public constant DEPOSITOR_WHITELIST_ROLE = keccak256("DEPOSITOR_WHITELIST_ROLE");

    /**
     * @inheritdoc IVault
     */
    address public immutable NETWORK_REGISTRY;

    /**
     * @inheritdoc IVault
     */
    address public immutable OPERATOR_REGISTRY;

    /**
     * @inheritdoc IVault
     */
    address public immutable NETWORK_MIDDLEWARE_PLUGIN;

    /**
     * @inheritdoc IVault
     */
    address public immutable NETWORK_OPT_IN_PLUGIN;

    /**
     * @inheritdoc IVault
     */
    string public metadataURL;

    /**
     * @inheritdoc IVault
     */
    address public collateral;

    /**
     * @inheritdoc IVault
     */
    uint48 public epochStart;

    /**
     * @inheritdoc IVault
     */
    uint48 public epochDuration;

    /**
     * @inheritdoc IVault
     */
    uint48 public slashDuration;

    /**
     * @inheritdoc IVault
     */
    uint48 public vetoDuration;

    /**
     * @inheritdoc IVault
     */
    mapping(uint256 epoch => uint256 amount) public withdrawals;

    /**
     * @inheritdoc IVault
     */
    mapping(uint256 epoch => uint256 amount) public withdrawalsShares;

    /**
     * @inheritdoc IVault
     */
    mapping(uint256 epoch => mapping(address account => uint256 amount)) public withdrawalsSharesOf;

    /**
     * @inheritdoc IVault
     */
    mapping(address account => uint48 timestamp) public firstDepositAt;

    /**
     * @inheritdoc IVault
     */
    mapping(address network => mapping(address resolver => bool value)) public isNetworkOptedIn;

    /**
     * @inheritdoc IVault
     */
    mapping(address operator => uint48 timestamp) public operatorOptOutAt;

    /**
     * @inheritdoc IVault
     */
    mapping(address network => mapping(address resolver => uint256 amount)) public maxNetworkLimit;

    /**
     * @inheritdoc IVault
     */
    mapping(address network => mapping(address resolver => DelayedLimit)) public nextNetworkLimit;

    /**
     * @inheritdoc IVault
     */
    mapping(address operator => mapping(address network => DelayedLimit)) public nextOperatorLimit;

    /**
     * @inheritdoc IVault
     */
    SlashRequest[] public slashRequests;

    /**
     * @inheritdoc IVault
     */
    mapping(address token => RewardDistribution[] rewards_) public rewards;

    /**
     * @inheritdoc IVault
     */
    mapping(address account => mapping(address token => uint256 rewardIndex)) public lastUnclaimedReward;

    /**
     * @inheritdoc IVault
     */
    bool public hasDepositWhitelist;

    /**
     * @inheritdoc IVault
     */
    mapping(address account => bool value) public isDepositorWhitelisted;

    Checkpoints.Trace256 private _activeShares;

    Checkpoints.Trace256 private _activeSupplies;

    mapping(address account => Checkpoints.Trace256 shares) private _activeSharesOf;

    mapping(address operator => bool value) private _isOperatorOptedIn;

    mapping(address network => mapping(address resolver => Limit limit)) private _networkLimit;

    mapping(address operator => mapping(address network => Limit limit)) private _operatorLimit;

    mapping(uint48 timestamp => Cache cache) private _activeSharesCache;

    mapping(uint48 timestamp => Cache cache) private _activeSuppliesCache;

    modifier isNetwork(address account) {
        if (!IFactory(NETWORK_REGISTRY).isEntity(account)) {
            revert NotNetwork();
        }
        _;
    }

    modifier onlyNetwork() {
        if (!IFactory(NETWORK_REGISTRY).isEntity(msg.sender)) {
            revert NotNetwork();
        }
        _;
    }

    modifier onlyNetworkMiddleware(address network) {
        if (IMiddlewarePlugin(NETWORK_MIDDLEWARE_PLUGIN).middleware(network) != msg.sender) {
            revert NotNetworkMiddleware();
        }
        _;
    }

    modifier isOperator(address account) {
        if (!IFactory(OPERATOR_REGISTRY).isEntity(account)) {
            revert NotOperator();
        }
        _;
    }

    modifier onlyOperator() {
        if (!IFactory(OPERATOR_REGISTRY).isEntity(msg.sender)) {
            revert NotOperator();
        }
        _;
    }

    constructor(
        address networkRegistry,
        address operatorRegistry,
        address networkMiddlewarePlugin,
        address networkOptInPlugin
    ) {
        NETWORK_REGISTRY = networkRegistry;
        OPERATOR_REGISTRY = operatorRegistry;
        NETWORK_MIDDLEWARE_PLUGIN = networkMiddlewarePlugin;
        NETWORK_OPT_IN_PLUGIN = networkOptInPlugin;
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
    function activeSharesAt(uint48 timestamp) public view returns (uint256) {
        return _activeShares.upperLookupRecent(timestamp);
    }

    /**
     * @inheritdoc IVault
     */
    function activeShares() public view returns (uint256) {
        return _activeShares.latest();
    }

    /**
     * @inheritdoc IVault
     */
    function activeSupplyAt(uint48 timestamp) public view returns (uint256) {
        return _activeSupplies.upperLookupRecent(timestamp);
    }

    /**
     * @inheritdoc IVault
     */
    function activeSupply() public view returns (uint256) {
        return _activeSupplies.latest();
    }

    /**
     * @inheritdoc IVault
     */
    function activeSharesOfAt(address account, uint48 timestamp) public view returns (uint256) {
        return _activeSharesOf[account].upperLookupRecent(timestamp);
    }

    /**
     * @inheritdoc IVault
     */
    function activeSharesOf(address account) public view returns (uint256) {
        return _activeSharesOf[account].latest();
    }

    /**
     * @inheritdoc IVault
     */
    function activeBalanceOfAt(address account, uint48 timestamp) public view returns (uint256) {
        return
            _previewRedeem(activeSharesOfAt(account, timestamp), activeSupplyAt(timestamp), activeSharesAt(timestamp));
    }

    /**
     * @inheritdoc IVault
     */
    function activeBalanceOf(address account) public view returns (uint256) {
        return _previewRedeem(activeSharesOf(account), activeSupply(), activeShares());
    }

    /**
     * @inheritdoc IVault
     */
    function maxSlash(address network, address resolver, address operator) public view returns (uint256) {
        uint256 networkLimit_ = networkLimit(network, resolver);
        uint256 operatorLimit_ = operatorLimit(operator, network);

        uint256 amount = totalSupply();
        if (networkLimit_ != type(uint256).max) {
            amount = Math.min(amount, networkLimit_);
        }
        if (operatorLimit_ != type(uint256).max) {
            amount = Math.min(amount, operatorLimit_);
        }
        return amount;
    }

    function slashRequestsLength() public view returns (uint256) {
        return slashRequests.length;
    }

    function rewardsLength(address token) public view returns (uint256) {
        return rewards[token].length;
    }

    /**
     * @inheritdoc IVault
     */
    function currentEpoch() public view returns (uint256) {
        return (clock() - epochStart) / epochDuration;
    }

    /**
     * @inheritdoc IVault
     */
    function currentEpochStart() public view returns (uint48) {
        return uint48(epochStart + currentEpoch() * epochDuration);
    }

    /**
     * @inheritdoc IVault
     */
    function isOperatorOptedIn(address operator) public view returns (bool) {
        if (operatorOptOutAt[operator] == 0) {
            return _isOperatorOptedIn[operator];
        }
        if (clock() < operatorOptOutAt[operator]) {
            return true;
        }
        return false;
    }

    /**
     * @inheritdoc IVault
     */
    function networkLimit(address network, address resolver) public view returns (uint256) {
        DelayedLimit storage nextLimit = nextNetworkLimit[network][resolver];
        if (nextLimit.timestamp == 0) {
            return _networkLimit[network][resolver].amount;
        }
        if (clock() < nextLimit.timestamp) {
            return _networkLimit[network][resolver].amount;
        }
        return nextLimit.amount;
    }

    /**
     * @inheritdoc IVault
     */
    function operatorLimit(address operator, address network) public view returns (uint256) {
        DelayedLimit storage nextLimit = nextOperatorLimit[operator][network];
        if (nextLimit.timestamp == 0) {
            return _operatorLimit[operator][network].amount;
        }
        if (clock() < nextLimit.timestamp) {
            return _operatorLimit[operator][network].amount;
        }
        return nextLimit.amount;
    }

    /**
     * @inheritdoc MigratableEntity
     */
    function initialize(bytes memory data) public override initializer {
        __ReentrancyGuard_init();

        (IVault.InitParams memory params) = abi.decode(data, (IVault.InitParams));
        super.initialize(abi.encode(params.owner));

        metadataURL = params.metadataURL;
        collateral = params.collateral;

        if (params.epochDuration == 0) {
            revert InvalidEpochDuration();
        }

        if (params.vetoDuration + params.slashDuration > params.epochDuration) {
            revert InvalidSlashDuration();
        }

        epochStart = clock();
        epochDuration = params.epochDuration;

        slashDuration = params.slashDuration;
        vetoDuration = params.vetoDuration;

        hasDepositWhitelist = params.hasDepositWhitelist;

        _grantRole(DEFAULT_ADMIN_ROLE, params.owner);
        _grantRole(NETWORK_LIMIT_SET_ROLE, params.owner);
        _grantRole(OPERATOR_LIMIT_SET_ROLE, params.owner);
        if (params.hasDepositWhitelist) {
            _grantRole(DEPOSITOR_WHITELIST_ROLE, params.owner);
        }
    }

    /**
     * @inheritdoc IVault
     */
    function setMetadataURL(string calldata metadataURL_) external onlyOwner {
        metadataURL = metadataURL_;
    }

    /**
     * @inheritdoc IVault
     */
    function deposit(address onBehalfOf, uint256 amount) external returns (uint256 shares) {
        if (hasDepositWhitelist && !isDepositorWhitelisted[msg.sender]) {
            revert NotWhitelistedDepositor();
        }

        if (amount == 0) {
            revert InsufficientDeposit();
        }

        IERC20(collateral).transferFrom(msg.sender, address(this), amount);

        uint256 activeSupply_ = activeSupply();
        uint256 activeShares_ = activeShares();
        uint256 activeSharesOf_ = activeSharesOf(onBehalfOf);

        shares = _previewDeposit(amount, activeShares_, activeSupply_);

        _activeSupplies.push(clock(), activeSupply_ + amount);
        _activeShares.push(clock(), activeShares_ + shares);
        _activeSharesOf[onBehalfOf].push(clock(), activeSharesOf_ + shares);

        if (firstDepositAt[onBehalfOf] == 0) {
            firstDepositAt[onBehalfOf] = clock();
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

        burnedShares = _previewWithdraw(amount, activeShares_, activeSupply_);
        if (burnedShares > activeSharesOf_) {
            revert TooMuchWithdraw();
        }

        _activeSupplies.push(clock(), activeSupply_ - amount);
        _activeShares.push(clock(), activeShares_ - burnedShares);
        _activeSharesOf[msg.sender].push(clock(), activeSharesOf_ - burnedShares);

        uint256 epoch = currentEpoch() + 1;
        mintedShares = _previewDeposit(amount, withdrawalsShares[epoch], withdrawals[epoch]);

        withdrawals[epoch] += amount;
        withdrawalsShares[epoch] += mintedShares;
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

        amount = _previewRedeem(withdrawalsSharesOf[epoch][msg.sender], withdrawals[epoch], withdrawalsShares[epoch]);

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
    ) external isNetwork(network) onlyNetworkMiddleware(network) isOperator(operator) returns (uint256 slashIndex) {
        uint256 maxSlash_ = maxSlash(network, resolver, operator);

        if (amount == 0 || maxSlash_ == 0) {
            revert InsufficientSlash();
        }

        if (!isNetworkOptedIn[network][resolver]) {
            revert NetworkNotOptedIn();
        }

        bool optedInNetwork = INetworkOptInPlugin(NETWORK_OPT_IN_PLUGIN).isOperatorOptedIn(operator, network);
        uint48 lastOperatorOptOut = INetworkOptInPlugin(NETWORK_OPT_IN_PLUGIN).lastOperatorOptOut(operator, network);
        if (!optedInNetwork && lastOperatorOptOut < block.timestamp - epochDuration) {
            revert OperatorNotOptedInNetwork();
        }

        if (!isOperatorOptedIn(operator)) {
            revert OperatorNotOptedInVault();
        }

        uint256 slashAmount = Math.min(amount, maxSlash_);
        uint48 vetoDeadline = clock() + vetoDuration;
        uint48 slashDeadline = vetoDeadline + slashDuration;

        slashIndex = slashRequests.length;
        slashRequests.push(
            SlashRequest({
                network: network,
                resolver: resolver,
                operator: operator,
                amount: slashAmount,
                vetoDeadline: vetoDeadline,
                slashDeadline: slashDeadline,
                completed: false
            })
        );

        emit RequestSlash(slashIndex, network, resolver, operator, slashAmount, vetoDeadline, slashDeadline);
    }

    /**
     * @inheritdoc IVault
     */
    function executeSlash(uint256 slashIndex) external returns (uint256 slashedAmount) {
        if (slashIndex >= slashRequests.length) {
            revert SlashRequestNotExist();
        }

        SlashRequest storage request = slashRequests[slashIndex];

        if (request.vetoDeadline > clock()) {
            revert VetoPeriodNotEnded();
        }

        if (request.slashDeadline <= clock()) {
            revert SlashPeriodEnded();
        }

        if (request.completed) {
            revert SlashCompleted();
        }

        if (!isOperatorOptedIn(request.operator)) {
            revert OperatorNotOptedInVault();
        }

        request.completed = true;

        slashedAmount = Math.min(request.amount, maxSlash(request.network, request.resolver, request.operator));

        if (slashedAmount == 0) {
            emit ExecuteSlash(slashIndex, 0);
            return 0;
        }

        uint256 epoch = currentEpoch();
        uint256 totalSupply_ = totalSupply();
        uint256 activeSupply_ = activeSupply();
        uint256 withdrawals_ = withdrawals[epoch];
        uint256 nextWithdrawals_ = withdrawals[epoch + 1];
        uint256 networkLimit_ = networkLimit(request.network, request.resolver);
        uint256 operatorLimit_ = operatorLimit(request.operator, request.network);

        uint256 activeSlashed = slashedAmount.mulDiv(activeSupply_, totalSupply_);
        uint256 withdrawalsSlashed = slashedAmount.mulDiv(withdrawals_, totalSupply_);
        uint256 nextWithdrawalsSlashed = slashedAmount - activeSlashed - withdrawalsSlashed;
        if (nextWithdrawals_ < nextWithdrawalsSlashed) {
            nextWithdrawalsSlashed = nextWithdrawals_;
        }

        slashedAmount = activeSlashed + withdrawalsSlashed + nextWithdrawalsSlashed;

        emit ExecuteSlash(slashIndex, slashedAmount);

        if (slashedAmount == 0) {
            return 0;
        }

        _activeSupplies.push(clock(), activeSupply_ - activeSlashed);
        withdrawals[epoch] = withdrawals_ - withdrawalsSlashed;
        withdrawals[epoch + 1] = nextWithdrawals_ - nextWithdrawalsSlashed;

        _updateLimit(
            _networkLimit[request.network][request.resolver], nextNetworkLimit[request.network][request.resolver]
        );
        _updateLimit(
            _operatorLimit[request.operator][request.network], nextOperatorLimit[request.operator][request.network]
        );

        if (networkLimit_ != type(uint256).max) {
            _networkLimit[request.network][request.resolver].amount = networkLimit_ - slashedAmount;
        }
        if (operatorLimit_ != type(uint256).max) {
            _operatorLimit[request.operator][request.network].amount = operatorLimit_ - slashedAmount;
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

        if (request.vetoDeadline <= clock()) {
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
    function optInNetwork(address resolver, uint256 maxNetworkLimit_) external onlyNetwork {
        if (isNetworkOptedIn[msg.sender][resolver]) {
            revert NetworkAlreadyOptedIn();
        }

        if (maxNetworkLimit_ == 0) {
            revert InvalidMaxNetworkLimit();
        }

        isNetworkOptedIn[msg.sender][resolver] = true;

        _networkLimit[msg.sender][resolver].amount = 0;
        nextNetworkLimit[msg.sender][resolver].timestamp = 0;

        maxNetworkLimit[msg.sender][resolver] = maxNetworkLimit_;

        emit OptInNetwork(msg.sender, resolver);
    }

    /**
     * @inheritdoc IVault
     */
    function optOutNetwork(address resolver) external onlyNetwork {
        if (!isNetworkOptedIn[msg.sender][resolver]) {
            revert NetworkNotOptedIn();
        }

        _updateLimit(_networkLimit[msg.sender][resolver], nextNetworkLimit[msg.sender][resolver]);

        isNetworkOptedIn[msg.sender][resolver] = false;

        nextNetworkLimit[msg.sender][resolver].amount = 0;
        nextNetworkLimit[msg.sender][resolver].timestamp = currentEpochStart() + 2 * epochDuration;

        maxNetworkLimit[msg.sender][resolver] = 0;

        emit OptOutNetwork(msg.sender, resolver);
    }

    /**
     * @inheritdoc IVault
     */
    function optInOperator() external onlyOperator {
        if (isOperatorOptedIn(msg.sender)) {
            revert OperatorAlreadyOptedIn();
        }

        if (!_isOperatorOptedIn[msg.sender]) {
            _isOperatorOptedIn[msg.sender] = true;
        } else {
            operatorOptOutAt[msg.sender] = 0;
        }

        emit OptInOperator(msg.sender);
    }

    /**
     * @inheritdoc IVault
     */
    function optOutOperator() external onlyOperator {
        if (!isOperatorOptedIn(msg.sender)) {
            revert OperatorNotOptedIn();
        }

        operatorOptOutAt[msg.sender] = currentEpochStart() + 2 * epochDuration;

        emit OptOutOperator(msg.sender);
    }

    /**
     * @inheritdoc IVault
     */
    function distributeReward(
        address network,
        address token,
        uint256 amount,
        uint48 timestamp
    ) external isNetwork(network) returns (uint256 rewardIndex) {
        if (timestamp >= clock()) {
            revert InvalidRewardTimestamp();
        }

        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        amount = IERC20(token).balanceOf(address(this)) - balanceBefore;

        if (amount == 0) {
            revert InsufficientReward();
        }

        rewardIndex = rewards[token].length;

        rewards[token].push(RewardDistribution({amount: amount, timestamp: timestamp, creation: clock()}));

        if (!_activeSharesCache[timestamp].isSet) {
            _activeSharesCache[timestamp].isSet = true;
            _activeSharesCache[timestamp].amount = activeSharesAt(timestamp);
        }
        if (!_activeSuppliesCache[timestamp].isSet) {
            _activeSuppliesCache[timestamp].isSet = true;
            _activeSuppliesCache[timestamp].amount = activeSupplyAt(timestamp);
        }

        emit DistributeReward(token, rewardIndex, network, amount, timestamp);
    }

    /**
     * @inheritdoc IVault
     */
    function claimRewards(address recipient, RewardClaim[] calldata rewardClaims) external {
        uint256 tokensLen = rewardClaims.length;
        if (tokensLen == 0) {
            revert NoRewardClaims();
        }

        uint48 firstDepositAt_ = firstDepositAt[msg.sender];
        if (firstDepositAt_ == 0) {
            revert NoDeposits();
        }

        mapping(address => uint256) storage lastUnclaimedRewardByUser = lastUnclaimedReward[msg.sender];

        for (uint256 i; i < tokensLen; ++i) {
            RewardClaim calldata rewardClaim = rewardClaims[i];
            address token = rewardClaim.token;

            RewardDistribution[] storage rewardsByToken = rewards[token];
            uint256 rewardIndex = lastUnclaimedRewardByUser[token];
            if (rewardIndex == 0) {
                rewardIndex = _firstUnclaimedReward(rewardsByToken, firstDepositAt_ - 1);
            }

            uint256 rewardsToClaim = rewardsByToken.length - rewardIndex;
            if (rewardsToClaim > rewardClaim.amountIndexes) {
                rewardsToClaim = rewardClaim.amountIndexes;
            }

            if (rewardsToClaim == 0) {
                revert NoRewardsToClaim();
            }

            uint256 activeSharesOfHintsLen = rewardClaim.activeSharesOfHints.length;
            if (activeSharesOfHintsLen != 0 && activeSharesOfHintsLen != rewardsToClaim) {
                revert InvalidHintsLength();
            }

            uint256 amount;
            for (uint256 j; j < rewardsToClaim; ++j) {
                RewardDistribution storage reward = rewardsByToken[rewardIndex];

                uint256 claimedAmount;
                uint48 timestamp = reward.timestamp;
                if (timestamp >= firstDepositAt_) {
                    uint256 activeShares_ = _activeSharesCache[timestamp].amount;
                    uint256 activeSupply_ = _activeSuppliesCache[timestamp].amount;
                    uint256 activeSharesOf_ = activeSharesOfHintsLen != 0
                        ? _activeSharesOf[msg.sender].upperLookupRecent(timestamp, rewardClaim.activeSharesOfHints[j])
                        : _activeSharesOf[msg.sender].upperLookupRecent(timestamp);
                    uint256 activeBalanceOf_ = _previewRedeem(activeSharesOf_, activeSupply_, activeShares_);

                    claimedAmount = activeBalanceOf_.mulDiv(reward.amount, activeSupply_);
                    amount += claimedAmount;
                }

                emit ClaimReward(token, rewardIndex, msg.sender, recipient, claimedAmount);

                ++rewardIndex;
            }

            lastUnclaimedRewardByUser[token] = rewardIndex;

            if (amount != 0) {
                IERC20(token).safeTransfer(recipient, amount);
            }
        }
    }

    /**
     * @inheritdoc IVault
     */
    function setNetworkLimit(
        address network,
        address resolver,
        uint256 amount
    ) external onlyRole(NETWORK_LIMIT_SET_ROLE) {
        if (!isNetworkOptedIn[network][resolver]) {
            revert NetworkNotOptedIn();
        }

        if (amount > maxNetworkLimit[network][resolver]) {
            revert ExceedsMaxNetworkLimit();
        }

        _setLimit(_networkLimit[network][resolver], nextNetworkLimit[network][resolver], amount);

        emit SetNetworkLimit(network, resolver, amount);
    }

    /**
     * @inheritdoc IVault
     */
    function setOperatorLimit(
        address operator,
        address network,
        uint256 amount
    ) external onlyRole(OPERATOR_LIMIT_SET_ROLE) {
        Limit storage limit = _operatorLimit[operator][network];
        DelayedLimit storage nextLimit = nextOperatorLimit[operator][network];

        if (!isOperatorOptedIn(operator)) {
            if (amount != 0) {
                revert OperatorNotOptedIn();
            } else {
                limit.amount = 0;
                nextLimit.amount = 0;
                nextLimit.timestamp = 0;
            }
        } else {
            _setLimit(limit, nextLimit, amount);
        }

        emit SetOperatorLimit(operator, network, amount);
    }

    /**
     * @inheritdoc IVault
     */
    function setHasDepositWhitelist(bool value) external onlyOwner {
        if (value == hasDepositWhitelist) {
            revert AlreadySet();
        }

        hasDepositWhitelist = value;

        emit SetHasDepositWhitelist(value);
    }

    /**
     * @inheritdoc IVault
     */
    function setDepositorWhitelistStatus(address account, bool value) external onlyRole(DEPOSITOR_WHITELIST_ROLE) {
        if (value && !hasDepositWhitelist) {
            revert NoDepositWhitelist();
        }

        if (isDepositorWhitelisted[account] == value) {
            revert AlreadySet();
        }

        isDepositorWhitelisted[account] = value;

        emit SetDepositorWhitelistStatus(account, value);
    }

    /**
     * @inheritdoc MigratableEntity
     */
    function migrate(bytes memory) public override {
        revert();
    }

    function _firstUnclaimedReward(
        RewardDistribution[] storage array,
        uint48 claimedUntil
    ) private view returns (uint256) {
        uint256 low = 0;
        uint256 high = array.length;
        uint48 element = claimedUntil + 1;

        if (high == 0) {
            return 0;
        }

        while (low < high) {
            uint256 mid = Math.average(low, high);

            // Note that mid will always be strictly less than high (i.e. it will be a valid array index)
            // because Math.average rounds towards zero (it does integer division with truncation).
            if (array[mid].creation > element) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        // At this point `low` is the exclusive upper bound. We will return the inclusive upper bound.
        if (low > 0 && array[low - 1].creation == element) {
            return low - 1;
        } else {
            return low;
        }
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

    function _updateLimit(Limit storage limit, DelayedLimit storage nextLimit) private {
        if (nextLimit.timestamp != 0 && nextLimit.timestamp <= clock()) {
            limit.amount = nextLimit.amount;
            nextLimit.timestamp = 0;
            nextLimit.amount = 0;
        }
    }

    function _previewDeposit(uint256 assets, uint256 totalShares, uint256 totalAssets) private pure returns (uint256) {
        return _convertToShares(assets, totalShares, totalAssets, Math.Rounding.Floor);
    }

    function _previewWithdraw(
        uint256 assets,
        uint256 totalShares,
        uint256 totalAssets
    ) private pure returns (uint256) {
        return _convertToShares(assets, totalShares, totalAssets, Math.Rounding.Ceil);
    }

    function _previewRedeem(uint256 shares, uint256 totalAssets, uint256 totalShares) private pure returns (uint256) {
        return _convertToAssets(shares, totalAssets, totalShares, Math.Rounding.Floor);
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     */
    function _convertToShares(
        uint256 assets,
        uint256 totalShares,
        uint256 totalAssets,
        Math.Rounding rounding
    ) private pure returns (uint256) {
        return assets.mulDiv(totalShares + 10 ** _decimalsOffset(), totalAssets + 1, rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(
        uint256 shares,
        uint256 totalAssets,
        uint256 totalShares,
        Math.Rounding rounding
    ) private pure returns (uint256) {
        return shares.mulDiv(totalAssets + 1, totalShares + 10 ** _decimalsOffset(), rounding);
    }

    function _decimalsOffset() private pure returns (uint8) {
        return 3;
    }
}
