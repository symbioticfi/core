// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IFeeRegistry} from "../../src/interfaces/vault/IFeeRegistry.sol";

contract MockFeeRegistry is IFeeRegistry {
    mapping(address vault => uint256 fee) internal _managementFee;
    mapping(address vault => address recipient) internal _managementFeeRecipient;
    mapping(address vault => uint256 fee) internal _performanceFee;
    mapping(address vault => address recipient) internal _performanceFeeRecipient;

    function setManagementFee(address vault, uint256 fee) external {
        _managementFee[vault] = fee;
    }

    function setManagementFeeRecipient(address vault, address recipient) external {
        _managementFeeRecipient[vault] = recipient;
    }

    function setPerformanceFee(address vault, uint256 fee) external {
        _performanceFee[vault] = fee;
    }

    function setPerformanceFeeRecipient(address vault, address recipient) external {
        _performanceFeeRecipient[vault] = recipient;
    }

    function getManagementFee(address vault) external view returns (uint256 fee) {
        return _managementFee[vault];
    }

    function getManagementFeeRecipient(address vault) external view returns (address recipient) {
        return _managementFeeRecipient[vault];
    }

    function getPerformanceFee(address vault) external view returns (uint256 fee) {
        return _performanceFee[vault];
    }

    function getPerformanceFeeRecipient(address vault) external view returns (address recipient) {
        return _performanceFeeRecipient[vault];
    }
}
