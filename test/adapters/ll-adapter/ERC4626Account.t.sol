// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ERC4626Account} from "../../../src/contracts/adapters/ll-adapter/ERC4626Account.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract ERC4626AccountTest is Test {
    address internal adapter = makeAddr("adapter");
    address internal cowSwapSettlement;

    function setUp() public {
        cowSwapSettlement = address(new ERC4626AccountCoWSwapSettlementMock(makeAddr("cowSwapVaultRelayer")));
    }

    function testSyncRedeemsOnlyAvailableShares() public {
        ERC4626AccountAssetMock asset = new ERC4626AccountAssetMock("Asset", "ASSET");
        LiquidityLimitedERC4626Mock tokenToRedeem = new LiquidityLimitedERC4626Mock(asset);
        MigratablesFactory factory = new MigratablesFactory(address(this));
        ERC4626Account implementation = new ERC4626Account(address(factory), address(tokenToRedeem), cowSwapSettlement);
        factory.whitelist(address(implementation));
        ERC4626Account account = ERC4626Account(
            factory.create(1, address(this), abi.encode(address(new ERC4626AccountVaultMock(address(asset))), adapter))
        );

        asset.mint(address(this), 100 ether);
        asset.approve(address(tokenToRedeem), 100 ether);
        tokenToRedeem.deposit(100 ether, address(account));
        tokenToRedeem.setRedeemLimit(40 ether);

        account.sync();

        assertEq(asset.balanceOf(address(account)), 40 ether);
        assertEq(tokenToRedeem.balanceOf(address(account)), 60 ether);
        assertEq(account.totalAssets(), 100 ether);
    }
}

contract LiquidityLimitedERC4626Mock is ERC4626 {
    uint256 internal _redeemLimit = type(uint256).max;

    constructor(IERC20 asset_) ERC20("Liquidity-Limited Vault", "LLV") ERC4626(asset_) {}

    function setRedeemLimit(uint256 redeemLimit) external {
        _redeemLimit = redeemLimit;
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        uint256 ownerShares = super.maxRedeem(owner);
        return ownerShares < _redeemLimit ? ownerShares : _redeemLimit;
    }
}

contract ERC4626AccountAssetMock is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract ERC4626AccountVaultMock {
    address public immutable asset;

    constructor(address asset_) {
        asset = asset_;
    }
}

contract ERC4626AccountCoWSwapSettlementMock {
    address public immutable vaultRelayer;

    constructor(address vaultRelayer_) {
        vaultRelayer = vaultRelayer_;
    }
}
