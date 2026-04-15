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
import {AaveV3Adapter, AaveV3Account} from "../../src/contracts/vault/adapters/AaveV3Adapter.sol";
import {MorphoVaultV2Adapter, MorphoVaultV2Account} from "../../src/contracts/vault/adapters/MorphoVaultV2Adapter.sol";

import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";
import {IVaultV2, DEALLOCATE_ADAPTER_ROLE} from "../../src/interfaces/vault/IVaultV2.sol";
import {IRewards} from "../../src/interfaces/vault/IRewards.sol";
import {IAaveV3Pool} from "../../src/interfaces/vault/adapters/aave_v3_adapter/IAaveV3AdapterDependencies.sol";
import {IMorphoVaultV2} from "../../src/interfaces/vault/adapters/morpho_vaultv2_adapter/IMorphoVaultV2.sol";
import {IUniversalDelegator} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IUniversalSlasher} from "../../src/interfaces/slasher/IUniversalSlasher.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {MockFeeRegistry} from "../mocks/MockFeeRegistry.sol";

import {UpgradeableBeacon} from "@solady/src/utils/UpgradeableBeacon.sol";

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

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address internal constant MORPHO_VAULT_FACTORY = 0xA1D94F746dEfa1928926b84fB2596c06926C0405;
    address internal constant MORPHO_ADAPTER_REGISTRY = 0x3696c5eAe4a7Ffd04Ea163564571E9CD8Ed9364e;
    address internal constant MORPHO_GAUNTLET_USDC_PRIME = 0x8c106EEDAd96553e64287A5A6839c3Cc78afA3D0;

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
        vm.createSelectFork(vm.rpcUrl("mainnet"));

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

        adapterRegistry.whitelistAdapter(address(aaveAdapter));
        adapterRegistry.whitelistAdapter(address(morphoAdapter));

        curatorRegistry.setCurator(address(morphoVault), curator);
        vm.prank(curator);
        morphoAdapter.setMorphoVault(address(morphoVault), MORPHO_GAUNTLET_USDC_PRIME);
    }

    function testFork_Mainnet_AaveAdapter_RepeatedHealthyAllocateWithOutstandingYieldDoesNotRevert() public {
        _fundAndDeposit(aaveVault, DEPOSIT_AMOUNT);
        _prepareAdapter(aaveVault, address(aaveAdapter), type(uint208).max);

        vm.prank(alice);
        aaveVault.allocateAdapter(address(aaveAdapter), ALLOCATE_AMOUNT);

        _assertAaveHealthyReallocation(25e6, 50e6);
        _assertAaveHealthyReallocation(7e6, 25e6);
        _assertAaveHealthyReallocation(2e6, 10e6);
    }

    function testFork_Mainnet_MorphoAdapter_RepeatedHealthyAllocateWithOutstandingYieldDoesNotRevert() public {
        _fundAndDeposit(morphoVault, DEPOSIT_AMOUNT);
        _prepareAdapter(morphoVault, address(morphoAdapter), type(uint208).max);

        vm.prank(alice);
        morphoVault.allocateAdapter(address(morphoAdapter), ALLOCATE_AMOUNT);

        _assertMorphoHealthyReallocation(25e6, 50e6);
        _assertMorphoHealthyReallocation(7e6, 25e6);
        _assertMorphoHealthyReallocation(2e6, 10e6);
    }

    function testFork_Mainnet_AaveAdapter_Gas() public {
        _fundAndDeposit(aaveVault, DEPOSIT_AMOUNT);
        _prepareAdapter(aaveVault, address(aaveAdapter), type(uint208).max);

        vm.prank(alice);
        aaveVault.allocateAdapter(address(aaveAdapter), ALLOCATE_AMOUNT);
        uint256 allocateGas = vm.lastCallGas().gasTotalUsed;

        address aaveAccount = aaveAdapter.getAccount(address(aaveVault));
        _fundUsdc(address(this), YIELD_AMOUNT);
        IERC20(USDC).forceApprove(AAVE_POOL, YIELD_AMOUNT);
        IAaveV3Pool(AAVE_POOL).supply(USDC, YIELD_AMOUNT, aaveAccount, 0);

        uint256 skimmable = aaveAdapter.skimmable(address(aaveVault));
        assertGt(skimmable, 0);

        VaultV2(address(aaveVault)).skimAdapters();
        uint256 skimGas = vm.lastCallGas().gasTotalUsed;

        vm.prank(alice);
        aaveVault.deallocateAdapter(address(aaveAdapter), DEALLOCATE_AMOUNT);
        uint256 deallocateGas = vm.lastCallGas().gasTotalUsed;

        console2.log("Aave mainnet allocateAdapter gas", allocateGas);
        console2.log("Aave mainnet skimAdapters gas", skimGas);
        console2.log("Aave mainnet deallocateAdapter gas", deallocateGas);
        console2.log("Aave mainnet skimmable", skimmable);

        assertEq(aaveVault.adapterAllocated(address(aaveAdapter)), ALLOCATE_AMOUNT - DEALLOCATE_AMOUNT);
        assertEq(aaveVault.adaptersAllocated(), ALLOCATE_AMOUNT - DEALLOCATE_AMOUNT);
        assertGt(IERC20(USDC).balanceOf(address(aaveVault)), DEPOSIT_AMOUNT - ALLOCATE_AMOUNT);
    }

    function testFork_Mainnet_MorphoAdapter_Gas() public {
        _fundAndDeposit(morphoVault, DEPOSIT_AMOUNT);
        _prepareAdapter(morphoVault, address(morphoAdapter), type(uint208).max);

        vm.prank(alice);
        morphoVault.allocateAdapter(address(morphoAdapter), ALLOCATE_AMOUNT);
        uint256 allocateGas = vm.lastCallGas().gasTotalUsed;

        address morphoAccount = morphoAdapter.getAccount(address(morphoVault));
        _fundUsdc(address(this), YIELD_AMOUNT);
        IERC20(USDC).forceApprove(MORPHO_GAUNTLET_USDC_PRIME, YIELD_AMOUNT);
        IMorphoVaultV2(MORPHO_GAUNTLET_USDC_PRIME).deposit(YIELD_AMOUNT, morphoAccount);

        uint256 skimmable = morphoAdapter.skimmable(address(morphoVault));
        assertGt(skimmable, 0);

        VaultV2(address(morphoVault)).skimAdapters();
        uint256 skimGas = vm.lastCallGas().gasTotalUsed;

        vm.prank(alice);
        morphoVault.deallocateAdapter(address(morphoAdapter), DEALLOCATE_AMOUNT);
        uint256 deallocateGas = vm.lastCallGas().gasTotalUsed;

        console2.log("Morpho mainnet allocateAdapter gas", allocateGas);
        console2.log("Morpho mainnet skimAdapters gas", skimGas);
        console2.log("Morpho mainnet deallocateAdapter gas", deallocateGas);
        console2.log("Morpho mainnet skimmable", skimmable);

        assertEq(morphoVault.adapterAllocated(address(morphoAdapter)), ALLOCATE_AMOUNT - DEALLOCATE_AMOUNT);
        assertEq(morphoVault.adaptersAllocated(), ALLOCATE_AMOUNT - DEALLOCATE_AMOUNT);
        assertGt(IERC20(USDC).balanceOf(address(morphoVault)), DEPOSIT_AMOUNT - ALLOCATE_AMOUNT);
    }

    function _assertAaveHealthyReallocation(uint256 yieldAmount, uint256 allocateAmount) internal {
        address aaveAccount = aaveAdapter.getAccount(address(aaveVault));
        _fundUsdc(address(this), yieldAmount);
        IERC20(USDC).forceApprove(AAVE_POOL, yieldAmount);
        IAaveV3Pool(AAVE_POOL).supply(USDC, yieldAmount, aaveAccount, 0);

        uint256 skimmableBefore = aaveAdapter.skimmable(address(aaveVault));
        uint256 vaultBalanceBefore = IERC20(USDC).balanceOf(address(aaveVault));
        uint256 allocatedBefore = aaveVault.adapterAllocated(address(aaveAdapter));
        assertGt(skimmableBefore, 0);

        vm.prank(alice);
        uint256 allocated = aaveVault.allocateAdapter(address(aaveAdapter), allocateAmount);
        uint256 vaultBalanceAfterAllocate = IERC20(USDC).balanceOf(address(aaveVault));
        uint256 skimmableAfterAllocate = aaveAdapter.skimmable(address(aaveVault));

        assertEq(allocated, allocateAmount);
        assertEq(aaveVault.adapterAllocated(address(aaveAdapter)), allocatedBefore + allocateAmount);
        assertEq(aaveVault.adaptersAllocated(), allocatedBefore + allocateAmount);
        assertEq(aaveAdapter.globalAllocated(USDC), allocatedBefore + allocateAmount);
        assertEq(vaultBalanceAfterAllocate, vaultBalanceBefore - allocateAmount);
        assertLe(skimmableAfterAllocate, skimmableBefore + 1);

        VaultV2(address(aaveVault)).skimAdapters();

        assertEq(aaveAdapter.skimmable(address(aaveVault)), 0);
        assertApproxEqAbs(
            IERC20(USDC).balanceOf(address(aaveVault)), vaultBalanceAfterAllocate + skimmableAfterAllocate, 1
        );
    }

    function _assertMorphoHealthyReallocation(uint256 yieldAmount, uint256 allocateAmount) internal {
        address morphoAccount = morphoAdapter.getAccount(address(morphoVault));
        _fundUsdc(address(this), yieldAmount);
        IERC20(USDC).forceApprove(MORPHO_GAUNTLET_USDC_PRIME, yieldAmount);
        IMorphoVaultV2(MORPHO_GAUNTLET_USDC_PRIME).deposit(yieldAmount, morphoAccount);

        uint256 skimmableBefore = morphoAdapter.skimmable(address(morphoVault));
        uint256 vaultBalanceBefore = IERC20(USDC).balanceOf(address(morphoVault));
        uint256 allocatedBefore = morphoVault.adapterAllocated(address(morphoAdapter));
        assertGt(skimmableBefore, 0);

        vm.prank(alice);
        uint256 allocated = morphoVault.allocateAdapter(address(morphoAdapter), allocateAmount);
        uint256 vaultBalanceAfterAllocate = IERC20(USDC).balanceOf(address(morphoVault));
        uint256 skimmableAfterAllocate = morphoAdapter.skimmable(address(morphoVault));

        assertEq(allocated, allocateAmount);
        assertEq(morphoVault.adapterAllocated(address(morphoAdapter)), allocatedBefore + allocateAmount);
        assertEq(morphoVault.adaptersAllocated(), allocatedBefore + allocateAmount);
        assertEq(morphoAdapter.globalAllocated(USDC), allocatedBefore + allocateAmount);
        assertEq(vaultBalanceAfterAllocate, vaultBalanceBefore - allocateAmount);
        assertLe(skimmableAfterAllocate, skimmableBefore + 1);

        VaultV2(address(morphoVault)).skimAdapters();

        assertEq(morphoAdapter.skimmable(address(morphoVault)), 0);
        assertApproxEqAbs(
            IERC20(USDC).balanceOf(address(morphoVault)), vaultBalanceAfterAllocate + skimmableAfterAllocate, 1
        );
    }

    function _fundAndDeposit(IVaultV2 vault_, uint256 amount) internal {
        _fundUsdc(address(this), amount);
        IERC20(USDC).forceApprove(address(vault_), amount);
        vault_.deposit(address(this), amount);
    }

    function _deployAaveAdapter() internal returns (AaveV3Adapter adapter) {
        uint256 nonce = vm.getNonce(address(this));
        address predictedAdapter = vm.computeCreateAddress(address(this), nonce + 2);
        address beacon =
            address(new UpgradeableBeacon(address(0), address(new AaveV3Account(AAVE_POOL, predictedAdapter))));

        adapter =
            new AaveV3Adapter(AAVE_POOL, address(curatorRegistry), address(rewards), address(vaultFactory), beacon);
    }

    function _deployMorphoAdapter() internal returns (MorphoVaultV2Adapter adapter) {
        uint256 nonce = vm.getNonce(address(this));
        address predictedAdapter = vm.computeCreateAddress(address(this), nonce + 2);
        address beacon = address(new UpgradeableBeacon(address(0), address(new MorphoVaultV2Account(predictedAdapter))));

        adapter = new MorphoVaultV2Adapter(
            MORPHO_VAULT_FACTORY,
            MORPHO_ADAPTER_REGISTRY,
            address(curatorRegistry),
            address(rewards),
            address(vaultFactory),
            beacon
        );
    }

    function _prepareAdapter(IVaultV2 vault_, address adapter, uint208 limit) internal {
        vm.startPrank(alice);
        VaultV2(address(vault_)).setAdapterLimit(adapter, limit);
        VaultV2(address(vault_)).grantRole(DEALLOCATE_ADAPTER_ROLE, alice);
        vm.stopPrank();
    }

    function _fundUsdc(address account, uint256 amount) internal {
        deal(USDC, account, IERC20(USDC).balanceOf(account) + amount);
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
