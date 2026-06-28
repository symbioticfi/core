// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MorphoVaultV2Adapter} from "../../../src/contracts/adapters/MorphoVaultV2Adapter.sol";
import {DeployAdapterBase} from "./DeployAdapterBase.sol";

contract DeployMorphoVaultV2AdapterBase is DeployAdapterBase {
    struct DeployParams {
        address adapterFactoryOwner;
        address morphoVaultFactory;
        address morphoAdapterRegistry;
        address cowSwapSettlement;
        address merklDistributor;
    }

    function runBase(DeployParams memory params) public virtual returns (DeploymentData memory data) {
        _validateParams(params);

        address vaultFactory = _coreVaultFactory();

        _startBroadcast();
        data.adapterFactory = _deployAdapterFactory();
        data.adapterImplementation = address(
            new MorphoVaultV2Adapter(
                vaultFactory,
                data.adapterFactory,
                params.merklDistributor,
                params.cowSwapSettlement,
                params.morphoVaultFactory,
                params.morphoAdapterRegistry
            )
        );
        _whitelistAndTransferOwnership(data, params.adapterFactoryOwner);
        _stopBroadcast();

        _validateAdapterDeployment(data, params.adapterFactoryOwner);
        _logDeployment("MorphoVaultV2", data);
    }

    function _validateParams(DeployParams memory params) internal pure {
        _validateAdapterFactoryOwner(params.adapterFactoryOwner);
        require(params.morphoVaultFactory != address(0), "invalid Morpho vault factory");
        require(params.morphoAdapterRegistry != address(0), "invalid Morpho adapter registry");
        require(params.cowSwapSettlement != address(0), "invalid CoW settlement");
        require(params.merklDistributor != address(0), "invalid Merkl distributor");
    }
}
