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

        new AaveV3Adapter(aavePool, vaultFactory, adapterFactory, curatorRegistry);
        new MorphoVaultV2Adapter(
            vaultFactory, adapterFactory, curatorRegistry, morphoVaultFactory, morphoAdapterRegistry
        );
    }
}
