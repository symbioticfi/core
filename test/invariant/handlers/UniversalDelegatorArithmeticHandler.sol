// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {VaultFactory} from "../../../src/contracts/VaultFactory.sol";
import {DelegatorFactory} from "../../../src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "../../../src/contracts/SlasherFactory.sol";
import {VaultConfigurator} from "../../../src/contracts/VaultConfigurator.sol";
import {NetworkRegistry} from "../../../src/contracts/NetworkRegistry.sol";
import {OperatorRegistry} from "../../../src/contracts/OperatorRegistry.sol";
import {NetworkMiddlewareService} from "../../../src/contracts/service/NetworkMiddlewareService.sol";
import {OptInService} from "../../../src/contracts/service/OptInService.sol";

import {Vault as VaultV1} from "../../../src/contracts/vault/Vault.sol";
import {VaultTokenized} from "../../../src/contracts/vault/VaultTokenized.sol";
import {VaultV2} from "../../../src/contracts/vault/VaultV2.sol";
import {VaultV2Migrate} from "../../../src/contracts/vault/VaultV2Migrate.sol";
import {NetworkRestakeDelegator} from "../../../src/contracts/delegator/NetworkRestakeDelegator.sol";
import {FullRestakeDelegator} from "../../../src/contracts/delegator/FullRestakeDelegator.sol";
import {OperatorSpecificDelegator} from "../../../src/contracts/delegator/OperatorSpecificDelegator.sol";
import {OperatorNetworkSpecificDelegator} from "../../../src/contracts/delegator/OperatorNetworkSpecificDelegator.sol";
import {UniversalDelegator} from "../../../src/contracts/delegator/UniversalDelegator.sol";
import {Slasher} from "../../../src/contracts/slasher/Slasher.sol";
import {VetoSlasher} from "../../../src/contracts/slasher/VetoSlasher.sol";
import {UniversalSlasher} from "../../../src/contracts/slasher/UniversalSlasher.sol";

import {Subnetwork} from "../../../src/contracts/libraries/Subnetwork.sol";
import {UniversalDelegatorIndex} from "../../../src/contracts/libraries/UniversalDelegatorIndex.sol";

import {IVaultV2} from "../../../src/interfaces/vault/IVaultV2.sol";
import {
    IUniversalDelegator,
    MAX_NETWORKS,
    MAX_OPERATORS,
    MAX_SUBVAULTS,
    WITHDRAWAL_BUFFER_CHILD_INDEX
} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IUniversalSlasher} from "../../../src/interfaces/slasher/IUniversalSlasher.sol";
import {IVaultConfigurator} from "../../../src/interfaces/IVaultConfigurator.sol";

import {Token} from "../../mocks/Token.sol";
import {MockRewards} from "../../mocks/MockRewards.sol";

contract UniversalDelegatorArithmeticHarness is UniversalDelegator {
    constructor(
        address networkRegistry,
        address vaultFactory,
        address delegatorFactory,
        uint64 entityType,
        address networkMiddlewareService
    ) UniversalDelegator(networkRegistry, vaultFactory, delegatorFactory, entityType, networkMiddlewareService) {}
}

contract UniversalDelegatorArithmeticHandler is Test {
    using Subnetwork for address;
    using Subnetwork for bytes32;
    using UniversalDelegatorIndex for uint96;

    uint256 internal constant MAX_ACTION_AMOUNT = 1_000_000 ether;
    uint256 internal constant MAX_SLOT_SIZE = 250_000 ether;
    uint256 internal constant MAX_TRACKED_TIMESTAMPS = 64;
    uint48 internal constant EPOCH_DURATION = 7 days;

    VaultFactory internal vaultFactory;
    DelegatorFactory internal delegatorFactory;
    SlasherFactory internal slasherFactory;
    VaultConfigurator internal vaultConfigurator;
    NetworkRegistry internal networkRegistry;
    OperatorRegistry internal operatorRegistry;
    NetworkMiddlewareService internal networkMiddlewareService;
    OptInService internal operatorVaultOptInService;
    OptInService internal operatorNetworkOptInService;

    Token public collateral;
    MockRewards public rewards;
    IVaultV2 public vault;
    UniversalDelegatorArithmeticHarness public delegator;
    IUniversalSlasher public slasher;

    uint96[] internal trackedRootSlots;
    uint96[] internal trackedNetworkSlots;
    uint96[] internal trackedOperatorSlots;
    uint48[] internal trackedTimestamps;

    mapping(bytes32 subnetwork => address middleware) internal middlewareOf;
    mapping(uint96 operatorSlot => address operator) internal operatorOfSlot;
    mapping(address account => bool knownDepositor) internal isKnownDepositor;
    address[] internal depositors;

    uint256 internal nextNetworkNonce;
    uint256 internal nextOperatorNonce;
    uint256 internal nextTimestampWriteIndex;

    constructor() {
        _initialize();
    }

    function getTrackedRootSlots() external view returns (uint96[] memory) {
        return trackedRootSlots;
    }

    function getTrackedNetworkSlots() external view returns (uint96[] memory) {
        return trackedNetworkSlots;
    }

    function getTrackedOperatorSlots() external view returns (uint96[] memory) {
        return trackedOperatorSlots;
    }

    function getTrackedSlots() external view returns (uint96[] memory slots_) {
        slots_ = new uint96[](trackedRootSlots.length + trackedNetworkSlots.length + trackedOperatorSlots.length);

        uint256 cursor;
        for (uint256 i; i < trackedRootSlots.length; ++i) {
            slots_[cursor++] = trackedRootSlots[i];
        }
        for (uint256 i; i < trackedNetworkSlots.length; ++i) {
            slots_[cursor++] = trackedNetworkSlots[i];
        }
        for (uint256 i; i < trackedOperatorSlots.length; ++i) {
            slots_[cursor++] = trackedOperatorSlots[i];
        }
    }

    function getTrackedTimestamps() external view returns (uint48[] memory) {
        return trackedTimestamps;
    }

    function getMiddleware(bytes32 subnetwork) external view returns (address) {
        return middlewareOf[subnetwork];
    }

    function warp(uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);
        _recordTimestamp();
    }

    function deposit(uint256 userSeed, uint256 amount, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        address user = _user(userSeed);
        amount = _bound(amount, 1 ether, MAX_ACTION_AMOUNT);

        deal(address(collateral), user, amount);

        vm.startPrank(user);
        collateral.approve(address(vault), amount);
        try vault.deposit(user, amount) returns (uint256, uint256) {
            _rememberDepositor(user);
        } catch {}
        vm.stopPrank();

        _recordTimestamp();
    }

    function withdraw(uint256 userSeed, uint256 amount, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        address user = _selectDepositor(userSeed);
        if (user == address(0)) {
            _recordTimestamp();
            return;
        }

        uint256 balance = vault.activeBalanceOf(user);
        if (balance == 0) {
            _recordTimestamp();
            return;
        }

        vm.prank(user);
        try vault.withdraw(user, _bound(amount, 1, balance)) {} catch {}

        _recordTimestamp();
    }

    function createRootSlot(uint256 sizeSeed, uint256 flagsSeed, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        bytes32 slotKey = bytes32(uint256(trackedRootSlots.length + 1));
        bool isShared = flagsSeed & 1 == 1;
        uint128 size = uint128(_bound(sizeSeed, 0, MAX_SLOT_SIZE));

        (bool success, bytes memory returnData) =
            address(delegator).call(abi.encodeCall(delegator.createSlot, (slotKey, 0, isShared, size)));
        if (success) {
            trackedRootSlots.push(abi.decode(returnData, (uint96)));
        }

        _recordTimestamp();
    }

    function setMaxNetworkLimit(uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        (address network,,) = _prepareFreshSubnetwork();
        vm.prank(network);
        address(delegator).call(abi.encodeCall(delegator.setMaxNetworkLimit, (uint96(0), type(uint256).max)));

        _recordTimestamp();
    }

    function createNetworkSlot(uint256 rootSeed, uint256 sizeSeed, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        uint96 rootSlot = _selectLiveSlot(trackedRootSlots, rootSeed);
        if (rootSlot == 0) {
            _recordTimestamp();
            return;
        }

        (,, bytes32 subnetwork) = _prepareFreshSubnetwork();
        uint128 size = uint128(_bound(sizeSeed, 0, MAX_SLOT_SIZE));

        (bool success, bytes memory returnData) =
            address(delegator).call(abi.encodeCall(delegator.createSlot, (subnetwork, rootSlot, false, size)));
        if (success) {
            trackedNetworkSlots.push(abi.decode(returnData, (uint96)));
        }

        _recordTimestamp();
    }

    function createOperatorSlot(uint256 networkSeed, uint256 sizeSeed, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        uint96 networkSlot = _selectLiveSlot(trackedNetworkSlots, networkSeed);
        if (networkSlot == 0) {
            _recordTimestamp();
            return;
        }

        bytes32 subnetwork = delegator.getSlot(networkSlot).subnetworkOrOperator;
        address operator = _prepareFreshOperator(subnetwork);
        uint128 size = uint128(_bound(sizeSeed, 0, MAX_SLOT_SIZE));

        (bool success, bytes memory returnData) = address(delegator)
            .call(abi.encodeCall(delegator.createSlot, (bytes32(bytes20(operator)), networkSlot, false, size)));
        if (success) {
            uint96 operatorSlot = abi.decode(returnData, (uint96));
            trackedOperatorSlots.push(operatorSlot);
            operatorOfSlot[operatorSlot] = operator;
        }

        _recordTimestamp();
    }

    function setSize(uint256 slotSeed, uint256 newSizeSeed, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        uint96 slot = _selectLiveAnySlot(slotSeed);
        if (slot == 0) {
            _recordTimestamp();
            return;
        }

        address(delegator)
            .call(abi.encodeCall(delegator.setSize, (slot, uint128(_bound(newSizeSeed, 0, MAX_SLOT_SIZE)))));

        _recordTimestamp();
    }

    function swapSlots(uint256 parentSeed, uint256 leftSeed, uint256 rightSeed, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        uint96 parent = _selectParentWithAtLeastTwoChildren(parentSeed);
        if (parent == type(uint96).max) {
            _recordTimestamp();
            return;
        }

        uint96[] memory siblings = _liveChildrenOf(parent);
        if (siblings.length < 2) {
            _recordTimestamp();
            return;
        }

        uint256 leftIndex = _bound(leftSeed, 0, siblings.length - 1);
        uint256 rightIndex = _bound(rightSeed, 0, siblings.length - 1);
        if (leftIndex == rightIndex) {
            rightIndex = (rightIndex + 1) % siblings.length;
        }

        uint96 left = siblings[leftIndex];
        uint96 right = siblings[rightIndex];
        if (left.getChildIndex() > right.getChildIndex()) {
            (left, right) = (right, left);
        }

        address(delegator).call(abi.encodeCall(delegator.swapSlots, (left, right)));

        _recordTimestamp();
    }

    function removeSlot(uint256 slotSeed, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        uint96 slot = _selectRemovableLiveSlot(slotSeed);
        if (slot == 0) {
            _recordTimestamp();
            return;
        }

        address(delegator).call(abi.encodeCall(delegator.removeSlot, (slot)));

        _recordTimestamp();
    }

    function resetAllocation(uint256 networkSeed, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        uint96 networkSlot = _selectLiveSlot(trackedNetworkSlots, networkSeed);
        if (networkSlot == 0) {
            _recordTimestamp();
            return;
        }

        bytes32 subnetwork = delegator.getSlot(networkSlot).subnetworkOrOperator;
        address middleware = middlewareOf[subnetwork];
        if (middleware == address(0)) {
            _recordTimestamp();
            return;
        }

        vm.prank(middleware);
        address(delegator).call(abi.encodeCall(delegator.resetAllocation, (subnetwork)));

        _recordTimestamp();
    }

    function slash(uint256 operatorSeed, uint256 amountSeed, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        uint96 operatorSlot = _selectLiveSlot(trackedOperatorSlots, operatorSeed);
        if (operatorSlot == 0) {
            _recordTimestamp();
            return;
        }

        address operator = operatorOfSlot[operatorSlot];
        bytes32 subnetwork = delegator.getSlot(operatorSlot.getParentIndex()).subnetworkOrOperator;
        uint256 slashable = slasher.slashableStake(subnetwork, operator, 0, "");
        if (slashable == 0) {
            _recordTimestamp();
            return;
        }

        address middleware = middlewareOf[subnetwork];
        if (middleware == address(0)) {
            _recordTimestamp();
            return;
        }

        vm.startPrank(middleware);
        try slasher.requestSlash(subnetwork, operator, _bound(amountSeed, 1, slashable), 0, "") returns (
            uint256 index
        ) {
            try slasher.executeSlash(index, "") {} catch {}
        } catch {}
        vm.stopPrank();

        _recordTimestamp();
    }

    function _initialize() internal {
        vm.warp(1);

        vaultFactory = new VaultFactory(address(this));
        delegatorFactory = new DelegatorFactory(address(this));
        slasherFactory = new SlasherFactory(address(this));
        vaultConfigurator =
            new VaultConfigurator(address(vaultFactory), address(delegatorFactory), address(slasherFactory));
        networkRegistry = new NetworkRegistry();
        operatorRegistry = new OperatorRegistry();
        networkMiddlewareService = new NetworkMiddlewareService(address(networkRegistry));
        operatorVaultOptInService =
            new OptInService(address(operatorRegistry), address(vaultFactory), "OperatorVaultOptInService");
        operatorNetworkOptInService =
            new OptInService(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService");
        collateral = new Token("UniversalDelegatorInvariantToken");
        rewards = new MockRewards();

        vaultFactory.whitelist(
            address(new VaultV1(address(delegatorFactory), address(slasherFactory), address(vaultFactory)))
        );
        vaultFactory.whitelist(
            address(new VaultTokenized(address(delegatorFactory), address(slasherFactory), address(vaultFactory)))
        );

        address vaultV2Migrate = address(
            new VaultV2Migrate(
                address(delegatorFactory), address(slasherFactory), address(0), address(rewards), address(0)
            )
        );
        vaultFactory.whitelist(
            address(
                new VaultV2(
                    address(delegatorFactory),
                    address(slasherFactory),
                    address(vaultFactory),
                    address(0),
                    address(rewards),
                    address(0),
                    vaultV2Migrate
                )
            )
        );

        delegatorFactory.whitelist(
            address(
                new NetworkRestakeDelegator(
                    address(networkRegistry),
                    address(vaultFactory),
                    address(operatorVaultOptInService),
                    address(operatorNetworkOptInService),
                    address(delegatorFactory),
                    delegatorFactory.totalTypes()
                )
            )
        );
        delegatorFactory.whitelist(
            address(
                new FullRestakeDelegator(
                    address(networkRegistry),
                    address(vaultFactory),
                    address(operatorVaultOptInService),
                    address(operatorNetworkOptInService),
                    address(delegatorFactory),
                    delegatorFactory.totalTypes()
                )
            )
        );
        delegatorFactory.whitelist(
            address(
                new OperatorSpecificDelegator(
                    address(operatorRegistry),
                    address(networkRegistry),
                    address(vaultFactory),
                    address(operatorVaultOptInService),
                    address(operatorNetworkOptInService),
                    address(delegatorFactory),
                    delegatorFactory.totalTypes()
                )
            )
        );
        delegatorFactory.whitelist(
            address(
                new OperatorNetworkSpecificDelegator(
                    address(operatorRegistry),
                    address(networkRegistry),
                    address(vaultFactory),
                    address(operatorVaultOptInService),
                    address(operatorNetworkOptInService),
                    address(delegatorFactory),
                    delegatorFactory.totalTypes()
                )
            )
        );
        delegatorFactory.whitelist(
            address(
                new UniversalDelegatorArithmeticHarness(
                    address(networkRegistry),
                    address(vaultFactory),
                    address(delegatorFactory),
                    delegatorFactory.totalTypes(),
                    address(networkMiddlewareService)
                )
            )
        );

        slasherFactory.whitelist(
            address(
                new Slasher(
                    address(vaultFactory),
                    address(networkMiddlewareService),
                    address(slasherFactory),
                    slasherFactory.totalTypes()
                )
            )
        );
        slasherFactory.whitelist(
            address(
                new VetoSlasher(
                    address(vaultFactory),
                    address(networkMiddlewareService),
                    address(networkRegistry),
                    address(slasherFactory),
                    slasherFactory.totalTypes()
                )
            )
        );
        slasherFactory.whitelist(
            address(
                new UniversalSlasher(
                    address(vaultFactory),
                    address(networkMiddlewareService),
                    address(networkRegistry),
                    address(slasherFactory),
                    slasherFactory.totalTypes()
                )
            )
        );

        IVaultV2.InitParams memory vaultParams = IVaultV2.InitParams({
            name: "UD Invariant Vault",
            symbol: "UDIV",
            collateral: address(collateral),
            burner: address(0xBEEF),
            epochDuration: EPOCH_DURATION,
            adapters: new address[](0),
            adaptersAllowDelay: EPOCH_DURATION + 1,
            depositWhitelist: false,
            depositorToWhitelist: address(0xBEEF),
            isDepositLimit: false,
            depositLimit: 0,
            defaultAdminRoleHolder: address(this),
            depositWhitelistSetRoleHolder: address(this),
            depositorWhitelistRoleHolder: address(this),
            isDepositLimitSetRoleHolder: address(this),
            depositLimitSetRoleHolder: address(this),
            setAdapterLimitRoleHolder: address(this),
            swapAdaptersRoleHolder: address(this),
            allocateAdapterRoleHolder: address(this),
            deallocateAdapterRoleHolder: address(this)
        });

        IUniversalDelegator.InitParams memory delegatorParams = IUniversalDelegator.InitParams({
            defaultAdminRoleHolder: address(this),
            createSlotRoleHolder: address(this),
            setSizeRoleHolder: address(this),
            swapSlotsRoleHolder: address(this),
            removeSlotRoleHolder: address(this),
            setWithdrawalBufferSizeRoleHolder: address(this),
            withdrawalBufferSize: type(uint128).max
        });

        IUniversalSlasher.InitParams memory slasherParams =
            IUniversalSlasher.InitParams({isBurnerHook: false, vetoDuration: 0, resolverSetDelay: 8 days});

        (address vault_, address delegator_, address slasher_) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: vaultFactory.lastVersion(),
                owner: address(this),
                vaultParams: abi.encode(vaultParams),
                delegatorIndex: uint64(delegatorFactory.totalTypes() - 1),
                delegatorParams: abi.encode(delegatorParams),
                withSlasher: true,
                slasherIndex: uint64(slasherFactory.totalTypes() - 1),
                slasherParams: abi.encode(slasherParams)
            })
        );

        vault = IVaultV2(vault_);
        delegator = UniversalDelegatorArithmeticHarness(delegator_);
        slasher = IUniversalSlasher(slasher_);

        address bootstrapDepositor = _user(0);
        deal(address(collateral), bootstrapDepositor, 2_000_000 ether);

        vm.startPrank(bootstrapDepositor);
        collateral.approve(address(vault), 2_000_000 ether);
        vault.deposit(bootstrapDepositor, 2_000_000 ether);
        vm.stopPrank();
        _rememberDepositor(bootstrapDepositor);

        _bootstrapMixedTopology();
        _recordTimestamp();
    }

    function _bootstrapMixedTopology() internal {
        (,, bytes32 sharedSubnetwork1) = _prepareFreshSubnetwork();
        (,, bytes32 sharedSubnetwork2) = _prepareFreshSubnetwork();
        address sharedOperator1 = _prepareFreshOperator(sharedSubnetwork1);
        address sharedOperator2 = _prepareFreshOperator(sharedSubnetwork2);

        uint96 sharedRoot = delegator.createSlot(bytes32("bootstrap-shared-root"), 0, true, uint128(220 ether));
        trackedRootSlots.push(sharedRoot);
        uint96 sharedNetwork1 = delegator.createSlot(sharedSubnetwork1, sharedRoot, false, uint128(220 ether));
        uint96 sharedNetwork2 = delegator.createSlot(sharedSubnetwork2, sharedRoot, false, uint128(220 ether));
        trackedNetworkSlots.push(sharedNetwork1);
        trackedNetworkSlots.push(sharedNetwork2);

        uint96 sharedOperatorSlot1 =
            delegator.createSlot(bytes32(bytes20(sharedOperator1)), sharedNetwork1, false, uint128(150 ether));
        uint96 sharedOperatorSlot2 =
            delegator.createSlot(bytes32(bytes20(sharedOperator2)), sharedNetwork2, false, uint128(160 ether));
        trackedOperatorSlots.push(sharedOperatorSlot1);
        trackedOperatorSlots.push(sharedOperatorSlot2);
        operatorOfSlot[sharedOperatorSlot1] = sharedOperator1;
        operatorOfSlot[sharedOperatorSlot2] = sharedOperator2;

        (,, bytes32 isolatedSubnetwork) = _prepareFreshSubnetwork();
        address isolatedOperator1 = _prepareFreshOperator(isolatedSubnetwork);
        address isolatedOperator2 = _prepareFreshOperator(isolatedSubnetwork);

        uint96 isolatedRoot = delegator.createSlot(bytes32("bootstrap-isolated-root"), 0, false, uint128(260 ether));
        trackedRootSlots.push(isolatedRoot);
        uint96 isolatedNetwork = delegator.createSlot(isolatedSubnetwork, isolatedRoot, false, uint128(260 ether));
        trackedNetworkSlots.push(isolatedNetwork);

        uint96 isolatedOperatorSlot1 =
            delegator.createSlot(bytes32(bytes20(isolatedOperator1)), isolatedNetwork, false, uint128(130 ether));
        uint96 isolatedOperatorSlot2 =
            delegator.createSlot(bytes32(bytes20(isolatedOperator2)), isolatedNetwork, false, uint128(120 ether));
        trackedOperatorSlots.push(isolatedOperatorSlot1);
        trackedOperatorSlots.push(isolatedOperatorSlot2);
        operatorOfSlot[isolatedOperatorSlot1] = isolatedOperator1;
        operatorOfSlot[isolatedOperatorSlot2] = isolatedOperator2;
    }

    function _prepareFreshSubnetwork() internal returns (address network, address middleware, bytes32 subnetwork) {
        ++nextNetworkNonce;
        network = address(uint160(10_000 + nextNetworkNonce));
        middleware = address(uint160(100_000 + nextNetworkNonce));
        subnetwork = network.subnetwork(0);

        vm.startPrank(network);
        networkRegistry.registerNetwork();
        networkMiddlewareService.setMiddleware(middleware);
        vm.stopPrank();

        middlewareOf[subnetwork] = middleware;

        vm.prank(network);
        delegator.setMaxNetworkLimit(0, type(uint256).max);
    }

    function _prepareFreshOperator(bytes32 subnetwork) internal returns (address operator) {
        ++nextOperatorNonce;
        operator = address(uint160(1_000_000 + nextOperatorNonce));

        vm.prank(operator);
        operatorRegistry.registerOperator();

        vm.prank(operator);
        address(operatorVaultOptInService).call(abi.encodeWithSignature("optIn(address)", address(vault)));

        vm.prank(operator);
        address(operatorNetworkOptInService).call(abi.encodeWithSignature("optIn(address)", subnetwork.network()));
    }

    function _rememberDepositor(address user) internal {
        if (isKnownDepositor[user]) {
            return;
        }
        isKnownDepositor[user] = true;
        depositors.push(user);
    }

    function _selectDepositor(uint256 seed) internal view returns (address) {
        if (depositors.length == 0) {
            return address(0);
        }
        return depositors[_bound(seed, 0, depositors.length - 1)];
    }

    function _user(uint256 seed) internal pure returns (address user) {
        user = address(uint160(seed + 500));
        if (user == address(0)) {
            user = address(500);
        }
    }

    function _warp(uint256 timeJumpSeed) internal {
        uint256 timeJump = _bound(timeJumpSeed, 1 hours, 14 days);
        vm.warp(block.timestamp + timeJump);
    }

    function _recordTimestamp() internal {
        uint48 timestamp = uint48(block.timestamp);
        if (trackedTimestamps.length < MAX_TRACKED_TIMESTAMPS) {
            trackedTimestamps.push(timestamp);
            return;
        }

        trackedTimestamps[nextTimestampWriteIndex] = timestamp;
        nextTimestampWriteIndex = (nextTimestampWriteIndex + 1) % MAX_TRACKED_TIMESTAMPS;
    }

    function _selectLiveSlot(uint96[] storage trackedSlots, uint256 seed) internal view returns (uint96) {
        uint256 liveCount;
        for (uint256 i; i < trackedSlots.length; ++i) {
            if (delegator.getSlot(trackedSlots[i]).exists) {
                ++liveCount;
            }
        }
        if (liveCount == 0) {
            return 0;
        }

        uint256 target = _bound(seed, 0, liveCount - 1);
        for (uint256 i; i < trackedSlots.length; ++i) {
            uint96 slot = trackedSlots[i];
            if (!delegator.getSlot(slot).exists) {
                continue;
            }
            if (target == 0) {
                return slot;
            }
            --target;
        }

        return 0;
    }

    function _selectLiveAnySlot(uint256 seed) internal view returns (uint96) {
        uint96[] memory slots_ = this.getTrackedSlots();
        uint256 liveCount;
        for (uint256 i; i < slots_.length; ++i) {
            if (delegator.getSlot(slots_[i]).exists) {
                ++liveCount;
            }
        }
        if (liveCount == 0) {
            return 0;
        }

        uint256 target = _bound(seed, 0, liveCount - 1);
        for (uint256 i; i < slots_.length; ++i) {
            if (!delegator.getSlot(slots_[i]).exists) {
                continue;
            }
            if (target == 0) {
                return slots_[i];
            }
            --target;
        }
        return 0;
    }

    function _selectRemovableLiveSlot(uint256 seed) internal view returns (uint96) {
        uint96[] memory slots_ = this.getTrackedSlots();
        uint256 removableCount;
        for (uint256 i; i < slots_.length; ++i) {
            if (delegator.getSlot(slots_[i]).exists && delegator.getAllocated(slots_[i], 0) == 0) {
                ++removableCount;
            }
        }
        if (removableCount == 0) {
            return 0;
        }

        uint256 target = _bound(seed, 0, removableCount - 1);
        for (uint256 i; i < slots_.length; ++i) {
            uint96 slot = slots_[i];
            if (!delegator.getSlot(slot).exists || delegator.getAllocated(slot, 0) > 0) {
                continue;
            }
            if (target == 0) {
                return slot;
            }
            --target;
        }
        return 0;
    }

    function _selectParentWithAtLeastTwoChildren(uint256 seed) internal view returns (uint96) {
        uint96[] memory parents = new uint96[](1 + trackedRootSlots.length + trackedNetworkSlots.length);
        parents[0] = 0;

        uint256 cursor = 1;
        for (uint256 i; i < trackedRootSlots.length; ++i) {
            if (delegator.getSlot(trackedRootSlots[i]).exists) {
                parents[cursor++] = trackedRootSlots[i];
            }
        }
        for (uint256 i; i < trackedNetworkSlots.length; ++i) {
            if (delegator.getSlot(trackedNetworkSlots[i]).exists) {
                parents[cursor++] = trackedNetworkSlots[i];
            }
        }

        uint256 eligibleCount;
        for (uint256 i; i < cursor; ++i) {
            if (_liveChildrenOf(parents[i]).length >= 2) {
                ++eligibleCount;
            }
        }
        if (eligibleCount == 0) {
            return type(uint96).max;
        }

        uint256 target = _bound(seed, 0, eligibleCount - 1);
        for (uint256 i; i < cursor; ++i) {
            if (_liveChildrenOf(parents[i]).length < 2) {
                continue;
            }
            if (target == 0) {
                return parents[i];
            }
            --target;
        }
        return type(uint96).max;
    }

    function _liveChildrenOf(uint96 parent) internal view returns (uint96[] memory children) {
        IUniversalDelegator.Slot memory parentSlot = delegator.getSlot(parent);
        uint96[] memory scratch =
            new uint96[](parent == 0 ? MAX_SUBVAULTS : parent.getDepth() == 1 ? MAX_NETWORKS : MAX_OPERATORS);
        uint256 count;
        uint32 childIndex = parentSlot.firstChild;

        while (childIndex > 0 && childIndex < WITHDRAWAL_BUFFER_CHILD_INDEX) {
            uint96 child = parent.createIndex(childIndex);
            if (delegator.getSlot(child).exists) {
                scratch[count++] = child;
            }
            childIndex = delegator.getSlot(child).nextSlot;
        }

        children = new uint96[](count);
        for (uint256 i; i < count; ++i) {
            children[i] = scratch[i];
        }
    }
}
