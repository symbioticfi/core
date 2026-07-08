// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployAdapterBase} from "./base/DeployAdapterBase.sol";

import {IMorphoVaultV2Adapter} from "../../src/interfaces/adapters/IMorphoVaultV2Adapter.sol";

// forge script script/adapters/DeployMorphoVaultV2Adapter.s.sol:DeployMorphoVaultV2AdapterScript --rpc-url=RPC --account=ACCOUNT --sender=SENDER --broadcast

contract DeployMorphoVaultV2AdapterScript is DeployAdapterBase {
    // Configurations - UPDATE THESE BEFORE DEPLOYMENT.

    address public constant ADAPTER_FACTORY = 0x70bc72b19a554436459a2C6a9E88892AeD18685b;
    uint64 public constant VERSION = 1;
    address public constant OWNER = 0x0000000000000000000000000000000000000000;
    address public constant VAULT = 0x0000000000000000000000000000000000000000;
    address public constant MORPHO_VAULT = 0x0000000000000000000000000000000000000000;
    address public constant CONVERTER = 0x0000000000000000000000000000000000000000;

    function run() public returns (DeploymentData memory data) {
        data = runBase(
            DeployParams({
                adapterFactory: ADAPTER_FACTORY,
                version: VERSION,
                owner: OWNER,
                vault: VAULT,
                initData: abi.encode(
                    IMorphoVaultV2Adapter.InitParams({
                        morphoVault: MORPHO_VAULT, converters: _singleConverter(CONVERTER)
                    })
                )
            })
        );
    }
}
