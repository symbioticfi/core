// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployAdapterBase} from "./base/DeployAdapterBase.sol";

import {IAaveV3Adapter} from "../../src/interfaces/adapters/IAaveV3Adapter.sol";

// forge script script/adapters/DeployAaveV3Adapter.s.sol:DeployAaveV3AdapterScript --rpc-url=RPC --account=ACCOUNT --sender=SENDER --broadcast

contract DeployAaveV3AdapterScript is DeployAdapterBase {
    // Configurations - UPDATE THESE BEFORE DEPLOYMENT.

    address public constant ADAPTER_FACTORY = 0x58F61759D858EafD8F58e4926e251701F6495dbF;
    uint64 public constant VERSION = 1;
    address public constant OWNER = 0x0000000000000000000000000000000000000000;
    address public constant VAULT = 0x0000000000000000000000000000000000000000;
    address public constant CONVERTER = 0x0000000000000000000000000000000000000000;

    function run() public returns (DeploymentData memory data) {
        data = runBase(
            DeployParams({
                adapterFactory: ADAPTER_FACTORY,
                version: VERSION,
                owner: OWNER,
                vault: VAULT,
                initData: abi.encode(IAaveV3Adapter.InitParams({converters: _singleConverter(CONVERTER)}))
            })
        );
    }
}
