// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Adapter} from "../../../src/contracts/adapters/Adapter.sol";
import {CoWSwapConverter} from "../../../src/contracts/adapters/common/CoWSwapConverter.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
import {Registry} from "../../../src/contracts/common/Registry.sol";
import {
    COW_SWAP_BALANCE_ERC20,
    COW_SWAP_KIND_SELL,
    COW_SWAP_ORDER_UID_LENGTH,
    EXECUTION_DELAY,
    ICoWSwapConverter,
    MAX_VALID_TO_DURATION
} from "../../../src/interfaces/adapters/common/ICoWSwapConverter.sol";

import {Token} from "../../mocks/Token.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract CoWSwapConverterTest is Test {
    bytes32 internal constant OZ_NONCES_STORAGE_LOCATION =
        0x5ab42ced628888259c08ac98db1eb0cf702fc1501344311d8b100cd1bfe4bb00;

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

        settlement = new CoWSwapSettlementMock(relayer);
        tokenIn = new Token("Token In");
        tokenOut = new Token("Token Out");
        vaultFactory = new CoWSwapVaultRegistryMock();
        adapterFactory = new MigratablesFactory(owner);
        vault = new CoWSwapVaultMock(address(tokenOut));
        vaultFactory.add(address(vault));

        CoWSwapConverterHarness implementation =
            new CoWSwapConverterHarness(address(vaultFactory), address(adapterFactory), address(settlement));

        vm.startPrank(owner);
        adapterFactory.whitelist(address(implementation));
        converter = CoWSwapConverterHarness(adapterFactory.create(1, owner, _initData()));
        vm.stopPrank();

        tokenIn.transfer(address(converter), 100);
    }

    function test_InitializeRegistersConverterFromInitData() public view {
        assertEq(converter.owner(), owner);
        assertEq(converter.converters(0), converterRoleHolder);
    }

    function test_ComputeOrderUidMatchesCanonicalMainnetFixture() public view {
        address orderOwner = 0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa;
        uint32 validTo = 2200;
        bytes memory orderUid = converter.computeOrderUid(
            ICoWSwapConverter.Data({
                sellToken: 0x9994E35Db50125E0DF82e4c2dde62496CE330999,
                buyToken: 0x1111111111111111111111111111111111111111,
                receiver: orderOwner,
                sellAmount: 5,
                buyAmount: 990_000,
                validTo: validTo,
                appData: 0x412c256874305de3f4aa0f8391d6f829d4918f6ea6ef32931c6ed62a3e2bc897,
                feeAmount: 0,
                kind: COW_SWAP_KIND_SELL,
                partiallyFillable: true,
                sellTokenBalance: COW_SWAP_BALANCE_ERC20,
                buyTokenBalance: COW_SWAP_BALANCE_ERC20
            }),
            0xc078f884a2676e1345748b1feace7b0abee5d00ecadb6e574dcdd109a63e8943,
            orderOwner,
            validTo
        );

        assertEq(
            orderUid,
            hex"fddd8f2e7930f6882586ca5be3923ece8b3479e55e144e4d029bf77b36cd143aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa00000898"
        );
    }

    function test_ConvertPresignsOrderAndApprovesRelayer() public {
        vm.prank(converterRoleHolder);
        converter.convert(address(tokenIn), 100, address(tokenOut), _orderData(90, 1));

        assertEq(settlement.lastOrderUid().length, 56);
        assertTrue(settlement.lastSigned());
        assertEq(tokenIn.allowance(address(converter), relayer), type(uint256).max);
    }

    function test_InvalidateConvertClearsOrderPreSignature() public {
        vm.prank(converterRoleHolder);
        converter.convert(address(tokenIn), 100, address(tokenOut), _orderData(90, 1));

        bytes memory orderUid = settlement.lastOrderUid();

        vm.prank(converterRoleHolder);
        converter.invalidateConvert(orderUid);

        assertEq(settlement.lastOrderUid(), orderUid);
        assertFalse(settlement.lastSigned());
    }

    function test_InvalidateConvertRevertsForNonConverter() public {
        vm.prank(converterRoleHolder);
        converter.convert(address(tokenIn), 100, address(tokenOut), _orderData(90, 1));

        bytes memory orderUid = settlement.lastOrderUid();

        vm.expectRevert(ICoWSwapConverter.InvalidCaller.selector);
        converter.invalidateConvert(orderUid);
    }

    function test_InvalidateConvertsInvalidatesPreparedRequestsForToken() public {
        address caller = makeAddr("caller");
        bytes memory data = _orderData(90, 1, uint32(vm.getBlockTimestamp() + EXECUTION_DELAY + MAX_VALID_TO_DURATION));

        bytes32 requestHash = converter.prepareConvert(address(tokenIn), 100, address(tokenOut), data);
        assertEq(converter.executableAt(0, requestHash), vm.getBlockTimestamp() + EXECUTION_DELAY);

        vm.expectEmit(address(converter));
        emit ICoWSwapConverter.InvalidateConverts(address(tokenIn));
        vm.prank(converterRoleHolder);
        converter.invalidateConverts(address(tokenIn));

        assertEq(converter.nonces(address(tokenIn)), 1);

        vm.warp(vm.getBlockTimestamp() + EXECUTION_DELAY);
        vm.expectRevert(ICoWSwapConverter.ExecutionDelayNotElapsed.selector);
        vm.prank(caller);
        converter.convert(address(tokenIn), 100, address(tokenOut), data);

        bytes memory newData =
            _orderData(90, 2, uint32(vm.getBlockTimestamp() + EXECUTION_DELAY + MAX_VALID_TO_DURATION));
        bytes32 newRequestHash = converter.prepareConvert(address(tokenIn), 100, address(tokenOut), newData);
        assertEq(converter.executableAt(1, newRequestHash), vm.getBlockTimestamp() + EXECUTION_DELAY);
    }

    function test_InvalidateConvertsRevertsForNonConverter() public {
        vm.expectRevert(ICoWSwapConverter.InvalidCaller.selector);
        converter.invalidateConverts(address(tokenIn));
    }

    function test_ConverterCanConvertWithoutPreparedNonce() public {
        address newConverter = makeAddr("newConverter");

        vm.prank(owner);
        converter.setConverters(_converters(newConverter));

        vm.prank(newConverter);
        converter.convert(address(tokenIn), 100, address(tokenOut), _orderData(90, 1));

        assertEq(converter.nonces(address(tokenIn)), 1);
        assertEq(settlement.lastOrderUid().length, 56);
        assertTrue(settlement.lastSigned());
    }

    function test_ConvertStoresNonceInUpgradeableStorageNamespace() public {
        vm.prank(converterRoleHolder);
        converter.convert(address(tokenIn), 100, address(tokenOut), _orderData(90, 1));

        assertEq(converter.nonces(address(tokenIn)), 1);
        assertEq(uint256(vm.load(address(converter), _nonceStorageSlot(address(tokenIn)))), 1);
    }

    function test_SetConvertersRevertsForNonOwner() public {
        address newConverter = makeAddr("newConverter");

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        converter.setConverters(_converters(newConverter));
    }

    function test_SetConvertersCanRemoveConverter() public {
        vm.prank(owner);
        converter.setConverters(new address[](0));

        vm.expectRevert(ICoWSwapConverter.ExecutionDelayNotElapsed.selector);
        vm.prank(converterRoleHolder);
        converter.convert(address(tokenIn), 100, address(tokenOut), _orderData(90, 1));
    }

    function test_ConvertRevertsWhenBalanceIsInsufficient() public {
        vm.expectRevert(ICoWSwapConverter.InvalidSellAmount.selector);
        vm.prank(converterRoleHolder);
        converter.convert(address(tokenIn), 101, address(tokenOut), _orderData(90, 1));
    }

    function test_ConvertRevertsWhenTokensMatch() public {
        vm.expectRevert(ICoWSwapConverter.InvalidTokenIn.selector);
        vm.prank(converterRoleHolder);
        converter.convert(address(tokenOut), 100, address(tokenOut), _orderData(90, 1));
    }

    function test_ConvertRevertsForInvalidOrderBounds() public {
        vm.expectRevert(ICoWSwapConverter.InvalidSellAmount.selector);
        vm.prank(converterRoleHolder);
        converter.convert(address(tokenIn), 0, address(tokenOut), _orderData(90, 1));

        vm.expectRevert(ICoWSwapConverter.InvalidBuyAmount.selector);
        vm.prank(converterRoleHolder);
        converter.convert(address(tokenIn), 100, address(tokenOut), _orderData(0, 2));

        vm.expectRevert(ICoWSwapConverter.ExpiredOrder.selector);
        vm.prank(converterRoleHolder);
        converter.convert(address(tokenIn), 100, address(tokenOut), _orderData(90, 3, uint32(vm.getBlockTimestamp())));

        vm.expectRevert(ICoWSwapConverter.TooFarValidTo.selector);
        vm.prank(converterRoleHolder);
        converter.convert(
            address(tokenIn),
            100,
            address(tokenOut),
            _orderData(90, 4, uint32(vm.getBlockTimestamp() + MAX_VALID_TO_DURATION + 1))
        );
    }

    function test_ConvertChecksOrderBoundsBeforePreparedNonce() public {
        address caller = makeAddr("caller");

        vm.expectRevert(ICoWSwapConverter.InvalidSellAmount.selector);
        vm.prank(caller);
        converter.convert(address(tokenIn), 0, address(tokenOut), _orderData(90, 1));

        vm.expectRevert(ICoWSwapConverter.InvalidBuyAmount.selector);
        vm.prank(caller);
        converter.convert(address(tokenIn), 100, address(tokenOut), _orderData(0, 2));

        vm.expectRevert(ICoWSwapConverter.ExpiredOrder.selector);
        vm.prank(caller);
        converter.convert(address(tokenIn), 100, address(tokenOut), _orderData(90, 3, uint32(vm.getBlockTimestamp())));

        vm.expectRevert(ICoWSwapConverter.TooFarValidTo.selector);
        vm.prank(caller);
        converter.convert(
            address(tokenIn),
            100,
            address(tokenOut),
            _orderData(90, 4, uint32(vm.getBlockTimestamp() + MAX_VALID_TO_DURATION + 1))
        );
    }

    function test_PrepareConvertAllowsPublicExecutionAfterDelayIfNonceUnchanged() public {
        address caller = makeAddr("caller");
        bytes memory data = _orderData(90, 1, uint32(vm.getBlockTimestamp() + EXECUTION_DELAY + MAX_VALID_TO_DURATION));

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

    function test_PreparedConvertWaitsUntilOrderIsWithinMaxValidToDuration() public {
        address caller = makeAddr("caller");
        bytes memory data =
            _orderData(90, 1, uint32(vm.getBlockTimestamp() + EXECUTION_DELAY + MAX_VALID_TO_DURATION + 1));

        converter.prepareConvert(address(tokenIn), 100, address(tokenOut), data);

        vm.warp(vm.getBlockTimestamp() + EXECUTION_DELAY);
        vm.expectRevert(ICoWSwapConverter.TooFarValidTo.selector);
        vm.prank(caller);
        converter.convert(address(tokenIn), 100, address(tokenOut), data);

        vm.warp(vm.getBlockTimestamp() + 1);
        vm.prank(caller);
        converter.convert(address(tokenIn), 100, address(tokenOut), data);

        assertEq(converter.nonces(address(tokenIn)), 1);
        assertTrue(settlement.lastSigned());
    }

    function test_PrepareConvertRevertsWhenRequestIsAlreadyScheduledOnCurrentNonce() public {
        bytes memory data = _orderData(90, 1, uint32(vm.getBlockTimestamp() + EXECUTION_DELAY + MAX_VALID_TO_DURATION));

        converter.prepareConvert(address(tokenIn), 100, address(tokenOut), data);

        vm.expectRevert(ICoWSwapConverter.AlreadyReservedOrder.selector);
        converter.prepareConvert(address(tokenIn), 100, address(tokenOut), data);
    }

    function test_PrepareConvertRevertsWhenSellAmountIsInvalid() public {
        vm.expectRevert(ICoWSwapConverter.InvalidSellAmount.selector);
        converter.prepareConvert(address(tokenIn), 0, address(tokenOut), _orderData(90, 1));

        vm.expectRevert(ICoWSwapConverter.InvalidSellAmount.selector);
        converter.prepareConvert(address(tokenIn), 101, address(tokenOut), _orderData(90, 1));
    }

    function test_PrepareConvertRevertsForInvalidOrderBounds() public {
        vm.expectRevert(ICoWSwapConverter.InvalidTokenIn.selector);
        converter.prepareConvert(address(tokenOut), 100, address(tokenOut), _orderData(90, 1));

        vm.expectRevert(ICoWSwapConverter.InvalidBuyAmount.selector);
        converter.prepareConvert(address(tokenIn), 100, address(tokenOut), _orderData(0, 2));

        vm.expectRevert(ICoWSwapConverter.ExpiredOrder.selector);
        converter.prepareConvert(
            address(tokenIn), 100, address(tokenOut), _orderData(90, 3, uint32(vm.getBlockTimestamp()))
        );

        vm.expectRevert(ICoWSwapConverter.ExpiredOrder.selector);
        converter.prepareConvert(
            address(tokenIn),
            100,
            address(tokenOut),
            _orderData(90, 4, uint32(vm.getBlockTimestamp() + EXECUTION_DELAY))
        );
    }

    function test_PreparedConvertRevertsWhenTokenOutChanges() public {
        address caller = makeAddr("caller");
        Token otherTokenOut = new Token("Other Token Out");
        bytes memory data = _orderData(90, 1, uint32(vm.getBlockTimestamp() + EXECUTION_DELAY + MAX_VALID_TO_DURATION));
        converter.prepareConvert(address(tokenIn), 100, address(tokenOut), data);

        vm.warp(vm.getBlockTimestamp() + EXECUTION_DELAY);
        vm.expectRevert(ICoWSwapConverter.ExecutionDelayNotElapsed.selector);
        vm.prank(caller);
        converter.convert(address(tokenIn), 100, address(otherTokenOut), data);
    }

    function test_PreparedConvertRevertsWhenNonceChanged() public {
        address caller = makeAddr("caller");
        bytes memory data = _orderData(90, 1, uint32(vm.getBlockTimestamp() + EXECUTION_DELAY + MAX_VALID_TO_DURATION));
        converter.prepareConvert(address(tokenIn), 100, address(tokenOut), data);

        vm.prank(converterRoleHolder);
        converter.convert(address(tokenIn), 100, address(tokenOut), _orderData(80, 2));

        vm.warp(vm.getBlockTimestamp() + EXECUTION_DELAY);
        vm.expectRevert(ICoWSwapConverter.ExecutionDelayNotElapsed.selector);
        vm.prank(caller);
        converter.convert(address(tokenIn), 100, address(tokenOut), data);
    }

    function _orderData(uint256 buyAmount, uint256 salt) internal view returns (bytes memory) {
        return _orderData(buyAmount, salt, uint32(vm.getBlockTimestamp() + MAX_VALID_TO_DURATION));
    }

    function _orderData(uint256 buyAmount, uint256 salt, uint32 validTo) internal pure returns (bytes memory) {
        return
            abi.encode(ICoWSwapConverter.OrderParams({buyAmount: buyAmount, validTo: validTo, appData: bytes32(salt)}));
    }

    function _initData() internal view returns (bytes memory) {
        return abi.encode(address(vault), abi.encode(_converters(converterRoleHolder)));
    }

    function _converters(address converter_) internal pure returns (address[] memory converters_) {
        converters_ = new address[](1);
        converters_[0] = converter_;
    }

    function _nonceStorageSlot(address account) internal pure returns (bytes32) {
        return keccak256(abi.encode(account, OZ_NONCES_STORAGE_LOCATION));
    }
}

contract CoWSwapConverterHarness is Adapter, CoWSwapConverter {
    constructor(address vaultFactory, address adapterFactory, address settlement)
        Adapter(vaultFactory, adapterFactory)
        CoWSwapConverter(settlement)
    {}

    function totalAssets() public pure override returns (uint256) {
        return 0;
    }

    function computeOrderUid(
        ICoWSwapConverter.Data memory order,
        bytes32 domainSeparator,
        address orderOwner,
        uint32 validTo
    ) public pure returns (bytes memory orderUid) {
        orderUid = new bytes(COW_SWAP_ORDER_UID_LENGTH);
        _packOrderUidParams(orderUid, _hash(order, domainSeparator), orderOwner, validTo);
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
    address public vaultRelayer;
    bytes32 public domainSeparator = keccak256("DOMAIN");
    bytes public lastOrderUid;
    bool public lastSigned;

    constructor(address vaultRelayer_) {
        vaultRelayer = vaultRelayer_;
    }

    function setPreSignature(bytes calldata orderUid, bool signed) external {
        lastOrderUid = orderUid;
        lastSigned = signed;
    }
}
