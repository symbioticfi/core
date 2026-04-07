// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

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
import {AaveV3Adapter} from "../../src/contracts/vault/adapters/AaveV3Adapter.sol";
import {MorphoVaultV2Adapter} from "../../src/contracts/vault/adapters/MorphoVaultV2Adapter.sol";
import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";
import {IAdapter} from "../../src/interfaces/vault/IAdapter.sol";
import {IVaultV2, DEALLOCATE_ADAPTER_ROLE} from "../../src/interfaces/vault/IVaultV2.sol";
import {AaveV3ReserveData} from "../../src/interfaces/vault/adapters/aave_v3_adapter/IAaveV3AdapterDependencies.sol";
import {IUniversalDelegator} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IUniversalSlasher} from "../../src/interfaces/slasher/IUniversalSlasher.sol";
import {
    IMorphoVaultV2Adapter
} from "../../src/interfaces/vault/adapters/morpho_vaultv2_adapter/IMorphoVaultV2Adapter.sol";

import {MockFeeRegistry} from "../mocks/MockFeeRegistry.sol";
import {MockMorphoVault} from "../mocks/MockMorphoVault.sol";
import {Token} from "../mocks/Token.sol";

contract MockCuratorRegistryHarnessAdapters {
    mapping(address vault => address curator) public curators;

    function setCurator(address vault, address curator) external {
        curators[vault] = curator;
    }

    function getCurator(address vault) external view returns (address) {
        return curators[vault];
    }
}

contract MockMorphoVaultFactoryHarnessAdapters {
    mapping(address vault => bool status) public isVaultV2;

    function setVault(address vault, bool status) external {
        isVaultV2[vault] = status;
    }
}

interface IVaultDonateHarnessAdapters {
    function collateral() external view returns (address);
    function donate(uint256 amount) external;
}

contract MockRewardsPullAdapters is ReentrancyGuard {
    function distributeDonationRewards(address vault, uint256 amount) external nonReentrant {
        address collateral = IVaultDonateHarnessAdapters(vault).collateral();
        IERC20(collateral).transferFrom(msg.sender, address(this), amount);
        IERC20(collateral).approve(vault, amount);
        IVaultDonateHarnessAdapters(vault).donate(amount);
    }
}

contract MockRewardsRevertAdapters {
    function distributeDonationRewards(address, uint256) external pure {
        revert("donate failed");
    }
}

contract MockMorphoVaultHarness is MockMorphoVault {
    address public immutable adapterRegistry;

    constructor(address asset_, address adapterRegistry_) MockMorphoVault(asset_) {
        adapterRegistry = adapterRegistry_;
    }

    function liquidityAdapter() external pure returns (address) {
        return address(0);
    }

    function abdicated(bytes4) external pure returns (bool) {
        return true;
    }
}

contract MockMorphoVaultConfigurable {
    IERC20 public immutable asset;
    address public immutable adapterRegistry;
    address public liquidityAdapter;

    uint256 public totalShares;
    mapping(address account => uint256 shares) public sharesOf;

    bool public revertOnDeposit;
    bool public revertOnWithdraw;

    constructor(address asset_, address adapterRegistry_) {
        asset = IERC20(asset_);
        adapterRegistry = adapterRegistry_;
    }

    function setRevertOnDeposit(bool value) external {
        revertOnDeposit = value;
    }

    function setRevertOnWithdraw(bool value) external {
        revertOnWithdraw = value;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        if (revertOnDeposit) {
            revert("deposit failed");
        }

        uint256 totalAssetsBefore = asset.balanceOf(address(this));
        asset.transferFrom(msg.sender, address(this), assets);

        if (totalShares == 0 || totalAssetsBefore == 0) {
            shares = assets;
        } else {
            shares = assets * totalShares / totalAssetsBefore;
        }

        sharesOf[receiver] += shares;
        totalShares += shares;
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        if (revertOnWithdraw) {
            revert("withdraw failed");
        }

        uint256 totalAssets = asset.balanceOf(address(this));
        if (totalAssets == 0 || totalShares == 0) {
            return 0;
        }

        shares = assets * totalShares / totalAssets;
        if (shares > sharesOf[owner]) {
            shares = sharesOf[owner];
            assets = shares * totalAssets / totalShares;
        }

        sharesOf[owner] -= shares;
        totalShares -= shares;
        asset.transfer(receiver, assets);
    }

    function balanceOf(address account) external view returns (uint256) {
        return sharesOf[account];
    }

    function previewRedeem(uint256 shares) external view returns (uint256) {
        if (totalShares == 0) {
            return 0;
        }

        return shares * asset.balanceOf(address(this)) / totalShares;
    }

    function donateYield(uint256 amount) external {
        asset.transferFrom(msg.sender, address(this), amount);
    }

    function abdicated(bytes4) external pure returns (bool) {
        return true;
    }
}

contract MockAaveAToken is ERC20 {
    address public immutable UNDERLYING_ASSET_ADDRESS;
    address public pool;

    constructor(address underlyingAsset) ERC20("Mock AToken", "maToken") {
        UNDERLYING_ASSET_ADDRESS = underlyingAsset;
    }

    function setPool(address newPool) external {
        require(pool == address(0), "pool already set");
        pool = newPool;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }

    function transferUnderlying(address to, uint256 amount) external {
        require(msg.sender == pool, "not pool");
        IERC20(UNDERLYING_ASSET_ADDRESS).transfer(to, amount);
    }
}

contract MockAavePoolAddressesProvider {
    address public pool;
    address public poolDataProvider;

    function setPool(address pool_) external {
        pool = pool_;
    }

    function getPool() external view returns (address) {
        return pool;
    }

    function setPoolDataProvider(address poolDataProvider_) external {
        poolDataProvider = poolDataProvider_;
    }

    function getPoolDataProvider() external view returns (address) {
        return poolDataProvider;
    }
}

contract MockAavePoolDataProvider {
    mapping(address asset => address aToken) public aTokens;

    function setReserveToken(address asset, address aToken) external {
        aTokens[asset] = aToken;
    }

    function getReserveTokensAddresses(address asset) external view returns (address aToken, address, address) {
        return (aTokens[asset], address(0), address(0));
    }
}

contract MockAavePool {
    IERC20 public immutable asset;
    MockAaveAToken public immutable aToken;
    address public immutable ADDRESSES_PROVIDER;

    bool public revertOnSupply;
    bool public revertOnWithdraw;

    constructor(address asset_, address aToken_, address addressesProvider_) {
        asset = IERC20(asset_);
        aToken = MockAaveAToken(aToken_);
        ADDRESSES_PROVIDER = addressesProvider_;
    }

    function getReserveData(address asset_) external view returns (AaveV3ReserveData memory reserveData) {
        if (asset_ == address(asset)) {
            reserveData.aTokenAddress = address(aToken);
        }
    }

    function setRevertOnSupply(bool value) external {
        revertOnSupply = value;
    }

    function setRevertOnWithdraw(bool value) external {
        revertOnWithdraw = value;
    }

    function supply(address asset_, uint256 amount, address onBehalfOf, uint16) external {
        require(asset_ == address(asset), "invalid asset");
        require(!revertOnSupply, "supply failed");

        asset.transferFrom(msg.sender, address(aToken), amount);
        aToken.mint(onBehalfOf, amount);
    }

    function withdraw(address asset_, uint256 amount, address to) external returns (uint256 withdrawn) {
        require(asset_ == address(asset), "invalid asset");
        require(!revertOnWithdraw, "withdraw failed");

        uint256 balance = aToken.balanceOf(msg.sender);
        uint256 liquidity = asset.balanceOf(address(aToken));
        withdrawn = amount > balance ? balance : amount;
        withdrawn = withdrawn > liquidity ? liquidity : withdrawn;
        if (withdrawn > 0) {
            aToken.burn(msg.sender, withdrawn);
            aToken.transferUnderlying(to, withdrawn);
        }
    }

    function accrueYield(address account, uint256 amount) external {
        asset.transferFrom(msg.sender, address(aToken), amount);
        aToken.mint(account, amount);
    }

    function drainLiquidity(address to, uint256 amount) external {
        aToken.transferUnderlying(to, amount);
    }
}

contract VaultV2AdaptersTest is Test {
    address internal owner;
    address internal alice;

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
    MockCuratorRegistryHarnessAdapters internal curatorRegistry;

    Token internal collateral;
    Token internal otherCollateral;
    MockRewardsPullAdapters internal pullRewards;
    MockMorphoVaultFactoryHarnessAdapters internal morphoVaultFactory;
    IVaultV2 internal vault1;
    IVaultV2 internal vault2;
    MorphoVaultV2Adapter internal morphoAdapter;
    MockMorphoVaultHarness internal morphoVault;
    AaveV3Adapter internal aaveAdapter;
    MockAaveAToken internal aToken;
    MockAavePoolAddressesProvider internal aaveAddressesProvider;
    MockAavePoolDataProvider internal aaveDataProvider;
    MockAavePool internal aavePool;

    address internal curator = makeAddr("curator");
    address internal morphoAdapterRegistry = makeAddr("morphoAdapterRegistry");

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");

        vaultFactory = new VaultFactory(owner);
        delegatorFactory = new DelegatorFactory(owner);
        slasherFactory = new SlasherFactory(owner);
        networkRegistry = new NetworkRegistry();
        operatorRegistry = new OperatorRegistry();
        networkMiddlewareService = new NetworkMiddlewareService(address(networkRegistry));
        operatorVaultOptInService =
            new OptInService(address(operatorRegistry), address(vaultFactory), "OperatorVaultOptInService");
        operatorNetworkOptInService =
            new OptInService(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService");
        feeRegistry = new MockFeeRegistry();
        adapterRegistry = new AdapterRegistry(owner);
        vaultConfigurator =
            new VaultConfigurator(address(vaultFactory), address(delegatorFactory), address(slasherFactory));
        curatorRegistry = new MockCuratorRegistryHarnessAdapters();

        collateral = new Token("Token");
        otherCollateral = new Token("OtherCollateral");
        pullRewards = new MockRewardsPullAdapters();
        morphoVaultFactory = new MockMorphoVaultFactoryHarnessAdapters();

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
                    address(pullRewards),
                    address(adapterRegistry)
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

        vault1 = _createVault(address(collateral));
        vault2 = _createVault(address(collateral));
        morphoVault = new MockMorphoVaultHarness(address(collateral), morphoAdapterRegistry);

        (aToken, aaveAddressesProvider, aaveDataProvider, aavePool) = _deployAaveReserve(address(collateral));

        morphoVaultFactory.setVault(address(morphoVault), true);
        morphoAdapter = new MorphoVaultV2Adapter(
            address(morphoVaultFactory),
            morphoAdapterRegistry,
            address(curatorRegistry),
            address(pullRewards),
            address(vaultFactory)
        );
        morphoAdapter.initialize();
        morphoAdapter.setGlobalLimit(address(collateral), type(uint256).max);

        aaveAdapter = new AaveV3Adapter(address(aavePool), address(pullRewards), address(vaultFactory));
        aaveAdapter.initialize();
        aaveAdapter.setGlobalLimit(address(collateral), type(uint256).max);

        adapterRegistry.whitelistAdapter(address(morphoAdapter));
        adapterRegistry.whitelistAdapter(address(aaveAdapter));

        curatorRegistry.setCurator(address(vault1), curator);
        curatorRegistry.setCurator(address(vault2), curator);
    }

    function test_AdapterInitializeSetsCallerAsOwner() public view {
        assertEq(morphoAdapter.owner(), address(this));
        assertEq(aaveAdapter.owner(), address(this));
    }

    function test_AaveMulticallExecutesCallsSequentially() public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(IAdapter.setGlobalLimit, (address(collateral), 123));
        data[1] = abi.encodeCall(IAdapter.setGlobalLimit, (address(otherCollateral), 456));

        aaveAdapter.multicall(data);

        assertEq(aaveAdapter.globalLimit(address(collateral)), 123);
        assertEq(aaveAdapter.globalLimit(address(otherCollateral)), 456);
    }

    function test_MorphoMulticallBubblesRevertReason() public {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(IAdapter.setGlobalLimit, (address(collateral), 1));

        vm.prank(curator);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", curator));
        morphoAdapter.multicall(data);
    }

    function test_AaveSkimRejectsNonVault() public {
        vm.expectRevert(IAdapter.NotVault.selector);
        aaveAdapter.skim(address(this));
    }

    function test_MorphoAllocateRejectsNonVault() public {
        vm.prank(curator);
        vm.expectRevert(IAdapter.NotVault.selector);
        morphoAdapter.allocate(1);
    }

    function test_MorphoSetGlobalLimitRejectsNonOwner() public {
        vm.prank(curator);
        vm.expectRevert();
        morphoAdapter.setGlobalLimit(address(collateral), 1);
    }

    function test_MorphoSetVaultRejectsNonCurator() public {
        vm.expectRevert(IMorphoVaultV2Adapter.NotCurator.selector);
        morphoAdapter.setMorphoVault(address(vault1), address(morphoVault));
    }

    function test_MorphoSetVaultRejectsWrongCollateral() public {
        MockMorphoVaultHarness wrongMorphoVault =
            new MockMorphoVaultHarness(address(otherCollateral), morphoAdapterRegistry);
        morphoVaultFactory.setVault(address(wrongMorphoVault), true);

        vm.prank(curator);
        vm.expectRevert(IMorphoVaultV2Adapter.InvalidMorphoVault.selector);
        morphoAdapter.setMorphoVault(address(vault1), address(wrongMorphoVault));
    }

    function test_MorphoSetVaultAliasWorks() public {
        _configureMorpho(address(vault1));

        assertEq(morphoAdapter.morphoVaults(address(vault1)), address(morphoVault));
    }

    function test_MorphoSetVaultCannotReplaceActivePosition() public {
        MockMorphoVaultHarness otherMorphoVault = new MockMorphoVaultHarness(address(collateral), morphoAdapterRegistry);
        morphoVaultFactory.setVault(address(otherMorphoVault), true);

        _configureMorpho(address(vault1));
        _allocateMorpho(vault1, 80, 80);

        vm.prank(curator);
        vm.expectRevert(IMorphoVaultV2Adapter.ActivePosition.selector);
        morphoAdapter.setMorphoVault(address(vault1), address(otherMorphoVault));
    }

    function test_MorphoSetVaultCanClearWhenNoPosition() public {
        _configureMorpho(address(vault1));

        vm.prank(curator);
        morphoAdapter.setMorphoVault(address(vault1), address(0));

        assertEq(morphoAdapter.morphoVaults(address(vault1)), address(0));
        assertEq(morphoAdapter.allocatable(address(vault1)), 0);
        assertEq(morphoAdapter.deallocatable(address(vault1)), 0);
        assertEq(morphoAdapter.skimmable(address(vault1)), 0);
    }

    function test_MorphoAllocatableRespectsGlobalLimit() public {
        _configureMorpho(address(vault1));

        assertEq(morphoAdapter.allocatable(address(vault1)), type(uint256).max);
    }

    function test_MorphoAllocatableUsesRemainingGlobalLimitAcrossVaults() public {
        _configureMorpho(address(vault1));
        _configureMorpho(address(vault2));
        morphoAdapter.setGlobalLimit(address(collateral), 150);

        _allocateMorpho(vault1, 80, 80);
        assertEq(morphoAdapter.allocatable(address(vault1)), 70);

        _allocateMorpho(vault2, 50, 50);
        assertEq(morphoAdapter.allocatable(address(vault1)), 20);
        assertEq(morphoAdapter.allocatable(address(vault2)), 20);
    }

    function test_MorphoDeallocateRestoresGlobalLimitCapacity() public {
        _configureMorpho(address(vault1));
        morphoAdapter.setGlobalLimit(address(collateral), 100);

        _allocateMorpho(vault1, 80, 80);
        assertEq(morphoAdapter.allocatable(address(vault1)), 20);
        assertEq(morphoAdapter.globalAllocated(address(collateral)), 80);

        uint256 deallocated = _deallocateFromVault(vault1, address(morphoAdapter), 30);

        assertEq(deallocated, 30);
        assertEq(morphoAdapter.allocatable(address(vault1)), 50);
        assertEq(morphoAdapter.globalAllocated(address(collateral)), 50);
    }

    function test_MorphoDeallocateZeroAmountReturnsZero() public {
        _configureMorpho(address(vault1));
        _allocateMorpho(vault1, 80, 80);

        uint256 vaultBalanceBefore = collateral.balanceOf(address(vault1));
        uint256 deallocated = _deallocateFromVault(vault1, address(morphoAdapter), 0);

        assertEq(deallocated, 0);
        assertEq(collateral.balanceOf(address(vault1)), vaultBalanceBefore);
        assertEq(morphoAdapter.globalAllocated(address(collateral)), 80);
        assertEq(vault1.adapterAllocated(address(morphoAdapter)), 80);
        assertEq(morphoAdapter.deallocatable(address(vault1)), 80);
    }

    function test_MorphoAllocateWithoutConfiguredVaultReturnsEarly() public {
        morphoAdapter.setGlobalLimit(address(collateral), 100);
        _depositIntoVault(vault1, collateral, 80);
        _prepareAdapter(vault1, address(morphoAdapter), type(uint208).max);

        vm.prank(alice);
        uint256 allocated = vault1.allocateAdapter(address(morphoAdapter), 80);

        assertEq(allocated, 0);
        assertEq(collateral.balanceOf(address(morphoAdapter)), 0);
        assertEq(collateral.balanceOf(address(vault1)), 80);
        assertEq(vault1.adapterAllocated(address(morphoAdapter)), 0);
        assertEq(morphoAdapter.globalAllocated(address(collateral)), 0);
        assertEq(morphoAdapter.allocatable(address(vault1)), 0);
        assertEq(morphoAdapter.deallocatable(address(vault1)), 0);
        assertEq(morphoAdapter.skimmable(address(vault1)), 0);
    }

    function test_MorphoAllocateRetainsIdleAssetsWhenDepositFails() public {
        MockMorphoVaultConfigurable failingMorphoVault =
            new MockMorphoVaultConfigurable(address(collateral), morphoAdapterRegistry);
        failingMorphoVault.setRevertOnDeposit(true);
        morphoVaultFactory.setVault(address(failingMorphoVault), true);

        vm.prank(curator);
        morphoAdapter.setMorphoVault(address(vault1), address(failingMorphoVault));

        _depositIntoVault(vault1, collateral, 80);
        _prepareAdapter(vault1, address(morphoAdapter), type(uint208).max);

        vm.prank(alice);
        vault1.allocateAdapter(address(morphoAdapter), 80);

        assertEq(collateral.balanceOf(address(morphoAdapter)), 0);
        assertEq(collateral.balanceOf(address(failingMorphoVault)), 0);
        assertEq(collateral.balanceOf(address(vault1)), 80);
        assertEq(vault1.adapterAllocated(address(morphoAdapter)), 0);
        assertEq(morphoAdapter.globalAllocated(address(collateral)), 0);
        assertEq(morphoAdapter.deallocatable(address(vault1)), 0);
        assertEq(morphoAdapter.skimmable(address(vault1)), 0);
    }

    function test_MorphoSkimRevertsWhenRewardsDonationFails() public {
        MockRewardsRevertAdapters revertingRewards = new MockRewardsRevertAdapters();
        MorphoVaultV2Adapter adapter = new MorphoVaultV2Adapter(
            address(morphoVaultFactory),
            morphoAdapterRegistry,
            address(curatorRegistry),
            address(revertingRewards),
            address(vaultFactory)
        );
        adapter.initialize();
        adapter.setGlobalLimit(address(collateral), type(uint256).max);
        adapterRegistry.whitelistAdapter(address(adapter));

        _configureMorpho(adapter, address(vault1), address(morphoVault));
        _allocateMorpho(adapter, vault1, 80, 80);

        collateral.approve(address(morphoVault), 20);
        morphoVault.donateYield(20);

        uint256 skimmableBefore = adapter.skimmable(address(vault1));
        uint256 deallocatableBefore = adapter.deallocatable(address(vault1));

        vm.expectRevert();
        adapter.skim(address(vault1));
        assertEq(adapter.skimmable(address(vault1)), skimmableBefore);
        assertEq(adapter.deallocatable(address(vault1)), deallocatableBefore);
    }

    function test_MorphoAllocateAndSkimTracksYield() public {
        _configureMorpho(address(vault1));
        _allocateMorpho(vault1, 80, 80);

        assertEq(collateral.balanceOf(address(morphoAdapter)), 0);
        assertEq(collateral.balanceOf(address(morphoVault)), 80);
        assertEq(morphoAdapter.skimmable(address(vault1)), 0);
        assertEq(morphoAdapter.deallocatable(address(vault1)), 80);

        collateral.approve(address(morphoVault), 20);
        morphoVault.donateYield(20);

        uint256 expectedSkimmable = morphoAdapter.skimmable(address(vault1));
        uint256 vaultBalanceBefore = collateral.balanceOf(address(vault1));
        uint256 activeStakeBefore = vault1.activeStake();
        uint256 skimmed = morphoAdapter.skim(address(vault1));

        assertEq(skimmed, expectedSkimmable);
        assertEq(collateral.balanceOf(address(vault1)) - vaultBalanceBefore, skimmed);
        assertEq(vault1.activeStake() - activeStakeBefore, skimmed);
        assertEq(morphoAdapter.skimmable(address(vault1)), 0);
        assertEq(morphoAdapter.deallocatable(address(vault1)), 80);
    }

    function test_MorphoSkimReturnsZeroWhenWithdrawFails() public {
        MockMorphoVaultConfigurable failingMorphoVault =
            new MockMorphoVaultConfigurable(address(collateral), morphoAdapterRegistry);
        morphoVaultFactory.setVault(address(failingMorphoVault), true);

        vm.prank(curator);
        morphoAdapter.setMorphoVault(address(vault1), address(failingMorphoVault));

        _allocateMorpho(vault1, 80, 80);

        collateral.approve(address(failingMorphoVault), 20);
        failingMorphoVault.donateYield(20);
        failingMorphoVault.setRevertOnWithdraw(true);

        uint256 skimmableBefore = morphoAdapter.skimmable(address(vault1));
        uint256 deallocatableBefore = morphoAdapter.deallocatable(address(vault1));
        uint256 activeStakeBefore = vault1.activeStake();
        uint256 vaultBalanceBefore = collateral.balanceOf(address(vault1));

        uint256 skimmed = morphoAdapter.skim(address(vault1));

        assertEq(skimmed, 0);
        assertEq(collateral.balanceOf(address(vault1)), vaultBalanceBefore);
        assertEq(vault1.activeStake(), activeStakeBefore);
        assertEq(morphoAdapter.skimmable(address(vault1)), skimmableBefore);
        assertEq(morphoAdapter.deallocatable(address(vault1)), deallocatableBefore);
    }

    function test_MorphoSkimDoesNotDiluteOtherVault() public {
        _configureMorpho(address(vault1));
        _configureMorpho(address(vault2));

        _allocateMorpho(vault1, 100, 100);
        _allocateMorpho(vault2, 100, 100);

        collateral.approve(address(morphoVault), 20);
        morphoVault.donateYield(20);

        uint256 expectedSkimmed = morphoAdapter.skimmable(address(vault1));
        uint256 vault1BeforeSkim = morphoAdapter.deallocatable(address(vault1));
        uint256 vault2BeforeSkim = morphoAdapter.deallocatable(address(vault2));
        uint256 vault2SkimmableBefore = morphoAdapter.skimmable(address(vault2));

        uint256 skimmed = morphoAdapter.skim(address(vault1));

        assertEq(skimmed, expectedSkimmed);
        assertEq(morphoAdapter.deallocatable(address(vault1)), vault1BeforeSkim);
        assertEq(morphoAdapter.skimmable(address(vault1)), 0);
        assertGe(morphoAdapter.deallocatable(address(vault2)), vault2BeforeSkim);
        assertGe(morphoAdapter.skimmable(address(vault2)), vault2SkimmableBefore);
    }

    function test_MorphoDeallocateDoesNotDiluteOtherVault() public {
        _configureMorpho(address(vault1));
        _configureMorpho(address(vault2));

        _allocateMorpho(vault1, 100, 100);
        _allocateMorpho(vault2, 100, 100);

        uint256 deallocated = _deallocateFromVault(vault1, address(morphoAdapter), 40);

        assertEq(deallocated, 40);
        assertEq(morphoAdapter.deallocatable(address(vault1)), 60);
        assertEq(morphoAdapter.deallocatable(address(vault2)), 100);
        assertEq(collateral.balanceOf(address(vault1)), 40);
    }

    function test_MorphoDeallocateReturnsIdleBalanceWhenWithdrawFails() public {
        MockMorphoVaultConfigurable failingMorphoVault =
            new MockMorphoVaultConfigurable(address(collateral), morphoAdapterRegistry);
        morphoVaultFactory.setVault(address(failingMorphoVault), true);

        vm.prank(curator);
        morphoAdapter.setMorphoVault(address(vault1), address(failingMorphoVault));

        _allocateMorpho(vault1, 80, 80);

        collateral.transfer(address(morphoAdapter), 10);
        failingMorphoVault.setRevertOnWithdraw(true);

        uint256 deallocated = _deallocateFromVault(vault1, address(morphoAdapter), 30);

        assertEq(deallocated, 10);
        assertEq(collateral.balanceOf(address(vault1)), 10);
        assertEq(morphoAdapter.globalAllocated(address(collateral)), 70);
        assertEq(vault1.adapterAllocated(address(morphoAdapter)), 70);
        assertEq(morphoAdapter.deallocatable(address(vault1)), 70);
    }

    function test_AaveUsesPoolReserveForVaultCollateral() public view {
        assertEq(aaveAdapter.aToken(address(vault1)), address(aToken));
    }

    function test_AaveSetGlobalLimitRejectsNonOwner() public {
        vm.prank(curator);
        vm.expectRevert();
        aaveAdapter.setGlobalLimit(address(collateral), 1);
    }

    function test_AaveAllocatableRequiresReserve() public {
        IVaultV2 otherVault = _getVaultForCollateral(otherCollateral);

        assertEq(aaveAdapter.allocatable(address(otherVault)), 0);
    }

    function test_AaveDeallocatableRequiresReserve() public {
        IVaultV2 otherVault = _getVaultForCollateral(otherCollateral);

        assertEq(aaveAdapter.deallocatable(address(otherVault)), 0);
    }

    function test_AaveAllocatableUsesRemainingGlobalLimitAcrossVaults() public {
        aaveAdapter.setGlobalLimit(address(collateral), 150);

        _allocateAave(vault1, 80, 80);
        assertEq(aaveAdapter.allocatable(address(vault1)), 70);

        _allocateAave(vault2, 50, 50);
        assertEq(aaveAdapter.allocatable(address(vault1)), 20);
        assertEq(aaveAdapter.allocatable(address(vault2)), 20);
    }

    function test_AaveDeallocateRestoresGlobalLimitCapacity() public {
        aaveAdapter.setGlobalLimit(address(collateral), 100);

        _allocateAave(vault1, 80, 80);
        assertEq(aaveAdapter.allocatable(address(vault1)), 20);
        assertEq(aaveAdapter.globalAllocated(address(collateral)), 80);

        uint256 deallocated = _deallocateFromVault(vault1, address(aaveAdapter), 30);

        assertEq(deallocated, 30);
        assertEq(aaveAdapter.allocatable(address(vault1)), 50);
        assertEq(aaveAdapter.globalAllocated(address(collateral)), 50);
    }

    function test_AaveDeallocateZeroAmountReturnsZero() public {
        _allocateAave(vault1, 80, 80);

        uint256 vaultBalanceBefore = collateral.balanceOf(address(vault1));
        uint256 deallocated = _deallocateFromVault(vault1, address(aaveAdapter), 0);

        assertEq(deallocated, 0);
        assertEq(collateral.balanceOf(address(vault1)), vaultBalanceBefore);
        assertEq(aaveAdapter.globalAllocated(address(collateral)), 80);
        assertEq(vault1.adapterAllocated(address(aaveAdapter)), 80);
        assertEq(aaveAdapter.deallocatable(address(vault1)), 80);
    }

    function test_AaveAllocateUnsupportedReserveDoesNotConsumeGlobalLimit() public {
        IVaultV2 otherVault = _getVaultForCollateral(otherCollateral);
        aaveAdapter.setGlobalLimit(address(otherCollateral), 100);
        _depositIntoVault(otherVault, otherCollateral, 80);
        _prepareAdapter(otherVault, address(aaveAdapter), type(uint208).max);

        vm.prank(alice);
        uint256 allocated = otherVault.allocateAdapter(address(aaveAdapter), 80);

        assertEq(allocated, 0);
        assertEq(otherCollateral.balanceOf(address(aaveAdapter)), 0);
        assertEq(otherCollateral.balanceOf(address(otherVault)), 80);
        assertEq(otherVault.adapterAllocated(address(aaveAdapter)), 0);
        assertEq(aaveAdapter.globalAllocated(address(otherCollateral)), 0);
        assertEq(aaveAdapter.allocatable(address(otherVault)), 0);
        assertEq(aaveAdapter.deallocatable(address(otherVault)), 0);
        assertEq(aaveAdapter.skimmable(address(otherVault)), 0);
    }

    function test_AaveAllocateDeallocatesBackToVaultWhenSupplyFails() public {
        aavePool.setRevertOnSupply(true);

        _depositIntoVault(vault1, collateral, 80);
        _prepareAdapter(vault1, address(aaveAdapter), type(uint208).max);

        vm.prank(alice);
        vault1.allocateAdapter(address(aaveAdapter), 80);

        assertEq(collateral.balanceOf(address(aaveAdapter)), 0);
        assertEq(collateral.balanceOf(address(aavePool)), 0);
        assertEq(aToken.balanceOf(address(aaveAdapter)), 0);
        assertEq(collateral.balanceOf(address(vault1)), 80);
        assertEq(vault1.adapterAllocated(address(aaveAdapter)), 0);
        assertEq(aaveAdapter.globalAllocated(address(collateral)), 0);
        assertEq(aaveAdapter.deallocatable(address(vault1)), 0);
        assertEq(aaveAdapter.skimmable(address(vault1)), 0);
    }

    function test_AaveSkimRevertsWhenRewardsDonationFails() public {
        MockRewardsRevertAdapters revertingRewards = new MockRewardsRevertAdapters();
        AaveV3Adapter adapter = new AaveV3Adapter(address(aavePool), address(revertingRewards), address(vaultFactory));
        adapter.initialize();
        adapter.setGlobalLimit(address(collateral), type(uint256).max);
        adapterRegistry.whitelistAdapter(address(adapter));

        _allocateAave(adapter, vault1, 80, 80);

        collateral.approve(address(aavePool), 20);
        aavePool.accrueYield(address(adapter), 20);

        uint256 skimmableBefore = adapter.skimmable(address(vault1));
        uint256 deallocatableBefore = adapter.deallocatable(address(vault1));

        vm.expectRevert();
        adapter.skim(address(vault1));
        assertEq(adapter.skimmable(address(vault1)), skimmableBefore);
        assertEq(adapter.deallocatable(address(vault1)), deallocatableBefore);
    }

    function test_AaveDeallocateCapsToPoolLiquidity() public {
        _allocateAave(vault1, 80, 80);

        aavePool.drainLiquidity(address(this), 50);

        assertEq(aaveAdapter.deallocatable(address(vault1)), 30);

        uint256 deallocated = _deallocateFromVault(vault1, address(aaveAdapter), 80);

        assertEq(deallocated, 30);
        assertEq(collateral.balanceOf(address(vault1)), 30);
    }

    function test_AaveAllocateAndSkimTracksYield() public {
        _allocateAave(vault1, 80, 80);

        assertEq(collateral.balanceOf(address(aaveAdapter)), 0);
        assertEq(collateral.balanceOf(address(aToken)), 80);
        assertEq(aToken.balanceOf(address(aaveAdapter)), 80);
        assertEq(aaveAdapter.skimmable(address(vault1)), 0);
        assertEq(aaveAdapter.deallocatable(address(vault1)), 80);

        collateral.approve(address(aavePool), 20);
        aavePool.accrueYield(address(aaveAdapter), 20);

        uint256 expectedSkimmable = aaveAdapter.skimmable(address(vault1));
        uint256 vaultBalanceBefore = collateral.balanceOf(address(vault1));
        uint256 activeStakeBefore = vault1.activeStake();
        uint256 skimmed = aaveAdapter.skim(address(vault1));

        assertEq(skimmed, expectedSkimmable);
        assertEq(collateral.balanceOf(address(vault1)) - vaultBalanceBefore, skimmed);
        assertEq(vault1.activeStake() - activeStakeBefore, skimmed);
        assertEq(aaveAdapter.skimmable(address(vault1)), 0);
        assertEq(aaveAdapter.deallocatable(address(vault1)), 80);
    }

    function test_AaveSkimReturnsZeroWhenWithdrawFails() public {
        _allocateAave(vault1, 80, 80);

        collateral.approve(address(aavePool), 20);
        aavePool.accrueYield(address(aaveAdapter), 20);
        aavePool.setRevertOnWithdraw(true);

        uint256 skimmableBefore = aaveAdapter.skimmable(address(vault1));
        uint256 deallocatableBefore = aaveAdapter.deallocatable(address(vault1));
        uint256 activeStakeBefore = vault1.activeStake();
        uint256 vaultBalanceBefore = collateral.balanceOf(address(vault1));

        uint256 skimmed = aaveAdapter.skim(address(vault1));

        assertEq(skimmed, 0);
        assertEq(collateral.balanceOf(address(vault1)), vaultBalanceBefore);
        assertEq(vault1.activeStake(), activeStakeBefore);
        assertEq(aaveAdapter.skimmable(address(vault1)), skimmableBefore);
        assertEq(aaveAdapter.deallocatable(address(vault1)), deallocatableBefore);
    }

    function test_AaveSkimDoesNotDiluteOtherVault() public {
        _allocateAave(vault1, 100, 100);
        _allocateAave(vault2, 100, 100);

        collateral.approve(address(aavePool), 20);
        aavePool.accrueYield(address(aaveAdapter), 20);

        uint256 expectedSkimmed = aaveAdapter.skimmable(address(vault1));
        uint256 vault1BeforeSkim = aaveAdapter.deallocatable(address(vault1));
        uint256 vault2BeforeSkim = aaveAdapter.deallocatable(address(vault2));
        uint256 vault2SkimmableBefore = aaveAdapter.skimmable(address(vault2));

        uint256 skimmed = aaveAdapter.skim(address(vault1));

        assertEq(skimmed, expectedSkimmed);
        assertEq(aaveAdapter.deallocatable(address(vault1)), vault1BeforeSkim);
        assertEq(aaveAdapter.skimmable(address(vault1)), 0);
        assertGe(aaveAdapter.deallocatable(address(vault2)), vault2BeforeSkim);
        assertGe(aaveAdapter.skimmable(address(vault2)), vault2SkimmableBefore);
    }

    function test_AaveDeallocateCapsToVaultAllocation() public {
        _allocateAave(vault1, 80, 50);

        uint256 deallocated = _deallocateFromVault(vault1, address(aaveAdapter), 70);

        assertEq(deallocated, 50);
        assertEq(collateral.balanceOf(address(vault1)), 80);
        assertEq(aToken.balanceOf(address(aaveAdapter)), 0);
        assertEq(aaveAdapter.deallocatable(address(vault1)), 0);
    }

    function test_AaveDeallocateReturnsIdleBalanceWhenWithdrawFails() public {
        _allocateAave(vault1, 80, 80);

        collateral.transfer(address(aaveAdapter), 10);
        aavePool.setRevertOnWithdraw(true);

        uint256 deallocated = _deallocateFromVault(vault1, address(aaveAdapter), 30);

        assertEq(deallocated, 10);
        assertEq(collateral.balanceOf(address(vault1)), 10);
        assertEq(aaveAdapter.globalAllocated(address(collateral)), 70);
        assertEq(vault1.adapterAllocated(address(aaveAdapter)), 70);
        assertEq(aaveAdapter.deallocatable(address(vault1)), 70);
    }

    function _configureMorpho(address vaultAddress) internal {
        _configureMorpho(morphoAdapter, vaultAddress, address(morphoVault));
    }

    function _configureMorpho(MorphoVaultV2Adapter adapter, address vaultAddress, address morphoVaultAddress) internal {
        vm.prank(curator);
        adapter.setMorphoVault(vaultAddress, morphoVaultAddress);
    }

    function _depositIntoVault(IVaultV2 vault_, Token collateral_, uint256 amount) internal {
        collateral_.approve(address(vault_), amount);
        vault_.deposit(address(this), amount);
    }

    function _prepareAdapter(IVaultV2 vault_, address adapter, uint208 limit) internal {
        vm.startPrank(alice);
        VaultV2(address(vault_)).setAdapterLimit(adapter, limit);
        VaultV2(address(vault_)).grantRole(DEALLOCATE_ADAPTER_ROLE, alice);
        vm.stopPrank();
    }

    function _allocateMorpho(IVaultV2 vault_, uint256 depositedAmount, uint256 allocatedAmount) internal {
        _allocateMorpho(morphoAdapter, vault_, depositedAmount, allocatedAmount);
    }

    function _allocateMorpho(
        MorphoVaultV2Adapter adapter,
        IVaultV2 vault_,
        uint256 depositedAmount,
        uint256 allocatedAmount
    ) internal {
        _depositIntoVault(vault_, collateral, depositedAmount);
        _prepareAdapter(vault_, address(adapter), type(uint208).max);

        vm.prank(alice);
        vault_.allocateAdapter(address(adapter), allocatedAmount);
    }

    function _allocateAave(IVaultV2 vault_, uint256 depositedAmount, uint256 allocatedAmount) internal {
        _allocateAave(aaveAdapter, vault_, depositedAmount, allocatedAmount);
    }

    function _allocateAave(AaveV3Adapter adapter, IVaultV2 vault_, uint256 depositedAmount, uint256 allocatedAmount)
        internal
    {
        _depositIntoVault(vault_, collateral, depositedAmount);
        _prepareAdapter(vault_, address(adapter), type(uint208).max);

        vm.prank(alice);
        vault_.allocateAdapter(address(adapter), allocatedAmount);
    }

    function _deallocateFromVault(IVaultV2 vault_, address adapter, uint256 amount) internal returns (uint256) {
        vm.prank(alice);
        return vault_.deallocateAdapter(adapter, amount);
    }

    function _getVaultForCollateral(Token collateral_) internal returns (IVaultV2 collateralVault) {
        return _createVault(address(collateral_));
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
                allocateAdapterRoleHolder: alice
            })
        );
        bytes memory delegatorParams = abi.encode(
            IUniversalDelegator.InitParams({
                defaultAdminRoleHolder: alice,
                hook: address(0),
                hookSetRoleHolder: alice,
                createSlotRoleHolder: alice,
                setSizeRoleHolder: alice,
                swapSlotsRoleHolder: alice,
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

    function _deployAaveReserve(address asset)
        internal
        returns (
            MockAaveAToken deployedAToken,
            MockAavePoolAddressesProvider deployedProvider,
            MockAavePoolDataProvider deployedDataProvider,
            MockAavePool deployedPool
        )
    {
        deployedAToken = new MockAaveAToken(asset);
        deployedProvider = new MockAavePoolAddressesProvider();
        deployedDataProvider = new MockAavePoolDataProvider();
        deployedPool = new MockAavePool(asset, address(deployedAToken), address(deployedProvider));
        deployedAToken.setPool(address(deployedPool));
        deployedProvider.setPool(address(deployedPool));
        deployedProvider.setPoolDataProvider(address(deployedDataProvider));
        deployedDataProvider.setReserveToken(asset, address(deployedAToken));
    }
}
