// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {AaveV3Adapter} from "../../src/contracts/vault/adapters/AaveV3Adapter.sol";
import {MorphoVaultV2Adapter} from "../../src/contracts/vault/adapters/MorphoVaultV2Adapter.sol";
import {IAdapter} from "../../src/interfaces/vault/IAdapter.sol";
import {IAaveV3Adapter} from "../../src/interfaces/vault/adapters/aave_v3_adapter/IAaveV3Adapter.sol";
import {AaveV3ReserveData} from "../../src/interfaces/vault/adapters/aave_v3_adapter/IAaveV3AdapterDependencies.sol";
import {
    IMorphoVaultV2Adapter
} from "../../src/interfaces/vault/adapters/morpho_vaultv2_adapter/IMorphoVaultV2Adapter.sol";

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

contract MockRegistryHarnessAdapters {
    mapping(address account => bool status) public isEntity;

    function setEntity(address account, bool status) external {
        isEntity[account] = status;
    }
}

contract MockMorphoVaultFactoryHarnessAdapters {
    mapping(address vault => bool status) public isVaultV2;

    function setVault(address vault, bool status) external {
        isVaultV2[vault] = status;
    }
}

contract MockVaultHarnessAdapters {
    address public immutable collateral;
    mapping(address adapter => uint256 allocated) public adapterAllocated;
    uint256 public donated;

    constructor(address collateral_) {
        collateral = collateral_;
    }

    function setAdapterAllocated(address adapter, uint256 amount) external {
        adapterAllocated[adapter] = amount;
    }

    function donate(uint256 amount) external {
        IERC20(collateral).transferFrom(msg.sender, address(this), amount);
        donated += amount;
    }

    function pull(address token, address from, uint256 amount) external {
        IERC20(token).transferFrom(from, address(this), amount);
    }

    function deallocateAdapter(address adapter, uint256 amount) external returns (uint256 deallocated) {
        deallocated = IAdapter(adapter).deallocate(amount);
        if (deallocated > 0) {
            IERC20(collateral).transferFrom(adapter, address(this), deallocated);
            adapterAllocated[adapter] -= deallocated;
        }
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

    constructor(address asset_, address adapterRegistry_) {
        asset = IERC20(asset_);
        adapterRegistry = adapterRegistry_;
    }

    function setRevertOnDeposit(bool value) external {
        revertOnDeposit = value;
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
    Token internal collateral;
    Token internal otherCollateral;
    MockRewardsPullAdapters internal rewards;
    MockCuratorRegistryHarnessAdapters internal curatorRegistry;
    MockRegistryHarnessAdapters internal vaultFactory;
    MockMorphoVaultFactoryHarnessAdapters internal morphoVaultFactory;
    MockVaultHarnessAdapters internal vault1;
    MockVaultHarnessAdapters internal vault2;
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
        collateral = new Token("Collateral");
        otherCollateral = new Token("OtherCollateral");
        rewards = new MockRewardsPullAdapters();
        curatorRegistry = new MockCuratorRegistryHarnessAdapters();
        vaultFactory = new MockRegistryHarnessAdapters();
        morphoVaultFactory = new MockMorphoVaultFactoryHarnessAdapters();
        vault1 = new MockVaultHarnessAdapters(address(collateral));
        vault2 = new MockVaultHarnessAdapters(address(collateral));
        morphoVault = new MockMorphoVaultHarness(address(collateral), morphoAdapterRegistry);

        (aToken, aaveAddressesProvider, aaveDataProvider, aavePool) = _deployAaveReserve(address(collateral));

        morphoVaultFactory.setVault(address(morphoVault), true);
        morphoAdapter = new MorphoVaultV2Adapter(
            address(morphoVaultFactory),
            morphoAdapterRegistry,
            address(curatorRegistry),
            address(rewards),
            address(vaultFactory)
        );
        morphoAdapter.initialize();
        aaveAdapter = new AaveV3Adapter(address(aavePool), address(rewards), address(vaultFactory));
        aaveAdapter.initialize();

        vaultFactory.setEntity(address(vault1), true);
        vaultFactory.setEntity(address(vault2), true);
        curatorRegistry.setCurator(address(vault1), curator);
        curatorRegistry.setCurator(address(vault2), curator);
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
        vm.prank(curator);
        morphoAdapter.setMorphoVault(address(vault1), address(morphoVault));

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

    function test_MorphoAllocateRetainsIdleAssetsWhenDepositFails() public {
        MockMorphoVaultConfigurable failingMorphoVault =
            new MockMorphoVaultConfigurable(address(collateral), morphoAdapterRegistry);
        failingMorphoVault.setRevertOnDeposit(true);
        morphoVaultFactory.setVault(address(failingMorphoVault), true);

        vm.prank(curator);
        morphoAdapter.setMorphoVault(address(vault1), address(failingMorphoVault));

        collateral.transfer(address(morphoAdapter), 80);
        vault1.setAdapterAllocated(address(morphoAdapter), 80);

        vm.prank(address(vault1));
        morphoAdapter.allocate(80);

        assertEq(collateral.balanceOf(address(morphoAdapter)), 0);
        assertEq(collateral.balanceOf(address(failingMorphoVault)), 0);
        assertEq(collateral.balanceOf(address(vault1)), 80);
        assertEq(vault1.adapterAllocated(address(morphoAdapter)), 0);
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
        uint256 skimmed = morphoAdapter.skim(address(vault1));

        assertEq(skimmed, expectedSkimmable);
        assertEq(collateral.balanceOf(address(vault1)) - vaultBalanceBefore, skimmed);
        assertEq(vault1.donated(), skimmed);
        assertEq(morphoAdapter.skimmable(address(vault1)), 0);
        assertEq(morphoAdapter.deallocatable(address(vault1)), 80);
    }

    function test_MorphoSkimDoesNotDiluteOtherVault() public {
        _configureMorpho(address(vault1));
        _configureMorpho(address(vault2));

        _allocateMorpho(vault1, 100, type(uint256).max);
        _allocateMorpho(vault2, 100, type(uint256).max);

        collateral.approve(address(morphoVault), 20);
        morphoVault.donateYield(20);

        uint256 expectedSkimmed = morphoAdapter.skimmable(address(vault1));
        uint256 vault1BeforeSkim = morphoAdapter.deallocatable(address(vault1));
        uint256 vault2BeforeSkim = morphoAdapter.deallocatable(address(vault2));
        uint256 vault2SkimmableBefore = morphoAdapter.skimmable(address(vault2));

        uint256 skimmed = morphoAdapter.skim(address(vault1));

        assertEq(skimmed, expectedSkimmed);
        assertEq(morphoAdapter.deallocatable(address(vault1)), vault1BeforeSkim - skimmed);
        assertGe(morphoAdapter.deallocatable(address(vault2)), vault2BeforeSkim);
        assertGe(morphoAdapter.skimmable(address(vault2)), vault2SkimmableBefore);
    }

    function test_MorphoDeallocateDoesNotDiluteOtherVault() public {
        _configureMorpho(address(vault1));
        _configureMorpho(address(vault2));

        _allocateMorpho(vault1, 100, 100);
        _allocateMorpho(vault2, 100, 100);

        vm.prank(address(vault1));
        uint256 deallocated = morphoAdapter.deallocate(40);
        vault1.pull(address(collateral), address(morphoAdapter), deallocated);

        assertEq(deallocated, 40);
        assertEq(morphoAdapter.deallocatable(address(vault1)), 60);
        assertEq(morphoAdapter.deallocatable(address(vault2)), 100);
        assertEq(collateral.balanceOf(address(vault1)), 40);
    }

    function test_AaveUsesPoolReserveForVaultCollateral() public {
        assertEq(aaveAdapter.AAVE_POOL(), address(aavePool));
        assertEq(aaveAdapter.aToken(address(vault1)), address(aToken));
    }

    function test_AaveAllocatableRequiresReserve() public {
        MockVaultHarnessAdapters otherVault = new MockVaultHarnessAdapters(address(otherCollateral));
        vaultFactory.setEntity(address(otherVault), true);

        assertEq(aaveAdapter.allocatable(address(otherVault)), 0);
    }

    function test_AaveAllocateDeallocatesBackToVaultWhenSupplyFails() public {
        aavePool.setRevertOnSupply(true);

        collateral.transfer(address(aaveAdapter), 80);
        vault1.setAdapterAllocated(address(aaveAdapter), 80);

        vm.prank(address(vault1));
        aaveAdapter.allocate(80);

        assertEq(collateral.balanceOf(address(aaveAdapter)), 0);
        assertEq(collateral.balanceOf(address(aavePool)), 0);
        assertEq(aToken.balanceOf(address(aaveAdapter)), 0);
        assertEq(collateral.balanceOf(address(vault1)), 80);
        assertEq(vault1.adapterAllocated(address(aaveAdapter)), 0);
        assertEq(aaveAdapter.deallocatable(address(vault1)), 0);
        assertEq(aaveAdapter.skimmable(address(vault1)), 0);
    }

    function test_AaveSkimRevertsWhenRewardsDonationFails() public {
        MockRewardsRevertAdapters revertingRewards = new MockRewardsRevertAdapters();
        AaveV3Adapter adapter = new AaveV3Adapter(address(aavePool), address(revertingRewards), address(vaultFactory));
        adapter.initialize();

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

        vm.prank(address(vault1));
        uint256 deallocated = aaveAdapter.deallocate(80);
        vault1.pull(address(collateral), address(aaveAdapter), deallocated);

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
        uint256 skimmed = aaveAdapter.skim(address(vault1));

        assertEq(skimmed, expectedSkimmable);
        assertEq(collateral.balanceOf(address(vault1)) - vaultBalanceBefore, skimmed);
        assertEq(vault1.donated(), skimmed);
        assertEq(aaveAdapter.skimmable(address(vault1)), 0);
        assertEq(aaveAdapter.deallocatable(address(vault1)), 80);
    }

    function test_AaveSkimDoesNotDiluteOtherVault() public {
        _allocateAave(vault1, 100, type(uint256).max);
        _allocateAave(vault2, 100, type(uint256).max);

        collateral.approve(address(aavePool), 20);
        aavePool.accrueYield(address(aaveAdapter), 20);

        uint256 expectedSkimmed = aaveAdapter.skimmable(address(vault1));
        uint256 vault1BeforeSkim = aaveAdapter.deallocatable(address(vault1));
        uint256 vault2BeforeSkim = aaveAdapter.deallocatable(address(vault2));
        uint256 vault2SkimmableBefore = aaveAdapter.skimmable(address(vault2));

        uint256 skimmed = aaveAdapter.skim(address(vault1));

        assertEq(skimmed, expectedSkimmed);
        assertEq(aaveAdapter.deallocatable(address(vault1)), vault1BeforeSkim - skimmed);
        assertGe(aaveAdapter.deallocatable(address(vault2)), vault2BeforeSkim);
        assertGe(aaveAdapter.skimmable(address(vault2)), vault2SkimmableBefore);
    }

    function test_AaveDeallocateCapsToVaultAllocation() public {
        _allocateAave(vault1, 80, 50);

        vm.prank(address(vault1));
        uint256 deallocated = aaveAdapter.deallocate(70);
        vault1.pull(address(collateral), address(aaveAdapter), deallocated);

        assertEq(deallocated, 50);
        assertEq(collateral.balanceOf(address(vault1)), 80);
        assertEq(aToken.balanceOf(address(aaveAdapter)), 0);
        assertEq(aaveAdapter.deallocatable(address(vault1)), 0);
    }

    function _configureMorpho(address vaultAddress) internal {
        _configureMorpho(morphoAdapter, vaultAddress, address(morphoVault));
    }

    function _configureMorpho(MorphoVaultV2Adapter adapter, address vaultAddress, address morphoVaultAddress) internal {
        vm.prank(curator);
        adapter.setMorphoVault(vaultAddress, morphoVaultAddress);
    }

    function _allocateMorpho(MockVaultHarnessAdapters vault_, uint256 amount, uint256 allocatedToAdapter) internal {
        _allocateMorpho(morphoAdapter, vault_, amount, allocatedToAdapter);
    }

    function _allocateMorpho(
        MorphoVaultV2Adapter adapter,
        MockVaultHarnessAdapters vault_,
        uint256 amount,
        uint256 allocatedToAdapter
    ) internal {
        collateral.transfer(address(adapter), amount);
        vault_.setAdapterAllocated(address(adapter), allocatedToAdapter);

        vm.prank(address(vault_));
        adapter.allocate(amount);
    }

    function _allocateAave(MockVaultHarnessAdapters vault_, uint256 amount, uint256 allocatedToAdapter) internal {
        _allocateAave(aaveAdapter, vault_, amount, allocatedToAdapter);
    }

    function _allocateAave(
        AaveV3Adapter adapter,
        MockVaultHarnessAdapters vault_,
        uint256 amount,
        uint256 allocatedToAdapter
    ) internal {
        collateral.transfer(address(adapter), amount);
        vault_.setAdapterAllocated(address(adapter), allocatedToAdapter);

        vm.prank(address(vault_));
        adapter.allocate(amount);
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
