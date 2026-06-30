// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IThreeFVaultController} from "./IThreeFVaultController.sol";

/**
 * @title IThreeFRequest
 * @notice Minimal interface for 3F requests.
 */
interface IThreeFRequest is IThreeFVaultController {
    /**
     * @notice Returns the request asset.
     * @return asset Request asset.
     */
    function asset() external view returns (address asset);
}
