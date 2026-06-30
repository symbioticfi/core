// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {IProtocolFeeRegistry} from "../interfaces/IProtocolFeeRegistry.sol";
import {MAX_MANAGEMENT_FEE, MAX_PERFORMANCE_FEE} from "../interfaces/vault/IVaultV2.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ProtocolFeeRegistry is Ownable, IProtocolFeeRegistry {
    /* STATE VARIABLES */

    /// @inheritdoc IProtocolFeeRegistry
    address public globalReceiver;
    /// @inheritdoc IProtocolFeeRegistry
    uint96 public globalManagementFee;
    /// @inheritdoc IProtocolFeeRegistry
    uint96 public globalPerformanceFee;
    /// @dev Vault-specific fee override data.
    mapping(address vault => Fee) public vaultFee;

    /* CONSTRUCTOR */

    constructor(address newOwner) Ownable(newOwner) {}

    /* VIEW FUNCTIONS */

    /// @inheritdoc IProtocolFeeRegistry
    function getFee(address vault) public view returns (address, uint96, uint96) {
        Fee storage fee = vaultFee[vault];
        if (fee.isEnabled) {
            return (fee.receiver, fee.managementFee, fee.performanceFee);
        }
        return (globalReceiver, globalManagementFee, globalPerformanceFee);
    }

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc IProtocolFeeRegistry
    function setGlobalFee(uint96 newGlobalManagementFee, uint96 newGlobalPerformanceFee) public onlyOwner {
        if (newGlobalManagementFee > MAX_MANAGEMENT_FEE || newGlobalPerformanceFee > MAX_PERFORMANCE_FEE) {
            revert FeeTooHigh();
        }
        if ((newGlobalManagementFee > 0 || newGlobalPerformanceFee > 0) && globalReceiver == address(0)) {
            revert InvalidReceiver();
        }
        globalManagementFee = newGlobalManagementFee;
        globalPerformanceFee = newGlobalPerformanceFee;
        emit SetGlobalFee(newGlobalManagementFee, newGlobalPerformanceFee);
    }

    /// @inheritdoc IProtocolFeeRegistry
    function setGlobalReceiver(address newGlobalReceiver) public onlyOwner {
        if (newGlobalReceiver == address(0)) {
            revert InvalidReceiver();
        }
        globalReceiver = newGlobalReceiver;
        emit SetGlobalReceiver(newGlobalReceiver);
    }

    /// @inheritdoc IProtocolFeeRegistry
    function setVaultFee(
        address vault,
        bool isEnabled,
        address newVaultReceiver,
        uint96 newVaultManagementFee,
        uint96 newVaultPerformanceFee
    ) public onlyOwner {
        if (newVaultManagementFee > MAX_MANAGEMENT_FEE || newVaultPerformanceFee > MAX_PERFORMANCE_FEE) {
            revert FeeTooHigh();
        }
        if (isEnabled && (newVaultManagementFee > 0 || newVaultPerformanceFee > 0) && newVaultReceiver == address(0)) {
            revert InvalidReceiver();
        }
        vaultFee[vault] = Fee({
            isEnabled: isEnabled,
            receiver: newVaultReceiver,
            managementFee: newVaultManagementFee,
            performanceFee: newVaultPerformanceFee
        });
        emit SetVaultFee(vault, isEnabled, newVaultReceiver, newVaultManagementFee, newVaultPerformanceFee);
    }
}
