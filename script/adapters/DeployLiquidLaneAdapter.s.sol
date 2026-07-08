// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployAdapterBase} from "./base/DeployAdapterBase.sol";

import {ILiquidLaneAdapter} from "../../src/interfaces/adapters/ILiquidLaneAdapter.sol";

// forge script script/adapters/DeployLiquidLaneAdapter.s.sol:DeployLiquidLaneAdapterScript --rpc-url=RPC --broadcast

contract DeployLiquidLaneAdapterScript is DeployAdapterBase {
    // Configurations - UPDATE THESE BEFORE DEPLOYMENT.

    address public constant ADAPTER_FACTORY = 0x9b5dbB434269e39e41b1E331C2AcE09e05A899B5;
    uint64 public constant VERSION = 1;
    address public constant OWNER = 0x0000000000000000000000000000000000000000;
    address public constant VAULT = 0x0000000000000000000000000000000000000000;
    address public constant PAUSER = 0x0000000000000000000000000000000000000000;
    address public constant UNPAUSER = 0x0000000000000000000000000000000000000000;

    function run() public returns (DeploymentData memory data) {
        data = runBase(
            DeployParams({
                adapterFactory: ADAPTER_FACTORY,
                version: VERSION,
                owner: OWNER,
                vault: VAULT,
                initData: abi.encode(ILiquidLaneAdapter.InitParams({pauser: PAUSER, unpauser: UNPAUSER}))
            })
        );
    }
}
