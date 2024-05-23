// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IVaultStorage {
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
     * @param resolver resolver which can veto the slash
     * @param operator operator which could be slashed
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
     * @notice Get the maximum admin fee (= 100%).
     * @return maximum admin fee
     */
    function ADMIN_FEE_BASE() external view returns (uint256);

    /**
     * @notice Get the network limit setter's role.
     */
    function NETWORK_LIMIT_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get the operator limit setter's role.
     */
    function OPERATOR_LIMIT_SET_ROLE() external view returns (bytes32);

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
     * @notice Get the network-vault opt-in plugin's address.
     * @return address of the network-vault opt-in plugin
     */
    function NETWORK_VAULT_OPT_IN_PLUGIN() external view returns (address);

    /**
     * @notice Get the operator-vault opt-in plugin's address.
     * @return address of the operator-vault opt-in plugin
     */
    function OPERATOR_VAULT_OPT_IN_PLUGIN() external view returns (address);

    /**
     * @notice Get the operator-network opt-in plugin's address.
     * @return address of the operator-network opt-in plugin
     */
    function OPERATOR_NETWORK_OPT_IN_PLUGIN() external view returns (address);

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
     * @notice Get a start of the previous vault epoch.
     * @return start of the previous epoch
     */
    function previousEpochStart() external view returns (uint48);

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
     * @notice Get a total amount of the active shares for a particular account at a given timestamp using a hint.
     * @param account account to get the amount of the active shares for
     * @param timestamp time point to get the amount of the active shares for the account at
     * @param hint hint for the checkpoint index
     * @return total amount of the active shares for the account at the timestamp
     */
    function activeSharesOfAtHint(address account, uint48 timestamp, uint32 hint) external view returns (uint256);

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
     * @notice Get a timestamp when the first deposit was made by a particular account.
     * @param account account to get the timestamp when the first deposit was made for
     * @return timestamp when the first deposit was made
     */
    function firstDepositAt(address account) external view returns (uint48);

    /**
     * @notice Get a total number of slash requests.
     * @return total number of slash requests
     */
    function slashRequestsLength() external view returns (uint256);

    /**
     * @notice Get a slash request.
     * @param slashIndex index of the slash request
     * @return network network which requested the slash
     * @return resolver resolver which can veto the slash
     * @return operator operator which could be slashed
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
     * @notice Get a maximum network limit for a particular network and resolver.
     * @param network address of the network
     * @param resolver address of the resolver
     * @return maximum network limit
     */
    function maxNetworkLimit(address network, address resolver) external view returns (uint256);

    /**
     * @notice Get next network limit for a particular network and resolver.
     * @param network address of the network
     * @param resolver address of the resolver
     * @return next network limit
     * @return timestamp when the limit will be set
     */
    function nextNetworkLimit(address network, address resolver) external view returns (uint256, uint48);

    /**
     * @notice Get next operator limit for a particular operator and network.
     * @param operator address of the operator
     * @param network address of the network
     * @return next operator limit
     * @return timestamp when the limit will be set
     */
    function nextOperatorLimit(address operator, address network) external view returns (uint256, uint48);
}
