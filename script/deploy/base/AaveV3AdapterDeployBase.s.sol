// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";

import {UpgradeableBeacon} from "@solady/src/utils/UpgradeableBeacon.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Logs} from "../../utils/Logs.sol";
import {SymbioticCoreConstants} from "../../../test/integration/SymbioticCoreConstants.sol";

import {Adapter} from "../../../src/contracts/vault/adapters/Adapter.sol";
import {AaveV3Account, AaveV3Adapter} from "../../../src/contracts/vault/adapters/AaveV3Adapter.sol";

contract AaveV3AdapterDeployBaseScript is Script {
    bytes32 internal constant ERC1967_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    struct DeployParams {
        address adapterOwner;
        address aavePool;
        address curatorRegistry;
        address rewards;
    }

    struct DeploymentData {
        address accountImplementation;
        address beacon;
        address adapterImplementation;
        address proxyAdmin;
        address adapter;
    }

    function runBase(DeployParams memory params) public virtual returns (DeploymentData memory data) {
        _validateParams(params);

        address vaultFactory = address(SymbioticCoreConstants.core().vaultFactory);

        _startBroadcast();
        (data.accountImplementation, data.beacon, data.adapterImplementation, data.proxyAdmin, data.adapter) =
            _deployAdapter(params, vaultFactory);
        _stopBroadcast();

        assert(AaveV3Adapter(data.adapter).owner() == params.adapterOwner);

        Logs.log(
            string.concat(
                "Deployed AaveV3 adapter",
                "\n    accountImplementation:",
                vm.toString(data.accountImplementation),
                "\n    beacon:",
                vm.toString(data.beacon),
                "\n    adapterImplementation:",
                vm.toString(data.adapterImplementation),
                "\n    proxyAdmin:",
                vm.toString(data.proxyAdmin),
                "\n    adapter:",
                vm.toString(data.adapter)
            )
        );
    }

    function _deployAdapter(DeployParams memory params, address vaultFactory)
        internal
        returns (
            address accountImplementation,
            address beacon,
            address adapterImplementation,
            address proxyAdmin,
            address adapter
        )
    {
        address broadcaster = _scriptOwner();
        uint256 nonce = vm.getNonce(broadcaster);
        address predictedAdapter = vm.computeCreateAddress(broadcaster, nonce + 3);

        accountImplementation = address(new AaveV3Account(params.aavePool, predictedAdapter));
        beacon = address(new UpgradeableBeacon(address(0), accountImplementation));

        adapterImplementation =
            address(new AaveV3Adapter(params.aavePool, params.curatorRegistry, params.rewards, vaultFactory, beacon));
        adapter = address(
            new TransparentUpgradeableProxy(
                adapterImplementation, params.adapterOwner, abi.encodeCall(Adapter.initialize, ())
            )
        );
        require(adapter == predictedAdapter, "unexpected Aave adapter address");

        proxyAdmin = _proxyAdmin(adapter);
        AaveV3Adapter deployedAdapter = AaveV3Adapter(adapter);
        if (deployedAdapter.owner() != params.adapterOwner) {
            deployedAdapter.transferOwnership(params.adapterOwner);
        }
    }

    function _validateParams(DeployParams memory params) internal pure {
        require(params.adapterOwner != address(0), "invalid adapter owner");
        require(params.aavePool != address(0), "invalid Aave pool");
        require(params.curatorRegistry != address(0), "invalid curator registry");
        require(params.rewards != address(0), "invalid rewards");
    }

    function _scriptOwner() internal view returns (address owner_) {
        (,, address origin) = vm.readCallers();
        return origin == address(0) ? msg.sender : origin;
    }

    function _proxyAdmin(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967_ADMIN_SLOT))));
    }

    function _startBroadcast() internal virtual {
        vm.startBroadcast();
    }

    function _stopBroadcast() internal virtual {
        vm.stopBroadcast();
    }
}
