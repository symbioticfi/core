// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "./DeployVaultBase.sol";
import {IVaultTokenized} from "../../src/interfaces/vault/IVaultTokenized.sol";

contract DeployVaultTokenizedBase is DeployVaultBase {
    struct DeployVaultTokenizedParams {
        DeployVaultParams deployVaultParams;
        string name;
        string symbol;
    }

    string public name;
    string public symbol;

    constructor(
        DeployVaultTokenizedParams memory params_
    ) DeployVaultBase(params_.deployVaultParams) {
        name = params_.name;
        symbol = params_.symbol;
    }

    function _getVaultParamsEncoded() internal virtual override returns (bytes memory) {
        (,, address deployer) = vm.readCallers();
        bool needWhitelistDepositors = params.vaultParams.whitelistedDepositors.length != 0;

        IVault.InitParams memory baseParams = params.vaultParams.baseParams;
        baseParams.defaultAdminRoleHolder =
            needWhitelistDepositors ? deployer : params.vaultParams.baseParams.defaultAdminRoleHolder;
        baseParams.depositorWhitelistRoleHolder =
            needWhitelistDepositors ? deployer : params.vaultParams.baseParams.depositorWhitelistRoleHolder;

        return abi.encode(IVaultTokenized.InitParamsTokenized({baseParams: baseParams, name: name, symbol: symbol}));
    }
}
