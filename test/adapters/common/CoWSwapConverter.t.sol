// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {CoWSwapConverter} from "../../../src/contracts/adapters/common/CoWSwapConverter.sol";
import {
    EXECUTION_DELAY,
    ICoWSwapConverter,
    MAX_VALID_TO_DURATION
} from "../../../src/interfaces/adapters/common/ICoWSwapConverter.sol";

import {Token} from "../../mocks/Token.sol";

contract CoWSwapConverterTest is Test {
    CoWSwapSettlementMock internal settlement;
    CoWSwapConverter internal converter;
    Token internal tokenIn;
    Token internal tokenOut;
    address internal owner = makeAddr("owner");
    address internal relayer = makeAddr("relayer");

    function setUp() public {
        vm.warp(100);

        settlement = new CoWSwapSettlementMock();
        tokenIn = new Token("Token In");
        tokenOut = new Token("Token Out");
        converter = new CoWSwapConverterHarness(owner, address(settlement), relayer, address(tokenOut));

        tokenIn.transfer(address(converter), 100);
    }

    function test_ConvertPresignsOrderAndApprovesRelayer() public {
        vm.prank(owner);
        converter.convert(address(tokenIn), 100, address(tokenOut), _orderData(100, 90, 0, 1));

        assertEq(settlement.lastOrderUid().length, 56);
        assertTrue(settlement.lastSigned());
        assertEq(tokenIn.allowance(address(converter), relayer), type(uint256).max);
    }

    function test_ConvertPresignsOrderWhenBalanceIsInsufficient() public {
        vm.prank(owner);
        converter.convert(address(tokenIn), 101, address(tokenOut), _orderData(101, 90, 0, 1));

        assertEq(settlement.lastOrderUid().length, 56);
        assertTrue(settlement.lastSigned());
        assertEq(tokenIn.allowance(address(converter), relayer), type(uint256).max);
    }

    function test_ConvertRevertsWhenTokenInIsVaultAsset() public {
        vm.expectRevert(ICoWSwapConverter.InvalidTokenIn.selector);
        converter.convert(address(tokenOut), 100, address(tokenOut), _orderData(100, 90, 0, 1));
    }

    function test_ConvertRevertsForInvalidOrderBounds() public {
        vm.expectRevert(ICoWSwapConverter.InvalidSellAmount.selector);
        vm.prank(owner);
        converter.convert(address(tokenIn), 100, address(tokenOut), _orderData(99, 90, 0, 1));

        vm.expectRevert(ICoWSwapConverter.ExpiredOrder.selector);
        vm.prank(owner);
        converter.convert(address(tokenIn), 100, address(tokenOut), _orderData(100, 90, 0, 3, uint32(block.timestamp)));

        vm.expectRevert(ICoWSwapConverter.TooFarValidTo.selector);
        vm.prank(owner);
        converter.convert(
            address(tokenIn),
            100,
            address(tokenOut),
            _orderData(100, 90, 0, 4, uint32(block.timestamp + MAX_VALID_TO_DURATION + 1))
        );
    }

    function test_ConvertChecksOrderBoundsBeforePreparedNonce() public {
        address caller = makeAddr("caller");

        vm.expectRevert(ICoWSwapConverter.InvalidSellAmount.selector);
        vm.prank(caller);
        converter.convert(address(tokenIn), 100, address(tokenOut), _orderData(99, 90, 0, 1));

        vm.expectRevert(ICoWSwapConverter.ExpiredOrder.selector);
        vm.prank(caller);
        converter.convert(address(tokenIn), 100, address(tokenOut), _orderData(100, 90, 0, 3, uint32(block.timestamp)));

        vm.expectRevert(ICoWSwapConverter.TooFarValidTo.selector);
        vm.prank(caller);
        converter.convert(
            address(tokenIn),
            100,
            address(tokenOut),
            _orderData(100, 90, 0, 4, uint32(block.timestamp + MAX_VALID_TO_DURATION + 1))
        );
    }

    function test_PrepareConvertAllowsPublicExecutionAfterDelayIfNonceUnchanged() public {
        address caller = makeAddr("caller");
        bytes memory data = _orderData(100, 90, 0, 1, uint32(block.timestamp + EXECUTION_DELAY + MAX_VALID_TO_DURATION));

        bytes32 requestHash = converter.prepareConvert(address(tokenIn), 100, address(tokenOut), data);
        uint48 timestamp = converter.executableAt(0, requestHash);

        assertEq(timestamp, block.timestamp + EXECUTION_DELAY);

        vm.expectRevert(ICoWSwapConverter.TooFarValidTo.selector);
        vm.prank(caller);
        converter.convert(address(tokenIn), 100, address(tokenOut), data);

        vm.warp(block.timestamp + EXECUTION_DELAY);
        vm.prank(caller);
        converter.convert(address(tokenIn), 100, address(tokenOut), data);

        assertEq(converter.nonces(address(tokenIn)), 1);
        assertEq(settlement.lastOrderUid().length, 56);
        assertTrue(settlement.lastSigned());
    }

    function test_PreparedConvertRevertsWhenTokenOutChanges() public {
        address caller = makeAddr("caller");
        Token otherTokenOut = new Token("Other Token Out");
        bytes memory data = _orderData(100, 90, 0, 1, uint32(block.timestamp + EXECUTION_DELAY + MAX_VALID_TO_DURATION));
        converter.prepareConvert(address(tokenIn), 100, address(tokenOut), data);

        vm.warp(block.timestamp + EXECUTION_DELAY);
        vm.expectRevert(ICoWSwapConverter.InvalidNonce.selector);
        vm.prank(caller);
        converter.convert(address(tokenIn), 100, address(otherTokenOut), data);
    }

    function test_PreparedConvertRevertsWhenNonceChanged() public {
        address caller = makeAddr("caller");
        bytes memory data = _orderData(100, 90, 0, 1, uint32(block.timestamp + EXECUTION_DELAY + MAX_VALID_TO_DURATION));
        converter.prepareConvert(address(tokenIn), 100, address(tokenOut), data);

        vm.prank(owner);
        converter.convert(address(tokenIn), 100, address(tokenOut), _orderData(100, 80, 0, 2));

        vm.warp(block.timestamp + EXECUTION_DELAY);
        vm.expectRevert(ICoWSwapConverter.InvalidNonce.selector);
        vm.prank(caller);
        converter.convert(address(tokenIn), 100, address(tokenOut), data);
    }

    function _orderData(uint256 sellAmount, uint256 buyAmount, uint256 feeAmount, uint256 salt)
        internal
        view
        returns (bytes memory)
    {
        return _orderData(sellAmount, buyAmount, feeAmount, salt, uint32(block.timestamp + MAX_VALID_TO_DURATION));
    }

    function _orderData(uint256 sellAmount, uint256 buyAmount, uint256 feeAmount, uint256 salt, uint32 validTo)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(
            ICoWSwapConverter.OrderParams({
                sellAmount: sellAmount,
                buyAmount: buyAmount,
                validTo: validTo,
                appData: bytes32(salt),
                feeAmount: feeAmount
            })
        );
    }
}

contract CoWSwapConverterHarness is CoWSwapConverter {
    address internal immutable OWNER;

    constructor(address owner_, address settlement, address relayer, address asset)
        CoWSwapConverter(address(0), address(0), settlement, relayer)
    {
        OWNER = owner_;
        vault = address(new CoWSwapVaultMock(asset));
    }

    function owner() public view override returns (address) {
        return OWNER;
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
