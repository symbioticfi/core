// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {VaultBase} from "./base/VaultBase.sol";

contract VaultScript is VaultBase {
    address VAULT_CONFIGURATOR = 0x0000000000000000000000000000000000000000;
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
        VaultBase(
            VaultParams({
                vaultConfigurator: VAULT_CONFIGURATOR,
                owner: OWNER,
                collateral: COLLATERAL,
                burner: BURNER,
                epochDuration: EPOCH_DURATION,
                whitelistedDepositors: WHITELISTED_DEPOSITORS,
                depositLimit: DEPOSIT_LIMIT,
                delegatorIndex: DELEGATOR_INDEX,
                hook: HOOK,
                network: NETWORK,
                withSlasher: WITH_SLASHER,
                slasherIndex: SLASHER_INDEX,
                vetoDuration: VETO_DURATION
            })
        )
    {}
}
