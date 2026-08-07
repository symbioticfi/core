// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";
import {SThreeJaneAccount} from "../SThreeJaneAccount.sol";
import {SThreeJaneOracle} from "../oracles/SThreeJaneOracle.sol";

contract sUSD3_Account is SThreeJaneAccount {
    uint256 internal constant MIN_PRICE = 0.5e18;
    uint256 internal constant MAX_PRICE = 2.5e18;
    address internal constant TOKEN_ADDRESS = 0xf689555121e529Ff0463e191F9Bd9d1E496164a7;

    constructor(address factory, address cowSwapSettlement)
        SThreeJaneAccount(
            address(new SThreeJaneOracle(MIN_PRICE, MAX_PRICE, TOKEN_ADDRESS)),
            factory,
            TOKEN_ADDRESS,
            cowSwapSettlement
        )
    {}
}

contract sUSD3_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}
