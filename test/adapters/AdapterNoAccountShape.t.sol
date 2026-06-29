// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {AaveV3Adapter} from "../../src/contracts/adapters/AaveV3Adapter.sol";
import {ERC4626Adapter} from "../../src/contracts/adapters/ERC4626Adapter.sol";
import {MorphoVaultV2Adapter} from "../../src/contracts/adapters/MorphoVaultV2Adapter.sol";
import {ThreeFAdapter} from "../../src/contracts/adapters/ThreeFAdapter.sol";
import {ICoWSwapSettlement} from "../../src/interfaces/adapters/common/ICoWSwapConverter.sol";

contract AdapterNoAccountShapeTest is Test {
    function test_ConstructorsDoNotRequireAccountBeacon() public {
        address adapterFactory = makeAddr("adapterFactory");
        address aavePool = makeAddr("aavePool");
        address vaultFactory = makeAddr("vaultFactory");
        address rewards = makeAddr("rewards");
        address settlement = makeAddr("settlement");
        address relayer = makeAddr("relayer");
        address requestWhitelist = makeAddr("requestWhitelist");
        address morphoVaultFactory = makeAddr("morphoVaultFactory");
        address morphoAdapterRegistry = makeAddr("morphoAdapterRegistry");

        vm.mockCall(settlement, abi.encodeCall(ICoWSwapSettlement.vaultRelayer, ()), abi.encode(relayer));

        new AaveV3Adapter(aavePool, vaultFactory, adapterFactory, rewards, settlement);
        new ERC4626Adapter(vaultFactory, adapterFactory, rewards, settlement);
        new MorphoVaultV2Adapter(
            vaultFactory, adapterFactory, rewards, settlement, morphoVaultFactory, morphoAdapterRegistry
        );
        new ThreeFAdapter(requestWhitelist, adapterFactory, vaultFactory);
    }
}
