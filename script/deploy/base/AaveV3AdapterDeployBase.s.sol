// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Logs} from "../../utils/Logs.sol";
import {SymbioticCoreConstants} from "../../../test/integration/SymbioticCoreConstants.sol";

import {AdapterFactory} from "../../../src/contracts/adapters/AdapterFactory.sol";
import {AaveV3Adapter} from "../../../src/contracts/adapters/AaveV3Adapter.sol";

contract AaveV3AdapterDeployBaseScript is Script {
    struct DeployParams {
        address adapterFactoryOwner;
        address aavePool;
        address cowSwapSettlement;
        address cowSwapVaultRelayer;
        address rewards;
    }

    struct DeploymentData {
        address adapterFactory;
        address adapterImplementation;
    }

    function runBase(DeployParams memory params) public virtual returns (DeploymentData memory data) {
        _validateParams(params);

        address vaultFactory = address(SymbioticCoreConstants.core().vaultFactory);

        _startBroadcast();
        (data.adapterFactory, data.adapterImplementation) = _deployAdapterFactory(params, vaultFactory);
        _stopBroadcast();

        assert(Ownable(data.adapterFactory).owner() == params.adapterFactoryOwner);
        assert(AaveV3Adapter(data.adapterImplementation).FACTORY() == data.adapterFactory);

        Logs.log(
            string.concat(
                "Deployed AaveV3 adapter factory",
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
            new AaveV3Adapter(
                params.aavePool,
                vaultFactory,
                adapterFactory,
                params.rewards,
                params.cowSwapSettlement,
                params.cowSwapVaultRelayer
            )
        );
        AdapterFactory(adapterFactory).whitelist(adapterImplementation);

        if (params.adapterFactoryOwner != broadcaster) {
            Ownable(adapterFactory).transferOwnership(params.adapterFactoryOwner);
        }
    }

    function _validateParams(DeployParams memory params) internal pure {
        require(params.adapterFactoryOwner != address(0), "invalid adapter factory owner");
        require(params.aavePool != address(0), "invalid Aave pool");
        require(params.cowSwapSettlement != address(0), "invalid CoW settlement");
        require(params.cowSwapVaultRelayer != address(0), "invalid CoW vault relayer");
        require(params.rewards != address(0), "invalid rewards");
    }

    function _scriptOwner() internal view returns (address owner_) {
        (,, address origin) = vm.readCallers();
        return origin == address(0) ? msg.sender : origin;
    }

    function _startBroadcast() internal virtual {
        vm.startBroadcast();
    }

    function _stopBroadcast() internal virtual {
        vm.stopBroadcast();
    }
}
