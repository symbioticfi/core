// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {ERC4626Oracle} from "../oracles/ERC4626Oracle.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";
import {TheoAccount} from "../TheoAccount.sol";

contract sthUSD_Account is TheoAccount {
    uint256 internal constant MIN_PRICE = 0.5e18;
    uint256 internal constant MAX_PRICE = 2.5e18;
    address internal constant TOKEN_ADDRESS = 0xA808Bc9775cb41c52C7842f8b50427fE7A770326;

    constructor(address factory, address cowSwapSettlement)
        TheoAccount(
            address(new ERC4626Oracle(MIN_PRICE, MAX_PRICE, TOKEN_ADDRESS)), factory, TOKEN_ADDRESS, cowSwapSettlement
        )
    {}
}

contract sthUSD_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}
