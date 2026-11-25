// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {CentrifugeAccount} from "../../../src/contracts/adapters/ll-adapter/CentrifugeAccount.sol";
import {AsyncRedeemAccount} from "../../../src/contracts/adapters/ll-adapter/common/AsyncRedeemAccount.sol";
import {PRIME_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/PRIME_Account.sol";
import {FigureSubAccount} from "../../../src/contracts/adapters/ll-adapter/FigureAccount.sol";
import {deJAAA_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/deJAAA_Account.sol";
import {deJTRSY_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/deJTRSY_Account.sol";
import {JAAA_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/JAAA_Account.sol";
import {JTRSY_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/JTRSY_Account.sol";
import {ChainlinkOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/ChainlinkOracle.sol";
import {AsyncRedeemOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/AsyncRedeemOracle.sol";
import {MakinaOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/MakinaOracle.sol";
import {SaidOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/SaidOracle.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
import {IAccount} from "../../../src/interfaces/adapters/ll-adapter/IAccount.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Vm} from "forge-std/Vm.sol";

interface ILegacyRequestRedeem {
    function requestRedeem() external;
}

interface ILegacySubAccounts {
    function subAccounts(uint256 index) external view returns (address subAccount);
}

interface ILegacyTotalAssets {
    function totalAssets() external view returns (uint256 assets);
}

interface ILegacyTotalRequests {
    function totalRequests() external view returns (uint256 count);
}

abstract contract AccountsBase is Test {
    address internal constant ACRDX_TOKEN_ADDRESS = 0x9477724Bb54AD5417de8Baff29e59DF3fB4DA74f;
    address internal constant DECRDX_TOKEN_ADDRESS = 0x9E2679eABFF131b8b1b48fF7566140794E0eEdc4;
    address internal constant DEJAAA_TOKEN_ADDRESS = 0xAAA0008C8CF3A7Dca931adaF04336A5D808C82Cc;
    address internal constant DEJTRSY_TOKEN_ADDRESS = 0xA6233014B9b7aaa74f38fa1977ffC7A89642dC72;
    address internal constant JAAA_TOKEN_ADDRESS = 0x5a0F93D040De44e78F251b03c43be9CF317Dcf64;
    address internal constant JTRSY_TOKEN_ADDRESS = 0x8c213ee79581Ff4984583C6a801e5263418C4b86;

    address internal adapter = makeAddr("adapter");
    address internal cowSwapVaultRelayer = makeAddr("cowSwapVaultRelayer");
    address internal cowSwapSettlement = address(new AccountsCoWSwapSettlementMock(cowSwapVaultRelayer));

    function _deployAsyncRedeem(MockAsyncRedeemVault tokenToRedeem, MockERC20 asset, MockOracle oracle)
        internal
        returns (TestAsyncRedeemAccount account)
    {
        account = _deployAsyncRedeem(address(tokenToRedeem), asset, oracle, 0);
    }

    function _deployAsyncRedeem(MockAsyncRedeemVault tokenToRedeem, MockERC20 asset, AsyncRedeemOracle oracle)
        internal
        returns (TestAsyncRedeemAccount account)
    {
        account = _deployAsyncRedeem(address(tokenToRedeem), asset, address(oracle), 0);
    }

    function _deployAsyncRedeem(MockAsyncRedeemVault tokenToRedeem, MockERC20 asset, MockOracle oracle, uint48 cooldown)
        internal
        returns (TestAsyncRedeemAccount account)
    {
        account = _deployAsyncRedeem(address(tokenToRedeem), asset, oracle, cooldown);
    }

    function _deployAsyncRedeem(address tokenToRedeem, MockERC20 asset, MockOracle oracle, uint48 cooldown)
        internal
        returns (TestAsyncRedeemAccount account)
    {
        account = _deployAsyncRedeem(tokenToRedeem, asset, address(oracle), cooldown);
    }

    function _deployAsyncRedeem(address tokenToRedeem, MockERC20 asset, address oracle, uint48 cooldown)
        internal
        returns (TestAsyncRedeemAccount account)
    {
        return _deployAsyncRedeem(tokenToRedeem, asset, oracle, cooldown, tokenToRedeem);
    }

    function _deployAsyncRedeem(
        address tokenToRedeem,
        MockERC20 asset,
        address oracle,
        uint48 cooldown,
        address asyncRedeemVault
    ) internal returns (TestAsyncRedeemAccount account) {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        TestAsyncRedeemAccount implementation = new TestAsyncRedeemAccount(
            oracle, address(factory), cooldown, tokenToRedeem, address(asset), asyncRedeemVault, cowSwapSettlement
        );
        factory.whitelist(address(implementation));
        account = TestAsyncRedeemAccount(factory.create(1, address(this), _initData(address(asset), tokenToRedeem)));
    }

    function _deployPrime(MockPrimeToken prime, MockERC20 asset, MockOracle oracle)
        internal
        returns (PRIME_Account account)
    {
        account = _deployPrime(prime, asset, address(oracle));
    }

    function _deployPrime(MockPrimeToken prime, MockERC20 asset, AsyncRedeemOracle oracle)
        internal
        returns (PRIME_Account account)
    {
        account = _deployPrime(prime, asset, address(oracle));
    }

    function _deployPrime(MockPrimeToken prime, MockERC20 asset, address oracle)
        internal
        returns (PRIME_Account account)
    {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        PRIME_Account implementation = new PRIME_Account(
            oracle, address(factory), address(prime), address(new FigureSubAccount(address(prime))), cowSwapSettlement
        );
        factory.whitelist(address(implementation));
        account = PRIME_Account(factory.create(1, address(this), _initData(address(asset), address(prime))));
    }

    function _initData(address asset, address) internal returns (bytes memory) {
        return abi.encode(address(_vault(MockERC20(asset))), adapter);
    }

    function _vault(MockERC20 asset) internal returns (MockVault vault) {
        vault = new MockVault(address(asset));
    }

    function _mockDecimals(address token, uint8 decimals_) internal {
        vm.mockCall(token, abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(decimals_));
    }
}

contract MockOracle {
    uint256 internal _price;

    constructor(uint256 price_) {
        _price = price_;
    }

    function setPrice(uint256 price_) external {
        _price = price_;
    }

    function getPrice() external view returns (uint256) {
        return _price;
    }
}

contract MockPriceDataOracle {
    uint256 public price;
    uint48 public updatedAt;

    constructor(uint256 price_) {
        price = price_;
        updatedAt = uint48(block.timestamp);
    }

    function setPriceData(uint256 price_, uint48 updatedAt_) external {
        price = price_;
        updatedAt = updatedAt_;
    }

    function getPrice() external view returns (uint256) {
        return price;
    }

    function getPriceData() external view returns (uint256, uint48) {
        return (price, updatedAt);
    }
}

contract MockVault {
    address public immutable asset;

    constructor(address asset_) {
        asset = asset_;
    }
}

contract MockERC20 is ERC20 {
    uint8 internal immutable _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract MockPrimeToken is MockERC20 {
    MockERC20 internal immutable _wylds;
    uint256 internal immutable _wyldsPerPrime;

    constructor(MockERC20 wylds_, uint256 wyldsPerPrime_) MockERC20("Hastra PRIME", "PRIME", 6) {
        _wylds = wylds_;
        _wyldsPerPrime = wyldsPerPrime_;
    }

    function asset() external view returns (address) {
        return address(_wylds);
    }

    function convertToAssets(uint256 shares) external view returns (uint256 assets) {
        assets = shares * _wyldsPerPrime / 1e6;
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);
        assets = shares * _wyldsPerPrime / 1e6;
        _wylds.mint(receiver, assets);
    }
}

contract MockAsyncRedeemVault is MockERC20 {
    MockERC20 public immutable asset;
    uint256 public assetsPerShare;
    bool public freshRequestIds;
    bool public revertPreviewWithdraw;
    uint256 public nextRequestId;

    mapping(uint256 requestId => mapping(address controller => uint256 shares)) public pending;
    mapping(uint256 requestId => mapping(address controller => uint256 shares)) public claimable;
    mapping(address controller => uint256 shares) public claimableShares;
    mapping(address controller => uint256 assets) public claimableAssets;
    mapping(address controller => uint256 calls) public redeemCalls;

    struct PendingRedemption {
        uint256 shares;
        uint256 assets;
        uint256 timestamp;
    }

    mapping(address user => PendingRedemption redemption) public pendingRedemptions;

    constructor(string memory name_, string memory symbol_, uint8 decimals_, MockERC20 asset_, uint256 assetsPerShare_)
        MockERC20(name_, symbol_, decimals_)
    {
        asset = asset_;
        assetsPerShare = assetsPerShare_;
    }

    function setFreshRequestIds(bool status) external {
        freshRequestIds = status;
    }

    function setRevertPreviewWithdraw(bool status) external {
        revertPreviewWithdraw = status;
    }

    function setAssetsPerShare(uint256 assetsPerShare_) external {
        assetsPerShare = assetsPerShare_;
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        return shares * assetsPerShare / 10 ** decimals();
    }

    function vault(address asset_) external view returns (address) {
        return asset_ == address(asset) ? address(this) : address(0);
    }

    function previewWithdraw(uint256 shares) external view returns (uint256 assets) {
        if (revertPreviewWithdraw) {
            revert();
        }
        assets = convertToAssets(shares);
    }

    function requestRedeem(uint256 shares, address controller, address owner) external returns (uint256 requestId) {
        if (freshRequestIds) {
            requestId = nextRequestId++;
        }
        if (msg.sender == owner) {
            _transfer(owner, address(this), shares);
        } else {
            IERC20(address(this)).transferFrom(owner, address(this), shares);
        }
        pending[requestId][controller] += shares;
    }

    function requestRedeem(uint256 shares) external {
        if (pendingRedemptions[msg.sender].shares > 0) {
            revert();
        }
        _transfer(msg.sender, address(this), shares);
        pendingRedemptions[msg.sender] =
            PendingRedemption({shares: shares, assets: convertToAssets(shares), timestamp: block.timestamp});
    }

    function pendingRedeemRequest(uint256 requestId, address controller) external view returns (uint256 shares) {
        return pending[requestId][controller];
    }

    function claimableRedeemRequest(uint256 requestId, address controller) external view returns (uint256 shares) {
        return claimable[requestId][controller];
    }

    function fulfill(uint256 requestId, address controller, uint256 shares) external {
        pending[requestId][controller] -= shares;
        claimable[requestId][controller] += shares;
        claimableShares[controller] += shares;
        claimableAssets[controller] += convertToAssets(shares);
    }

    function process(uint256 requestId, address controller, uint256 shares) external {
        pending[requestId][controller] -= shares;
    }

    function makeClaimable(uint256 requestId, address controller, uint256 shares) external {
        claimable[requestId][controller] += shares;
        claimableShares[controller] += shares;
        claimableAssets[controller] += convertToAssets(shares);
    }

    function maxWithdraw(address owner) external view returns (uint256 maxAssets) {
        return claimableAssets[owner];
    }

    function maxRedeem(address owner) external view returns (uint256 maxShares) {
        return claimableShares[owner];
    }

    function redeem(uint256 shares, address receiver, address controller) external returns (uint256 assets) {
        uint256 curClaimableShares = claimableShares[controller];
        assets = shares == curClaimableShares
            ? claimableAssets[controller]
            : claimableAssets[controller] * shares / curClaimableShares;
        claimableShares[controller] -= shares;
        claimableAssets[controller] -= assets;
        ++redeemCalls[controller];
        asset.mint(receiver, assets);
    }

    function completeFigureRedeem(address user) external {
        PendingRedemption memory redemption = pendingRedemptions[user];
        delete pendingRedemptions[user];
        _burn(address(this), redemption.shares);
        asset.mint(user, redemption.assets);
    }
}

contract AccountsCoWSwapSettlementMock {
    address public vaultRelayer;
    bytes32 public domainSeparator = keccak256("DOMAIN");
    bool public lastSigned;

    constructor(address vaultRelayer_) {
        vaultRelayer = vaultRelayer_;
    }

    function setPreSignature(bytes calldata, bool signed) external {
        lastSigned = signed;
    }
}

contract TestAsyncRedeemAccount is CentrifugeAccount {
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address redemptionToken,
        address asyncRedeemVault,
        address cowSwapSettlement
    )
        CentrifugeAccount(
            oracle, factory, cooldown, tokenToRedeem, redemptionToken, asyncRedeemVault, cowSwapSettlement
        )
    {}

    function asyncRedeemVault() external view returns (address) {
        return _asyncRedeemVault();
    }
}

contract TestBaseAsyncRedeemAccount is AsyncRedeemAccount {
    constructor(
        address oracle,
        address factory,
        address tokenToRedeem,
        address redemptionToken,
        address cowSwapSettlement
    ) AsyncRedeemAccount(oracle, factory, 0, tokenToRedeem, redemptionToken, cowSwapSettlement) {}

    function asyncRedeemVault() external view returns (address) {
        return _asyncRedeemVault();
    }
}
