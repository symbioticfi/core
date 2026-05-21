// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IAdapterBase} from "../../src/interfaces/vault/IAdapterBase.sol";
import {IBurner} from "../../src/interfaces/slasher/IBurner.sol";

contract MockReentrantAdapter is IAdapterBase {
    IERC20 public immutable collateral;
    address public immutable vault;

    uint256 public allocated;
    uint256 public reentryCalls;
    bool public lastCallSuccess;

    address public reentryTarget;
    bytes internal _reentryData;

    constructor(address vault_, address collateral_) {
        vault = vault_;
        collateral = IERC20(collateral_);
    }

    function armReentry(address target, bytes calldata data) external {
        reentryTarget = target;
        _reentryData = data;
    }

    function clearReentry() external {
        reentryTarget = address(0);
        delete _reentryData;
    }

    function allocatable(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function deallocatable(address vault_) external view returns (uint256) {
        if (vault_ != vault) {
            return 0;
        }

        return collateral.balanceOf(address(this));
    }

    function allocate(uint256 amount) external {
        allocated += amount;
        _attemptReentry();
    }

    function deallocate(uint256 amount) external returns (uint256 deallocated) {
        _attemptReentry();

        uint256 balance = collateral.balanceOf(address(this));
        deallocated = amount <= balance ? amount : balance;
        if (deallocated > 0) {
            allocated = allocated > deallocated ? allocated - deallocated : 0;
            collateral.approve(vault, deallocated);
        }
    }

    function _attemptReentry() internal {
        address target = reentryTarget;
        if (target == address(0)) {
            return;
        }

        bytes memory data = _reentryData;
        reentryTarget = address(0);
        delete _reentryData;

        ++reentryCalls;
        bytes memory returnData;
        (lastCallSuccess, returnData) = target.call(data);
    }
}

contract MockReentrantBurner is IBurner {
    bytes32 public lastSubnetwork;
    address public lastOperator;
    uint256 public lastAmount;
    uint48 public lastCaptureTimestamp;
    uint256 public calls;
    uint256 public reentryCalls;
    bool public lastCallSuccess;

    address public reentryTarget;
    bytes internal _reentryData;

    function armReentry(address target, bytes calldata data) external {
        reentryTarget = target;
        _reentryData = data;
    }

    function clearReentry() external {
        reentryTarget = address(0);
        delete _reentryData;
    }

    function onSlash(bytes32 subnetwork, address operator, uint256 amount, uint48 captureTimestamp) external {
        lastSubnetwork = subnetwork;
        lastOperator = operator;
        lastAmount = amount;
        lastCaptureTimestamp = captureTimestamp;
        ++calls;

        _attemptReentry();
    }

    function _attemptReentry() internal {
        address target = reentryTarget;
        if (target == address(0)) {
            return;
        }

        bytes memory data = _reentryData;
        reentryTarget = address(0);
        delete _reentryData;

        ++reentryCalls;
        bytes memory returnData;
        (lastCallSuccess, returnData) = target.call(data);
    }
}
