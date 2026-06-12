// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";

import {IVaultConfigurator} from "../src/interfaces/IVaultConfigurator.sol";
import {IUniversalDelegator, UNIVERSAL_DELEGATOR_TYPE} from "../src/interfaces/delegator/IUniversalDelegator.sol";
import {IVaultV2, VAULT_V2_VERSION} from "../src/interfaces/vault/IVaultV2.sol";
import {Logs} from "./utils/Logs.sol";
import {SymbioticCoreConstants} from "../test/integration/SymbioticCoreConstants.sol";

// forge script script/DeployVaultV2.s.sol:DeployVaultV2Script --rpc-url=RPC --account=ACCOUNT --sender=SENDER --broadcast

contract DeployVaultV2Script is Script {
    // Configurations - UPDATE THESE BEFORE DEPLOYMENT

    // Name of the ERC20 representing shares in the vault
    string NAME = "SymVault";
    // Symbol of the ERC20 representing shares in the vault
    string SYMBOL = "SV";
    // Address of the owner of the vault who can migrate the vault to new versions whitelisted by Symbiotic
    address OWNER = 0x0000000000000000000000000000000000000000;
    // Address of the vault asset token
    address ASSET = 0x0000000000000000000000000000000000000000;

    // Optional

    // Deposit limit (maximum amount of assets allowed in the vault)
    uint256 DEPOSIT_LIMIT = 0;
    // Whether deposits are restricted to whitelisted depositors
    bool DEPOSIT_WHITELIST = false;
    // Initial whitelisted depositor (used only when DEPOSIT_WHITELIST is true)
    address DEPOSITOR_TO_WHITELIST = 0x0000000000000000000000000000000000000000;

    function run() public returns (address vault, address delegator, address slasher) {
        SymbioticCoreConstants.Core memory core = SymbioticCoreConstants.core();

        bytes memory vaultParams = abi.encode(
            IVaultV2.InitParams({
                name: NAME,
                symbol: SYMBOL,
                asset: ASSET,
                depositWhitelist: DEPOSIT_WHITELIST,
                depositorToWhitelist: DEPOSITOR_TO_WHITELIST,
                depositLimit: DEPOSIT_LIMIT,
                isDepositLimit: DEPOSIT_LIMIT != 0,
                defaultAdminRoleHolder: OWNER,
                managementFeeRoleHolder: OWNER,
                performanceFeeRoleHolder: OWNER,
                depositLimitSetRoleHolder: OWNER,
                depositorWhitelistRoleHolder: OWNER,
                isDepositLimitSetRoleHolder: OWNER,
                depositWhitelistSetRoleHolder: OWNER
            })
        );

        bytes memory delegatorParams = abi.encode(
            IUniversalDelegator.InitParams({
                allocateRoleHolder: OWNER,
                deallocateRoleHolder: OWNER,
                addAdapterRoleHolder: OWNER,
                swapAdaptersRoleHolder: OWNER,
                defaultAdminRoleHolder: OWNER,
                removeAdapterRoleHolder: OWNER,
                setAdapterLimitsRoleHolder: OWNER,
                setAutoAllocateAdaptersRoleHolder: OWNER
            })
        );

        vm.startBroadcast();
        (vault, delegator, slasher) = IVaultConfigurator(core.vaultConfigurator)
            .create(
                IVaultConfigurator.InitParams({
                version: VAULT_V2_VERSION,
                owner: OWNER,
                vaultParams: vaultParams,
                delegatorIndex: UNIVERSAL_DELEGATOR_TYPE,
                delegatorParams: delegatorParams,
                withSlasher: false,
                slasherIndex: 0,
                slasherParams: ""
            })
            );
        vm.stopBroadcast();

        assert(IVaultV2(vault).delegator() == delegator);
        assert(IUniversalDelegator(delegator).vault() == vault);
        assert(slasher == address(0));

        Logs.log(
            string.concat(
                "Deployed VaultV2",
                "\n    vault:",
                vm.toString(vault),
                "\n    delegator:",
                vm.toString(delegator),
                "\n    slasher:",
                vm.toString(slasher)
            )
        );
    }
}
