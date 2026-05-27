// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {CoWSwapConverter} from "../../../src/contracts/adapters/common/CoWSwapConverter.sol";
import {ICoWSwapConverter} from "../../../src/interfaces/adapters/common/ICoWSwapConverter.sol";

import {Token} from "../../mocks/Token.sol";

contract CoWSwapConverterTest is Test {
    CoWSwapSettlementMock internal settlement;
    CoWSwapConverter internal converter;
    Token internal tokenIn;
    Token internal tokenOut;
    address internal relayer = makeAddr("relayer");

    function setUp() public {
        vm.warp(100);

        settlement = new CoWSwapSettlementMock();
        converter = new CoWSwapConverter(address(settlement), relayer, 1 hours);
        tokenIn = new Token("Token In");
        tokenOut = new Token("Token Out");

        tokenIn.transfer(address(converter), 100);
    }

    function test_ConvertReservesSellBalanceAgainstDuplicateOutstandingOrders() public {
        converter.convert(address(tokenIn), address(tokenOut), 100, 90, _orderData(100, 90, 0, 1));

        vm.expectRevert(ICoWSwapConverter.InsufficientSellBalance.selector);
        converter.convert(address(tokenIn), address(tokenOut), 100, 90, _orderData(100, 90, 0, 2));

        assertEq(converter.reservedSellBalance(address(tokenIn)), 100);
    }

    function test_ReleaseExpiredOrderFreesReservedSellBalance() public {
        converter.convert(address(tokenIn), address(tokenOut), 100, 90, _orderData(100, 90, 0, 1));
        bytes memory orderUid = settlement.lastOrderUid();

        vm.warp(block.timestamp + 1 hours + 1);
        converter.releaseExpiredOrder(orderUid);

        assertEq(converter.reservedSellBalance(address(tokenIn)), 0);

        converter.convert(address(tokenIn), address(tokenOut), 100, 90, _orderData(100, 90, 0, 2));
        assertEq(converter.reservedSellBalance(address(tokenIn)), 100);
    }

    function _orderData(uint256 sellAmount, uint256 buyAmount, uint256 feeAmount, uint256 salt)
        internal
        view
        returns (bytes memory)
    {
        return abi.encode(
            ICoWSwapConverter.OrderParams({
                sellAmount: sellAmount,
                buyAmount: buyAmount,
                validTo: uint32(block.timestamp + 1 hours),
                appData: bytes32(salt),
                feeAmount: feeAmount
            })
        );
    }
}

contract CoWSwapSettlementMock {
    bytes32 public domainSeparator = keccak256("DOMAIN");
    bytes public lastOrderUid;
    bool public lastSigned;

    function setPreSignature(bytes calldata orderUid, bool signed) external {
        lastOrderUid = orderUid;
        lastSigned = signed;
    }
}
