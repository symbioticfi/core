// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Oracle} from "./Oracle.sol";

import {IOracle} from "../../../../interfaces/adapters/ll-adapter/IOracle.sol";
import {IParetoCDO} from "../../../../interfaces/adapters/ll-adapter/pareto/IParetoCDO.sol";
import {IParetoOracle} from "../../../../interfaces/adapters/ll-adapter/oracles/IParetoOracle.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title ParetoOracle
/// @notice Oracle returning a Pareto tranche virtual price in `1e18` precision.
contract ParetoOracle is Oracle, IParetoOracle {
    using Math for uint256;

    /* IMMUTABLES */

    /// @inheritdoc IParetoOracle
    address public immutable TOKEN_TO_REDEEM;

    /// @inheritdoc IParetoOracle
    address public immutable IDLE_CDO;

    /// @dev Pareto underlying-token unit.
    uint256 internal immutable UNDERLYING_UNIT;

    /* CONSTRUCTOR */

    /// @notice Creates the bounded Pareto virtual-price oracle.
    constructor(uint256 minPrice, uint256 maxPrice, address tokenToRedeem, address idleCdo) Oracle(minPrice, maxPrice) {
        if (IParetoCDO(idleCdo).AATranche() != tokenToRedeem) {
            revert InvalidTranche();
        }
        TOKEN_TO_REDEEM = tokenToRedeem;
        IDLE_CDO = idleCdo;
        UNDERLYING_UNIT = 10 ** IERC20Metadata(IParetoCDO(idleCdo).token()).decimals();
    }

    /* VIEW FUNCTIONS */

    function getPrice() public view override(Oracle, IOracle) returns (uint256) {
        return IParetoCDO(IDLE_CDO).defaulted() ? 0 : super.getPrice();
    }

    /* INTERNAL VIEW FUNCTIONS */

    /// @inheritdoc Oracle
    function _getPrice() internal view override returns (uint256) {
        return IParetoCDO(IDLE_CDO).virtualPrice(TOKEN_TO_REDEEM) * 1e18 / UNDERLYING_UNIT;
    }
}
