// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ACRDX_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/ACRDX_Account.sol";
import {AsyncRedeemAccount} from "../../../src/contracts/adapters/ll-adapter/common/AsyncRedeemAccount.sol";
import {DigiFTAccount} from "../../../src/contracts/adapters/ll-adapter/DigiFTAccount.sol";
import {DUSD_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/DUSD_Account.sol";
import {GaibAccount} from "../../../src/contracts/adapters/ll-adapter/GaibAccount.sol";
import {MakinaAccount} from "../../../src/contracts/adapters/ll-adapter/MakinaAccount.sol";
import {PRIME_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/PRIME_Account.sol";
import {sAID_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/sAID_Account.sol";
import {deCRDX_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/deCRDX_Account.sol";
import {deJAAA_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/deJAAA_Account.sol";
import {deJTRSY_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/deJTRSY_Account.sol";
import {JAAA_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/JAAA_Account.sol";
import {JTRSY_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/JTRSY_Account.sol";
import {sthUSD_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/sthUSD_Account.sol";
import {sUSD3_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/sUSD3_Account.sol";
import {TheoAccount} from "../../../src/contracts/adapters/ll-adapter/TheoAccount.sol";
import {ThreeJaneAccount} from "../../../src/contracts/adapters/ll-adapter/ThreeJaneAccount.sol";
import {weETH_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/weETH_Account.sol";
import {wstETH_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/wstETH_Account.sol";
import {ChainlinkOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/ChainlinkOracle.sol";
import {AsyncRedeemOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/AsyncRedeemOracle.sol";
import {MakinaOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/MakinaOracle.sol";
import {SaidOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/SaidOracle.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
import {IAccount} from "../../../src/interfaces/adapters/ll-adapter/IAccount.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "forge-std/Vm.sol";

abstract contract AccountsBase is Test {
    address internal constant ACRDX_TOKEN_ADDRESS = 0x9477724Bb54AD5417de8Baff29e59DF3fB4DA74f;
    address internal constant BEQTY_SUB_RED_MANAGEMENT_ADDRESS = 0x3797C46db697c24a983222c335F17Ba28e8c5b69;
    address internal constant BEQTY_TOKEN_ADDRESS = 0xEaFD6D38f41f882BCFd5fEaABccCc714B983b701;
    address internal constant DECRDX_TOKEN_ADDRESS = 0x9E2679eABFF131b8b1b48fF7566140794E0eEdc4;
    address internal constant DEJAAA_TOKEN_ADDRESS = 0xAAA0008C8CF3A7Dca931adaF04336A5D808C82Cc;
    address internal constant DEJTRSY_TOKEN_ADDRESS = 0xA6233014B9b7aaa74f38fa1977ffC7A89642dC72;
    address internal constant DUSD_MACHINE_ADDRESS = 0x6b006870C83b1Cd49E766Ac9209f8d68763Df721;
    address internal constant DUSD_REDEEMER_ADDRESS = 0x1303c26cFE06bac5bfEE29907f37919643DEF75c;
    address internal constant DUSD_SHARE_PRICE_ORACLE_ADDRESS = 0xFFCBc7A7eEF2796C277095C66067aC749f4cA078;
    address internal constant DUSD_TOKEN_ADDRESS = 0x1e33E98aF620F1D563fcD3cfd3C75acE841204ef;
    address internal constant JAAA_TOKEN_ADDRESS = 0x5a0F93D040De44e78F251b03c43be9CF317Dcf64;
    address internal constant JTRSY_TOKEN_ADDRESS = 0x8c213ee79581Ff4984583C6a801e5263418C4b86;
    address internal constant AID_TOKEN_ADDRESS = 0x18F52B3fb465118731d9e0d276d4Eb3599D57596;
    address internal constant SAID_TOKEN_ADDRESS = 0xB3B3c527BA57cd61648e2EC2F5e006A0B390A9F8;
    address internal constant STHUSD_TOKEN_ADDRESS = 0xA808Bc9775cb41c52C7842f8b50427fE7A770326;
    address internal constant SUSD3_TOKEN_ADDRESS = 0xf689555121e529Ff0463e191F9Bd9d1E496164a7;
    address internal constant USDC_TOKEN_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    uint48 internal constant DUSD_TOKEN_COOLDOWN = 72 minutes;
    uint48 internal constant DIGIFT_SETTLEMENT_DURATION = 7 days;
    uint48 internal constant SAID_TOKEN_COOLDOWN = 6 days;

    address internal adapter = makeAddr("adapter");
    address internal cowSwapVaultRelayer = makeAddr("cowSwapVaultRelayer");
    address internal cowSwapSettlement = address(new AccountsCoWSwapSettlementMock(cowSwapVaultRelayer));
    address internal subRedManagement = makeAddr("subRedManagement");

    function _deployWstETH(
        MockWstETH wstETH,
        MockERC20 stETH,
        MockERC20 asset,
        MockLidoWithdrawalQueue withdrawalQueue,
        MockOracle oracle
    ) internal returns (wstETH_Account account) {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        wstETH_Account implementation = new wstETH_Account(
            address(stETH),
            address(asset),
            address(oracle),
            address(wstETH),
            address(factory),
            address(withdrawalQueue),
            cowSwapSettlement
        );
        factory.whitelist(address(implementation));
        account = wstETH_Account(payable(factory.create(1, address(this), _initData(address(asset), address(wstETH)))));
    }

    function _deployWeETH(LstMocks memory mocks, MockERC20 asset, MockOracle oracle)
        internal
        returns (weETH_Account account)
    {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        weETH_Account implementation = new weETH_Account(
            address(mocks.eETH),
            address(mocks.weth),
            address(mocks.weETH),
            address(oracle),
            address(factory),
            address(mocks.liquidityPool),
            address(mocks.redemptionManager),
            cowSwapSettlement,
            address(mocks.withdrawRequestNft)
        );
        factory.whitelist(address(implementation));
        account =
            weETH_Account(payable(factory.create(1, address(this), _initData(address(asset), address(mocks.weETH)))));
    }

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
        MigratablesFactory factory = new MigratablesFactory(address(this));
        TestAsyncRedeemAccount implementation =
            new TestAsyncRedeemAccount(oracle, address(factory), cooldown, tokenToRedeem, cowSwapSettlement);
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
        PRIME_Account implementation = new PRIME_Account(oracle, address(factory), address(prime), cowSwapSettlement);
        factory.whitelist(address(implementation));
        account = PRIME_Account(factory.create(1, address(this), _initData(address(asset), address(prime))));
    }

    function _deployGaib(MockSaidVault tokenToRedeem, MockERC20 asset, MockOracle oracle, uint48 cooldown)
        internal
        returns (GaibAccount account)
    {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        GaibAccount implementation =
            new GaibAccount(address(oracle), address(factory), cooldown, address(tokenToRedeem), cowSwapSettlement);
        factory.whitelist(address(implementation));
        account = GaibAccount(factory.create(1, address(this), _initData(address(asset), address(tokenToRedeem))));
    }

    function _deployThreeJane(MockThreeJaneSUSD3 tokenToRedeem, MockERC20 asset, MockOracle oracle)
        internal
        returns (ThreeJaneAccount account)
    {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        ThreeJaneAccount implementation =
            new ThreeJaneAccount(address(oracle), address(factory), address(tokenToRedeem), cowSwapSettlement);
        factory.whitelist(address(implementation));
        account = ThreeJaneAccount(factory.create(1, address(this), _initData(address(asset), address(tokenToRedeem))));
    }

    function _deployTheo(MockSthUSD tokenToRedeem, MockERC20 asset, MockOracle oracle)
        internal
        returns (TheoAccount account)
    {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        TheoAccount implementation =
            new TheoAccount(address(oracle), address(factory), address(tokenToRedeem), cowSwapSettlement);
        factory.whitelist(address(implementation));
        account = TheoAccount(factory.create(1, address(this), _initData(address(asset), address(tokenToRedeem))));
    }

    function _deployDigiFT(MockERC20 tokenToRedeem, MockERC20 asset, MockPriceDataOracle oracle)
        internal
        returns (DigiFTAccount account)
    {
        account = _deployDigiFT(tokenToRedeem, asset, oracle, subRedManagement);
    }

    function _deployDigiFT(
        MockERC20 tokenToRedeem,
        MockERC20 asset,
        MockPriceDataOracle oracle,
        address subRedManagement_
    ) internal returns (DigiFTAccount account) {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        DigiFTAccount implementation = new DigiFTAccount(
            address(oracle),
            address(factory),
            address(tokenToRedeem),
            subRedManagement_,
            DIGIFT_SETTLEMENT_DURATION,
            cowSwapSettlement
        );
        factory.whitelist(address(implementation));
        account = DigiFTAccount(factory.create(1, address(this), _initData(address(asset), address(tokenToRedeem))));
    }

    function _deployMakina(
        MockERC20 tokenToRedeem,
        MockERC20 asset,
        MockMakinaRedeemer redeemer,
        MockOracle oracle,
        uint48 cooldown
    ) internal returns (MakinaAccount account) {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        MakinaAccount implementation = new MakinaAccount(
            address(oracle), address(factory), cooldown, address(redeemer), address(tokenToRedeem), cowSwapSettlement
        );
        factory.whitelist(address(implementation));
        account = MakinaAccount(factory.create(1, address(this), _initData(address(asset), address(tokenToRedeem))));
    }

    function _lstMocks() internal returns (LstMocks memory mocks) {
        mocks.stETH = new MockERC20("Liquid staked Ether", "stETH", 18);
        mocks.eETH = new MockERC20("ether.fi ETH", "eETH", 18);
        mocks.weth = new MockWETH();
        mocks.wstETH = new MockWstETH(address(mocks.stETH));
        mocks.weETH = new MockWeETH(address(mocks.eETH));
        mocks.redemptionManager =
            new MockEtherFiRedemptionManager(address(mocks.weETH), address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
        mocks.withdrawRequestNft = new MockEtherFiWithdrawRequestNFT();
        mocks.liquidityPool = new MockEtherFiLiquidityPool(address(mocks.eETH), address(mocks.withdrawRequestNft));
    }

    function _initData(address asset, address) internal returns (bytes memory) {
        return abi.encode(address(_vault(MockERC20(asset))), adapter);
    }

    function _vault(MockERC20 asset) internal returns (MockVault vault) {
        vault = new MockVault(address(asset));
    }

    function _mockDecimals(address token, uint8 decimals_) internal {
        vm.mockCall(token, abi.encodeWithSignature("decimals()"), abi.encode(decimals_));
    }
}

struct LstMocks {
    MockERC20 stETH;
    MockERC20 eETH;
    MockWETH weth;
    MockWstETH wstETH;
    MockWeETH weETH;
    MockEtherFiRedemptionManager redemptionManager;
    MockEtherFiLiquidityPool liquidityPool;
    MockEtherFiWithdrawRequestNFT withdrawRequestNft;
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

contract MockWETH is MockERC20 {
    constructor() MockERC20("Wrapped Ether", "WETH", 18) {}

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }
}

contract MockWstETH is MockERC20 {
    MockERC20 internal immutable _stETH;

    constructor(address stETH_) MockERC20("Wrapped stETH", "wstETH", 18) {
        _stETH = MockERC20(stETH_);
    }

    function wrap(uint256 stETHAmount) external returns (uint256 wstETHAmount) {
        IERC20(address(_stETH)).transferFrom(msg.sender, address(this), stETHAmount);
        _mint(msg.sender, stETHAmount);
        return stETHAmount;
    }

    function unwrap(uint256 wstETHAmount) external returns (uint256 stETHAmount) {
        _burn(msg.sender, wstETHAmount);
        _stETH.mint(msg.sender, wstETHAmount);
        return wstETHAmount;
    }

    function getWstETHByStETH(uint256 stETHAmount) external pure returns (uint256 wstETHAmount) {
        return stETHAmount;
    }

    function getStETHByWstETH(uint256 wstETHAmount) external pure returns (uint256 stETHAmount) {
        return wstETHAmount;
    }
}

contract MockLidoWithdrawalQueue {
    struct WithdrawalRequestStatus {
        uint256 amountOfStETH;
        uint256 amountOfShares;
        address owner;
        uint256 timestamp;
        bool isFinalized;
        bool isClaimed;
    }

    IERC20 internal immutable _wstETH;
    IERC20 internal immutable _stETH;

    uint256 public constant MAX_STETH_WITHDRAWAL_AMOUNT = 1000 ether;
    uint256 public constant MIN_STETH_WITHDRAWAL_AMOUNT = 100;

    uint256 public nextRequestId = 1;

    mapping(uint256 requestId => uint256 amount) public requestedWstETH;
    mapping(uint256 requestId => uint256 amount) public requestedStETH;
    mapping(uint256 requestId => uint256 amount) public claimAmount;
    mapping(uint256 requestId => bool status) public successfulClaim;
    mapping(uint256 requestId => bool status) public claimed;
    mapping(uint256 requestId => address owner) public requestOwner;
    mapping(uint256 requestId => uint256 amount) public statusAmountOfStETH;

    constructor(address wstETH_, address stETH_) {
        _wstETH = IERC20(wstETH_);
        _stETH = IERC20(stETH_);
    }

    function requestWithdrawalsWstETH(uint256[] calldata amounts, address recipient)
        external
        returns (uint256[] memory ids)
    {
        ids = new uint256[](amounts.length);
        for (uint256 i; i < amounts.length; ++i) {
            _wstETH.transferFrom(msg.sender, address(this), amounts[i]);
            ids[i] = nextRequestId++;
            requestedWstETH[ids[i]] = amounts[i];
            statusAmountOfStETH[ids[i]] = amounts[i];
            requestOwner[ids[i]] = recipient;
        }
    }

    function requestWithdrawals(uint256[] calldata amounts, address recipient) external returns (uint256[] memory ids) {
        ids = new uint256[](amounts.length);
        for (uint256 i; i < amounts.length; ++i) {
            _stETH.transferFrom(msg.sender, address(this), amounts[i]);
            ids[i] = nextRequestId++;
            requestedStETH[ids[i]] = amounts[i];
            statusAmountOfStETH[ids[i]] = amounts[i];
            requestOwner[ids[i]] = recipient;
        }
    }

    function setClaimAmount(uint256 requestId, uint256 amount) external payable {
        claimAmount[requestId] = amount;
    }

    function setSuccessfulClaim(uint256 requestId, bool status) external {
        successfulClaim[requestId] = status;
    }

    function setWithdrawalStatusAmount(uint256 requestId, uint256 amount) external {
        statusAmountOfStETH[requestId] = amount;
    }

    function claimWithdrawal(uint256 requestId) external {
        uint256 amount = claimAmount[requestId];
        if (amount == 0 && !successfulClaim[requestId]) {
            revert();
        }
        claimAmount[requestId] = 0;
        successfulClaim[requestId] = false;
        claimed[requestId] = true;
        if (amount > 0) {
            (bool success,) = msg.sender.call{value: amount}("");
            require(success);
        }
    }

    function getWithdrawalStatus(uint256[] calldata requestIds)
        external
        view
        returns (WithdrawalRequestStatus[] memory statuses)
    {
        statuses = new WithdrawalRequestStatus[](requestIds.length);
        for (uint256 i; i < requestIds.length; ++i) {
            uint256 requestId = requestIds[i];
            statuses[i] = WithdrawalRequestStatus({
                amountOfStETH: statusAmountOfStETH[requestId],
                amountOfShares: statusAmountOfStETH[requestId],
                owner: requestOwner[requestId],
                timestamp: 0,
                isFinalized: claimAmount[requestId] > 0 || successfulClaim[requestId],
                isClaimed: claimed[requestId]
            });
        }
    }

    function getLastCheckpointIndex() external view returns (uint256 index) {
        return nextRequestId > 1 ? 1 : 0;
    }

    function findCheckpointHints(uint256[] calldata requestIds, uint256, uint256)
        external
        pure
        returns (uint256[] memory hints)
    {
        hints = new uint256[](requestIds.length);
        for (uint256 i; i < requestIds.length; ++i) {
            if (i > 0) {
                require(requestIds[i - 1] <= requestIds[i], "UNSORTED");
            }
            hints[i] = 1;
        }
    }

    function getClaimableEther(uint256[] calldata requestIds, uint256[] calldata)
        external
        view
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](requestIds.length);
        for (uint256 i; i < requestIds.length; ++i) {
            amounts[i] = claimAmount[requestIds[i]];
        }
    }
}

contract MockWeETH is MockERC20 {
    MockERC20 internal immutable _eETH;

    constructor(address eETH_) MockERC20("Wrapped eETH", "weETH", 18) {
        _eETH = MockERC20(eETH_);
    }

    function unwrap(uint256 weETHAmount) external returns (uint256 eETHAmount) {
        _burn(msg.sender, weETHAmount);
        _eETH.mint(msg.sender, weETHAmount);
        return weETHAmount;
    }

    function getEETHByWeETH(uint256 weETHAmount) external pure returns (uint256 eETHAmount) {
        return weETHAmount;
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

contract MockERC4626RedeemToken is MockERC20 {
    address internal immutable _asset;
    uint256 internal immutable _assetsPerShare;

    constructor(MockERC20 asset_, string memory name_, string memory symbol_, uint8 decimals_, uint256 assetsPerShare_)
        MockERC20(name_, symbol_, decimals_)
    {
        _asset = address(asset_);
        _assetsPerShare = assetsPerShare_;
    }

    function asset() external view returns (address) {
        return _asset;
    }

    function convertToAssets(uint256 shares) external view returns (uint256 assets) {
        assets = shares * _assetsPerShare / 10 ** decimals();
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);
        assets = shares * _assetsPerShare / 10 ** decimals();
        MockERC20(_asset).mint(receiver, assets);
    }
}

contract MockThreeJaneSUSD3 is MockERC20 {
    Vm internal constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct UserCooldown {
        uint48 cooldownEnd;
        uint48 windowEnd;
        uint128 shares;
    }

    MockERC20 internal immutable _asset;
    uint256 internal immutable _assetsPerShare;
    uint48 public immutable cooldownDuration;
    uint48 public immutable withdrawalWindow;

    uint256 internal _availableWithdrawLimit;

    mapping(address user => uint48 timestamp) public lockedUntil;
    mapping(address user => UserCooldown cooldown) internal _cooldowns;

    constructor(MockERC20 asset_, uint256 assetsPerShare_, uint48 cooldownDuration_, uint48 withdrawalWindow_)
        MockERC20("3Jane sUSD3", "sUSD3", 6)
    {
        _asset = asset_;
        _assetsPerShare = assetsPerShare_;
        cooldownDuration = cooldownDuration_;
        withdrawalWindow = withdrawalWindow_;
        _availableWithdrawLimit = type(uint256).max;
    }

    function asset() external view returns (address) {
        return address(_asset);
    }

    function availableWithdrawLimit(address) external view returns (uint256 assets) {
        return _availableWithdrawLimit;
    }

    function setAvailableWithdrawLimit(uint256 assets) external {
        _availableWithdrawLimit = assets;
    }

    function setLockedUntil(address user, uint48 timestamp) external {
        lockedUntil[user] = timestamp;
    }

    function getCooldownStatus(address user)
        external
        view
        returns (uint48 cooldownEnd, uint48 windowEnd, uint256 shares)
    {
        UserCooldown memory cooldown = _cooldowns[user];
        return (cooldown.cooldownEnd, cooldown.windowEnd, cooldown.shares);
    }

    function startCooldown(uint256 shares) external {
        uint48 timestamp = uint48(VM.getBlockTimestamp());

        require(shares > 0);
        require(timestamp >= lockedUntil[msg.sender]);
        require(shares <= balanceOf(msg.sender));
        _cooldowns[msg.sender] = UserCooldown({
            shares: uint128(shares),
            windowEnd: timestamp + cooldownDuration + withdrawalWindow,
            cooldownEnd: timestamp + cooldownDuration
        });
    }

    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        return shares * _assetsPerShare / 10 ** decimals();
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        shares = assets * 10 ** decimals() / _assetsPerShare;
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        require(assets <= _availableWithdrawLimit);

        UserCooldown storage cooldown = _cooldowns[owner];
        require(cooldown.shares >= shares);
        if (cooldown.shares == shares) {
            delete _cooldowns[owner];
        } else {
            cooldown.shares -= uint128(shares);
        }
        _burn(owner, shares);
        _asset.mint(receiver, assets);
    }
}

contract MockSthUSD is MockERC20 {
    Vm internal constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct RedeemRequestData {
        uint256 assets;
        uint256 shares;
        uint256 claimableTimestamp;
    }

    MockERC20 internal immutable _asset;
    uint256 internal immutable _assetsPerShare;
    uint256 public immutable lockupPeriod;

    mapping(address user => RedeemRequestData request) internal _redeemRequests;

    constructor(MockERC20 asset_, uint256 assetsPerShare_, uint256 lockupPeriod_)
        MockERC20("Staked thUSD", "sthUSD", 6)
    {
        _asset = asset_;
        _assetsPerShare = assetsPerShare_;
        lockupPeriod = lockupPeriod_;
    }

    function asset() external view returns (address) {
        return address(_asset);
    }

    function currentRedeemRequest(address owner)
        external
        view
        returns (uint256 assets, uint256 shares, uint256 claimableTimestamp)
    {
        RedeemRequestData memory request = _redeemRequests[owner];
        return (request.assets, request.shares, request.claimableTimestamp);
    }

    function initiateRedeem(uint256 shares, address owner) external {
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        uint256 assets = convertToAssets(shares);
        _burn(owner, shares);

        RedeemRequestData storage request = _redeemRequests[msg.sender];
        request.assets += assets;
        request.shares += shares;
        request.claimableTimestamp = VM.getBlockTimestamp() + lockupPeriod;
    }

    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        return shares * _assetsPerShare / 10 ** decimals();
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        require(msg.sender == owner);

        RedeemRequestData storage request = _redeemRequests[owner];
        require(VM.getBlockTimestamp() >= request.claimableTimestamp);
        require(shares <= request.shares);

        if (shares == request.shares) {
            assets = request.assets;
        } else {
            assets = shares * request.assets / request.shares;
        }

        request.assets -= assets;
        request.shares -= shares;
        _asset.mint(receiver, assets);
    }
}

contract MockSaidVault is MockERC20 {
    MockERC20 public immutable assetToken;
    uint256 public immutable assetsPerShareWithLoss;

    mapping(address account => uint256 assets) public claimableAssets;
    mapping(address account => uint256 assets) public pendingAssets;
    mapping(address account => uint256 time) public requestTime;

    constructor(MockERC20 asset_, uint256 assetsPerShareWithLoss_) MockERC20("Staked AI Dollar", "sAID", 18) {
        assetToken = asset_;
        assetsPerShareWithLoss = assetsPerShareWithLoss_;
    }

    function asset() external view returns (address) {
        return address(assetToken);
    }

    function convertToAssetsWithLoss(uint256 shares) public view returns (uint256 assets) {
        assets = shares * assetsPerShareWithLoss / 1e18;
    }

    function unstake(uint256 shares) external {
        if (pendingAssets[msg.sender] > 0) {
            revert();
        }

        _burn(msg.sender, shares);
        requestTime[msg.sender] = block.timestamp;
        pendingAssets[msg.sender] = convertToAssetsWithLoss(shares);
    }

    function fulfill(address account, uint256 assets) external {
        assetToken.mint(address(this), assets);
        claimableAssets[account] += assets;
    }

    function processUnstakeQueue(uint256) external {
        uint256 claimable = claimableAssets[msg.sender];
        uint256 pending = pendingAssets[msg.sender];
        if (claimable == 0 || pending == 0) {
            return;
        }

        uint256 assets = claimable > pending ? pending : claimable;
        claimableAssets[msg.sender] -= assets;
        pendingAssets[msg.sender] -= assets;
        assetToken.transfer(msg.sender, assets);

        if (pendingAssets[msg.sender] == 0) {
            requestTime[msg.sender] = 0;
        }
    }

    function getUnstakeRequest(address user) external view returns (uint256 time, uint256 assets) {
        time = requestTime[user];
        assets = pendingAssets[user];
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
    mapping(address controller => uint256 assets) public claimableAssets;

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

    function setNextRequestId(uint256 requestId) external {
        nextRequestId = requestId;
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
        claimableAssets[controller] += convertToAssets(shares);
    }

    function maxWithdraw(address owner) external view returns (uint256 maxAssets) {
        return claimableAssets[owner];
    }

    function redeem(uint256 shares, address receiver, address controller) external returns (uint256 assets) {
        uint256 claimableShares = claimable[0][controller];
        assets = shares == claimableShares
            ? claimableAssets[controller]
            : claimableAssets[controller] * shares / claimableShares;
        claimable[0][controller] -= shares;
        claimableAssets[controller] -= assets;
        asset.mint(receiver, assets);
    }

    function completeFigureRedeem(address user) external {
        PendingRedemption memory redemption = pendingRedemptions[user];
        delete pendingRedemptions[user];
        _burn(address(this), redemption.shares);
        asset.mint(user, redemption.assets);
    }
}

contract MockMakinaMachine {
    MockERC20 public immutable shareToken;
    MockERC20 public immutable accountingToken;
    uint256 public immutable assetsPerShare;

    constructor(MockERC20 shareToken_, MockERC20 accountingToken_, uint256 assetsPerShare_) {
        shareToken = shareToken_;
        accountingToken = accountingToken_;
        assetsPerShare = assetsPerShare_;
    }

    function convertToAssets(uint256 shares) external view returns (uint256 assets) {
        assets = shares * assetsPerShare / 10 ** shareToken.decimals();
    }
}

contract MockMakinaRedeemer {
    MockMakinaMachine public immutable machineContract;

    uint256 public nextRequestId = 1;
    uint256 public lastFinalizedRequestId;

    mapping(uint256 requestId => address owner) public ownerOf;
    mapping(uint256 requestId => uint256 assets) public claimableAssets;
    mapping(uint256 requestId => uint256 shares) public requestShares;

    constructor(MockMakinaMachine machine_) {
        machineContract = machine_;
    }

    function machine() external view returns (address) {
        return address(machineContract);
    }

    function getShares(uint256 requestId) external view returns (uint256 shares) {
        if (ownerOf[requestId] == address(0)) {
            revert();
        }
        shares = requestShares[requestId];
    }

    function getClaimableAssets(uint256 requestId) external view returns (uint256 assets) {
        if (ownerOf[requestId] == address(0) || requestId > lastFinalizedRequestId) {
            revert();
        }
        assets = claimableAssets[requestId];
    }

    function requestRedeem(uint256 shares, address receiver, uint256) external returns (uint256 requestId) {
        requestId = nextRequestId++;
        ownerOf[requestId] = receiver;
        requestShares[requestId] = shares;
        IERC20(address(machineContract.shareToken())).transferFrom(msg.sender, address(this), shares);
    }

    function finalize(uint256 requestId, uint256 assets) external {
        lastFinalizedRequestId = requestId;
        claimableAssets[requestId] = assets;
        machineContract.accountingToken().mint(address(this), assets);
    }

    function claimAssets(uint256 requestId) external returns (uint256 assets) {
        if (ownerOf[requestId] != msg.sender) {
            revert();
        }
        assets = this.getClaimableAssets(requestId);
        delete ownerOf[requestId];
        delete requestShares[requestId];
        delete claimableAssets[requestId];
        IERC20(address(machineContract.accountingToken())).transfer(msg.sender, assets);
    }
}

contract MockMakinaSharePriceOracle {
    uint8 public immutable decimals;
    uint256 public immutable sharePrice;

    constructor(uint8 decimals_, uint256 sharePrice_) {
        decimals = decimals_;
        sharePrice = sharePrice_;
    }

    function getSharePrice() external view returns (uint256) {
        return sharePrice;
    }
}

contract MockEtherFiRedemptionManager {
    address public immutable weETH;
    address public immutable ETH_ADDRESS;

    mapping(address token => uint16 fee) public exitFeeInBps;
    mapping(address token => bool status) public redeemable;

    bool public revertRedeem;

    address public lastOutputToken;
    address public lastReceiver;
    uint256 public lastWeETHAmount;

    constructor(address weETH_, address ethAddress_) {
        weETH = weETH_;
        ETH_ADDRESS = ethAddress_;
    }

    function setExitFee(address token, uint16 fee) external {
        exitFeeInBps[token] = fee;
    }

    function setRedeemable(address token, bool status) external {
        redeemable[token] = status;
    }

    function setRevertRedeem(bool status) external {
        revertRedeem = status;
    }

    function tokenToRedemptionInfo(address token)
        external
        view
        returns (BucketLimit memory limit, uint16, uint16 exitFeeInBps_, uint16)
    {
        return (limit, 0, exitFeeInBps[token], 0);
    }

    function canRedeem(uint256, address token) external view returns (bool) {
        return redeemable[token];
    }

    function redeemWeEth(uint256 weETHAmount, address receiver, address outputToken) external {
        if (revertRedeem) {
            revert();
        }

        IERC20(weETH).transferFrom(msg.sender, address(this), weETHAmount);

        lastWeETHAmount = weETHAmount;
        lastReceiver = receiver;
        lastOutputToken = outputToken;

        if (outputToken == ETH_ADDRESS) {
            (bool success,) = receiver.call{value: weETHAmount}("");
            require(success);
        } else {
            MockERC20(outputToken).mint(receiver, weETHAmount);
        }
    }

    struct BucketLimit {
        uint64 capacity;
        uint64 remaining;
        uint64 lastRefill;
        uint64 refillRate;
    }
}

contract MockEtherFiLiquidityPool {
    IERC20 internal immutable _eETH;
    MockEtherFiWithdrawRequestNFT internal immutable _withdrawRequestNft;

    address public lastRecipient;
    uint256 public lastAmount;
    uint256 public nextRequestId = 1;
    uint256 public amountForShareRate = 1e18;

    constructor(address eETH_, address withdrawRequestNft_) {
        _eETH = IERC20(eETH_);
        _withdrawRequestNft = MockEtherFiWithdrawRequestNFT(withdrawRequestNft_);
    }

    function setAmountForShareRate(uint256 rate) external {
        amountForShareRate = rate;
    }

    function requestWithdraw(address recipient, uint256 amount) external returns (uint256 requestId) {
        _eETH.transferFrom(msg.sender, address(this), amount);
        lastRecipient = recipient;
        lastAmount = amount;
        requestId = nextRequestId++;
        _withdrawRequestNft.recordRequest(requestId, uint96(amount), uint96(amount), 0);
    }

    function amountForShare(uint256 share) external view returns (uint256 amount) {
        return share * amountForShareRate / 1e18;
    }
}

contract MockEtherFiWithdrawRequestNFT {
    struct WithdrawRequest {
        uint96 amountOfEEth;
        uint96 shareOfEEth;
        bool isValid;
        uint32 feeGwei;
    }

    mapping(uint256 requestId => uint256 amount) public claimAmount;
    mapping(uint256 requestId => bool status) public successfulClaim;
    mapping(uint256 requestId => WithdrawRequest request) internal _requests;

    function recordRequest(uint256 requestId, uint96 amountOfEEth, uint96 shareOfEEth, uint32 feeGwei) external {
        _requests[requestId] =
            WithdrawRequest({amountOfEEth: amountOfEEth, shareOfEEth: shareOfEEth, isValid: true, feeGwei: feeGwei});
    }

    function setClaimAmount(uint256 claimAmount_) external payable {
        claimAmount[1] = claimAmount_;
    }

    function setClaimSucceeds(uint256 requestId, bool status) external {
        successfulClaim[requestId] = status;
    }

    function claimWithdraw(uint256 requestId) external {
        uint256 amount = claimAmount[requestId];
        if (amount == 0 && !successfulClaim[requestId]) {
            revert();
        }
        claimAmount[requestId] = 0;
        successfulClaim[requestId] = false;
        delete _requests[requestId];
        if (amount > 0) {
            (bool success,) = msg.sender.call{value: amount}("");
            require(success);
        }
    }

    function getRequest(uint256 requestId) external view returns (WithdrawRequest memory request) {
        return _requests[requestId];
    }
}

contract AccountsCoWSwapSettlementMock {
    address public vaultRelayer;

    constructor(address vaultRelayer_) {
        vaultRelayer = vaultRelayer_;
    }
}

contract TestAsyncRedeemAccount is AsyncRedeemAccount {
    constructor(address oracle, address factory, uint48 cooldown, address tokenToRedeem, address cowSwapSettlement)
        AsyncRedeemAccount(oracle, factory, cooldown, tokenToRedeem, cowSwapSettlement)
    {}
}
