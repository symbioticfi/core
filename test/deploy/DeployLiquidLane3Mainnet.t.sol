// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {DeployLiquidLane3Script} from "../../script/deploy/adapters/DeployLiquidLane3.s.sol";
import {AdapterFactory} from "../../src/contracts/adapters/AdapterFactory.sol";
import {MigratablesFactory} from "../../src/contracts/common/MigratablesFactory.sol";
import {ICoWSwapConverter} from "../../src/interfaces/adapters/common/ICoWSwapConverter.sol";
import {IMerklClaimer} from "../../src/interfaces/adapters/common/IMerklClaimer.sol";
import {IAccount} from "../../src/interfaces/adapters/ll-adapter/IAccount.sol";
import {IParetoOracle} from "../../src/interfaces/adapters/ll-adapter/oracles/IParetoOracle.sol";
import {IParetoAccount} from "../../src/interfaces/adapters/ll-adapter/pareto/IParetoAccount.sol";
import {IMigratableEntity} from "../../src/interfaces/common/IMigratableEntity.sol";

contract DeployLiquidLane3MainnetHarness is DeployLiquidLane3Script {
    function _startBroadcast() internal override {}

    function _stopBroadcast() internal override {}

    function _scriptOwner() internal view override returns (address) {
        return address(this);
    }
}

contract DeployLiquidLane3MainnetTest is Test {
    function testDeploysCompleteCurrentMainnetConfiguration() public {
        string memory rpcUrl = vm.envOr("ETH_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            vm.skip(true);
        }
        vm.createSelectFork(rpcUrl);

        DeployLiquidLane3MainnetHarness harness = new DeployLiquidLane3MainnetHarness();
        DeployLiquidLane3Script.LiquidLane3DeploymentData memory data = harness.run();

        assertEq(Ownable(data.euler.adapterFactory).owner(), harness.FACTORIES_OWNER());
        assertEq(AdapterFactory(data.euler.adapterFactory).lastVersion(), 1);
        assertEq(AdapterFactory(data.euler.adapterFactory).implementation(1), data.euler.adapterImplementation);
        assertEq(IMigratableEntity(data.euler.adapterImplementation).FACTORY(), data.euler.adapterFactory);
        assertEq(IMerklClaimer(data.euler.adapterImplementation).MERKL_DISTRIBUTOR(), harness.MERKL_DISTRIBUTOR());
        assertEq(
            ICoWSwapConverter(data.euler.adapterImplementation).COW_SWAP_SETTLEMENT(), harness.COW_SWAP_SETTLEMENT()
        );

        assertEq(Ownable(data.aaFalconX.factory).owner(), harness.FACTORIES_OWNER());
        assertEq(MigratablesFactory(data.aaFalconX.factory).lastVersion(), 1);
        assertEq(MigratablesFactory(data.aaFalconX.factory).implementation(1), data.aaFalconX.implementation);
        assertEq(IMigratableEntity(data.aaFalconX.implementation).FACTORY(), data.aaFalconX.factory);
        assertEq(IAccount(data.aaFalconX.implementation).ORACLE(), data.aaFalconX.oracle);
        assertEq(IAccount(data.aaFalconX.implementation).TOKEN_TO_REDEEM(), harness.AA_FALCONX());
        assertEq(IParetoAccount(data.aaFalconX.implementation).WITHDRAWAL_QUEUE(), harness.PARETO_WITHDRAWAL_QUEUE());
        assertEq(ICoWSwapConverter(data.aaFalconX.implementation).COW_SWAP_SETTLEMENT(), harness.COW_SWAP_SETTLEMENT());
        assertEq(IParetoOracle(data.aaFalconX.oracle).IDLE_CDO(), harness.PARETO_CDO());
        assertEq(IParetoOracle(data.aaFalconX.oracle).TOKEN_TO_REDEEM(), harness.AA_FALCONX());
        assertGe(IParetoOracle(data.aaFalconX.oracle).getPrice(), harness.MIN_PRICE());
        assertLe(IParetoOracle(data.aaFalconX.oracle).getPrice(), harness.MAX_PRICE());

        assertGt(harness.FACTORIES_OWNER().code.length, 0);
        assertGt(harness.EULER_LEND_VAULT_FACTORY().code.length, 0);
        assertGt(harness.COW_SWAP_SETTLEMENT().code.length, 0);
        assertGt(harness.MERKL_DISTRIBUTOR().code.length, 0);
    }
}
