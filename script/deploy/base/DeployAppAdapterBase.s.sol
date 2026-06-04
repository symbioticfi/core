// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Script} from "forge-std/Script.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Logs} from "../../utils/Logs.sol";
import {SymbioticCoreConstants} from "../../../test/integration/SymbioticCoreConstants.sol";

import {AdapterFactory} from "../../../src/contracts/adapters/AdapterFactory.sol";
import {AppAdapter} from "../../../src/contracts/adapters/AppAdapter.sol";

contract DeployAppAdapterBaseScript is Script {
    struct DeployParams {
        address adapterFactoryOwner;
        address cowSwapSettlement;
        address cowSwapVaultRelayer;
        address networkMiddlewareService;
    }

    struct DeploymentData {
        address adapterFactory;
        address adapterImplementation;
    }

    function runBase(DeployParams memory params) public virtual returns (DeploymentData memory data) {
        _validateParams(params);

        address vaultFactory = _coreVaultFactory();

        _startBroadcast();
        (data.adapterFactory, data.adapterImplementation) = _deployAdapterFactory(params, vaultFactory);
        _stopBroadcast();

        assert(Ownable(data.adapterFactory).owner() == params.adapterFactoryOwner);
        assert(AppAdapter(data.adapterImplementation).FACTORY() == data.adapterFactory);
        assert(AdapterFactory(data.adapterFactory).implementation(1) == data.adapterImplementation);

        Logs.log(
            string.concat(
                "Deployed App adapter factory",
                "\n    adapterFactory:",
                vm.toString(data.adapterFactory),
                "\n    adapterImplementation:",
                vm.toString(data.adapterImplementation)
            )
        );
    }

    function _deployAdapterFactory(DeployParams memory params, address vaultFactory)
        internal
        returns (address adapterFactory, address adapterImplementation)
    {
        address broadcaster = _scriptOwner();

        adapterFactory = address(new AdapterFactory(broadcaster));
        adapterImplementation = address(
            new AppAdapter(
                vaultFactory,
                adapterFactory,
                params.cowSwapSettlement,
                params.cowSwapVaultRelayer,
                params.networkMiddlewareService
            )
        );
        AdapterFactory(adapterFactory).whitelist(adapterImplementation);

        if (params.adapterFactoryOwner != broadcaster) {
            Ownable(adapterFactory).transferOwnership(params.adapterFactoryOwner);
        }
    }

    function _validateParams(DeployParams memory params) internal pure {
        require(params.adapterFactoryOwner != address(0), "invalid adapter factory owner");
        require(params.cowSwapSettlement != address(0), "invalid CoW settlement");
        require(params.cowSwapVaultRelayer != address(0), "invalid CoW vault relayer");
        require(params.networkMiddlewareService != address(0), "invalid network middleware service");
    }

    function _scriptOwner() internal view virtual returns (address owner_) {
        (,, address origin) = vm.readCallers();
        return origin == address(0) ? msg.sender : origin;
    }

    function _coreVaultFactory() internal view virtual returns (address) {
        return address(SymbioticCoreConstants.core().vaultFactory);
    }

    function _startBroadcast() internal virtual {
        vm.startBroadcast();
    }

    function _stopBroadcast() internal virtual {
        vm.stopBroadcast();
    }
}
