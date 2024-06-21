// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface INonResolvableSlasher {
    error InsufficientSlash();
    error NetworkNotOptedInVault();
    error NotNetwork();
    error NotNetworkMiddleware();
    error NotOperator();
    error NotResolver();
    error NotVault();
    error OperatorNotOptedInNetwork();
    error OperatorNotOptedInVault();

    struct InitParams {
        address vault;
    }

    /**
     * @notice Emitted when a slash request is created.
     * @param network network that requested the slash
     * @param operator operator that could be slashed (if the request is not vetoed)
     * @param slashAmount maximum amount of the collateral to be slashed
     */
    event Slash(address indexed network, address indexed operator, uint256 slashAmount);

    /**
     * @notice Get the vault factory's address.
     * @return address of the vault factory
     */
    function VAULT_FACTORY() external view returns (address);

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
     * @notice Get the vault's address.
     * @return address of the vault
     */
    function vault() external view returns (address);

    /**
     * @notice Perform a slash using a network for a particular operator by a given amount.
     * @param network address of the network
     * @param operator address of the operator
     * @param amount maximum amount of the collateral to be slashed
     * @return slashedAmount amount of the collateral slashed
     * @dev Only network middleware can call this function.
     */
    function slash(address network, address operator, uint256 amount) external returns (uint256 slashedAmount);
}
