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
        tokenIn = new Token("Token In");
        tokenOut = new Token("Token Out");
        converter = new CoWSwapConverterHarness(address(settlement), relayer, 1 hours, address(tokenOut));

        tokenIn.transfer(address(converter), 100);
    }

    function test_ConvertPresignsOrderAndApprovesRelayer() public {
        converter.convert(address(tokenIn), address(tokenOut), 100, 90, _orderData(100, 90, 0, 1));

        assertEq(settlement.lastOrderUid().length, 56);
        assertTrue(settlement.lastSigned());
        assertEq(tokenIn.allowance(address(converter), relayer), type(uint256).max);
    }

    function test_ConvertRevertsWhenBalanceIsInsufficient() public {
        vm.expectRevert(ICoWSwapConverter.InsufficientSellBalance.selector);
        converter.convert(address(tokenIn), address(tokenOut), 101, 90, _orderData(101, 90, 0, 1));
    }

    function test_ConvertRevertsWhenTokenInIsVaultAsset() public {
        vm.expectRevert(ICoWSwapConverter.InvalidTokenIn.selector);
        converter.convert(address(tokenOut), address(tokenIn), 100, 90, _orderData(100, 90, 0, 1));
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

contract CoWSwapConverterHarness is CoWSwapConverter {
    constructor(address settlement, address relayer, uint32 maxValidToDuration, address asset)
        CoWSwapConverter(address(0), address(0), address(0), settlement, relayer, maxValidToDuration)
    {
        vault = address(new CoWSwapVaultMock(asset));
    }

    function totalAssets() public pure override returns (uint256) {
        return 0;
    }

    function _allocate(uint256) internal pure override returns (uint256) {
        return 0;
    }

    function _deallocate(uint256) internal pure override returns (uint256) {
        return 0;
    }
}

contract CoWSwapVaultMock {
    address public asset;

    constructor(address asset_) {
        asset = asset_;
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
