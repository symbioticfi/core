// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./base/DeployVaultV2Base.sol";

// forge script script/DeployVaultV2.s.sol:DeployVaultV2Script --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract DeployVaultV2Script is DeployVaultV2Base {
    // Configurations - UPDATE THESE BEFORE DEPLOYMENT

    // Name of the ERC20 representing shares of the active stake in the vault
    string NAME = "SymVault";
    // Symbol of the ERC20 representing shares of the active stake in the vault
    string SYMBOL = "SV";
    // Address of the owner of the vault who can migrate the vault to new versions whitelisted by Symbiotic
    address OWNER = 0x0000000000000000000000000000000000000000;
    // Address of the collateral token
    address COLLATERAL = 0x0000000000000000000000000000000000000001;
    // Vault's burner to send slashed funds to (e.g., 0xdEaD or some unwrapper contract; not used in case of no slasher)
    address BURNER = 0x000000000000000000000000000000000000dEaD;
    // Duration of the vault epoch (the withdrawal delay for staker varies from EPOCH_DURATION to 2 * EPOCH_DURATION depending on when the withdrawal is requested)
    uint48 EPOCH_DURATION = 7 days;
    // Initial depositor to whitelist (VaultV2 requires one non-zero address even when the deposit whitelist is disabled)
    address DEPOSITOR_TO_WHITELIST = 0x0000000000000000000000000000000000000001;
    // Initial withdrawal buffer size
    uint128 WITHDRAWAL_BUFFER_SIZE = type(uint128).max;
    // Whether to deploy a slasher
    bool WITH_SLASHER = true;
    // Whether slash execution should make a call to the burner on slashing
    bool IS_BURNER_HOOK = BURNER != address(0);
    // Duration of a veto period (should be less than EPOCH_DURATION)
    uint48 VETO_DURATION = 1 days;
    // Delay before a resolver update becomes active (should be greater than EPOCH_DURATION)
    uint48 RESOLVER_SET_DELAY = 21 days;

    // Optional

    // Deposit limit (maximum amount of the active stake allowed in the vault)
    uint256 DEPOSIT_LIMIT = 0;

    function run() public {
        runBase(
            DeployVaultV2Params({
                owner: OWNER,
                vaultParams: IVaultV2.InitParams({
                    name: NAME,
                    symbol: SYMBOL,
                    collateral: COLLATERAL,
                    burner: BURNER,
                    epochDuration: EPOCH_DURATION,
                    depositWhitelist: false,
                    depositorToWhitelist: DEPOSITOR_TO_WHITELIST,
                    isDepositLimit: DEPOSIT_LIMIT != 0,
                    depositLimit: DEPOSIT_LIMIT,
                    defaultAdminRoleHolder: OWNER,
                    depositWhitelistSetRoleHolder: OWNER,
                    depositorWhitelistRoleHolder: OWNER,
                    isDepositLimitSetRoleHolder: OWNER,
                    depositLimitSetRoleHolder: OWNER,
                    setAdapterLimitRoleHolder: OWNER,
                    swapAdaptersRoleHolder: OWNER,
                    allocateAdapterRoleHolder: OWNER,
                    deallocateAdapterRoleHolder: OWNER
                }),
                delegatorParams: IUniversalDelegator.InitParams({
                    defaultAdminRoleHolder: OWNER,
                    createSlotRoleHolder: OWNER,
                    setSizeRoleHolder: OWNER,
                    swapSlotsRoleHolder: OWNER,
                    removeSlotRoleHolder: OWNER,
                    setWithdrawalBufferSizeRoleHolder: OWNER,
                    withdrawalBufferSize: WITHDRAWAL_BUFFER_SIZE
                }),
                withSlasher: WITH_SLASHER,
                slasherParams: IUniversalSlasher.InitParams({
                    isBurnerHook: IS_BURNER_HOOK, vetoDuration: VETO_DURATION, resolverSetDelay: RESOLVER_SET_DELAY
                })
            })
        );
    }
}
