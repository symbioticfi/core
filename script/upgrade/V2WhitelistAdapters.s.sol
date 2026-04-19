// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./base/V2WhitelistAdaptersBase.s.sol";
import {Logs} from "../utils/Logs.sol";

contract V2WhitelistAdaptersScript is V2WhitelistAdaptersBaseScript {
    address constant ADAPTER_REGISTRY = address(0);
    address constant AAVE_ADAPTER = address(0);
    address constant MORPHO_ADAPTER = address(0);

    function run() public {
        (bytes memory whitelistAaveData, address whitelistAaveTarget) = whitelistAdapter(ADAPTER_REGISTRY, AAVE_ADAPTER);
        (bytes memory whitelistMorphoData, address whitelistMorphoTarget) =
            whitelistAdapter(ADAPTER_REGISTRY, MORPHO_ADAPTER);

        Logs.log(
            string.concat(
                "V2WhitelistAdapters data:",
                "\n    whitelistAaveData:",
                vm.toString(whitelistAaveData),
                "\n    whitelistAaveTarget:",
                vm.toString(whitelistAaveTarget),
                "\n    whitelistMorphoData:",
                vm.toString(whitelistMorphoData),
                "\n    whitelistMorphoTarget:",
                vm.toString(whitelistMorphoTarget)
            )
        );
    }
}
