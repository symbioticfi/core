// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOracle} from "../IOracle.sol";

/**
 * @title IWstETHOracle
 * @notice Interface for the native wstETH-to-stETH rate oracle.
 */
interface IWstETHOracle is IOracle {
    /**
     * @notice Returns the wstETH token used as the rate source.
     * @return wstETH The wstETH token address.
     */
    function WSTETH() external view returns (address wstETH);
}
