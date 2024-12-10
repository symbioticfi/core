// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {VaultFactory} from "../../src/contracts/VaultFactory.sol";
import {DelegatorFactory} from "../../src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "../../src/contracts/SlasherFactory.sol";
import {NetworkRegistry} from "../../src/contracts/NetworkRegistry.sol";
import {OperatorRegistry} from "../../src/contracts/OperatorRegistry.sol";
import {MetadataService} from "../../src/contracts/service/MetadataService.sol";
import {NetworkMiddlewareService} from "../../src/contracts/service/NetworkMiddlewareService.sol";
import {OptInService} from "../../src/contracts/service/OptInService.sol";

import {Vault} from "../../src/contracts/vault/Vault.sol";
import {NetworkRestakeDelegator} from "../../src/contracts/delegator/NetworkRestakeDelegator.sol";
import {FullRestakeDelegator} from "../../src/contracts/delegator/FullRestakeDelegator.sol";
import {OperatorSpecificDelegator} from "../../src/contracts/delegator/OperatorSpecificDelegator.sol";
import {OperatorNetworkSpecificDelegator} from "../../src/contracts/delegator/OperatorNetworkSpecificDelegator.sol";
import {Slasher} from "../../src/contracts/slasher/Slasher.sol";
import {VetoSlasher} from "../../src/contracts/slasher/VetoSlasher.sol";

import {IVault} from "../../src/interfaces/vault/IVault.sol";

import {Token} from "../mocks/Token.sol";
import {VaultConfigurator} from "../../src/contracts/VaultConfigurator.sol";
import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";
import {INetworkRestakeDelegator} from "../../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IFullRestakeDelegator} from "../../src/interfaces/delegator/IFullRestakeDelegator.sol";
import {IBaseDelegator} from "../../src/interfaces/delegator/IBaseDelegator.sol";
import {IMigratableEntityProxy} from "../../src/interfaces/common/IMigratableEntityProxy.sol";
import {IMigratableEntity} from "../../src/interfaces/common/IMigratableEntity.sol";
import {ISlasher} from "../../src/interfaces/slasher/ISlasher.sol";

import {IVaultStorage} from "../../src/interfaces/vault/IVaultStorage.sol";
import {IVetoSlasher} from "../../src/interfaces/slasher/IVetoSlasher.sol";
import {IBaseSlasher} from "../../src/interfaces/slasher/IBaseSlasher.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {BaseSlasherHints, VetoSlasherHints} from "../../src/contracts/hints/SlasherHints.sol";
import {BaseDelegatorHints} from "../../src/contracts/hints/DelegatorHints.sol";
import {OptInServiceHints} from "../../src/contracts/hints/OptInServiceHints.sol";
import {VaultHints} from "../../src/contracts/hints/VaultHints.sol";
import {Subnetwork} from "../../src/contracts/libraries/Subnetwork.sol";

contract VetoSlasherTest is Test {
    using Math for uint256;
    using Subnetwork for bytes32;
    using Subnetwork for address;

    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    VaultFactory vaultFactory;
    DelegatorFactory delegatorFactory;
    SlasherFactory slasherFactory;
    NetworkRegistry networkRegistry;
    OperatorRegistry operatorRegistry;
    MetadataService operatorMetadataService;
    MetadataService networkMetadataService;
    NetworkMiddlewareService networkMiddlewareService;
    OptInService operatorVaultOptInService;
    OptInService operatorNetworkOptInService;

    Token collateral;
    VaultConfigurator vaultConfigurator;

    Vault vault;
    FullRestakeDelegator delegator;
    VetoSlasher slasher;

    OptInServiceHints optInServiceHints;
    BaseDelegatorHints baseDelegatorHints;
    BaseSlasherHints baseSlasherHints;
    VetoSlasherHints vetoSlasherHints;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        vaultFactory = new VaultFactory(owner);
        delegatorFactory = new DelegatorFactory(owner);
        slasherFactory = new SlasherFactory(owner);
        networkRegistry = new NetworkRegistry();
        operatorRegistry = new OperatorRegistry();
        operatorMetadataService = new MetadataService(address(operatorRegistry));
        networkMetadataService = new MetadataService(address(networkRegistry));
        networkMiddlewareService = new NetworkMiddlewareService(address(networkRegistry));
        operatorVaultOptInService =
            new OptInService(address(operatorRegistry), address(vaultFactory), "OperatorVaultOptInService");
        operatorNetworkOptInService =
            new OptInService(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService");

        address vaultImpl =
            address(new Vault(address(delegatorFactory), address(slasherFactory), address(vaultFactory)));
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

        collateral = new Token("Token");

        vaultConfigurator =
            new VaultConfigurator(address(vaultFactory), address(delegatorFactory), address(slasherFactory));
    }

    function test_Create(uint48 epochDuration, uint48 vetoDuration) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        vm.assume(vetoDuration < epochDuration);

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        slasher = _getSlasher(address(vault), vetoDuration);

        assertEq(slasher.VAULT_FACTORY(), address(vaultFactory));
        assertEq(slasher.NETWORK_MIDDLEWARE_SERVICE(), address(networkMiddlewareService));
        assertEq(slasher.vault(), address(vault));
        assertEq(slasher.NETWORK_REGISTRY(), address(networkRegistry));
        assertEq(slasher.vetoDuration(), vetoDuration);
        assertEq(slasher.slashRequestsLength(), 0);
        vm.expectRevert();
        slasher.slashRequests(0);
        assertEq(slasher.resolverSetEpochsDelay(), 3);
        assertEq(slasher.resolverAt(bytes32(0), 0, ""), address(0));
        assertEq(slasher.resolver(bytes32(0), ""), address(0));
    }

    function test_CreateRevertNotVault(
        uint48 epochDuration,
        uint48 vetoDuration,
        uint256 resolverSetEpochsDelay
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        resolverSetEpochsDelay = bound(resolverSetEpochsDelay, 3, type(uint256).max);
        vm.assume(vetoDuration < epochDuration);

        (vault,) = _getVaultAndDelegator(epochDuration);

        vm.expectRevert(IBaseSlasher.NotVault.selector);
        slasherFactory.create(
            1,
            abi.encode(
                address(1),
                abi.encode(
                    IVetoSlasher.InitParams({
                        baseParams: IBaseSlasher.BaseParams({isBurnerHook: false}),
                        vetoDuration: vetoDuration,
                        resolverSetEpochsDelay: resolverSetEpochsDelay
                    })
                )
            )
        );
    }

    function test_CreateRevertInvalidVetoDuration(
        uint48 epochDuration,
        uint48 vetoDuration,
        uint256 resolverSetEpochsDelay
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        resolverSetEpochsDelay = bound(resolverSetEpochsDelay, 3, type(uint256).max);
        vm.assume(vetoDuration >= epochDuration);

        (vault,) = _getVaultAndDelegator(epochDuration);

        vm.expectRevert(IVetoSlasher.InvalidVetoDuration.selector);
        slasherFactory.create(
            1,
            abi.encode(
                address(vault),
                abi.encode(
                    IVetoSlasher.InitParams({
                        baseParams: IBaseSlasher.BaseParams({isBurnerHook: false}),
                        vetoDuration: vetoDuration,
                        resolverSetEpochsDelay: resolverSetEpochsDelay
                    })
                )
            )
        );
    }

    function test_CreateRevertInvalidResolverSetEpochsDelay(
        uint48 epochDuration,
        uint48 vetoDuration,
        uint256 resolverSetEpochsDelay
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        resolverSetEpochsDelay = bound(resolverSetEpochsDelay, 0, 2);
        vm.assume(vetoDuration < epochDuration);

        (vault,) = _getVaultAndDelegator(epochDuration);

        vm.expectRevert(IVetoSlasher.InvalidResolverSetEpochsDelay.selector);
        slasherFactory.create(
            1,
            abi.encode(
                address(vault),
                abi.encode(
                    IVetoSlasher.InitParams({
                        baseParams: IBaseSlasher.BaseParams({isBurnerHook: false}),
                        vetoDuration: vetoDuration,
                        resolverSetEpochsDelay: resolverSetEpochsDelay
                    })
                )
            )
        );
    }

    function test_RequestSlash(
        // uint48 epochDuration,
        uint48 vetoDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 operatorNetworkLimit2,
        uint256 slashAmount1,
        uint256 slashAmount2
    ) public {
        // epochDuration = uint48(bound(epochDuration, 1, 10 days));
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        operatorNetworkLimit2 = bound(operatorNetworkLimit2, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);
        slashAmount2 = bound(slashAmount2, 1, type(uint256).max);
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        vm.assume(vetoDuration < 7 days);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(7 days, vetoDuration);

        // address network = alice;
        _registerNetwork(alice, alice);
        _setMaxNetworkLimit(alice, 0, type(uint256).max);

        _registerOperator(alice);
        _registerOperator(bob);

        _optInOperatorVault(alice);
        _optInOperatorVault(bob);

        _optInOperatorNetwork(alice, address(alice));
        _optInOperatorNetwork(bob, address(alice));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, alice, networkLimit);

        _setOperatorNetworkLimit(alice, alice, alice, operatorNetworkLimit1);
        _setOperatorNetworkLimit(alice, alice, bob, operatorNetworkLimit2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(0, _requestSlash(alice, alice, alice, slashAmount1, uint48(blockTimestamp - 1), ""));

        (
            // bytes32 subnetwork_,
            ,
            // address operator_,
            ,
            uint256 amount_,
            uint48 captureTimestamp_,
            uint48 vetoDeadline_,
            // bool completed_
        ) = slasher.slashRequests(0);

        // assertEq(subnetwork_, alice.subnetwork(0));
        // assertEq(operator_, alice);
        assertEq(
            amount_, Math.min(slashAmount1, Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1)))
        );
        assertEq(captureTimestamp_, uint48(blockTimestamp - 1));
        assertEq(vetoDeadline_, uint48(blockTimestamp + slasher.vetoDuration()));
        // assertEq(completed_, false);

        assertEq(1, _requestSlash(alice, alice, bob, slashAmount2, uint48(blockTimestamp - 1), ""));

        (
            // subnetwork_,
            ,
            // operator_,
            ,
            amount_,
            captureTimestamp_,
            vetoDeadline_,
            // completed_
        ) = slasher.slashRequests(1);

        // assertEq(subnetwork_, alice.subnetwork(0));
        // assertEq(operator_, bob);
        assertEq(
            amount_, Math.min(slashAmount2, Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit2)))
        );
        assertEq(captureTimestamp_, uint48(blockTimestamp - 1));
        assertEq(vetoDeadline_, uint48(blockTimestamp + slasher.vetoDuration()));
        // assertEq(completed_, false);
    }

    function test_RequestSlashRevertNotNetworkMiddleware(
        // uint48 epochDuration,
        uint48 vetoDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 operatorNetworkLimit2,
        uint256 slashAmount1,
        uint256 slashAmount2
    ) public {
        // epochDuration = uint48(bound(epochDuration, 1, 10 days));
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        operatorNetworkLimit2 = bound(operatorNetworkLimit2, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);
        slashAmount2 = bound(slashAmount2, 1, type(uint256).max);
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        vm.assume(vetoDuration < 7 days);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(7 days, vetoDuration);

        // address network = alice;
        _registerNetwork(alice, alice);
        _setMaxNetworkLimit(alice, 0, type(uint256).max);

        _registerOperator(alice);
        _registerOperator(bob);

        _optInOperatorVault(alice);
        _optInOperatorVault(bob);

        _optInOperatorNetwork(alice, address(alice));
        _optInOperatorNetwork(bob, address(alice));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, alice, networkLimit);

        _setOperatorNetworkLimit(alice, alice, alice, operatorNetworkLimit1);
        _setOperatorNetworkLimit(alice, alice, bob, operatorNetworkLimit2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.expectRevert(IBaseSlasher.NotNetworkMiddleware.selector);
        _requestSlash(bob, alice, alice, slashAmount1, uint48(blockTimestamp - 1), "");
    }

    function test_RequestSlashRevertInsufficientSlash(
        uint48 epochDuration,
        uint48 vetoDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 operatorNetworkLimit2,
        uint256 slashAmount1,
        uint256 slashAmount2
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        operatorNetworkLimit2 = bound(operatorNetworkLimit2, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);
        slashAmount2 = bound(slashAmount2, 1, type(uint256).max);
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        vm.assume(vetoDuration < epochDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, vetoDuration);

        address network = alice;
        _registerNetwork(network, alice);
        _setMaxNetworkLimit(network, 0, type(uint256).max);

        _registerOperator(alice);
        _registerOperator(bob);

        _optInOperatorVault(alice);
        _optInOperatorVault(bob);

        _optInOperatorNetwork(alice, address(network));
        _optInOperatorNetwork(bob, address(network));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, network, networkLimit);
        _setNetworkLimit(alice, network, networkLimit - 1);

        _setOperatorNetworkLimit(alice, network, alice, operatorNetworkLimit1);
        _setOperatorNetworkLimit(alice, network, bob, operatorNetworkLimit2);

        _setOperatorNetworkLimit(alice, network, alice, operatorNetworkLimit1 - 1);
        _setOperatorNetworkLimit(alice, network, bob, operatorNetworkLimit2 - 1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.expectRevert(IVetoSlasher.InsufficientSlash.selector);
        _requestSlash(alice, network, alice, 0, uint48(blockTimestamp - 1), "");
    }

    function test_RequestSlashRevertInvalidCaptureTimestamp(
        uint48 epochDuration,
        uint48 vetoDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 slashAmount1,
        uint256 captureAgo
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        vm.assume(vetoDuration < epochDuration);
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, vetoDuration);

        address network = alice;
        _registerNetwork(network, alice);
        _setMaxNetworkLimit(network, 0, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(network));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, network, networkLimit);

        _setOperatorNetworkLimit(alice, network, alice, operatorNetworkLimit1);

        blockTimestamp = blockTimestamp + 10 * epochDuration;
        vm.warp(blockTimestamp);

        vm.assume(captureAgo <= 10 * epochDuration && (captureAgo > epochDuration - vetoDuration || captureAgo == 0));
        vm.expectRevert(IVetoSlasher.InvalidCaptureTimestamp.selector);
        _requestSlash(alice, network, alice, slashAmount1, uint48(blockTimestamp - captureAgo), "");
    }

    function test_SetResolver(uint48 epochDuration, uint48 vetoDuration, address resolver1, address resolver2) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        vm.assume(vetoDuration < epochDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, vetoDuration);

        vm.assume(resolver1 != address(0));
        vm.assume(resolver2 != address(0) && resolver2 != resolver1);

        address network = alice;
        _registerNetwork(network, alice);

        _setResolver(network, 0, resolver1, "");

        assertEq(
            slasher.resolverAt(network.subnetwork(0), uint48(blockTimestamp + 2 * vault.epochDuration()), ""), resolver1
        );
        assertEq(slasher.resolver(network.subnetwork(0), ""), resolver1);

        _setResolver(network, 0, resolver2, "");

        assertEq(
            slasher.resolverAt(network.subnetwork(0), uint48(blockTimestamp + 3 * vault.epochDuration()), ""), resolver2
        );
        assertEq(
            slasher.resolverAt(network.subnetwork(0), uint48(blockTimestamp + 2 * vault.epochDuration()), ""), resolver1
        );
        assertEq(slasher.resolver(network.subnetwork(0), ""), resolver1);

        blockTimestamp = blockTimestamp + vault.epochDuration();
        vm.warp(blockTimestamp);

        assertEq(
            slasher.resolverAt(network.subnetwork(0), uint48(blockTimestamp + 2 * vault.epochDuration()), ""), resolver2
        );
        assertEq(slasher.resolver(network.subnetwork(0), ""), resolver1);

        _setResolver(network, 0, address(0), "");

        assertEq(
            slasher.resolverAt(network.subnetwork(0), uint48(blockTimestamp + 2 * vault.epochDuration()), ""), resolver1
        );
        assertEq(slasher.resolver(network.subnetwork(0), ""), resolver1);
        assertEq(
            slasher.resolverAt(network.subnetwork(0), uint48(blockTimestamp + 3 * vault.epochDuration()), ""),
            address(0)
        );

        blockTimestamp = blockTimestamp + 3 * vault.epochDuration();
        vm.warp(blockTimestamp);

        assertEq(
            slasher.resolverAt(network.subnetwork(0), uint48(blockTimestamp + 3 * vault.epochDuration()), ""),
            address(0)
        );
        assertEq(slasher.resolver(network.subnetwork(0), ""), address(0));

        _setResolver(network, 0, resolver1, "");

        assertEq(
            slasher.resolverAt(network.subnetwork(0), uint48(blockTimestamp + 2 * vault.epochDuration()), ""),
            address(0)
        );
        assertEq(
            slasher.resolverAt(network.subnetwork(0), uint48(blockTimestamp + 3 * vault.epochDuration()), ""), resolver1
        );
        assertEq(slasher.resolver(network.subnetwork(0), ""), address(0));
    }

    function test_SetResolverRevertAlreadySet1(uint48 epochDuration, uint48 vetoDuration) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        vm.assume(vetoDuration < epochDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, vetoDuration);

        address network = alice;
        _registerNetwork(network, alice);

        vm.expectRevert(IVetoSlasher.AlreadySet.selector);
        _setResolver(network, 0, address(0), "");
    }

    function test_SetResolverRevertAlreadySet2(uint48 epochDuration, uint48 vetoDuration) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        vm.assume(vetoDuration < epochDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, vetoDuration);

        address network = alice;
        _registerNetwork(network, alice);

        _setResolver(network, 0, address(1), "");

        vm.expectRevert(IVetoSlasher.AlreadySet.selector);
        _setResolver(network, 0, address(1), "");
    }

    function test_SetResolverRevertNotNetwork(uint48 epochDuration, uint48 vetoDuration) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        vm.assume(vetoDuration < epochDuration);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, vetoDuration);

        address network = alice;
        _registerNetwork(network, alice);

        vm.expectRevert(IVetoSlasher.NotNetwork.selector);
        _setResolver(bob, 0, alice, "");
    }

    function test_ExecuteSlash1(
        uint48 epochDuration,
        uint48 vetoDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 slashAmount1
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        vm.assume(vetoDuration < epochDuration);
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, vetoDuration);

        // address network = alice;
        _registerNetwork(alice, alice);
        _setMaxNetworkLimit(alice, 0, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(alice));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, alice, networkLimit);

        _setOperatorNetworkLimit(alice, alice, alice, operatorNetworkLimit1);

        _setResolver(alice, 0, alice, "");

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 slashAmountReal1 =
            Math.min(slashAmount1, Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1)));

        _requestSlash(alice, alice, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        (
            bytes32 subnetwork_,
            address operator_,
            uint256 amount_,
            uint48 captureTimestamp_,
            // uint48 vetoDeadline_,
            ,
            bool completed_
        ) = slasher.slashRequests(0);

        assertEq(subnetwork_, alice.subnetwork(0));
        assertEq(operator_, alice);
        assertEq(amount_, slashAmountReal1);
        assertEq(captureTimestamp_, uint48(blockTimestamp - 1));
        // assertEq(vetoDeadline_, uint48(blockTimestamp + slasher.vetoDuration()));
        assertEq(completed_, false);

        blockTimestamp = blockTimestamp + epochDuration - 1;
        vm.warp(blockTimestamp);

        assertTrue(blockTimestamp - uint48(blockTimestamp - 1) <= epochDuration);

        assertEq(slasher.latestSlashedCaptureTimestamp(alice.subnetwork(0), alice), 0);

        assertEq(_executeSlash(alice, 0, ""), slashAmountReal1);

        assertEq(vault.totalStake(), depositAmount - Math.min(slashAmountReal1, depositAmount));

        (
            subnetwork_,
            operator_,
            amount_,
            captureTimestamp_,
            //  vetoDeadline_,
            ,
            completed_
        ) = slasher.slashRequests(0);

        assertEq(slasher.latestSlashedCaptureTimestamp(alice.subnetwork(0), alice), captureTimestamp_);

        assertEq(subnetwork_, alice.subnetwork(0));
        assertEq(operator_, alice);
        assertEq(amount_, slashAmountReal1);
        assertEq(captureTimestamp_, uint48(blockTimestamp - epochDuration));
        // assertEq(vetoDeadline_, uint48(blockTimestamp - (epochDuration - 1) + vetoDuration));
        assertEq(completed_, true);

        assertEq(slasher.cumulativeSlashAt(alice.subnetwork(0), alice, uint48(blockTimestamp - 1), ""), 0);
        assertEq(slasher.cumulativeSlashAt(alice.subnetwork(0), alice, uint48(blockTimestamp), ""), slashAmountReal1);
        assertEq(slasher.cumulativeSlash(alice.subnetwork(0), alice), slashAmountReal1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        depositAmount -= slashAmountReal1;
        uint256 slashAmountReal2 =
            Math.min(slashAmount1, Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1)));

        vm.assume(slashAmountReal2 != 0);

        _requestSlash(alice, alice, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        (
            subnetwork_,
            operator_,
            amount_,
            captureTimestamp_,
            // uint48 vetoDeadline_,
            ,
            completed_
        ) = slasher.slashRequests(1);

        assertEq(subnetwork_, alice.subnetwork(0));
        assertEq(operator_, alice);
        assertEq(amount_, slashAmountReal2);
        assertEq(captureTimestamp_, uint48(blockTimestamp - 1));
        // assertEq(vetoDeadline_, uint48(blockTimestamp + slasher.vetoDuration()));
        assertEq(completed_, false);

        blockTimestamp = blockTimestamp + epochDuration - 1;
        vm.warp(blockTimestamp);

        assertTrue(blockTimestamp - uint48(blockTimestamp - 1) <= epochDuration);

        assertEq(_executeSlash(alice, 1, ""), slashAmountReal2);

        assertEq(vault.totalStake(), depositAmount - Math.min(slashAmountReal2, depositAmount));

        (
            subnetwork_,
            operator_,
            amount_,
            captureTimestamp_,
            //  vetoDeadline_,
            ,
            completed_
        ) = slasher.slashRequests(1);

        assertEq(slasher.latestSlashedCaptureTimestamp(alice.subnetwork(0), alice), captureTimestamp_);

        assertEq(subnetwork_, alice.subnetwork(0));
        assertEq(operator_, alice);
        assertEq(amount_, slashAmountReal2);
        assertEq(captureTimestamp_, uint48(blockTimestamp - epochDuration));
        // assertEq(vetoDeadline_, uint48(blockTimestamp - (epochDuration - 1) + vetoDuration));
        assertEq(completed_, true);

        assertEq(
            slasher.cumulativeSlashAt(alice.subnetwork(0), alice, uint48(blockTimestamp - 1), ""), slashAmountReal1
        );
        assertEq(
            slasher.cumulativeSlashAt(alice.subnetwork(0), alice, uint48(blockTimestamp), ""),
            slashAmountReal1 + slashAmountReal2
        );
        assertEq(slasher.cumulativeSlash(alice.subnetwork(0), alice), slashAmountReal1 + slashAmountReal2);
    }

    function test_ExecuteSlash2(
        uint48 epochDuration,
        uint48 vetoDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 slashAmount1
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        vm.assume(vetoDuration < epochDuration);
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, vetoDuration);

        // address network = alice;
        _registerNetwork(alice, alice);
        _setMaxNetworkLimit(alice, 0, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(alice));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, alice, networkLimit);

        _setOperatorNetworkLimit(alice, alice, alice, operatorNetworkLimit1);

        _setResolver(alice, 0, alice, "");

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 slashAmountReal1 =
            Math.min(slashAmount1, Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1)));

        vm.assume(slashAmountReal1 < Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1)));

        _requestSlash(alice, alice, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        (
            bytes32 subnetwork_,
            address operator_,
            uint256 amount_,
            uint48 captureTimestamp_,
            // uint48 vetoDeadline_,
            ,
            bool completed_
        ) = slasher.slashRequests(0);

        assertEq(subnetwork_, alice.subnetwork(0));
        assertEq(operator_, alice);
        assertEq(amount_, slashAmountReal1);
        assertEq(captureTimestamp_, uint48(blockTimestamp - 1));
        // assertEq(vetoDeadline_, uint48(blockTimestamp + slasher.vetoDuration()));
        assertEq(completed_, false);

        _requestSlash(alice, alice, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        (
            subnetwork_,
            operator_,
            amount_,
            captureTimestamp_,
            // uint48 vetoDeadline_,
            ,
            completed_
        ) = slasher.slashRequests(1);

        assertEq(subnetwork_, alice.subnetwork(0));
        assertEq(operator_, alice);
        assertEq(amount_, slashAmountReal1);
        assertEq(captureTimestamp_, uint48(blockTimestamp - 1));
        // assertEq(vetoDeadline_, uint48(blockTimestamp + slasher.vetoDuration()));
        assertEq(completed_, false);

        blockTimestamp = blockTimestamp + epochDuration - 1;
        vm.warp(blockTimestamp);

        assertTrue(blockTimestamp - uint48(blockTimestamp - 1) <= epochDuration);

        assertEq(slasher.latestSlashedCaptureTimestamp(alice.subnetwork(0), alice), 0);

        assertEq(_executeSlash(alice, 0, ""), slashAmountReal1);

        assertEq(vault.totalStake(), depositAmount - Math.min(slashAmountReal1, depositAmount));

        (
            subnetwork_,
            operator_,
            amount_,
            captureTimestamp_,
            //  vetoDeadline_,
            ,
            completed_
        ) = slasher.slashRequests(0);

        assertEq(slasher.latestSlashedCaptureTimestamp(alice.subnetwork(0), alice), captureTimestamp_);

        assertEq(subnetwork_, alice.subnetwork(0));
        assertEq(operator_, alice);
        assertEq(amount_, slashAmountReal1);
        assertEq(captureTimestamp_, uint48(blockTimestamp - epochDuration));
        // assertEq(vetoDeadline_, uint48(blockTimestamp - (epochDuration - 1) + vetoDuration));
        assertEq(completed_, true);

        assertEq(slasher.cumulativeSlashAt(alice.subnetwork(0), alice, uint48(blockTimestamp - 1), ""), 0);
        assertEq(slasher.cumulativeSlashAt(alice.subnetwork(0), alice, uint48(blockTimestamp), ""), slashAmountReal1);
        assertEq(slasher.cumulativeSlash(alice.subnetwork(0), alice), slashAmountReal1);

        uint256 slashAmountReal2 = Math.min(
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1)) - slashAmountReal1, slashAmountReal1
        );

        depositAmount -= slashAmountReal1;

        assertEq(_executeSlash(alice, 1, ""), slashAmountReal2);

        assertEq(vault.totalStake(), depositAmount - Math.min(slashAmountReal2, depositAmount));

        (
            subnetwork_,
            operator_,
            amount_,
            captureTimestamp_,
            //  vetoDeadline_,
            ,
            completed_
        ) = slasher.slashRequests(1);

        assertEq(slasher.latestSlashedCaptureTimestamp(alice.subnetwork(0), alice), captureTimestamp_);

        assertEq(subnetwork_, alice.subnetwork(0));
        assertEq(operator_, alice);
        assertEq(amount_, slashAmountReal1);
        assertEq(captureTimestamp_, uint48(blockTimestamp - epochDuration));
        // assertEq(vetoDeadline_, uint48(blockTimestamp - (epochDuration - 1) + vetoDuration));
        assertEq(completed_, true);

        assertEq(slasher.cumulativeSlashAt(alice.subnetwork(0), alice, uint48(blockTimestamp - 1), ""), 0);
        assertEq(
            slasher.cumulativeSlashAt(alice.subnetwork(0), alice, uint48(blockTimestamp), ""),
            slashAmountReal1 + slashAmountReal2
        );
        assertEq(slasher.cumulativeSlash(alice.subnetwork(0), alice), slashAmountReal1 + slashAmountReal2);
    }

    function test_ExecuteSlashWithoutResolver1(
        uint48 epochDuration,
        uint48 vetoDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 slashAmount1
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        vm.assume(vetoDuration < epochDuration);
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, vetoDuration);

        // address network = alice;
        _registerNetwork(alice, alice);
        _setMaxNetworkLimit(alice, 0, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(alice));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, alice, networkLimit);

        _setOperatorNetworkLimit(alice, alice, alice, operatorNetworkLimit1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 slashAmountReal1 =
            Math.min(slashAmount1, Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1)));

        _requestSlash(alice, alice, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        (
            bytes32 subnetwork_,
            address operator_,
            uint256 amount_,
            uint48 captureTimestamp_,
            // uint48 vetoDeadline_,
            ,
            bool completed_
        ) = slasher.slashRequests(0);

        assertEq(subnetwork_, alice.subnetwork(0));
        assertEq(operator_, alice);
        assertEq(amount_, slashAmountReal1);
        assertEq(captureTimestamp_, uint48(blockTimestamp - 1));
        // assertEq(vetoDeadline_, uint48(blockTimestamp + slasher.vetoDuration()));
        assertEq(completed_, false);

        assertEq(_executeSlash(alice, 0, ""), slashAmountReal1);

        assertEq(vault.totalStake(), depositAmount - Math.min(slashAmountReal1, depositAmount));

        (
            subnetwork_,
            operator_,
            amount_,
            captureTimestamp_,
            //  vetoDeadline_,
            ,
            completed_
        ) = slasher.slashRequests(0);

        assertEq(subnetwork_, alice.subnetwork(0));
        assertEq(operator_, alice);
        assertEq(amount_, slashAmountReal1);
        assertEq(captureTimestamp_, uint48(blockTimestamp - 1));
        // assertEq(vetoDeadline_, uint48(blockTimestamp + vetoDuration));
        assertEq(completed_, true);

        assertEq(slasher.cumulativeSlashAt(alice.subnetwork(0), alice, uint48(blockTimestamp - 1), ""), 0);
        assertEq(slasher.cumulativeSlashAt(alice.subnetwork(0), alice, uint48(blockTimestamp), ""), slashAmountReal1);
        assertEq(slasher.cumulativeSlash(alice.subnetwork(0), alice), slashAmountReal1);
    }

    function test_ExecuteSlashWithoutResolver2(
        uint48 epochDuration,
        uint48 vetoDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 slashAmount1
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        vm.assume(vetoDuration < epochDuration);
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, vetoDuration);

        // address network = alice;
        _registerNetwork(alice, alice);
        _setMaxNetworkLimit(alice, 0, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(alice));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, alice, networkLimit);

        _setOperatorNetworkLimit(alice, alice, alice, operatorNetworkLimit1);

        _setResolver(alice, 0, alice, "");

        _setResolver(alice, 0, address(0), "");

        blockTimestamp = blockTimestamp + 3 * epochDuration + 1;
        vm.warp(blockTimestamp);

        uint256 slashAmountReal1 =
            Math.min(slashAmount1, Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1)));

        _requestSlash(alice, alice, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        (
            bytes32 subnetwork_,
            address operator_,
            uint256 amount_,
            uint48 captureTimestamp_,
            // uint48 vetoDeadline_,
            ,
            bool completed_
        ) = slasher.slashRequests(0);

        assertEq(subnetwork_, alice.subnetwork(0));
        assertEq(operator_, alice);
        assertEq(amount_, slashAmountReal1);
        assertEq(captureTimestamp_, uint48(blockTimestamp - 1));
        // assertEq(vetoDeadline_, uint48(blockTimestamp + slasher.vetoDuration()));
        assertEq(completed_, false);

        assertEq(_executeSlash(alice, 0, ""), slashAmountReal1);

        assertEq(vault.totalStake(), depositAmount - Math.min(slashAmountReal1, depositAmount));

        (
            subnetwork_,
            operator_,
            amount_,
            captureTimestamp_,
            //  vetoDeadline_,
            ,
            completed_
        ) = slasher.slashRequests(0);

        assertEq(subnetwork_, alice.subnetwork(0));
        assertEq(operator_, alice);
        assertEq(amount_, slashAmountReal1);
        assertEq(captureTimestamp_, uint48(blockTimestamp - 1));
        // assertEq(vetoDeadline_, uint48(blockTimestamp + vetoDuration));
        assertEq(completed_, true);

        assertEq(slasher.cumulativeSlashAt(alice.subnetwork(0), alice, uint48(blockTimestamp - 1), ""), 0);
        assertEq(slasher.cumulativeSlashAt(alice.subnetwork(0), alice, uint48(blockTimestamp), ""), slashAmountReal1);
        assertEq(slasher.cumulativeSlash(alice.subnetwork(0), alice), slashAmountReal1);
    }

    function test_ExecuteSlashRevertNotNetworkMiddleware(
        uint48 epochDuration,
        uint48 vetoDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 slashAmount1
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        vm.assume(vetoDuration < epochDuration);
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, vetoDuration);

        address network = alice;
        _registerNetwork(network, alice);
        _setMaxNetworkLimit(network, 0, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(network));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, network, networkLimit);

        _setOperatorNetworkLimit(alice, network, alice, operatorNetworkLimit1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        slashAmount1 = Math.min(slashAmount1, Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1)));

        _requestSlash(alice, network, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        blockTimestamp = blockTimestamp + vetoDuration;
        vm.warp(blockTimestamp);

        vm.expectRevert(IBaseSlasher.NotNetworkMiddleware.selector);
        _executeSlash(bob, 0, "");
    }

    function test_ExecuteSlashRevertInsufficientSlash1(
        uint48 epochDuration,
        uint48 vetoDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 slashAmount1
    ) public {
        epochDuration = uint48(bound(epochDuration, 2, 10 days));
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        vm.assume(vetoDuration < epochDuration / 2 - 1);
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, vetoDuration);

        // address network = alice;
        _registerNetwork(alice, alice);
        _setMaxNetworkLimit(alice, 0, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(alice));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, alice, networkLimit);

        _setOperatorNetworkLimit(alice, alice, alice, operatorNetworkLimit1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _requestSlash(alice, alice, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        blockTimestamp = blockTimestamp + vetoDuration;
        vm.warp(blockTimestamp);

        _executeSlash(alice, 0, "");

        vm.expectRevert(IVetoSlasher.InsufficientSlash.selector);
        _requestSlash(alice, alice, alice, slashAmount1, uint48(blockTimestamp - vetoDuration - 2), "");
    }

    function test_ExecuteSlashRevertInsufficientSlash2(
        uint48 epochDuration,
        uint48 vetoDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 slashAmount1
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        vm.assume(vetoDuration < epochDuration - 1);
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, vetoDuration);

        // address network = alice;
        _registerNetwork(alice, alice);
        _setMaxNetworkLimit(alice, 0, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(alice));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, alice, networkLimit);

        _setOperatorNetworkLimit(alice, alice, alice, operatorNetworkLimit1);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        _requestSlash(alice, alice, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        _requestSlash(alice, alice, alice, slashAmount1, uint48(blockTimestamp - 2), "");

        blockTimestamp = blockTimestamp + epochDuration - 2;
        vm.warp(blockTimestamp);

        _executeSlash(alice, 0, "");

        vm.expectRevert(IVetoSlasher.InsufficientSlash.selector);
        _executeSlash(alice, 1, "");
    }

    function test_ExecuteSlashRevertSlashRequestNotExist(
        uint48 epochDuration,
        uint48 vetoDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 slashAmount1
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        vm.assume(vetoDuration < epochDuration);
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, vetoDuration);

        address network = alice;
        _registerNetwork(network, alice);
        _setMaxNetworkLimit(network, 0, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(network));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, network, networkLimit);

        _setOperatorNetworkLimit(alice, network, alice, operatorNetworkLimit1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        slashAmount1 = Math.min(slashAmount1, Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1)));

        _requestSlash(alice, network, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        blockTimestamp = blockTimestamp + vetoDuration;
        vm.warp(blockTimestamp);

        vm.expectRevert(IVetoSlasher.SlashRequestNotExist.selector);
        _executeSlash(alice, 1, "");
    }

    function test_ExecuteSlashRevertVetoPeriodNotEnded(
        uint48 epochDuration,
        uint48 vetoDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 slashAmount1
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        vetoDuration = uint48(bound(vetoDuration, 1, type(uint48).max / 2));
        vm.assume(vetoDuration < epochDuration);
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, vetoDuration);

        address network = alice;
        _registerNetwork(network, alice);
        _setMaxNetworkLimit(network, 0, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(network));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, network, networkLimit);

        _setOperatorNetworkLimit(alice, network, alice, operatorNetworkLimit1);

        _setResolver(network, 0, alice, "");

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        slashAmount1 = Math.min(slashAmount1, Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1)));

        _requestSlash(alice, network, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        vm.expectRevert(IVetoSlasher.VetoPeriodNotEnded.selector);
        _executeSlash(alice, 0, "");
    }

    function test_ExecuteSlashRevertSlashPeriodEnded(
        uint48 epochDuration,
        uint48 vetoDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 slashAmount1
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        vm.assume(vetoDuration < epochDuration);
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, vetoDuration);

        address network = alice;
        _registerNetwork(network, alice);
        _setMaxNetworkLimit(network, 0, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(network));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, network, networkLimit);

        _setOperatorNetworkLimit(alice, network, alice, operatorNetworkLimit1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        slashAmount1 = Math.min(slashAmount1, Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1)));

        _requestSlash(alice, network, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        blockTimestamp = blockTimestamp + epochDuration + 1;
        vm.warp(blockTimestamp);

        vm.expectRevert(IVetoSlasher.SlashPeriodEnded.selector);
        _executeSlash(alice, 0, "");
    }

    function test_ExecuteSlashRevertSlashRequestCompleted(
        uint48 epochDuration,
        uint48 vetoDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 slashAmount1
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        vm.assume(vetoDuration < epochDuration);
        depositAmount = bound(depositAmount, 2, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 2, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 2, type(uint256).max / 2);
        slashAmount1 =
            bound(slashAmount1, 1, Math.min(Math.min(depositAmount, networkLimit), operatorNetworkLimit1) - 1);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, vetoDuration);

        address network = alice;
        _registerNetwork(network, alice);
        _setMaxNetworkLimit(network, 0, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(network));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, network, networkLimit);

        _setOperatorNetworkLimit(alice, network, alice, operatorNetworkLimit1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        slashAmount1 = Math.min(slashAmount1, Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1)));

        _requestSlash(alice, network, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        blockTimestamp = blockTimestamp + vetoDuration;
        vm.warp(blockTimestamp);

        _executeSlash(alice, 0, "");

        vm.expectRevert(IVetoSlasher.SlashRequestCompleted.selector);
        _executeSlash(alice, 0, "");
    }

    function test_VetoSlash(
        uint48 epochDuration,
        uint48 vetoDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 slashAmount1
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        vetoDuration = uint48(bound(vetoDuration, 1, type(uint48).max / 2));
        vm.assume(vetoDuration + 1 <= epochDuration);
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, vetoDuration);

        // address network = alice;
        _registerNetwork(alice, alice);
        _setMaxNetworkLimit(alice, 0, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(alice));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, alice, networkLimit);

        _setOperatorNetworkLimit(alice, alice, alice, operatorNetworkLimit1);

        _setResolver(alice, 0, alice, "");

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _setResolver(alice, 0, bob, "");

        slashAmount1 = Math.min(slashAmount1, Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1)));

        _requestSlash(alice, alice, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        _vetoSlash(alice, 0, "");

        (,,,,, bool completed_) = slasher.slashRequests(0);

        assertEq(completed_, true);
    }

    function test_VetoSlashRevertSlashRequestNotExist(
        uint48 epochDuration,
        uint48 vetoDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 slashAmount1
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        vetoDuration = uint48(bound(vetoDuration, 1, type(uint48).max / 2));
        vm.assume(vetoDuration + 1 <= epochDuration);
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, vetoDuration);

        // address network = alice;
        _registerNetwork(alice, alice);
        _setMaxNetworkLimit(alice, 0, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(alice));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, alice, networkLimit);

        _setOperatorNetworkLimit(alice, alice, alice, operatorNetworkLimit1);

        _setResolver(alice, 0, alice, "");

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        slashAmount1 = Math.min(slashAmount1, Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1)));

        _requestSlash(alice, alice, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        vm.expectRevert(IVetoSlasher.SlashRequestNotExist.selector);
        _vetoSlash(alice, 1, "");
    }

    function test_VetoSlashRevertVetoPeriodEnded(
        uint48 epochDuration,
        uint48 vetoDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 slashAmount1
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        vetoDuration = uint48(bound(vetoDuration, 1, type(uint48).max / 2));
        vm.assume(vetoDuration + 1 <= epochDuration);
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, vetoDuration);

        // address network = alice;
        _registerNetwork(alice, alice);
        _setMaxNetworkLimit(alice, 0, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(alice));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, alice, networkLimit);

        _setOperatorNetworkLimit(alice, alice, alice, operatorNetworkLimit1);

        _setResolver(alice, 0, alice, "");

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        slashAmount1 = Math.min(slashAmount1, Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1)));

        _requestSlash(alice, alice, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        blockTimestamp = blockTimestamp + vetoDuration;
        vm.warp(blockTimestamp);

        vm.expectRevert(IVetoSlasher.VetoPeriodEnded.selector);
        _vetoSlash(alice, 0, "");
    }

    function test_VetoSlashRevertNoResolver1(
        uint48 epochDuration,
        uint48 vetoDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 slashAmount1
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        vetoDuration = uint48(bound(vetoDuration, 1, type(uint48).max / 2));
        vm.assume(vetoDuration + 1 <= epochDuration);
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, vetoDuration);

        // address network = alice;
        _registerNetwork(alice, alice);
        _setMaxNetworkLimit(alice, 0, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(alice));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, alice, networkLimit);

        _setOperatorNetworkLimit(alice, alice, alice, operatorNetworkLimit1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        slashAmount1 = Math.min(slashAmount1, Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1)));

        _requestSlash(alice, alice, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        vm.expectRevert(IVetoSlasher.NoResolver.selector);
        _vetoSlash(alice, 0, "");
    }

    function test_VetoSlashRevertNoResolver2(
        uint48 epochDuration,
        uint48 vetoDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 slashAmount1
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        vetoDuration = uint48(bound(vetoDuration, 1, type(uint48).max / 2));
        vm.assume(vetoDuration + 1 <= epochDuration);
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, vetoDuration);

        // address network = alice;
        _registerNetwork(alice, alice);
        _setMaxNetworkLimit(alice, 0, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(alice));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, alice, networkLimit);

        _setOperatorNetworkLimit(alice, alice, alice, operatorNetworkLimit1);

        _setResolver(alice, 0, alice, "");

        _setResolver(alice, 0, address(0), "");

        blockTimestamp = blockTimestamp + 3 * epochDuration + 1;
        vm.warp(blockTimestamp);

        slashAmount1 = Math.min(slashAmount1, Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1)));

        _requestSlash(alice, alice, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        vm.expectRevert(IVetoSlasher.NoResolver.selector);
        _vetoSlash(alice, 0, "");
    }

    function test_VetoSlashRevertNotResolver(
        uint48 epochDuration,
        uint48 vetoDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 slashAmount1
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        vetoDuration = uint48(bound(vetoDuration, 1, type(uint48).max / 2));
        vm.assume(vetoDuration + 1 <= epochDuration);
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, vetoDuration);

        // address network = alice;
        _registerNetwork(alice, alice);
        _setMaxNetworkLimit(alice, 0, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(alice));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, alice, networkLimit);

        _setOperatorNetworkLimit(alice, alice, alice, operatorNetworkLimit1);

        _setResolver(alice, 0, alice, "");

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        slashAmount1 = Math.min(slashAmount1, Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1)));

        _requestSlash(alice, alice, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        vm.expectRevert(IVetoSlasher.NotResolver.selector);
        _vetoSlash(address(1), 0, "");
    }

    function test_VetoSlashRevertSlashRequestCompleted(
        uint48 epochDuration,
        uint48 vetoDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 slashAmount1
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        vetoDuration = uint48(bound(vetoDuration, 1, type(uint48).max / 2));
        vm.assume(vetoDuration + 1 <= epochDuration);
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, vetoDuration);

        // address network = alice;
        _registerNetwork(alice, alice);
        _setMaxNetworkLimit(alice, 0, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(alice));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, alice, networkLimit);

        _setOperatorNetworkLimit(alice, alice, alice, operatorNetworkLimit1);

        _setResolver(alice, 0, alice, "");

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        slashAmount1 = Math.min(slashAmount1, Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1)));

        _requestSlash(alice, alice, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        _vetoSlash(alice, 0, "");

        vm.expectRevert(IVetoSlasher.SlashRequestCompleted.selector);
        _vetoSlash(alice, 0, "");
    }

    // struct GasStruct {
    //     uint256 gasSpent1;
    //     uint256 gasSpent2;
    // }

    // struct HintStruct {
    //     uint256 num;
    //     bool back;
    //     uint256 secondsAgo;
    // }

    // function test_ResolverSharesHint(uint256 amount1, uint48 epochDuration, HintStruct memory hintStruct) public {
    //     epochDuration = uint48(bound(epochDuration, 1, 7 days));
    //     hintStruct.num = bound(hintStruct.num, 0, 25);
    //     hintStruct.secondsAgo = bound(hintStruct.secondsAgo, 0, 1_720_700_948);

    //     uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, 0);

    //     amount1 = bound(amount1, 0, slasher.SHARES_BASE());

    //     address network = alice;
    //     _registerNetwork(network, alice);

    //     _registerOperator(alice);

    //     for (uint256 i; i < hintStruct.num; ++i) {
    //         _setResolverShares(alice, alice, amount1, "");

    //         blockTimestamp = blockTimestamp + 3 * epochDuration;
    //         vm.warp(blockTimestamp);
    //     }

    //     uint48 timestamp =
    //         uint48(hintStruct.back ? blockTimestamp - hintStruct.secondsAgo : blockTimestamp + hintStruct.secondsAgo);

    //     optInServiceHints = new OptInServiceHints();
    //     baseDelegatorHints = new BaseDelegatorHints(address(optInServiceHints), address(new VaultHints()));
    //     baseSlasherHints = new BaseSlasherHints(address(baseDelegatorHints), address(optInServiceHints));
    //     vetoSlasherHints = VetoSlasherHints(baseSlasherHints.VETO_SLASHER_HINTS());

    //     GasStruct memory gasStruct = GasStruct({gasSpent1: 1, gasSpent2: 1});
    //     slasher.resolverSharesAt(network, alice, timestamp, "");
    //     gasStruct.gasSpent1 = vm.lastCallGas().gasTotalUsed;

    //     bytes memory hints = vetoSlasherHints.resolverSharesHint(address(slasher), network, alice, timestamp);
    //     slasher.resolverSharesAt(network, alice, timestamp, hints);
    //     gasStruct.gasSpent2 = vm.lastCallGas().gasTotalUsed;
    //     assertGe(gasStruct.gasSpent1, gasStruct.gasSpent2);
    // }

    // function test_ResolverSharesHintNow(uint256 amount1, uint48 epochDuration, HintStruct memory hintStruct) public {
    //     epochDuration = uint48(bound(epochDuration, 1, 7 days));
    //     hintStruct.num = bound(hintStruct.num, 0, 25);
    //     hintStruct.secondsAgo = bound(hintStruct.secondsAgo, 0, 1_720_700_948);

    //     uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, 0);

    //     amount1 = bound(amount1, 0, slasher.SHARES_BASE());

    //     address network = alice;
    //     _registerNetwork(network, alice);

    //     _registerOperator(alice);

    //     for (uint256 i; i < hintStruct.num; ++i) {
    //         _setResolverShares(alice, alice, amount1, "");

    //         blockTimestamp = blockTimestamp + 3 * epochDuration;
    //         vm.warp(blockTimestamp);
    //     }

    //     uint48 timestamp = uint48(blockTimestamp);

    //     optInServiceHints = new OptInServiceHints();
    //     VaultHints vaultHints = new VaultHints();
    //     baseDelegatorHints = new BaseDelegatorHints(address(optInServiceHints), address(vaultHints));
    //     baseSlasherHints = new BaseSlasherHints(address(baseDelegatorHints), address(optInServiceHints));
    //     vetoSlasherHints = VetoSlasherHints(baseSlasherHints.VETO_SLASHER_HINTS());
    //     bytes memory hints = vetoSlasherHints.resolverSharesHint(address(slasher), network, alice, timestamp);

    //     GasStruct memory gasStruct = GasStruct({gasSpent1: 1, gasSpent2: 1});
    //     slasher.resolverShares(network, alice, "");
    //     gasStruct.gasSpent1 = vm.lastCallGas().gasTotalUsed;
    //     slasher.resolverShares(network, alice, hints);
    //     gasStruct.gasSpent2 = vm.lastCallGas().gasTotalUsed;
    //     assertGe(gasStruct.gasSpent1, gasStruct.gasSpent2);
    // }

    // struct InputParams {
    //     uint256 depositAmount;
    //     uint256 networkLimit;
    //     uint256 operatorNetworkLimit;
    //     uint256 slashAmount;
    // }

    // function test_RequestSlashHints(
    //     uint256 amount1,
    //     uint48 epochDuration,
    //     HintStruct memory hintStruct,
    //     InputParams memory inputParams
    // ) public {
    //     amount1 = bound(amount1, 1, 10 * 10 ** 18);
    //     epochDuration = uint48(bound(epochDuration, 1, 7 days));
    //     hintStruct.num = bound(hintStruct.num, 0, 25);
    //     hintStruct.secondsAgo = bound(hintStruct.secondsAgo, 0, 2 * epochDuration);
    //     inputParams.slashAmount = bound(inputParams.slashAmount, 1, 1 * 10 ** 18);
    //     inputParams.depositAmount =
    //         bound(inputParams.depositAmount, Math.max(1, inputParams.slashAmount * hintStruct.num), 1000 * 10 ** 18);
    //     inputParams.networkLimit = bound(inputParams.networkLimit, inputParams.slashAmount, type(uint256).max);
    //     inputParams.operatorNetworkLimit =
    //         bound(inputParams.operatorNetworkLimit, inputParams.slashAmount, type(uint256).max);

    //     uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, 0);
    //     VetoSlasherHintsHelper vetoSlasherHintsHelper = new VetoSlasherHintsHelper();

    //     address network = alice;
    //     address middleware = address(vetoSlasherHintsHelper);
    //     _registerNetwork(network, middleware);
    //     _setMaxNetworkLimit(network, type(uint256).max);

    //     _registerOperator(alice);

    //     for (uint256 i; i < hintStruct.num / 2; ++i) {
    //         _optInOperatorVault(alice);
    //         if (hintStruct.num % 2 == 0) {
    //             _optInOperatorNetwork(alice, address(network));
    //         }
    //

    //         _deposit(alice, inputParams.depositAmount);
    //         _setNetworkLimit(alice, network, inputParams.networkLimit);
    //         _setOperatorNetworkLimit(alice, network, alice, inputParams.operatorNetworkLimit);

    //         blockTimestamp = blockTimestamp + 1;
    //         vm.warp(blockTimestamp);

    //         if (hintStruct.num % 2 == 0) {
    //             vm.startPrank(alice);
    //             try slasher.requestSlash(network, alice, inputParams.slashAmount, uint48(blockTimestamp - 1), "")
    //             returns (uint256 slashIndex) {
    //                 slasher.executeSlash(slashIndex, "");
    //             } catch {}
    //             vm.stopPrank();
    //         }

    //         _optOutOperatorVault(alice);
    //         if (hintStruct.num % 2 == 0) {
    //             _optOutOperatorNetwork(alice, address(network));
    //         }
    //
    //     }

    //     for (uint256 i; i < hintStruct.num / 2; ++i) {
    //         _optInOperatorVault(alice);
    //         if (hintStruct.num % 2 == 0) {
    //             _optInOperatorNetwork(alice, address(network));
    //         }
    //

    //         _deposit(alice, inputParams.depositAmount);
    //         _setNetworkLimit(alice, network, inputParams.networkLimit);
    //         _setOperatorNetworkLimit(alice, network, alice, inputParams.operatorNetworkLimit);

    //         blockTimestamp = blockTimestamp + 1;
    //         vm.warp(blockTimestamp);

    //         if (hintStruct.num % 2 == 0) {
    //             vm.startPrank(alice);
    //             try slasher.requestSlash(network, alice, inputParams.slashAmount, uint48(blockTimestamp - 1), "")
    //             returns (uint256 slashIndex) {
    //                 slasher.executeSlash(slashIndex, "");
    //             } catch {}
    //             vm.stopPrank();
    //         }

    //         _optOutOperatorVault(alice);
    //         if (hintStruct.num % 2 == 0) {
    //             _optOutOperatorNetwork(alice, address(network));
    //         }
    //

    //         blockTimestamp = blockTimestamp + 1;
    //         vm.warp(blockTimestamp);
    //     }

    //     uint48 timestamp =
    //         uint48(hintStruct.back ? blockTimestamp - hintStruct.secondsAgo : blockTimestamp + hintStruct.secondsAgo);

    //     optInServiceHints = new OptInServiceHints();
    //     VaultHints vaultHints = new VaultHints();
    //     baseDelegatorHints = new BaseDelegatorHints(address(optInServiceHints), address(vaultHints));
    //     baseSlasherHints = new BaseSlasherHints(address(baseDelegatorHints), address(optInServiceHints));
    //     vetoSlasherHints = VetoSlasherHints(baseSlasherHints.VETO_SLASHER_HINTS());

    //     GasStruct memory gasStruct = GasStruct({gasSpent1: 1, gasSpent2: 1});
    //     try vetoSlasherHintsHelper.tryRequestSlash(
    //         address(slasher), network, alice, inputParams.slashAmount, timestamp, ""
    //     ) {} catch (bytes memory data) {
    //         (bool reverted, uint256 gasSpent) = abi.decode(data, (bool, uint256));
    //         gasStruct.gasSpent1 = gasSpent;
    //     }

    //     bytes memory hints = vetoSlasherHints.requestSlashHints(
    //         address(slasher), middleware, network, alice, inputParams.slashAmount, timestamp
    //     );
    //     try vetoSlasherHintsHelper.tryRequestSlash(
    //         address(slasher), network, alice, inputParams.slashAmount, timestamp, hints
    //     ) {} catch (bytes memory data) {
    //         (bool reverted, uint256 gasSpent) = abi.decode(data, (bool, uint256));
    //         gasStruct.gasSpent2 = gasSpent;
    //     }
    //     assertGe(gasStruct.gasSpent1, gasStruct.gasSpent2);
    // }

    // function test_ExecuteSlashHints(
    //     uint256 amount1,
    //     uint48 epochDuration,
    //     HintStruct memory hintStruct,
    //     InputParams memory inputParams
    // ) public {
    //     amount1 = bound(amount1, 1, 10 * 10 ** 18);
    //     epochDuration = uint48(bound(epochDuration, 1, 7 days));
    //     hintStruct.num = bound(hintStruct.num, 1, 25);
    //     hintStruct.secondsAgo = bound(hintStruct.secondsAgo, 1, Math.min(hintStruct.num, epochDuration));
    //     inputParams.slashAmount = bound(inputParams.slashAmount, 1, 1 * 10 ** 18);
    //     inputParams.depositAmount = bound(
    //         inputParams.depositAmount, Math.max(1, inputParams.slashAmount * (hintStruct.num + 1)), 1000 * 10 ** 18
    //     );
    //     inputParams.networkLimit = bound(
    //         inputParams.networkLimit, Math.max(1, inputParams.slashAmount * (hintStruct.num + 1)), type(uint256).max
    //     );
    //     inputParams.operatorNetworkLimit = bound(
    //         inputParams.operatorNetworkLimit,
    //         Math.max(1, inputParams.slashAmount * (hintStruct.num + 1)),
    //         type(uint256).max
    //     );

    //     uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, 0);
    //     VetoSlasherHintsHelper vetoSlasherHintsHelper = new VetoSlasherHintsHelper();

    //     address network = alice;
    //     address middleware = alice;
    //     _registerNetwork(network, middleware);
    //     _setMaxNetworkLimit(network, type(uint256).max);

    //     _registerOperator(alice);

    //     for (uint256 i; i < hintStruct.num; ++i) {
    //         _optInOperatorVault(alice);
    //         _optInOperatorNetwork(alice, address(network));

    //         _deposit(alice, inputParams.depositAmount);
    //         _setNetworkLimit(alice, network, inputParams.networkLimit);
    //         _setOperatorNetworkLimit(alice, network, alice, inputParams.operatorNetworkLimit);

    //         blockTimestamp = blockTimestamp + 1;
    //         vm.warp(blockTimestamp);

    //         if (hintStruct.num % 2 == 0) {
    //             vm.startPrank(alice);
    //             try slasher.requestSlash(network, alice, inputParams.slashAmount, uint48(blockTimestamp - 1), "")
    //             returns (uint256 slashIndex) {
    //                 slasher.executeSlash(slashIndex, "");
    //             } catch {}
    //             vm.stopPrank();
    //         }

    //         _optOutOperatorVault(alice);
    //         _optOutOperatorNetwork(alice, address(network));
    //     }

    //     uint48 timestamp = uint48(blockTimestamp - hintStruct.secondsAgo);

    //     optInServiceHints = new OptInServiceHints();
    //     VaultHints vaultHints = new VaultHints();
    //     baseDelegatorHints = new BaseDelegatorHints(address(optInServiceHints), address(vaultHints));
    //     baseSlasherHints = new BaseSlasherHints(address(baseDelegatorHints), address(optInServiceHints));
    //     vetoSlasherHints = VetoSlasherHints(baseSlasherHints.VETO_SLASHER_HINTS());

    //     vm.startPrank(middleware);
    //     uint256 slashIndex = slasher.requestSlash(network, alice, inputParams.slashAmount, timestamp, "");
    //     vm.stopPrank();

    //     GasStruct memory gasStruct = GasStruct({gasSpent1: 1, gasSpent2: 1});
    //     try vetoSlasherHintsHelper.tryExecuteSlash(address(slasher), slashIndex, "") {}
    //     catch (bytes memory data) {
    //         (bool reverted, uint256 gasSpent) = abi.decode(data, (bool, uint256));
    //         gasStruct.gasSpent1 = gasSpent;
    //     }

    //     bytes memory hints = vetoSlasherHints.executeSlashHints(address(slasher), address(vetoSlasherHints), slashIndex);
    //     try vetoSlasherHintsHelper.tryExecuteSlash(address(slasher), slashIndex, hints) {}
    //     catch (bytes memory data) {
    //         (bool reverted, uint256 gasSpent) = abi.decode(data, (bool, uint256));
    //         gasStruct.gasSpent2 = gasSpent;
    //     }
    //     assertGe(gasStruct.gasSpent1, gasStruct.gasSpent2);
    // }

    // struct InputParamsVeto {
    //     uint256 depositAmount;
    //     uint256 networkLimit;
    //     uint256 operatorNetworkLimit;
    //     uint256 slashAmount;
    //     uint256 shares;
    // }

    // function test_VetoSlashHints(
    //     uint256 amount1,
    //     uint48 epochDuration,
    //     HintStruct memory hintStruct,
    //     InputParamsVeto memory inputParams
    // ) public {
    //     amount1 = bound(amount1, 1, 10 * 10 ** 18);
    //     epochDuration = uint48(bound(epochDuration, 2, 7 days));
    //     hintStruct.num = bound(hintStruct.num, 1, 25);
    //     hintStruct.secondsAgo = 1;
    //     inputParams.slashAmount = bound(inputParams.slashAmount, 1, 1 * 10 ** 18);
    //     inputParams.depositAmount = bound(
    //         inputParams.depositAmount, Math.max(1, inputParams.slashAmount * (hintStruct.num + 1)), 1000 * 10 ** 18
    //     );
    //     inputParams.networkLimit = bound(
    //         inputParams.networkLimit, Math.max(1, inputParams.slashAmount * (hintStruct.num + 1)), type(uint256).max
    //     );
    //     inputParams.operatorNetworkLimit = bound(
    //         inputParams.operatorNetworkLimit,
    //         Math.max(1, inputParams.slashAmount * (hintStruct.num + 1)),
    //         type(uint256).max
    //     );
    //     inputParams.shares = bound(inputParams.shares, hintStruct.num * 10, 10 ** 18);

    //     uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, epochDuration - 1);
    //     VetoSlasherHintsHelper vetoSlasherHintsHelper = new VetoSlasherHintsHelper();

    //     address network = alice;
    //     address middleware = alice;
    //     _registerNetwork(network, middleware);
    //     _setMaxNetworkLimit(network, type(uint256).max);

    //     _registerOperator(alice);

    //     for (uint256 i; i < hintStruct.num; ++i) {
    //         _optInOperatorVault(alice);
    //         _optInOperatorNetwork(alice, address(network));

    //         _deposit(alice, inputParams.depositAmount);
    //         _setNetworkLimit(alice, network, inputParams.networkLimit);
    //         _setOperatorNetworkLimit(alice, network, alice, inputParams.operatorNetworkLimit);
    //         _setResolverShares(alice, address(vetoSlasherHintsHelper), inputParams.shares - (hintStruct.num - i), "");

    //         blockTimestamp = blockTimestamp + 1;
    //         vm.warp(blockTimestamp);

    //         // if (hintStruct.num % 2 == 0) {
    //         //     vm.startPrank(alice);
    //         //     try slasher.requestSlash(network, alice, inputParams.slashAmount, uint48(blockTimestamp - 1), "")
    //         //     returns (uint256 slashIndex) {
    //         //         slasher.executeSlash(slashIndex, "");
    //         //     } catch {}
    //         //     vm.stopPrank();
    //         // }

    //         _optOutOperatorVault(alice);
    //         _optOutOperatorNetwork(alice, address(network));
    //     }

    //     uint48 timestamp = uint48(blockTimestamp - hintStruct.secondsAgo);

    //     optInServiceHints = new OptInServiceHints();
    //     VaultHints vaultHints = new VaultHints();
    //     baseDelegatorHints = new BaseDelegatorHints(address(optInServiceHints), address(vaultHints));
    //     baseSlasherHints = new BaseSlasherHints(address(baseDelegatorHints), address(optInServiceHints));
    //     vetoSlasherHints = VetoSlasherHints(baseSlasherHints.VETO_SLASHER_HINTS());

    //     vm.startPrank(middleware);
    //     uint256 slashIndex = slasher.requestSlash(network, alice, inputParams.slashAmount, timestamp, "");
    //     vm.stopPrank();

    //     GasStruct memory gasStruct = GasStruct({gasSpent1: 1, gasSpent2: 1});
    //     try vetoSlasherHintsHelper.tryVetoSlash(address(slasher), slashIndex, "") {}
    //     catch (bytes memory data) {
    //         (bool reverted, uint256 gasSpent) = abi.decode(data, (bool, uint256));
    //         gasStruct.gasSpent1 = gasSpent;
    //     }

    //     bytes memory hints =
    //         vetoSlasherHints.vetoSlashHints(address(slasher), address(vetoSlasherHintsHelper), slashIndex);
    //     try vetoSlasherHintsHelper.tryVetoSlash(address(slasher), slashIndex, hints) {}
    //     catch (bytes memory data) {
    //         (bool reverted, uint256 gasSpent) = abi.decode(data, (bool, uint256));
    //         gasStruct.gasSpent2 = gasSpent;
    //     }
    //     assertGe(gasStruct.gasSpent1, gasStruct.gasSpent2);
    // }

    // function test_SetResolverSharesHints(
    //     uint256 amount1,
    //     uint48 epochDuration,
    //     HintStruct memory hintStruct,
    //     InputParamsVeto memory inputParams
    // ) public {
    //     amount1 = bound(amount1, 1, 10 * 10 ** 18);
    //     epochDuration = uint48(bound(epochDuration, 1, 7 days));
    //     hintStruct.num = bound(hintStruct.num, 0, 25);
    //     hintStruct.secondsAgo = bound(hintStruct.secondsAgo, 0, 2 * epochDuration);
    //     inputParams.slashAmount = bound(inputParams.slashAmount, 1, 1 * 10 ** 18);
    //     inputParams.depositAmount =
    //         bound(inputParams.depositAmount, Math.max(1, inputParams.slashAmount * hintStruct.num), 1000 * 10 ** 18);
    //     inputParams.networkLimit = bound(inputParams.networkLimit, inputParams.slashAmount, type(uint256).max);
    //     inputParams.operatorNetworkLimit =
    //         bound(inputParams.operatorNetworkLimit, inputParams.slashAmount, type(uint256).max);
    //     inputParams.shares = bound(inputParams.shares, hintStruct.num * 10, 10 ** 18);

    //     uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration, 0);
    //     VetoSlasherHintsHelper vetoSlasherHintsHelper = new VetoSlasherHintsHelper();

    //     address network = address(vetoSlasherHintsHelper);
    //     _registerNetwork(network, alice);
    //     _setMaxNetworkLimit(network, type(uint256).max);

    //     _registerOperator(alice);

    //     for (uint256 i; i < hintStruct.num / 2; ++i) {
    //         _setResolverShares(network, alice, inputParams.shares - (hintStruct.num - i), "");

    //         blockTimestamp = blockTimestamp + 1;
    //         vm.warp(blockTimestamp);
    //     }

    //     optInServiceHints = new OptInServiceHints();
    //     VaultHints vaultHints = new VaultHints();
    //     baseDelegatorHints = new BaseDelegatorHints(address(optInServiceHints), address(vaultHints));
    //     baseSlasherHints = new BaseSlasherHints(address(baseDelegatorHints), address(optInServiceHints));
    //     vetoSlasherHints = VetoSlasherHints(baseSlasherHints.VETO_SLASHER_HINTS());

    //     GasStruct memory gasStruct = GasStruct({gasSpent1: 1, gasSpent2: 1});
    //     try vetoSlasherHintsHelper.trySetResolverShares(address(slasher), alice, inputParams.shares, "") {}
    //     catch (bytes memory data) {
    //         (bool reverted, uint256 gasSpent) = abi.decode(data, (bool, uint256));
    //         gasStruct.gasSpent1 = gasSpent;
    //     }

    //     bytes memory hints = VetoSlasherHints(vetoSlasherHints).setResolverSharesHints(
    //         address(slasher), address(vetoSlasherHintsHelper), alice, inputParams.shares
    //     );
    //     try vetoSlasherHintsHelper.trySetResolverShares(address(slasher), alice, inputParams.shares, hints) {}
    //     catch (bytes memory data) {
    //         (bool reverted, uint256 gasSpent) = abi.decode(data, (bool, uint256));
    //         gasStruct.gasSpent2 = gasSpent;
    //     }
    //     assertGe(gasStruct.gasSpent1, gasStruct.gasSpent2);
    // }

    function _getVaultAndDelegator(
        uint48 epochDuration
    ) internal returns (Vault, FullRestakeDelegator) {
        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
        (address vault_, address delegator_,) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: vaultFactory.lastVersion(),
                owner: alice,
                vaultParams: abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: epochDuration,
                        depositWhitelist: false,
                        isDepositLimit: false,
                        depositLimit: 0,
                        defaultAdminRoleHolder: alice,
                        depositWhitelistSetRoleHolder: alice,
                        depositorWhitelistRoleHolder: alice,
                        isDepositLimitSetRoleHolder: alice,
                        depositLimitSetRoleHolder: alice
                    })
                ),
                delegatorIndex: 0,
                delegatorParams: abi.encode(
                    INetworkRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: alice,
                            hook: address(0),
                            hookSetRoleHolder: alice
                        }),
                        networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                        operatorNetworkSharesSetRoleHolders: operatorNetworkSharesSetRoleHolders
                    })
                ),
                withSlasher: false,
                slasherIndex: 0,
                slasherParams: abi.encode(ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})}))
            })
        );

        return (Vault(vault_), FullRestakeDelegator(delegator_));
    }

    function _getVaultAndDelegatorAndSlasher(
        uint48 epochDuration,
        uint48 vetoDuration
    ) internal returns (Vault, FullRestakeDelegator, VetoSlasher) {
        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](1);
        operatorNetworkLimitSetRoleHolders[0] = alice;
        (address vault_, address delegator_, address slasher_) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: vaultFactory.lastVersion(),
                owner: alice,
                vaultParams: abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: epochDuration,
                        depositWhitelist: false,
                        isDepositLimit: false,
                        depositLimit: 0,
                        defaultAdminRoleHolder: alice,
                        depositWhitelistSetRoleHolder: alice,
                        depositorWhitelistRoleHolder: alice,
                        isDepositLimitSetRoleHolder: alice,
                        depositLimitSetRoleHolder: alice
                    })
                ),
                delegatorIndex: 1,
                delegatorParams: abi.encode(
                    IFullRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: alice,
                            hook: address(0),
                            hookSetRoleHolder: alice
                        }),
                        networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                        operatorNetworkLimitSetRoleHolders: operatorNetworkLimitSetRoleHolders
                    })
                ),
                withSlasher: true,
                slasherIndex: 1,
                slasherParams: abi.encode(
                    IVetoSlasher.InitParams({
                        baseParams: IBaseSlasher.BaseParams({isBurnerHook: false}),
                        vetoDuration: vetoDuration,
                        resolverSetEpochsDelay: 3
                    })
                )
            })
        );

        return (Vault(vault_), FullRestakeDelegator(delegator_), VetoSlasher(slasher_));
    }

    function _getSlasher(address vault_, uint48 vetoDuration) internal returns (VetoSlasher) {
        return VetoSlasher(
            slasherFactory.create(
                1,
                abi.encode(
                    vault_,
                    abi.encode(
                        IVetoSlasher.InitParams({
                            baseParams: IBaseSlasher.BaseParams({isBurnerHook: false}),
                            vetoDuration: vetoDuration,
                            resolverSetEpochsDelay: 3
                        })
                    )
                )
            )
        );
    }

    function _registerOperator(
        address user
    ) internal {
        vm.startPrank(user);
        operatorRegistry.registerOperator();
        vm.stopPrank();
    }

    function _registerNetwork(address user, address middleware) internal {
        vm.startPrank(user);
        networkRegistry.registerNetwork();
        networkMiddlewareService.setMiddleware(middleware);
        vm.stopPrank();
    }

    function _grantDepositorWhitelistRole(address user, address account) internal {
        vm.startPrank(user);
        Vault(address(vault)).grantRole(vault.DEPOSITOR_WHITELIST_ROLE(), account);
        vm.stopPrank();
    }

    function _grantDepositWhitelistSetRole(address user, address account) internal {
        vm.startPrank(user);
        Vault(address(vault)).grantRole(vault.DEPOSIT_WHITELIST_SET_ROLE(), account);
        vm.stopPrank();
    }

    function _deposit(address user, uint256 amount) internal returns (uint256 depositedAmount, uint256 mintedShares) {
        collateral.transfer(user, amount);
        vm.startPrank(user);
        collateral.approve(address(vault), amount);
        (depositedAmount, mintedShares) = vault.deposit(user, amount);
        vm.stopPrank();
    }

    function _withdraw(address user, uint256 amount) internal returns (uint256 burnedShares, uint256 mintedShares) {
        vm.startPrank(user);
        (burnedShares, mintedShares) = vault.withdraw(user, amount);
        vm.stopPrank();
    }

    function _claim(address user, uint256 epoch) internal returns (uint256 amount) {
        vm.startPrank(user);
        amount = vault.claim(user, epoch);
        vm.stopPrank();
    }

    function _claimBatch(address user, uint256[] memory epochs) internal returns (uint256 amount) {
        vm.startPrank(user);
        amount = vault.claimBatch(user, epochs);
        vm.stopPrank();
    }

    function _optInOperatorVault(
        address user
    ) internal {
        vm.startPrank(user);
        operatorVaultOptInService.optIn(address(vault));
        vm.stopPrank();
    }

    function _optOutOperatorVault(
        address user
    ) internal {
        vm.startPrank(user);
        operatorVaultOptInService.optOut(address(vault));
        vm.stopPrank();
    }

    function _optInOperatorNetwork(address user, address network) internal {
        vm.startPrank(user);
        operatorNetworkOptInService.optIn(network);
        vm.stopPrank();
    }

    function _optOutOperatorNetwork(address user, address network) internal {
        vm.startPrank(user);
        operatorNetworkOptInService.optOut(network);
        vm.stopPrank();
    }

    function _setDepositWhitelist(address user, bool depositWhitelist) internal {
        vm.startPrank(user);
        vault.setDepositWhitelist(depositWhitelist);
        vm.stopPrank();
    }

    function _setDepositorWhitelistStatus(address user, address depositor, bool status) internal {
        vm.startPrank(user);
        vault.setDepositorWhitelistStatus(depositor, status);
        vm.stopPrank();
    }

    function _requestSlash(
        address user,
        address network,
        address operator,
        uint256 amount,
        uint48 captureTimestamp,
        bytes memory hints
    ) internal returns (uint256 slashIndex) {
        vm.startPrank(user);
        slashIndex = slasher.requestSlash(network.subnetwork(0), operator, amount, captureTimestamp, hints);
        vm.stopPrank();
    }

    function _executeSlash(
        address user,
        uint256 slashIndex,
        bytes memory hints
    ) internal returns (uint256 slashAmount) {
        vm.startPrank(user);
        slashAmount = slasher.executeSlash(slashIndex, hints);
        vm.stopPrank();
    }

    function _vetoSlash(address user, uint256 slashIndex, bytes memory hints) internal {
        vm.startPrank(user);
        slasher.vetoSlash(slashIndex, hints);
        vm.stopPrank();
    }

    function _setResolver(address user, uint96 identifier, address resolver, bytes memory hints) internal {
        vm.startPrank(user);
        slasher.setResolver(identifier, resolver, hints);
        vm.stopPrank();
    }

    function _setNetworkLimit(address user, address network, uint256 amount) internal {
        vm.startPrank(user);
        delegator.setNetworkLimit(network.subnetwork(0), amount);
        vm.stopPrank();
    }

    function _setOperatorNetworkLimit(address user, address network, address operator, uint256 amount) internal {
        vm.startPrank(user);
        delegator.setOperatorNetworkLimit(network.subnetwork(0), operator, amount);
        vm.stopPrank();
    }

    function _setMaxNetworkLimit(address user, uint96 identifier, uint256 amount) internal {
        vm.startPrank(user);
        delegator.setMaxNetworkLimit(identifier, amount);
        vm.stopPrank();
    }
}

contract VetoSlasherHintsHelper is Test {
    function tryRequestSlash(
        address slasher,
        bytes32 subnetwork,
        address operator,
        uint256 amount,
        uint48 captureTimestamp,
        bytes memory hints
    ) external returns (bool reverted) {
        try VetoSlasher(slasher).requestSlash(subnetwork, operator, amount, captureTimestamp, hints) {}
        catch {
            reverted = true;
        }
        bytes memory revertData = abi.encode(reverted, vm.lastCallGas().gasTotalUsed);
        assembly {
            revert(add(32, revertData), mload(revertData))
        }
    }

    function tryExecuteSlash(
        address slasher,
        uint256 slashIndex,
        bytes memory hints
    ) external returns (bool reverted) {
        try VetoSlasher(slasher).executeSlash(slashIndex, hints) {}
        catch {
            reverted = true;
        }

        bytes memory revertData = abi.encode(reverted, vm.lastCallGas().gasTotalUsed);
        assembly {
            revert(add(32, revertData), mload(revertData))
        }
    }

    function tryVetoSlash(address slasher, uint256 slashIndex, bytes memory hints) external returns (bool reverted) {
        try VetoSlasher(slasher).vetoSlash(slashIndex, hints) {}
        catch {
            reverted = true;
        }
        bytes memory revertData = abi.encode(reverted, vm.lastCallGas().gasTotalUsed);
        assembly {
            revert(add(32, revertData), mload(revertData))
        }
    }

    function trySetResolver(
        address slasher,
        uint96 identifier,
        address resolver,
        uint256 shares,
        bytes memory hints
    ) external returns (bool reverted) {
        try VetoSlasher(slasher).setResolver(identifier, resolver, hints) {}
        catch {
            reverted = true;
        }
        bytes memory revertData = abi.encode(reverted, vm.lastCallGas().gasTotalUsed);
        assembly {
            revert(add(32, revertData), mload(revertData))
        }
    }
}
