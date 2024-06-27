// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IBaseSlasher {
    error NotNetworkMiddleware();
    error NetworkNotOptedInVault();
    error NotVault();
    error OperatorNotOptedInNetwork();
    error OperatorNotOptedInVault();

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
     * @return address of the vault to perform slashings on
     */
    function vault() external view returns (address);
}
