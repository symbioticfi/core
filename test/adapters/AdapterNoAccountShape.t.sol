// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {AaveV3Adapter} from "../../src/contracts/adapters/AaveV3Adapter.sol";
import {MorphoVaultV2Adapter} from "../../src/contracts/adapters/MorphoVaultV2Adapter.sol";

contract AdapterNoAccountShapeTest is Test {
    function test_ConstructorsDoNotRequireAccountBeacon() public {
        address adapterFactory = makeAddr("adapterFactory");
        address aavePool = makeAddr("aavePool");
        address curatorRegistry = makeAddr("curatorRegistry");
        address rewards = makeAddr("rewards");
        address vaultFactory = makeAddr("vaultFactory");
        address morphoVaultFactory = makeAddr("morphoVaultFactory");
        address morphoAdapterRegistry = makeAddr("morphoAdapterRegistry");
        address cowSwapSettlement = makeAddr("cowSwapSettlement");
        address cowSwapVaultRelayer = makeAddr("cowSwapVaultRelayer");
        address protocol = makeAddr("protocol");

        new AaveV3Adapter(
            protocol,
            aavePool,
            vaultFactory,
            adapterFactory,
            curatorRegistry,
            rewards,
            cowSwapSettlement,
            1 hours,
            cowSwapVaultRelayer
        );
        new MorphoVaultV2Adapter(
            protocol,
            vaultFactory,
            adapterFactory,
            curatorRegistry,
            rewards,
            cowSwapSettlement,
            1 hours,
            morphoVaultFactory,
            cowSwapVaultRelayer,
            morphoAdapterRegistry
        );
    }
}
