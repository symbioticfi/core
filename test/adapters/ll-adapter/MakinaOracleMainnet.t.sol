// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {DUSD_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/DUSD_Account.sol";
import {MakinaOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/MakinaOracle.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
import {IMakinaMachine} from "../../../src/interfaces/adapters/ll-adapter/makina/IMakinaMachine.sol";

contract MakinaOracleMainnetTest is Test {
    address internal constant COW_SWAP_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address internal constant DUSD = 0x1e33E98aF620F1D563fcD3cfd3C75acE841204ef;
    address internal constant MACHINE = 0x6b006870C83b1Cd49E766Ac9209f8d68763Df721;
    address internal constant REDEEMER = 0x1303c26cFE06bac5bfEE29907f37919643DEF75c;
    address internal constant SHARE_PRICE_ORACLE = 0xFFCBc7A7eEF2796C277095C66067aC749f4cA078;

    string internal mainnetRpcUrl;

    function setUp() public {
        mainnetRpcUrl = vm.envOr("ETH_RPC_URL", string(""));
    }

    function testDUSDAccountBindsFreshMakinaAccounting() public {
        _forkMainnet();

        assertGt(DUSD.code.length, 0);
        assertGt(MACHINE.code.length, 0);
        assertGt(REDEEMER.code.length, 0);
        assertGt(SHARE_PRICE_ORACLE.code.length, 0);

        MigratablesFactory factory = new MigratablesFactory(address(this));
        DUSD_Account implementation = new DUSD_Account(address(factory), COW_SWAP_SETTLEMENT);
        MakinaOracle oracle = MakinaOracle(implementation.ORACLE());

        assertEq(implementation.TOKEN_TO_REDEEM(), DUSD);
        assertEq(implementation.REDEEMER(), REDEEMER);
        assertEq(oracle.MACHINE(), MACHINE);
        assertEq(oracle.SHARE_PRICE_ORACLE(), SHARE_PRICE_ORACLE);
        assertEq(oracle.STALENESS_DURATION(), 48 hours);

        uint256 updatedAt = IMakinaMachine(MACHINE).lastGlobalAccountingTime();
        assertLe(updatedAt, block.timestamp);
        assertLe(block.timestamp - updatedAt, oracle.STALENESS_DURATION());
        assertGe(oracle.getPrice(), oracle.MIN_PRICE());
        assertLe(oracle.getPrice(), oracle.MAX_PRICE());
    }

    function _forkMainnet() internal {
        if (bytes(mainnetRpcUrl).length == 0) {
            vm.skip(true, "ETH_RPC_URL is required for Makina oracle mainnet checks");
        }
        uint256 forkBlock = vm.envOr("MAINNET_FORK_BLOCK", uint256(0));
        if (forkBlock == 0) {
            vm.createSelectFork(mainnetRpcUrl);
        } else {
            vm.createSelectFork(mainnetRpcUrl, forkBlock);
        }
    }
}
