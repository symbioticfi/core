// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IVault {
    error NotNetwork();
    error NotNetworkOwner();
    error NotNetworkMiddleware();
    error NotOperator();
    error NotOperatorOwner();
    error InvalidEpochDuration();
    error InvalidSlashDuration();
    error NotWhitelistedDepositor();
    error InsufficientDeposit();
    error InsufficientWithdrawal();
    error TooMuchWithdraw();
    error InvalidEpoch();
    error InsufficientClaim();
    error InsufficientSlash();
    error OperatorNotOptedInNetwork();
    error OperatorNotOptedInVault();
    error SlashRequestNotExist();
    error VetoPeriodNotEnded();
    error SlashPeriodEnded();
    error SlashCompleted();
    error NotResolver();
    error VetoPeriodEnded();
    error NetworkAlreadyOptedIn();
    error InvalidMaxNetworkLimit();
    error NetworkNotOptedIn();
    error OperatorAlreadyOptedIn();
    error ExceedsMaxNetworkLimit();
    error OperatorNotOptedIn();
    error NoRewardsToClaim();
    error InvalidHintsLength();
    error InsufficientLimit();
    error InsufficientReward();
    error InvalidRewardTimestamp();
    error NoRewardClaims();
    error NotEqualLengths();
    error NoDeposits();
    error AlreadySet();
    error NoDepositWhitelist();

    // Initial parameters needed for a vault deployment
    struct InitParams {
        address owner;
        string metadataURL;
        address collateral;
        uint48 epochDuration;
        uint48 slashDuration;
        uint48 vetoDuration;
        bool hasDepositWhitelist;
    }

    struct Cache {
        bool isSet;
        uint256 amount;
    }

    struct Limit {
        uint256 amount;
    }

    struct DelayedLimit {
        uint256 amount;
        uint48 timestamp;
    }

    struct SlashRequest {
        address network;
        address resolver;
        address operator;
        uint256 amount;
        uint48 vetoDeadline;
        uint48 slashDeadline;
        bool completed;
    }

    struct RewardDistribution {
        uint256 amount;
        uint48 timestamp;
        uint48 creation;
    }

    struct RewardClaim {
        address token;
        uint256 amountIndexes;
        uint32[] activeSharesOfHints;
    }

    event Deposit(address indexed depositor, address indexed onBehalfOf, uint256 amount, uint256 shares);

    event Withdraw(
        address indexed withdrawer, address indexed claimer, uint256 amount, uint256 burnedShares, uint256 mintedShares
    );

    event Claim(address indexed claimer, address indexed recipient, uint256 amount);

    event RequestSlash(
        uint256 indexed slashIndex,
        address indexed network,
        address resolver,
        address indexed operator,
        uint256 slashAmount,
        uint48 vetoDeadline,
        uint48 slashDeadline
    );

    event ExecuteSlash(uint256 indexed slashIndex, uint256 slashedAmount);

    event VetoSlash(uint256 indexed slashIndex);

    event OptInNetwork(address indexed network, address indexed resolver);

    event OptOutNetwork(address indexed network, address indexed resolver);

    event OptInOperator(address indexed operator);

    event OptOutOperator(address indexed operator);

    event DistributeReward(
        address indexed token, uint256 indexed rewardIndex, address indexed network, uint256 amount, uint48 timestamp
    );

    event ClaimReward(
        address indexed token,
        uint256 indexed rewardIndex,
        address indexed claimer,
        address recipient,
        uint256 claimedAmount
    );

    event SetNetworkLimit(address indexed network, address indexed resolver, uint256 amount);

    event SetOperatorLimit(address indexed operator, address indexed network, uint256 amount);

    event SetHasDepositWhitelist(bool hasDepositWhitelist);

    event SetDepositorWhitelistStatus(address indexed account, bool value);

    function NETWORK_LIMIT_SET_ROLE() external view returns (bytes32);

    function OPERATOR_LIMIT_SET_ROLE() external view returns (bytes32);

    function DEPOSITOR_WHITELIST_ROLE() external view returns (bytes32);

    /**
     * @notice Get the Network Registry's address.
     * @return address of the registry
     */
    function NETWORK_REGISTRY() external view returns (address);

    /**
     * @notice Get the Operator Registry's address.
     * @return address of the Operator Registry
     */
    function OPERATOR_REGISTRY() external view returns (address);

    function NETWORK_MIDDLEWARE_PLUGIN() external view returns (address);

    function NETWORK_OPT_IN_PLUGIN() external view returns (address);

    /**
     * @notice Get a URL with a vault's metadata.
     * The metadata should contain: name, description, external_url, image.
     * @return metadata URL of the vault
     */
    function metadataURL() external view returns (string memory);

    /**
     * @notice Get a vault token.
     * @return collateral underlying vault
     */
    function collateral() external view returns (address);

    function epochStart() external view returns (uint48);

    function epochDuration() external view returns (uint48);

    function currentEpoch() external view returns (uint256);

    function currentEpochStart() external view returns (uint48);

    function slashDuration() external view returns (uint48);

    function vetoDuration() external view returns (uint48);

    function totalSupply() external view returns (uint256);

    function activeSharesAt(uint48 timestamp) external view returns (uint256);

    function activeShares() external view returns (uint256);

    function activeSupplyAt(uint48 timestamp) external view returns (uint256);

    function activeSupply() external view returns (uint256);

    function activeSharesOfAt(address account, uint48 timestamp) external view returns (uint256);

    function activeSharesOf(address account) external view returns (uint256);

    function activeBalanceOfAt(address account, uint48 timestamp) external view returns (uint256);

    function activeBalanceOf(address account) external view returns (uint256);

    function withdrawals(uint256 epoch) external view returns (uint256);

    function withdrawalsShares(uint256 epoch) external view returns (uint256);

    function withdrawalsSharesOf(uint256 epoch, address account) external view returns (uint256);

    function firstDepositAt(address account) external view returns (uint48);

    function maxSlash(address network, address resolver, address operator) external view returns (uint256);

    function slashRequestsLength() external view returns (uint256);

    function slashRequests(uint256 slashIndex)
        external
        view
        returns (
            address network,
            address resolver,
            address operator,
            uint256 amount,
            uint48 vetoDeadline,
            uint48 slashDeadline,
            bool completed
        );

    function rewardsLength(address token) external view returns (uint256);

    function rewards(
        address token,
        uint256 rewardIndex
    ) external view returns (uint256 amount, uint48 timestamp, uint48 creation);

    function lastUnclaimedReward(address account, address token) external view returns (uint256);

    function isNetworkOptedIn(address network, address resolver) external view returns (bool);

    function isOperatorOptedIn(address operator) external view returns (bool);

    function operatorOptOutAt(address operator) external view returns (uint48);

    function maxNetworkLimit(address network, address resolver) external view returns (uint256);

    function networkLimit(address network, address resolver) external view returns (uint256);

    function nextNetworkLimit(address network, address resolver) external view returns (uint256, uint48);

    function operatorLimit(address operator, address network) external view returns (uint256);

    function nextOperatorLimit(address operator, address network) external view returns (uint256, uint48);

    function hasDepositWhitelist() external view returns (bool);

    function isDepositorWhitelisted(address account) external view returns (bool);

    /**
     * @notice Set a new metadata URL for this vault.
     * @param metadataURL metadata URL of the vault
     */
    function setMetadataURL(string calldata metadataURL) external;

    function deposit(address onBehalfOf, uint256 amount) external returns (uint256 shares);

    function withdraw(address claimer, uint256 amount) external returns (uint256 burnedShares, uint256 mintedShares);

    function claim(address recipient, uint256 epoch) external returns (uint256 amount);

    function requestSlash(
        address network,
        address resolver,
        address operator,
        uint256 amount
    ) external returns (uint256 slashIndex);

    function executeSlash(uint256 slashIndex) external returns (uint256 slashedAmount);

    function vetoSlash(uint256 slashIndex) external;

    function optInNetwork(address resolver, uint256 maxNetworkLimit) external;

    function optOutNetwork(address resolver) external;

    function optInOperator() external;

    function optOutOperator() external;

    function distributeReward(
        address network,
        address token,
        uint256 amount,
        uint48 timestamp
    ) external returns (uint256 rewardIndex);

    function claimRewards(address recipient, RewardClaim[] calldata rewardClaims) external;

    function setNetworkLimit(address network, address resolver, uint256 amount) external;

    function setOperatorLimit(address operator, address network, uint256 amount) external;

    function setHasDepositWhitelist(bool value) external;

    function setDepositorWhitelistStatus(address account, bool value) external;
}
