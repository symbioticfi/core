// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {CentrifugeAccount} from "../CentrifugeAccount.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

contract deJAAA_Account is CentrifugeAccount {
    address internal constant TOKEN_ADDRESS = 0xAAA0008C8CF3A7Dca931adaF04336A5D808C82Cc;
    uint48 internal constant TOKEN_COOLDOWN = 1 days;

    constructor(address oracle, address factory, address cowSwapSettlement, address cowSwapVaultRelayer)
        CentrifugeAccount(oracle, factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, cowSwapSettlement, cowSwapVaultRelayer)
    {}
}

contract deJAAA_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}
