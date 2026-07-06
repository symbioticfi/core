// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// Local-anvil deploy of a single V1 vault (NetworkRestakeDelegator + VetoSlasher)
// so the curator-frontend's V1-only sections — Delegations and Resolvers (the veto
// slasher) — have real on-chain data to render. Self-contained: the stock
// DeployVault script resolves the configurator via SymbioticCoreConstants, which
// reverts on chainId 31337, so this injects the locally-deployed configurator and
// uses the seeded USDC mock as collateral. Driven by
// curator-frontend/scripts/seed-local-chain.sh — not committed to core-mirror.

import {Script} from "forge-std/Script.sol";

import {IVault} from "../../src/interfaces/vault/IVault.sol";
import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";
import {IBaseDelegator} from "../../src/interfaces/delegator/IBaseDelegator.sol";
import {INetworkRestakeDelegator} from "../../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IBaseSlasher} from "../../src/interfaces/slasher/IBaseSlasher.sol";
import {IVetoSlasher} from "../../src/interfaces/slasher/IVetoSlasher.sol";
import {Logs} from "../utils/Logs.sol";

contract DeployV1VaultLocalScript is Script {
    // Locally-deployed core (deterministic EOA-CREATE). The USDC-mock collateral's
    // CREATE address is nonce-dependent and shifts when core-mirror's deploy changes,
    // so the seed passes the resolved address via the V1_COLLATERAL env var. The
    // fallback is the current core-mirror's USDC mock (for direct, seed-less runs).
    address constant VAULT_CONFIGURATOR = 0x09635F643e140090A9A8Dcd712eD6285858ceBef;
    address constant COLLATERAL_FALLBACK = 0x4826533B4897376654Bb4d4AD88B7faFD0C98528;
    address constant BURNER = 0x000000000000000000000000000000000000dEaD;
    uint48 constant EPOCH_DURATION = 7 days;
    uint48 constant VETO_DURATION = 1 days;
    uint48 constant RESOLVER_SET_EPOCHS_DELAY = 3;

    function run() external {
        vm.startBroadcast();
        (,, address owner) = vm.readCallers();

        address collateral = vm.envOr("V1_COLLATERAL", COLLATERAL_FALLBACK);

        address[] memory roleHolders = new address[](1);
        roleHolders[0] = owner;

        bytes memory vaultParams = abi.encode(
            IVault.InitParams({
                collateral: collateral,
                burner: BURNER,
                epochDuration: EPOCH_DURATION,
                depositWhitelist: false,
                isDepositLimit: false,
                depositLimit: 0,
                defaultAdminRoleHolder: owner,
                depositWhitelistSetRoleHolder: owner,
                depositorWhitelistRoleHolder: owner,
                isDepositLimitSetRoleHolder: owner,
                depositLimitSetRoleHolder: owner
            })
        );

        bytes memory delegatorParams = abi.encode(
            INetworkRestakeDelegator.InitParams({
                baseParams: IBaseDelegator.BaseParams({
                    defaultAdminRoleHolder: owner,
                    hook: address(0),
                    hookSetRoleHolder: owner
                }),
                networkLimitSetRoleHolders: roleHolders,
                operatorNetworkSharesSetRoleHolders: roleHolders
            })
        );

        bytes memory slasherParams = abi.encode(
            IVetoSlasher.InitParams({
                baseParams: IBaseSlasher.BaseParams({isBurnerHook: true}),
                vetoDuration: VETO_DURATION,
                resolverSetEpochsDelay: RESOLVER_SET_EPOCHS_DELAY
            })
        );

        (address vault, address delegator, address slasher) = IVaultConfigurator(VAULT_CONFIGURATOR).create(
            IVaultConfigurator.InitParams({
                version: 1,
                owner: owner,
                vaultParams: vaultParams,
                delegatorIndex: 0,
                delegatorParams: delegatorParams,
                withSlasher: true,
                slasherIndex: 1,
                slasherParams: slasherParams
            })
        );

        vm.stopBroadcast();

        Logs.log(string.concat("Deployed V1 vault: ", vm.toString(vault)));
        Logs.log(string.concat("  delegator (NetworkRestake): ", vm.toString(delegator)));
        Logs.log(string.concat("  slasher (Veto): ", vm.toString(slasher)));
    }
}
