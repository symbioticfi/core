// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {EtherFiAccount} from "../EtherFiAccount.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";
import {WeETHOracle} from "../oracles/WeETHOracle.sol";

contract weETH_Account is EtherFiAccount {
    address internal constant EETH_ADDRESS = 0x35fA164735182de50811E8e2E824cFb9B6118ac2;
    address internal constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant TOKEN_ADDRESS = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address internal constant LIQUIDITY_POOL_ADDRESS = 0x308861A430be4cce5502d0A12724771Fc6DaF216;
    address internal constant REDEMPTION_MANAGER_ADDRESS = 0xDadEf1fFBFeaAB4f68A9fD181395F68b4e4E7Ae0;
    address internal constant WITHDRAW_REQUEST_NFT_ADDRESS = 0x7d5706f6ef3F89B3951E23e557CDFBC3239D4E2c;

    constructor(address factory, address cowSwapSettlement)
        EtherFiAccount(
            EETH_ADDRESS,
            WETH_ADDRESS,
            address(new WeETHOracle(0.5e18, 2.5e18, TOKEN_ADDRESS)),
            factory,
            LIQUIDITY_POOL_ADDRESS,
            TOKEN_ADDRESS,
            REDEMPTION_MANAGER_ADDRESS,
            cowSwapSettlement,
            WITHDRAW_REQUEST_NFT_ADDRESS
        )
    {}
}

contract weETH_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}
