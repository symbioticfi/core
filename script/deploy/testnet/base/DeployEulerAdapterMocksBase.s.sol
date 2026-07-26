// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {Logs} from "../../../utils/Logs.sol";

import {
    MockEulerLendVaultFactoryUpgradeable,
    MockHoodiTokenUpgradeable
} from "../../../../test/mocks/HoodiScenarioProtocolMocks.sol";

contract DeployEulerAdapterMocksBaseScript is Script {
    bytes32 internal constant ERC1967_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    struct DeploymentData {
        address collateral;
        address collateralImplementation;
        address collateralProxyAdmin;
        address eulerLendVaultFactory;
        address eulerLendVaultFactoryImplementation;
        address eulerLendVaultFactoryProxyAdmin;
        address eulerLendVault;
        address eulerLendVaultImplementation;
        address eulerLendVaultProxyAdmin;
    }

    function runBase(address collateral) public virtual returns (DeploymentData memory data) {
        _startBroadcast();
        address proxyOwner = _scriptOwner();
        if (collateral == address(0)) {
            (data.collateralImplementation, data.collateralProxyAdmin, data.collateral) = _deployProxy(
                address(new MockHoodiTokenUpgradeable()),
                proxyOwner,
                abi.encodeCall(MockHoodiTokenUpgradeable.initialize, ("Hoodi Euler Collateral", proxyOwner))
            );
        } else {
            data.collateral = collateral;
        }

        (data.eulerLendVaultFactoryImplementation, data.eulerLendVaultFactoryProxyAdmin, data.eulerLendVaultFactory) =
            _deployProxy(
                address(new MockEulerLendVaultFactoryUpgradeable()),
                proxyOwner,
                abi.encodeCall(MockEulerLendVaultFactoryUpgradeable.initialize, (proxyOwner))
            );
        (data.eulerLendVaultImplementation, data.eulerLendVault) =
            MockEulerLendVaultFactoryUpgradeable(data.eulerLendVaultFactory).createVault(data.collateral);
        data.eulerLendVaultProxyAdmin = _proxyAdmin(data.eulerLendVault);
        _stopBroadcast();

        assert(MockEulerLendVaultFactoryUpgradeable(data.eulerLendVaultFactory).isProxy(data.eulerLendVault));
        assert(IERC4626(data.eulerLendVault).asset() == data.collateral);

        Logs.log("Deployed Euler mocks");
        _logProxy("collateral", data.collateral, data.collateralImplementation, data.collateralProxyAdmin);
        _logProxy(
            "eulerLendVaultFactory",
            data.eulerLendVaultFactory,
            data.eulerLendVaultFactoryImplementation,
            data.eulerLendVaultFactoryProxyAdmin
        );
        _logProxy(
            "eulerLendVault", data.eulerLendVault, data.eulerLendVaultImplementation, data.eulerLendVaultProxyAdmin
        );
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
