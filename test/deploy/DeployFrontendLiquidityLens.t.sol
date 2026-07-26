// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {DeployFrontendLiquidityLensScript} from "../../script/deploy/utils/DeployFrontendLiquidityLens.s.sol";
import {FrontendLiquidityLens} from "../../src/contracts/adapters/utils/FrontendLiquidityLens.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployFrontendLiquidityLensScriptHarness is DeployFrontendLiquidityLensScript {
    address internal immutable PROXY_OWNER;

    constructor(address proxyOwner) {
        PROXY_OWNER = proxyOwner;
    }

    function _proxyOwner() internal view override returns (address) {
        return PROXY_OWNER;
    }

    function _startBroadcast() internal override {}

    function _stopBroadcast() internal override {}
}

/// @dev Runs the deploy script on a mainnet fork, including its own validation, then exercises the
///      resulting proxy end to end: answers, upgrade authority, and upgrade continuity.
contract DeployFrontendLiquidityLensTest is Test {
    address internal constant PROXY_OWNER = address(0x0FFEE);

    bool internal forked;

    function setUp() public {
        string memory rpcUrl = vm.envOr("ETH_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            return;
        }
        uint256 forkBlock = vm.envOr("MAINNET_FORK_BLOCK", uint256(0));
        if (forkBlock == 0) {
            vm.createSelectFork(rpcUrl);
        } else {
            vm.createSelectFork(rpcUrl, forkBlock);
        }
        forked = true;
    }

    function test_DeployValidatesAndUpgrades() public {
        if (!forked) {
            vm.skip(true, "ETH_RPC_URL is required for the lens deploy test");
        }

        // `run` performs the script's own wiring and live-behaviour validation internally.
        DeployFrontendLiquidityLensScriptHarness harness = new DeployFrontendLiquidityLensScriptHarness(PROXY_OWNER);
        (address lens, address implementation, address proxyAdmin) = harness.run();

        assertTrue(lens != implementation, "lens must be the proxy, not the implementation");
        assertEq(Ownable(proxyAdmin).owner(), PROXY_OWNER, "upgrade authority must be the configured owner");

        // The proxy keeps its address and answers across an upgrade driven by the configured owner.
        uint256 snapshot = vm.snapshotState();
        uint256 answerBefore = FrontendLiquidityLens(lens).getMaxAssets(harness.MAINNET_THREEF_ADAPTER());
        vm.revertToState(snapshot);

        address implementationV2 = address(new FrontendLiquidityLens());
        vm.prank(PROXY_OWNER);
        ProxyAdmin(proxyAdmin).upgradeAndCall(ITransparentUpgradeableProxy(lens), implementationV2, "");

        snapshot = vm.snapshotState();
        uint256 answerAfter = FrontendLiquidityLens(lens).getMaxAssets(harness.MAINNET_THREEF_ADAPTER());
        vm.revertToState(snapshot);

        assertEq(answerAfter, answerBefore, "same address must answer identically after the upgrade");
    }
}
