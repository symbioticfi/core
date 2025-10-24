// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICreateX} from "./interfaces/ICreateX.sol";

/**
 * @title CreateXWrapper
 * @notice Contract providing convenient wrapper functions for deployments via CreateX factory
 * @dev This contract simplifies deployments by handling salt generation and factory interactions
 */
contract CreateXWrapper {
    /// @notice Address of the CreateX factory contract used for CREATE3 deployments
    /// @dev This is the canonical CreateX factory address deployed on multiple chains
    address public constant CREATEX_FACTORY = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;

    /**
     * @notice Deploys a contract using CREATE
     * @param initCode The contract bytecode to deploy
     * @return The address of the deployed contract
     */
    function deployCreate(
        bytes memory initCode
    ) public returns (address) {
        return ICreateX(CREATEX_FACTORY).deployCreate(initCode);
    }

    /**
     * @notice Deploys a contract using CREATE and calls an initialization function
     * @param initCode The contract bytecode to deploy
     * @param data The calldata for the initialization function call
     * @return The address of the deployed and initialized contract
     */
    function deployCreateAndInit(bytes memory initCode, bytes memory data) public returns (address) {
        return ICreateX(CREATEX_FACTORY).deployCreateAndInit(initCode, data, ICreateX.Values(0, 0));
    }

    /**
     * @notice Deploys a contract using CREATE2
     * @param initCode The contract bytecode to deploy
     * @return The address of the deployed contract
     */
    function deployCreate2(
        bytes memory initCode
    ) public returns (address) {
        return ICreateX(CREATEX_FACTORY).deployCreate2(initCode);
    }

    /**
     * @notice Deploys a contract using CREATE2 with a salt
     * @param salt An 11-byte salt value for deterministic address generation
     * @param initCode The contract bytecode to deploy
     * @return The address of the deployed contract
     */
    function deployCreate2WithSalt(bytes32 salt, bytes memory initCode) public returns (address) {
        return ICreateX(CREATEX_FACTORY).deployCreate2(salt, initCode);
    }

    /**
     * @notice Deploys a contract using CREATE2 and calls an initialization function
     * @param salt An 32-byte salt value for deterministic address generation
     * @param initCode The contract bytecode to deploy
     * @param data The calldata for the initialization function call
     * @return The address of the deployed and initialized contract
     */
    function deployCreate2AndInit(bytes32 salt, bytes memory initCode, bytes memory data) public returns (address) {
        return ICreateX(CREATEX_FACTORY).deployCreate2AndInit(salt, initCode, data, ICreateX.Values(0, 0));
    }

    /**
     * @notice Deploys a contract using CREATE3
     * @param salt An 11-byte salt value for deterministic address generation
     * @param code The contract bytecode to deploy
     * @return The address of the deployed contract
     */
    function deployCreate3(bytes32 salt, bytes memory code) public returns (address) {
        return ICreateX(CREATEX_FACTORY).deployCreate3(salt, code);
    }

    /**
     * @notice Deploys a contract using CREATE3 with a deployer-specific salt
     * @dev Combines the deployer address with the provided salt to create a unique deployment salt
     * @param deployer The address of the deployer (used in salt generation)
     * @param salt An 11-byte salt value for deterministic address generation
     * @param code The contract bytecode to deploy
     * @return The address of the deployed contract
     */
    function deployCreate3WithGuardedSalt(address deployer, bytes11 salt, bytes memory code) public returns (address) {
        return ICreateX(CREATEX_FACTORY).deployCreate3(getSaltForCreate3(salt, deployer), code);
    }

    /**
     * @notice Deploys a contract using CREATE3 and calls an initialization function
     * @dev Combines deployment and initialization in a single transaction
     * @param salt An 32-byte salt value for deterministic address generation
     * @param code The contract bytecode to deploy
     * @param data The calldata for the initialization function call
     * @return The address of the deployed and initialized contract
     */
    function deployCreate3AndInit(bytes32 salt, bytes memory code, bytes memory data) public returns (address) {
        return ICreateX(CREATEX_FACTORY).deployCreate3AndInit(salt, code, data, ICreateX.Values(0, 0));
    }

    /**
     * @notice Deploys a contract using CREATE3 and calls an initialization function
     * @dev Combines deployment and initialization in a single transaction
     * @param deployer The address of the deployer (used in salt generation)
     * @param salt An 11-byte salt value for deterministic address generation
     * @param code The contract bytecode to deploy
     * @param data The calldata for the initialization function call
     * @return The address of the deployed and initialized contract
     */
    function deployCreate3AndInitWithGuardedSalt(
        address deployer,
        bytes11 salt,
        bytes memory code,
        bytes memory data
    ) public returns (address) {
        return ICreateX(CREATEX_FACTORY).deployCreate3AndInit(
            getSaltForCreate3(salt, deployer), code, data, ICreateX.Values(0, 0)
        );
    }

    /**
     * @notice Computes the deterministic address for a CREATE3 deployment
     * @dev Useful for predicting contract addresses before deployment
     * @param salt An 32-byte salt value
     * @return The computed address where the contract would be deployed
     */
    function computeCreate3Address(
        bytes32 salt
    ) public view returns (address) {
        return ICreateX(CREATEX_FACTORY).computeCreate3Address(salt);
    }

    /**
     * @notice Computes the deterministic address for a CREATE3 deployment
     * @dev Useful for predicting contract addresses before deployment
     * @param salt An 11-byte salt value
     * @param deployer The address of the deployer (used in salt generation)
     * @return The computed address where the contract would be deployed
     */
    function computeCreate3AddressWithGuardedSalt(bytes11 salt, address deployer) public view returns (address) {
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

    /**
     * @notice Generates a guarded salt for CREATE3 deployment by combining deployer address and salt
     * @dev The salt format is: [160-bit deployer address][8-bit zero padding][88-bit salt]
     * @param deployer The deployer's address (160-bit)
     * @param salt An 32-byte salt value
     * @return A 32-byte salt suitable for CREATE3 deployment
     */
    function getGuardedSalt(address deployer, bytes32 salt) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(bytes32(uint256(uint160(deployer))), salt));
    }
}
