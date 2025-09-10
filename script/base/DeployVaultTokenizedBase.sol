// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "./DeployVaultBase.sol";
import {IVaultTokenized} from "../../src/interfaces/vault/IVaultTokenized.sol";

contract DeployVaultTokenizedBase is DeployVaultBase {
    string public name;
    string public symbol;

    constructor(DeployVaultParams memory params, string memory name_, string memory symbol_) DeployVaultBase(params) {
        name = name_;
        symbol = symbol_;
    }

    function _buildEncodedParams() internal virtual override returns (bytes memory vaultParamsEncoded) {
        (,, address deployer) = vm.readCallers();
        bool needWhitelistDepositors = params.vaultParams.whitelistedDepositors.length != 0;

        IVault.InitParams memory baseParams = abi.decode(abi.encode(params.vaultParams.baseParams), (IVault.InitParams));
        baseParams.defaultAdminRoleHolder =
            needWhitelistDepositors ? deployer : params.vaultParams.baseParams.defaultAdminRoleHolder;
        baseParams.depositorWhitelistRoleHolder =
            needWhitelistDepositors ? deployer : params.vaultParams.baseParams.depositorWhitelistRoleHolder;

        vaultParamsEncoded =
            abi.encode(IVaultTokenized.InitParamsTokenized({baseParams: baseParams, name: name, symbol: symbol}));
    }
}
