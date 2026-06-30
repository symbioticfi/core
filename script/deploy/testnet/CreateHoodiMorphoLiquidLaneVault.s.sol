// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {IAdapter} from "src/interfaces/adapters/IAdapter.sol";
import {IAdapterRegistry} from "src/interfaces/IAdapterRegistry.sol";
import {ILiquidLaneAdapter} from "src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {IMorphoVaultV2Adapter} from "src/interfaces/adapters/IMorphoVaultV2Adapter.sol";
import {IMigratablesFactory} from "src/interfaces/common/IMigratablesFactory.sol";
import {IUniversalDelegator, MAX_SHARE} from "src/interfaces/delegator/IUniversalDelegator.sol";
import {IVaultV2, VAULT_V2_VERSION} from "src/interfaces/vault/IVaultV2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface ITestnetERC20Mintable {
    function mint(address to, uint256 amount) external;
}

contract CreateHoodiMorphoLiquidLaneVault is Script {
    address internal constant OWNER = 0xc056736be7C05790667CDb678c03eb09F616E157;

    address internal constant VAULT_FACTORY = 0x600Fcd6256DDaB8C649d599fC5b8031bD5F912DA;
    address internal constant ADAPTER_REGISTRY = 0x32b7a1Cbd387aC9aC7f3fb06F889575924a2F988;
    address internal constant LIQUID_LANE_ADAPTER_FACTORY = 0x7Ce3f158f22aC66F8Ed2973B7a10F666818301C5;
    address internal constant MORPHO_ADAPTER_FACTORY = 0x747da25AC316bF3829351f08b6e1dFD1C290CaCa;

    address internal constant USDC = 0x9B97F7eDAbd9Ef43cAcE2eaFDD1DE5721aE3Bdd3;
    address internal constant MFONE = 0xA684911e92b8E4Dd27046331B849Bbd6dbca0fA2;
    address internal constant MGLOBAL = 0x2Ee6f1A395Bce7a7c5bF1D07bAaF9F8A0828A8d3;
    address internal constant MORPHO_USDC_VAULT = 0xAfe11A1e8009d3c0bD66E80cbf89A3c850b84A1c;

    uint256 internal constant DEPOSIT_LIMIT = 10_000_000e6;
    uint256 internal constant DEPOSIT_AMOUNT = 8_000_000e6;
    uint256 internal constant LIQUID_LANE_LIMIT = 5_000_000e6;
    uint256 internal constant TOKEN_LIMIT = 2_000_000e6;
    uint256 internal constant LIQUID_LANE_SHARE_LIMIT = MAX_SHARE * 75 / 100;
    uint256 internal constant MFONE_DISCOUNT = 8_000;
    uint256 internal constant MGLOBAL_DISCOUNT = 15_000;

    struct DeploymentData {
        address vault;
        address delegator;
        address morphoAdapter;
        address liquidLaneAdapter;
        address mFoneAccount;
        address mGlobalAccount;
    }

    function run() external returns (DeploymentData memory data) {
        vm.startBroadcast();
        data = _deploy();
        vm.stopBroadcast();

        _validate(data);
        _log(data);
    }

    function _deploy() internal returns (DeploymentData memory data) {
        data.vault = IMigratablesFactory(VAULT_FACTORY).create(VAULT_V2_VERSION, OWNER, _vaultParams());
        data.delegator = IVaultV2(data.vault).delegator();

        data.morphoAdapter = _createMorphoAdapter(data.vault);
        data.liquidLaneAdapter = _createLiquidLaneAdapter(data.vault);

        IAdapterRegistry(ADAPTER_REGISTRY).setWhitelistedStatus(data.vault, data.morphoAdapter, true);
        IAdapterRegistry(ADAPTER_REGISTRY).setWhitelistedStatus(data.vault, data.liquidLaneAdapter, true);

        IUniversalDelegator(data.delegator).addAdapter(data.morphoAdapter);
        IUniversalDelegator(data.delegator).addAdapter(data.liquidLaneAdapter);
        IUniversalDelegator(data.delegator).setLimits(data.morphoAdapter, type(uint256).max, MAX_SHARE);
        IUniversalDelegator(data.delegator).setLimits(data.liquidLaneAdapter, LIQUID_LANE_LIMIT, LIQUID_LANE_SHARE_LIMIT);

        ILiquidLaneAdapter(data.liquidLaneAdapter).addTokenToRedeem(MFONE);
        ILiquidLaneAdapter(data.liquidLaneAdapter).addTokenToRedeem(MGLOBAL);
        ILiquidLaneAdapter(data.liquidLaneAdapter).setLimit(MFONE, TOKEN_LIMIT);
        ILiquidLaneAdapter(data.liquidLaneAdapter).setLimit(MGLOBAL, TOKEN_LIMIT);
        ILiquidLaneAdapter(data.liquidLaneAdapter).setMinDiscount(MFONE, MFONE_DISCOUNT);
        ILiquidLaneAdapter(data.liquidLaneAdapter).setMinDiscount(MGLOBAL, MGLOBAL_DISCOUNT);
        ILiquidLaneAdapter(data.liquidLaneAdapter).setMarketMaker(OWNER, true);

        address[] memory autoAllocateAdapters = new address[](1);
        autoAllocateAdapters[0] = data.morphoAdapter;
        IUniversalDelegator(data.delegator).setAutoAllocateAdapters(autoAllocateAdapters);

        ITestnetERC20Mintable(USDC).mint(OWNER, DEPOSIT_AMOUNT);
        IERC20(USDC).approve(data.vault, DEPOSIT_AMOUNT);
        IERC4626(data.vault).deposit(DEPOSIT_AMOUNT, OWNER);

        data.mFoneAccount = ILiquidLaneAdapter(data.liquidLaneAdapter).accounts(MFONE);
        data.mGlobalAccount = ILiquidLaneAdapter(data.liquidLaneAdapter).accounts(MGLOBAL);
    }

    function _createMorphoAdapter(address vault) internal returns (address) {
        address[] memory converters = new address[](0);
        return IMigratablesFactory(MORPHO_ADAPTER_FACTORY).create(
            IMigratablesFactory(MORPHO_ADAPTER_FACTORY).lastVersion(),
            OWNER,
            abi.encode(
                vault,
                abi.encode(IMorphoVaultV2Adapter.InitParams({morphoVault: MORPHO_USDC_VAULT, converters: converters}))
            )
        );
    }

    function _createLiquidLaneAdapter(address vault) internal returns (address) {
        return IMigratablesFactory(LIQUID_LANE_ADAPTER_FACTORY).create(
            IMigratablesFactory(LIQUID_LANE_ADAPTER_FACTORY).lastVersion(),
            OWNER,
            abi.encode(vault, abi.encode(ILiquidLaneAdapter.InitParams({pauser: OWNER, unpauser: OWNER})))
        );
    }

    function _vaultParams() internal pure returns (bytes memory) {
        return abi.encode(
            IVaultV2.InitParams({
                name: "Hoodi USDC Morpho LiquidLane Vault",
                symbol: "hUSDC-MLL",
                asset: USDC,
                depositWhitelist: false,
                depositorToWhitelist: address(0),
                depositLimit: DEPOSIT_LIMIT,
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

    function _validate(DeploymentData memory data) internal view {
        assert(IERC4626(data.vault).asset() == USDC);
        assert(IVaultV2(data.vault).depositLimit() == DEPOSIT_LIMIT);
        assert(IVaultV2(data.vault).isDepositLimit());
        assert(IVaultV2(data.vault).delegator() == data.delegator);
        assert(IAdapterRegistry(ADAPTER_REGISTRY).isWhitelisted(data.vault, data.morphoAdapter));
        assert(IAdapterRegistry(ADAPTER_REGISTRY).isWhitelisted(data.vault, data.liquidLaneAdapter));
        assert(IUniversalDelegator(data.delegator).getAdaptersLength() == 2);
        assert(IUniversalDelegator(data.delegator).adapters(0) == data.morphoAdapter);
        assert(IUniversalDelegator(data.delegator).adapters(1) == data.liquidLaneAdapter);
        assert(IUniversalDelegator(data.delegator).autoAllocateAdapters(0) == data.morphoAdapter);
        assert(IUniversalDelegator(data.delegator).absoluteLimitOf(data.morphoAdapter) == type(uint256).max);
        assert(IUniversalDelegator(data.delegator).shareLimitOf(data.morphoAdapter) == MAX_SHARE);
        assert(IUniversalDelegator(data.delegator).absoluteLimitOf(data.liquidLaneAdapter) == LIQUID_LANE_LIMIT);
        assert(IUniversalDelegator(data.delegator).shareLimitOf(data.liquidLaneAdapter) == LIQUID_LANE_SHARE_LIMIT);
        assert(IMorphoVaultV2Adapter(data.morphoAdapter).morphoVault() == MORPHO_USDC_VAULT);
        assert(ILiquidLaneAdapter(data.liquidLaneAdapter).limit(MFONE) == TOKEN_LIMIT);
        assert(ILiquidLaneAdapter(data.liquidLaneAdapter).limit(MGLOBAL) == TOKEN_LIMIT);
        assert(ILiquidLaneAdapter(data.liquidLaneAdapter).minDiscount(MFONE) == MFONE_DISCOUNT);
        assert(ILiquidLaneAdapter(data.liquidLaneAdapter).minDiscount(MGLOBAL) == MGLOBAL_DISCOUNT);
        assert(ILiquidLaneAdapter(data.liquidLaneAdapter).marketMaker() == OWNER);
        assert(data.mFoneAccount != address(0));
        assert(data.mGlobalAccount != address(0));
        assert(_almostEq(IERC4626(data.vault).totalAssets(), DEPOSIT_AMOUNT, 1));
        assert(_almostEq(IAdapter(data.morphoAdapter).totalAssets(), DEPOSIT_AMOUNT, 1));
    }

    function _almostEq(uint256 actual, uint256 expected, uint256 maxDelta) internal pure returns (bool) {
        return actual > expected ? actual - expected <= maxDelta : expected - actual <= maxDelta;
    }

    function _log(DeploymentData memory data) internal view {
        console2.log("Vault:", data.vault);
        console2.log("Delegator:", data.delegator);
        console2.log("Morpho adapter:", data.morphoAdapter);
        console2.log("LiquidLane adapter:", data.liquidLaneAdapter);
        console2.log("mF-ONE account:", data.mFoneAccount);
        console2.log("mGLOBAL account:", data.mGlobalAccount);
        console2.log("USDC:", USDC);
        console2.log("mF-ONE:", MFONE);
        console2.log("mGLOBAL:", MGLOBAL);
        console2.log("Morpho USDC vault:", MORPHO_USDC_VAULT);
        console2.log("Deposit limit:", IVaultV2(data.vault).depositLimit());
        console2.log("Deposited assets:", IERC4626(data.vault).totalAssets());
        console2.log("Vault free assets:", IVaultV2(data.vault).freeAssets());
        console2.log("Delegator total assets:", IUniversalDelegator(data.delegator).totalAssets());
        console2.log("Morpho adapter assets:", IAdapter(data.morphoAdapter).totalAssets());
        console2.log("LiquidLane adapter limit:", IUniversalDelegator(data.delegator).absoluteLimitOf(data.liquidLaneAdapter));
        console2.log("LiquidLane relative limit:", IUniversalDelegator(data.delegator).shareLimitOf(data.liquidLaneAdapter));
        console2.log("mF-ONE token limit:", ILiquidLaneAdapter(data.liquidLaneAdapter).limit(MFONE));
        console2.log("mGLOBAL token limit:", ILiquidLaneAdapter(data.liquidLaneAdapter).limit(MGLOBAL));
        console2.log("mF-ONE discount ppm:", ILiquidLaneAdapter(data.liquidLaneAdapter).minDiscount(MFONE));
        console2.log("mGLOBAL discount ppm:", ILiquidLaneAdapter(data.liquidLaneAdapter).minDiscount(MGLOBAL));
    }
}
