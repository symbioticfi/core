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

    /**
     * @notice Initial parameters needed for a vault deployment.
     * @param owner owner of the vault (can set metadata and enable/disable deposit whitelist)
     * @param metadataURL URL with metadata of the vault
     * The metadata should contain: name, description, external_url, image.
     * @param collateral underlying vault collateral
     * @param epochDuration duration of an vault epoch
     * @param vetoDuration duration of the veto period for a slash request
     * @param slashDuration duration of the slash period for a slash request (after veto period)
     * @param depositWhitelist enable/disable deposit whitelist
     */
    struct InitParams {
        address owner;
        string metadataURL;
        address collateral;
        uint48 epochDuration;
        uint48 vetoDuration;
        uint48 slashDuration;
        bool depositWhitelist;
    }

    /**
     * @notice Structure for a slashing limit.
     * @param amount amount of the collateral that can be slashed
     */
    struct Limit {
        uint256 amount;
    }

    /**
     * @notice Structure for a slashing limit which will be set in the future.
     * @param amount amount of the collateral that can be slashed
     * @param timestamp timestamp when the limit will be set
     */
    struct DelayedLimit {
        uint256 amount;
        uint48 timestamp;
    }

    /**
     * @notice Structure for a slash request.
     * @param network network which requested the slash
     * @param resolver resolver who can veto the slash
     * @param operator operator who could be slashed
     * @param amount maximum amount of the collateral to be slashed
     * @param vetoDeadline deadline for the resolver to veto the slash
     * @param slashDeadline deadline to execute slash
     * @param completed if the slash was vetoed/executed
     *
     */
    struct SlashRequest {
        address network;
        address resolver;
        address operator;
        uint256 amount;
        uint48 vetoDeadline;
        uint48 slashDeadline;
        bool completed;
    }

    /**
     * @notice Structure for a reward distribution.
     * @param network network on behalf of which the reward is distributed
     * @param amount amount of tokens to be distributed
     * @param timestamp time point stakes must taken into account at
     * @param creation timestamp when the reward distribution was created
     */
    struct RewardDistribution {
        address network;
        uint256 amount;
        uint48 timestamp;
        uint48 creation;
    }

    /**
     * @notice Structure for a reward claim.
     * @param token address of the token to be claimed
     * @param maxRewards max amount of rewards to be processed
     * @param activeSharesOfHints hint indexes to optimize `activeSharesOf()` processing
     */
    struct RewardClaim {
        address token;
        uint256 maxRewards;
        uint32[] activeSharesOfHints;
    }

    /**
     * @notice Emitted when a metadata URL is set.
     * @param metadataURL metadata URL of the vault
     */
    event SetMetadataURL(string metadataURL);

    /**
     * @notice Emitted when a deposit is made.
     * @param depositor account that made the deposit
     * @param onBehalfOf account that the deposit was made on behalf of
     * @param amount amount of the collateral deposited
     * @param shares amount of the active supply shares minted
     */
    event Deposit(address indexed depositor, address indexed onBehalfOf, uint256 amount, uint256 shares);

    /**
     * @notice Emitted when a withdrawal is made.
     * @param withdrawer account that made the withdrawal
     * @param claimer account that need to claim the withdrawal
     * @param amount amount of the collateral withdrawn
     * @param burnedShares amount of the active supply shares burned
     * @param mintedShares amount of the epoch withdrawal shares minted
     */
    event Withdraw(
        address indexed withdrawer, address indexed claimer, uint256 amount, uint256 burnedShares, uint256 mintedShares
    );

    /**
     * @notice Emitted when a claim is made.
     * @param claimer account that made the claim
     * @param recipient account that received the collateral
     * @param amount amount of the collateral claimed
     */
    event Claim(address indexed claimer, address indexed recipient, uint256 amount);

    /**
     * @notice Emitted when a slash request is made.
     * @param slashIndex index of the slash request
     * @param network network which requested the slash
     * @param resolver resolver who can veto the slash
     * @param operator operator who could be slashed
     * @param slashAmount maximum amount of the collateral to be slashed
     * @param vetoDeadline deadline for the resolver to veto the slash
     * @param slashDeadline deadline to execute slash
     */
    event RequestSlash(
        uint256 indexed slashIndex,
        address indexed network,
        address resolver,
        address indexed operator,
        uint256 slashAmount,
        uint48 vetoDeadline,
        uint48 slashDeadline
    );

    /**
     * @notice Emitted when a slash request is executed.
     * @param slashIndex index of the slash request
     * @param slashedAmount amount of the collateral slashed
     */
    event ExecuteSlash(uint256 indexed slashIndex, uint256 slashedAmount);

    /**
     * @notice Emitted when a slash request is vetoed.
     * @param slashIndex index of the slash request
     */
    event VetoSlash(uint256 indexed slashIndex);

    /**
     * @notice Emitted when a network opts in.
     * @param network network which opted in
     * @param resolver resolver who can veto the the network's slash requests
     */
    event OptInNetwork(address indexed network, address indexed resolver);

    /**
     * @notice Emitted when a network opts out.
     * @param network network which opted out
     * @param resolver resolver who could veto the the network's slash requests
     */
    event OptOutNetwork(address indexed network, address indexed resolver);

    /**
     * @notice Emitted when an operator opts in.
     * @param operator operator who opted in
     */
    event OptInOperator(address indexed operator);

    /**
     * @notice Emitted when an operator opts out.
     * @param operator operator who opted out
     */
    event OptOutOperator(address indexed operator);

    /**
     * @notice Emitted when a reward is distributed.
     * @param token address of the token to be distributed
     * @param rewardIndex index of the reward distribution
     * @param network network on behalf of which the reward is distributed
     * @param amount amount of tokens distributed
     * @param timestamp time point stakes must taken into account at
     */
    event DistributeReward(
        address indexed token, uint256 indexed rewardIndex, address indexed network, uint256 amount, uint48 timestamp
    );

    /**
     * @notice Emitted when a reward is claimed.
     * @param token address of the token claimed
     * @param rewardIndex index of the reward distribution
     * @param claimer account that claimed the reward
     * @param recipient account that received the reward
     * @param claimedAmount amount of tokens claimed
     */
    event ClaimReward(
        address indexed token,
        uint256 indexed rewardIndex,
        address indexed claimer,
        address recipient,
        uint256 claimedAmount
    );

    /**
     * @notice Emitted when a network limit is set.
     * @param network network for which the limit is set
     * @param resolver resolver for which the limit is set
     * @param amount amount of the collateral that can be slashed
     */
    event SetNetworkLimit(address indexed network, address indexed resolver, uint256 amount);

    /**
     * @notice Emitted when an operator limit is set.
     * @param operator operator for which the limit is set
     * @param network network for which the limit is set
     * @param amount amount of the collateral that can be slashed
     */
    event SetOperatorLimit(address indexed operator, address indexed network, uint256 amount);

    /**
     * @notice Emitted when deposit whitelist status is set.
     * @param depositWhitelist enable/disable deposit whitelist
     */
    event SetDepositWhitelist(bool depositWhitelist);

    /**
     * @notice Emitted when a depositor whitelist status is set.
     * @param account account for which the whitelist status is set
     * @param value whitelist status
     */
    event SetDepositorWhitelistStatus(address indexed account, bool value);

    /**
     * @notice Get the network limit setter's role.
     */
    function NETWORK_LIMIT_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get the operator limit setter's role.
     */
    function OPERATOR_LIMIT_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get the deposit whitelist enabler/disabler's role.
     */
    function DEPOSIT_WHITELIST_ROLE() external view returns (bytes32);

    /**
     * @notice Get the depositor whitelist status setter's role.
     */
    function DEPOSITOR_WHITELIST_ROLE() external view returns (bytes32);

    /**
     * @notice Get the network registry's address.
     * @return address of the registry
     */
    function NETWORK_REGISTRY() external view returns (address);

    /**
     * @notice Get the operator registry's address.
     * @return address of the operator registry
     */
    function OPERATOR_REGISTRY() external view returns (address);

    /**
     * @notice Get the network middleware plugin's address.
     * @return address of the network middleware plugin
     */
    function NETWORK_MIDDLEWARE_PLUGIN() external view returns (address);

    /**
     * @notice Get the network opt-in plugin's address.
     * @return address of the network opt-in plugin
     */
    function NETWORK_OPT_IN_PLUGIN() external view returns (address);

    /**
     * @notice Get a URL with a vault's metadata.
     * The metadata should contain: name, description, external_url, image.
     * @return metadata URL of the vault
     */
    function metadataURL() external view returns (string memory);

    /**
     * @notice Get a vault collateral.
     * @return collateral underlying vault
     */
    function collateral() external view returns (address);

    /**
     * @notice Get a time point of the epoch duration set.
     * @return time point of the epoch duration set
     */
    function epochDurationInit() external view returns (uint48);

    /**
     * @notice Get a duration of the vault epoch.
     * @return duration of the epoch
     */
    function epochDuration() external view returns (uint48);

    /**
     * @notice Get a current vault epoch.
     * @return current epoch
     */
    function currentEpoch() external view returns (uint256);

    /**
     * @notice Get a start of the current vault epoch.
     * @return start of the current epoch
     */
    function currentEpochStart() external view returns (uint48);

    /**
     * @notice Get a duration during which resolvers can veto slash requests.
     * @return duration of the veto period
     */
    function vetoDuration() external view returns (uint48);

    /**
     * @notice Get a duration during which slash requests can be executed (after veto period).
     * @return duration of the slash period
     */
    function slashDuration() external view returns (uint48);

    /**
     * @notice Get a total amount of the collateral deposited in the vault.
     * @return total amount of the collateral deposited
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice Get a total amount of the active shares in the vault at a given timestamp.
     * @param timestamp time point to get the total amount of the active shares at
     * @return total amount of the active shares at the timestamp
     */
    function activeSharesAt(uint48 timestamp) external view returns (uint256);

    /**
     * @notice Get a total amount of the active shares in the vault.
     * @return total amount of the active shares
     */
    function activeShares() external view returns (uint256);

    /**
     * @notice Get a total amount of the active supply in the vault at a given timestamp.
     * @param timestamp time point to get the total active supply at
     * @return total amount of the active supply at the timestamp
     */
    function activeSupplyAt(uint48 timestamp) external view returns (uint256);

    /**
     * @notice Get a total amount of the active supply in the vault.
     * @return total amount of the active supply
     */
    function activeSupply() external view returns (uint256);

    /**
     * @notice Get a total amount of the active shares for a particular account at a given timestamp.
     * @param account account to get the amount of the active shares for
     * @param timestamp time point to get the amount of the active shares for the account at
     * @return total amount of the active shares for the account at the timestamp
     */
    function activeSharesOfAt(address account, uint48 timestamp) external view returns (uint256);

    /**
     * @notice Get an amount of the active shares for a particular account.
     * @param account account to get the amount of the active shares for
     * @return amount of the active shares for the account
     */
    function activeSharesOf(address account) external view returns (uint256);

    /**
     * @notice Get a total number of the activeSharesOf checkpoints for a particular account.
     * @param account account to get the total number of the activeSharesOf checkpoints for
     * @return total number of the activeSharesOf checkpoints for the account
     */
    function activeSharesOfCheckpointsLength(address account) external view returns (uint256);

    /**
     * @notice Get an activeSharesOf checkpoint for a particular account at a given index.
     * @param account account to get the activeSharesOf checkpoint for
     * @param pos index of the checkpoint
     * @return timestamp time point of the checkpoint
     * @return amount of active shares at the checkpoint
     */
    function activeSharesOfCheckpoint(address account, uint32 pos) external view returns (uint48, uint256);

    /**
     * @notice Get an active balance for a particular account at a given timestamp.
     * @param account account to get the active balance for
     * @param timestamp time point to get the active balance for the account at
     * @return active balance for the account at the timestamp
     */
    function activeBalanceOfAt(address account, uint48 timestamp) external view returns (uint256);

    /**
     * @notice Get an active balance for a particular account.
     * @param account account to get the active balance for
     * @return active balance for the account
     */
    function activeBalanceOf(address account) external view returns (uint256);

    /**
     * @notice Get a total amount of the withdrawals at a given epoch.
     * @param epoch epoch to get the total amount of the withdrawals at
     * @return total amount of the withdrawals at the epoch
     */
    function withdrawals(uint256 epoch) external view returns (uint256);

    /**
     * @notice Get a total amount of the withdrawals shares at a given epoch.
     * @param epoch epoch to get the total amount of the withdrawals shares at
     * @return total amount of the withdrawals shares at the epoch
     */
    function withdrawalsShares(uint256 epoch) external view returns (uint256);

    /**
     * @notice Get an amount of the withdrawals shares for a particular account at a given epoch.
     * @param epoch epoch to get the amount of the withdrawals shares for the account at
     * @param account account to get the amount of the withdrawals shares for
     * @return amount of the withdrawals shares for the account at the epoch
     */
    function withdrawalsSharesOf(uint256 epoch, address account) external view returns (uint256);

    /**
     * @notice Get a withdrawals balance for a particular account at a given epoch.
     * @param epoch epoch to get the withdrawals balance for the account at
     * @param account account to get the withdrawals balance for
     * @return withdrawals balance for the account at the epoch
     */
    function withdrawalsBalanceOf(uint256 epoch, address account) external view returns (uint256);

    /**
     * @notice Get a timestamp when the first deposit was made by a particular account.
     * @param account account to get the timestamp when the first deposit was made for
     * @return timestamp when the first deposit was made
     */
    function firstDepositAt(address account) external view returns (uint48);

    /**
     * @notice Get a maximum amount of collateral that can be slashed for particular network, resolver and operator.
     * @param network address of the network
     * @param resolver address of the resolver
     * @param operator address of the operator
     * @return maximum amount of the collateral that can be slashed
     */
    function maxSlash(address network, address resolver, address operator) external view returns (uint256);

    /**
     * @notice Get a total number of slash requests.
     * @return total number of slash requests
     */
    function slashRequestsLength() external view returns (uint256);

    /**
     * @notice Get a slash request.
     * @param slashIndex index of the slash request
     * @return network network which requested the slash
     * @return resolver resolver who can veto the slash
     * @return operator operator who could be slashed
     * @return amount maximum amount of the collateral to be slashed
     * @return vetoDeadline deadline for the resolver to veto the slash
     * @return slashDeadline deadline to execute slash
     * @return completed if the slash was vetoed/executed
     */
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

    /**
     * @notice Get a total number of rewards using a particular token.
     * @param token address of the token
     * @return total number of rewards using the token
     */
    function rewardsLength(address token) external view returns (uint256);

    /**
     * @notice Get a reward distribution.
     * @param token address of the token
     * @param rewardIndex index of the reward distribution
     * @return network network on behalf of which the reward is distributed
     * @return amount amount of tokens to be distributed
     * @return timestamp time point stakes must taken into account at
     * @return creation timestamp when the reward distribution was created
     */
    function rewards(
        address token,
        uint256 rewardIndex
    ) external view returns (address network, uint256 amount, uint48 timestamp, uint48 creation);

    /**
     * @notice Get a first index of the unclaimed rewards using a particular token by a given account.
     * @param account address of the account
     * @param token address of the token
     * @return first index of the unclaimed rewards
     */
    function lastUnclaimedReward(address account, address token) external view returns (uint256);

    /**
     * @notice Get if a given network-resolver pair is opted in.
     * @return if the network-resolver pair is opted in
     */
    function isNetworkOptedIn(address network, address resolver) external view returns (bool);

    /**
     * @notice Get if a given operator is opted in.
     * @return if the operator is opted in
     */
    function isOperatorOptedIn(address operator) external view returns (bool);

    /**
     * @notice Get a timestamp of last operator opt-out.
     * @param operator address of the operator
     * @return timestamp of the last operator opt-out
     */
    function operatorOptOutAt(address operator) external view returns (uint48);

    /**
     * @notice Get a maximum network limit for a particular network and resolver.
     * @param network address of the network
     * @param resolver address of the resolver
     * @return maximum network limit
     */
    function maxNetworkLimit(address network, address resolver) external view returns (uint256);

    /**
     * @notice Get a network limit for a particular network and resolver.
     * @param network address of the network
     * @param resolver address of the resolver
     * @return network limit
     */
    function networkLimit(address network, address resolver) external view returns (uint256);

    /**
     * @notice Get next network limit for a particular network and resolver.
     * @param network address of the network
     * @param resolver address of the resolver
     * @return next network limit
     * @return timestamp when the limit will be set
     */
    function nextNetworkLimit(address network, address resolver) external view returns (uint256, uint48);

    /**
     * @notice Get an operator limit for a particular operator and network.
     * @param operator address of the operator
     * @param network address of the network
     * @return operator limit
     */
    function operatorLimit(address operator, address network) external view returns (uint256);

    /**
     * @notice Get next operator limit for a particular operator and network.
     * @param operator address of the operator
     * @param network address of the network
     * @return next operator limit
     * @return timestamp when the limit will be set
     */
    function nextOperatorLimit(address operator, address network) external view returns (uint256, uint48);

    /**
     * @notice Get if the deposit whitelist is enabled.
     * @return if the deposit whitelist is enabled
     */
    function depositWhitelist() external view returns (bool);

    /**
     * @notice Get if a given account is whitelisted as a depositor.
     * @param account address to check
     * @return if the account is whitelisted as a depositor
     */
    function isDepositorWhitelisted(address account) external view returns (bool);

    /**
     * @notice Set a new metadata URL for this vault.
     * @param metadataURL metadata URL of the vault
     * The metadata should contain: name, description, external_url, image.
     */
    function setMetadataURL(string calldata metadataURL) external;

    /**
     * @notice Deposit collateral into the vault.
     * @param onBehalfOf account that the deposit is made on behalf of
     * @param amount amount of the collateral to deposit
     * @return shares amount of the active supply shares minted
     */
    function deposit(address onBehalfOf, uint256 amount) external returns (uint256 shares);

    /**
     * @notice Withdraw collateral from the vault.
     * @param claimer account that needs to claim the withdrawal
     * @param amount amount of the collateral to withdraw
     * @return burnedShares amount of the active supply shares burned
     * @return mintedShares amount of the epoch withdrawal shares minted
     */
    function withdraw(address claimer, uint256 amount) external returns (uint256 burnedShares, uint256 mintedShares);

    /**
     * @notice Claim collateral from the vault.
     * @param recipient account that receives the collateral
     * @param epoch epoch to claim the collateral for
     * @return amount amount of the collateral claimed
     */
    function claim(address recipient, uint256 epoch) external returns (uint256 amount);

    /**
     * @notice Request a slash for a particular network, resolver and operator.
     * @param network address of the network
     * @param resolver address of the resolver
     * @param operator address of the operator
     * @param amount maximum amount of the collateral to be slashed
     * @return slashIndex index of the slash request
     * @dev Only network middleware can call this function.
     */
    function requestSlash(
        address network,
        address resolver,
        address operator,
        uint256 amount
    ) external returns (uint256 slashIndex);

    /**
     * @notice Execute a slash with a given slash index.
     * @param slashIndex index of the slash request
     * @return slashedAmount amount of the collateral slashed
     */
    function executeSlash(uint256 slashIndex) external returns (uint256 slashedAmount);

    /**
     * @notice Veto a slash with a given slash index.
     * @param slashIndex index of the slash request
     */
    function vetoSlash(uint256 slashIndex) external;

    /**
     * @notice Opt in a network with a given resolver.
     * @param resolver address of the resolver
     * @param maxNetworkLimit maximum network limit
     * @dev Only network can call this function.
     */
    function optInNetwork(address resolver, uint256 maxNetworkLimit) external;

    /**
     * @notice Opt out a network with a given resolver.
     * @param resolver address of the resolver
     * @dev Only network can call this function.
     */
    function optOutNetwork(address resolver) external;

    /**
     * @notice Opt in an operator.
     * @dev Only operator can call this function.
     */
    function optInOperator() external;

    /**
     * @notice Opt out an operator.
     * @dev Only operator can call this function.
     */
    function optOutOperator() external;

    /**
     * @notice Distribute rewards on behalf of a particular network using a given token.
     * @param network address of the network
     * @param token address of the token
     * @param amount amount of tokens to distribute
     * @param timestamp time point stakes must taken into account at
     * @return rewardIndex index of the reward distribution
     */
    function distributeReward(
        address network,
        address token,
        uint256 amount,
        uint48 timestamp
    ) external returns (uint256 rewardIndex);

    /**
     * @notice Claim rewards using a given reward claims.
     * @param recipient account that receives the rewards
     * @param rewardClaims reward claims to process
     */
    function claimRewards(address recipient, RewardClaim[] calldata rewardClaims) external;

    /**
     * @notice Set a network limit for a particular network and resolver.
     * @param network address of the network
     * @param resolver address of the resolver
     * @param amount maximum amount of the collateral that can be slashed
     * @dev Only NETWORK_LIMIT_SET_ROLE holder can call this function.
     */
    function setNetworkLimit(address network, address resolver, uint256 amount) external;

    /**
     * @notice Set an operator limit for a particular operator and network.
     * @param operator address of the operator
     * @param network address of the network
     * @param amount maximum amount of the collateral that can be slashed
     * @dev Only OPERATOR_LIMIT_SET_ROLE holder can call this function.
     */
    function setOperatorLimit(address operator, address network, uint256 amount) external;

    /**
     * @notice Enable/disable deposit whitelist.
     * @param status enable/disable deposit whitelist
     * @dev Only DEPOSIT_WHITELIST_ROLE holder can call this function.
     */
    function setDepositWhitelist(bool status) external;

    /**
     * @notice Set a depositor whitelist status.
     * @param account account for which the whitelist status is set
     * @param status whitelist status
     * @dev Only DEPOSITOR_WHITELIST_ROLE holder can call this function.
     */
    function setDepositorWhitelistStatus(address account, bool status) external;
}
