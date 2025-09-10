// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "./base/DeployVaultBase.sol";

contract DeployVaultScript is DeployVaultBase {
    // Configuration constants - UPDATE THESE BEFORE DEPLOYMENT

    // Address of the owner of the vault who can migrate the vault to new versions whitelisted by Symbiotic
    address OWNER = 0x0000000000000000000000000000000000000000;
    // Address of the collateral token
    address COLLATERAL = 0x0000000000000000000000000000000000000000;
    // Vault's burner to send slashed funds to (e.g., 0xdEaD or some unwrapper contract; not used in case of no slasher)
    address BURNER = 0x0000000000000000000000000000000000000000;
    // Duration of the vault epoch (the withdrawal delay for staker varies from EPOCH_DURATION to 2 * EPOCH_DURATION depending on when the withdrawal is requested)
    uint48 EPOCH_DURATION = 1 days;
    // Type of the delegator:
    //  0. NetworkRestakeDelegator (allows restaking across multiple networks and having multiple operators per network)
    //  1. FullRestakeDelegator (do not use without knowing what you are doing)
    //  2. OperatorSpecificDelegator (allows restaking across multiple networks with only a single operator)
    //  3. OperatorNetworkSpecificDelegator (allocates the stake to a specific operator and network)
    uint64 DELEGATOR_INDEX = 0;
    // Setting depending on the delegator type:
    // 0. NetworkLimitSetRoleHolders (adjust allocations for networks)
    // 1. NetworkLimitSetRoleHolders (adjust allocations for networks)
    // 2. NetworkLimitSetRoleHolders (adjust allocations for networks)
    // 3. network (the only network that will receive the stake; should be an array with a single element)
    address[] NETWORK_ALLOCATION_SETTERS_OR_NETWORK = [0x0000000000000000000000000000000000000000];
    // Setting depending on the delegator type:
    // 0. OperatorNetworkSharesSetRoleHolders (adjust allocations for operators inside networks; in shares, resulting percentage is operatorShares / totalOperatorShares)
    // 1. OperatorNetworkLimitSetRoleHolders (adjust allocations for operators inside networks; in shares, resulting percentage is operatorShares / totalOperatorShares)
    // 2. operator (the only operator that will receive the stake; should be an array with a single element)
    // 3. operator (the only operator that will receive the stake; should be an array with a single element)
    address[] OPERATOR_ALLOCATION_SETTERS_OR_OPERATOR = [0x0000000000000000000000000000000000000000];
    // Whether to deploy a slasher
    bool WITH_SLASHER = false;
    // Type of the slasher:
    //  0. Slasher (allows instant slashing)
    //  1. VetoSlasher (allows having a veto period if the resolver is set)
    uint64 SLASHER_INDEX = 1;
    // Duration of a veto period (should be less than EPOCH_DURATION)
    uint48 VETO_DURATION = 1 days;

    // Optional

    // Deposit limit (maximum amount of the active stake allowed in the vault)
    uint256 DEPOSIT_LIMIT = 0;
    // Addresses of the whitelisted depositors
    address[] WHITELISTED_DEPOSITORS = new address[](0);
    // Address of the hook contract which, e.g., can automatically adjust the allocations on slashing events (not used in case of no slasher)
    address HOOK = 0x0000000000000000000000000000000000000000;
    // Delay in epochs for a network to update a resolver
    uint48 RESOLVER_SET_EPOCHS_DELAY = 3;

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
            })
        )
    {}
}
