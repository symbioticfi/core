// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "./base/DeployVaultBase.sol";

contract DeployVaultScript is DeployVaultBase {
    // Configuration constants - UPDATE THESE BEFORE DEPLOYMENT

    // Address of the owner of the vault who can migrate the vault to new versions whitelisted by Symbiotic
    address constant OWNER = 0x0000000000000000000000000000000000000000;
    // Address of the collateral token
    address constant COLLATERAL = 0x0000000000000000000000000000000000000000;
    // Vault's burner to send slashed funds to (e.g., 0xdEaD or some unwrapper contract; not used in case of no slasher)
    address constant BURNER = 0x0000000000000000000000000000000000000000;
    // Duration of the vault epoch (the withdrawal delay for staker varies from EPOCH_DURATION to 2 * EPOCH_DURATION depending on when the withdrawal is requested)
    uint48 constant EPOCH_DURATION = 1 days;
    // Type of the delegator:
    //  0. NetworkRestakeDelegator (allows restaking across multiple networks and having multiple operators per network)
    //  1. FullRestakeDelegator (do not use without knowing what you are doing)
    //  2. OperatorSpecificDelegator (allows restaking across multiple networks with only a single operator)
    //  3. OperatorNetworkSpecificDelegator (allocates the stake to a specific operator and network)
    uint64 constant DELEGATOR_INDEX = 0;
    // Setting depending on the delegator type:
    // 0. NetworkLimitSetRoleHolders (adjust allocations for networks)
    // 1. NetworkLimitSetRoleHolders (adjust allocations for networks)
    // 2. NetworkLimitSetRoleHolders (adjust allocations for networks)
    // 3. network (the only network that will receive the stake; should be an array with a single element)
    address constant NETWORK_ALLOCATION_SETTER = 0x0000000000000000000000000000000000000000;
    // Setting depending on the delegator type:
    // 0. OperatorNetworkSharesSetRoleHolders (adjust allocations for operators inside networks; in shares, resulting percentage is operatorShares / totalOperatorShares)
    // 1. OperatorNetworkLimitSetRoleHolders (adjust allocations for operators inside networks; in shares, resulting percentage is operatorShares / totalOperatorShares)
    // 2. operator (the only operator that will receive the stake; should be an array with a single element)
    // 3. operator (the only operator that will receive the stake; should be an array with a single element)
    address constant OPERATOR_ALLOCATION_SETTER = 0x0000000000000000000000000000000000000000;
    // Whether to deploy a slasher
    bool constant WITH_SLASHER = false;
    // Type of the slasher:
    //  0. Slasher (allows instant slashing)
    //  1. VetoSlasher (allows having a veto period if the resolver is set)
    uint64 constant SLASHER_INDEX = 1;
    // Duration of a veto period (should be less than EPOCH_DURATION)
    uint48 constant VETO_DURATION = 1 days;

    // Optional

    // Deposit limit (maximum amount of the active stake allowed in the vault)
    uint256 constant DEPOSIT_LIMIT = 0;
    // Comma-separated list of addresses of the whitelisted depositors
    string constant WHITELISTED_DEPOSITORS = "";
    // Address of the hook contract which, e.g., can automatically adjust the allocations on slashing events (not used in case of no slasher)
    address constant HOOK = 0x0000000000000000000000000000000000000000;
    // Delay in epochs for a network to update a resolver
    uint48 constant RESOLVER_SET_EPOCHS_DELAY = 3;

    constructor()
        DeployVaultBase(
            DeployVaultParams({
                owner: OWNER,
                vaultParams: VaultParams({
                    baseParams: IVault.InitParams({
                        collateral: COLLATERAL,
                        burner: BURNER,
                        epochDuration: EPOCH_DURATION,
                        depositWhitelist: bytes(WHITELISTED_DEPOSITORS).length != 0,
                        isDepositLimit: DEPOSIT_LIMIT != 0,
                        depositLimit: DEPOSIT_LIMIT,
                        defaultAdminRoleHolder: OWNER,
                        depositWhitelistSetRoleHolder: OWNER,
                        depositorWhitelistRoleHolder: OWNER,
                        isDepositLimitSetRoleHolder: OWNER,
                        depositLimitSetRoleHolder: OWNER
                    }),
                    whitelistedDepositors: parseAddressesFromString(WHITELISTED_DEPOSITORS)
                }),
                delegatorIndex: DELEGATOR_INDEX,
                delegatorParams: DelegatorParams({
                    baseParams: IBaseDelegator.BaseParams({defaultAdminRoleHolder: OWNER, hook: HOOK, hookSetRoleHolder: OWNER}),
                    networkAllocationSettersOrNetwork: _createArray(NETWORK_ALLOCATION_SETTER),
                    operatorAllocationSettersOrOperator: _createArray(OPERATOR_ALLOCATION_SETTER)
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

    function _createArray(
        address element
    ) private pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = element;
        return arr;
    }
}
