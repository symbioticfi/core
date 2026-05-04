// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {UpgradeableBeacon} from "@solady/src/utils/UpgradeableBeacon.sol";

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
import {IAdapter} from "../../src/interfaces/vault/adapters/IAdapter.sol";
import {
    IVaultV2,
    ALLOCATE_ADAPTER_ROLE,
    DEALLOCATE_ADAPTER_ROLE,
    MAX_ADAPTERS
} from "../../src/interfaces/vault/IVaultV2.sol";
import {IUniversalDelegator} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IUniversalSlasher} from "../../src/interfaces/slasher/IUniversalSlasher.sol";
import {DEALLOCATE_BUFFER, IMorphoVaultV2Adapter} from "../../src/interfaces/vault/adapters/IMorphoVaultV2Adapter.sol";

import {MockFeeRegistry} from "../mocks/MockFeeRegistry.sol";
import {MockMorphoVault} from "../mocks/MockMorphoVault.sol";
import {FeeOnTransferToken} from "../mocks/FeeOnTransferToken.sol";
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

contract MockVaultV2MigrateReverter {
    fallback() external payable {
        revert("migrate failed");
    }
}

contract VaultV2MigrateFailureHarness {
    address internal immutable vaultV2Migrate;

    constructor(address vaultV2Migrate_) {
        vaultV2Migrate = vaultV2Migrate_;
    }

    function exposeMigrate() external {
        (bool success, bytes memory returnData) =
            vaultV2Migrate.delegatecall(abi.encodeCall(VaultV2Migrate.migrate, (uint64(1), "")));
        if (!success) {
            assembly ("memory-safe") {
                revert(add(32, returnData), mload(returnData))
            }
        }
    }
}

contract MockCoverageAdapter {
    function allocatable(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function deallocatable(address) external pure returns (uint256) {
        return 0;
    }

    function allocate(uint256) external pure {}

    function deallocate(uint256) external pure returns (uint256) {
        return 0;
    }

    function skim(address) external pure returns (uint256) {
        return 0;
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
    bool public useVirtualUnderlyingBalanceOverride;
    uint128 public virtualUnderlyingBalanceOverride;

    constructor(address asset_, address aToken_, address addressesProvider_) {
        asset = IERC20(asset_);
        aToken = MockAaveAToken(aToken_);
        ADDRESSES_PROVIDER = addressesProvider_;
    }

    function getReserveAToken(address asset_) external view returns (address) {
        return asset_ == address(asset) ? address(aToken) : address(0);
    }

    function getVirtualUnderlyingBalance(address asset_) external view returns (uint128) {
        if (asset_ != address(asset)) {
            return 0;
        }
        if (useVirtualUnderlyingBalanceOverride) {
            return virtualUnderlyingBalanceOverride;
        }
        return uint128(asset.balanceOf(address(aToken)));
    }

    function setRevertOnSupply(bool value) external {
        revertOnSupply = value;
    }

    function setRevertOnWithdraw(bool value) external {
        revertOnWithdraw = value;
    }

    function setVirtualUnderlyingBalance(uint128 value) external {
        useVirtualUnderlyingBalanceOverride = true;
        virtualUnderlyingBalanceOverride = value;
    }

    function clearVirtualUnderlyingBalanceOverride() external {
        useVirtualUnderlyingBalanceOverride = false;
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
                    address(adapterRegistry),
                    address(
                        new VaultV2Migrate(
                            address(delegatorFactory),
                            address(slasherFactory),
                            address(feeRegistry),
                            address(pullRewards),
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

        vault1 = _createVault(address(collateral));
        vault2 = _createVault(address(collateral));
        morphoVault = new MockMorphoVaultHarness(address(collateral), morphoAdapterRegistry);

        (aToken, aaveAddressesProvider, aaveDataProvider, aavePool) = _deployAaveReserve(address(collateral));

        morphoVaultFactory.setVault(address(morphoVault), true);
        morphoAdapter = _deployMorphoAdapter(address(pullRewards));
        morphoAdapter.initialize();
        morphoAdapter.setGlobalLimit(address(collateral), type(uint256).max);

        aaveAdapter = _deployAaveAdapter(address(pullRewards));
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

    function test_CreateRevertsWhenAdaptersAllowDelayNotGreaterThanEpochDuration() public {
        address[] memory initialAdapters = new address[](0);

        vm.expectRevert(IVaultV2.InvalidAdaptersAddDelay.selector);
        this.createVaultForInvalidAdaptersAllowDelayTest(address(collateral), initialAdapters, 1 days);
    }

    function test_CreateRevertsWhenInitialAdaptersContainDuplicate() public {
        address[] memory initialAdapters = new address[](2);
        initialAdapters[0] = address(aaveAdapter);
        initialAdapters[1] = address(aaveAdapter);

        vm.expectRevert(IVaultV2.AlreadyAdded.selector);
        this.createVaultForDuplicateAdaptersTest(address(collateral), initialAdapters);
    }

    function test_SetAdapterLimitSchedulesNewAdapterBeforeLimitCanBeSet() public {
        uint48 availableAt = uint48(block.timestamp + 2 days);

        vm.prank(alice);
        bool isSet = VaultV2(address(vault1)).setAdapterLimit(address(aaveAdapter), 100);

        assertFalse(isSet);
        assertEq(VaultV2(address(vault1)).adapterAllowedAt(address(aaveAdapter)), availableAt);
        assertEq(vault1.adapterLimit(address(aaveAdapter)), 0);
        assertEq(vault1.adaptersLength(), 1);
        assertEq(vault1.adapters(0), address(aaveAdapter));
        assertEq(vault1.adapterIndex(address(aaveAdapter)), 1);

        vm.prank(alice);
        isSet = VaultV2(address(vault1)).setAdapterLimit(address(aaveAdapter), 100);

        assertFalse(isSet);
        assertEq(vault1.adapterLimit(address(aaveAdapter)), 0);

        vm.warp(availableAt);

        vm.prank(alice);
        isSet = VaultV2(address(vault1)).setAdapterLimit(address(aaveAdapter), 100);

        assertTrue(isSet);
        assertEq(vault1.adapterLimit(address(aaveAdapter)), 100);
        assertEq(vault1.adaptersLength(), 1);
        assertEq(vault1.adapters(0), address(aaveAdapter));
    }

    function test_SetAdapterLimitAllowsInitialAdapterImmediately() public {
        address[] memory initialAdapters = new address[](1);
        initialAdapters[0] = address(aaveAdapter);
        IVaultV2 vault_ = _createVault(address(collateral), initialAdapters, 2 days);

        vm.prank(alice);
        bool isSet = VaultV2(address(vault_)).setAdapterLimit(address(aaveAdapter), 100);

        assertTrue(isSet);
        assertEq(VaultV2(address(vault_)).adapterAllowedAt(address(aaveAdapter)), 0);
        assertEq(vault_.adapterLimit(address(aaveAdapter)), 100);
        assertEq(vault_.adaptersLength(), 1);
        assertEq(vault_.adapters(0), address(aaveAdapter));
        assertEq(vault_.adapterIndex(address(aaveAdapter)), 1);
        assertTrue(VaultV2(address(vault_)).hasRole(ALLOCATE_ADAPTER_ROLE, address(aaveAdapter)));
        assertTrue(VaultV2(address(vault_)).hasRole(DEALLOCATE_ADAPTER_ROLE, address(aaveAdapter)));
    }

    function test_SetAdapterLimitUpdatesAdapterIndexWhenRemovingAdapter() public {
        _prepareAdapter(vault1, address(aaveAdapter), 100);
        _prepareAdapter(vault1, address(morphoAdapter), 100);

        vm.prank(alice);
        VaultV2(address(vault1)).setAdapterLimit(address(aaveAdapter), 0);

        assertEq(vault1.adaptersLength(), 1);
        assertEq(vault1.adapters(0), address(morphoAdapter));
        assertEq(vault1.adapterIndex(address(aaveAdapter)), 0);
        assertEq(vault1.adapterIndex(address(morphoAdapter)), 1);
    }

    function test_SetAdapterLimitUpdatesAdapterIndexWhenRemovingLastAdapter() public {
        _prepareAdapter(vault1, address(aaveAdapter), 100);
        _prepareAdapter(vault1, address(morphoAdapter), 100);

        vm.prank(alice);
        VaultV2(address(vault1)).setAdapterLimit(address(morphoAdapter), 0);

        assertEq(vault1.adaptersLength(), 1);
        assertEq(vault1.adapters(0), address(aaveAdapter));
        assertEq(vault1.adapterIndex(address(aaveAdapter)), 1);
        assertEq(vault1.adapterIndex(address(morphoAdapter)), 0);
    }

    function test_SetAdapterLimitZeroForAbsentAdapterReturnsFalseAndKeepsFirstAdapter() public {
        _prepareAdapter(vault1, address(aaveAdapter), 100);

        vm.prank(alice);
        bool isSet = VaultV2(address(vault1)).setAdapterLimit(address(morphoAdapter), 0);

        assertFalse(isSet);
        assertEq(vault1.adaptersLength(), 1);
        assertEq(vault1.adapters(0), address(aaveAdapter));
        assertEq(vault1.adapterLimit(address(aaveAdapter)), 100);
        assertEq(vault1.adapterLimit(address(morphoAdapter)), 0);
    }

    function test_SetAdapterLimitZeroForAbsentAdapterReturnsFalseWhenAdaptersEmpty() public {
        vm.prank(alice);
        bool isSet = VaultV2(address(vault1)).setAdapterLimit(address(aaveAdapter), 0);

        assertFalse(isSet);
        assertEq(vault1.adaptersLength(), 0);
        assertEq(vault1.adapterLimit(address(aaveAdapter)), 0);
    }

    function test_SwapAdaptersUpdatesAdapterIndexes() public {
        _prepareAdapter(vault1, address(aaveAdapter), 100);
        _prepareAdapter(vault1, address(morphoAdapter), 100);

        vm.prank(alice);
        vault1.swapAdapters(address(aaveAdapter), address(morphoAdapter));

        assertEq(vault1.adapters(0), address(morphoAdapter));
        assertEq(vault1.adapters(1), address(aaveAdapter));
        assertEq(vault1.adapterIndex(address(morphoAdapter)), 1);
        assertEq(vault1.adapterIndex(address(aaveAdapter)), 2);
    }

    function test_SwapAdaptersRevertsWhenFirstAdapterAbsent() public {
        _prepareAdapter(vault1, address(aaveAdapter), 100);

        vm.prank(alice);
        vm.expectRevert(stdError.arithmeticError);
        vault1.swapAdapters(address(morphoAdapter), address(aaveAdapter));
    }

    function test_SwapAdaptersRevertsWhenSecondAdapterAbsent() public {
        _prepareAdapter(vault1, address(aaveAdapter), 100);

        vm.prank(alice);
        vm.expectRevert(stdError.arithmeticError);
        vault1.swapAdapters(address(aaveAdapter), address(morphoAdapter));
    }

    function test_SwapAdaptersSameAdapterIsNoop() public {
        _prepareAdapter(vault1, address(aaveAdapter), 100);

        vm.prank(alice);
        vault1.swapAdapters(address(aaveAdapter), address(aaveAdapter));

        assertEq(vault1.adaptersLength(), 1);
        assertEq(vault1.adapters(0), address(aaveAdapter));
        assertEq(vault1.adapterIndex(address(aaveAdapter)), 1);
    }

    function test_SetAdapterLimitRevertsWhenAdaptersLimitExceeded() public {
        for (uint160 i; i < MAX_ADAPTERS; ++i) {
            address adapter = address(0x1000 + i);
            adapterRegistry.whitelistAdapter(adapter);

            vm.prank(alice);
            VaultV2(address(vault1)).setAdapterLimit(adapter, 1);
        }

        address extraAdapter = address(0x2000);
        adapterRegistry.whitelistAdapter(extraAdapter);

        vm.prank(alice);
        vm.expectRevert(IVaultV2.TooManyAdapters.selector);
        VaultV2(address(vault1)).setAdapterLimit(extraAdapter, 1);
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

    function test_VaultV2MulticallSetsCuratorFlagsAndBubblesReverts() public {
        bytes[] memory data = new bytes[](4);
        data[0] = abi.encodeCall(VaultV2.setDepositWhitelist, (true));
        data[1] = abi.encodeCall(VaultV2.setDepositorWhitelistStatus, (alice, true));
        data[2] = abi.encodeCall(VaultV2.setIsDepositLimit, (true));
        data[3] = abi.encodeCall(VaultV2.setDepositLimit, (uint256(10)));

        vm.prank(alice);
        VaultV2(address(vault1)).multicall(data);

        assertTrue(vault1.depositWhitelist());
        assertTrue(vault1.isDepositorWhitelisted(alice));
        assertTrue(vault1.isDepositLimit());
        assertEq(vault1.depositLimit(), 10);

        address bob = makeAddr("bob");
        collateral.transfer(bob, 20);
        vm.startPrank(bob);
        collateral.approve(address(vault1), 1);
        vm.expectRevert(IVaultV2.NotWhitelistedDepositor.selector);
        vault1.deposit(bob, 1);
        vm.stopPrank();

        collateral.transfer(alice, 20);
        vm.startPrank(alice);
        collateral.approve(address(vault1), 11);
        vm.expectRevert(IVaultV2.DepositLimitReached.selector);
        vault1.deposit(alice, 11);
        vm.stopPrank();

        bytes[] memory badData = new bytes[](1);
        badData[0] = abi.encodeCall(VaultV2.setDepositorWhitelistStatus, (address(0), true));

        vm.prank(alice);
        vm.expectRevert(IVaultV2.InvalidAddress.selector);
        VaultV2(address(vault1)).multicall(badData);
    }

    function test_VaultV2DepositAutoAllocatesInitialAdapterAndDirectDeallocateAdapters() public {
        MockCoverageAdapter adapter = new MockCoverageAdapter();
        adapterRegistry.whitelistAdapter(address(adapter));

        address[] memory initialAdapters = new address[](1);
        initialAdapters[0] = address(adapter);
        IVaultV2 vault_ = _createVault(address(collateral), initialAdapters, 2 days);

        vm.prank(alice);
        assertTrue(VaultV2(address(vault_)).setAdapterLimit(address(adapter), 100));

        collateral.approve(address(vault_), 100);
        vault_.deposit(address(this), 100);

        assertEq(vault_.adaptersAllocated(), 100);
        assertEq(vault_.adapterAllocated(address(adapter)), 100);
        assertEq(collateral.balanceOf(address(adapter)), 100);

        vault_.deallocateAdapters();
    }

    function test_VaultV2RedeemClaimBatchAndWithdrawalViews() public {
        _depositIntoVault(vault1, collateral, 100);

        assertEq(VaultV2(address(vault1)).decimals(), collateral.decimals() + 6);
        assertEq(VaultV2(address(vault1)).totalSupply(), vault1.activeShares());
        assertEq(VaultV2(address(vault1)).balanceOf(address(this)), vault1.activeSharesOf(address(this)));
        assertEq(vault1.totalStake(), 100);
        assertEq(vault1.activeBalanceOfAt(address(this), uint48(block.timestamp), ""), 100);
        assertEq(vault1.activeWithdrawalsFor(vault1.epochDuration() + 1), 0);
        assertEq(vault1.activeWithdrawalsForAt(vault1.epochDuration() + 1, uint48(block.timestamp)), 0);
        assertEq(vault1.activeWithdrawals(), 0);
        assertEq(vault1.activeWithdrawalsAt(uint48(block.timestamp)), 0);
        assertEq(vault1.activeWithdrawalShares(), 0);
        assertEq(vault1.activeWithdrawalSharesAt(uint48(block.timestamp)), 0);
        assertEq(vault1.activeWithdrawalSharesOfAt(alice, uint48(block.timestamp)), 0);
        assertEq(vault1.allocatable(), 100);
        assertEq(vault1.adaptersOwe(), 0);
        assertEq(vault1.unclaimed(), 0);

        vault1.withdraw(alice, 20);
        vault1.redeem(alice, vault1.activeSharesOf(address(this)) / 10);

        uint48 requestedAt = uint48(block.timestamp);
        assertEq(vault1.withdrawalsOfLength(alice), 2);
        assertGt(vault1.withdrawalSharesOf(0, alice), 0);
        assertGt(vault1.withdrawalSharesOf(1, alice), 0);
        assertEq(vault1.withdrawalUnlockAt(0, alice), requestedAt + vault1.epochDuration());
        assertEq(vault1.withdrawalUnlockAt(1, alice), requestedAt + vault1.epochDuration());
        assertGt(vault1.withdrawalsOf(0, alice), 0);
        assertGt(vault1.withdrawalsOf(1, alice), 0);
        assertGt(vault1.activeWithdrawals(), 0);
        assertGt(vault1.activeWithdrawalShares(), 0);
        assertGt(vault1.activeWithdrawalSharesFor(0), 0);
        assertGt(vault1.activeWithdrawalSharesForAt(0, requestedAt), 0);
        assertGt(vault1.activeWithdrawalSharesOfAt(alice, requestedAt), 0);

        vm.prank(alice);
        vm.expectRevert(IVaultV2.WithdrawalNotMatured.selector);
        vault1.claim(alice, 0);

        vm.warp(requestedAt + vault1.epochDuration());

        uint256[] memory indexes = new uint256[](2);
        indexes[0] = 0;
        indexes[1] = 1;
        uint256 balanceBefore = collateral.balanceOf(alice);
        vm.prank(alice);
        uint256 claimed = vault1.claimBatch(alice, indexes);

        assertGt(claimed, 0);
        assertEq(collateral.balanceOf(alice) - balanceBefore, claimed);

        vm.prank(alice);
        vm.expectRevert(IVaultV2.AlreadyClaimed.selector);
        vault1.claim(alice, 0);
    }

    function test_VaultV2AccountingGuardReverts() public {
        _depositIntoVault(vault1, collateral, 10);

        vm.expectRevert(IVaultV2.TooMuchWithdraw.selector);
        vault1.withdraw(alice, 11);

        uint256 tooManyShares = vault1.activeSharesOf(address(this)) + 1;
        vm.expectRevert(IVaultV2.TooMuchRedeem.selector);
        vault1.redeem(alice, tooManyShares);

        VaultV2(address(vault1)).transfer(alice, 1);

        vm.prank(alice);
        vm.expectRevert(IVaultV2.TooMuchWithdraw.selector);
        vault1.instantWithdraw(alice, 10);
    }

    function test_VaultV2InstantWithdrawRevertsWhenAdapterCannotDeallocateOwedStake() public {
        MockCoverageAdapter adapter = new MockCoverageAdapter();
        adapterRegistry.whitelistAdapter(address(adapter));

        address[] memory initialAdapters = new address[](1);
        initialAdapters[0] = address(adapter);
        IVaultV2 vault_ = _createVault(address(collateral), initialAdapters, 2 days);

        vm.prank(alice);
        VaultV2(address(vault_)).setAdapterLimit(address(adapter), 100);

        collateral.approve(address(vault_), 100);
        vault_.deposit(address(this), 100);

        vm.expectRevert(IVaultV2.InsufficientAmount.selector);
        vault_.instantWithdraw(alice, 10);
    }

    function test_VaultV2ClaimRevertsWhenAdapterCannotDeallocateOwedStake() public {
        MockCoverageAdapter adapter = new MockCoverageAdapter();
        adapterRegistry.whitelistAdapter(address(adapter));

        address[] memory initialAdapters = new address[](1);
        initialAdapters[0] = address(adapter);
        IVaultV2 vault_ = _createVault(address(collateral), initialAdapters, 2 days);

        vm.prank(alice);
        VaultV2(address(vault_)).setAdapterLimit(address(adapter), 100);

        collateral.approve(address(vault_), 100);
        vault_.deposit(address(this), 100);
        vault_.withdraw(alice, 50);

        vm.warp(block.timestamp + vault_.epochDuration());

        vm.prank(alice);
        vm.expectRevert(IVaultV2.InsufficientAmount.selector);
        vault_.claim(alice, 0);
    }

    function test_VaultV2DonationRollsMaturedWithdrawalsIntoClaimableBucket() public {
        _depositIntoVault(vault1, collateral, 100);
        vault1.withdraw(alice, 20);

        vm.warp(block.timestamp + vault1.epochDuration());
        vault1.withdraw(alice, 10);

        collateral.transfer(address(pullRewards), 10);
        vm.prank(address(pullRewards));
        collateral.approve(address(vault1), 10);

        vm.prank(address(pullRewards));
        VaultV2(address(vault1)).donate(10);

        assertEq(vault1.unclaimed(), 20);
        assertGt(vault1.activeWithdrawals(), 0);
    }

    function test_VaultV2DonateEmitsActiveAndWithdrawalAmounts() public {
        _depositIntoVault(vault1, collateral, 100);
        vault1.withdraw(alice, 40);

        collateral.transfer(address(pullRewards), 10);
        vm.prank(address(pullRewards));
        collateral.approve(address(vault1), 10);

        vm.expectEmit(false, false, false, true, address(vault1));
        emit IVaultV2.Donate(6, 4);

        vm.prank(address(pullRewards));
        VaultV2(address(vault1)).donate(10);
    }

    function test_VaultV2OnSlashEmitsRequestedAndSplitSlashedAmounts() public {
        _depositIntoVault(vault1, collateral, 100);
        vault1.withdraw(alice, 40);

        vm.expectEmit(false, false, false, true, address(vault1));
        emit IVaultV2.OnSlash(150, 60, 40);

        vm.prank(vault1.slasher());
        (uint256 slashedAmount, uint256 owedAmount) = VaultV2(address(vault1)).onSlash(150);

        assertEq(slashedAmount, 100);
        assertEq(owedAmount, 0);
    }

    function test_VaultV2DonateSlashInstantWithdrawAndTransferPaths() public {
        _depositIntoVault(vault1, collateral, 100);
        vault1.withdraw(alice, 40);

        collateral.transfer(address(pullRewards), 10);
        vm.prank(address(pullRewards));
        collateral.approve(address(vault1), 10);

        vm.prank(address(pullRewards));
        VaultV2(address(vault1)).donate(10);

        vm.expectRevert(IVaultV2.NotRewards.selector);
        VaultV2(address(vault1)).donate(1);

        vm.expectRevert(IVaultV2.NotSlasher.selector);
        VaultV2(address(vault1)).onSlash(1);

        uint256 burnerBefore = collateral.balanceOf(vault1.burner());
        vm.prank(vault1.slasher());
        (uint256 slashedAmount, uint256 owedAmount) = VaultV2(address(vault1)).onSlash(10);
        assertEq(slashedAmount, 10);
        assertEq(owedAmount, 0);
        assertEq(collateral.balanceOf(vault1.burner()) - burnerBefore, 10);

        feeRegistry.setInstantWithdrawFee(address(vault1), 100_000);
        uint256 aliceBefore = collateral.balanceOf(alice);
        vault1.instantWithdraw(alice, 10);
        assertGt(collateral.balanceOf(alice) - aliceBefore, 0);
        assertLt(collateral.balanceOf(alice) - aliceBefore, 10);

        uint256 aliceSharesBefore = vault1.activeSharesOf(alice);
        VaultV2(address(vault1)).transfer(alice, 5);
        assertEq(vault1.activeSharesOf(alice), aliceSharesBefore + 5);
    }

    function test_VaultV2SetAdapterLimitRejectsUnregisteredAdapterAndRevokeRoleFallsThrough() public {
        vm.prank(alice);
        vm.expectRevert(IVaultV2.NotAdapter.selector);
        VaultV2(address(vault1)).setAdapterLimit(address(0xCAFE), 1);

        assertTrue(VaultV2(address(vault1)).hasRole(ALLOCATE_ADAPTER_ROLE, alice));

        vm.prank(alice);
        VaultV2(address(vault1)).revokeRole(ALLOCATE_ADAPTER_ROLE, alice);

        assertFalse(VaultV2(address(vault1)).hasRole(ALLOCATE_ADAPTER_ROLE, alice));
    }

    function test_VaultV2AdapterLimitRevokeAndOwedDeallocationPaths() public {
        _allocateAave(vault1, 100, 80);

        vm.prank(alice);
        vm.expectRevert(IVaultV2.AdapterAllocated.selector);
        VaultV2(address(vault1)).setAdapterLimit(address(aaveAdapter), 10);

        vm.prank(alice);
        VaultV2(address(vault1)).revokeRole(ALLOCATE_ADAPTER_ROLE, address(aaveAdapter));
        assertTrue(VaultV2(address(vault1)).hasRole(ALLOCATE_ADAPTER_ROLE, address(aaveAdapter)));

        uint256 allocatedBefore = vault1.adapterAllocated(address(aaveAdapter));
        vm.prank(vault1.slasher());
        VaultV2(address(vault1)).onSlash(50);
        assertLt(vault1.adapterAllocated(address(aaveAdapter)), allocatedBefore);
    }

    function test_VaultV2SyncOwedSlashOnlySlasher() public {
        _depositIntoVault(vault1, collateral, 50);

        vm.expectRevert(IVaultV2.NotSlasher.selector);
        VaultV2(address(vault1)).syncOwedSlash(1);

        uint256 burnerBefore = collateral.balanceOf(vault1.burner());
        vm.prank(vault1.slasher());
        uint256 slashedAmount = VaultV2(address(vault1)).syncOwedSlash(5);

        assertEq(slashedAmount, 5);
        assertEq(collateral.balanceOf(vault1.burner()) - burnerBefore, 5);
    }

    function test_VaultV2FeeOnTransferAllocationReverts() public {
        FeeOnTransferToken feeOnTransferCollateral = new FeeOnTransferToken("FeeOnTransferCoverage");
        MockCoverageAdapter adapter = new MockCoverageAdapter();
        adapterRegistry.whitelistAdapter(address(adapter));

        IVaultV2 feeVault = _createVault(address(feeOnTransferCollateral));
        feeOnTransferCollateral.approve(address(feeVault), 100);
        feeVault.deposit(address(this), 100);

        vm.startPrank(alice);
        VaultV2(address(feeVault)).setAdapterLimit(address(adapter), 100);
        vm.warp(VaultV2(address(feeVault)).adapterAllowedAt(address(adapter)));
        VaultV2(address(feeVault)).setAdapterLimit(address(adapter), 100);
        vm.expectRevert(IVaultV2.FeeOnTransferNotSupported.selector);
        feeVault.allocateAdapter(address(adapter), 10);
        vm.stopPrank();
    }

    function test_VaultV2InitializationEntityAndMigrateFailureReverts() public {
        vm.expectRevert(IVaultV2.InvalidCollateral.selector);
        this.createVaultForInitializationCoverageTest(address(0), 1 days, 2 days, address(0xBEEF));

        vm.expectRevert(IVaultV2.TooLongDuration.selector);
        this.createVaultForInitializationCoverageTest(address(collateral), 0, 2 days, address(0xBEEF));

        vm.expectRevert(IVaultV2.InvalidDepositorToWhitelist.selector);
        this.createVaultForInitializationCoverageTest(address(collateral), 1 days, 2 days, address(0));

        address initializedDelegator = vault1.delegator();
        vm.expectRevert(IVaultV2.DelegatorAlreadyInitialized.selector);
        VaultV2(address(vault1)).setDelegator(initializedDelegator);

        address initializedSlasher = vault1.slasher();
        vm.expectRevert(IVaultV2.SlasherAlreadyInitialized.selector);
        VaultV2(address(vault1)).setSlasher(initializedSlasher);

        IVaultV2 bareVault = _createBareVault(address(collateral));
        vm.expectRevert(IVaultV2.InvalidDelegator.selector);
        VaultV2(address(bareVault)).setDelegator(address(1));

        vm.expectRevert(IVaultV2.InvalidSlasher.selector);
        VaultV2(address(bareVault)).setSlasher(address(1));

        VaultV2MigrateFailureHarness harness =
            new VaultV2MigrateFailureHarness(address(new MockVaultV2MigrateReverter()));

        vm.expectRevert("migrate failed");
        harness.exposeMigrate();
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
        vm.expectRevert(IAdapter.NotCurator.selector);
        morphoAdapter.setMorphoVault(address(vault1), address(morphoVault));
    }

    function test_AdapterRecoverRejectsNonCurator() public {
        vm.expectRevert(IAdapter.NotCurator.selector);
        aaveAdapter.recover(address(vault1), 1);

        vm.expectRevert(IAdapter.NotCurator.selector);
        morphoAdapter.recover(address(vault1), 1);
    }

    function test_AdapterRecoverRejectsZeroAmountForCurator() public {
        vm.prank(curator);
        vm.expectRevert(IAdapter.ZeroAmount.selector);
        aaveAdapter.recover(address(vault1), 0);
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

    function test_MorphoAllocationUsesDeterministicVaultAccount() public {
        _configureMorpho(address(vault1));
        _allocateMorpho(vault1, 80, 80);

        address account = morphoAdapter.getAccount(address(vault1));

        assertEq(morphoVault.balanceOf(account), 80);
        assertEq(morphoVault.balanceOf(address(morphoAdapter)), 0);
        assertEq(morphoAdapter.getAssets(address(vault1)), 80);
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

    function test_MorphoSetVaultCanReplaceShareDustWithNoRedeemableAssets() public {
        MockMorphoVaultHarness otherMorphoVault = new MockMorphoVaultHarness(address(collateral), morphoAdapterRegistry);
        morphoVaultFactory.setVault(address(otherMorphoVault), true);

        _configureMorpho(address(vault1));
        _allocateMorpho(vault1, 80, 80);

        address account = morphoAdapter.getAccount(address(vault1));
        deal(address(collateral), address(morphoVault), 0);

        assertEq(morphoVault.balanceOf(account), 80);
        assertEq(morphoAdapter.getAssets(address(vault1)), 0);

        vm.prank(curator);
        morphoAdapter.setMorphoVault(address(vault1), address(otherMorphoVault));

        assertEq(morphoAdapter.morphoVaults(address(vault1)), address(otherMorphoVault));
        assertEq(morphoAdapter.getAssets(address(vault1)), 0);

        collateral.approve(address(morphoVault), 10);
        morphoVault.donateYield(10);
        vm.prank(curator);
        morphoAdapter.setMorphoVault(address(vault1), address(morphoVault));

        assertEq(morphoAdapter.getAssets(address(vault1)), 10);
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

    function test_MorphoDepositRejectsNonSelfCall() public {
        vm.startPrank(alice);
        (bool success, bytes memory returnData) = address(morphoAdapter)
            .call(
                abi.encodeCall(
                    MorphoVaultV2Adapter.deposit, (address(morphoVault), 1, morphoAdapter.getAccount(address(vault1)))
                )
            );
        vm.stopPrank();

        assertFalse(success);
        assertEq(bytes4(returnData), IMorphoVaultV2Adapter.NotSelf.selector);
    }

    function test_MorphoDepositRejectsMulticallRoute() public {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(
            MorphoVaultV2Adapter.deposit, (address(morphoVault), 1, morphoAdapter.getAccount(address(vault1)))
        );

        vm.prank(alice);
        vm.expectRevert(IMorphoVaultV2Adapter.NotSelf.selector);
        morphoAdapter.multicall(data);
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
        MorphoVaultV2Adapter adapter = _deployMorphoAdapter(address(revertingRewards));
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

    function test_MorphoAllocateRevertsWhenSkimCannotClearExistingYield() public {
        MockMorphoVaultConfigurable failingMorphoVault =
            new MockMorphoVaultConfigurable(address(collateral), morphoAdapterRegistry);
        morphoVaultFactory.setVault(address(failingMorphoVault), true);

        vm.prank(curator);
        morphoAdapter.setMorphoVault(address(vault1), address(failingMorphoVault));

        _allocateMorpho(vault1, 100, 80);

        collateral.approve(address(failingMorphoVault), 20);
        failingMorphoVault.donateYield(20);
        failingMorphoVault.setRevertOnWithdraw(true);

        uint256 vaultBalanceBefore = collateral.balanceOf(address(vault1));
        uint256 adapterAllocatedBefore = vault1.adapterAllocated(address(morphoAdapter));
        uint256 globalAllocatedBefore = morphoAdapter.globalAllocated(address(collateral));
        uint256 skimmableBefore = morphoAdapter.skimmable(address(vault1));

        vm.prank(alice);
        vm.expectRevert();
        vault1.allocateAdapter(address(morphoAdapter), 10);

        assertEq(collateral.balanceOf(address(vault1)), vaultBalanceBefore);
        assertEq(vault1.adapterAllocated(address(morphoAdapter)), adapterAllocatedBefore);
        assertEq(morphoAdapter.globalAllocated(address(collateral)), globalAllocatedBefore);
        assertEq(morphoAdapter.skimmable(address(vault1)), skimmableBefore);
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
        assertGe(morphoAdapter.skimmable(address(vault2)) + 1, vault2SkimmableBefore);
    }

    function test_MorphoShareBalanceIncreaseOnAdapterDoesNotAffectVaultAccounting() public {
        _configureMorpho(address(vault1));
        _configureMorpho(address(vault2));

        _allocateMorpho(vault1, 100, 100);
        _allocateMorpho(vault2, 100, 100);

        collateral.approve(address(morphoVault), 10_000);
        uint256 shares = morphoVault.deposit(10_000, address(morphoAdapter));

        assertEq(morphoVault.balanceOf(address(morphoAdapter)), shares);
        assertEq(morphoAdapter.getAssets(address(vault1)), 100);
        assertEq(vault2.adapterAllocated(address(morphoAdapter)), 100);
        assertEq(morphoAdapter.getAssets(address(vault2)), 100);
        assertEq(morphoAdapter.deallocatable(address(vault2)), 100);

        uint256 victimRecovered = _deallocateFromVault(vault2, address(morphoAdapter), 100);

        assertEq(victimRecovered, 100);
        assertEq(vault2.adapterAllocated(address(morphoAdapter)), 0);
    }

    function test_MorphoSmallAllocationReturnsFundsWhenDepositWouldMintZeroShares() public {
        _configureMorpho(address(vault1));
        _configureMorpho(address(vault2));

        _allocateMorpho(vault1, 100, 100);

        collateral.approve(address(morphoVault), 1000);
        morphoVault.donateYield(1000);

        uint256 vault1SkimmableBefore = morphoAdapter.skimmable(address(vault1));
        uint256 vault2BalanceBefore = collateral.balanceOf(address(vault2));
        uint256 globalAllocatedBefore = morphoAdapter.globalAllocated(address(collateral));

        _allocateMorpho(vault2, 1, 1);

        assertEq(collateral.balanceOf(address(vault2)), vault2BalanceBefore + 1);
        assertEq(vault2.adapterAllocated(address(morphoAdapter)), 0);
        assertEq(morphoAdapter.globalAllocated(address(collateral)), globalAllocatedBefore);
        assertEq(morphoAdapter.getAssets(address(vault2)), 0);
        assertEq(morphoAdapter.deallocatable(address(vault2)), 0);
        assertEq(morphoAdapter.skimmable(address(vault1)), vault1SkimmableBefore);
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

    function test_MorphoDeallocateAllowsLossAtBuffer() public {
        uint256 liveAssets = DEALLOCATE_BUFFER;
        uint256 allocated = liveAssets + DEALLOCATE_BUFFER;

        _configureMorpho(address(vault1));
        _allocateMorpho(vault1, allocated, allocated);

        deal(address(collateral), address(morphoVault), liveAssets);

        assertEq(morphoAdapter.getAssets(address(vault1)), liveAssets);
        assertEq(morphoAdapter.deallocatable(address(vault1)), liveAssets);

        uint256 deallocated = _deallocateFromVault(vault1, address(morphoAdapter), allocated);

        assertEq(deallocated, liveAssets);
        assertEq(collateral.balanceOf(address(vault1)), liveAssets);
        assertEq(collateral.balanceOf(address(morphoVault)), 0);
        assertEq(vault1.adapterAllocated(address(morphoAdapter)), DEALLOCATE_BUFFER);
        assertEq(morphoAdapter.globalAllocated(address(collateral)), DEALLOCATE_BUFFER);
        assertEq(morphoAdapter.getAssets(address(vault1)), 0);
        assertEq(morphoAdapter.deallocatable(address(vault1)), 0);
    }

    function test_MorphoForceDeallocateWithdrawsWhenLossExceedsBuffer() public {
        uint256 liveAssets = DEALLOCATE_BUFFER;
        uint256 allocated = liveAssets + DEALLOCATE_BUFFER + 1;

        _configureMorpho(address(vault1));
        _allocateMorpho(vault1, allocated, allocated);

        deal(address(collateral), address(morphoVault), liveAssets);

        assertEq(morphoAdapter.getAssets(address(vault1)), liveAssets);
        assertEq(morphoAdapter.deallocatable(address(vault1)), 0);

        vm.prank(curator);
        uint256 deallocated = IMorphoVaultV2Adapter(address(morphoAdapter)).forceDeallocate(address(vault1), allocated);

        assertEq(deallocated, liveAssets);
        assertEq(collateral.balanceOf(address(vault1)), liveAssets);
        assertEq(collateral.balanceOf(address(morphoVault)), 0);
        assertEq(vault1.adapterAllocated(address(morphoAdapter)), DEALLOCATE_BUFFER + 1);
        assertEq(morphoAdapter.globalAllocated(address(collateral)), DEALLOCATE_BUFFER + 1);
        assertEq(morphoAdapter.getAssets(address(vault1)), 0);
        assertEq(morphoAdapter.deallocatable(address(vault1)), 0);
    }

    function test_MorphoRecoverReturnsCuratorFundsToVaultAndReducesAllocation() public {
        _configureMorpho(address(vault1));
        morphoAdapter.setGlobalLimit(address(collateral), 100);
        _allocateMorpho(vault1, 80, 80);
        assertEq(morphoAdapter.allocatable(address(vault1)), 20);

        deal(address(collateral), curator, 10);

        vm.startPrank(curator);
        collateral.approve(address(morphoAdapter), 10);
        morphoAdapter.recover(address(vault1), 10);
        vm.stopPrank();

        assertEq(collateral.balanceOf(address(vault1)), 20);
        assertEq(collateral.balanceOf(address(morphoAdapter)), 0);
        assertEq(vault1.adapterAllocated(address(morphoAdapter)), 70);
        assertEq(morphoAdapter.globalAllocated(address(collateral)), 70);
        assertEq(morphoAdapter.getAssets(address(vault1)), 70);
        assertEq(morphoAdapter.allocatable(address(vault1)), 30);
        assertEq(morphoAdapter.deallocatable(address(vault1)), 70);
        assertEq(morphoAdapter.skimmable(address(vault1)), 0);
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

        assertEq(deallocated, 0);
        assertEq(collateral.balanceOf(address(vault1)), 0);
        assertEq(collateral.balanceOf(address(morphoAdapter)), 10);
        assertEq(morphoAdapter.globalAllocated(address(collateral)), 80);
        assertEq(vault1.adapterAllocated(address(morphoAdapter)), 80);
        assertEq(morphoAdapter.deallocatable(address(vault1)), 80);
    }

    function test_AaveUsesPoolReserveForVaultCollateral() public view {
        assertEq(aaveAdapter.aToken(address(vault1)), address(aToken));
    }

    function test_AaveAllocationUsesDeterministicVaultAccount() public {
        _allocateAave(vault1, 80, 80);

        address account = aaveAdapter.getAccount(address(vault1));

        assertEq(aToken.balanceOf(account), 80);
        assertEq(aToken.balanceOf(address(aaveAdapter)), 0);
        assertEq(aaveAdapter.getAssets(address(vault1)), 80);
    }

    function test_AaveDeallocatableUsesVirtualUnderlyingBalance() public {
        _allocateAave(vault1, 80, 80);

        aavePool.setVirtualUnderlyingBalance(30);

        assertEq(aaveAdapter.deallocatable(address(vault1)), 30);
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
        AaveV3Adapter adapter = _deployAaveAdapter(address(revertingRewards));
        adapter.initialize();
        adapter.setGlobalLimit(address(collateral), type(uint256).max);
        adapterRegistry.whitelistAdapter(address(adapter));

        _allocateAave(adapter, vault1, 80, 80);

        collateral.approve(address(aavePool), 20);
        aavePool.accrueYield(adapter.getAccount(address(vault1)), 20);

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

        address account = aaveAdapter.getAccount(address(vault1));
        assertEq(collateral.balanceOf(address(aaveAdapter)), 0);
        assertEq(collateral.balanceOf(address(aToken)), 80);
        assertEq(aToken.balanceOf(account), 80);
        assertEq(aToken.balanceOf(address(aaveAdapter)), 0);
        assertEq(aaveAdapter.skimmable(address(vault1)), 0);
        assertEq(aaveAdapter.deallocatable(address(vault1)), 80);

        collateral.approve(address(aavePool), 20);
        aavePool.accrueYield(account, 20);

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
        aavePool.accrueYield(aaveAdapter.getAccount(address(vault1)), 20);
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

    function test_AaveAllocateRevertsWhenSkimCannotClearExistingYield() public {
        _allocateAave(vault1, 100, 80);

        collateral.approve(address(aavePool), 20);
        aavePool.accrueYield(aaveAdapter.getAccount(address(vault1)), 20);
        aavePool.setRevertOnWithdraw(true);

        uint256 vaultBalanceBefore = collateral.balanceOf(address(vault1));
        uint256 adapterAllocatedBefore = vault1.adapterAllocated(address(aaveAdapter));
        uint256 globalAllocatedBefore = aaveAdapter.globalAllocated(address(collateral));
        uint256 skimmableBefore = aaveAdapter.skimmable(address(vault1));

        vm.prank(alice);
        vm.expectRevert(IAdapter.SkimFailed.selector);
        vault1.allocateAdapter(address(aaveAdapter), 10);

        assertEq(collateral.balanceOf(address(vault1)), vaultBalanceBefore);
        assertEq(vault1.adapterAllocated(address(aaveAdapter)), adapterAllocatedBefore);
        assertEq(aaveAdapter.globalAllocated(address(collateral)), globalAllocatedBefore);
        assertEq(aaveAdapter.skimmable(address(vault1)), skimmableBefore);
    }

    function test_AaveSkimDoesNotDiluteOtherVault() public {
        _allocateAave(vault1, 100, 100);
        _allocateAave(vault2, 100, 100);

        collateral.approve(address(aavePool), 20);
        aavePool.accrueYield(aaveAdapter.getAccount(address(vault1)), 20);

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

    function test_AaveATokenTransferToOneAccountDoesNotAffectAnotherVault() public {
        _allocateAave(vault1, 100, 100);
        _allocateAave(vault2, 100, 100);

        collateral.approve(address(aavePool), 10_000);
        aavePool.supply(address(collateral), 10_000, address(this), 0);
        aToken.transfer(aaveAdapter.getAccount(address(vault1)), 10_000);

        assertGt(aaveAdapter.skimmable(address(vault1)), 0);
        assertEq(vault2.adapterAllocated(address(aaveAdapter)), 100);
        assertEq(aaveAdapter.getAssets(address(vault2)), 100);
        assertEq(aaveAdapter.deallocatable(address(vault2)), 100);

        uint256 victimRecovered = _deallocateFromVault(vault2, address(aaveAdapter), 100);

        assertEq(victimRecovered, 100);
        assertEq(vault2.adapterAllocated(address(aaveAdapter)), 0);
    }

    function test_AaveDeallocateCapsToVaultAllocation() public {
        _allocateAave(vault1, 80, 50);

        uint256 deallocated = _deallocateFromVault(vault1, address(aaveAdapter), 70);

        assertEq(deallocated, 50);
        assertEq(collateral.balanceOf(address(vault1)), 80);
        assertEq(aToken.balanceOf(address(aaveAdapter)), 0);
        assertEq(aaveAdapter.deallocatable(address(vault1)), 0);
    }

    function test_AaveRecoverReturnsCuratorFundsToVaultAndReducesAllocation() public {
        aaveAdapter.setGlobalLimit(address(collateral), 100);
        _allocateAave(vault1, 80, 80);
        assertEq(aaveAdapter.allocatable(address(vault1)), 20);

        deal(address(collateral), curator, 10);

        vm.startPrank(curator);
        collateral.approve(address(aaveAdapter), 10);
        aaveAdapter.recover(address(vault1), 10);
        vm.stopPrank();

        assertEq(collateral.balanceOf(address(vault1)), 20);
        assertEq(collateral.balanceOf(address(aaveAdapter)), 0);
        assertEq(vault1.adapterAllocated(address(aaveAdapter)), 70);
        assertEq(aaveAdapter.globalAllocated(address(collateral)), 70);
        assertEq(aaveAdapter.getAssets(address(vault1)), 70);
        assertEq(aaveAdapter.allocatable(address(vault1)), 30);
        assertEq(aaveAdapter.deallocatable(address(vault1)), 70);
        assertEq(aaveAdapter.skimmable(address(vault1)), 0);
    }

    function test_AaveDeallocateReturnsIdleBalanceWhenWithdrawFails() public {
        _allocateAave(vault1, 80, 80);

        collateral.transfer(address(aaveAdapter), 10);
        aavePool.setRevertOnWithdraw(true);

        uint256 deallocated = _deallocateFromVault(vault1, address(aaveAdapter), 30);

        assertEq(deallocated, 0);
        assertEq(collateral.balanceOf(address(vault1)), 0);
        assertEq(collateral.balanceOf(address(aaveAdapter)), 10);
        assertEq(aaveAdapter.globalAllocated(address(collateral)), 80);
        assertEq(vault1.adapterAllocated(address(aaveAdapter)), 80);
        assertEq(aaveAdapter.deallocatable(address(vault1)), 80);
    }

    function _configureMorpho(address vaultAddress) internal {
        _configureMorpho(morphoAdapter, vaultAddress, address(morphoVault));
    }

    function _configureMorpho(MorphoVaultV2Adapter adapter, address vaultAddress, address morphoVaultAddress) internal {
        vm.prank(curator);
        adapter.setMorphoVault(vaultAddress, morphoVaultAddress);
    }

    function _deployAaveAdapter(address rewards_) internal returns (AaveV3Adapter adapter) {
        uint256 nonce = vm.getNonce(address(this));
        address predictedAdapter = vm.computeCreateAddress(address(this), nonce + 2);
        address beacon =
            address(new UpgradeableBeacon(address(0), address(new AaveV3Account(address(aavePool), predictedAdapter))));

        adapter =
            new AaveV3Adapter(address(aavePool), address(curatorRegistry), rewards_, address(vaultFactory), beacon);
    }

    function _deployMorphoAdapter(address rewards_) internal returns (MorphoVaultV2Adapter adapter) {
        uint256 nonce = vm.getNonce(address(this));
        address predictedAdapter = vm.computeCreateAddress(address(this), nonce + 2);
        address beacon = address(new UpgradeableBeacon(address(0), address(new MorphoVaultV2Account(predictedAdapter))));

        adapter = new MorphoVaultV2Adapter(
            address(morphoVaultFactory),
            morphoAdapterRegistry,
            address(curatorRegistry),
            rewards_,
            address(vaultFactory),
            beacon
        );
    }

    function _depositIntoVault(IVaultV2 vault_, Token collateral_, uint256 amount) internal {
        collateral_.approve(address(vault_), amount);
        vault_.deposit(address(this), amount);
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

    function createVaultForInvalidAdaptersAllowDelayTest(
        address collateral_,
        address[] memory initialAdapters,
        uint48 adaptersAllowDelay
    ) external returns (IVaultV2 vault_) {
        return _createVault(collateral_, initialAdapters, adaptersAllowDelay);
    }

    function createVaultForDuplicateAdaptersTest(address collateral_, address[] memory initialAdapters)
        external
        returns (IVaultV2 vault_)
    {
        return _createVault(collateral_, initialAdapters, 2 days);
    }

    function createVaultForInitializationCoverageTest(
        address collateral_,
        uint48 epochDuration_,
        uint48 adaptersAllowDelay_,
        address depositorToWhitelist_
    ) external returns (IVaultV2 vault_) {
        return _createVault(collateral_, new address[](0), epochDuration_, adaptersAllowDelay_, depositorToWhitelist_);
    }

    function _createVault(address collateral_) internal returns (IVaultV2 vault_) {
        address[] memory initialAdapters = new address[](0);
        return _createVault(collateral_, initialAdapters, 2 days);
    }

    function _createVault(address collateral_, address[] memory initialAdapters, uint48 adaptersAllowDelay)
        internal
        returns (IVaultV2 vault_)
    {
        return _createVault(collateral_, initialAdapters, 1 days, adaptersAllowDelay, address(0xBEEF));
    }

    function _createVault(
        address collateral_,
        address[] memory initialAdapters,
        uint48 epochDuration,
        uint48 adaptersAllowDelay,
        address depositorToWhitelist
    ) internal returns (IVaultV2 vault_) {
        bytes memory vaultParams = abi.encode(
            IVaultV2.InitParams({
                name: "Test",
                symbol: "TEST",
                collateral: collateral_,
                burner: address(0xdEaD),
                epochDuration: epochDuration,
                adapters: initialAdapters,
                adaptersAllowDelay: adaptersAllowDelay,
                depositWhitelist: false,
                depositorToWhitelist: depositorToWhitelist,
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

    function _createBareVault(address collateral_) internal returns (IVaultV2 vault_) {
        address[] memory initialAdapters = new address[](0);
        bytes memory vaultParams = abi.encode(
            IVaultV2.InitParams({
                name: "Bare",
                symbol: "BARE",
                collateral: collateral_,
                burner: address(0xdEaD),
                epochDuration: 1 days,
                adapters: initialAdapters,
                adaptersAllowDelay: 2 days,
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

        vault_ = IVaultV2(vaultFactory.create(vaultFactory.lastVersion(), address(0xdEaD), vaultParams));
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
