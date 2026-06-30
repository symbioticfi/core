// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EulerAdapter} from "../../../src/contracts/adapters/EulerAdapter.sol";
import {DeployAdapterBase} from "./DeployAdapterBase.sol";

contract DeployEulerAdapterBase is DeployAdapterBase {
    struct DeployParams {
        address adapterFactoryOwner;
        address eulerLendVaultFactory;
        address cowSwapSettlement;
        address merklDistributor;
    }

    function runBase(DeployParams memory params) public virtual returns (DeploymentData memory data) {
        _validateParams(params);

        address vaultFactory = _coreVaultFactory();

        _startBroadcast();
        data.adapterFactory = _deployAdapterFactory();
        data.adapterImplementation = address(
            new EulerAdapter(
                vaultFactory,
                data.adapterFactory,
                params.merklDistributor,
                params.cowSwapSettlement,
                params.eulerLendVaultFactory
            )
        );
        _whitelistAndTransferOwnership(data, params.adapterFactoryOwner);
        _stopBroadcast();

        _validateAdapterDeployment(data, params.adapterFactoryOwner);
        _logDeployment("Euler", data);
    }

    function _validateParams(DeployParams memory params) internal pure {
        _validateAdapterFactoryOwner(params.adapterFactoryOwner);
        require(params.eulerLendVaultFactory != address(0), "invalid Euler Lend vault factory");
        require(params.cowSwapSettlement != address(0), "invalid CoW settlement");
        require(params.merklDistributor != address(0), "invalid Merkl distributor");
    }
}
