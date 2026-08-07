// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Oracle} from "./Oracle.sol";

import {IERC4626Oracle} from "../../../../interfaces/adapters/ll-adapter/oracles/IERC4626Oracle.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title ERC4626Oracle
/// @notice Oracle returning an ERC-4626 share conversion in `1e18` precision.
contract ERC4626Oracle is Oracle, IERC4626Oracle {
    using Math for uint256;

    /* IMMUTABLES */

    /// @inheritdoc IERC4626Oracle
    address public immutable VAULT;

    /// @dev Vault share unit.
    uint256 internal immutable _shareUnit;
    /// @dev Vault asset unit.
    uint256 internal immutable _assetUnit;

    /* CONSTRUCTOR */

    /// @notice Creates the bounded ERC-4626 conversion oracle.
    constructor(uint256 minPrice, uint256 maxPrice, address vault) Oracle(minPrice, maxPrice) {
        VAULT = vault;
        _shareUnit = 10 ** IERC20Metadata(vault).decimals();
        _assetUnit = 10 ** IERC20Metadata(IERC4626(vault).asset()).decimals();
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc Oracle
    function _getPrice() internal view override returns (uint256) {
        return IERC4626(VAULT).convertToAssets(_shareUnit).mulDiv(1e18, _assetUnit);
    }
}
