// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ICreateX
 * @notice Interface for the CreateX factory contract that provides CREATE3 deployment functionality
 * @dev CreateX is a factory contract that enables deterministic contract deployment using CREATE3
 * https://github.com/pcaversaccio/createx/tree/main
 */
interface ICreateX {
    struct Values {
        uint256 constructorAmount;
        uint256 initCallAmount;
    }

    function deployCreate3(bytes32 salt, bytes memory initCode) external payable returns (address);
    function computeCreate3Address(
        bytes32 salt
    ) external view returns (address computedAddress);
    function deployCreate3AndInit(
        bytes32 salt,
        bytes memory initCode,
        bytes memory data,
        Values memory values
    ) external payable returns (address newContract);
}

/**
 * @title Create3Library
 * @notice Library providing convenient wrapper functions for CREATE3 deployments via CreateX factory
 * @dev This library simplifies CREATE3 deployments by handling salt generation and factory interactions
 */
library Create3Library {
    /// @notice Address of the CreateX factory contract used for CREATE3 deployments
    /// @dev This is the canonical CreateX factory address deployed on multiple chains
    address public constant CREATEX_FACTORY = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;

    /**
     * @notice Deploys a contract using CREATE3 with a deployer-specific salt
     * @dev Combines the deployer address with the provided salt to create a unique deployment salt
     * @param deployer The address of the deployer (used in salt generation)
     * @param salt An 11-byte salt value for deterministic address generation
     * @param code The contract bytecode to deploy
     * @return The address of the deployed contract
     */
    function deployCreate3(address deployer, bytes11 salt, bytes memory code) public returns (address) {
        return ICreateX(CREATEX_FACTORY).deployCreate3(getSaltForCreate3(salt, deployer), code);
    }

    /**
     * @notice Deploys a contract using CREATE3 and calls an initialization function
     * @dev Combines deployment and initialization in a single transaction
     * @param deployer The address of the deployer (used in salt generation)
     * @param salt An 11-byte salt value for deterministic address generation
     * @param code The contract bytecode to deploy
     * @param data The calldata for the initialization function call
     * @param values The ETH values to send during deployment and initialization
     * @return The address of the deployed and initialized contract
     */
    function deployCreate3AndInit(
        address deployer,
        bytes11 salt,
        bytes memory code,
        bytes memory data,
        ICreateX.Values memory values
    ) public returns (address) {
        return ICreateX(CREATEX_FACTORY).deployCreate3AndInit(getSaltForCreate3(salt, deployer), code, data, values);
    }

    /**
     * @notice Computes the deterministic address for a CREATE3 deployment
     * @dev Useful for predicting contract addresses before deployment
     * @param salt An 11-byte salt value for address computation
     * @param deployer The address of the deployer (used in salt generation)
     * @return The computed address where the contract would be deployed
     */
    function computeCreate3Address(bytes11 salt, address deployer) public view returns (address) {
        return ICreateX(CREATEX_FACTORY).computeCreate3Address(getSaltForCreate3(salt, deployer));
    }

    /**
     * @notice Generates a 32-byte salt for CREATE3 deployment by combining deployer address and salt
     * @dev The salt format is: [160-bit deployer address][8-bit zero padding][88-bit salt]
     * @param salt An 11-byte (88-bit) salt value
     * @param deployer The deployer's address (160-bit)
     * @return A 32-byte salt suitable for CREATE3 deployment
     */
    function getSaltForCreate3(bytes11 salt, address deployer) public pure returns (bytes32) {
        return bytes32(uint256(uint160(deployer)) << 96 | uint256(0x00) << 88 | uint256(uint88(salt)));
    }
}
