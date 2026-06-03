// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {IAsyncRedeemVault} from "../../../../interfaces/adapters/ll-adapter/IAsyncRedeemVault.sol";
import {IOracle} from "../../../../interfaces/adapters/ll-adapter/IOracle.sol";
import {IPikuOracle} from "../../../../interfaces/adapters/ll-adapter/oracles/IPikuOracle.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title PikuOracle
/// @notice Oracle returning a Piku Accountable vault share price in `1e18` precision.
contract PikuOracle is IPikuOracle {
    using Math for uint256;

    /* IMMUTABLES */

    /// @inheritdoc IPikuOracle
    address public immutable VAULT;

    /// @dev Vault asset unit.
    uint256 internal immutable _assetUnit;
    /// @dev Vault share unit.
    uint256 internal immutable _shareUnit;

    /* CONSTRUCTOR */

    /// @notice Creates the Piku Accountable vault oracle.
    constructor(address vault) {
        VAULT = vault;
        _shareUnit = 10 ** IERC20Metadata(vault).decimals();
        _assetUnit = 10 ** IERC20Metadata(IERC4626(vault).asset()).decimals();
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IOracle
    function getPrice() public view returns (uint256) {
        return IAsyncRedeemVault(VAULT).convertToAssets(_shareUnit).mulDiv(1e18, _assetUnit);
    }
}
