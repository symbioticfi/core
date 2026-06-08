// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";
import {TheoAccount} from "../TheoAccount.sol";

contract sthUSD_Account is TheoAccount {
    address internal constant TOKEN_ADDRESS = 0xA808Bc9775cb41c52C7842f8b50427fE7A770326;

    constructor(address oracle, address factory, address cowSwapSettlement, address cowSwapVaultRelayer)
        TheoAccount(oracle, factory, TOKEN_ADDRESS, cowSwapSettlement, cowSwapVaultRelayer)
    {}
}

contract sthUSD_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}
