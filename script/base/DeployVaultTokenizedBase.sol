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

    function _buidEncodedParams() internal virtual override returns (bytes memory vaultParamsEncoded) {
        (,, address deployer) = vm.readCallers();
        bool needWhitelistDepositors = params.vaultParams.whitelistedDepositors.length != 0;

        vaultParamsEncoded = abi.encode(
            IVaultTokenized.InitParamsTokenized({
                baseParams: IVault.InitParams({
                    collateral: params.vaultParams.baseParams.collateral,
                    burner: params.vaultParams.baseParams.burner,
                    epochDuration: params.vaultParams.baseParams.epochDuration,
                    depositWhitelist: params.vaultParams.baseParams.depositWhitelist,
                    isDepositLimit: params.vaultParams.baseParams.isDepositLimit,
                    depositLimit: params.vaultParams.baseParams.depositLimit,
                    defaultAdminRoleHolder: needWhitelistDepositors
                        ? deployer
                        : params.vaultParams.baseParams.defaultAdminRoleHolder,
                    depositWhitelistSetRoleHolder: params.vaultParams.baseParams.depositWhitelistSetRoleHolder,
                    depositorWhitelistRoleHolder: needWhitelistDepositors
                        ? deployer
                        : params.vaultParams.baseParams.depositorWhitelistRoleHolder,
                    isDepositLimitSetRoleHolder: params.vaultParams.baseParams.isDepositLimitSetRoleHolder,
                    depositLimitSetRoleHolder: params.vaultParams.baseParams.depositLimitSetRoleHolder
                }),
                name: name,
                symbol: symbol
            })
        );
    }
}
