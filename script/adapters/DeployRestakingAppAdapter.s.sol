// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployAdapterBase} from "./base/DeployAdapterBase.sol";

import {IAppAdapter} from "../../src/interfaces/adapters/IAppAdapter.sol";
import {IRestakingAppAdapter} from "../../src/interfaces/adapters/IRestakingAppAdapter.sol";

// forge script script/adapters/DeployRestakingAppAdapter.s.sol:DeployRestakingAppAdapterScript --rpc-url=RPC --account=ACCOUNT --sender=SENDER --broadcast

contract DeployRestakingAppAdapterScript is DeployAdapterBase {
    // Configurations - UPDATE THESE BEFORE DEPLOYMENT.

    address public constant ADAPTER_FACTORY = 0xe1986078E2A2cE0f8609410B33Fca1C1CbCCbb4E;
    uint64 public constant VERSION = 1;
    address public constant OWNER = 0x0000000000000000000000000000000000000000;
    address public constant VAULT = 0x0000000000000000000000000000000000000000;
    address public constant ASSET = 0x0000000000000000000000000000000000000000;
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
                    IRestakingAppAdapter.RestakingInitParams({
                        asset: ASSET,
                        initParams: IAppAdapter.InitParams({
                            burner: BURNER,
                            duration: DURATION,
                            operator: OPERATOR,
                            subnetwork: SUBNETWORK,
                            converters: _singleConverter(CONVERTER)
                        })
                    })
                )
            })
        );
    }
}
