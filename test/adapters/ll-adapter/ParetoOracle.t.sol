// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MockERC20} from "./AccountsBase.t.sol";

import {ParetoOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/ParetoOracle.sol";
import {IParetoOracle} from "../../../src/interfaces/adapters/ll-adapter/oracles/IParetoOracle.sol";
import {IOracle} from "../../../src/interfaces/adapters/ll-adapter/IOracle.sol";

import {Test} from "forge-std/Test.sol";

contract ParetoOracleTest is Test {
    MockERC20 internal tranche;
    ParetoOracleTestCDO internal cdo;
    ParetoOracle internal oracle;

    function setUp() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        tranche = new MockERC20("Pareto AA Tranche", "AA_TEST", 18);
        cdo = new ParetoOracleTestCDO(address(usdc), address(tranche), 1_094_752);
        oracle = new ParetoOracle(1e18, 12e17, address(tranche), address(cdo));
    }

    function test_GetPrice_NormalizesUnderlyingDecimalsToOneE18() public view {
        assertEq(oracle.getPrice(), 1_094_752e12);
    }

    function test_Constructor_RevertsForTokenOutsideCDO() public {
        MockERC20 other = new MockERC20("Other", "OTHER", 18);

        vm.expectRevert(IParetoOracle.InvalidTranche.selector);
        new ParetoOracle(1e18, 12e17, address(other), address(cdo));
    }

    function test_GetPrice_RevertsOutsideBounds() public {
        cdo.setVirtualPrice(999_999);
        vm.expectRevert(IOracle.InvalidPrice.selector);
        oracle.getPrice();

        cdo.setVirtualPrice(1_200_001);
        vm.expectRevert(IOracle.InvalidPrice.selector);
        oracle.getPrice();
    }
}

contract ParetoOracleTestCDO {
    address public immutable token;
    address public immutable AATranche;
    uint256 internal _virtualPrice;

    constructor(address token_, address tranche_, uint256 virtualPrice_) {
        token = token_;
        AATranche = tranche_;
        _virtualPrice = virtualPrice_;
    }

    function setVirtualPrice(uint256 virtualPrice_) external {
        _virtualPrice = virtualPrice_;
    }

    function virtualPrice(address tranche) external view returns (uint256 price) {
        assert(tranche == AATranche);
        price = _virtualPrice;
    }
}
