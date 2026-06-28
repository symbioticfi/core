// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC4626Adapter} from "../../../src/contracts/adapters/ERC4626Adapter.sol";
import {DeployAdapterBase} from "./DeployAdapterBase.sol";

contract DeployERC4626AdapterBase is DeployAdapterBase {
    struct DeployParams {
        address adapterFactoryOwner;
        address cowSwapSettlement;
        address merklDistributor;
    }

    function runBase(DeployParams memory params) public virtual returns (DeploymentData memory data) {
        _validateParams(params);

        address vaultFactory = _coreVaultFactory();

        _startBroadcast();
        data.adapterFactory = _deployAdapterFactory();
        data.adapterImplementation = address(
            new ERC4626Adapter(vaultFactory, data.adapterFactory, params.merklDistributor, params.cowSwapSettlement)
        );
        _whitelistAndTransferOwnership(data, params.adapterFactoryOwner);
        _stopBroadcast();

        _validateAdapterDeployment(data, params.adapterFactoryOwner);
        _logDeployment("ERC4626", data);
    }

    function _validateParams(DeployParams memory params) internal pure {
        _validateAdapterFactoryOwner(params.adapterFactoryOwner);
        require(params.cowSwapSettlement != address(0), "invalid CoW settlement");
        require(params.merklDistributor != address(0), "invalid Merkl distributor");
    }
}
