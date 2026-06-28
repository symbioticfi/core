// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AaveV3Adapter} from "../../../src/contracts/adapters/AaveV3Adapter.sol";
import {DeployAdapterBase} from "./DeployAdapterBase.sol";

contract DeployAaveV3AdapterBase is DeployAdapterBase {
    struct DeployParams {
        address adapterFactoryOwner;
        address aavePool;
        address cowSwapSettlement;
        address merklDistributor;
    }

    function runBase(DeployParams memory params) public virtual returns (DeploymentData memory data) {
        _validateParams(params);

        address vaultFactory = _coreVaultFactory();

        _startBroadcast();
        data.adapterFactory = _deployAdapterFactory();
        data.adapterImplementation = address(
            new AaveV3Adapter(
                params.aavePool, vaultFactory, data.adapterFactory, params.merklDistributor, params.cowSwapSettlement
            )
        );
        _whitelistAndTransferOwnership(data, params.adapterFactoryOwner);
        _stopBroadcast();

        _validateAdapterDeployment(data, params.adapterFactoryOwner);
        _logDeployment("AaveV3", data);
    }

    function _validateParams(DeployParams memory params) internal pure {
        _validateAdapterFactoryOwner(params.adapterFactoryOwner);
        require(params.aavePool != address(0), "invalid Aave pool");
        require(params.cowSwapSettlement != address(0), "invalid CoW settlement");
        require(params.merklDistributor != address(0), "invalid Merkl distributor");
    }
}
