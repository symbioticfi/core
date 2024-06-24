// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IVaultStorage} from "./IVaultStorage.sol";

interface IVault is IVaultStorage {
    error AlreadyClaimed();
    error AlreadySet();
    error ExceedsMaxNetworkResolverLimit();
    error InsufficientClaim();
    error InsufficientDeposit();
    error InsufficientSlash();
    error InsufficientWithdrawal();
    error InvalidAccount();
    error InvalidAdminFee();
    error InvalidClaimer();
    error InvalidCollateral();
    error InvalidEpoch();
    error InvalidEpochDuration();
    error InvalidOnBehalfOf();
    error InvalidRecipient();
    error InvalidSlashDuration();
    error InvalidVetoDuration();
    error NetworkNotOptedInVault();
    error NoDepositWhitelist();
    error NotNetwork();
    error NotNetworkMiddleware();
    error NotOperator();
    error NotResolver();
    error NotWhitelistedDepositor();
    error OperatorNotOptedInNetwork();
    error OperatorNotOptedInVault();
    error SlashCompleted();
    error SlashPeriodEnded();
    error SlashRequestNotExist();
    error TooMuchWithdraw();
    error VetoPeriodEnded();
    error VetoPeriodNotEnded();

    /**
     * @notice Initial parameters needed for a vault deployment.
     * @param collateral vault's underlying collateral
     * @param epochDuration duration of the vault epoch (it determines sync points for withdrawals)
     * @param vetoDuration duration of the veto period for a slash request
     * @param executeDuration duration of the slash period for a slash request (after the veto duration has passed)
     * @param rewardsDistributor address of the rewards distributor (it must implement IRewardsDistributor interface)
     * @param adminFee admin fee (up to ADMIN_FEE_BASE inclusively)
     * @param depositWhitelist if enabling deposit whitelist
     */
    struct InitParams {
        address collateral;
        uint48 epochDuration;
        uint48 vetoDuration;
        uint48 executeDuration;
        address rewardsDistributor;
        uint256 adminFee;
        bool depositWhitelist;
    }

    /**
     * @notice Emitted when a deposit is made.
     * @param depositor account that made the deposit
     * @param onBehalfOf account the deposit was made on behalf of
     * @param amount amount of the collateral deposited
     * @param shares amount of the active shares minted
     */
    event Deposit(address indexed depositor, address indexed onBehalfOf, uint256 amount, uint256 shares);

    /**
     * @notice Emitted when a withdrawal is made.
     * @param withdrawer account that made the withdrawal
     * @param claimer account that needs to claim the withdrawal
     * @param amount amount of the collateral withdrawn
     * @param burnedShares amount of the active shares burned
     * @param mintedShares amount of the epoch withdrawal shares minted
     */
    event Withdraw(
        address indexed withdrawer, address indexed claimer, uint256 amount, uint256 burnedShares, uint256 mintedShares
    );

    /**
     * @notice Emitted when a claim is made.
     * @param claimer account that claimed
     * @param recipient account that received the collateral
     * @param amount amount of the collateral claimed
     */
    event Claim(address indexed claimer, address indexed recipient, uint256 amount);

    /**
     * @notice Emitted when a slash request is created.
     * @param slashIndex index of the slash request
     * @param network network that requested the slash
     * @param resolver resolver that can veto the slash
     * @param operator operator that could be slashed (if the request is not vetoed)
     * @param slashAmount maximum amount of the collateral to be slashed
     * @param vetoDeadline deadline for the resolver to veto the slash (exclusively)
     * @param executeDeadline deadline to execute slash (exclusively)
     */
    event RequestSlash(
        uint256 indexed slashIndex,
        address indexed network,
        address resolver,
        address indexed operator,
        uint256 slashAmount,
        uint48 vetoDeadline,
        uint48 executeDeadline
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
     * @notice Emitted when a maximum network-resolver limit is set.
     * @param network address of the network
     * @param resolver address of the resolver
     * @param amount maximum network-resolver limit that can be set
     */
    event SetMaxNetworkResolverLimit(address indexed network, address indexed resolver, uint256 amount);

    /**
     * @notice Emitted when a network-resolver limit is set.
     * @param network address of the network
     * @param resolver address of the resolver
     * @param amount maximum amount of the collateral that can be slashed
     */
    event SetNetworkResolverLimit(address indexed network, address indexed resolver, uint256 amount);

    /**
     * @notice Emitted when an operator-network limit is set.
     * @param operator address of the operator
     * @param network address of the network
     * @param amount maximum amount of the collateral that can be slashed
     */
    event SetOperatorNetworkLimit(address indexed operator, address indexed network, uint256 amount);

    /**
     * @notice Emitted when a rewards distributor is set.
     * @param rewardsDistributor address of the rewards distributor
     */
    event SetRewardsDistributor(address rewardsDistributor);

    /**
     * @notice Emitted when an admin fee is set.
     * @param adminFee admin fee
     */
    event SetAdminFee(uint256 adminFee);

    /**
     * @notice Emitted when a deposit whitelist status is enabled/disabled.
     * @param depositWhitelist if enabled deposit whitelist
     */
    event SetDepositWhitelist(bool depositWhitelist);

    /**
     * @notice Emitted when a depositor whitelist status is set.
     * @param account account for which the whitelist status is set
     * @param status if whitelisted the account
     */
    event SetDepositorWhitelistStatus(address indexed account, bool status);

    /**
     * @notice Get a total amount of the collateral that can be slashed
     *         in `duration` seconds (if there will be no new deposits and slash executions).
     * @param duration duration to get the total amount of the slashable collateral in
     * @return total amount of the slashable collateral in `duration` seconds
     */
    function totalSupplyIn(uint48 duration) external view returns (uint256);

    /**
     * @notice Get a total amount of the collateral that can be slashed.
     * @return total amount of the slashable collateral
     */
    function totalSupply() external view returns (uint256);

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
     * @notice Get pending withdrawals for a particular account at a given epoch (zero if claimed).
     * @param epoch epoch to get the pending withdrawals for the account at
     * @param account account to get the pending withdrawals for
     * @return pending withdrawals for the account at the epoch
     */
    function pendingWithdrawalsOf(uint256 epoch, address account) external view returns (uint256);

    /**
     * @notice Get a maximum amount of collateral that can be slashed
     *         for a particular network, resolver, and operator in `duration` seconds.
     * @param network address of the network
     * @param resolver address of the resolver
     * @param operator address of the operator
     * @param duration duration to get the slashable amount in
     * @return maximum amount of the collateral that can be slashed in `duration` seconds
     */
    function slashableAmountIn(
        address network,
        address resolver,
        address operator,
        uint48 duration
    ) external view returns (uint256);

    /**
     * @notice Get a maximum amount of collateral that can be slashed for a particular network, resolver, and operator.
     * @param network address of the network
     * @param resolver address of the resolver
     * @param operator address of the operator
     * @return maximum amount of the collateral that can be slashed
     */
    function slashableAmount(address network, address resolver, address operator) external view returns (uint256);

    /**
     * @notice Get a network-resolver limit for a particular network and resolver in `duration` seconds.
     * @param network address of the network
     * @param resolver address of the resolver
     * @param duration duration to get the network-resolver limit in
     * @return network-resolver limit in `duration` seconds
     */
    function networkResolverLimitIn(
        address network,
        address resolver,
        uint48 duration
    ) external view returns (uint256);

    /**
     * @notice Get a network-resolver limit for a particular network and resolver.
     * @param network address of the network
     * @param resolver address of the resolver
     * @return network-resolver limit
     */
    function networkResolverLimit(address network, address resolver) external view returns (uint256);

    /**
     * @notice Get an operator-network limit for a particular operator and network in `duration` seconds.
     * @param operator address of the operator
     * @param network address of the network
     * @param duration duration to get the operator-network limit in
     * @return operator-network limit in `duration` seconds
     */
    function operatorNetworkLimitIn(
        address operator,
        address network,
        uint48 duration
    ) external view returns (uint256);

    /**
     * @notice Get an operator-network limit for a particular operator and network.
     * @param operator address of the operator
     * @param network address of the network
     * @return operator-network limit
     */
    function operatorNetworkLimit(address operator, address network) external view returns (uint256);

    /**
     * @notice Get a minimum stake that a given network will be able to slash using a particular resolver
     *         for a certain operator during `duration` (if no cross-slashing).
     * @param network address of the network
     * @param resolver address of the resolver
     * @param operator address of the operator
     * @param duration duration to get the minimum slashable stake during
     * @return minimum slashable stake during `duration`
     */
    function minStakeDuring(
        address network,
        address resolver,
        address operator,
        uint48 duration
    ) external view returns (uint256);

    /**
     * @notice Deposit collateral into the vault.
     * @param onBehalfOf account the deposit is made on behalf of
     * @param amount amount of the collateral to deposit
     * @return shares amount of the active shares minted
     */
    function deposit(address onBehalfOf, uint256 amount) external returns (uint256 shares);

    /**
     * @notice Withdraw collateral from the vault (it will be claimable after the next epoch).
     * @param claimer account that needs to claim the withdrawal
     * @param amount amount of the collateral to withdraw
     * @return burnedShares amount of the active shares burned
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
     * @notice Request a slash using a network and a resolver for a particular operator by a given amount.
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
     * @dev Anyone can call this function.
     */
    function executeSlash(uint256 slashIndex) external returns (uint256 slashedAmount);

    /**
     * @notice Veto a slash with a given slash index.
     * @param slashIndex index of the slash request
     * @dev Only a resolver can call this function.
     */
    function vetoSlash(uint256 slashIndex) external;

    /**
     * @notice Set a maximum network-resolver limit.
     * @param resolver address of the resolver
     * @param amount maximum network-resolver limit that can be set
     * @dev Only a network can call this function.
     */
    function setMaxNetworkResolverLimit(address resolver, uint256 amount) external;

    /**
     * @notice Set a network-resolver limit for a particular network and resolver.
     * @param network address of the network
     * @param resolver address of the resolver
     * @param amount new maximum amount of the collateral that can be slashed
     * @dev Only the NETWORK_RESOLVER_LIMIT_SET_ROLE holder can call this function.
     */
    function setNetworkResolverLimit(address network, address resolver, uint256 amount) external;

    /**
     * @notice Set an operator-network limit for a particular operator and network.
     * @param operator address of the operator
     * @param network address of the network
     * @param amount new maximum amount of the collateral that can be slashed
     * @dev Only the OPERATOR_NETWORK_LIMIT_SET_ROLE holder can call this function.
     */
    function setOperatorNetworkLimit(address operator, address network, uint256 amount) external;

    /**
     * @notice Set a rewards distributor.
     * @param rewardsDistributor address of the rewards distributor
     * @dev Only the REWARDS_DISTRIBUTOR_SET_ROLE holder can call this function.
     */
    function setRewardsDistributor(address rewardsDistributor) external;

    /**
     * @notice Set an admin fee.
     * @param adminFee admin fee (up to ADMIN_FEE_BASE inclusively)
     * @dev Only the ADMIN_FEE_SET_ROLE holder can call this function.
     */
    function setAdminFee(uint256 adminFee) external;

    /**
     * @notice Enable/disable deposit whitelist.
     * @param status if enabling deposit whitelist
     * @dev Only the DEPOSIT_WHITELIST_SET_ROLE holder can call this function.
     */
    function setDepositWhitelist(bool status) external;

    /**
     * @notice Set a depositor whitelist status.
     * @param account account for which the whitelist status is set
     * @param status if whitelisting the account
     * @dev Only the DEPOSITOR_WHITELIST_ROLE holder can call this function.
     */
    function setDepositorWhitelistStatus(address account, bool status) external;
}
