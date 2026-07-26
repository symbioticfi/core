// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {CentrifugeAccount} from "../CentrifugeAccount.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

contract HYB_Account is CentrifugeAccount {
    address internal constant TOKEN_ADDRESS = 0x4827C7ecce4f07ADfe44A97165f06A199e7d2505;
    uint48 internal constant TOKEN_COOLDOWN = 0;

    constructor(
        address oracle,
        address factory,
        address redemptionToken,
        address asyncRedeemVault,
        address cowSwapSettlement
    )
        CentrifugeAccount(
            oracle, factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, redemptionToken, asyncRedeemVault, cowSwapSettlement
        )
    {}
}

contract HYB_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}
