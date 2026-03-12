// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {VaultFactory} from "../../src/contracts/VaultFactory.sol";
import {DelegatorFactory} from "../../src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "../../src/contracts/SlasherFactory.sol";
import {NetworkRegistry} from "../../src/contracts/NetworkRegistry.sol";
import {OperatorRegistry} from "../../src/contracts/OperatorRegistry.sol";
import {VaultConfigurator} from "../../src/contracts/VaultConfigurator.sol";
import {NetworkMiddlewareService} from "../../src/contracts/service/NetworkMiddlewareService.sol";
import {OptInService} from "../../src/contracts/service/OptInService.sol";

import {VaultV2} from "../../src/contracts/vault/VaultV2.sol";
import {Vault as VaultV1} from "../../src/contracts/vault/Vault.sol";
import {VaultTokenized} from "../../src/contracts/vault/VaultTokenized.sol";
import {NetworkRestakeDelegator} from "../../src/contracts/delegator/NetworkRestakeDelegator.sol";
import {FullRestakeDelegator} from "../../src/contracts/delegator/FullRestakeDelegator.sol";
import {OperatorSpecificDelegator} from "../../src/contracts/delegator/OperatorSpecificDelegator.sol";
import {OperatorNetworkSpecificDelegator} from "../../src/contracts/delegator/OperatorNetworkSpecificDelegator.sol";
import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";
import {Slasher} from "../../src/contracts/slasher/Slasher.sol";
import {UniversalSlasher} from "../../src/contracts/slasher/UniversalSlasher.sol";
import {VetoSlasher} from "../../src/contracts/slasher/VetoSlasher.sol";

import {UniversalDelegatorIndex} from "../../src/contracts/libraries/UniversalDelegatorIndex.sol";
import {Subnetwork} from "../../src/contracts/libraries/Subnetwork.sol";

import {IUniversalDelegator, UNIVERSAL_DELEGATOR_TYPE} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IUniversalSlasher} from "../../src/interfaces/slasher/IUniversalSlasher.sol";
import {IVaultV2} from "../../src/interfaces/vault/IVaultV2.sol";
import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";

import {Token} from "../mocks/Token.sol";
import {MockRewards} from "../mocks/MockRewards.sol";

contract UniversalDelegatorSharedSimulationTest is Test {
    using UniversalDelegatorIndex for uint96;
    using Subnetwork for address;

    uint48 internal constant EPOCH_DURATION = 3 days;
    string internal constant VAULT_NAME = "Shared Simulation Vault";
    string internal constant VAULT_SYMBOL = "SSVLT";
    address internal constant DUMMY_NETWORK = address(0xdeAD00000000000000000000000000000000dEAd);
    address internal constant DUMMY_OPERATOR_BASE = address(0xBEEF00000000000000000000000000000000BEEf);

    address internal owner;
    address internal alice;
    address internal bob;

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
    uint96 internal dummyNetworkId;
    uint160 internal dummyOperatorId;

    struct BigCtx {
        uint96 isolatedX;
        uint96 sharedA;
        uint96 isolatedY;
        uint96 sharedB;
        bytes32 subnetworkX;
        bytes32 subnetworkA1;
        bytes32 subnetworkA2;
        bytes32 subnetworkA3;
        bytes32 subnetworkY;
        bytes32 subnetworkB1;
        bytes32 subnetworkB2;
        address xavier;
        address carol;
        address dave;
        address iris;
        address jack;
        address yves;
        address erin;
        address frank;
        address gina;
        address hank;
        address middleware;
    }

    function setUp() public {
        vm.warp(0);

        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");

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
    }

    function test_simulation_exampleShared_siblingSlashSettlement() public {
        _logExampleSharedSiblingSlashSettlement();
    }

    function test_simulation_exampleShared_freshNetworkBaseline() public {
        _logExampleSharedFreshNetworkBaseline();
    }

    function test_simulation_exampleShared_regrowth() public {
        _logExampleSharedRegrowth();
    }

    function test_simulation_exampleShared_onSlashUnassigned() public {
        _logExampleSharedOnSlashUnassigned();
    }

    function test_simulation_exampleSharedBig_currentBehavior() public {
        BigCtx memory p = _setupBigSimulation();

        _deposit(alice, 20);
        _logBigCheckpoint("t0", p);

        vm.warp(1);
        vm.prank(p.middleware);
        uint256 slashIndex = slasher.requestSlash(p.subnetworkA1, alice, 3, 0, "");
        vm.prank(p.middleware);
        slasher.executeSlash(slashIndex, "");
        _logBigCheckpoint("t1", p);

        _withdraw(alice, 5);
        _logBigCheckpoint("t2", p);

        _createNetworkSlot(p.sharedA, p.subnetworkA3, 8);
        uint96 networkSlotA3 = p.sharedA.createIndex(uint32(3));
        _createOperatorSlot(networkSlotA3, p.iris, 5);
        _createOperatorSlot(networkSlotA3, p.jack, 5);
        _logBigCheckpoint("t3", p);

        delegator.setSize(p.sharedA, 4);
        delegator.setSize(delegator.getSlotOfNetwork(p.subnetworkA2), 4);
        delegator.setSize(delegator.getSlotOf(p.subnetworkA2, p.carol), 2);
        delegator.setSize(delegator.getSlotOf(p.subnetworkA2, p.dave), 2);
        _logBigCheckpoint("t4", p);

        vm.warp(block.timestamp + 1);
        _withdraw(alice, 2);
        _logBigCheckpoint("t4w", p);

        vm.warp(block.timestamp + EPOCH_DURATION + 1);
        _logBigCheckpoint("t5", p);

        _deposit(alice, 8);
        _logBigCheckpoint("t6", p);
    }

    function test_simulation_sharedPendingDoesNotCreateSharedGuaranteeForFreshNetwork() public {
        address network1 = makeAddr("sim-proof-network1");
        address network2 = makeAddr("sim-proof-network2");
        address middleware = makeAddr("sim-proof-middleware");

        _registerNetwork(network1, middleware);
        _registerNetwork(network2, middleware);
        _registerOperator(alice);
        _registerOperator(bob);
        _optIn(alice, network1);
        _optIn(bob, network2);
        _setUnlimited(network1);
        _setUnlimited(network2);

        _createSlot(0, true, 10);
        uint96 sharedSubvault = _rootIndex(uint32(1));
        _createNetworkSlot(sharedSubvault, network1.subnetwork(0), 100);
        _createOperatorSlot(sharedSubvault.createIndex(uint32(1)), alice, 100);

        _deposit(alice, 10);

        // This withdrawal expires before the pending window below does.
        vm.warp(1);
        _withdraw(alice, 4);

        // Old pending tranche: network2 must not inherit this one.
        vm.warp(100);
        delegator.setSize(sharedSubvault, 6);

        _createNetworkSlot(sharedSubvault, network2.subnetwork(0), 100);
        _createOperatorSlot(sharedSubvault.createIndex(uint32(2)), bob, 100);

        // New pending tranche: network2 should not get extra slashability from this either
        // until shared pending is actually consumed by a slash.
        vm.warp(200);
        delegator.setSize(sharedSubvault, 2);

        // Withdrawal is expired, both pending tranches are still active.
        vm.warp(EPOCH_DURATION + 2);

        assertEq(delegator.getAllocated(sharedSubvault, 0), 6);
        assertEq(delegator.getPending(sharedSubvault, 0), 8);
        assertEq(delegator.stakeFor(network2.subnetwork(0), bob, 0), 6);
        assertEq(slasher.slashableStake(network2.subnetwork(0), bob, 0, ""), 6);
    }

    function _logExampleSharedSiblingSlashSettlement() internal {
        address network1 = makeAddr("sim-shared-network1");
        address network2 = makeAddr("sim-shared-network2");
        address network3 = makeAddr("sim-shared-network3");
        address middleware = makeAddr("sim-shared-middleware");
        address carol = makeAddr("sim-shared-carol");

        _registerNetwork(network1, middleware);
        _registerNetwork(network2, middleware);
        _registerNetwork(network3, middleware);
        _registerOperator(alice);
        _registerOperator(bob);
        _registerOperator(carol);
        _optIn(alice, network1);
        _optIn(bob, network2);
        _optIn(carol, network3);

        bytes32 subnetwork1 = network1.subnetwork(0);
        bytes32 subnetwork2 = network2.subnetwork(0);
        bytes32 subnetwork3 = network3.subnetwork(0);
        _setUnlimited(network1);
        _setUnlimited(network2);
        _setUnlimited(network3);

        _createSlot(0, true, 10);
        uint96 sharedSubvault = _rootIndex(uint32(1));
        _createSlot(0, false, 10);
        uint96 isolatedSubvault = _rootIndex(uint32(2));
        _createNetworkSlot(sharedSubvault, subnetwork1, 10);
        _createNetworkSlot(sharedSubvault, subnetwork2, 10);
        _createNetworkSlot(isolatedSubvault, subnetwork3, 10);
        _createOperatorSlot(sharedSubvault.createIndex(uint32(1)), alice, 10);
        _createOperatorSlot(sharedSubvault.createIndex(uint32(2)), bob, 10);
        _createOperatorSlot(isolatedSubvault.createIndex(uint32(1)), carol, 10);

        _deposit(alice, 20);
        vm.warp(1);

        console2.log("example shared / before first slash / stake A", delegator.stake(subnetwork1, alice));
        console2.log("example shared / before first slash / stake B", delegator.stake(subnetwork2, bob));
        console2.log("example shared / before first slash / stake C", delegator.stake(subnetwork3, carol));
        console2.log(
            "example shared / before first slash / slashable B", slasher.slashableStake(subnetwork2, bob, 0, "")
        );

        vm.prank(middleware);
        uint256 slashIndex1 = slasher.requestSlash(subnetwork1, alice, 10, 0, "");
        vm.prank(middleware);
        uint256 slashIndex2 = slasher.requestSlash(subnetwork2, bob, 10, 0, "");

        vm.prank(middleware);
        slasher.executeSlash(slashIndex1, "");

        console2.log("example shared / after first slash / stake A", delegator.stake(subnetwork1, alice));
        console2.log("example shared / after first slash / stake B", delegator.stake(subnetwork2, bob));
        console2.log("example shared / after first slash / stake C", delegator.stake(subnetwork3, carol));
        console2.log(
            "example shared / after first slash / slashable B", slasher.slashableStake(subnetwork2, bob, 0, "")
        );

        vm.prank(middleware);
        uint256 settled = slasher.executeSlash(slashIndex2, "");

        console2.log("example shared / after second slash / settled B", settled);
        console2.log("example shared / after second slash / stake C", delegator.stake(subnetwork3, carol));
        console2.log(
            "example shared / after second slash / slashable B", slasher.slashableStake(subnetwork2, bob, 0, "")
        );
    }

    function _logExampleSharedFreshNetworkBaseline() internal {
        address network1 = makeAddr("sim-pending-network1");
        address network2 = makeAddr("sim-pending-network2");
        address middleware = makeAddr("sim-pending-middleware");

        _registerNetwork(network1, middleware);
        _registerNetwork(network2, middleware);
        _registerOperator(alice);
        _registerOperator(bob);
        _optIn(alice, network1);
        _optIn(bob, network2);

        bytes32 subnetwork1 = network1.subnetwork(0);
        bytes32 subnetwork2 = network2.subnetwork(0);
        _setUnlimited(network1);
        _setUnlimited(network2);

        _createSlot(0, true, 10);
        uint96 sharedSubvault = _rootIndex(uint32(1));
        _createNetworkSlot(sharedSubvault, subnetwork1, 10);
        uint96 networkSlot1 = sharedSubvault.createIndex(uint32(1));
        _createOperatorSlot(networkSlot1, alice, 10);

        _deposit(alice, 8);
        vm.warp(1);
        delegator.setSize(sharedSubvault, 5);

        _createNetworkSlot(sharedSubvault, subnetwork2, 100);
        uint96 networkSlot2 = sharedSubvault.createIndex(uint32(2));
        _createOperatorSlot(networkSlot2, bob, 100);

        console2.log("example shared / pending baseline / shared allocated", delegator.getAllocated(sharedSubvault, 0));
        console2.log("example shared / pending baseline / shared pending", delegator.getPending(sharedSubvault, 0));
        console2.log("example shared / pending baseline / public stake", delegator.stake(subnetwork2, bob));
        console2.log(
            "example shared / pending baseline / slashable stake", slasher.slashableStake(subnetwork2, bob, 0, "")
        );
    }

    function _logExampleSharedRegrowth() internal {
        address network1 = makeAddr("sim-regrowth-network1");
        address network2 = makeAddr("sim-regrowth-network2");
        address middleware = makeAddr("sim-regrowth-middleware");

        _registerNetwork(network1, middleware);
        _registerNetwork(network2, middleware);
        _registerOperator(alice);
        _registerOperator(bob);
        _optIn(alice, network1);
        _optIn(bob, network2);

        bytes32 subnetwork1 = network1.subnetwork(0);
        bytes32 subnetwork2 = network2.subnetwork(0);
        _setUnlimited(network1);
        _setUnlimited(network2);

        _createSlot(0, true, 10);
        uint96 sharedSubvault = _rootIndex(uint32(1));
        _createNetworkSlot(sharedSubvault, subnetwork1, 10);
        _createNetworkSlot(sharedSubvault, subnetwork2, 10);
        uint96 networkSlot1 = sharedSubvault.createIndex(uint32(1));
        uint96 networkSlot2 = sharedSubvault.createIndex(uint32(2));
        _createOperatorSlot(networkSlot1, alice, 10);
        _createOperatorSlot(networkSlot2, bob, 10);
        uint96 operatorSlot1 = networkSlot1.createIndex(uint32(1));

        _deposit(alice, 10);
        vm.warp(1);

        vm.prank(middleware);
        uint256 slashIndex = slasher.requestSlash(subnetwork1, alice, 3, 0, "");
        vm.prank(middleware);
        slasher.executeSlash(slashIndex, "");

        console2.log("example shared / regrowth / right after slash / public A", delegator.stake(subnetwork1, alice));
        console2.log(
            "example shared / regrowth / right after slash / slashable A",
            slasher.slashableStake(subnetwork1, alice, 0, "")
        );
        console2.log(
            "example shared / regrowth / right after slash / slashable B",
            slasher.slashableStake(subnetwork2, bob, 0, "")
        );

        delegator.setSize(networkSlot1, 10);
        delegator.setSize(operatorSlot1, 10);

        console2.log("example shared / regrowth / after regrow / public A", delegator.stake(subnetwork1, alice));
        console2.log(
            "example shared / regrowth / after regrow / slashable A", slasher.slashableStake(subnetwork1, alice, 0, "")
        );
        console2.log(
            "example shared / regrowth / after regrow / slashable B", slasher.slashableStake(subnetwork2, bob, 0, "")
        );
    }

    function _logExampleSharedOnSlashUnassigned() internal {
        vm.prank(address(slasher));
        try delegator.onSlash(bytes32(0), address(0), 0, "") returns (uint256) {
            console2.log("example shared / onSlash unassigned / no revert");
        } catch (bytes memory err) {
            console2.log("example shared / onSlash unassigned / revert data length", err.length);
        }
    }

    function _setupBigSimulation() internal returns (BigCtx memory p) {
        p.middleware = makeAddr("big-middleware");
        address networkX = makeAddr("big-networkX");
        address networkA1 = makeAddr("big-networkA1");
        address networkA2 = makeAddr("big-networkA2");
        address networkA3 = makeAddr("big-networkA3");
        address networkY = makeAddr("big-networkY");
        address networkB1 = makeAddr("big-networkB1");
        address networkB2 = makeAddr("big-networkB2");

        p.xavier = makeAddr("big-xavier");
        p.carol = makeAddr("big-carol");
        p.dave = makeAddr("big-dave");
        p.iris = makeAddr("big-iris");
        p.jack = makeAddr("big-jack");
        p.yves = makeAddr("big-yves");
        p.erin = makeAddr("big-erin");
        p.frank = makeAddr("big-frank");
        p.gina = makeAddr("big-gina");
        p.hank = makeAddr("big-hank");

        _registerNetwork(networkX, p.middleware);
        _registerNetwork(networkA1, p.middleware);
        _registerNetwork(networkA2, p.middleware);
        _registerNetwork(networkA3, p.middleware);
        _registerNetwork(networkY, p.middleware);
        _registerNetwork(networkB1, p.middleware);
        _registerNetwork(networkB2, p.middleware);

        _registerOperator(alice);
        _registerOperator(bob);
        _registerOperator(p.xavier);
        _registerOperator(p.carol);
        _registerOperator(p.dave);
        _registerOperator(p.iris);
        _registerOperator(p.jack);
        _registerOperator(p.yves);
        _registerOperator(p.erin);
        _registerOperator(p.frank);
        _registerOperator(p.gina);
        _registerOperator(p.hank);

        _optIn(p.xavier, networkX);
        _optIn(alice, networkA1);
        _optIn(bob, networkA1);
        _optIn(p.carol, networkA2);
        _optIn(p.dave, networkA2);
        _optIn(p.iris, networkA3);
        _optIn(p.jack, networkA3);
        _optIn(p.yves, networkY);
        _optIn(p.erin, networkB1);
        _optIn(p.frank, networkB1);
        _optIn(p.gina, networkB2);
        _optIn(p.hank, networkB2);

        p.subnetworkX = networkX.subnetwork(0);
        p.subnetworkA1 = networkA1.subnetwork(0);
        p.subnetworkA2 = networkA2.subnetwork(0);
        p.subnetworkA3 = networkA3.subnetwork(0);
        p.subnetworkY = networkY.subnetwork(0);
        p.subnetworkB1 = networkB1.subnetwork(0);
        p.subnetworkB2 = networkB2.subnetwork(0);

        _setUnlimited(networkX);
        _setUnlimited(networkA1);
        _setUnlimited(networkA2);
        _setUnlimited(networkA3);
        _setUnlimited(networkY);
        _setUnlimited(networkB1);
        _setUnlimited(networkB2);

        _createSlot(0, false, 6);
        p.isolatedX = _rootIndex(uint32(1));
        _createSlot(0, true, 10);
        p.sharedA = _rootIndex(uint32(2));
        _createSlot(0, false, 4);
        p.isolatedY = _rootIndex(uint32(3));
        _createSlot(0, true, 8);
        p.sharedB = _rootIndex(uint32(4));

        _createNetworkSlot(p.isolatedX, p.subnetworkX, 8);
        _createOperatorSlot(p.isolatedX.createIndex(uint32(1)), p.xavier, 6);

        _createNetworkSlot(p.sharedA, p.subnetworkA1, 12);
        uint96 networkSlotA1 = p.sharedA.createIndex(uint32(1));
        _createOperatorSlot(networkSlotA1, alice, 6);
        _createOperatorSlot(networkSlotA1, bob, 4);

        _createNetworkSlot(p.sharedA, p.subnetworkA2, 8);
        uint96 networkSlotA2 = p.sharedA.createIndex(uint32(2));
        _createOperatorSlot(networkSlotA2, p.carol, 3);
        _createOperatorSlot(networkSlotA2, p.dave, 4);

        _createNetworkSlot(p.isolatedY, p.subnetworkY, 5);
        _createOperatorSlot(p.isolatedY.createIndex(uint32(1)), p.yves, 4);

        _createNetworkSlot(p.sharedB, p.subnetworkB1, 6);
        uint96 networkSlotB1 = p.sharedB.createIndex(uint32(1));
        _createOperatorSlot(networkSlotB1, p.erin, 5);
        _createOperatorSlot(networkSlotB1, p.frank, 3);

        _createNetworkSlot(p.sharedB, p.subnetworkB2, 7);
        uint96 networkSlotB2 = p.sharedB.createIndex(uint32(2));
        _createOperatorSlot(networkSlotB2, p.gina, 2);
        _createOperatorSlot(networkSlotB2, p.hank, 3);
    }

    function _logBigCheckpoint(string memory label, BigCtx memory p) internal view {
        console2.log("big checkpoint", label);
        console2.log("activeStake", vault.activeStake());
        console2.log("activeWithdrawals0", vault.activeWithdrawalsFor(0));
        console2.log("funded isolatedX", delegator.getAllocated(p.isolatedX, 0));
        console2.log("funded sharedA", delegator.getAllocated(p.sharedA, 0));
        console2.log("funded isolatedY", delegator.getAllocated(p.isolatedY, 0));
        console2.log("funded sharedB", delegator.getAllocated(p.sharedB, 0));
        console2.log("pending sharedA", delegator.getPending(p.sharedA, 0));
        console2.log("pending networkA2", delegator.getPending(delegator.getSlotOfNetwork(p.subnetworkA2), 0));
        console2.log("pending dave", delegator.getPending(delegator.getSlotOf(p.subnetworkA2, p.dave), 0));

        _logOperator(0, p.subnetworkX, p.xavier);
        _logOperator(1, p.subnetworkA1, alice);
        _logOperator(2, p.subnetworkA1, bob);
        _logOperator(3, p.subnetworkA2, p.carol);
        _logOperator(4, p.subnetworkA2, p.dave);
        _logOperator(5, p.subnetworkA3, p.iris);
        _logOperator(6, p.subnetworkA3, p.jack);
        _logOperator(7, p.subnetworkY, p.yves);
        _logOperator(8, p.subnetworkB1, p.erin);
        _logOperator(9, p.subnetworkB1, p.frank);
        _logOperator(10, p.subnetworkB2, p.gina);
        _logOperator(11, p.subnetworkB2, p.hank);
    }

    function _logOperator(uint256 idx, bytes32 subnetwork, address operator) internal view {
        if (delegator.getSlotOf(subnetwork, operator) == 0) {
            console2.log("operator", idx);
            console2.log("stake", type(uint256).max);
            console2.log("slashable", type(uint256).max);
            return;
        }

        console2.log("operator", idx);
        console2.log("stake", delegator.stake(subnetwork, operator));
        console2.log("slashable", slasher.slashableStake(subnetwork, operator, 0, ""));
    }

    function _createSlot(uint96 parentIndex, bool isShared, uint256 size) internal {
        bytes32 key;
        uint256 depth = parentIndex.getDepth();
        if (depth == 1) {
            ++dummyNetworkId;
            key = DUMMY_NETWORK.subnetwork(dummyNetworkId);
        } else if (depth == 2) {
            ++dummyOperatorId;
            address dummyOperator = address(uint160(DUMMY_OPERATOR_BASE) + dummyOperatorId);
            key = _operatorKey(dummyOperator);
        }
        delegator.createSlot(key, parentIndex, isShared, false, uint128(size));
    }

    function _createNetworkSlot(uint96 parentIndex, bytes32 subnetwork, uint256 size) internal {
        delegator.createSlot(subnetwork, parentIndex, false, false, uint128(size));
    }

    function _createOperatorSlot(uint96 parentIndex, address operator, uint256 size) internal {
        delegator.createSlot(_operatorKey(operator), parentIndex, false, false, uint128(size));
    }

    function _operatorKey(address operator) internal pure returns (bytes32) {
        return bytes32(bytes20(operator));
    }

    function _rootIndex(uint32 localIndex) internal pure returns (uint96) {
        return uint96(0).createIndex(localIndex);
    }

    function _registerOperator(address operator) internal {
        vm.startPrank(operator);
        operatorRegistry.registerOperator();
        vm.stopPrank();
    }

    function _registerNetwork(address network, address middleware) internal {
        vm.startPrank(network);
        networkRegistry.registerNetwork();
        networkMiddlewareService.setMiddleware(middleware);
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

    function _withdraw(address user, uint256 amount) internal {
        vm.startPrank(user);
        vault.withdraw(user, amount);
        vm.stopPrank();
    }

    function _setUnlimited(address network) internal {
        vm.prank(network);
        delegator.setMaxNetworkLimit(0, type(uint256).max);
    }
}
