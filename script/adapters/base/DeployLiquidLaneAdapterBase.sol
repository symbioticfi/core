// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LiquidLaneAdapter} from "../../../src/contracts/adapters/LiquidLaneAdapter.sol";
import {DeployAdapterBase} from "./DeployAdapterBase.sol";

contract DeployLiquidLaneAdapterBase is DeployAdapterBase {
    struct DeployParams {
        address adapterFactoryOwner;
        address accountRegistry;
    }

    function runBase(DeployParams memory params) public virtual returns (DeploymentData memory data) {
        _validateParams(params);

        address vaultFactory = _coreVaultFactory();

        _startBroadcast();
        data.adapterFactory = _deployAdapterFactory();
        data.adapterImplementation =
            address(new LiquidLaneAdapter(vaultFactory, data.adapterFactory, params.accountRegistry));
        _whitelistAndTransferOwnership(data, params.adapterFactoryOwner);
        _stopBroadcast();

        _validateAdapterDeployment(data, params.adapterFactoryOwner);
        _logDeployment("LiquidLane", data);
    }

    function _validateParams(DeployParams memory params) internal pure {
        _validateAdapterFactoryOwner(params.adapterFactoryOwner);
        require(params.accountRegistry != address(0), "invalid account registry");
    }
}
