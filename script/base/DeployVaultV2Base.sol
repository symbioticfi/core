// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";

import {IUniversalDelegator} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IVaultV2, VAULT_V2_VERSION} from "../../src/interfaces/vault/IVaultV2.sol";
import {Logs} from "../utils/Logs.sol";
import {SymbioticCoreConstants} from "../../test/integration/SymbioticCoreConstants.sol";

contract DeployVaultV2Base is Script {
    struct VaultV2Params {
        IVaultV2.InitParams baseParams;
    }

    struct DeployVaultV2Params {
        address owner;
        VaultV2Params vaultParams;
    }

    function runBase(DeployVaultV2Params memory params) public returns (address, address) {
        vm.startBroadcast();

        address vault_ = address(
            SymbioticCoreConstants.core().vaultFactory
                .create(_getVaultVersion(), params.owner, _getVaultParamsEncoded(params))
        );
        address delegator_ = IVaultV2(vault_).delegator();

        Logs.log(
            string.concat(
                "Deployed VaultV2", "\n    vault:", vm.toString(vault_), "\n    delegator:", vm.toString(delegator_)
            )
        );

        _validateDeployment(vault_, delegator_);

        vm.stopBroadcast();
        return (vault_, delegator_);
    }

    function _getVaultVersion() internal virtual returns (uint64) {
        return VAULT_V2_VERSION;
    }

    function _getVaultParamsEncoded(DeployVaultV2Params memory params) internal pure virtual returns (bytes memory) {
        return abi.encode(params.vaultParams.baseParams);
    }

    function _validateDeployment(address vault, address delegator) internal view {
        assert(IVaultV2(vault).delegator() == delegator);
        assert(IUniversalDelegator(delegator).vault() == vault);
    }
}
