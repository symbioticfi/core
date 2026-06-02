// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Script} from "forge-std/Script.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Logs} from "../../../utils/Logs.sol";

import {
    MockHoodiTokenUpgradeable,
    MockMorphoAdapterRegistryUpgradeable,
    MockMorphoVaultFactoryUpgradeable,
    MockMorphoVaultHarnessUpgradeable
} from "../../../../test/mocks/HoodiScenarioProtocolMocks.sol";

contract MorphoVaultV2MocksDeployBaseScript is Script {
    bytes32 internal constant ERC1967_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    struct DeployParams {
        address adapterRegistryOwner;
        address collateral;
    }

    struct DeploymentData {
        address collateral;
        address collateralImplementation;
        address collateralProxyAdmin;
        address morphoVaultFactory;
        address morphoVaultFactoryImplementation;
        address morphoVaultFactoryProxyAdmin;
        address morphoAdapterRegistry;
        address morphoAdapterRegistryImplementation;
        address morphoAdapterRegistryProxyAdmin;
        address morphoVault;
        address morphoVaultImplementation;
        address morphoVaultProxyAdmin;
    }

    function runBase(DeployParams memory params) public virtual returns (DeploymentData memory data) {
        require(params.adapterRegistryOwner != address(0), "invalid adapter registry owner");

        _startBroadcast();
        if (params.collateral == address(0)) {
            (data.collateralImplementation, data.collateralProxyAdmin, data.collateral) = _deployProxy(
                address(new MockHoodiTokenUpgradeable()),
                params.adapterRegistryOwner,
                abi.encodeCall(
                    MockHoodiTokenUpgradeable.initialize, ("Hoodi Morpho Collateral", params.adapterRegistryOwner)
                )
            );
        } else {
            data.collateral = params.collateral;
        }

        (data.morphoAdapterRegistryImplementation, data.morphoAdapterRegistryProxyAdmin, data.morphoAdapterRegistry) =
            _deployProxy(
                address(new MockMorphoAdapterRegistryUpgradeable()),
                params.adapterRegistryOwner,
                abi.encodeCall(MockMorphoAdapterRegistryUpgradeable.initialize, (params.adapterRegistryOwner))
            );
        (data.morphoVaultFactoryImplementation, data.morphoVaultFactoryProxyAdmin, data.morphoVaultFactory) =
            _deployProxy(
                address(new MockMorphoVaultFactoryUpgradeable()),
                params.adapterRegistryOwner,
                abi.encodeCall(
                    MockMorphoVaultFactoryUpgradeable.initialize,
                    (data.morphoAdapterRegistry, params.adapterRegistryOwner)
                )
            );
        (data.morphoVaultImplementation, data.morphoVault) =
            MockMorphoVaultFactoryUpgradeable(data.morphoVaultFactory).createVault(data.collateral);
        data.morphoVaultProxyAdmin = _proxyAdmin(data.morphoVault);
        _stopBroadcast();

        assert(MockMorphoAdapterRegistryUpgradeable(data.morphoAdapterRegistry).owner() == params.adapterRegistryOwner);
        assert(MockMorphoVaultFactoryUpgradeable(data.morphoVaultFactory).isVaultV2(data.morphoVault));

        Logs.log("Deployed MorphoVaultV2 mocks");
        _logProxy("collateral", data.collateral, data.collateralImplementation, data.collateralProxyAdmin);
        _logProxy(
            "morphoVaultFactory",
            data.morphoVaultFactory,
            data.morphoVaultFactoryImplementation,
            data.morphoVaultFactoryProxyAdmin
        );
        _logProxy(
            "morphoAdapterRegistry",
            data.morphoAdapterRegistry,
            data.morphoAdapterRegistryImplementation,
            data.morphoAdapterRegistryProxyAdmin
        );
        _logProxy("morphoVault", data.morphoVault, data.morphoVaultImplementation, data.morphoVaultProxyAdmin);
    }

    function _deployProxy(address implementation, address proxyOwner, bytes memory initData)
        internal
        returns (address implementation_, address proxyAdmin, address proxy)
    {
        implementation_ = implementation;
        proxy = address(new TransparentUpgradeableProxy(implementation, proxyOwner, initData));
        proxyAdmin = _proxyAdmin(proxy);
    }

    function _logProxy(string memory label, address proxy, address implementation, address proxyAdmin) internal {
        Logs.log(
            string.concat(
                "    ",
                label,
                ":",
                vm.toString(proxy),
                "\n        implementation:",
                vm.toString(implementation),
                "\n        proxyAdmin:",
                vm.toString(proxyAdmin)
            )
        );
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
