// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";
import {ERC4626Account} from "../ERC4626Account.sol";

contract USD3_Account is ERC4626Account {
    address internal constant TOKEN_ADDRESS = 0x056B269Eb1f75477a8666ae8C7fE01b64dD55eCc;

    constructor(address factory, address cowSwapSettlement) ERC4626Account(factory, TOKEN_ADDRESS, cowSwapSettlement) {}
}

contract USD3_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}
