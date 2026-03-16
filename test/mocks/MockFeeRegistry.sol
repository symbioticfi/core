// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IFeeRegistry} from "../../src/interfaces/vault/IFeeRegistry.sol";

contract MockFeeRegistry is IFeeRegistry {
    mapping(address vault => uint256 fee) internal _instantWithdrawFee;

    function setInstantWithdrawFee(address vault, uint256 fee) external {
        _instantWithdrawFee[vault] = fee;
    }

    function getInstantWithdrawFee(address vault) external view returns (uint256 fee) {
        return _instantWithdrawFee[vault];
    }
}
