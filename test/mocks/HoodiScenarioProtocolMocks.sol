// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IRewards} from "../../src/interfaces/vault/IRewards.sol";
import {MockMorphoVault} from "./MockMorphoVault.sol";

interface IVaultDonateHoodiScenario {
    function donate(uint256 amount) external;
}

interface IVaultCollateralHoodiScenario {
    function collateral() external view returns (address);
}

contract MockMorphoVaultFactory is Ownable {
    mapping(address vault => bool status) public isVaultV2;

    address public immutable adapterRegistry;

    constructor(address adapterRegistry_, address owner_) Ownable(owner_) {
        adapterRegistry = adapterRegistry_;
    }

    function createVault(address asset) external onlyOwner returns (address implementation, address vault) {
        vault = address(new MockMorphoVaultHarness(asset, adapterRegistry));
        implementation = vault;
        isVaultV2[vault] = true;
    }

    function setVault(address vault, bool status) external onlyOwner {
        isVaultV2[vault] = status;
    }
}

contract MockHoodiTokenUpgradeable is Initializable, ERC20Upgradeable {
    function initialize(string memory name_, address recipient) external initializer {
        __ERC20_init(name_, "");
        _mint(recipient, 1_000_000 * 10 ** decimals());
    }
}

contract MockMorphoVaultFactoryUpgradeable is Initializable, OwnableUpgradeable {
    mapping(address vault => bool status) public isVaultV2;

    address public adapterRegistry;
    address public proxyOwner;

    function initialize(address adapterRegistry_, address proxyOwner_) external initializer {
        __Ownable_init(proxyOwner_);
        adapterRegistry = adapterRegistry_;
        proxyOwner = proxyOwner_;
    }

    function createVault(address asset) external onlyOwner returns (address implementation, address vault) {
        implementation = address(new MockMorphoVaultHarnessUpgradeable());
        vault = address(
            new TransparentUpgradeableProxy(
                implementation,
                proxyOwner,
                abi.encodeCall(MockMorphoVaultHarnessUpgradeable.initialize, (asset, adapterRegistry))
            )
        );
        isVaultV2[vault] = true;
    }

    function setVault(address vault, bool status) external onlyOwner {
        isVaultV2[vault] = status;
    }
}

interface IMorphoAdapterRegistry {
    function isInRegistry(address account) external view returns (bool);
}

contract MockMorphoAdapterRegistry is Ownable, IMorphoAdapterRegistry {
    mapping(address account => bool status) internal _isInRegistry;

    constructor(address owner_) Ownable(owner_) {}

    function isInRegistry(address account) external view override returns (bool) {
        return _isInRegistry[account];
    }

    function setInRegistry(address account, bool status) external onlyOwner {
        _isInRegistry[account] = status;
    }
}

contract MockMorphoAdapterRegistryUpgradeable is Initializable, OwnableUpgradeable, IMorphoAdapterRegistry {
    mapping(address account => bool status) internal _isInRegistry;

    function initialize(address owner_) external initializer {
        __Ownable_init(owner_);
    }

    function isInRegistry(address account) external view override returns (bool) {
        return _isInRegistry[account];
    }

    function setInRegistry(address account, bool status) external onlyOwner {
        _isInRegistry[account] = status;
    }
}

contract MockRewardsDistributor is IRewards, ReentrancyGuard {
    event Donate(address indexed vault, uint256 amount);

    uint256 public donationRewardCalls;
    address public lastDonationVault;
    uint256 public lastDonationAmount;
    bool public pullIntoVault;

    constructor(bool pullIntoVault_) {
        pullIntoVault = pullIntoVault_;
    }

    function setPullIntoVault(bool value) external {
        pullIntoVault = value;
    }

    function distributeDonationRewards(address vault, uint256 amount) external nonReentrant {
        ++donationRewardCalls;
        lastDonationVault = vault;
        lastDonationAmount = amount;

        if (pullIntoVault) {
            IERC20 collateral = IERC20(IVaultCollateralHoodiScenario(vault).collateral());
            if (!collateral.transferFrom(msg.sender, address(this), amount)) {
                revert();
            }
            collateral.approve(vault, amount);
            IVaultDonateHoodiScenario(vault).donate(amount);
        }

        emit Donate(vault, amount);
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

contract MockMorphoVaultHarnessUpgradeable is Initializable {
    IERC20 public asset;
    address public adapterRegistry;

    uint256 public totalShares;
    mapping(address account => uint256 shares) public sharesOf;

    function initialize(address asset_, address adapterRegistry_) external initializer {
        asset = IERC20(asset_);
        adapterRegistry = adapterRegistry_;
    }

    function liquidityAdapter() external pure returns (address) {
        return address(0);
    }

    function abdicated(bytes4) external pure returns (bool) {
        return true;
    }

    function maxWithdraw(address owner) external view returns (uint256) {
        if (totalShares == 0) {
            return 0;
        }
        return sharesOf[owner] * asset.balanceOf(address(this)) / totalShares;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        uint256 totalAssetsBefore = asset.balanceOf(address(this));
        asset.transferFrom(msg.sender, address(this), assets);

        if (totalShares == 0 || totalAssetsBefore == 0) {
            shares = assets;
        } else {
            shares = assets * totalShares / totalAssetsBefore;
        }

        sharesOf[receiver] += shares;
        totalShares += shares;
        return shares;
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
        return shares;
    }

    function balanceOf(address account) external view virtual returns (uint256) {
        return sharesOf[account];
    }

    function previewRedeem(uint256 shares) external view virtual returns (uint256) {
        if (totalShares == 0) {
            return 0;
        }
        return shares * asset.balanceOf(address(this)) / totalShares;
    }

    function donateYield(uint256 amount) external {
        asset.transferFrom(msg.sender, address(this), amount);
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

contract MockAaveAToken is ERC20, Ownable {
    address public immutable UNDERLYING_ASSET_ADDRESS;
    address public pool;

    constructor(address underlyingAsset, address owner_) ERC20("Mock AToken", "maToken") Ownable(owner_) {
        UNDERLYING_ASSET_ADDRESS = underlyingAsset;
    }

    function setPool(address newPool) external onlyOwner {
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

contract MockAaveATokenUpgradeable is Initializable, ERC20Upgradeable, OwnableUpgradeable {
    address public UNDERLYING_ASSET_ADDRESS;
    address public pool;

    function initialize(address underlyingAsset, address owner_) external initializer {
        __ERC20_init("Mock AToken", "maToken");
        __Ownable_init(owner_);
        UNDERLYING_ASSET_ADDRESS = underlyingAsset;
    }

    function setPool(address newPool) external onlyOwner {
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

contract MockAavePoolAddressesProvider is Ownable {
    address public pool;
    address public poolDataProvider;

    constructor(address owner_) Ownable(owner_) {}

    function setPool(address pool_) external onlyOwner {
        pool = pool_;
    }

    function getPool() external view returns (address) {
        return pool;
    }

    function setPoolDataProvider(address poolDataProvider_) external onlyOwner {
        poolDataProvider = poolDataProvider_;
    }

    function getPoolDataProvider() external view returns (address) {
        return poolDataProvider;
    }
}

contract MockAavePoolAddressesProviderUpgradeable is Initializable, OwnableUpgradeable {
    address public pool;
    address public poolDataProvider;

    function initialize(address owner_) external initializer {
        __Ownable_init(owner_);
    }

    function setPool(address pool_) external onlyOwner {
        pool = pool_;
    }

    function getPool() external view returns (address) {
        return pool;
    }

    function setPoolDataProvider(address poolDataProvider_) external onlyOwner {
        poolDataProvider = poolDataProvider_;
    }

    function getPoolDataProvider() external view returns (address) {
        return poolDataProvider;
    }
}

contract MockAavePoolDataProvider is Ownable {
    mapping(address asset => address aToken) public aTokens;

    constructor(address owner_) Ownable(owner_) {}

    function setReserveToken(address asset, address aToken) external onlyOwner {
        aTokens[asset] = aToken;
    }

    function getReserveTokensAddresses(address asset) external view returns (address aToken, address, address) {
        return (aTokens[asset], address(0), address(0));
    }
}

contract MockAavePoolDataProviderUpgradeable is Initializable, OwnableUpgradeable {
    mapping(address asset => address aToken) public aTokens;

    function initialize(address owner_) external initializer {
        __Ownable_init(owner_);
    }

    function setReserveToken(address asset, address aToken) external onlyOwner {
        aTokens[asset] = aToken;
    }

    function getReserveTokensAddresses(address asset) external view returns (address aToken, address, address) {
        return (aTokens[asset], address(0), address(0));
    }
}

contract MockAavePool is Ownable {
    mapping(address asset => MockAaveAToken aToken) public aTokens;
    address public immutable ADDRESSES_PROVIDER;

    bool public revertOnSupply;
    bool public revertOnWithdraw;
    bool public useVirtualUnderlyingBalanceOverride;
    uint128 public virtualUnderlyingBalanceOverride;

    constructor(address asset_, address aToken_, address addressesProvider_, address owner_) Ownable(owner_) {
        ADDRESSES_PROVIDER = addressesProvider_;
        aTokens[asset_] = MockAaveAToken(aToken_);
    }

    function setReserveToken(address asset_, address aToken_) external onlyOwner {
        aTokens[asset_] = MockAaveAToken(aToken_);
    }

    function getReserveAToken(address asset_) external view returns (address) {
        return address(aTokens[asset_]);
    }

    function getVirtualUnderlyingBalance(address asset_) external view returns (uint128) {
        MockAaveAToken aToken = aTokens[asset_];
        if (address(aToken) == address(0)) {
            return 0;
        }
        if (useVirtualUnderlyingBalanceOverride) {
            return virtualUnderlyingBalanceOverride;
        }
        return uint128(IERC20(asset_).balanceOf(address(aToken)));
    }

    function setRevertOnSupply(bool value) external onlyOwner {
        revertOnSupply = value;
    }

    function setRevertOnWithdraw(bool value) external onlyOwner {
        revertOnWithdraw = value;
    }

    function setVirtualUnderlyingBalance(uint128 value) external onlyOwner {
        useVirtualUnderlyingBalanceOverride = true;
        virtualUnderlyingBalanceOverride = value;
    }

    function clearVirtualUnderlyingBalanceOverride() external onlyOwner {
        useVirtualUnderlyingBalanceOverride = false;
    }

    function supply(address asset_, uint256 amount, address onBehalfOf, uint16) external {
        MockAaveAToken aToken = aTokens[asset_];
        require(address(aToken) != address(0), "invalid asset");
        require(!revertOnSupply, "supply failed");

        IERC20(asset_).transferFrom(msg.sender, address(aToken), amount);
        aToken.mint(onBehalfOf, amount);
    }

    function withdraw(address asset_, uint256 amount, address to) external returns (uint256 withdrawn) {
        MockAaveAToken aToken = aTokens[asset_];
        require(address(aToken) != address(0), "invalid asset");
        require(!revertOnWithdraw, "withdraw failed");

        uint256 balance = aToken.balanceOf(msg.sender);
        uint256 liquidity = IERC20(asset_).balanceOf(address(aToken));
        withdrawn = amount > balance ? balance : amount;
        withdrawn = withdrawn > liquidity ? liquidity : withdrawn;
        if (withdrawn > 0) {
            aToken.burn(msg.sender, withdrawn);
            aToken.transferUnderlying(to, withdrawn);
        }
    }

    function accrueYield(address asset_, address account, uint256 amount) external onlyOwner {
        MockAaveAToken aToken = aTokens[asset_];
        require(address(aToken) != address(0), "invalid asset");
        IERC20(asset_).transferFrom(msg.sender, address(aToken), amount);
        aToken.mint(account, amount);
    }
}

contract MockAavePoolUpgradeable is Initializable, OwnableUpgradeable {
    mapping(address asset => MockAaveATokenUpgradeable aToken) public aTokens;
    address public ADDRESSES_PROVIDER;

    bool public revertOnSupply;
    bool public revertOnWithdraw;
    bool public useVirtualUnderlyingBalanceOverride;
    uint128 public virtualUnderlyingBalanceOverride;

    function initialize(address addressesProvider_, address owner_) external initializer {
        __Ownable_init(owner_);
        ADDRESSES_PROVIDER = addressesProvider_;
    }

    function setReserveToken(address asset_, address aToken_) external onlyOwner {
        aTokens[asset_] = MockAaveATokenUpgradeable(aToken_);
    }

    function getReserveAToken(address asset_) external view returns (address) {
        return address(aTokens[asset_]);
    }

    function getVirtualUnderlyingBalance(address asset_) external view returns (uint128) {
        MockAaveATokenUpgradeable aToken = aTokens[asset_];
        if (address(aToken) == address(0)) {
            return 0;
        }
        if (useVirtualUnderlyingBalanceOverride) {
            return virtualUnderlyingBalanceOverride;
        }
        return uint128(IERC20(asset_).balanceOf(address(aToken)));
    }

    function setRevertOnSupply(bool value) external onlyOwner {
        revertOnSupply = value;
    }

    function setRevertOnWithdraw(bool value) external onlyOwner {
        revertOnWithdraw = value;
    }

    function setVirtualUnderlyingBalance(uint128 value) external onlyOwner {
        useVirtualUnderlyingBalanceOverride = true;
        virtualUnderlyingBalanceOverride = value;
    }

    function clearVirtualUnderlyingBalanceOverride() external onlyOwner {
        useVirtualUnderlyingBalanceOverride = false;
    }

    function supply(address asset_, uint256 amount, address onBehalfOf, uint16) external {
        MockAaveATokenUpgradeable aToken = aTokens[asset_];
        require(address(aToken) != address(0), "invalid asset");
        require(!revertOnSupply, "supply failed");

        IERC20(asset_).transferFrom(msg.sender, address(aToken), amount);
        aToken.mint(onBehalfOf, amount);
    }

    function withdraw(address asset_, uint256 amount, address to) external returns (uint256 withdrawn) {
        MockAaveATokenUpgradeable aToken = aTokens[asset_];
        require(address(aToken) != address(0), "invalid asset");
        require(!revertOnWithdraw, "withdraw failed");

        uint256 balance = aToken.balanceOf(msg.sender);
        uint256 liquidity = IERC20(asset_).balanceOf(address(aToken));
        withdrawn = amount > balance ? balance : amount;
        withdrawn = withdrawn > liquidity ? liquidity : withdrawn;
        if (withdrawn > 0) {
            aToken.burn(msg.sender, withdrawn);
            aToken.transferUnderlying(to, withdrawn);
        }
    }

    function accrueYield(address asset_, address account, uint256 amount) external onlyOwner {
        MockAaveATokenUpgradeable aToken = aTokens[asset_];
        require(address(aToken) != address(0), "invalid asset");
        IERC20(asset_).transferFrom(msg.sender, address(aToken), amount);
        aToken.mint(account, amount);
    }
}
