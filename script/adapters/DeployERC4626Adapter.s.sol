// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployAdapterBase} from "./base/DeployAdapterBase.sol";

import {IERC4626Adapter} from "../../src/interfaces/adapters/IERC4626Adapter.sol";

// forge script script/adapters/DeployERC4626Adapter.s.sol:DeployERC4626AdapterScript --rpc-url=RPC --broadcast

contract DeployERC4626AdapterScript is DeployAdapterBase {
    // Configurations - UPDATE THESE BEFORE DEPLOYMENT.

    address public constant ADAPTER_FACTORY = 0x0000000000000000000000000000000000000000;
    uint64 public constant VERSION = 1;
    address public constant OWNER = 0x0000000000000000000000000000000000000000;
    address public constant VAULT = 0x0000000000000000000000000000000000000000;
    address public constant ERC4626_VAULT = 0x0000000000000000000000000000000000000000;
    address public constant CONVERTER = 0x0000000000000000000000000000000000000000;

    function run() public returns (DeploymentData memory data) {
        data = runBase(
            DeployParams({
                adapterFactory: ADAPTER_FACTORY,
                version: VERSION,
                owner: OWNER,
                vault: VAULT,
                initData: abi.encode(
                    IERC4626Adapter.InitParams({converters: _singleConverter(CONVERTER), erc4626Vault: ERC4626_VAULT})
                )
            })
        );
    }
}
