// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {DeployLiquidLane2Script} from "script/deploy/adapters/DeployLiquidLane2.s.sol";

contract DeployLiquidLane2MainnetHarness is DeployLiquidLane2Script {
    function _startBroadcast() internal override {}

    function _stopBroadcast() internal override {}

    function _scriptOwner() internal view override returns (address) {
        return address(this);
    }
}

contract DeployLiquidLane2MainnetTest is Test {
    function testDeploysCompleteCurrentMainnetConfiguration() public {
        string memory rpcUrl = vm.envOr("ETH_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            vm.skip(true);
        }
        vm.createSelectFork(rpcUrl);

        DeployLiquidLane2Script.LiquidLane2DeploymentData memory data = (new DeployLiquidLane2MainnetHarness()).run();
        DeployLiquidLane2Script.AccountDeploymentData[8] memory deployments =
            [data.jaaa, data.jtrsy, data.hyb, data.deJAAA, data.deJTRSY, data.hybond, data.prime, data.mGlobal];

        for (uint256 i; i < deployments.length; ++i) {
            assertNotEq(deployments[i].oracle, address(0));
            assertNotEq(deployments[i].factory, address(0));
            assertNotEq(deployments[i].implementation, address(0));
        }
    }
}
