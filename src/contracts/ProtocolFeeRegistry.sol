// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {IProtocolFeeRegistry, MAX_PROTOCOL_FEE} from "../interfaces/IProtocolFeeRegistry.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ProtocolFeeRegistry is Ownable, IProtocolFeeRegistry {
    /* STATE VARIABLES */

    /// @inheritdoc IProtocolFeeRegistry
    uint256 public globalFee;
    /// @inheritdoc IProtocolFeeRegistry
    address public globalReceiver;
    /// @inheritdoc IProtocolFeeRegistry
    mapping(address vault => address receiver) public vaultReceiver;

    /// @dev Serialized vault-specific fee override data.
    mapping(address vault => uint256 data) internal _vaultFeeData;

    /* CONSTRUCTOR */

    constructor(address curOwner) Ownable(curOwner) {}

    /* VIEW FUNCTIONS */

    /// @inheritdoc IProtocolFeeRegistry
    function getFee(address vault) external view returns (uint256) {
        (bool isEnabled, uint256 fee) = _deserializeFeeData(_vaultFeeData[vault]);
        if (isEnabled) {
            return fee;
        }
        return globalFee;
    }

    /// @inheritdoc IProtocolFeeRegistry
    function getReceiver(address vault) external view returns (address receiver) {
        receiver = vaultReceiver[vault];
        if (receiver == address(0)) {
            receiver = globalReceiver;
        }
    }

    /// @inheritdoc IProtocolFeeRegistry
    function vaultFee(address vault) external view returns (uint256 fee) {
        (, fee) = _deserializeFeeData(_vaultFeeData[vault]);
    }

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc IProtocolFeeRegistry
    function setGlobalFee(uint256 newGlobalFee) external onlyOwner {
        if (newGlobalFee > MAX_PROTOCOL_FEE) {
            revert FeeTooHigh();
        }
        globalFee = newGlobalFee;
        emit SetGlobalFee(newGlobalFee);
    }

    /// @inheritdoc IProtocolFeeRegistry
    function setVaultFee(address vault, bool isEnabled, uint256 newVaultFee) external onlyOwner {
        if (newVaultFee > MAX_PROTOCOL_FEE) {
            revert FeeTooHigh();
        }
        _vaultFeeData[vault] = _serializeFeeData(isEnabled, newVaultFee);
        emit SetVaultFee(vault, newVaultFee);
    }

    /// @inheritdoc IProtocolFeeRegistry
    function setGlobalReceiver(address newGlobalReceiver) external onlyOwner {
        if (newGlobalReceiver == address(0)) {
            revert InvalidReceiver();
        }
        globalReceiver = newGlobalReceiver;
        emit SetGlobalReceiver(newGlobalReceiver);
    }

    /// @inheritdoc IProtocolFeeRegistry
    function setVaultReceiver(address vault, address newVaultReceiver) external onlyOwner {
        vaultReceiver[vault] = newVaultReceiver;
        emit SetVaultReceiver(vault, newVaultReceiver);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Serializes fee data (enable + fee).
    function _serializeFeeData(bool isEnabled, uint256 fee) internal pure returns (uint256) {
        return (fee << 1) | (isEnabled ? 1 : 0);
    }

    /// @dev Deserializes fee data (enable + fee).
    function _deserializeFeeData(uint256 data) internal pure returns (bool, uint256) {
        return ((data & 1) > 0, data >> 1);
    }
}
