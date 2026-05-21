// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {VaultFactory} from "../../src/contracts/VaultFactory.sol";
import {DelegatorFactory} from "../../src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "../../src/contracts/SlasherFactory.sol";
import {NetworkRegistry} from "../../src/contracts/NetworkRegistry.sol";
import {OperatorRegistry} from "../../src/contracts/OperatorRegistry.sol";
import {AdapterRegistry} from "../../src/contracts/AdapterRegistry.sol";
import {VaultConfigurator} from "../../src/contracts/VaultConfigurator.sol";
import {NetworkMiddlewareService} from "../../src/contracts/service/NetworkMiddlewareService.sol";
import {OptInService} from "../../src/contracts/service/OptInService.sol";
import {NetworkRestakeDelegator} from "../../src/contracts/delegator/NetworkRestakeDelegator.sol";
import {FullRestakeDelegator} from "../../src/contracts/delegator/FullRestakeDelegator.sol";
import {OperatorSpecificDelegator} from "../../src/contracts/delegator/OperatorSpecificDelegator.sol";
import {OperatorNetworkSpecificDelegator} from "../../src/contracts/delegator/OperatorNetworkSpecificDelegator.sol";
import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";
import {Slasher} from "../../src/contracts/slasher/Slasher.sol";
import {VetoSlasher} from "../../src/contracts/slasher/VetoSlasher.sol";
import {UniversalSlasher} from "../../src/contracts/slasher/UniversalSlasher.sol";
import {Vault as VaultV1} from "../../src/contracts/vault/Vault.sol";
import {VaultTokenized} from "../../src/contracts/vault/VaultTokenized.sol";
import {VaultV2} from "../../src/contracts/vault/VaultV2.sol";
import {VaultV2Migrate} from "../../src/contracts/vault/VaultV2Migrate.sol";
import {AaveV3Adapter, AaveV3Account} from "../../src/contracts/adapters/AaveV3Adapter.sol";
import {MorphoVaultV2Adapter, MorphoVaultV2Account} from "../../src/contracts/adapters/MorphoVaultV2Adapter.sol";

import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";
import {IAdapter} from "../../src/interfaces/adapters/IAdapter.sol";
import {IVaultV2, DEALLOCATE_ADAPTER_ROLE} from "../../src/interfaces/vault/IVaultV2.sol";
import {IRewards} from "../../src/interfaces/vault/IRewards.sol";
import {IAaveV3Pool} from "../../src/interfaces/adapters/aave_v3_adapter/IAaveV3AdapterDependencies.sol";
import {IMorphoVaultV2Factory} from "../../src/interfaces/adapters/morpho_vaultv2_adapter/IMorphoVaultV2Factory.sol";
import {IMorphoVaultV2} from "../../src/interfaces/adapters/morpho_vaultv2_adapter/IMorphoVaultV2.sol";
import {DEALLOCATE_BUFFER, IMorphoVaultV2Adapter} from "../../src/interfaces/adapters/IMorphoVaultV2Adapter.sol";
import {IUniversalDelegator} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IUniversalSlasher} from "../../src/interfaces/slasher/IUniversalSlasher.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {MockFeeRegistry} from "../mocks/MockFeeRegistry.sol";

contract MainnetCuratorRegistryHarness {
    mapping(address vault => address curator) public curators;

    function setCurator(address vault, address curator) external {
        curators[vault] = curator;
    }

    function getCurator(address vault) external view returns (address) {
        return curators[vault];
    }
}

contract MainnetDonationRewardsHarness is ReentrancyGuard, IRewards {
    using SafeERC20 for IERC20;

    function distributeDonationRewards(address vault, uint256 amount) external nonReentrant {
        IERC20 collateral = IERC20(IVaultV2(vault).collateral());
        collateral.safeTransferFrom(msg.sender, address(this), amount);
        collateral.forceApprove(vault, amount);
        VaultV2(vault).donate(amount);
    }
}

contract VaultV2MainnetAdaptersForkTest is Test {
    using SafeERC20 for IERC20;

    uint256 internal constant MAINNET_FORK_BLOCK = 24_916_218;

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address internal constant MORPHO_VAULT_FACTORY = 0xA1D94F746dEfa1928926b84fB2596c06926C0405;
    address internal constant MORPHO_ADAPTER_REGISTRY = 0x3696c5eAe4a7Ffd04Ea163564571E9CD8Ed9364e;
    address internal constant MORPHO_GAUNTLET_USDC_PRIME = 0x8c106EEDAd96553e64287A5A6839c3Cc78afA3D0;
    address internal constant MORPHO_KEYROCK_USDC = 0x04422053aDDbc9bB2759b248B574e3FCA76Bc145;
    address internal constant MORPHO_CLEARSTAR_USDC_CORE = 0x69A238Ae7ebeb3c53ff3B544E48B96a2142fc284;
    address internal constant MORPHO_ALPHA_USDC_CORE = 0xf1CA44EEa3A4eFFcB195A970a2f1d8553f76F9A1;
    address internal constant MORPHO_KPK_USDC_YIELD = 0xD5cCe260E7a755DDf0Fb9cdF06443d593AaeaA13;
    address internal constant MORPHO_ALPHA_USDC_ASIA = 0x35Cbe8542E70fa2f7F9cDF129F19e593F4b4f560;
    address internal constant MORPHO_ALPHA_USDC_FOREX = 0x153Bd1abE60104Bd46aa05a27fA12D1346D64A57;
    address internal constant MORPHO_ETHEREALM_USDC = 0xB7305D968ECD8a23a13eC01927E3f9588C7653B5;
    address internal constant MORPHO_GAUNTLET_WETH_PRIME = 0x43fCd85E8D9D003D515f886891B7C742AC9f92da;

    uint256 internal constant DEPOSIT_AMOUNT = 1000e6;
    uint256 internal constant ALLOCATE_AMOUNT = 750e6;
    uint256 internal constant YIELD_AMOUNT = 25e6;
    uint256 internal constant DEALLOCATE_AMOUNT = 100e6;

    address internal alice;
    address internal curator;

    VaultFactory internal vaultFactory;
    DelegatorFactory internal delegatorFactory;
    SlasherFactory internal slasherFactory;
    NetworkRegistry internal networkRegistry;
    OperatorRegistry internal operatorRegistry;
    NetworkMiddlewareService internal networkMiddlewareService;
    OptInService internal operatorVaultOptInService;
    OptInService internal operatorNetworkOptInService;
    MockFeeRegistry internal feeRegistry;
    AdapterRegistry internal adapterRegistry;
    VaultConfigurator internal vaultConfigurator;
    MainnetCuratorRegistryHarness internal curatorRegistry;
    MainnetDonationRewardsHarness internal rewards;

    IVaultV2 internal aaveVault;
    IVaultV2 internal morphoVault;
    AaveV3Adapter internal aaveAdapter;
    MorphoVaultV2Adapter internal morphoAdapter;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), MAINNET_FORK_BLOCK);

        alice = makeAddr("alice");
        curator = makeAddr("curator");

        vaultFactory = new VaultFactory(address(this));
        delegatorFactory = new DelegatorFactory(address(this));
        slasherFactory = new SlasherFactory(address(this));
        networkRegistry = new NetworkRegistry();
        operatorRegistry = new OperatorRegistry();
        networkMiddlewareService = new NetworkMiddlewareService(address(networkRegistry));
        operatorVaultOptInService =
            new OptInService(address(operatorRegistry), address(vaultFactory), "OperatorVaultOptInService");
        operatorNetworkOptInService =
            new OptInService(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService");
        feeRegistry = new MockFeeRegistry();
        adapterRegistry = new AdapterRegistry(address(this));
        vaultConfigurator =
            new VaultConfigurator(address(vaultFactory), address(delegatorFactory), address(slasherFactory));
        curatorRegistry = new MainnetCuratorRegistryHarness();
        rewards = new MainnetDonationRewardsHarness();

        _whitelistCoreImplementations();

        aaveVault = _createVault(USDC);
        morphoVault = _createVault(USDC);

        aaveAdapter = _deployAaveAdapter();
        aaveAdapter.initialize();
        aaveAdapter.setGlobalLimit(USDC, type(uint256).max);

        morphoAdapter = _deployMorphoAdapter();
        morphoAdapter.initialize();
        morphoAdapter.setGlobalLimit(USDC, type(uint256).max);
        morphoAdapter.setGlobalLimit(WETH, type(uint256).max);

        adapterRegistry.whitelistAdapter(address(aaveAdapter));
        adapterRegistry.whitelistAdapter(address(morphoAdapter));

        curatorRegistry.setCurator(address(aaveVault), curator);
        curatorRegistry.setCurator(address(morphoVault), curator);
        vm.prank(curator);
        morphoAdapter.setMorphoVault(address(morphoVault), MORPHO_GAUNTLET_USDC_PRIME);
    }






    function testFork_Mainnet_AdapterRejectsNonCurator() public {
        vm.expectRevert(IAdapter.NotCurator.selector);
        morphoAdapter.setMorphoVault(address(morphoVault), MORPHO_GAUNTLET_USDC_PRIME);
    }

    function testFork_Mainnet_AdapterRecoverRejectsNonCurator() public {
        vm.expectRevert(IAdapter.NotCurator.selector);
        aaveAdapter.recover(address(aaveVault), 1);
    }

    function testFork_Mainnet_AdapterMulticallBubblesRevertReason() public {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(IAdapter.setGlobalLimit, (USDC, 1));

        vm.prank(alice);
        vm.expectRevert();
        aaveAdapter.multicall(data);
    }

    function testFork_Mainnet_AdapterRecoverRejectsZeroAmount() public {
        vm.prank(curator);
        vm.expectRevert(IAdapter.ZeroAmount.selector);
        aaveAdapter.recover(address(aaveVault), 0);
    }

    function testFork_Mainnet_AdapterRecoverReturnsFundsToVaultAndReducesAllocation() public {
        _fundAndDeposit(aaveVault, DEPOSIT_AMOUNT);
        _prepareAdapter(aaveVault, address(aaveAdapter), type(uint208).max);

        vm.prank(alice);
        aaveVault.allocateAdapter(address(aaveAdapter), ALLOCATE_AMOUNT);

        _fundUsdc(curator, DEALLOCATE_AMOUNT);

        vm.startPrank(curator);
        IERC20(USDC).forceApprove(address(aaveAdapter), DEALLOCATE_AMOUNT);
        aaveAdapter.recover(address(aaveVault), DEALLOCATE_AMOUNT);
        vm.stopPrank();

        assertEq(aaveVault.adapterAllocated(address(aaveAdapter)), ALLOCATE_AMOUNT - DEALLOCATE_AMOUNT);
        assertEq(aaveAdapter.globalAllocated(USDC), ALLOCATE_AMOUNT - DEALLOCATE_AMOUNT);
        assertApproxEqAbs(
            IERC20(USDC).balanceOf(address(aaveVault)), DEPOSIT_AMOUNT - ALLOCATE_AMOUNT + DEALLOCATE_AMOUNT * 2, 10
        );
    }

    function testFork_Mainnet_AaveUnsupportedReserveReturnsZeroCapacityAndAssets() public {
        IVaultV2 unsupportedVault = _createVault(makeAddr("unsupportedCollateral"));

        assertEq(aaveAdapter.allocatable(address(unsupportedVault)), 0);
        assertEq(aaveAdapter.deallocatable(address(unsupportedVault)), 0);
        assertEq(aaveAdapter.totalAssets(address(unsupportedVault)), 0);
    }

    function testFork_Mainnet_AaveDeallocateZeroAndZeroCapacityReturnZero() public {
        vm.prank(address(aaveVault));
        assertEq(aaveAdapter.deallocate(0), 0);

        vm.prank(address(aaveVault));
        assertEq(aaveAdapter.deallocate(1), 0);
    }


    function testFork_Mainnet_AaveAccountRejectsNonAdapterWithdraw() public {
        _fundAndDeposit(aaveVault, DEPOSIT_AMOUNT);
        _prepareAdapter(aaveVault, address(aaveAdapter), type(uint208).max);

        vm.prank(alice);
        aaveVault.allocateAdapter(address(aaveAdapter), ALLOCATE_AMOUNT);

        vm.prank(address(aaveVault));
        aaveAdapter.deallocate(1);

        address aaveAccount = aaveAdapter.getAccount(address(aaveVault));
        assertGt(aaveAccount.code.length, 0);

        vm.expectRevert(AaveV3Account.NotAdapter.selector);
        AaveV3Account(aaveAccount).withdraw(USDC, 1);
    }

    function testFork_Mainnet_MorphoUnconfiguredVaultReturnsZeroCapacityAndAssets() public {
        assertEq(morphoAdapter.allocatable(address(aaveVault)), 0);
        assertEq(morphoAdapter.deallocatable(address(aaveVault)), 0);
        assertEq(morphoAdapter.totalAssets(address(aaveVault)), 0);
    }

    function testFork_Mainnet_MorphoLiveUsdcVaultsPassFactoryAndAdapterValidation() public {
        address[8] memory morphoVaults = _liveMorphoUsdcVaults();

        for (uint256 i; i < morphoVaults.length; ++i) {
            address liveMorphoVault = morphoVaults[i];
            IVaultV2 vault_ = _createVault(USDC);
            curatorRegistry.setCurator(address(vault_), curator);

            _assertLiveMorphoVault(liveMorphoVault, USDC);

            vm.prank(curator);
            morphoAdapter.setMorphoVault(address(vault_), liveMorphoVault);

            assertEq(morphoAdapter.morphoVaults(address(vault_)), liveMorphoVault);
        }
    }

    function testFork_Mainnet_MorphoAllocatesAndDeallocatesAcrossLiveUsdcVaults() public {
        address[3] memory liveMorphoVaults = [MORPHO_KEYROCK_USDC, MORPHO_CLEARSTAR_USDC_CORE, MORPHO_ALPHA_USDC_ASIA];

        for (uint256 i; i < liveMorphoVaults.length; ++i) {
            IVaultV2 vault_ = _createVault(USDC);
            curatorRegistry.setCurator(address(vault_), curator);

            vm.prank(curator);
            morphoAdapter.setMorphoVault(address(vault_), liveMorphoVaults[i]);

            _fundAndDeposit(vault_, 10e6);
            _prepareAdapter(vault_, address(morphoAdapter), type(uint208).max);

            vm.prank(alice);
            uint256 allocated = vault_.allocateAdapter(address(morphoAdapter), 2e6);
            assertEq(allocated, 2e6);
            assertEq(vault_.adapterAllocated(address(morphoAdapter)), 2e6);
            assertGt(IMorphoVaultV2(liveMorphoVaults[i]).balanceOf(morphoAdapter.getAccount(address(vault_))), 0);

            vm.prank(alice);
            uint256 deallocated = vault_.deallocateAdapter(address(morphoAdapter), 1e6);
            assertEq(deallocated, 1e6);
            assertEq(vault_.adapterAllocated(address(morphoAdapter)), 1e6);
        }
    }

    function testFork_Mainnet_MorphoForceDeallocateRejectsZeroAmount() public {
        vm.prank(curator);
        vm.expectRevert(IMorphoVaultV2Adapter.InsufficientAmount.selector);
        morphoAdapter.forceDeallocate(address(morphoVault), 0);
    }

    function testFork_Mainnet_MorphoSetVaultRejectsInvalidVault() public {
        vm.prank(curator);
        vm.expectRevert(IMorphoVaultV2Adapter.InvalidMorphoVault.selector);
        morphoAdapter.setMorphoVault(address(morphoVault), USDC);
    }

    function testFork_Mainnet_MorphoSetVaultRejectsWrongAssetLiveVault() public {
        _assertLiveMorphoVault(MORPHO_GAUNTLET_WETH_PRIME, WETH);

        vm.prank(curator);
        vm.expectRevert(IMorphoVaultV2Adapter.InvalidMorphoVault.selector);
        morphoAdapter.setMorphoVault(address(morphoVault), MORPHO_GAUNTLET_WETH_PRIME);
    }

    function testFork_Mainnet_MorphoSetVaultRejectsActivePosition() public {
        _fundAndDeposit(morphoVault, DEPOSIT_AMOUNT);
        _prepareAdapter(morphoVault, address(morphoAdapter), type(uint208).max);

        vm.prank(alice);
        morphoVault.allocateAdapter(address(morphoAdapter), ALLOCATE_AMOUNT);

        vm.prank(curator);
        vm.expectRevert(IMorphoVaultV2Adapter.ActivePosition.selector);
        morphoAdapter.setMorphoVault(address(morphoVault), address(0));
    }

    function testFork_Mainnet_MorphoNormalDeallocationIsBlockedWhenLossExceedsBuffer() public {
        _fundAndDeposit(morphoVault, DEPOSIT_AMOUNT);
        _prepareAdapter(morphoVault, address(morphoAdapter), type(uint208).max);

        vm.prank(alice);
        morphoVault.allocateAdapter(address(morphoAdapter), ALLOCATE_AMOUNT);

        address morphoAccount = morphoAdapter.getAccount(address(morphoVault));
        deal(MORPHO_GAUNTLET_USDC_PRIME, morphoAccount, 0);

        assertEq(morphoAdapter.totalAssets(address(morphoVault)), 0);
        assertGt(morphoVault.adapterAllocated(address(morphoAdapter)), DEALLOCATE_BUFFER);
        assertEq(morphoAdapter.deallocatable(address(morphoVault)), 0);
    }


    function testFork_Mainnet_MorphoDepositRejectsNonSelfCall() public {
        address morphoAccount = morphoAdapter.getAccount(address(morphoVault));

        vm.expectRevert(IMorphoVaultV2Adapter.NotSelf.selector);
        morphoAdapter.deposit(MORPHO_GAUNTLET_USDC_PRIME, 1, morphoAccount);
    }

    function testFork_Mainnet_MorphoAllocateRecoversWhenLiveWethVaultMintsZeroShares() public {
        IVaultV2 wethVault = _createVault(WETH);
        curatorRegistry.setCurator(address(wethVault), curator);

        vm.prank(curator);
        morphoAdapter.setMorphoVault(address(wethVault), MORPHO_GAUNTLET_WETH_PRIME);

        _fundAndDeposit(wethVault, 1);
        _prepareAdapter(wethVault, address(morphoAdapter), type(uint208).max);

        assertEq(IMorphoVaultV2(MORPHO_GAUNTLET_WETH_PRIME).previewDeposit(1), 0);

        address morphoAccount = morphoAdapter.getAccount(address(wethVault));
        vm.prank(alice);
        wethVault.allocateAdapter(address(morphoAdapter), 1);

        assertEq(wethVault.adapterAllocated(address(morphoAdapter)), 0);
        assertEq(morphoAdapter.globalAllocated(WETH), 0);
        assertEq(IERC20(WETH).balanceOf(address(wethVault)), 1);
        assertEq(IMorphoVaultV2(MORPHO_GAUNTLET_WETH_PRIME).balanceOf(morphoAccount), 0);
    }

    function testFork_Mainnet_MorphoDeallocateZeroAndZeroCapacityReturnZero() public {
        vm.prank(address(morphoVault));
        assertEq(morphoAdapter.deallocate(0), 0);

        vm.prank(address(morphoVault));
        assertEq(morphoAdapter.deallocate(1), 0);
    }

    function testFork_Mainnet_MorphoAccountRejectsNonAdapterWithdraw() public {
        _fundAndDeposit(morphoVault, DEPOSIT_AMOUNT);
        _prepareAdapter(morphoVault, address(morphoAdapter), type(uint208).max);

        vm.prank(alice);
        morphoVault.allocateAdapter(address(morphoAdapter), ALLOCATE_AMOUNT);

        vm.prank(address(morphoVault));
        morphoAdapter.deallocate(1);

        address morphoAccount = morphoAdapter.getAccount(address(morphoVault));
        assertGt(morphoAccount.code.length, 0);

        vm.expectRevert(MorphoVaultV2Account.NotAdapter.selector);
        MorphoVaultV2Account(morphoAccount).withdraw(MORPHO_GAUNTLET_USDC_PRIME, 1);
    }



    function _donateAaveYield(uint256 yieldAmount) internal {
        address aaveAccount = aaveAdapter.getAccount(address(aaveVault));
        _fundUsdc(address(this), yieldAmount);
        IERC20(USDC).forceApprove(AAVE_POOL, yieldAmount);
        IAaveV3Pool(AAVE_POOL).supply(USDC, yieldAmount, aaveAccount, 0);
    }

    function _donateMorphoYield(uint256 yieldAmount) internal {
        address morphoAccount = morphoAdapter.getAccount(address(morphoVault));
        _fundUsdc(address(this), yieldAmount);
        IERC20(USDC).forceApprove(MORPHO_GAUNTLET_USDC_PRIME, yieldAmount);
        IMorphoVaultV2(MORPHO_GAUNTLET_USDC_PRIME).deposit(yieldAmount, morphoAccount);
    }

    function _fundAndDeposit(IVaultV2 vault_, uint256 amount) internal {
        address collateral = vault_.collateral();
        _fundToken(collateral, address(this), amount);
        IERC20(collateral).forceApprove(address(vault_), amount);
        vault_.deposit(address(this), amount);
    }

    function _liveMorphoUsdcVaults() internal pure returns (address[8] memory vaults) {
        vaults = [
            MORPHO_GAUNTLET_USDC_PRIME,
            MORPHO_KEYROCK_USDC,
            MORPHO_CLEARSTAR_USDC_CORE,
            MORPHO_ALPHA_USDC_CORE,
            MORPHO_KPK_USDC_YIELD,
            MORPHO_ALPHA_USDC_ASIA,
            MORPHO_ALPHA_USDC_FOREX,
            MORPHO_ETHEREALM_USDC
        ];
    }

    function _assertLiveMorphoVault(address liveMorphoVault, address asset) internal view {
        assertTrue(IMorphoVaultV2Factory(MORPHO_VAULT_FACTORY).isVaultV2(liveMorphoVault));
        assertEq(IMorphoVaultV2(liveMorphoVault).asset(), asset);
        assertEq(IMorphoVaultV2(liveMorphoVault).adapterRegistry(), MORPHO_ADAPTER_REGISTRY);
        assertTrue(IMorphoVaultV2(liveMorphoVault).abdicated(IMorphoVaultV2.setAdapterRegistry.selector));
        assertGt(IMorphoVaultV2(liveMorphoVault).totalSupply(), 0);
    }

    function _deployAaveAdapter() internal returns (AaveV3Adapter adapter) {
        uint256 nonce = vm.getNonce(address(this));
        address predictedAdapter = vm.computeCreateAddress(address(this), nonce + 2);
        UpgradeableBeacon accountBeacon =
            new UpgradeableBeacon(address(new AaveV3Account(AAVE_POOL, predictedAdapter)), address(this));
        address beacon = address(accountBeacon);

        adapter =
            new AaveV3Adapter(AAVE_POOL, address(curatorRegistry), address(rewards), address(vaultFactory), beacon);
        accountBeacon.renounceOwnership();
    }

    function _deployMorphoAdapter() internal returns (MorphoVaultV2Adapter adapter) {
        uint256 nonce = vm.getNonce(address(this));
        address predictedAdapter = vm.computeCreateAddress(address(this), nonce + 2);
        UpgradeableBeacon accountBeacon =
            new UpgradeableBeacon(address(new MorphoVaultV2Account(predictedAdapter)), address(this));
        address beacon = address(accountBeacon);

        adapter = new MorphoVaultV2Adapter(
            MORPHO_VAULT_FACTORY,
            MORPHO_ADAPTER_REGISTRY,
            address(curatorRegistry),
            address(rewards),
            address(vaultFactory),
            beacon
        );
        accountBeacon.renounceOwnership();
    }

    function _prepareAdapter(IVaultV2 vault_, address adapter, uint208 limit) internal {
        vm.startPrank(alice);
        VaultV2(address(vault_)).setAdapterLimit(adapter, limit);
        if (VaultV2(address(vault_)).adapterLimit(adapter) == 0 && limit > 0) {
            vm.warp(VaultV2(address(vault_)).adapterAllowedAt(adapter));
            VaultV2(address(vault_)).setAdapterLimit(adapter, limit);
        }
        VaultV2(address(vault_)).grantRole(DEALLOCATE_ADAPTER_ROLE, alice);
        vm.stopPrank();
    }

    function _fundUsdc(address account, uint256 amount) internal {
        _fundToken(USDC, account, amount);
    }

    function _fundToken(address token, address account, uint256 amount) internal {
        deal(token, account, IERC20(token).balanceOf(account) + amount);
    }

    function _createVault(address collateral_) internal returns (IVaultV2 vault_) {
        uint48 epochDuration = 1 days;
        bytes memory vaultParams = abi.encode(
            IVaultV2.InitParams({
                name: "Test",
                symbol: "TEST",
                collateral: collateral_,
                burner: address(0xdEaD),
                epochDuration: epochDuration,
                adapters: new address[](0),
                adaptersAllowDelay: epochDuration + 1,
                depositWhitelist: false,
                depositorToWhitelist: address(0xBEEF),
                isDepositLimit: false,
                depositLimit: 0,
                defaultAdminRoleHolder: alice,
                depositWhitelistSetRoleHolder: alice,
                depositorWhitelistRoleHolder: alice,
                isDepositLimitSetRoleHolder: alice,
                depositLimitSetRoleHolder: alice,
                setAdapterLimitRoleHolder: alice,
                swapAdaptersRoleHolder: alice,
                allocateAdapterRoleHolder: alice,
                deallocateAdapterRoleHolder: alice
            })
        );
        bytes memory delegatorParams = abi.encode(
            IUniversalDelegator.InitParams({
                defaultAdminRoleHolder: alice,
                createSlotRoleHolder: alice,
                setSizeRoleHolder: alice,
                swapSlotsRoleHolder: alice,
                removeSlotRoleHolder: alice,
                setWithdrawalBufferSizeRoleHolder: alice,
                withdrawalBufferSize: 0
            })
        );
        bytes memory slasherParams = abi.encode(
            IUniversalSlasher.InitParams({
                isBurnerHook: false,
                vetoDuration: epochDuration > 1 ? 1 : 0,
                resolverSetDelay: uint48(epochDuration * 3)
            })
        );

        (address deployedVault,,) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: vaultFactory.lastVersion(),
                owner: address(0xdEaD),
                vaultParams: vaultParams,
                delegatorIndex: uint64(delegatorFactory.totalTypes() - 1),
                delegatorParams: delegatorParams,
                withSlasher: true,
                slasherIndex: uint64(slasherFactory.totalTypes() - 1),
                slasherParams: slasherParams
            })
        );

        vault_ = IVaultV2(deployedVault);
    }

    function _whitelistCoreImplementations() internal {
        vaultFactory.whitelist(
            address(new VaultV1(address(delegatorFactory), address(slasherFactory), address(vaultFactory)))
        );
        vaultFactory.whitelist(
            address(new VaultTokenized(address(delegatorFactory), address(slasherFactory), address(vaultFactory)))
        );
        vaultFactory.whitelist(
            address(
                new VaultV2(
                    address(delegatorFactory),
                    address(slasherFactory),
                    address(vaultFactory),
                    address(feeRegistry),
                    address(rewards),
                    address(adapterRegistry),
                    address(
                        new VaultV2Migrate(
                            address(delegatorFactory),
                            address(slasherFactory),
                            address(feeRegistry),
                            address(rewards),
                            address(adapterRegistry)
                        )
                    )
                )
            )
        );
        delegatorFactory.whitelist(
            address(
                new NetworkRestakeDelegator(
                    address(networkRegistry),
                    address(vaultFactory),
                    address(operatorVaultOptInService),
                    address(operatorNetworkOptInService),
                    address(delegatorFactory),
                    delegatorFactory.totalTypes()
                )
            )
        );
        delegatorFactory.whitelist(
            address(
                new FullRestakeDelegator(
                    address(networkRegistry),
                    address(vaultFactory),
                    address(operatorVaultOptInService),
                    address(operatorNetworkOptInService),
                    address(delegatorFactory),
                    delegatorFactory.totalTypes()
                )
            )
        );
        delegatorFactory.whitelist(
            address(
                new OperatorSpecificDelegator(
                    address(operatorRegistry),
                    address(networkRegistry),
                    address(vaultFactory),
                    address(operatorVaultOptInService),
                    address(operatorNetworkOptInService),
                    address(delegatorFactory),
                    delegatorFactory.totalTypes()
                )
            )
        );
        delegatorFactory.whitelist(
            address(
                new OperatorNetworkSpecificDelegator(
                    address(operatorRegistry),
                    address(networkRegistry),
                    address(vaultFactory),
                    address(operatorVaultOptInService),
                    address(operatorNetworkOptInService),
                    address(delegatorFactory),
                    delegatorFactory.totalTypes()
                )
            )
        );
        delegatorFactory.whitelist(
            address(
                new UniversalDelegator(
                    address(networkRegistry),
                    address(vaultFactory),
                    address(delegatorFactory),
                    delegatorFactory.totalTypes(),
                    address(networkMiddlewareService)
                )
            )
        );
        slasherFactory.whitelist(
            address(
                new Slasher(
                    address(vaultFactory),
                    address(networkMiddlewareService),
                    address(slasherFactory),
                    slasherFactory.totalTypes()
                )
            )
        );
        slasherFactory.whitelist(
            address(
                new VetoSlasher(
                    address(vaultFactory),
                    address(networkMiddlewareService),
                    address(networkRegistry),
                    address(slasherFactory),
                    slasherFactory.totalTypes()
                )
            )
        );
        slasherFactory.whitelist(
            address(
                new UniversalSlasher(
                    address(vaultFactory),
                    address(networkMiddlewareService),
                    address(networkRegistry),
                    address(slasherFactory),
                    slasherFactory.totalTypes()
                )
            )
        );
    }
}
