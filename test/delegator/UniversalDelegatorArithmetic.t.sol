// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {VaultFactory} from "../../src/contracts/VaultFactory.sol";
import {DelegatorFactory} from "../../src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "../../src/contracts/SlasherFactory.sol";
import {NetworkRegistry} from "../../src/contracts/NetworkRegistry.sol";
import {OperatorRegistry} from "../../src/contracts/OperatorRegistry.sol";
import {VaultConfigurator} from "../../src/contracts/VaultConfigurator.sol";
import {NetworkMiddlewareService} from "../../src/contracts/service/NetworkMiddlewareService.sol";
import {OptInService} from "../../src/contracts/service/OptInService.sol";

import {VaultV2} from "../../src/contracts/vault/VaultV2.sol";
import {VaultV2Migrate} from "../../src/contracts/vault/VaultV2Migrate.sol";
import {Vault as VaultV1} from "../../src/contracts/vault/Vault.sol";
import {VaultTokenized} from "../../src/contracts/vault/VaultTokenized.sol";
import {FullRestakeDelegator} from "../../src/contracts/delegator/FullRestakeDelegator.sol";
import {NetworkRestakeDelegator} from "../../src/contracts/delegator/NetworkRestakeDelegator.sol";
import {OperatorNetworkSpecificDelegator} from "../../src/contracts/delegator/OperatorNetworkSpecificDelegator.sol";
import {OperatorSpecificDelegator} from "../../src/contracts/delegator/OperatorSpecificDelegator.sol";
import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";
import {Slasher} from "../../src/contracts/slasher/Slasher.sol";
import {UniversalSlasher} from "../../src/contracts/slasher/UniversalSlasher.sol";
import {VetoSlasher} from "../../src/contracts/slasher/VetoSlasher.sol";

import {Checkpoints} from "../../src/contracts/libraries/CheckpointsV2.sol";
import {Subnetwork} from "../../src/contracts/libraries/Subnetwork.sol";
import {UniversalDelegatorIndex} from "../../src/contracts/libraries/UniversalDelegatorIndex.sol";

import {
    IUniversalDelegator,
    MAX_NETWORKS,
    MAX_OPERATORS,
    WITHDRAWAL_BUFFER_CHILD_INDEX
} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IUniversalSlasher} from "../../src/interfaces/slasher/IUniversalSlasher.sol";
import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";
import {IVaultV2} from "../../src/interfaces/vault/IVaultV2.sol";

import {Token} from "../mocks/Token.sol";
import {MockRewards} from "../mocks/MockRewards.sol";
import {CoreV2StakeForInvariantHelper} from "../helpers/CoreV2StakeForInvariantHelper.sol";

contract MockVaultForDelegatorCoverage {
    uint48 public epochDuration = 3;
}

contract UniversalDelegatorCoverageHarness is Test, UniversalDelegator {
    using Checkpoints for Checkpoints.Trace208;

    constructor() UniversalDelegator(address(0), address(0), address(0), 0, address(0)) {}

    function setVaultRaw(address vault_) external {
        vault = vault_;
    }

    function pushSlotSizeRaw(uint64 index, uint48 timestamp, uint208 value) external {
        slots[index].size.push(timestamp, value);
    }

    function pushNextSlotRaw(uint64 index, uint48 timestamp, uint208 value) external {
        slots[index].nextSlot.push(timestamp, value);
    }

    function pushFirstChildRaw(uint64 index, uint48 timestamp, uint208 value) external {
        slots[index].firstChild.push(timestamp, value);
    }

    function pushSyncPrevSizeSumsRaw(uint64 index, uint48 timestamp, uint208 value) external {
        slots[index].syncPrevSizeSums.push(timestamp, value);
    }

    function latestPrevSizeSum(uint64 index) external view returns (uint208) {
        return slots[index].prevSizeSum.latest();
    }

    function latestSyncPrevSizeSums(uint64 index) external view returns (uint208) {
        return slots[index].syncPrevSizeSums.latest();
    }

    function exposeSyncPrevSizeSums(uint64 parentIndex) external syncPrevSizeSums(parentIndex) {}

    function exposeGetPrevSum(uint64 index) external view returns (uint208) {
        return _getPrevSum(index);
    }

    function exposeGetPrevSumAt(uint64 index, uint48 timestamp) external view returns (uint208) {
        return _getPrevSumAt(index, timestamp);
    }
}

contract UniversalDelegatorArithmeticTest is Test, CoreV2StakeForInvariantHelper {
    using Subnetwork for address;
    using UniversalDelegatorIndex for uint64;

    uint48 internal constant EPOCH_DURATION = 3;
    uint256 internal constant MAX_AMOUNT = 1_000_000 ether;
    string internal constant VAULT_NAME = "Test";
    string internal constant VAULT_SYMBOL = "TEST";

    address internal owner;
    address internal middleware;
    address internal alice;

    VaultFactory internal vaultFactory;
    DelegatorFactory internal delegatorFactory;
    SlasherFactory internal slasherFactory;
    NetworkRegistry internal networkRegistry;
    OperatorRegistry internal operatorRegistry;
    NetworkMiddlewareService internal networkMiddlewareService;
    OptInService internal operatorVaultOptInService;
    OptInService internal operatorNetworkOptInService;
    VaultConfigurator internal vaultConfigurator;
    MockRewards internal rewards;
    Token internal collateral;

    IVaultV2 internal vault;
    UniversalDelegator internal delegator;
    IUniversalSlasher internal slasher;

    struct DenseTopologyState {
        uint64 selectedNetworkSlot;
        bytes32 selectedSubnetwork;
        address selectedNetwork;
        address selectedOperator0;
        uint64 selectedOperatorSlot0;
        uint64 selectedOperatorSlot1;
        uint64 selectedOperatorSlot2;
    }

    DenseTopologyState internal denseTopo;

    struct RealChainState {
        address network;
        address operator1;
        address operator2;
        address operator3;
        bytes32 subnetwork;
        uint64 networkSlot;
        uint64 op1;
        uint64 op2;
        uint64 op3;
    }

    RealChainState internal realChain;

    function setUp() public {
        vm.warp(0);

        owner = address(this);
        middleware = makeAddr("arith-middleware");
        alice = makeAddr("arith-alice");

        vaultFactory = new VaultFactory(owner);
        delegatorFactory = new DelegatorFactory(owner);
        slasherFactory = new SlasherFactory(owner);
        networkRegistry = new NetworkRegistry();
        operatorRegistry = new OperatorRegistry();
        networkMiddlewareService = new NetworkMiddlewareService(address(networkRegistry));
        operatorVaultOptInService =
            new OptInService(address(operatorRegistry), address(vaultFactory), "OperatorVaultOptInService");
        operatorNetworkOptInService =
            new OptInService(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService");
        rewards = new MockRewards();

        address vaultImplV1 =
            address(new VaultV1(address(delegatorFactory), address(slasherFactory), address(vaultFactory)));
        vaultFactory.whitelist(vaultImplV1);

        address vaultImplTokenized =
            address(new VaultTokenized(address(delegatorFactory), address(slasherFactory), address(vaultFactory)));
        vaultFactory.whitelist(vaultImplTokenized);

        address vaultV2Migrate = address(
            new VaultV2Migrate(
                address(delegatorFactory), address(slasherFactory), address(0), address(rewards), address(0)
            )
        );
        address vaultImpl = address(
            new VaultV2(
                address(delegatorFactory),
                address(slasherFactory),
                address(vaultFactory),
                address(0),
                address(rewards),
                address(0),
                vaultV2Migrate
            )
        );
        vaultFactory.whitelist(vaultImpl);

        address networkRestakeDelegatorImpl = address(
            new NetworkRestakeDelegator(
                address(networkRegistry),
                address(vaultFactory),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(delegatorFactory),
                delegatorFactory.totalTypes()
            )
        );
        delegatorFactory.whitelist(networkRestakeDelegatorImpl);

        address fullRestakeDelegatorImpl = address(
            new FullRestakeDelegator(
                address(networkRegistry),
                address(vaultFactory),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(delegatorFactory),
                delegatorFactory.totalTypes()
            )
        );
        delegatorFactory.whitelist(fullRestakeDelegatorImpl);

        address operatorSpecificDelegatorImpl = address(
            new OperatorSpecificDelegator(
                address(operatorRegistry),
                address(networkRegistry),
                address(vaultFactory),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(delegatorFactory),
                delegatorFactory.totalTypes()
            )
        );
        delegatorFactory.whitelist(operatorSpecificDelegatorImpl);

        address operatorNetworkSpecificDelegatorImpl = address(
            new OperatorNetworkSpecificDelegator(
                address(operatorRegistry),
                address(networkRegistry),
                address(vaultFactory),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(delegatorFactory),
                delegatorFactory.totalTypes()
            )
        );
        delegatorFactory.whitelist(operatorNetworkSpecificDelegatorImpl);

        address slasherImpl = address(
            new Slasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(slasherFactory),
                slasherFactory.totalTypes()
            )
        );
        slasherFactory.whitelist(slasherImpl);

        address vetoSlasherImpl = address(
            new VetoSlasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(networkRegistry),
                address(slasherFactory),
                slasherFactory.totalTypes()
            )
        );
        slasherFactory.whitelist(vetoSlasherImpl);

        address delegatorImpl = address(
            new UniversalDelegator(
                address(networkRegistry),
                address(vaultFactory),
                address(delegatorFactory),
                delegatorFactory.totalTypes(),
                address(networkMiddlewareService)
            )
        );
        delegatorFactory.whitelist(delegatorImpl);

        address universalSlasherImpl = address(
            new UniversalSlasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(networkRegistry),
                address(slasherFactory),
                slasherFactory.totalTypes()
            )
        );
        slasherFactory.whitelist(universalSlasherImpl);

        collateral = new Token("Token");
        vaultConfigurator =
            new VaultConfigurator(address(vaultFactory), address(delegatorFactory), address(slasherFactory));

        (address vault_, address delegator_, address slasher_) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: vaultFactory.lastVersion(),
                owner: owner,
                vaultParams: abi.encode(
                    IVaultV2.InitParams({
                        name: VAULT_NAME,
                        symbol: VAULT_SYMBOL,
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: EPOCH_DURATION,
                        adapters: new address[](0),
                        adaptersAllowDelay: EPOCH_DURATION + 1,
                        depositWhitelist: false,
                        depositorToWhitelist: address(0xBEEF),
                        isDepositLimit: false,
                        depositLimit: 0,
                        defaultAdminRoleHolder: owner,
                        depositWhitelistSetRoleHolder: address(0),
                        depositorWhitelistRoleHolder: address(0),
                        isDepositLimitSetRoleHolder: address(0),
                        depositLimitSetRoleHolder: address(0),
                        setAdapterLimitRoleHolder: address(0),
                        swapAdaptersRoleHolder: address(0),
                        allocateAdapterRoleHolder: address(0),
                        deallocateAdapterRoleHolder: address(0)
                    })
                ),
                delegatorIndex: uint64(delegatorFactory.totalTypes() - 1),
                delegatorParams: abi.encode(
                    IUniversalDelegator.InitParams({
                        defaultAdminRoleHolder: owner,
                        createSlotRoleHolder: owner,
                        setSizeRoleHolder: owner,
                        swapSlotsRoleHolder: owner,
                        removeSlotRoleHolder: owner,
                        setWithdrawalBufferSizeRoleHolder: owner,
                        withdrawalBufferSize: type(uint128).max
                    })
                ),
                withSlasher: true,
                slasherIndex: uint64(slasherFactory.totalTypes() - 1),
                slasherParams: abi.encode(
                    IUniversalSlasher.InitParams({
                        isBurnerHook: false, vetoDuration: 1, resolverSetDelay: EPOCH_DURATION * 3
                    })
                )
            })
        );

        vault = IVaultV2(vault_);
        delegator = UniversalDelegator(delegator_);
        slasher = IUniversalSlasher(slasher_);
    }

    function testFuzz_rawPrefixMath_matchesManualOracle(uint8 siblingCount, uint128 sizeSeed) public {
        siblingCount = uint8(bound(siblingCount, 2, 20));
        sizeSeed = uint128(bound(sizeSeed, 1, type(uint128).max / 80));

        UniversalDelegatorCoverageHarness harness = new UniversalDelegatorCoverageHarness();
        MockVaultForDelegatorCoverage vaultMock = new MockVaultForDelegatorCoverage();
        uint64 parent = _rootIndex(1);
        uint48 timestamp = 1;

        vm.warp(timestamp);
        harness.setVaultRaw(address(vaultMock));
        harness.pushFirstChildRaw(parent, timestamp, 1);
        harness.pushSyncPrevSizeSumsRaw(parent, timestamp, 1);

        uint208 expectedPrevSize;

        for (uint32 i = 1; i <= siblingCount; ++i) {
            uint64 slot = parent.createIndex(i);
            uint128 childSize = sizeSeed + uint128(i * 3);

            harness.pushSlotSizeRaw(slot, timestamp, childSize);
            if (i < siblingCount) {
                harness.pushNextSlotRaw(slot, timestamp, i + 1);
            }

            assertEq(harness.exposeGetPrevSumAt(slot, timestamp), expectedPrevSize);
            assertEq(harness.exposeGetPrevSum(slot), expectedPrevSize);

            expectedPrevSize += childSize;
        }

        harness.exposeSyncPrevSizeSums(parent);
        expectedPrevSize = 0;
        for (uint32 i = 1; i <= siblingCount; ++i) {
            uint64 slot = parent.createIndex(i);
            assertEq(harness.latestPrevSizeSum(slot), expectedPrevSize);
            expectedPrevSize += sizeSeed + uint128(i * 3);
        }
        assertEq(harness.latestSyncPrevSizeSums(parent), 0);
    }

    function testFuzz_realSiblingChain_setSizeSlashAndHistoryKeepsCapacity(
        uint128 size1,
        uint128 size2,
        uint128 size3,
        uint128 shrink,
        uint128 slashAmount
    ) public {
        size1 = uint128(bound(size1, 1 ether, 400 ether));
        size2 = uint128(bound(size2, 1 ether, 400 ether));
        size3 = uint128(bound(size3, 1 ether, 400 ether));
        shrink = uint128(bound(shrink, 0, size1 - 1));
        slashAmount = uint128(bound(slashAmount, 1, size1 - shrink));

        _buildRealSiblingChain(size1, size2, size3);

        uint64[] memory slots = new uint64[](3);
        slots[0] = realChain.op1;
        slots[1] = realChain.op2;
        slots[2] = realChain.op3;

        _assertStakeForInvariantForDurations(address(vault), address(delegator), slots, EPOCH_DURATION);
        _assertSiblingPrefixSums(realChain.networkSlot);

        uint48 beforeChurn = uint48(block.timestamp);

        vm.warp(1);
        delegator.setSize(realChain.op1, size1 - shrink);
        assertEq(_pending(realChain.op1), shrink);
        assertEq(delegator.getAllocatedAt(realChain.op1, 0, beforeChurn), size1);
        assertEq(delegator.getFilledAt(realChain.networkSlot, 0, beforeChurn), uint256(size1) + size2 + size3);

        vm.prank(address(slasher));
        delegator.onSlash(realChain.subnetwork, realChain.operator1, slashAmount);

        _assertStakeForInvariantForDurations(address(vault), address(delegator), slots, EPOCH_DURATION);
    }

    function test_maxDensityTopology_protocolLimits_andChurn() public {
        _deposit(alice, MAX_AMOUNT);

        uint256 expectedRootFilled;
        for (uint256 networkIndex = 0; networkIndex < MAX_NETWORKS; ++networkIndex) {
            uint64 networkSlot = _buildDenseNetwork(networkIndex);
            expectedRootFilled += delegator.getAllocated(networkSlot, 0);
        }

        assertEq(delegator.getSlot(0).existChildren, MAX_NETWORKS);
        assertEq(delegator.getSlot(0).totalChildren, MAX_NETWORKS);
        assertEq(delegator.getFilled(0, 0), expectedRootFilled);
        _assertFilledMatchesChildren(0);
        _assertSiblingPrefixSums(0);

        _assertSiblingPrefixSums(denseTopo.selectedNetworkSlot);
        _assertFilledMatchesChildren(denseTopo.selectedNetworkSlot);

        uint48 beforeMutation = uint48(block.timestamp);
        uint256 selectedOperator0Size = delegator.getSlot(denseTopo.selectedOperatorSlot0).size;
        uint256 selectedOperator1Size = delegator.getSlot(denseTopo.selectedOperatorSlot1).size;

        vm.warp(1);
        delegator.setSize(denseTopo.selectedOperatorSlot0, 40 ether);
        delegator.setSize(denseTopo.selectedOperatorSlot1, 40 ether);
        assertEq(_pending(denseTopo.selectedOperatorSlot0), selectedOperator0Size - 40 ether);
        assertEq(_pending(denseTopo.selectedOperatorSlot1), selectedOperator1Size - 40 ether);
        assertEq(delegator.getAllocatedAt(denseTopo.selectedOperatorSlot0, 0, beforeMutation), selectedOperator0Size);
        assertEq(
            delegator.getFilledAt(denseTopo.selectedNetworkSlot, 0, beforeMutation),
            delegator.getFilled(denseTopo.selectedNetworkSlot, 0)
        );

        delegator.swapSlots(denseTopo.selectedOperatorSlot0, denseTopo.selectedOperatorSlot1);
        _assertSiblingPrefixSums(denseTopo.selectedNetworkSlot);

        vm.prank(address(slasher));
        delegator.onSlash(denseTopo.selectedSubnetwork, denseTopo.selectedOperator0, 10 ether);

        vm.warp(EPOCH_DURATION + 2);
        delegator.setSize(denseTopo.selectedOperatorSlot2, 0);
        vm.warp(EPOCH_DURATION + 6);
        delegator.removeSlot(denseTopo.selectedOperatorSlot2);
        assertEq(delegator.getSlot(denseTopo.selectedNetworkSlot).existChildren, MAX_OPERATORS - 1);

        vm.prank(denseTopo.selectedNetwork);
        delegator.resetAllocation(denseTopo.selectedSubnetwork);

        assertFalse(delegator.getSlot(denseTopo.selectedNetworkSlot).exists);
        assertEq(delegator.getSlotOfNetwork(denseTopo.selectedSubnetwork), 0);
        assertEq(delegator.getSlot(0).existChildren, MAX_NETWORKS - 1);
    }

    function _registerOperator(address operator) internal {
        vm.startPrank(operator);
        operatorRegistry.registerOperator();
        vm.stopPrank();
    }

    function _registerNetwork(address network, address middleware_) internal {
        vm.startPrank(network);
        networkRegistry.registerNetwork();
        networkMiddlewareService.setMiddleware(middleware_);
        vm.stopPrank();
    }

    function _optIn(address operator, address network) internal {
        vm.startPrank(operator);
        operatorVaultOptInService.optIn(address(vault));
        operatorNetworkOptInService.optIn(network);
        vm.stopPrank();
    }

    function _deposit(address user, uint256 amount) internal {
        collateral.transfer(user, amount);

        vm.startPrank(user);
        collateral.approve(address(vault), amount);
        vault.deposit(user, amount);
        vm.stopPrank();
    }

    function _operatorKey(address operator) internal pure returns (bytes32) {
        return bytes32(bytes20(operator));
    }

    function _rootIndex(uint32 localIndex) internal pure returns (uint64) {
        return uint64(0).createIndex(localIndex);
    }

    function _assertSiblingPrefixSums(uint64 parentIndex) internal view {
        IUniversalDelegator.Slot memory parent = delegator.getSlot(parentIndex);
        uint208 expectedPrevSize;
        uint32 childIndex = parent.firstChild;

        while (childIndex > 0 && childIndex < WITHDRAWAL_BUFFER_CHILD_INDEX) {
            uint64 slotIndex = parentIndex.createIndex(childIndex);
            IUniversalDelegator.Slot memory slot = delegator.getSlot(slotIndex);
            assertEq(slot.prevSizeSum, expectedPrevSize);
            expectedPrevSize += uint208(slot.size);
            childIndex = slot.nextSlot;
        }
    }

    function _assertFilledMatchesChildren(uint64 parentIndex) internal view {
        uint256 expected;
        uint32 childIndex = delegator.getSlot(parentIndex).firstChild;

        while (childIndex > 0 && childIndex < WITHDRAWAL_BUFFER_CHILD_INDEX) {
            uint64 slotIndex = parentIndex.createIndex(childIndex);
            expected += delegator.getAllocated(slotIndex, 0);
            childIndex = delegator.getSlot(slotIndex).nextSlot;
        }

        assertEq(delegator.getFilled(parentIndex, 0), expected);
    }

    function _pending(uint64 index) internal view returns (uint208) {
        IUniversalDelegator.Slot memory slot = delegator.getSlot(index);
        return slot.size > slot.latestSize ? uint208(slot.size - slot.latestSize) : 0;
    }

    function _buildDenseNetwork(uint256 networkIndex) internal returns (uint64 networkSlot) {
        address network = _denseNetworkAddress(networkIndex);
        bytes32 subnetwork = network.subnetwork(0);
        uint128 networkSize = uint128(3000 ether + networkIndex * 20 ether);

        networkSlot = delegator.createSlot(subnetwork, 0, networkSize);
        if (networkIndex == 0) {
            denseTopo.selectedNetwork = network;
            denseTopo.selectedSubnetwork = subnetwork;
            denseTopo.selectedNetworkSlot = networkSlot;

            _registerNetwork(network, middleware);
            vm.prank(network);
            delegator.setMaxNetworkLimit(0, type(uint256).max);
        }

        uint256 expectedNetworkFilled;
        for (uint256 operatorIndex = 0; operatorIndex < MAX_OPERATORS; ++operatorIndex) {
            uint64 operatorSlot = _buildDenseOperator(networkIndex, networkSlot, operatorIndex);
            expectedNetworkFilled += delegator.getAllocated(operatorSlot, 0);
        }

        assertEq(delegator.getSlot(networkSlot).existChildren, MAX_OPERATORS);
        assertEq(delegator.getSlot(networkSlot).totalChildren, MAX_OPERATORS);
        assertEq(delegator.getFilled(networkSlot, 0), expectedNetworkFilled);
        _assertSiblingPrefixSums(networkSlot);
    }

    function _buildDenseOperator(uint256 networkIndex, uint64 networkSlot, uint256 operatorIndex)
        internal
        returns (uint64 operatorSlot)
    {
        address operator = _denseOperatorAddress(networkIndex, operatorIndex);
        uint128 operatorSize = uint128(100 ether + operatorIndex);

        operatorSlot = delegator.createSlot(_operatorKey(operator), networkSlot, operatorSize);
        if (networkIndex == 0) {
            if (operatorIndex == 0) {
                denseTopo.selectedOperator0 = operator;
                denseTopo.selectedOperatorSlot0 = operatorSlot;
                _registerOperator(operator);
                _optIn(operator, denseTopo.selectedNetwork);
            } else if (operatorIndex == 1) {
                denseTopo.selectedOperatorSlot1 = operatorSlot;
            } else if (operatorIndex == 2) {
                denseTopo.selectedOperatorSlot2 = operatorSlot;
            }
        }
    }

    function _buildRealSiblingChain(uint128 size1, uint128 size2, uint128 size3) internal {
        realChain.network = makeAddr("arith-network");
        realChain.operator1 = makeAddr("arith-operator-1");
        realChain.operator2 = makeAddr("arith-operator-2");
        realChain.operator3 = makeAddr("arith-operator-3");
        realChain.subnetwork = realChain.network.subnetwork(0);

        _registerNetwork(realChain.network, middleware);
        _registerOperator(realChain.operator1);
        _registerOperator(realChain.operator2);
        _registerOperator(realChain.operator3);
        _optIn(realChain.operator1, realChain.network);
        _optIn(realChain.operator2, realChain.network);
        _optIn(realChain.operator3, realChain.network);

        vm.prank(realChain.network);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        uint256 networkSize = uint256(size1) + size2 + size3 + 500 ether;
        _deposit(alice, networkSize);

        realChain.networkSlot = delegator.createSlot(realChain.subnetwork, 0, uint128(networkSize));
        realChain.op1 = delegator.createSlot(_operatorKey(realChain.operator1), realChain.networkSlot, size1);
        realChain.op2 = delegator.createSlot(_operatorKey(realChain.operator2), realChain.networkSlot, size2);
        realChain.op3 = delegator.createSlot(_operatorKey(realChain.operator3), realChain.networkSlot, size3);
    }

    function _denseNetworkAddress(uint256 networkIndex) internal pure returns (address) {
        return address(uint160(0x100000 + networkIndex + 1));
    }

    function _denseOperatorAddress(uint256 networkIndex, uint256 operatorIndex) internal pure returns (address) {
        return address(uint160(0x200000 + networkIndex * 1000 + operatorIndex + 1));
    }
}
