// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {PikuAccount} from "../PikuAccount.sol";
import {PikuOracle} from "../oracles/PikuOracle.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

contract aFXArbUSDTRY_Account is PikuAccount {
    address internal constant TOKEN_ADDRESS = 0x99351BaEd3d8aB544CCb08aF96A105910fdA71E7;
    uint48 internal constant TOKEN_COOLDOWN = 1 days;

    constructor(address factory)
        PikuAccount(address(new PikuOracle(TOKEN_ADDRESS)), factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, TOKEN_ADDRESS)
    {}
}

contract aFXArbUSDTRY_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}
