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
import {NetworkMiddlewareService} from "../../src/contracts/service/NetworkMiddlewareService.sol";
import {OptInService} from "../../src/contracts/service/OptInService.sol";
import {UniversalSlasher} from "../../src/contracts/slasher/UniversalSlasher.sol";
import {MigratorV1V2} from "../../src/contracts/vault/MigratorV1V2.sol";
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

contract UniversalDelegatorGasTest is Test {
    using Subnetwork for address;

    uint48 internal constant EPOCH_DURATION = 16;
    uint48 internal constant CAPTURE_OFFSET = 4;
    uint48 internal constant START_TIMESTAMP = 1000;
    uint256 internal constant SECOND_CALL_WARP = 12;
    uint128 internal constant GROUP_SIZE = 3000 ether;
    uint128 internal constant NETWORK_SIZE = 1000 ether;
    uint128 internal constant OPERATOR_SIZE = 100 ether;
    uint256 internal constant DEPOSIT_AMOUNT = 9000 ether;
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
    MigratorV1V2 internal migratorV1V2;
    MockRewards internal rewards;

    Token internal collateral;
    IVaultV2 internal vault;
    UniversalDelegator internal delegator;
    IUniversalSlasher internal slasher;
    SlashBatchMiddleware internal batchMiddleware;

    bytes32 internal targetSubnetwork;
    address internal targetOperator;
    address internal nextOperator;

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
        migratorV1V2 = new MigratorV1V2(address(delegatorFactory), address(slasherFactory));
        rewards = new MockRewards();

        address vaultImplV1 =
            address(new VaultV1(address(delegatorFactory), address(slasherFactory), address(vaultFactory)));
        vaultFactory.whitelist(vaultImplV1);

        address vaultImplTokenized =
            address(new VaultTokenized(address(delegatorFactory), address(slasherFactory), address(vaultFactory)));
        vaultFactory.whitelist(vaultImplTokenized);

        address vaultImpl = address(
            new VaultV2(
                address(delegatorFactory),
                address(slasherFactory),
                address(vaultFactory),
                address(rewards),
                address(migratorV1V2)
            )
        );
        vaultFactory.whitelist(vaultImpl);

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

        address slasherImpl = address(
            new UniversalSlasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(networkRegistry),
                address(slasherFactory),
                slasherFactory.totalTypes()
            )
        );
        slasherFactory.whitelist(slasherImpl);

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
                        isDepositLimit: false,
                        depositLimit: 0,
                        defaultAdminRoleHolder: owner,
                        depositWhitelistSetRoleHolder: address(0),
                        depositorWhitelistRoleHolder: address(0),
                        isDepositLimitSetRoleHolder: address(0),
                        depositLimitSetRoleHolder: address(0),
                        setPluginLimitRoleHolder: address(0),
                        allocatePluginRoleHolder: address(0),
                        pluginsData: new IVaultV2.PluginData[](0)
                    })
                ),
                delegatorIndex: 0,
                delegatorParams: abi.encode(
                    IUniversalDelegator.InitParams({
                        defaultAdminRoleHolder: owner,
                        hook: address(0),
                        hookSetRoleHolder: address(0),
                        createSlotRoleHolder: owner,
                        setIsSharedRoleHolder: owner,
                        setSizeRoleHolder: owner,
                        setShareRoleHolder: owner,
                        swapSlotsRoleHolder: owner
                    })
                ),
                withSlasher: true,
                slasherIndex: 0,
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
        _setupTopology();
        vm.warp(setupTimestamp + CAPTURE_OFFSET + 1);
    }

    function test_Gas_StakeForAt_ExecuteSlash() public {
        uint48 timestamp = _currentCaptureTimestamp();
        bytes memory noHints = "";

        uint256 snapshot = vm.snapshotState();
        _measureIsolatedSequential("with_capture", timestamp, noHints);
        vm.revertToState(snapshot);

        _measureSingleTx("with_capture", timestamp, noHints, noHints);
        vm.revertToState(snapshot);

        _measureStakeForTimestamp("with_capture", timestamp, noHints, noHints);
        vm.revertToState(snapshot);

        _measureIsolatedSequential("no_capture", 0, noHints);
        vm.revertToState(snapshot);

        _measureSingleTx("no_capture", 0, noHints, noHints);
        vm.revertToState(snapshot);

        _measureStakeForTimestamp("no_capture", 0, noHints, noHints);
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
        for (uint256 groupIndex = 0; groupIndex < 3; ++groupIndex) {
            uint96 groupSlot = delegator.createSlot(bytes32(0), 0, false, false, GROUP_SIZE);

            for (uint256 networkIndex = 0; networkIndex < 3; ++networkIndex) {
                address network =
                    address(uint160(uint256(keccak256(abi.encodePacked("network", groupIndex, networkIndex)))));
                _registerNetwork(network);
                bytes32 subnetwork = network.subnetwork(uint96(networkIndex + 1));

                uint96 networkSlot = delegator.createSlot(subnetwork, groupSlot, false, false, NETWORK_SIZE);

                for (uint256 operatorIndex = 0; operatorIndex < 10; ++operatorIndex) {
                    address operator = address(
                        uint160(
                            uint256(keccak256(abi.encodePacked("operator", groupIndex, networkIndex, operatorIndex)))
                        )
                    );
                    delegator.createSlot(_operatorKey(operator), networkSlot, false, false, OPERATOR_SIZE);

                    if (groupIndex == 2 && networkIndex == 2 && operatorIndex == 9) {
                        targetSubnetwork = subnetwork;
                        targetOperator = operator;
                    }

                    if (groupIndex == 2 && networkIndex == 2 && operatorIndex == 8) {
                        nextOperator = operator;
                    }
                }
            }
        }
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
            groupAllocatedHints: bytes(""),
            groupCumulativeSlashFromHint: bytes("")
        });

        return abi.encode(hints);
    }

    function _allocatedHints() internal pure returns (bytes memory) {
        return abi.encode(_slotOfHints(), "");
    }

    function _groupAllocatedHints() internal pure returns (bytes memory) {
        return _baseAllocatedHints(_rootAvailableHints());
    }

    function _operatorAllocatedHints() internal pure returns (bytes memory) {
        bytes memory groupAllocated = _groupAllocatedHints();
        bytes memory groupAvailable = _availableHints(groupAllocated);
        bytes memory networkAllocated = _baseAllocatedHints(groupAvailable);
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
