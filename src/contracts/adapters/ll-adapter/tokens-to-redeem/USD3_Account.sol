// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";
import {ThreeJaneAccount} from "../ThreeJaneAccount.sol";
import {ThreeJaneOracle} from "../oracles/ThreeJaneOracle.sol";

contract USD3_Account is ThreeJaneAccount {
    uint256 internal constant MIN_PRICE = 0.5e18;
    uint256 internal constant MAX_PRICE = 2.5e18;
    address internal constant TOKEN_ADDRESS = 0x056B269Eb1f75477a8666ae8C7fE01b64dD55eCc;

    constructor(address factory, address cowSwapSettlement)
        ThreeJaneAccount(
            address(new ThreeJaneOracle(MIN_PRICE, MAX_PRICE, TOKEN_ADDRESS)), factory, TOKEN_ADDRESS, cowSwapSettlement
        )
    {}
}

contract USD3_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}
