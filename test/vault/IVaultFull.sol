// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVault} from "../../src/interfaces/vault/IVault.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVaultFull is IVault, IAccessControl, IERC20 {
    function DEPOSITOR_WHITELIST_ROLE() external view returns (bytes32);
    function DEPOSIT_WHITELIST_SET_ROLE() external view returns (bytes32);
    function IS_DEPOSIT_LIMIT_SET_ROLE() external view returns (bytes32);
    function DEPOSIT_LIMIT_SET_ROLE() external view returns (bytes32);
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

    function owner() external view returns (address);
    function latestWithdrawalBucket() external view returns (uint256);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
    function name() external view returns (string memory);
}