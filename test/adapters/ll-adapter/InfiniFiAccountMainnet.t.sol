// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract InfiniFiAccountMainnetTest is Test {
    struct TokenSpec {
        string symbol;
        address token;
        address feed;
        uint32 epochs;
        uint48 cooldown;
    }

    address internal constant GATEWAY = 0x3f04b65Ddbd87f9CE0A2e7Eb24d80e7fb87625b5;
    address internal constant IUSD = 0x48f9e38f3070AD8945DFEae3FA70987722E3D89c;
    address internal constant LIUSD_4W = 0x66bCF6151D5558AfB47c38B20663589843156078;
    address internal constant LIUSD_13W = 0xbd3f9814eB946E617f1d774A6762cDbec0bf087A;
    address internal constant LIUSD_4W_FEED = 0xF8472D8D3Ef3f8aEb83A2B09aC69f40dF1ace66c;
    address internal constant LIUSD_13W_FEED = 0x8D5FFAa15730D87C90C34A4c2e80684043704417;
    address internal constant REDEEM_CONTROLLER = 0xCb1747E89a43DEdcF4A2b831a0D94859EFeC7601;
    address internal constant UNWINDING_MODULE = 0x7092A43aE5407666C78dBEA657a1891f42b3dFcc;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address internal adapter = makeAddr("adapter");
    string internal mainnetRpcUrl;

    function setUp() public {
        mainnetRpcUrl = vm.envOr("ETH_RPC_URL", string(""));
    }

    function testInfiniFiMainnetLockedTokenInterfaces() public {
        _forkMainnet();

        TokenSpec[2] memory specs = _specs();
        for (uint256 i; i < specs.length; ++i) {
            assertGt(specs[i].token.code.length, 0, specs[i].symbol);
            assertGt(specs[i].feed.code.length, 0, specs[i].symbol);
            assertEq(IERC20Metadata(specs[i].token).symbol(), specs[i].symbol);
            assertEq(IERC20Metadata(specs[i].token).decimals(), 18);
            assertEq(IInfiniFiLockedPositionToken(specs[i].token).transferRestrictions(address(this)), 0);
        }

        assertGt(GATEWAY.code.length, 0);
        assertGt(IUSD.code.length, 0);
        assertGt(REDEEM_CONTROLLER.code.length, 0);
        assertGt(UNWINDING_MODULE.code.length, 0);
        assertEq(IMainnetInfiniFiGateway(GATEWAY).getAddress("redeemController"), REDEEM_CONTROLLER);
        assertEq(IMainnetInfiniFiRedeemController(REDEEM_CONTROLLER).assetToken(), USDC);
        assertEq(IERC20Metadata(IUSD).decimals(), 18);
    }

    function _forkMainnet() internal {
        if (bytes(mainnetRpcUrl).length == 0) {
            vm.skip(true, "ETH_RPC_URL is required for InfiniFi mainnet checks");
        }
        uint256 forkBlock = vm.envOr("MAINNET_FORK_BLOCK", uint256(0));
        if (forkBlock == 0) {
            vm.createSelectFork(mainnetRpcUrl);
        } else {
            vm.createSelectFork(mainnetRpcUrl, forkBlock);
        }
    }

    function _specs() internal pure returns (TokenSpec[2] memory specs) {
        specs[0] = TokenSpec({symbol: "liUSD-4w", token: LIUSD_4W, feed: LIUSD_4W_FEED, epochs: 4, cooldown: 3 days});
        specs[1] =
            TokenSpec({symbol: "liUSD-13w", token: LIUSD_13W, feed: LIUSD_13W_FEED, epochs: 13, cooldown: 7 days});
    }
}

contract InfiniFiMainnetVault {
    address public constant asset = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
}

interface IInfiniFiLockedPositionToken {
    function transferRestrictions(address user) external view returns (uint256 timestamp);
}

interface IMainnetInfiniFiRedeemController {
    function assetToken() external view returns (address token);
}

interface IMainnetInfiniFiGateway {
    function getAddress(string calldata name) external view returns (address value);
}
