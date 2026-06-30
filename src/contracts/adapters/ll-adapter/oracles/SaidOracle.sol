// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Oracle} from "./Oracle.sol";

import {ISaidOracle} from "../../../../interfaces/adapters/ll-adapter/oracles/ISaidOracle.sol";
import {ISaid} from "../../../../interfaces/adapters/ll-adapter/gaib/ISaid.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title SaidOracle
/// @notice Oracle returning the GAIB sAID unstaking NAV in `1e18` precision.
contract SaidOracle is Oracle, ISaidOracle {
    using Math for uint256;

    /* IMMUTABLES */

    /// @inheritdoc ISaidOracle
    address public immutable VAULT;

    /// @dev Vault asset unit.
    uint256 internal immutable _assetUnit;
    /// @dev Vault share unit.
    uint256 internal immutable _shareUnit;

    /* CONSTRUCTOR */

    /// @notice Creates the GAIB sAID oracle.
    constructor(uint256 minPrice, uint256 maxPrice, address vault) Oracle(minPrice, maxPrice) {
        VAULT = vault;
        _shareUnit = 10 ** IERC20Metadata(vault).decimals();
        _assetUnit = 10 ** IERC20Metadata(IERC4626(vault).asset()).decimals();
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc Oracle
    function _getPrice() internal view override returns (uint256) {
        return ISaid(VAULT).convertToAssetsWithLoss(_shareUnit).mulDiv(1e18, _assetUnit);
    }
}
