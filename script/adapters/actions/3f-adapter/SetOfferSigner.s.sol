// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetOfferSignerBase.s.sol";

contract SetOfferSignerScript is SetOfferSignerBaseScript {
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;
    address constant SIGNER = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(ADAPTER, SIGNER);
    }
}
