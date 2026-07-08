// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployAdapterBase} from "./base/DeployAdapterBase.sol";

import {IEulerAdapter} from "../../src/interfaces/adapters/IEulerAdapter.sol";

// forge script script/adapters/DeployEulerAdapter.s.sol:DeployEulerAdapterScript --rpc-url=RPC --broadcast

contract DeployEulerAdapterScript is DeployAdapterBase {
    // Configurations - UPDATE THESE BEFORE DEPLOYMENT.

    address public constant ADAPTER_FACTORY = 0x0000000000000000000000000000000000000000;
    uint64 public constant VERSION = 1;
    address public constant OWNER = 0x0000000000000000000000000000000000000000;
    address public constant VAULT = 0x0000000000000000000000000000000000000000;
    address public constant LEND_VAULT = 0x0000000000000000000000000000000000000000;
    address public constant CONVERTER = 0x0000000000000000000000000000000000000000;

    function run() public returns (DeploymentData memory data) {
        data = runBase(
            DeployParams({
                adapterFactory: ADAPTER_FACTORY,
                version: VERSION,
                owner: OWNER,
                vault: VAULT,
                initData: abi.encode(
                    IEulerAdapter.InitParams({lendVault: LEND_VAULT, converters: _singleConverter(CONVERTER)})
                )
            })
        );
    }
}
