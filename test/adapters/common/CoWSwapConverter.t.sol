// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Adapter} from "../../../src/contracts/adapters/Adapter.sol";
import {CoWSwapConverter} from "../../../src/contracts/adapters/common/CoWSwapConverter.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
import {Registry} from "../../../src/contracts/common/Registry.sol";
import {
    EXECUTION_DELAY,
    ICoWSwapConverter,
    MAX_VALID_TO_DURATION
} from "../../../src/interfaces/adapters/common/ICoWSwapConverter.sol";

import {Token} from "../../mocks/Token.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract CoWSwapConverterTest is Test {
    CoWSwapSettlementMock internal settlement;
    CoWSwapConverterHarness internal converter;
    Token internal tokenIn;
    Token internal tokenOut;
    CoWSwapVaultRegistryMock internal vaultFactory;
    MigratablesFactory internal adapterFactory;
    CoWSwapVaultMock internal vault;
    address internal owner = makeAddr("owner");
    address internal converterRoleHolder = makeAddr("converterRoleHolder");
    address internal relayer = makeAddr("relayer");

    function setUp() public {
        vm.warp(100);

        settlement = new CoWSwapSettlementMock();
        tokenIn = new Token("Token In");
        tokenOut = new Token("Token Out");
        vaultFactory = new CoWSwapVaultRegistryMock();
        adapterFactory = new MigratablesFactory(owner);
        vault = new CoWSwapVaultMock(address(tokenOut));
        vaultFactory.add(address(vault));

        CoWSwapConverterHarness implementation =
            new CoWSwapConverterHarness(address(vaultFactory), address(adapterFactory), address(settlement), relayer);

        vm.startPrank(owner);
        adapterFactory.whitelist(address(implementation));
        converter = CoWSwapConverterHarness(adapterFactory.create(1, owner, _initData()));
        vm.stopPrank();

        tokenIn.transfer(address(converter), 100);
    }

    function test_InitializeRegistersConverterFromInitData() public view {
        assertEq(converter.owner(), owner);
        assertTrue(converter.isConverter(converterRoleHolder));
    }

    function test_ConvertPresignsOrderAndApprovesRelayer() public {
        vm.prank(converterRoleHolder);
        converter.convert(address(tokenIn), 100, address(tokenOut), _orderData(100, 90, 0, 1));

        assertEq(settlement.lastOrderUid().length, 56);
        assertTrue(settlement.lastSigned());
        assertEq(tokenIn.allowance(address(converter), relayer), type(uint256).max);
    }

    function test_ConverterCanConvertWithoutPreparedNonce() public {
        address newConverter = makeAddr("newConverter");

        vm.prank(owner);
        converter.setConverterStatus(newConverter, true);

        vm.prank(newConverter);
        converter.convert(address(tokenIn), 100, address(tokenOut), _orderData(100, 90, 0, 1));

        assertEq(converter.nonces(address(tokenIn)), 1);
        assertEq(settlement.lastOrderUid().length, 56);
        assertTrue(settlement.lastSigned());
    }

    function test_SetConverterStatusRevertsForNonOwner() public {
        address newConverter = makeAddr("newConverter");

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        converter.setConverterStatus(newConverter, true);
    }

    function test_SetConverterStatusCanDisableConverter() public {
        vm.prank(owner);
        converter.setConverterStatus(converterRoleHolder, false);

        assertFalse(converter.isConverter(converterRoleHolder));
    }

    function test_ConvertPresignsOrderWhenBalanceIsInsufficient() public {
        vm.prank(converterRoleHolder);
        converter.convert(address(tokenIn), 101, address(tokenOut), _orderData(101, 90, 0, 1));

        assertEq(settlement.lastOrderUid().length, 56);
        assertTrue(settlement.lastSigned());
        assertEq(tokenIn.allowance(address(converter), relayer), type(uint256).max);
    }

    function test_ConvertAllowsVaultAssetInputAtBaseConverterLevel() public {
        vm.prank(converterRoleHolder);
        converter.convert(address(tokenOut), 100, address(tokenOut), _orderData(100, 90, 0, 1));

        assertEq(settlement.lastOrderUid().length, 56);
        assertTrue(settlement.lastSigned());
    }

    function test_ConvertRevertsForInvalidOrderBounds() public {
        vm.expectRevert(ICoWSwapConverter.InvalidSellAmount.selector);
        vm.prank(converterRoleHolder);
        converter.convert(address(tokenIn), 100, address(tokenOut), _orderData(99, 90, 0, 1));

        vm.expectRevert(ICoWSwapConverter.ExpiredOrder.selector);
        vm.prank(converterRoleHolder);
        converter.convert(
            address(tokenIn), 100, address(tokenOut), _orderData(100, 90, 0, 3, uint48(vm.getBlockTimestamp()))
        );

        vm.expectRevert(ICoWSwapConverter.TooFarValidTo.selector);
        vm.prank(converterRoleHolder);
        converter.convert(
            address(tokenIn),
            100,
            address(tokenOut),
            _orderData(100, 90, 0, 4, uint48(vm.getBlockTimestamp() + MAX_VALID_TO_DURATION + 1))
        );
    }

    function test_ConvertChecksOrderBoundsBeforePreparedNonce() public {
        address caller = makeAddr("caller");

        vm.expectRevert(ICoWSwapConverter.InvalidSellAmount.selector);
        vm.prank(caller);
        converter.convert(address(tokenIn), 100, address(tokenOut), _orderData(99, 90, 0, 1));

        vm.expectRevert(ICoWSwapConverter.ExpiredOrder.selector);
        vm.prank(caller);
        converter.convert(
            address(tokenIn), 100, address(tokenOut), _orderData(100, 90, 0, 3, uint48(vm.getBlockTimestamp()))
        );

        vm.expectRevert(ICoWSwapConverter.TooFarValidTo.selector);
        vm.prank(caller);
        converter.convert(
            address(tokenIn),
            100,
            address(tokenOut),
            _orderData(100, 90, 0, 4, uint48(vm.getBlockTimestamp() + MAX_VALID_TO_DURATION + 1))
        );
    }

    function test_PrepareConvertAllowsPublicExecutionAfterDelayIfNonceUnchanged() public {
        address caller = makeAddr("caller");
        bytes memory data =
            _orderData(100, 90, 0, 1, uint48(vm.getBlockTimestamp() + EXECUTION_DELAY + MAX_VALID_TO_DURATION));

        bytes32 requestHash = converter.prepareConvert(address(tokenIn), 100, address(tokenOut), data);
        uint48 timestamp = converter.executableAt(0, requestHash);

        assertEq(timestamp, vm.getBlockTimestamp() + EXECUTION_DELAY);

        vm.expectRevert(ICoWSwapConverter.TooFarValidTo.selector);
        vm.prank(caller);
        converter.convert(address(tokenIn), 100, address(tokenOut), data);

        vm.warp(vm.getBlockTimestamp() + EXECUTION_DELAY);
        vm.prank(caller);
        converter.convert(address(tokenIn), 100, address(tokenOut), data);

        assertEq(converter.nonces(address(tokenIn)), 1);
        assertEq(settlement.lastOrderUid().length, 56);
        assertTrue(settlement.lastSigned());
    }

    function test_PreparedConvertRevertsWhenTokenOutChanges() public {
        address caller = makeAddr("caller");
        Token otherTokenOut = new Token("Other Token Out");
        bytes memory data =
            _orderData(100, 90, 0, 1, uint48(vm.getBlockTimestamp() + EXECUTION_DELAY + MAX_VALID_TO_DURATION));
        converter.prepareConvert(address(tokenIn), 100, address(tokenOut), data);

        vm.warp(vm.getBlockTimestamp() + EXECUTION_DELAY);
        vm.expectRevert(ICoWSwapConverter.InvalidNonce.selector);
        vm.prank(caller);
        converter.convert(address(tokenIn), 100, address(otherTokenOut), data);
    }

    function test_PreparedConvertRevertsWhenNonceChanged() public {
        address caller = makeAddr("caller");
        bytes memory data =
            _orderData(100, 90, 0, 1, uint48(vm.getBlockTimestamp() + EXECUTION_DELAY + MAX_VALID_TO_DURATION));
        converter.prepareConvert(address(tokenIn), 100, address(tokenOut), data);

        vm.prank(converterRoleHolder);
        converter.convert(address(tokenIn), 100, address(tokenOut), _orderData(100, 80, 0, 2));

        vm.warp(vm.getBlockTimestamp() + EXECUTION_DELAY);
        vm.expectRevert(ICoWSwapConverter.InvalidNonce.selector);
        vm.prank(caller);
        converter.convert(address(tokenIn), 100, address(tokenOut), data);
    }

    function _orderData(uint256 sellAmount, uint256 buyAmount, uint256 feeAmount, uint256 salt)
        internal
        view
        returns (bytes memory)
    {
        return
            _orderData(sellAmount, buyAmount, feeAmount, salt, uint48(vm.getBlockTimestamp() + MAX_VALID_TO_DURATION));
    }

    function _orderData(uint256 sellAmount, uint256 buyAmount, uint256 feeAmount, uint256 salt, uint48 validTo)
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

    function _initData() internal view returns (bytes memory) {
        address[] memory converters = new address[](1);
        converters[0] = converterRoleHolder;
        return abi.encode(address(vault), abi.encode(converters));
    }
}

contract CoWSwapConverterHarness is Adapter, CoWSwapConverter {
    constructor(address vaultFactory, address adapterFactory, address settlement, address relayer)
        Adapter(vaultFactory, adapterFactory)
        CoWSwapConverter(settlement, relayer)
    {}

    function totalAssets() public pure override returns (uint256) {
        return 0;
    }

    function __initialize(address, bytes memory data) internal override {
        __CoWSwapConverter_init(abi.decode(data, (address[])));
    }

    function _allocate(uint256) internal pure override returns (uint256) {
        return 0;
    }

    function _deallocate(uint256) internal pure override returns (uint256) {
        return 0;
    }
}

contract CoWSwapVaultRegistryMock is Registry {
    function add(address entity) external {
        _addEntity(entity);
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
