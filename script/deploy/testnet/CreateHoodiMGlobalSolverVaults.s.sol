// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console2} from "forge-std/Script.sol";

import {IAdapterRegistry} from "src/interfaces/IAdapterRegistry.sol";
import {ILiquidLaneAdapter} from "src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {IMigratablesFactory} from "src/interfaces/common/IMigratablesFactory.sol";
import {IUniversalDelegator, MAX_SHARE} from "src/interfaces/delegator/IUniversalDelegator.sol";
import {IVaultV2, VAULT_V2_VERSION} from "src/interfaces/vault/IVaultV2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface ITestnetERC20Mintable {
    function mint(address to, uint256 amount) external;
}

/**
 * @title CreateHoodiMGlobalSolverVaults
 * @notice Deploys 3 dedicated USDC-asset LiquidLane vaults+adapters on Hoodi, one per solver
 *         executor, reusing the existing AdapterFactory/AdapterRegistry/AccountRegistry/VaultFactory
 *         and Midas oracle/account/redemption infra (NO core/oracle redeploy).
 *
 * @dev Per adapter i in [first, second, third]:
 *      (a) create USDC vault (OWNER as every role holder, UniversalDelegator wired)
 *      (b) read delegator = IVaultV2(vault).delegator()
 *      (c) create LiquidLane adapter via the LiquidLane AdapterFactory
 *      (d) adapterRegistry.setWhitelistedStatus(vault, adapter, true)  [BEFORE addAdapter]
 *      (e) delegator.addAdapter(adapter)
 *      (f) delegator.setLimits(adapter, type(uint256).max, MAX_SHARE)
 *      (g) adapter.addTokenToRedeem(mGLOBAL)  [auto-creates the Midas account]
 *      (h) adapter.setLimit(mGLOBAL, type(uint128).max)
 *      (i) adapter.setMinDiscount(mGLOBAL, 0)
 *      (j) adapter.setMarketMaker(OWNER, true)  [mirrors the two proven on-chain adapters; the
 *          RFQ fill path uses the discount-swap variant which authenticates discount.signer, and
 *          discounts are signed by OWNER == owner(), so no per-solver marketMaker/filler is needed
 *          on-chain — each adapter is bound to its solver purely via the solver's `adapters` config
 *          + the discount posted on it]
 *      then seed USDC liquidity (mint to OWNER + approve + deposit). The vault's withdrawable() USDC
 *      directly backs fills (getMaxAssets uses withdrawable()); no delegator allocate is needed —
 *      LiquidLane allocatable() is 0 outside a swap, so an explicit allocate would be a silent no-op.
 *      The `executor` arg is recorded only for logging / config mapping (which vault → which solver).
 *
 *      Run:  forge build   (NEVER --broadcast in this draft)
 */
contract CreateHoodiMGlobalSolverVaults is Script {
    /* ---- Hoodi constants (all verified on-chain) ---- */

    // Deployer / owner EOA (every role holder + broadcasting key)
    address internal constant OWNER = 0xc056736be7C05790667CDb678c03eb09F616E157;

    // Canonical V2 VaultFactory (lastVersion == VAULT_V2_VERSION == 3)
    address internal constant VAULT_FACTORY = 0x600Fcd6256DDaB8C649d599fC5b8031bD5F912DA;

    // LiquidLane AdapterFactory (lastVersion == 1; LiquidLaneAdapter impl whitelisted as v1)
    address internal constant ADAPTER_FACTORY = 0x7Ce3f158f22aC66F8Ed2973B7a10F666818301C5;

    // AdapterRegistry (per-vault adapter whitelist; OWNER-gated)
    address internal constant ADAPTER_REGISTRY = 0x32b7a1Cbd387aC9aC7f3fb06F889575924a2F988;

    // Tokens: USDC (vault asset, 6 dec, OWNER-mintable testnet token); mGLOBAL (token-to-redeem, 18 dec)
    address internal constant USDC = 0x9B97F7eDAbd9Ef43cAcE2eaFDD1DE5721aE3Bdd3;
    address internal constant MGLOBAL = 0x2Ee6f1A395Bce7a7c5bF1D07bAaF9F8A0828A8d3;

    // Per-solver Hoodi executors (market-maker target, one per adapter)
    address internal constant EXECUTOR_FIRST = 0x910af97D2402681a6B57D0794B9246Eae17c0B24;
    address internal constant EXECUTOR_SECOND = 0x37bF9f850b7C3334D3Fc252D79215C088D8be30d;
    address internal constant EXECUTOR_THIRD = 0x1B321F3B62AF7B3dF25E01800094802e3621C9dc;

    /* ---- Tunables ---- */

    // mGLOBAL per-token vault-asset limit and delegator absolute limit: 2^128 - 1 (mirrors existing adapter)
    uint256 internal constant TOKEN_LIMIT = type(uint128).max;
    // mGLOBAL minimum discount in ppm (existing working adapter uses 0)
    uint256 internal constant MIN_DISCOUNT = 0;

    // Per-vault USDC seed (6 decimals). This is minted to OWNER and deposited into each vault; it
    // becomes the vault's withdrawable() balance, which IS the fill capacity (getMaxAssets caps
    // maxCollateralOut to withdrawable()). 100k USDC comfortably covers the manifest's largest mGLOBAL
    // quote tier (100_000 mGLOBAL). Testnet USDC is freely OWNER-mintable; raise this for more depth.
    uint256 internal constant DEPOSIT_AMOUNT = 100_000e6;

    function run() external {
        vm.startBroadcast();

        _deployOne("Hoodi mGLOBAL USDC Vault 1", "mGUSDC1", EXECUTOR_FIRST);
        _deployOne("Hoodi mGLOBAL USDC Vault 2", "mGUSDC2", EXECUTOR_SECOND);
        _deployOne("Hoodi mGLOBAL USDC Vault 3", "mGUSDC3", EXECUTOR_THIRD);

        vm.stopBroadcast();
    }

    function _deployOne(string memory name, string memory symbol, address executor) internal {
        // (a) create the USDC vault
        address vault = IMigratablesFactory(VAULT_FACTORY).create(VAULT_V2_VERSION, OWNER, _vaultParams(name, symbol));

        // (b) read the auto-deployed delegator
        address delegator = IVaultV2(vault).delegator();

        // (c) create the LiquidLane adapter (version read defensively from the factory)
        uint64 adapterVersion = IMigratablesFactory(ADAPTER_FACTORY).lastVersion();
        address adapter = IMigratablesFactory(ADAPTER_FACTORY)
            .create(
                adapterVersion,
                OWNER,
                abi.encode(vault, abi.encode(ILiquidLaneAdapter.InitParams({pauser: OWNER, unpauser: OWNER})))
            );

        // (d) whitelist the adapter for the vault BEFORE wiring it into the delegator
        IAdapterRegistry(ADAPTER_REGISTRY).setWhitelistedStatus(vault, adapter, true);

        // (e) + (f) register the adapter with the delegator and set its limits
        IUniversalDelegator(delegator).addAdapter(adapter);
        IUniversalDelegator(delegator).setLimits(adapter, type(uint256).max, MAX_SHARE);

        // (g) configure mGLOBAL as a token-to-redeem (auto-creates the Midas account via AccountRegistry)
        ILiquidLaneAdapter(adapter).addTokenToRedeem(MGLOBAL);

        // (h) + (i) per-token limit and minimum discount
        ILiquidLaneAdapter(adapter).setLimit(MGLOBAL, TOKEN_LIMIT);
        ILiquidLaneAdapter(adapter).setMinDiscount(MGLOBAL, MIN_DISCOUNT);

        // (j) marketMaker = OWNER, canAcquire = true — identical to the proven on-chain adapters.
        // Discount-signed fills authenticate via owner(), so no per-solver marketMaker/filler on-chain.
        ILiquidLaneAdapter(adapter).setMarketMaker(OWNER, true);

        // Seed USDC liquidity: mint -> approve -> deposit. The deposit becomes vault.withdrawable(),
        // which getMaxAssets uses as the fill capacity — no delegator allocate (it would be a no-op).
        ITestnetERC20Mintable(USDC).mint(OWNER, DEPOSIT_AMOUNT);
        IERC20(USDC).approve(vault, DEPOSIT_AMOUNT);
        IERC4626(vault).deposit(DEPOSIT_AMOUNT, OWNER);

        _log(name, vault, delegator, adapter, executor);
    }

    function _vaultParams(string memory name, string memory symbol) internal pure returns (bytes memory) {
        return abi.encode(
            IVaultV2.InitParams({
                name: name,
                symbol: symbol,
                asset: USDC,
                depositWhitelist: false,
                depositorToWhitelist: address(0),
                depositLimit: type(uint256).max,
                isDepositLimit: true,
                defaultAdminRoleHolder: OWNER,
                managementFeeRoleHolder: OWNER,
                performanceFeeRoleHolder: OWNER,
                depositLimitSetRoleHolder: OWNER,
                depositorWhitelistRoleHolder: OWNER,
                isDepositLimitSetRoleHolder: OWNER,
                depositWhitelistSetRoleHolder: OWNER,
                delegatorParams: abi.encode(
                    IUniversalDelegator.InitParams({
                        allocateRoleHolder: OWNER,
                        deallocateRoleHolder: OWNER,
                        addAdapterRoleHolder: OWNER,
                        swapAdaptersRoleHolder: OWNER,
                        defaultAdminRoleHolder: OWNER,
                        removeAdapterRoleHolder: OWNER,
                        forceDeallocateRoleHolder: OWNER,
                        setAdapterLimitsRoleHolder: OWNER,
                        setAutoAllocateAdaptersRoleHolder: OWNER
                    })
                )
            })
        );
    }

    function _log(string memory name, address vault, address delegator, address adapter, address executor)
        internal
        view
    {
        console2.log("====", name, "====");
        console2.log("Vault:", vault);
        console2.log("Delegator:", delegator);
        console2.log("Adapter:", adapter);
        console2.log("Asset:", IERC4626(vault).asset());
        console2.log("MarketMaker:", ILiquidLaneAdapter(adapter).marketMaker());
        console2.log("Intended solver executor (config mapping):", executor);
        console2.log("mGLOBAL account:", ILiquidLaneAdapter(adapter).accounts(MGLOBAL));
        console2.log("mGLOBAL limit:", ILiquidLaneAdapter(adapter).limit(MGLOBAL));
        console2.log("mGLOBAL minDiscount:", ILiquidLaneAdapter(adapter).minDiscount(MGLOBAL));
        console2.log("VaultTotalAssets:", IERC4626(vault).totalAssets());
        console2.log("AdapterAbsoluteLimit:", IUniversalDelegator(delegator).absoluteLimitOf(adapter));
    }
}
