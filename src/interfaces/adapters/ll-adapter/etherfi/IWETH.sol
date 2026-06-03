// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IWETH
 * @notice Minimal WETH interface used by liquidity lane accounts.
 */
interface IWETH {
    /**
     * @notice Wraps received ETH into WETH.
     */
    function deposit() external payable;
}
