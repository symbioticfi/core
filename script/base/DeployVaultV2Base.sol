// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";

import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";
import {IUniversalDelegator, UNIVERSAL_DELEGATOR_TYPE} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
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
        IUniversalDelegator.InitParams delegatorParams;
    }

    function runBase(DeployVaultV2Params memory params) public returns (address, address, address) {
        vm.startBroadcast();

        (address vault_, address delegator_, address slasher_) = IVaultConfigurator(
                SymbioticCoreConstants.core().vaultConfigurator
            )
            .create(
                IVaultConfigurator.InitParams({
                version: _getVaultVersion(),
                owner: params.owner,
                vaultParams: _getVaultParamsEncoded(params),
                delegatorIndex: UNIVERSAL_DELEGATOR_TYPE,
                delegatorParams: abi.encode(params.delegatorParams),
                withSlasher: false,
                slasherIndex: 0,
                slasherParams: ""
            })
            );

        Logs.log(
            string.concat(
                "Deployed VaultV2",
                "\n    vault:",
                vm.toString(vault_),
                "\n    delegator:",
                vm.toString(delegator_),
                "\n    slasher:",
                vm.toString(slasher_)
            )
        );

        _validateDeployment(vault_, delegator_, slasher_);

        vm.stopBroadcast();
        return (vault_, delegator_, slasher_);
    }

    function _getVaultVersion() internal virtual returns (uint64) {
        return VAULT_V2_VERSION;
    }

    function _getVaultParamsEncoded(DeployVaultV2Params memory params) internal pure virtual returns (bytes memory) {
        return abi.encode(params.vaultParams.baseParams);
    }

    function _validateDeployment(address vault, address delegator, address slasher) internal view {
        assert(IVaultV2(vault).delegator() == delegator);
        assert(IUniversalDelegator(delegator).vault() == vault);
        assert(slasher == address(0));
    }
}
