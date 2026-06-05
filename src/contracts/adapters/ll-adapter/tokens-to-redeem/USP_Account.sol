// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {PikuFundingManagerAccount} from "../PikuFundingManagerAccount.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

contract USP_Account is PikuFundingManagerAccount {
    address internal constant TOKEN_ADDRESS = 0x098697bA3Fee4eA76294C5d6A466a4e3b3E95FE6;
    address internal constant FUNDING_MANAGER_ADDRESS = 0x7e0305B212dF3FB56366251C054c07748Bf9a797;

    constructor(address oracle, address factory, address cowSwapSettlement, address cowSwapVaultRelayer)
        PikuFundingManagerAccount(
            oracle, factory, TOKEN_ADDRESS, FUNDING_MANAGER_ADDRESS, cowSwapSettlement, cowSwapVaultRelayer
        )
    {}
}

contract USP_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}
