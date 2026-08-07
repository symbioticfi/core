// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {LidoAccount} from "../LidoAccount.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";
import {WstETHOracle} from "../oracles/WstETHOracle.sol";

contract wstETH_Account is LidoAccount {
    address internal constant STETH_ADDRESS = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address internal constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant TOKEN_ADDRESS = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant WITHDRAWAL_QUEUE_ADDRESS = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;

    constructor(address factory, address cowSwapSettlement)
        LidoAccount(
            STETH_ADDRESS,
            WETH_ADDRESS,
            address(new WstETHOracle(0.5e18, 2.5e18, TOKEN_ADDRESS)),
            TOKEN_ADDRESS,
            factory,
            WITHDRAWAL_QUEUE_ADDRESS,
            cowSwapSettlement
        )
    {}
}

contract wstETH_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}
