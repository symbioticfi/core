// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AppAdapter} from "../../../src/contracts/adapters/AppAdapter.sol";
import {DeployAdapterBase} from "./DeployAdapterBase.sol";

contract DeployAppAdapterBase is DeployAdapterBase {
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
            new AppAdapter(vaultFactory, data.adapterFactory, params.cowSwapSettlement, params.networkMiddlewareService)
        );
        _whitelistAndTransferOwnership(data, params.adapterFactoryOwner);
        _stopBroadcast();

        _validateAdapterDeployment(data, params.adapterFactoryOwner);
        _logDeployment("App", data);
    }

    function _validateParams(DeployParams memory params) internal pure {
        _validateAdapterFactoryOwner(params.adapterFactoryOwner);
        require(params.cowSwapSettlement != address(0), "invalid CoW settlement");
        require(params.networkMiddlewareService != address(0), "invalid network middleware service");
    }
}
