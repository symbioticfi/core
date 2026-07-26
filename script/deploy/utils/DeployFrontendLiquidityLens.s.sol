// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {FrontendLiquidityLens} from "../../../src/contracts/adapters/utils/FrontendLiquidityLens.sol";

import {IThreeFAdapter} from "../../../src/interfaces/adapters/IThreeFAdapter.sol";

import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/// @title DeployFrontendLiquidityLensScript
/// @notice Deploys the frontend liquidity lens behind a transparent proxy and validates it live.
/// @dev Requires `LENS_PROXY_OWNER` (the address that will own upgrades via the auto-created
///      `ProxyAdmin`). The validation runs during simulation, so a failing check aborts the broadcast.
contract DeployFrontendLiquidityLensScript is Script {
    /// @dev Reference 3F adapter used for the live post-deploy check (skipped when not deployed).
    address public constant MAINNET_THREEF_ADAPTER = 0x037356ac97fF97BE419cc608279e4389Fa7f2cfC;

    function run() public returns (address lens, address implementation, address proxyAdmin) {
        address proxyOwner = _proxyOwner();

        _startBroadcast();
        implementation = address(new FrontendLiquidityLens());
        lens = address(new TransparentUpgradeableProxy(implementation, proxyOwner, ""));
        _stopBroadcast();

        proxyAdmin = address(uint160(uint256(vm.load(lens, ERC1967Utils.ADMIN_SLOT))));
        _validate(lens, implementation, proxyAdmin, proxyOwner);

        console2.log("FrontendLiquidityLens (proxy, use this):", lens);
        console2.log("Implementation:", implementation);
        console2.log("ProxyAdmin:", proxyAdmin);
        console2.log("ProxyAdmin owner:", proxyOwner);
    }

    /// @dev Wiring checks plus a live behaviour check against the reference 3F adapter.
    function _validate(address lens, address implementation, address proxyAdmin, address proxyOwner) internal {
        require(implementation.code.length > 0, "implementation not deployed");
        require(
            address(uint160(uint256(vm.load(lens, ERC1967Utils.IMPLEMENTATION_SLOT)))) == implementation,
            "proxy implementation mismatch"
        );
        require(Ownable(proxyAdmin).owner() == proxyOwner, "ProxyAdmin owner mismatch");

        address threeFAdapter = vm.envOr("LENS_CHECK_ADAPTER", MAINNET_THREEF_ADAPTER);
        if (threeFAdapter.code.length == 0) {
            console2.log("Live check skipped: no 3F adapter deployed at", threeFAdapter);
            return;
        }
        uint256 lensAssets = FrontendLiquidityLens(lens).getMaxAssets(threeFAdapter);
        uint256 legacyAssets = IThreeFAdapter(threeFAdapter).getMaxAssets();
        require(lensAssets >= legacyAssets, "lens reports less than the adapter's own getter");
        console2.log("Live check: lens getMaxAssets(3F):", lensAssets);
        console2.log("Live check: adapter getMaxAssets():", legacyAssets);
    }

    function _proxyOwner() internal view virtual returns (address) {
        return vm.envAddress("LENS_PROXY_OWNER");
    }

    function _startBroadcast() internal virtual {
        vm.startBroadcast();
    }

    function _stopBroadcast() internal virtual {
        vm.stopBroadcast();
    }
}
