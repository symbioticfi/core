// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {EtherFiAccount} from "../EtherFiAccount.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

contract weETH_Account is EtherFiAccount {
    constructor(
        address eETH,
        address weth,
        address weETH,
        address oracle,
        address factory,
        address liquidityPool,
        address redemptionManager,
        address cowSwapSettlement,
        address withdrawRequestNft,
        address cowSwapVaultRelayer
    )
        EtherFiAccount(
            eETH,
            weth,
            oracle,
            factory,
            liquidityPool,
            weETH,
            redemptionManager,
            cowSwapSettlement,
            withdrawRequestNft,
            cowSwapVaultRelayer
        )
    {}
}

contract weETH_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}
