// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {DeployAppAdapterBaseScript} from "./base/DeployAppAdapterBase.s.sol";

// forge script script/deploy/DeployAppAdapter.s.sol:DeployAppAdapterScript --rpc-url RPC/hoodi --broadcast --verify --etherscan-api-key 5NEH7KHHDWPQSEXNXJT3YSVBSS67MXRFXE

contract DeployAppAdapterScript is DeployAppAdapterBaseScript {
    // Address that will own the adapter factory after deployment.
    address public constant ADAPTER_FACTORY_OWNER = 0x0000000000000000000000000000000000000000;
    // CoW Protocol settlement used by the converter.
    address public constant COW_SWAP_SETTLEMENT = 0x0000000000000000000000000000000000000000;
    // CoW Protocol vault relayer approved by the converter.
    address public constant COW_SWAP_VAULT_RELAYER = 0x0000000000000000000000000000000000000000;
    // Network middleware service used to authorize app slashes.
    address public constant NETWORK_MIDDLEWARE_SERVICE = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(
            DeployParams({
                adapterFactoryOwner: ADAPTER_FACTORY_OWNER,
                cowSwapSettlement: COW_SWAP_SETTLEMENT,
                cowSwapVaultRelayer: COW_SWAP_VAULT_RELAYER,
                networkMiddlewareService: NETWORK_MIDDLEWARE_SERVICE
            })
        );
    }
}
