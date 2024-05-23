// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IVaultDelegation} from "./IVaultDelegation.sol";

interface IVault is IVaultDelegation {
    error NotNetworkMiddleware();
    error NotWhitelistedDepositor();
    error InsufficientDeposit();
    error InsufficientWithdrawal();
    error TooMuchWithdraw();
    error InvalidEpoch();
    error InsufficientClaim();
    error InsufficientSlash();
    error OperatorNotOptedInNetwork();
    error SlashRequestNotExist();
    error VetoPeriodNotEnded();
    error SlashPeriodEnded();
    error SlashCompleted();
    error NotResolver();
    error VetoPeriodEnded();

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
     * @param resolver resolver which can veto the slash
     * @param operator operator which could be slashed
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
     * @notice Get a total amount of the collateral deposited in the vault.
     * @return total amount of the collateral deposited
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
     * @notice Get a withdrawals balance for a particular account at a given epoch.
     * @param epoch epoch to get the withdrawals balance for the account at
     * @param account account to get the withdrawals balance for
     * @return withdrawals balance for the account at the epoch
     */
    function withdrawalsBalanceOf(uint256 epoch, address account) external view returns (uint256);

    /**
     * @notice Get a maximum amount of collateral that can be slashed for particular network, resolver and operator.
     * @param network address of the network
     * @param resolver address of the resolver
     * @param operator address of the operator
     * @return maximum amount of the collateral that can be slashed
     */
    function maxSlash(address network, address resolver, address operator) external view returns (uint256);

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
}
