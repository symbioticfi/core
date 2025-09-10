// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "./base/DeployVaultBase.sol";

contract VaultScript is DeployVaultBase {
    address OWNER = 0x0000000000000000000000000000000000000000;
    address COLLATERAL = 0x0000000000000000000000000000000000000000;
    address BURNER = 0x0000000000000000000000000000000000000000;
    uint48 EPOCH_DURATION = 1 days;
    address[] WHITELISTED_DEPOSITORS = new address[](0);
    uint256 DEPOSIT_LIMIT = 0;
    uint64 DELEGATOR_INDEX = 0;
    address HOOK = 0x0000000000000000000000000000000000000000;
    address NETWORK = 0x0000000000000000000000000000000000000000;
    bool WITH_SLASHER = false;
    uint64 SLASHER_INDEX = 0;
    uint48 VETO_DURATION = 1 days;

    constructor()
        DeployVaultBase(
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
                    networkAllocationSettersOrNetwork: new address[](0),
                    operatorAllocationSettersOrOperator: new address[](0)
                }),
                withSlasher: WITH_SLASHER,
                slasherIndex: SLASHER_INDEX,
                slasherParams: SlasherParams({
                    baseParams: IBaseSlasher.BaseParams({isBurnerHook: BURNER != address(0)}),
                    vetoDuration: VETO_DURATION,
                    resolverSetEpochsDelay: 3
                })
            })
        )
    {}
}
