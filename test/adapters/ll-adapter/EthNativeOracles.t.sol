// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {WeETHOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/WeETHOracle.sol";
import {WstETHOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/WstETHOracle.sol";
import {IOracle} from "../../../src/interfaces/adapters/ll-adapter/IOracle.sol";

contract EthNativeOraclesTest is Test {
    uint256 internal constant MIN_PRICE = 0.5e18;
    uint256 internal constant MAX_PRICE = 2.5e18;

    function testWeETHOracleReturnsOneWeETHInEETH() public {
        MockWeETHRateSource source = new MockWeETHRateSource(1.125e18);
        WeETHOracle oracle = new WeETHOracle(MIN_PRICE, MAX_PRICE, address(source));

        assertEq(oracle.getPrice(), 1.125e18);
    }

    function testWeETHOracleRejectsZeroPrice() public {
        WeETHOracle oracle = new WeETHOracle(MIN_PRICE, MAX_PRICE, address(new MockWeETHRateSource(0)));

        vm.expectRevert(IOracle.InvalidPrice.selector);
        oracle.getPrice();
    }

    function testWeETHOracleRejectsPriceBelowBound() public {
        WeETHOracle oracle = new WeETHOracle(MIN_PRICE, MAX_PRICE, address(new MockWeETHRateSource(MIN_PRICE - 1)));

        vm.expectRevert(IOracle.InvalidPrice.selector);
        oracle.getPrice();
    }

    function testWeETHOracleRejectsPriceAboveBound() public {
        WeETHOracle oracle = new WeETHOracle(MIN_PRICE, MAX_PRICE, address(new MockWeETHRateSource(MAX_PRICE + 1)));

        vm.expectRevert(IOracle.InvalidPrice.selector);
        oracle.getPrice();
    }

    function testWstETHOracleReturnsOneWstETHInStETH() public {
        MockWstETHRateSource source = new MockWstETHRateSource(1.25e18);
        WstETHOracle oracle = new WstETHOracle(MIN_PRICE, MAX_PRICE, address(source));

        assertEq(oracle.getPrice(), 1.25e18);
    }

    function testWstETHOracleRejectsZeroPrice() public {
        WstETHOracle oracle = new WstETHOracle(MIN_PRICE, MAX_PRICE, address(new MockWstETHRateSource(0)));

        vm.expectRevert(IOracle.InvalidPrice.selector);
        oracle.getPrice();
    }

    function testWstETHOracleRejectsPriceBelowBound() public {
        WstETHOracle oracle = new WstETHOracle(MIN_PRICE, MAX_PRICE, address(new MockWstETHRateSource(MIN_PRICE - 1)));

        vm.expectRevert(IOracle.InvalidPrice.selector);
        oracle.getPrice();
    }

    function testWstETHOracleRejectsPriceAboveBound() public {
        WstETHOracle oracle = new WstETHOracle(MIN_PRICE, MAX_PRICE, address(new MockWstETHRateSource(MAX_PRICE + 1)));

        vm.expectRevert(IOracle.InvalidPrice.selector);
        oracle.getPrice();
    }
}

contract MockWeETHRateSource {
    uint256 internal immutable _rate;

    constructor(uint256 rate) {
        _rate = rate;
    }

    function getEETHByWeETH(uint256 amount) external view returns (uint256) {
        return amount == 1e18 ? _rate : 1;
    }
}

contract MockWstETHRateSource {
    uint256 internal immutable _rate;

    constructor(uint256 rate) {
        _rate = rate;
    }

    function getStETHByWstETH(uint256 amount) external view returns (uint256) {
        return amount == 1e18 ? _rate : 1;
    }
}
