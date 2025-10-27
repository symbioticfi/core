// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVault} from "../../../src/interfaces/vault/IVault.sol";
import {INetworkRestakeDelegator} from "../../../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract SetNetworkLimitBaseScript is ScriptBase {
    function runBase(address vault, bytes32 subnetwork, uint256 networkLimit)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = IVault(vault).delegator();
        data = abi.encodeCall(INetworkRestakeDelegator.setNetworkLimit, (subnetwork, networkLimit));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Set network limit ",
                "\n    vault:",
                vm.toString(vault),
                "\n    subnetwork:",
                vm.toString(subnetwork),
                "\n    networkLimit:",
                vm.toString(networkLimit)
            )
        );
        Logs.logSimulationLink(target, data);

        return (data, target);
    }
}
