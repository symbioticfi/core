// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {IProtocolFee, MAX_PROTOCOL_FEE} from "../../interfaces/vault/IProtocolFee.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ProtocolFee is Ownable, IProtocolFee {
    /* STATE VARIABLES */

    /// @inheritdoc IProtocolFee
    uint256 public globalFee;
    /// @inheritdoc IProtocolFee
    mapping(address vault => uint256 fee) public vaultFee;
    /// @inheritdoc IProtocolFee
    address public globalReceiver;
    /// @inheritdoc IProtocolFee
    mapping(address vault => address receiver) public vaultReceiver;

    /* CONSTRUCTOR */

    constructor(address curOwner, address curGlobalReceiver) Ownable(curOwner) {
        globalReceiver = curGlobalReceiver;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IProtocolFee
    function getFee(address vault) external view returns (uint256 fee) {
        fee = vaultFee[vault];
        if (fee == 0) {
            fee = globalFee;
        }
    }

    /// @inheritdoc IProtocolFee
    function getReceiver(address vault) external view returns (address receiver) {
        receiver = vaultReceiver[vault];
        if (receiver == address(0)) {
            receiver = globalReceiver;
        }
    }

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc IProtocolFee
    function setGlobalFee(uint256 newGlobalFee) external onlyOwner {
        if (newGlobalFee > MAX_PROTOCOL_FEE) {
            revert FeeTooHigh();
        }
        globalFee = newGlobalFee;
        emit SetGlobalFee(newGlobalFee);
    }

    /// @inheritdoc IProtocolFee
    function setVaultFee(address vault, uint256 newVaultFee) external onlyOwner {
        if (newVaultFee > MAX_PROTOCOL_FEE) {
            revert FeeTooHigh();
        }
        vaultFee[vault] = newVaultFee;
        emit SetVaultFee(vault, newVaultFee);
    }

    /// @inheritdoc IProtocolFee
    function setGlobalReceiver(address newGlobalReceiver) external onlyOwner {
        if (newGlobalReceiver == address(0)) {
            revert InvalidReceiver();
        }
        globalReceiver = newGlobalReceiver;
        emit SetGlobalReceiver(newGlobalReceiver);
    }

    /// @inheritdoc IProtocolFee
    function setVaultReceiver(address vault, address newVaultReceiver) external onlyOwner {
        vaultReceiver[vault] = newVaultReceiver;
        emit SetVaultReceiver(vault, newVaultReceiver);
    }
}
