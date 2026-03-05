// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {DelegatorFactory} from "../../src/contracts/DelegatorFactory.sol";
import {NetworkRegistry} from "../../src/contracts/NetworkRegistry.sol";
import {OperatorRegistry} from "../../src/contracts/OperatorRegistry.sol";
import {SlasherFactory} from "../../src/contracts/SlasherFactory.sol";
import {VaultConfigurator} from "../../src/contracts/VaultConfigurator.sol";
import {VaultFactory} from "../../src/contracts/VaultFactory.sol";
import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";
import {NetworkRestakeDelegator} from "../../src/contracts/delegator/NetworkRestakeDelegator.sol";
import {FullRestakeDelegator} from "../../src/contracts/delegator/FullRestakeDelegator.sol";
import {OperatorSpecificDelegator} from "../../src/contracts/delegator/OperatorSpecificDelegator.sol";
import {OperatorNetworkSpecificDelegator} from "../../src/contracts/delegator/OperatorNetworkSpecificDelegator.sol";
import {NetworkMiddlewareService} from "../../src/contracts/service/NetworkMiddlewareService.sol";
import {OptInService} from "../../src/contracts/service/OptInService.sol";
import {UniversalSlasher} from "../../src/contracts/slasher/UniversalSlasher.sol";
import {Slasher} from "../../src/contracts/slasher/Slasher.sol";
import {VetoSlasher} from "../../src/contracts/slasher/VetoSlasher.sol";
import {Vault as VaultV1} from "../../src/contracts/vault/Vault.sol";
import {VaultTokenized} from "../../src/contracts/vault/VaultTokenized.sol";
import {VaultV2} from "../../src/contracts/vault/VaultV2.sol";

import {Subnetwork} from "../../src/contracts/libraries/Subnetwork.sol";

import {IUniversalDelegator} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IUniversalSlasher} from "../../src/interfaces/slasher/IUniversalSlasher.sol";
import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";
import {IVaultV2} from "../../src/interfaces/vault/IVaultV2.sol";

import {MockRewards} from "../mocks/MockRewards.sol";
import {Token} from "../mocks/Token.sol";
import {CoreV2StakeForInvariantHelper} from "../helpers/CoreV2StakeForInvariantHelper.sol";

contract UniversalDelegatorGasTest is Test, CoreV2StakeForInvariantHelper {
    using Subnetwork for address;

    uint48 internal constant EPOCH_DURATION = 16;
    uint48 internal constant CAPTURE_OFFSET = 4;
    uint48 internal constant START_TIMESTAMP = 1000;
    uint256 internal constant SECOND_CALL_WARP = 12;
    uint128 internal constant SUBVAULT_SIZE = 3000 ether;
    uint128 internal constant NETWORK_SIZE = 1000 ether;
    uint128 internal constant OPERATOR_SIZE = 100 ether;
    uint256 internal constant DEPOSIT_AMOUNT = 9000 ether;
    uint256 internal constant WITHDRAW_AMOUNT = 1 ether;
    string internal constant VAULT_NAME = "Test";
    string internal constant VAULT_SYMBOL = "TEST";

    address internal owner;
    address internal middleware;

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
    SlashBatchMiddleware internal batchMiddleware;

    bytes32 internal targetSubnetwork;
    address internal targetOperator;
    address internal nextOperator;
    uint96[] internal operatorSlots;

    function setUp() public {
        owner = address(this);
        middleware = makeAddr("middleware");

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

        address vaultImpl = address(
            new VaultV2(
                address(delegatorFactory), address(slasherFactory), address(vaultFactory), address(rewards), address(0)
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
                        depositWhitelist: false,
                        depositorToWhitelist: address(0xBEEF),
                        isDepositLimit: false,
                        depositLimit: 0,
                        defaultAdminRoleHolder: owner,
                        depositWhitelistSetRoleHolder: address(0),
                        depositorWhitelistRoleHolder: address(0),
                        isDepositLimitSetRoleHolder: address(0),
                        depositLimitSetRoleHolder: address(0),
                        setPluginLimitRoleHolder: address(0),
                        allocatePluginRoleHolder: address(0)
                    })
                ),
                delegatorIndex: uint64(delegatorFactory.totalTypes() - 1),
                delegatorParams: abi.encode(
                    IUniversalDelegator.InitParams({
                        defaultAdminRoleHolder: owner,
                        hook: address(0),
                        hookSetRoleHolder: address(0),
                        createSlotRoleHolder: owner,
                        setSizeRoleHolder: owner,
                        swapSlotsRoleHolder: owner,
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
        batchMiddleware = new SlashBatchMiddleware(slasher);

        uint48 setupTimestamp = START_TIMESTAMP + EPOCH_DURATION;
        vm.warp(setupTimestamp);
        _deposit(owner, DEPOSIT_AMOUNT);
        _withdraw(owner, WITHDRAW_AMOUNT);
        _setupTopology();
        _assertStakeForInvariantAcrossOperatorSlots();
        vm.warp(setupTimestamp + CAPTURE_OFFSET + 1);
    }

    function test_Gas_StakeForAt_ExecuteSlash() public {
        uint48 timestamp = _currentCaptureTimestamp();
        bytes memory noHints = "";

        uint256 snapshot = vm.snapshotState();
        _assertStakeForInvariantAcrossOperatorSlots();
        _measureIsolatedSequential("with_capture", timestamp, noHints);
        _assertStakeForInvariantAcrossOperatorSlots();
        vm.revertToState(snapshot);

        _measureSingleTx("with_capture", timestamp, noHints, noHints);
        _assertStakeForInvariantAcrossOperatorSlots();
        vm.revertToState(snapshot);

        _measureStakeForTimestamp("with_capture", timestamp, noHints, noHints);
        _assertStakeForInvariantAcrossOperatorSlots();
        vm.revertToState(snapshot);

        _measureIsolatedSequential("no_capture", 0, noHints);
        _assertStakeForInvariantAcrossOperatorSlots();
        vm.revertToState(snapshot);

        _measureSingleTx("no_capture", 0, noHints, noHints);
        _assertStakeForInvariantAcrossOperatorSlots();
        vm.revertToState(snapshot);

        _measureStakeForTimestamp("no_capture", 0, noHints, noHints);
        _assertStakeForInvariantAcrossOperatorSlots();
    }

    function _measureIsolatedSequential(string memory labelPrefix, uint48 captureTimestamp, bytes memory executeHints)
        internal
    {
        (uint256 slashIndex1, uint256 request1) =
            _measureRequestSlashGas(targetSubnetwork, targetOperator, OPERATOR_SIZE / 2, captureTimestamp);
        (uint256 slashIndex2, uint256 request2) =
            _measureRequestSlashGas(targetSubnetwork, nextOperator, OPERATOR_SIZE / 2, captureTimestamp);

        vm.warp(uint256(block.timestamp) + SECOND_CALL_WARP);

        uint256 exec1 = _measureExecuteSlashGas(slashIndex1, executeHints);
        uint256 exec2 = _measureExecuteSlashGas(slashIndex2, executeHints);

        console2.log(string.concat(labelPrefix, "_isolated_request1"), request1);
        console2.log(string.concat(labelPrefix, "_isolated_request2"), request2);
        console2.log(string.concat(labelPrefix, "_isolated_execute1"), exec1);
        console2.log(string.concat(labelPrefix, "_isolated_execute2"), exec2);
    }

    function _measureSingleTx(
        string memory labelPrefix,
        uint48 captureTimestamp,
        bytes memory stakeHints,
        bytes memory executeHints
    ) internal {
        _setMiddleware(targetSubnetwork, address(batchMiddleware));
        (uint256 slashIndex1, uint256 slashIndex2, uint256 request1, uint256 request2) = batchMiddleware.requestTwo(
            targetSubnetwork, targetOperator, nextOperator, OPERATOR_SIZE / 2, captureTimestamp, stakeHints
        );
        (uint256 execute1, uint256 execute2) = batchMiddleware.executeTwo(slashIndex1, slashIndex2, executeHints);

        console2.log(string.concat(labelPrefix, "_single_request1"), request1);
        console2.log(string.concat(labelPrefix, "_single_request2"), request2);
        console2.log(string.concat(labelPrefix, "_single_execute1"), execute1);
        console2.log(string.concat(labelPrefix, "_single_execute2"), execute2);
    }

    function _measureStakeForTimestamp(
        string memory labelPrefix,
        uint48 captureTimestamp,
        bytes memory stakeHints,
        bytes memory executeHints
    ) internal {
        uint256 stakeBefore = _measureStakeForAtGas(targetSubnetwork, targetOperator, captureTimestamp, stakeHints);

        (uint256 slashIndex1,) =
            _measureRequestSlashGas(targetSubnetwork, targetOperator, OPERATOR_SIZE / 2, captureTimestamp);
        _measureExecuteSlashGas(slashIndex1, executeHints);

        uint256 stakeAfter = _measureStakeForAtGas(targetSubnetwork, nextOperator, captureTimestamp, stakeHints);

        console2.log(string.concat(labelPrefix, "_stake_before"), stakeBefore);
        console2.log(string.concat(labelPrefix, "_stake_after"), stakeAfter);
    }

    function _setupTopology() internal {
        for (uint256 subvaultIndex = 0; subvaultIndex < 3; ++subvaultIndex) {
            uint96 subvaultSlot = delegator.createSlot(bytes32(0), 0, false, false, SUBVAULT_SIZE);

            for (uint256 networkIndex = 0; networkIndex < 3; ++networkIndex) {
                address network =
                    address(uint160(uint256(keccak256(abi.encodePacked("network", subvaultIndex, networkIndex)))));
                _registerNetwork(network);
                uint96 networkIdentifier = uint96(networkIndex + 1);
                bytes32 subnetwork = network.subnetwork(networkIdentifier);
                vm.prank(network);
                delegator.setMaxNetworkLimit(networkIdentifier, type(uint256).max);

                uint96 networkSlot = delegator.createSlot(subnetwork, subvaultSlot, false, false, NETWORK_SIZE);

                for (uint256 operatorIndex = 0; operatorIndex < 10; ++operatorIndex) {
                    address operator = address(
                        uint160(
                            uint256(keccak256(abi.encodePacked("operator", subvaultIndex, networkIndex, operatorIndex)))
                        )
                    );
                    uint96 operatorSlot =
                        delegator.createSlot(_operatorKey(operator), networkSlot, false, false, OPERATOR_SIZE);
                    operatorSlots.push(operatorSlot);

                    if (subvaultIndex == 2 && networkIndex == 2 && operatorIndex == 9) {
                        targetSubnetwork = subnetwork;
                        targetOperator = operator;
                    }

                    if (subvaultIndex == 2 && networkIndex == 2 && operatorIndex == 8) {
                        nextOperator = operator;
                    }
                }
            }
        }
    }

    function _assertStakeForInvariantAcrossOperatorSlots() internal view {
        uint96[] memory slots = new uint96[](operatorSlots.length);
        for (uint256 i = 0; i < operatorSlots.length; ++i) {
            slots[i] = operatorSlots[i];
        }

        _assertStakeForInvariantForDurations(address(vault), address(delegator), slots, EPOCH_DURATION);
    }

    function _setMiddleware(bytes32 subnetwork, address middleware_) internal {
        address network = Subnetwork.network(subnetwork);
        vm.startPrank(network);
        networkMiddlewareService.setMiddleware(middleware_);
        vm.stopPrank();
    }

    function _measureRequestSlashGas(bytes32 subnetwork, address operator, uint256 amount, uint48 captureTimestamp)
        internal
        returns (uint256 slashIndex, uint256 gasUsed)
    {
        vm.startPrank(middleware);
        uint256 gasLeft = gasleft();
        slashIndex = slasher.requestSlash(subnetwork, operator, amount, captureTimestamp, "");
        gasUsed = gasLeft - gasleft();
        vm.stopPrank();
    }

    function _measureStakeForAtGas(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hints)
        internal
        returns (uint256 gasUsed)
    {
        uint256 gasLeft = gasleft();
        uint256 stake;
        hints;
        if (timestamp == 0) {
            stake = delegator.stakeFor(subnetwork, operator, 0);
        } else {
            stake = delegator.stakeForAt(subnetwork, operator, 0, timestamp);
        }
        gasUsed = gasLeft - gasleft();
        if (timestamp != 0) {
            assertEq(stake, OPERATOR_SIZE);
        }
    }

    function _measureExecuteSlashGas(uint256 slashIndex, bytes memory hints) internal returns (uint256 gasUsed) {
        vm.startPrank(middleware);
        uint256 gasLeft = gasleft();
        uint256 slashed = slasher.executeSlash(slashIndex, hints);
        gasUsed = gasLeft - gasleft();
        vm.stopPrank();
        assertEq(slashed, OPERATOR_SIZE / 2);
    }

    function _currentCaptureTimestamp() internal view returns (uint48) {
        return uint48(block.timestamp - CAPTURE_OFFSET);
    }

    function _executeSlashHints() internal pure returns (bytes memory) {
        return abi.encode(_slashableStakeHints(), _vaultOnSlashHints());
    }

    function _vaultOnSlashHints() internal pure returns (bytes memory) {
        return bytes("");
    }

    function _slashableStakeHints() internal pure returns (bytes memory) {
        IUniversalSlasher.SlashableStakeHints memory hints = IUniversalSlasher.SlashableStakeHints({
            stakeHints: _allocatedHints(),
            cumulativeSlashFromHint: bytes(""),
            slotOfHints: bytes(""),
            subvaultAllocatedHints: bytes(""),
            subvaultCumulativeSlashFromHint: bytes("")
        });

        return abi.encode(hints);
    }

    function _allocatedHints() internal pure returns (bytes memory) {
        return abi.encode(_slotOfHints(), "");
    }

    function _subvaultAllocatedHints() internal pure returns (bytes memory) {
        return _baseAllocatedHints(_rootAvailableHints());
    }

    function _operatorAllocatedHints() internal pure returns (bytes memory) {
        bytes memory subvaultAllocated = _subvaultAllocatedHints();
        bytes memory subvaultAvailable = _availableHints(subvaultAllocated);
        bytes memory networkAllocated = _baseAllocatedHints(subvaultAvailable);
        bytes memory networkAvailable = _availableHints(networkAllocated);
        return _baseAllocatedHints(networkAvailable);
    }

    function _rootAvailableHints() internal pure returns (bytes memory) {
        return _availableHints(_zeroHint());
    }

    function _availableHints(bytes memory balanceHints) internal pure returns (bytes memory) {
        return abi.encode(balanceHints, bytes(""), bytes(""));
    }

    function _baseAllocatedHints(bytes memory availableHints) internal pure returns (bytes memory) {
        return abi.encode(_zeroHint(), availableHints, bytes(""), bytes(""));
    }

    function _slotOfHints() internal pure returns (bytes memory) {
        return abi.encode(_zeroHint(), _zeroHint());
    }

    function _zeroHint() internal pure returns (bytes memory) {
        return abi.encode(uint32(0));
    }

    function _operatorKey(address operator) internal pure returns (bytes32) {
        return bytes32(bytes20(operator));
    }

    function _registerNetwork(address network) internal {
        vm.startPrank(network);
        networkRegistry.registerNetwork();
        networkMiddlewareService.setMiddleware(middleware);
        vm.stopPrank();
    }

    function _deposit(address user, uint256 amount) internal {
        collateral.transfer(user, amount);

        vm.startPrank(user);
        collateral.approve(address(vault), amount);
        vault.deposit(user, amount);
        vm.stopPrank();
    }

    function _withdraw(address user, uint256 amount) internal {
        vm.startPrank(user);
        vault.withdraw(user, amount);
        vm.stopPrank();
    }
}

contract SlashBatchMiddleware {
    IUniversalSlasher internal immutable _slasher;

    constructor(IUniversalSlasher slasher_) {
        _slasher = slasher_;
    }

    function requestTwo(
        bytes32 subnetwork,
        address operator1,
        address operator2,
        uint256 amount,
        uint48 captureTimestamp,
        bytes calldata requestHints
    ) external returns (uint256 slashIndex1, uint256 slashIndex2, uint256 gas1, uint256 gas2) {
        uint256 gasLeft = gasleft();
        slashIndex1 = _slasher.requestSlash(subnetwork, operator1, amount, captureTimestamp, requestHints);
        gas1 = gasLeft - gasleft();

        gasLeft = gasleft();
        slashIndex2 = _slasher.requestSlash(subnetwork, operator2, amount, captureTimestamp, requestHints);
        gas2 = gasLeft - gasleft();
    }

    function executeTwo(uint256 slashIndex1, uint256 slashIndex2, bytes calldata executeHints)
        external
        returns (uint256 gas1, uint256 gas2)
    {
        uint256 gasLeft = gasleft();
        _slasher.executeSlash(slashIndex1, executeHints);
        gas1 = gasLeft - gasleft();

        gasLeft = gasleft();
        _slasher.executeSlash(slashIndex2, executeHints);
        gas2 = gasLeft - gasleft();
    }
}
