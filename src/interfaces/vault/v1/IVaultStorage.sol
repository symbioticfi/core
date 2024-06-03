// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IVaultStorage {
    error InvalidTimestamp();
    error NoPreviousEpoch();

    /**
     * @notice Structure for a slashing limit.
     * @param amount amount of the collateral that can be slashed
     */
    struct Limit {
        uint256 amount;
    }

    /**
     * @notice Structure for a slashing limit that will be set in the future (if a new limit won't be set).
     * @param amount amount of the collateral that can be slashed
     * @param timestamp timestamp when the limit will be set
     */
    struct DelayedLimit {
        uint256 amount;
        uint48 timestamp;
    }

    /**
     * @notice Structure for a slash request.
     * @param network network that requested the slash
     * @param resolver resolver that can veto the slash
     * @param operator operator that could be slashed (if the request is not vetoed)
     * @param amount maximum amount of the collateral to be slashed
     * @param vetoDeadline deadline for the resolver to veto the slash (exclusively)
     * @param executeDeadline deadline to execute slash (exclusively)
     * @param completed if the slash was vetoed/executed
     */
    struct SlashRequest {
        address network;
        address resolver;
        address operator;
        uint256 amount;
        uint48 vetoDeadline;
        uint48 executeDeadline;
        bool completed;
    }

    /**
     * @notice Get the maximum admin fee (= 100%).
     * @return maximum admin fee
     */
    function ADMIN_FEE_BASE() external view returns (uint256);

    /**
     * @notice Get the rewards distributor setter's role.
     */
    function REWARDS_DISTRIBUTOR_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get the admin fee setter's role.
     */
    function ADMIN_FEE_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get the deposit whitelist enabler/disabler's role.
     */
    function DEPOSIT_WHITELIST_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get the depositor whitelist status setter's role.
     */
    function DEPOSITOR_WHITELIST_ROLE() external view returns (bytes32);

    /**
     * @notice Get the network-resolver limit setter's role.
     */
    function NETWORK_RESOLVER_LIMIT_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get the operator-network limit setter's role.
     */
    function OPERATOR_NETWORK_LIMIT_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get the network registry's address.
     * @return address of the network registry
     */
    function NETWORK_REGISTRY() external view returns (address);

    /**
     * @notice Get the network middleware service's address.
     * @return address of the network middleware service
     */
    function NETWORK_MIDDLEWARE_SERVICE() external view returns (address);

    /**
     * @notice Get the network-vault opt-in service's address.
     * @return address of the network-vault opt-in service
     */
    function NETWORK_VAULT_OPT_IN_SERVICE() external view returns (address);

    /**
     * @notice Get the operator-vault opt-in service's address.
     * @return address of the operator-vault opt-in service
     */
    function OPERATOR_VAULT_OPT_IN_SERVICE() external view returns (address);

    /**
     * @notice Get the operator-network opt-in service's address.
     * @return address of the operator-network opt-in service
     */
    function OPERATOR_NETWORK_OPT_IN_SERVICE() external view returns (address);

    /**
     * @notice Get a vault collateral.
     * @return vault's underlying collateral
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
     * @notice Get an epoch at a given timestamp.
     * @param timestamp time point to get the epoch at
     * @return epoch at the timestamp
     * @dev Reverts if the timestamp is less than the start of the epoch 0.
     */
    function epochAt(uint48 timestamp) external view returns (uint256);

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
     * @notice Get a start of the previous vault epoch.
     * @return start of the previous epoch
     * @dev Reverts if the current epoch is 0.
     */
    function previousEpochStart() external view returns (uint48);

    /**
     * @notice Get a duration during which resolvers can veto slash requests.
     * @return duration of the veto period
     */
    function vetoDuration() external view returns (uint48);

    /**
     * @notice Get a duration during which slash requests can be executed (after the veto period).
     * @return duration of the slash period
     */
    function executeDuration() external view returns (uint48);

    /**
     * @notice Get a rewards distributor.
     * @return address of the rewards distributor
     * @dev It must implement the IRewardsDistributor interface.
     */
    function rewardsDistributor() external view returns (address);

    /**
     * @notice Get an admin fee.
     * @return admin fee
     */
    function adminFee() external view returns (uint256);

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
     * @notice Get a timestamp when the first deposit was made by a particular account.
     * @param account account to get the timestamp when the first deposit was made for
     * @return timestamp when the first deposit was made
     */
    function firstDepositAt(address account) external view returns (uint48);

    /**
     * @notice Get a total amount of active shares in the vault at a given timestamp.
     * @param timestamp time point to get the total amount of active shares at
     * @return total amount of active shares at the timestamp
     */
    function activeSharesAt(uint48 timestamp) external view returns (uint256);

    /**
     * @notice Get a total amount of active shares in the vault.
     * @return total amount of active shares
     */
    function activeShares() external view returns (uint256);

    /**
     * @notice Get a total amount of active supply in the vault at a given timestamp.
     * @param timestamp time point to get the total active supply at
     * @return total amount of active supply at the timestamp
     */
    function activeSupplyAt(uint48 timestamp) external view returns (uint256);

    /**
     * @notice Get a total amount of active supply in the vault.
     * @return total amount of active supply
     */
    function activeSupply() external view returns (uint256);

    /**
     * @notice Get a total amount of active shares for a particular account at a given timestamp using a hint.
     * @param account account to get the amount of active shares for
     * @param timestamp time point to get the amount of active shares for the account at
     * @param hint hint for the checkpoint index
     * @return amount of active shares for the account at the timestamp
     */
    function activeSharesOfAtHint(address account, uint48 timestamp, uint32 hint) external view returns (uint256);

    /**
     * @notice Get a total amount of active shares for a particular account at a given timestamp.
     * @param account account to get the amount of active shares for
     * @param timestamp time point to get the amount of active shares for the account at
     * @return amount of active shares for the account at the timestamp
     */
    function activeSharesOfAt(address account, uint48 timestamp) external view returns (uint256);

    /**
     * @notice Get an amount of active shares for a particular account.
     * @param account account to get the amount of active shares for
     * @return amount of active shares for the account
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
     * @notice Get a total amount of the withdrawals at a given epoch.
     * @param epoch epoch to get the total amount of the withdrawals at
     * @return total amount of the withdrawals at the epoch
     */
    function withdrawals(uint256 epoch) external view returns (uint256);

    /**
     * @notice Get a total amount of withdrawal shares at a given epoch.
     * @param epoch epoch to get the total amount of withdrawal shares at
     * @return total amount of withdrawal shares at the epoch
     */
    function withdrawalShares(uint256 epoch) external view returns (uint256);

    /**
     * @notice Get an amount of pending withdrawal shares for a particular account at a given epoch (zero if claimed).
     * @param epoch epoch to get the amount of pending withdrawal shares for the account at
     * @param account account to get the amount of pending withdrawal shares for
     * @return amount of pending withdrawal shares for the account at the epoch
     */
    function pendingWithdrawalSharesOf(uint256 epoch, address account) external view returns (uint256);

    /**
     * @notice Get a total number of slash requests.
     * @return total number of slash requests
     */
    function slashRequestsLength() external view returns (uint256);

    /**
     * @notice Get a particular slash request.
     * @param slashIndex index of the slash request
     * @return network network that requested the slash
     * @return resolver resolver that can veto the slash
     * @return operator operator that could be slashed (if the request is not vetoed)
     * @return amount maximum amount of the collateral to be slashed
     * @return vetoDeadline deadline for the resolver to veto the slash (exclusively)
     * @return executeDeadline deadline to execute slash (exclusively)
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
            uint48 executeDeadline,
            bool completed
        );

    /**
     * @notice Get a maximum network-resolver limit for a particular network and resolver.
     * @param network address of the network
     * @param resolver address of the resolver
     * @return maximum network-resolver limit
     */
    function maxNetworkResolverLimit(address network, address resolver) external view returns (uint256);

    /**
     * @notice Get the next network-resolver limit for a particular network and resolver.
     * @param network address of the network
     * @param resolver address of the resolver
     * @return next network-resolver limit
     * @return timestamp when the limit will be set
     */
    function nextNetworkResolverLimit(address network, address resolver) external view returns (uint256, uint48);

    /**
     * @notice Get the next operator-network limit for a particular operator and network.
     * @param operator address of the operator
     * @param network address of the network
     * @return next operator-network limit
     * @return timestamp when the limit will be set
     */
    function nextOperatorNetworkLimit(address operator, address network) external view returns (uint256, uint48);
}
