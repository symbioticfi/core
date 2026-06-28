// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {RestakingAppAdapter} from "../../../src/contracts/adapters/RestakingAppAdapter.sol";
import {DeployAdapterBase} from "./DeployAdapterBase.sol";

contract DeployRestakingAppAdapterBase is DeployAdapterBase {
    struct DeployParams {
        address adapterFactoryOwner;
        address cowSwapSettlement;
        address networkMiddlewareService;
    }

    function runBase(DeployParams memory params) public virtual returns (DeploymentData memory data) {
        _validateParams(params);

        address vaultFactory = _coreVaultFactory();

        _startBroadcast();
        data.adapterFactory = _deployAdapterFactory();
        data.adapterImplementation = address(
            new RestakingAppAdapter(
                vaultFactory, data.adapterFactory, params.cowSwapSettlement, params.networkMiddlewareService
            )
        );
        _whitelistAndTransferOwnership(data, params.adapterFactoryOwner);
        _stopBroadcast();

        _validateAdapterDeployment(data, params.adapterFactoryOwner);
        _logDeployment("RestakingApp", data);
    }

    function _validateParams(DeployParams memory params) internal pure {
        _validateAdapterFactoryOwner(params.adapterFactoryOwner);
        require(params.cowSwapSettlement != address(0), "invalid CoW settlement");
        require(params.networkMiddlewareService != address(0), "invalid network middleware service");
    }
}
