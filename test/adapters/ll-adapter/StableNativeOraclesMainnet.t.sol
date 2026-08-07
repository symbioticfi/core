// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ERC4626Oracle} from "../../../src/contracts/adapters/ll-adapter/oracles/ERC4626Oracle.sol";
import {NoonOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/NoonOracle.sol";
import {sUSN_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/sUSN_Account.sol";
import {sthUSD_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/sthUSD_Account.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
import {INoonWithdrawalHandler} from "../../../src/interfaces/adapters/ll-adapter/noon/INoonWithdrawalHandler.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract StableNativeOraclesMainnetTest is Test {
    uint256 internal constant FORK_BLOCK = 25_675_677;

    address internal constant COW_SWAP_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address internal constant SUSN = 0xE24a3DC889621612422A64E6388927901608B91D;
    address internal constant USN = 0xdA67B4284609d2d48e5d10cfAc411572727dc1eD;
    address internal constant NOON_WITHDRAWAL_HANDLER = 0x0DaBc0D9B270c9B0C4C77AaCeAa712b56D0F9178;
    address internal constant NOON_RATE_PROVIDER = 0x7f741401422Afff770360fD13127F7462C6E1A79;
    address internal constant STHUSD = 0xA808Bc9775cb41c52C7842f8b50427fE7A770326;
    address internal constant THUSD = 0xa3fE5c7596024E6811E14F029937D5bd8Ae485b3;

    uint256 internal forkBlock;
    string internal mainnetRpcUrl;

    function setUp() public {
        mainnetRpcUrl = vm.envOr("ETH_RPC_URL", string(""));
    }

    function testStableNativeOracleMainnetTopologyAndPrices() public {
        _forkMainnet();
        if (forkBlock != 0) {
            assertEq(block.number, forkBlock);
        }

        address usn = IERC4626(SUSN).asset();
        address thUSD = IERC4626(STHUSD).asset();
        assertGt(SUSN.code.length, 0);
        assertGt(usn.code.length, 0);
        assertGt(NOON_WITHDRAWAL_HANDLER.code.length, 0);
        assertGt(NOON_RATE_PROVIDER.code.length, 0);
        assertGt(STHUSD.code.length, 0);
        assertGt(thUSD.code.length, 0);
        assertEq(usn, USN);
        assertEq(thUSD, THUSD);
        assertEq(INoonWithdrawalHandler(NOON_WITHDRAWAL_HANDLER).usn(), USN);
        assertEq(IERC20Metadata(SUSN).decimals(), 18);
        assertEq(IERC20Metadata(USN).decimals(), 18);
        assertEq(IERC20Metadata(STHUSD).decimals(), 6);
        assertEq(IERC20Metadata(THUSD).decimals(), 6);

        MigratablesFactory factory = new MigratablesFactory(address(this));
        sUSN_Account susnAccount = new sUSN_Account(address(factory), COW_SWAP_SETTLEMENT);
        sthUSD_Account sthusdAccount = new sthUSD_Account(address(factory), COW_SWAP_SETTLEMENT);
        NoonOracle noonOracle = NoonOracle(susnAccount.ORACLE());
        ERC4626Oracle erc4626Oracle = ERC4626Oracle(sthusdAccount.ORACLE());

        assertEq(susnAccount.TOKEN_TO_REDEEM(), SUSN);
        assertEq(susnAccount.WITHDRAWAL_HANDLER(), NOON_WITHDRAWAL_HANDLER);
        assertEq(noonOracle.RATE_PROVIDER(), NOON_RATE_PROVIDER);
        assertEq(noonOracle.QUOTE_TOKEN(), usn);
        assertEq(sthusdAccount.TOKEN_TO_REDEEM(), STHUSD);
        assertEq(erc4626Oracle.VAULT(), STHUSD);

        uint256 susnPrice = noonOracle.getPrice();
        uint256 sthusdPrice = erc4626Oracle.getPrice();
        assertGe(susnPrice, 0.5e18);
        assertLe(susnPrice, 2.5e18);
        assertGe(sthusdPrice, 0.5e18);
        assertLe(sthusdPrice, 2.5e18);
        assertGt(susnPrice, 1e18);
        assertGt(sthusdPrice, 1e18);
        if (forkBlock == FORK_BLOCK) {
            assertApproxEqAbs(susnPrice, 1_212_230_212_000_738_930, 1e12);
            assertApproxEqAbs(sthusdPrice, 1_015_160_000_000_000_000, 1e12);
        }
    }

    function _forkMainnet() internal {
        if (bytes(mainnetRpcUrl).length == 0) {
            vm.skip(true, "ETH_RPC_URL is required for stable-native mainnet checks");
        }
        forkBlock = vm.envOr("MAINNET_FORK_BLOCK", uint256(0));
        if (forkBlock == 0) {
            vm.createSelectFork(mainnetRpcUrl);
        } else {
            vm.createSelectFork(mainnetRpcUrl, forkBlock);
        }
    }
}
