// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ThreeFAdapter} from "../../../src/contracts/adapters/ThreeFAdapter.sol";
import {DeployAdapterBase} from "./DeployAdapterBase.sol";

contract DeployThreeFAdapterBase is DeployAdapterBase {
    struct DeployParams {
        address adapterFactoryOwner;
        address requestWhitelist;
        uint256 maxLoans;
    }

    function runBase(DeployParams memory params) public virtual returns (DeploymentData memory data) {
        _validateParams(params);

        address vaultFactory = _coreVaultFactory();

        _startBroadcast();
        data.adapterFactory = _deployAdapterFactory();
        data.adapterImplementation =
            address(new ThreeFAdapter(params.requestWhitelist, data.adapterFactory, vaultFactory, params.maxLoans));
        _whitelistAndTransferOwnership(data, params.adapterFactoryOwner);
        _stopBroadcast();

        _validateAdapterDeployment(data, params.adapterFactoryOwner);
        _logDeployment("ThreeF", data);
    }

    function _validateParams(DeployParams memory params) internal pure {
        _validateAdapterFactoryOwner(params.adapterFactoryOwner);
        require(params.requestWhitelist != address(0), "invalid request whitelist");
        require(params.maxLoans != 0, "invalid max loans");
    }
}
