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
 * @title CreateSepoliaMGlobalSolverVaults
 * @notice Sepolia port of CreateHoodiMGlobalSolverVaults: deploys 3 dedicated USDC-asset LiquidLane
 *         vaults+adapters, one per solver executor, reusing the existing Sepolia
 *         AdapterFactory/AdapterRegistry/AccountRegistry/VaultFactory + Midas oracle/account/redemption
 *         infra (NO core/oracle redeploy). marketMaker = OWNER on every adapter (discount-signed fills
 *         authenticate via owner(), so no per-solver marketMaker/filler on-chain — each adapter is bound
 *         to its solver via the solver's `adapters` config + the discount posted on it). Each vault is
 *         seeded with USDC, whose withdrawable() balance is the fill capacity (getMaxAssets).
 *
 *      Run:  forge build   (NEVER --broadcast in this draft)
 */
contract CreateSepoliaMGlobalSolverVaults is Script {
    /* ---- Sepolia constants (all verified on-chain) ---- */

    // Deployer / owner EOA (every role holder + broadcasting key)
    address internal constant OWNER = 0xc056736be7C05790667CDb678c03eb09F616E157;

    // Canonical V2 VaultFactory (lastVersion == VAULT_V2_VERSION == 3)
    address internal constant VAULT_FACTORY = 0x93eB791C21C1d11111CE17b887C2e98f708A8468;

    // LiquidLane AdapterFactory (FACTORY() of the existing Sepolia USDC LL adapter 0x8F38656…)
    address internal constant ADAPTER_FACTORY = 0xE929Cf04D2A587817773E6B5cB9Bc8D01f909Faa;

    // AdapterRegistry (per-vault adapter whitelist; OWNER-gated)
    address internal constant ADAPTER_REGISTRY = 0x543982a2FdEACf117B94e01a8c566d4465f91B5A;

    // Tokens: USDC (vault asset, 6 dec, OWNER-mintable testnet token); mGLOBAL (token-to-redeem, 18 dec)
    address internal constant USDC = 0xc06ea690d3eC9a85E1e1603f366f13c50d80afD3;
    address internal constant MGLOBAL = 0xb547DCEcfC86FCC7B2964A4d9A2d5e8CFc407593;

    // Per-solver Sepolia executors (one per adapter; recorded for config mapping)
    address internal constant EXECUTOR_FIRST = 0xc2251516e23A2b8E01249f8e9084297EDd8559b7;
    address internal constant EXECUTOR_SECOND = 0xC879456C5Ce99d3a6B81797f40b0BF28143E1640;
    address internal constant EXECUTOR_THIRD = 0x92E04ea2a18c8E87EAf6803691772b15eBb939ED;

    /* ---- Tunables ---- */

    // mGLOBAL per-token vault-asset limit and delegator absolute limit: 2^128 - 1 (mirrors existing adapter)
    uint256 internal constant TOKEN_LIMIT = type(uint128).max;
    // mGLOBAL minimum discount in ppm (existing working adapter uses 0)
    uint256 internal constant MIN_DISCOUNT = 0;

    // Per-vault USDC seed (6 decimals). Minted to OWNER and deposited; becomes the vault's withdrawable()
    // balance, which IS the fill capacity (getMaxAssets caps maxCollateralOut to withdrawable()).
    uint256 internal constant DEPOSIT_AMOUNT = 100_000e6;

    function run() external {
        vm.startBroadcast();

        _deployOne("Sepolia mGLOBAL USDC Vault 1", "mGUSDC1", EXECUTOR_FIRST);
        _deployOne("Sepolia mGLOBAL USDC Vault 2", "mGUSDC2", EXECUTOR_SECOND);
        _deployOne("Sepolia mGLOBAL USDC Vault 3", "mGUSDC3", EXECUTOR_THIRD);

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
