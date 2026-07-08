// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployAdapterBase} from "./base/DeployAdapterBase.sol";

import {IAppAdapter} from "../../src/interfaces/adapters/IAppAdapter.sol";

// forge script script/adapters/DeployAppAdapter.s.sol:DeployAppAdapterScript --rpc-url=RPC --account=ACCOUNT --sender=SENDER --broadcast

contract DeployAppAdapterScript is DeployAdapterBase {
    // Configurations - UPDATE THESE BEFORE DEPLOYMENT.

    address public constant ADAPTER_FACTORY = 0x161954842B7EA47CBd050cAb4875DAa4D6599476;
    uint64 public constant VERSION = 1;
    address public constant OWNER = 0x0000000000000000000000000000000000000000;
    address public constant VAULT = 0x0000000000000000000000000000000000000000;
    address public constant BURNER = 0x0000000000000000000000000000000000000000;
    uint48 public constant DURATION = 0;
    address public constant OPERATOR = 0x0000000000000000000000000000000000000000;
    bytes32 public constant SUBNETWORK = bytes32(0);
    address public constant CONVERTER = 0x0000000000000000000000000000000000000000;

    function run() public returns (DeploymentData memory data) {
        data = runBase(
            DeployParams({
                adapterFactory: ADAPTER_FACTORY,
                version: VERSION,
                owner: OWNER,
                vault: VAULT,
                initData: abi.encode(
                    IAppAdapter.InitParams({
                        burner: BURNER,
                        duration: DURATION,
                        operator: OPERATOR,
                        subnetwork: SUBNETWORK,
                        converters: _singleConverter(CONVERTER)
                    })
                )
            })
        );
    }
}
