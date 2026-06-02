// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Script} from "forge-std/Script.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Logs} from "../../../utils/Logs.sol";

import {
    MockAaveATokenUpgradeable,
    MockAavePoolAddressesProviderUpgradeable,
    MockAavePoolDataProviderUpgradeable,
    MockAavePoolUpgradeable,
    MockHoodiTokenUpgradeable
} from "../../../../test/mocks/HoodiScenarioProtocolMocks.sol";

contract AaveV3MocksDeployBaseScript is Script {
    bytes32 internal constant ERC1967_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    struct DeploymentData {
        address collateral;
        address collateralImplementation;
        address collateralProxyAdmin;
        address aavePool;
        address aavePoolImplementation;
        address aavePoolProxyAdmin;
        address aaveProvider;
        address aaveProviderImplementation;
        address aaveProviderProxyAdmin;
        address aaveDataProvider;
        address aaveDataProviderImplementation;
        address aaveDataProviderProxyAdmin;
        address aToken;
        address aTokenImplementation;
        address aTokenProxyAdmin;
    }

    function runBase(address collateral) public virtual returns (DeploymentData memory data) {
        _startBroadcast();
        address proxyOwner = _scriptOwner();
        if (collateral == address(0)) {
            (data.collateralImplementation, data.collateralProxyAdmin, data.collateral) = _deployProxy(
                address(new MockHoodiTokenUpgradeable()),
                proxyOwner,
                abi.encodeCall(MockHoodiTokenUpgradeable.initialize, ("Hoodi Aave Collateral", proxyOwner))
            );
        } else {
            data.collateral = collateral;
        }

        (data.aTokenImplementation, data.aTokenProxyAdmin, data.aToken) = _deployProxy(
            address(new MockAaveATokenUpgradeable()),
            proxyOwner,
            abi.encodeCall(MockAaveATokenUpgradeable.initialize, (data.collateral))
        );
        (data.aaveProviderImplementation, data.aaveProviderProxyAdmin, data.aaveProvider) = _deployProxy(
            address(new MockAavePoolAddressesProviderUpgradeable()),
            proxyOwner,
            abi.encodeCall(MockAavePoolAddressesProviderUpgradeable.initialize, ())
        );
        (data.aaveDataProviderImplementation, data.aaveDataProviderProxyAdmin, data.aaveDataProvider) = _deployProxy(
            address(new MockAavePoolDataProviderUpgradeable()),
            proxyOwner,
            abi.encodeCall(MockAavePoolDataProviderUpgradeable.initialize, ())
        );
        (data.aavePoolImplementation, data.aavePoolProxyAdmin, data.aavePool) = _deployProxy(
            address(new MockAavePoolUpgradeable()),
            proxyOwner,
            abi.encodeCall(MockAavePoolUpgradeable.initialize, (data.aaveProvider))
        );
        MockAavePoolUpgradeable(data.aavePool).setReserveToken(data.collateral, data.aToken);
        MockAaveATokenUpgradeable(data.aToken).setPool(data.aavePool);
        MockAavePoolAddressesProviderUpgradeable(data.aaveProvider).setPool(data.aavePool);
        MockAavePoolAddressesProviderUpgradeable(data.aaveProvider).setPoolDataProvider(data.aaveDataProvider);
        MockAavePoolDataProviderUpgradeable(data.aaveDataProvider).setReserveToken(data.collateral, data.aToken);
        _stopBroadcast();

        assert(MockAavePoolUpgradeable(data.aavePool).getReserveAToken(data.collateral) == data.aToken);

        Logs.log("Deployed AaveV3 mocks");
        _logProxy("collateral", data.collateral, data.collateralImplementation, data.collateralProxyAdmin);
        _logProxy("aavePool", data.aavePool, data.aavePoolImplementation, data.aavePoolProxyAdmin);
        _logProxy("aaveProvider", data.aaveProvider, data.aaveProviderImplementation, data.aaveProviderProxyAdmin);
        _logProxy(
            "aaveDataProvider",
            data.aaveDataProvider,
            data.aaveDataProviderImplementation,
            data.aaveDataProviderProxyAdmin
        );
        _logProxy("aToken", data.aToken, data.aTokenImplementation, data.aTokenProxyAdmin);
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
