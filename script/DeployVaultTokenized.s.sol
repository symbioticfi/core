// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "./base/DeployVaultTokenizedBase.sol";
import {IVaultTokenized} from "../src/interfaces/vault/IVaultTokenized.sol";

contract DeployVaultTokenizedScript is DeployVaultTokenizedBase {
    // Configuration constants - UPDATE THESE BEFORE DEPLOYMENT

    // address of the owner of the vault
    address OWNER = 0x0000000000000000000000000000000000000000;
    // address of the collateral token
    address COLLATERAL = 0x0000000000000000000000000000000000000000;
    // vault's burner to issue debt to (e.g., 0xdEaD or some unwrapper contract)
    address BURNER = 0x0000000000000000000000000000000000000000;
    // duration of the vault epoch
    uint48 EPOCH_DURATION = 1 days;
    // addresses of the whitelisted depositors
    address[] WHITELISTED_DEPOSITORS = new address[](0);
    // deposit limit (maximum amount of the collateral that can be in the vault simultaneously)
    uint256 DEPOSIT_LIMIT = 0;
    // index of the delegator implementation
    uint64 DELEGATOR_INDEX = 0;
    // address of the hook contract for the delegator
    address HOOK = 0x0000000000000000000000000000000000000000;
    // address of the network
    address NETWORK = 0x0000000000000000000000000000000000000000;
    // whether to deploy a slasher
    bool WITH_SLASHER = false;
    // index of the slasher implementation
    uint64 SLASHER_INDEX = 0;
    // duration of a veto period for the slasher
    uint48 VETO_DURATION = 1 days;
    // delay in epochs for a network to update a resolver
    uint48 RESOLVER_SET_EPOCHS_DELAY = 3;
    // name of the tokenized vault
    string NAME = "Test";
    // symbol of the tokenized vault
    string SYMBOL = "TEST";

    // Optional

    // array of addresses of the initial NETWORK_LIMIT_SET_ROLE holders
    address[] NETWORK_ALLOCATION_SETTERS_OR_NETWORK = new address[](0);
    // array of addresses of the initial OPERATOR_ALLOCATION_SETTERS_OR_OPERATOR holders
    address[] OPERATOR_ALLOCATION_SETTERS_OR_OPERATOR = new address[](0);

    constructor()
        DeployVaultTokenizedBase(
            DeployVaultParams({
                owner: OWNER,
                vaultParams: VaultParams({
                    baseParams: IVault.InitParams({
                        collateral: COLLATERAL,
                        burner: BURNER,
                        epochDuration: EPOCH_DURATION,
                        depositWhitelist: WHITELISTED_DEPOSITORS.length != 0,
                        isDepositLimit: DEPOSIT_LIMIT != 0,
                        depositLimit: DEPOSIT_LIMIT,
                        defaultAdminRoleHolder: OWNER,
                        depositWhitelistSetRoleHolder: OWNER,
                        depositorWhitelistRoleHolder: OWNER,
                        isDepositLimitSetRoleHolder: OWNER,
                        depositLimitSetRoleHolder: OWNER
                    }),
                    whitelistedDepositors: WHITELISTED_DEPOSITORS
                }),
                delegatorIndex: DELEGATOR_INDEX,
                delegatorParams: DelegatorParams({
                    baseParams: IBaseDelegator.BaseParams({defaultAdminRoleHolder: OWNER, hook: HOOK, hookSetRoleHolder: OWNER}),
                    networkAllocationSettersOrNetwork: NETWORK_ALLOCATION_SETTERS_OR_NETWORK,
                    operatorAllocationSettersOrOperator: OPERATOR_ALLOCATION_SETTERS_OR_OPERATOR
                }),
                withSlasher: WITH_SLASHER,
                slasherIndex: SLASHER_INDEX,
                slasherParams: SlasherParams({
                    baseParams: IBaseSlasher.BaseParams({isBurnerHook: BURNER != address(0)}),
                    vetoDuration: VETO_DURATION,
                    resolverSetEpochsDelay: RESOLVER_SET_EPOCHS_DELAY
                })
            }),
            _buidEncodedParams()
        )
    {}

    function _buidEncodedParams() internal returns (bytes memory vaultParamsEncoded) {
        (,, address deployer) = vm.readCallers();
        bool needWhitelistDepositors = WHITELISTED_DEPOSITORS.length != 0;

        vaultParamsEncoded = abi.encode(
            IVaultTokenized.InitParamsTokenized({
                baseParams: IVault.InitParams({
                    collateral: COLLATERAL,
                    burner: BURNER,
                    epochDuration: EPOCH_DURATION,
                    depositWhitelist: WHITELISTED_DEPOSITORS.length != 0,
                    isDepositLimit: DEPOSIT_LIMIT != 0,
                    depositLimit: DEPOSIT_LIMIT,
                    defaultAdminRoleHolder: needWhitelistDepositors ? deployer : OWNER,
                    depositWhitelistSetRoleHolder: OWNER,
                    depositorWhitelistRoleHolder: needWhitelistDepositors ? deployer : OWNER,
                    isDepositLimitSetRoleHolder: OWNER,
                    depositLimitSetRoleHolder: OWNER
                }),
                name: NAME,
                symbol: SYMBOL
            })
        );
    }
}
