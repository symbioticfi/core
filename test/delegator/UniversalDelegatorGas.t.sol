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

import {MockFeeRegistry} from "../mocks/MockFeeRegistry.sol";
import {MockRewards} from "../mocks/MockRewards.sol";
import {Token} from "../mocks/Token.sol";

contract UniversalDelegatorGasTest is Test {
    using Subnetwork for address;

    uint48 internal constant EPOCH_DURATION = 3;
    uint256 internal constant GROUP_SIZE = 3000 ether;
    uint256 internal constant NETWORK_SIZE = 1000 ether;
    uint256 internal constant OPERATOR_SIZE = 100 ether;
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
    MockFeeRegistry internal feeRegistry;

    Token internal collateral;
    IVaultV2 internal vault;
    UniversalDelegator internal delegator;
    IUniversalSlasher internal slasher;

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
        feeRegistry = new MockFeeRegistry(0);

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
                address(feeRegistry),
                address(migratorV1V2)
            )
        );
        vaultFactory.whitelist(vaultImpl);

        address delegatorImpl = address(
            new UniversalDelegator(
                address(networkRegistry),
                address(vaultFactory),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
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
                        addPluginRoleHolder: address(0),
                        removePluginRoleHolder: address(0),
                        pluginActiveDelay: EPOCH_DURATION * 3,
                        plugins: new address[](0)
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
                        swapSlotsRoleHolder: owner,
                        withdrawalBuffer: 0
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

        uint48 setupTimestamp = EPOCH_DURATION + 1;
        vm.warp(setupTimestamp);
        _deposit(owner, DEPOSIT_AMOUNT);
        _setupTopology();
        vm.warp(setupTimestamp + 1);
    }

    function test_Gas_StakeForAt_ExecuteSlash() public {
        uint48 timestamp = uint48(block.timestamp - 1);
        bytes memory noHints = "";
        bytes memory stakeForAtHints = _allocatedHints();

        uint256 stakeForNoHints = _measureStakeForAtGas(targetSubnetwork, targetOperator, timestamp, noHints);
        uint256 stakeForWithHints = _measureStakeForAtGas(targetSubnetwork, targetOperator, timestamp, stakeForAtHints);

        console2.log("stakeForAt_no_hints", stakeForNoHints);
        console2.log("stakeForAt_with_hints", stakeForWithHints);

        uint256 slashIndex = _requestSlash(targetSubnetwork, targetOperator, OPERATOR_SIZE / 2, timestamp);

        uint256 snapshot = vm.snapshotState();
        uint256 executeNoHints = _measureExecuteSlashGas(slashIndex, "");
        vm.revertToState(snapshot);
        uint256 executeWithHints = _measureExecuteSlashGas(slashIndex, _executeSlashHints());

        console2.log("executeSlash_no_hints", executeNoHints);
        console2.log("executeSlash_with_hints", executeWithHints);

        uint256 stakeForNoHints2 = _measureStakeForAtGas(targetSubnetwork, nextOperator, timestamp, noHints);
        uint256 stakeForWithHints2 = _measureStakeForAtGas(targetSubnetwork, nextOperator, timestamp, stakeForAtHints);

        console2.log("stakeForAt2_no_hints", stakeForNoHints2);
        console2.log("stakeForAt2_with_hints", stakeForWithHints2);

        uint256 slashIndex2 = _requestSlash(targetSubnetwork, nextOperator, OPERATOR_SIZE / 2, timestamp);

        uint256 snapshot2 = vm.snapshotState();
        uint256 executeNoHints2 = _measureExecuteSlashGas(slashIndex2, "");
        vm.revertToState(snapshot2);
        uint256 executeWithHints2 = _measureExecuteSlashGas(slashIndex2, _executeSlashHints());

        console2.log("executeSlash2_no_hints", executeNoHints2);
        console2.log("executeSlash2_with_hints", executeWithHints2);
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

    function _requestSlash(bytes32 subnetwork, address operator, uint256 amount, uint48 captureTimestamp)
        internal
        returns (uint256)
    {
        vm.startPrank(middleware);
        uint256 slashIndex = slasher.requestSlash(subnetwork, operator, amount, captureTimestamp, "");
        vm.stopPrank();
        return slashIndex;
    }

    function _measureStakeForAtGas(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hints)
        internal
        returns (uint256 gasUsed)
    {
        uint256 gasLeft = gasleft();
        uint256 stake = delegator.stakeForAt(subnetwork, operator, 0, timestamp, hints);
        gasUsed = gasLeft - gasleft();
        assertEq(stake, OPERATOR_SIZE);
    }

    function _measureExecuteSlashGas(uint256 slashIndex, bytes memory hints) internal returns (uint256 gasUsed) {
        vm.startPrank(middleware);
        uint256 gasLeft = gasleft();
        uint256 slashed = slasher.executeSlash(slashIndex, hints);
        gasUsed = gasLeft - gasleft();
        vm.stopPrank();
        assertEq(slashed, OPERATOR_SIZE / 2);
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
        return abi.encode(IUniversalDelegator.AllocatedHints({slotOfHints: _slotOfHints(), allocatedHints: bytes("")}));
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
        return abi.encode(
            IUniversalDelegator.BaseAllocatedHints({
                sizeHint: _zeroHint(), availableHints: availableHints, isSharedHint: bytes(""), prevSumHint: bytes("")
            })
        );
    }

    function _slotOfHints() internal pure returns (bytes memory) {
        return abi.encode(
            IUniversalDelegator.SlotOfHints({slotOfNetworkHints: _zeroHint(), slotOfOperatorHints: _zeroHint()})
        );
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
