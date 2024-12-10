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
import {ISlasher} from "../../src/interfaces/slasher/ISlasher.sol";
import {IBaseSlasher} from "../../src/interfaces/slasher/IBaseSlasher.sol";

import {IVaultStorage} from "../../src/interfaces/vault/IVaultStorage.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SimpleFullRestakeDelegatorHook} from "../mocks/SimpleFullRestakeDelegatorHook.sol";

import {BaseDelegatorHints, FullRestakeDelegatorHints} from "../../src/contracts/hints/DelegatorHints.sol";
import {OptInServiceHints} from "../../src/contracts/hints/OptInServiceHints.sol";
import {VaultHints} from "../../src/contracts/hints/VaultHints.sol";
import {Subnetwork} from "../../src/contracts/libraries/Subnetwork.sol";

contract FullRestakeDelegatorTest is Test {
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
    Slasher slasher;

    BaseDelegatorHints baseDelegatorHints;

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

    function test_Create(
        uint48 epochDuration
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        assertEq(delegator.VERSION(), 1);
        assertEq(delegator.NETWORK_REGISTRY(), address(networkRegistry));
        assertEq(delegator.VAULT_FACTORY(), address(vaultFactory));
        assertEq(delegator.OPERATOR_VAULT_OPT_IN_SERVICE(), address(operatorVaultOptInService));
        assertEq(delegator.OPERATOR_NETWORK_OPT_IN_SERVICE(), address(operatorNetworkOptInService));
        assertEq(delegator.vault(), address(vault));
        assertEq(delegator.maxNetworkLimit(alice.subnetwork(0)), 0);
        assertEq(delegator.stakeAt(alice.subnetwork(0), alice, 0, ""), 0);
        assertEq(delegator.stake(alice.subnetwork(0), alice), 0);
        assertEq(delegator.NETWORK_LIMIT_SET_ROLE(), keccak256("NETWORK_LIMIT_SET_ROLE"));
        assertEq(delegator.OPERATOR_NETWORK_LIMIT_SET_ROLE(), keccak256("OPERATOR_NETWORK_LIMIT_SET_ROLE"));
        assertEq(delegator.networkLimitAt(alice.subnetwork(0), 0, ""), 0);
        assertEq(delegator.networkLimit(alice.subnetwork(0)), 0);
        assertEq(delegator.operatorNetworkLimitAt(alice.subnetwork(0), alice, 0, ""), 0);
        assertEq(delegator.operatorNetworkLimit(alice.subnetwork(0), alice), 0);
    }

    function test_CreateRevertNotVault(
        uint48 epochDuration
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = bob;
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](1);
        operatorNetworkLimitSetRoleHolders[0] = bob;

        vm.expectRevert(IBaseDelegator.NotVault.selector);
        delegatorFactory.create(
            1,
            abi.encode(
                address(1),
                abi.encode(
                    IFullRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: bob,
                            hook: address(0),
                            hookSetRoleHolder: bob
                        }),
                        networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                        operatorNetworkLimitSetRoleHolders: operatorNetworkLimitSetRoleHolders
                    })
                )
            )
        );
    }

    function test_CreateRevertMissingRoleHolders(
        uint48 epochDuration
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        address[] memory networkLimitSetRoleHolders = new address[](0);
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](1);
        operatorNetworkLimitSetRoleHolders[0] = bob;

        vm.expectRevert(IFullRestakeDelegator.MissingRoleHolders.selector);
        delegatorFactory.create(
            1,
            abi.encode(
                address(vault),
                abi.encode(
                    IFullRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: address(0),
                            hook: address(0),
                            hookSetRoleHolder: address(1)
                        }),
                        networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                        operatorNetworkLimitSetRoleHolders: operatorNetworkLimitSetRoleHolders
                    })
                )
            )
        );
    }

    function test_CreateRevertZeroAddressRoleHolder1(
        uint48 epochDuration
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = address(0);
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](1);
        operatorNetworkLimitSetRoleHolders[0] = bob;

        vm.expectRevert(IFullRestakeDelegator.ZeroAddressRoleHolder.selector);
        delegatorFactory.create(
            1,
            abi.encode(
                address(vault),
                abi.encode(
                    IFullRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: address(0),
                            hook: address(0),
                            hookSetRoleHolder: address(1)
                        }),
                        networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                        operatorNetworkLimitSetRoleHolders: operatorNetworkLimitSetRoleHolders
                    })
                )
            )
        );
    }

    function test_CreateRevertZeroAddressRoleHolder2(
        uint48 epochDuration
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = bob;
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](1);
        operatorNetworkLimitSetRoleHolders[0] = address(0);

        vm.expectRevert(IFullRestakeDelegator.ZeroAddressRoleHolder.selector);
        delegatorFactory.create(
            1,
            abi.encode(
                address(vault),
                abi.encode(
                    IFullRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: address(0),
                            hook: address(0),
                            hookSetRoleHolder: address(1)
                        }),
                        networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                        operatorNetworkLimitSetRoleHolders: operatorNetworkLimitSetRoleHolders
                    })
                )
            )
        );
    }

    function test_CreateRevertDuplicateRoleHolder1(
        uint48 epochDuration
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        address[] memory networkLimitSetRoleHolders = new address[](2);
        networkLimitSetRoleHolders[0] = bob;
        networkLimitSetRoleHolders[1] = bob;
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](1);
        operatorNetworkLimitSetRoleHolders[0] = bob;

        vm.expectRevert(IFullRestakeDelegator.DuplicateRoleHolder.selector);
        delegatorFactory.create(
            1,
            abi.encode(
                address(vault),
                abi.encode(
                    IFullRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: address(0),
                            hook: address(0),
                            hookSetRoleHolder: address(1)
                        }),
                        networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                        operatorNetworkLimitSetRoleHolders: operatorNetworkLimitSetRoleHolders
                    })
                )
            )
        );
    }

    function test_CreateRevertDuplicateRoleHolder2(
        uint48 epochDuration
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = bob;
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](2);
        operatorNetworkLimitSetRoleHolders[0] = bob;
        operatorNetworkLimitSetRoleHolders[1] = bob;

        vm.expectRevert(IFullRestakeDelegator.DuplicateRoleHolder.selector);
        delegatorFactory.create(
            1,
            abi.encode(
                address(vault),
                abi.encode(
                    IFullRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: address(0),
                            hook: address(0),
                            hookSetRoleHolder: address(1)
                        }),
                        networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                        operatorNetworkLimitSetRoleHolders: operatorNetworkLimitSetRoleHolders
                    })
                )
            )
        );
    }

    function test_OnSlashRevertNotSlasher(
        uint48 epochDuration
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        vm.startPrank(alice);
        vm.expectRevert(IBaseDelegator.NotSlasher.selector);
        delegator.onSlash(bytes32(0), address(0), 0, 0, "");
        vm.stopPrank();
    }

    function test_SetNetworkLimit(
        uint48 epochDuration,
        uint256 amount1,
        uint256 amount2,
        uint256 amount3,
        uint256 amount4
    ) public {
        epochDuration = uint48(bound(uint256(epochDuration), 1, 100 days));

        vm.assume(0 != amount1);
        vm.assume(amount1 != amount2);
        vm.assume(amount2 != amount3);
        vm.assume(amount3 != amount4);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        address network = bob;
        _registerNetwork(network, bob);

        _setMaxNetworkLimit(network, 0, type(uint256).max);

        _setNetworkLimit(alice, network, amount1);

        assertEq(delegator.networkLimitAt(network.subnetwork(0), uint48(blockTimestamp), ""), amount1);
        assertEq(delegator.networkLimitAt(network.subnetwork(0), uint48(blockTimestamp + 1), ""), amount1);
        assertEq(delegator.networkLimit(network.subnetwork(0)), amount1);

        _setNetworkLimit(alice, network, amount2);

        assertEq(delegator.networkLimitAt(network.subnetwork(0), uint48(blockTimestamp), ""), amount2);
        assertEq(delegator.networkLimitAt(network.subnetwork(0), uint48(blockTimestamp + 1), ""), amount2);
        assertEq(delegator.networkLimit(network.subnetwork(0)), amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _setNetworkLimit(alice, network, amount3);

        assertEq(delegator.networkLimitAt(network.subnetwork(0), uint48(blockTimestamp - 1), ""), amount2);
        assertEq(delegator.networkLimitAt(network.subnetwork(0), uint48(blockTimestamp), ""), amount3);
        assertEq(delegator.networkLimitAt(network.subnetwork(0), uint48(blockTimestamp + 1), ""), amount3);
        assertEq(delegator.networkLimit(network.subnetwork(0)), amount3);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _setNetworkLimit(alice, network, amount4);

        assertEq(delegator.networkLimitAt(network.subnetwork(0), uint48(blockTimestamp - 2), ""), amount2);
        assertEq(delegator.networkLimitAt(network.subnetwork(0), uint48(blockTimestamp - 1), ""), amount3);
        assertEq(delegator.networkLimitAt(network.subnetwork(0), uint48(blockTimestamp), ""), amount4);
        assertEq(delegator.networkLimitAt(network.subnetwork(0), uint48(blockTimestamp + 1), ""), amount4);
        assertEq(delegator.networkLimit(network.subnetwork(0)), amount4);
    }

    function test_SetNetworkLimitRevertExceedsMaxNetworkLimit(
        uint48 epochDuration,
        uint256 amount1,
        uint256 maxNetworkLimit
    ) public {
        epochDuration = uint48(bound(uint256(epochDuration), 1, 100 days));
        maxNetworkLimit = bound(maxNetworkLimit, 1, type(uint256).max);
        vm.assume(amount1 > maxNetworkLimit);

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        address network = bob;
        _registerNetwork(network, bob);

        _setMaxNetworkLimit(network, 0, maxNetworkLimit);

        vm.expectRevert(IFullRestakeDelegator.ExceedsMaxNetworkLimit.selector);
        _setNetworkLimit(alice, network, amount1);
    }

    function test_SetNetworkLimitRevertAlreadySet(
        uint48 epochDuration,
        uint256 amount1,
        uint256 maxNetworkLimit
    ) public {
        epochDuration = uint48(bound(uint256(epochDuration), 1, 100 days));
        maxNetworkLimit = bound(maxNetworkLimit, 1, type(uint256).max);
        amount1 = bound(amount1, 1, maxNetworkLimit);

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        address network = bob;
        _registerNetwork(network, bob);

        _setMaxNetworkLimit(network, 0, maxNetworkLimit);

        _setNetworkLimit(alice, network, amount1);

        vm.expectRevert(IBaseDelegator.AlreadySet.selector);
        _setNetworkLimit(alice, network, amount1);
    }

    function test_SetOperatorNetworkLimit(
        uint48 epochDuration,
        uint256 amount1,
        uint256 amount2,
        uint256 amount3,
        uint256 amount4
    ) public {
        epochDuration = uint48(bound(uint256(epochDuration), 1, 100 days));
        amount1 = bound(amount1, 1, type(uint256).max);
        vm.assume(amount3 < amount2);
        vm.assume(amount4 > amount2 && amount4 > amount1);

        vm.assume(0 != amount1);
        vm.assume(amount1 != amount2);
        vm.assume(amount2 != amount3);
        vm.assume(amount3 != amount4);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        address network = bob;
        _registerNetwork(network, bob);
        address operator = bob;
        _registerOperator(operator);

        _setOperatorNetworkLimit(alice, network, operator, amount1);

        assertEq(delegator.operatorNetworkLimitAt(network.subnetwork(0), operator, uint48(blockTimestamp), ""), amount1);
        assertEq(
            delegator.operatorNetworkLimitAt(network.subnetwork(0), operator, uint48(blockTimestamp + 1), ""), amount1
        );
        assertEq(delegator.operatorNetworkLimit(network.subnetwork(0), operator), amount1);

        _setOperatorNetworkLimit(alice, network, operator, amount2);

        assertEq(delegator.operatorNetworkLimitAt(network.subnetwork(0), operator, uint48(blockTimestamp), ""), amount2);
        assertEq(
            delegator.operatorNetworkLimitAt(network.subnetwork(0), operator, uint48(blockTimestamp + 1), ""), amount2
        );
        assertEq(delegator.operatorNetworkLimit(network.subnetwork(0), operator), amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _setOperatorNetworkLimit(alice, network, operator, amount3);

        assertEq(
            delegator.operatorNetworkLimitAt(network.subnetwork(0), operator, uint48(blockTimestamp - 1), ""), amount2
        );
        assertEq(delegator.operatorNetworkLimitAt(network.subnetwork(0), operator, uint48(blockTimestamp), ""), amount3);
        assertEq(
            delegator.operatorNetworkLimitAt(network.subnetwork(0), operator, uint48(blockTimestamp + 1), ""), amount3
        );
        assertEq(delegator.operatorNetworkLimit(network.subnetwork(0), operator), amount3);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _setOperatorNetworkLimit(alice, network, operator, amount4);

        assertEq(
            delegator.operatorNetworkLimitAt(network.subnetwork(0), operator, uint48(blockTimestamp - 2), ""), amount2
        );
        assertEq(
            delegator.operatorNetworkLimitAt(network.subnetwork(0), operator, uint48(blockTimestamp - 1), ""), amount3
        );
        assertEq(delegator.operatorNetworkLimitAt(network.subnetwork(0), operator, uint48(blockTimestamp), ""), amount4);
        assertEq(
            delegator.operatorNetworkLimitAt(network.subnetwork(0), operator, uint48(blockTimestamp + 1), ""), amount4
        );
        assertEq(delegator.operatorNetworkLimit(network.subnetwork(0), operator), amount4);
    }

    function test_SetOperatorNetworkLimitBoth(
        uint48 epochDuration,
        uint256 amount1,
        uint256 amount2,
        uint256 amount3
    ) public {
        epochDuration = uint48(bound(uint256(epochDuration), 1, 100 days));
        amount1 = bound(amount1, 1, type(uint256).max / 2);
        amount2 = bound(amount2, 1, type(uint256).max / 2);
        vm.assume(amount3 < amount2);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        address network = bob;
        _registerNetwork(network, bob);
        _registerOperator(alice);
        _registerOperator(bob);

        _setOperatorNetworkLimit(alice, network, alice, amount1);

        assertEq(
            delegator.operatorNetworkLimitAt(network.subnetwork(0), alice, uint48(blockTimestamp + 1), ""), amount1
        );
        assertEq(delegator.operatorNetworkLimit(network.subnetwork(0), alice), amount1);

        _setOperatorNetworkLimit(alice, network, bob, amount2);

        assertEq(delegator.operatorNetworkLimitAt(network.subnetwork(0), bob, uint48(blockTimestamp + 1), ""), amount2);
        assertEq(delegator.operatorNetworkLimit(network.subnetwork(0), bob), amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _setOperatorNetworkLimit(alice, network, bob, amount3);

        assertEq(delegator.operatorNetworkLimitAt(network.subnetwork(0), bob, uint48(blockTimestamp - 1), ""), amount2);
        assertEq(delegator.operatorNetworkLimitAt(network.subnetwork(0), bob, uint48(blockTimestamp + 1), ""), amount3);
        assertEq(delegator.operatorNetworkLimit(network.subnetwork(0), bob), amount3);
    }

    function test_SetOperatorNetworkLimitRevertAlreadySet(uint48 epochDuration, uint256 amount1) public {
        epochDuration = uint48(bound(uint256(epochDuration), 1, 100 days));
        amount1 = bound(amount1, 1, type(uint256).max / 2);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        address network = bob;
        _registerNetwork(network, bob);
        _registerOperator(alice);

        _setOperatorNetworkLimit(alice, network, alice, amount1);

        vm.expectRevert(IBaseDelegator.AlreadySet.selector);
        _setOperatorNetworkLimit(alice, network, alice, amount1);
    }

    function test_SetMaxNetworkLimit(
        uint48 epochDuration,
        uint256 maxNetworkLimit1,
        uint256 maxNetworkLimit2,
        uint256 networkLimit1
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 100 days));
        maxNetworkLimit1 = bound(maxNetworkLimit1, 1, type(uint256).max);
        vm.assume(maxNetworkLimit1 > maxNetworkLimit2);
        vm.assume(maxNetworkLimit1 >= networkLimit1 && networkLimit1 >= maxNetworkLimit2);

        vm.assume(0 != networkLimit1);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        address network = alice;
        _registerNetwork(network, alice);

        _setMaxNetworkLimit(network, 0, maxNetworkLimit1);

        assertEq(delegator.maxNetworkLimit(network.subnetwork(0)), maxNetworkLimit1);

        _setNetworkLimit(alice, network, networkLimit1);

        assertEq(
            delegator.networkLimitAt(network.subnetwork(0), uint48(blockTimestamp + 2 * vault.epochDuration()), ""),
            networkLimit1
        );

        blockTimestamp = vault.currentEpochStart() + vault.epochDuration();
        vm.warp(blockTimestamp);

        assertEq(
            delegator.networkLimitAt(network.subnetwork(0), uint48(blockTimestamp + vault.epochDuration()), ""),
            networkLimit1
        );
        assertEq(
            delegator.networkLimitAt(network.subnetwork(0), uint48(blockTimestamp + 2 * vault.epochDuration()), ""),
            networkLimit1
        );

        _setMaxNetworkLimit(network, 0, maxNetworkLimit2);

        assertEq(delegator.maxNetworkLimit(network.subnetwork(0)), maxNetworkLimit2);
        assertEq(
            delegator.networkLimitAt(network.subnetwork(0), uint48(blockTimestamp + vault.epochDuration()), ""),
            maxNetworkLimit2
        );
        assertEq(
            delegator.networkLimitAt(network.subnetwork(0), uint48(blockTimestamp + 2 * vault.epochDuration()), ""),
            maxNetworkLimit2
        );
    }

    function test_SetMaxNetworkLimitRevertNotNetwork(uint48 epochDuration, uint256 maxNetworkLimit) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));
        maxNetworkLimit = bound(maxNetworkLimit, 1, type(uint256).max);

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        _registerNetwork(alice, alice);

        vm.expectRevert(IBaseDelegator.NotNetwork.selector);
        _setMaxNetworkLimit(bob, 0, maxNetworkLimit);
    }

    function test_SetMaxNetworkLimitRevertAlreadySet(uint48 epochDuration, uint256 maxNetworkLimit) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));
        maxNetworkLimit = bound(maxNetworkLimit, 1, type(uint256).max);

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        _registerNetwork(alice, alice);

        _setMaxNetworkLimit(alice, 0, maxNetworkLimit);

        vm.expectRevert(IBaseDelegator.AlreadySet.selector);
        _setMaxNetworkLimit(alice, 0, maxNetworkLimit);
    }

    function test_Stakes(
        uint48 epochDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 operatorNetworkLimit2,
        uint256 operatorNetworkLimit3
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        operatorNetworkLimit2 = bound(operatorNetworkLimit2, 1, type(uint256).max / 2);
        operatorNetworkLimit3 = bound(operatorNetworkLimit3, 0, type(uint256).max / 2);

        vm.assume(operatorNetworkLimit2 - 1 != operatorNetworkLimit3);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        address network = alice;
        _registerNetwork(network, alice);
        _setMaxNetworkLimit(network, 0, type(uint256).max);

        _registerOperator(alice);
        _registerOperator(bob);

        assertEq(delegator.stake(network.subnetwork(0), alice), 0);
        assertEq(delegator.stake(network.subnetwork(0), bob), 0);

        _optInOperatorVault(alice);
        _optInOperatorVault(bob);

        assertEq(delegator.stake(network.subnetwork(0), alice), 0);
        assertEq(delegator.stake(network.subnetwork(0), bob), 0);

        _optInOperatorNetwork(alice, address(network));
        _optInOperatorNetwork(bob, address(network));

        assertEq(delegator.stake(network.subnetwork(0), alice), 0);
        assertEq(delegator.stake(network.subnetwork(0), bob), 0);

        _deposit(alice, depositAmount);

        assertEq(delegator.stake(network.subnetwork(0), alice), 0);
        assertEq(delegator.stake(network.subnetwork(0), bob), 0);

        _setNetworkLimit(alice, network, networkLimit);

        assertEq(delegator.stake(network.subnetwork(0), alice), 0);
        assertEq(delegator.stake(network.subnetwork(0), bob), 0);

        _setOperatorNetworkLimit(alice, network, alice, operatorNetworkLimit1);

        assertEq(
            delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp), ""),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1))
        );
        assertEq(
            delegator.stake(network.subnetwork(0), alice),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1))
        );
        assertEq(delegator.stakeAt(network.subnetwork(0), bob, uint48(blockTimestamp), ""), 0);
        assertEq(delegator.stake(network.subnetwork(0), bob), 0);

        _setOperatorNetworkLimit(alice, network, bob, operatorNetworkLimit2);

        assertEq(
            delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp), ""),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1))
        );
        assertEq(
            delegator.stake(network.subnetwork(0), alice),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1))
        );
        assertEq(
            delegator.stakeAt(network.subnetwork(0), bob, uint48(blockTimestamp), ""),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit2))
        );
        assertEq(
            delegator.stake(network.subnetwork(0), bob),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit2))
        );

        _setOperatorNetworkLimit(alice, network, bob, operatorNetworkLimit2 - 1);

        assertEq(
            delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp), ""),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1))
        );
        assertEq(
            delegator.stake(network.subnetwork(0), alice),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1))
        );
        assertEq(
            delegator.stakeAt(network.subnetwork(0), bob, uint48(blockTimestamp), ""),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit2 - 1))
        );
        assertEq(
            delegator.stake(network.subnetwork(0), bob),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit2 - 1))
        );

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _setOperatorNetworkLimit(alice, network, bob, operatorNetworkLimit3);

        assertEq(
            delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 1), ""),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1))
        );
        assertEq(
            delegator.stake(network.subnetwork(0), alice),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1))
        );
        assertEq(
            delegator.stakeAt(network.subnetwork(0), bob, uint48(blockTimestamp - 1), ""),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit2 - 1))
        );
        assertEq(
            delegator.stake(network.subnetwork(0), bob),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit3))
        );

        bytes memory hints = abi.encode(
            IFullRestakeDelegator.StakeHints({
                baseHints: abi.encode(
                    IBaseDelegator.StakeBaseHints({
                        operatorVaultOptInHint: abi.encode(0),
                        operatorNetworkOptInHint: abi.encode(0)
                    })
                ),
                activeStakeHint: abi.encode(0),
                networkLimitHint: abi.encode(0),
                operatorNetworkLimitHint: abi.encode(0)
            })
        );
        uint256 gasLeft = gasleft();
        assertEq(
            delegator.stakeAt(network.subnetwork(0), bob, uint48(blockTimestamp), hints),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit3))
        );
        uint256 gasSpent = gasLeft - gasleft();
        hints = abi.encode(
            IFullRestakeDelegator.StakeHints({
                baseHints: abi.encode(
                    IBaseDelegator.StakeBaseHints({
                        operatorVaultOptInHint: abi.encode(0),
                        operatorNetworkOptInHint: abi.encode(0)
                    })
                ),
                activeStakeHint: abi.encode(0),
                networkLimitHint: abi.encode(0),
                operatorNetworkLimitHint: abi.encode(1)
            })
        );
        gasLeft = gasleft();
        assertEq(
            delegator.stakeAt(network.subnetwork(0), bob, uint48(blockTimestamp), hints),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit3))
        );
        assertGt(gasSpent, gasLeft - gasleft());

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(
            delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 2), ""),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1))
        );
        assertEq(
            delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 1), ""),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1))
        );
        assertEq(
            delegator.stake(network.subnetwork(0), alice),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1))
        );
        assertEq(
            delegator.stakeAt(network.subnetwork(0), bob, uint48(blockTimestamp - 2), ""),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit2 - 1))
        );
        assertEq(
            delegator.stakeAt(network.subnetwork(0), bob, uint48(blockTimestamp - 1), ""),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit3))
        );
        assertEq(
            delegator.stake(network.subnetwork(0), bob),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit3))
        );
    }

    function test_Slash(
        uint48 epochDuration,
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

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration);

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

        _setOperatorNetworkLimit(alice, network, alice, operatorNetworkLimit1);
        _setOperatorNetworkLimit(alice, network, bob, operatorNetworkLimit2);

        assertEq(delegator.networkLimit(network.subnetwork(0)), networkLimit);
        assertEq(delegator.operatorNetworkLimit(network.subnetwork(0), alice), operatorNetworkLimit1);
        assertEq(delegator.operatorNetworkLimit(network.subnetwork(0), bob), operatorNetworkLimit2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 slashAmount1Real =
            Math.min(slashAmount1, Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1)));
        assertEq(_slash(alice, network, alice, slashAmount1, uint48(blockTimestamp - 1), ""), slashAmount1Real);

        assertEq(delegator.networkLimit(network.subnetwork(0)), networkLimit);
        assertEq(delegator.operatorNetworkLimit(network.subnetwork(0), alice), operatorNetworkLimit1);
        assertEq(delegator.operatorNetworkLimit(network.subnetwork(0), bob), operatorNetworkLimit2);

        uint256 slashAmount2Real =
            Math.min(slashAmount2, Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit2)));
        assertEq(_slash(alice, network, bob, slashAmount2, uint48(blockTimestamp - 1), ""), slashAmount2Real);

        assertEq(delegator.networkLimit(network.subnetwork(0)), networkLimit);
        assertEq(delegator.operatorNetworkLimit(network.subnetwork(0), alice), operatorNetworkLimit1);
        assertEq(delegator.operatorNetworkLimit(network.subnetwork(0), bob), operatorNetworkLimit2);
    }

    function test_SlashWithHookBase(
        // uint48 epochDuration,
        uint256 depositAmount,
        // uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 slashAmount1,
        uint256 slashAmount2
    ) public {
        // epochDuration = uint48(bound(epochDuration, 1, 10 days));
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        // networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);
        slashAmount2 = bound(slashAmount2, 1, type(uint256).max);
        vm.assume(slashAmount1 < Math.min(depositAmount, Math.min(type(uint256).max, operatorNetworkLimit1)));

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        address hook = address(new SimpleFullRestakeDelegatorHook());
        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](2);
        operatorNetworkLimitSetRoleHolders[0] = alice;
        operatorNetworkLimitSetRoleHolders[1] = hook;
        (address vault_, address delegator_, address slasher_) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: vaultFactory.lastVersion(),
                owner: alice,
                vaultParams: abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: 7 days,
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
                            hook: hook,
                            hookSetRoleHolder: address(0)
                        }),
                        networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                        operatorNetworkLimitSetRoleHolders: operatorNetworkLimitSetRoleHolders
                    })
                ),
                withSlasher: true,
                slasherIndex: 0,
                slasherParams: abi.encode(ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})}))
            })
        );

        vault = Vault(vault_);
        delegator = FullRestakeDelegator(delegator_);
        slasher = Slasher(slasher_);

        address network = alice;
        _registerNetwork(network, alice);
        _setMaxNetworkLimit(network, 0, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(network));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, network, type(uint256).max);

        _setOperatorNetworkLimit(alice, network, alice, operatorNetworkLimit1);

        assertEq(delegator.networkLimit(network.subnetwork(0)), type(uint256).max);
        assertEq(delegator.operatorNetworkLimit(network.subnetwork(0), alice), operatorNetworkLimit1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        SimpleFullRestakeDelegatorHook(hook).setData(
            0,
            slasher.slashableStake(network.subnetwork(0), alice, uint48(blockTimestamp - 1), ""),
            delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 1), ""),
            0
        );
        _slash(alice, network, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        assertEq(delegator.networkLimit(network.subnetwork(0)), type(uint256).max);
        assertEq(delegator.operatorNetworkLimit(network.subnetwork(0), alice), operatorNetworkLimit1);

        SimpleFullRestakeDelegatorHook(hook).setData(
            0,
            slasher.slashableStake(network.subnetwork(0), alice, uint48(blockTimestamp - 1), ""),
            delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 1), ""),
            0
        );
        _slash(alice, network, alice, slashAmount2, uint48(blockTimestamp - 1), "");

        assertEq(delegator.networkLimit(network.subnetwork(0)), type(uint256).max);
        assertEq(delegator.operatorNetworkLimit(network.subnetwork(0), alice), 0);
    }

    function test_SlashWithHookGas(
        // uint48 epochDuration,
        uint256 depositAmount,
        // uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 slashAmount1,
        uint256 totalGas
    ) public {
        // epochDuration = uint48(bound(epochDuration, 1, 10 days));
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        // networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);
        totalGas = bound(totalGas, 1, 20_000_000);
        vm.assume(slashAmount1 < Math.min(depositAmount, Math.min(type(uint256).max, operatorNetworkLimit1)));

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        address hook = address(new SimpleFullRestakeDelegatorHook());
        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](2);
        operatorNetworkLimitSetRoleHolders[0] = alice;
        operatorNetworkLimitSetRoleHolders[1] = hook;
        (address vault_, address delegator_, address slasher_) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: vaultFactory.lastVersion(),
                owner: alice,
                vaultParams: abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: 7 days,
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
                            hook: hook,
                            hookSetRoleHolder: address(0)
                        }),
                        networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                        operatorNetworkLimitSetRoleHolders: operatorNetworkLimitSetRoleHolders
                    })
                ),
                withSlasher: true,
                slasherIndex: 0,
                slasherParams: abi.encode(ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})}))
            })
        );

        vault = Vault(vault_);
        delegator = FullRestakeDelegator(delegator_);
        slasher = Slasher(slasher_);

        address network = alice;
        _registerNetwork(network, alice);
        _setMaxNetworkLimit(network, 0, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(network));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, network, type(uint256).max);

        _setOperatorNetworkLimit(alice, network, alice, operatorNetworkLimit1);

        assertEq(delegator.networkLimit(network.subnetwork(0)), type(uint256).max);
        assertEq(delegator.operatorNetworkLimit(network.subnetwork(0), alice), operatorNetworkLimit1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        SimpleFullRestakeDelegatorHook(hook).setData(
            0,
            slasher.slashableStake(network.subnetwork(0), alice, uint48(blockTimestamp - 1), ""),
            delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 1), ""),
            0
        );
        _slash(alice, network, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        vm.startPrank(alice);
        uint256 HOOK_GAS_LIMIT = delegator.HOOK_GAS_LIMIT();
        vm.expectRevert(IBaseDelegator.InsufficientHookGas.selector);
        address(slasher).call{gas: HOOK_GAS_LIMIT}(
            abi.encodeCall(ISlasher.slash, (network.subnetwork(0), alice, slashAmount1, uint48(blockTimestamp - 1), ""))
        );
        vm.stopPrank();

        SimpleFullRestakeDelegatorHook(hook).setData(
            0,
            slasher.slashableStake(network.subnetwork(0), alice, uint48(blockTimestamp - 1), ""),
            delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 1), ""),
            0
        );
        vm.startPrank(alice);
        (bool success,) = address(slasher).call{gas: totalGas}(
            abi.encodeCall(ISlasher.slash, (network.subnetwork(0), alice, slashAmount1, uint48(blockTimestamp - 1), ""))
        );
        vm.stopPrank();

        if (success) {
            assertEq(delegator.networkLimit(network.subnetwork(0)), type(uint256).max);
            assertEq(delegator.operatorNetworkLimit(network.subnetwork(0), alice), 0);
        }
    }

    function test_SetHook(
        uint48 epochDuration
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        address hook = address(new SimpleFullRestakeDelegatorHook());

        assertEq(delegator.hook(), address(0));

        _setHook(alice, hook);

        assertEq(delegator.hook(), hook);

        hook = address(new SimpleFullRestakeDelegatorHook());

        _setHook(alice, hook);

        assertEq(delegator.hook(), hook);
    }

    function test_SetHookRevertAlreadySet(
        uint48 epochDuration
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        address hook = address(new SimpleFullRestakeDelegatorHook());

        _setHook(alice, hook);

        vm.expectRevert(IBaseDelegator.AlreadySet.selector);
        _setHook(alice, hook);
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

    // function test_NetworkLimitHint(uint256 amount1, uint48 epochDuration, HintStruct memory hintStruct) public {
    //     amount1 = bound(amount1, 1, 100 * 10 ** 18);
    //     epochDuration = uint48(bound(epochDuration, 1, 7 days));
    //     hintStruct.num = bound(hintStruct.num, 0, 25);
    //     hintStruct.secondsAgo = bound(hintStruct.secondsAgo, 0, 1_720_700_948);

    //     uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration);

    //     address network = alice;
    //     _registerNetwork(network, alice);
    //     _setMaxNetworkLimit(network, type(uint256).max);

    //     for (uint256 i; i < hintStruct.num; ++i) {
    //         _setNetworkLimit(alice, network, amount1);

    //         blockTimestamp = blockTimestamp + epochDuration;
    //         vm.warp(blockTimestamp);
    //     }

    //     uint48 timestamp =
    //         uint48(hintStruct.back ? blockTimestamp - hintStruct.secondsAgo : blockTimestamp + hintStruct.secondsAgo);

    //     OptInServiceHints optInServiceHints = new OptInServiceHints();
    //     VaultHints vaultHints = new VaultHints();
    //     baseDelegatorHints = new BaseDelegatorHints(address(optInServiceHints), address(vaultHints));
    //     FullRestakeDelegatorHints fullRestakeDelegatorHints =
    //         FullRestakeDelegatorHints(baseDelegatorHints.FULL_RESTAKE_DELEGATOR_HINTS());
    //     bytes memory hint = fullRestakeDelegatorHints.networkLimitHint(address(delegator), network, timestamp);

    //     GasStruct memory gasStruct = GasStruct({gasSpent1: 1, gasSpent2: 1});
    //     delegator.networkLimitAt(network, timestamp, new bytes(0));
    //     gasStruct.gasSpent1 = vm.lastCallGas().gasTotalUsed;
    //     delegator.networkLimitAt(network, timestamp, hint);
    //     gasStruct.gasSpent2 = vm.lastCallGas().gasTotalUsed;
    //     assertGe(gasStruct.gasSpent1, gasStruct.gasSpent2);
    // }

    // function test_OperatorNetworkLimitHint(
    //     uint256 amount1,
    //     uint48 epochDuration,
    //     HintStruct memory hintStruct
    // ) public {
    //     amount1 = bound(amount1, 1, 100 * 10 ** 18);
    //     epochDuration = uint48(bound(epochDuration, 1, 7 days));
    //     hintStruct.num = bound(hintStruct.num, 0, 25);
    //     hintStruct.secondsAgo = bound(hintStruct.secondsAgo, 0, 1_720_700_948);

    //     uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration);

    //     address network = alice;

    //     for (uint256 i; i < hintStruct.num; ++i) {
    //         _setOperatorNetworkLimit(alice, network, alice, amount1);

    //         blockTimestamp = blockTimestamp + epochDuration;
    //         vm.warp(blockTimestamp);
    //     }

    //     uint48 timestamp =
    //         uint48(hintStruct.back ? blockTimestamp - hintStruct.secondsAgo : blockTimestamp + hintStruct.secondsAgo);

    //     OptInServiceHints optInServiceHints = new OptInServiceHints();
    //     VaultHints vaultHints = new VaultHints();
    //     baseDelegatorHints = new BaseDelegatorHints(address(optInServiceHints), address(vaultHints));
    //     FullRestakeDelegatorHints fullRestakeDelegatorHints =
    //         FullRestakeDelegatorHints(baseDelegatorHints.FULL_RESTAKE_DELEGATOR_HINTS());
    //     bytes memory hint =
    //         fullRestakeDelegatorHints.operatorNetworkLimitHint(address(delegator), network, alice, timestamp);

    //     GasStruct memory gasStruct = GasStruct({gasSpent1: 1, gasSpent2: 1});
    //     delegator.operatorNetworkLimitAt(network, alice, timestamp, new bytes(0));
    //     gasStruct.gasSpent1 = vm.lastCallGas().gasTotalUsed;
    //     delegator.operatorNetworkLimitAt(network, alice, timestamp, hint);
    //     gasStruct.gasSpent2 = vm.lastCallGas().gasTotalUsed;
    //     assertGe(gasStruct.gasSpent1, gasStruct.gasSpent2);
    // }

    // struct StakeBaseHintsUint32 {
    //     bool withOperatorVaultOptInHint;
    //     uint32 operatorVaultOptInHint;
    //     bool withOperatorNetworkOptInHint;
    //     uint32 operatorNetworkOptInHint;
    // }

    // function test_StakeBaseHints(
    //     uint256 amount1,
    //     uint48 epochDuration,
    //     HintStruct memory hintStruct,
    //     StakeBaseHintsUint32 memory stakeBaseHintsUint32
    // ) public {
    //     amount1 = bound(amount1, 1, 100 * 10 ** 18);
    //     epochDuration = uint48(bound(epochDuration, 1, 7 days));
    //     hintStruct.num = bound(hintStruct.num, 0, 25);
    //     hintStruct.secondsAgo = bound(hintStruct.secondsAgo, 0, 1_720_700_948);
    //     if (stakeBaseHintsUint32.withOperatorVaultOptInHint) {
    //         stakeBaseHintsUint32.operatorVaultOptInHint =
    //             uint32(bound(stakeBaseHintsUint32.operatorVaultOptInHint, 0, 10 * hintStruct.num));
    //     }
    //     if (stakeBaseHintsUint32.withOperatorNetworkOptInHint) {
    //         stakeBaseHintsUint32.operatorNetworkOptInHint =
    //             uint32(bound(stakeBaseHintsUint32.operatorNetworkOptInHint, 0, 10 * hintStruct.num));
    //     }

    //     uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration);

    //     address network = alice;
    //     _registerNetwork(network, alice);

    //     _registerOperator(alice);

    //     for (uint256 i; i < hintStruct.num / 2; ++i) {
    //         _optInOperatorVault(alice);
    //         if (hintStruct.num % 2 == 0) {
    //             _optInOperatorNetwork(alice, address(network));
    //         }

    //         blockTimestamp = blockTimestamp + epochDuration;
    //         vm.warp(blockTimestamp);

    //         _optOutOperatorVault(alice);
    //         if (hintStruct.num % 2 == 0) {
    //             _optOutOperatorNetwork(alice, address(network));
    //         }
    //     }

    //     for (uint256 i; i < hintStruct.num / 2; ++i) {
    //         _optInOperatorVault(alice);
    //         if (hintStruct.num % 2 == 0) {
    //             _optInOperatorNetwork(alice, address(network));
    //         }

    //         blockTimestamp = blockTimestamp + epochDuration;
    //         vm.warp(blockTimestamp);

    //         _optOutOperatorVault(alice);
    //         if (hintStruct.num % 2 == 0) {
    //             _optOutOperatorNetwork(alice, address(network));
    //         }

    //         blockTimestamp = blockTimestamp + 1;
    //         vm.warp(blockTimestamp);
    //     }

    //     uint48 timestamp =
    //         uint48(hintStruct.back ? blockTimestamp - hintStruct.secondsAgo : blockTimestamp + hintStruct.secondsAgo);

    //     OptInServiceHints optInServiceHints = new OptInServiceHints();
    //     VaultHints vaultHints = new VaultHints();
    //     baseDelegatorHints = new BaseDelegatorHints(address(optInServiceHints), address(vaultHints));
    //     bytes memory hints = baseDelegatorHints.stakeBaseHints(address(delegator), network, alice, timestamp);

    //     GasStruct memory gasStruct = GasStruct({gasSpent1: 1, gasSpent2: 1});
    //     bytes memory stakeBaseHints = abi.encode(
    //         IBaseDelegator.StakeBaseHints({
    //             operatorVaultOptInHint: stakeBaseHintsUint32.withOperatorVaultOptInHint
    //                 ? abi.encode(stakeBaseHintsUint32.operatorVaultOptInHint)
    //                 : new bytes(0),
    //             operatorNetworkOptInHint: stakeBaseHintsUint32.withOperatorNetworkOptInHint
    //                 ? abi.encode(stakeBaseHintsUint32.operatorNetworkOptInHint)
    //                 : new bytes(0)
    //         })
    //     );
    //     try baseDelegatorHints._stakeBaseHints(address(delegator), network, alice, timestamp, stakeBaseHints) {
    //         gasStruct.gasSpent1 = vm.lastCallGas().gasTotalUsed;
    //     } catch {
    //         baseDelegatorHints._stakeBaseHints(address(delegator), network, alice, timestamp, new bytes(0));
    //         gasStruct.gasSpent1 = vm.lastCallGas().gasTotalUsed;
    //     }

    //     baseDelegatorHints._stakeBaseHints(address(delegator), network, alice, timestamp, hints);
    //     gasStruct.gasSpent2 = vm.lastCallGas().gasTotalUsed;
    //     assertGe(gasStruct.gasSpent1, gasStruct.gasSpent2);
    // }

    // struct StakeHintsUint32 {
    //     bool withBaseHints;
    //     StakeBaseHintsUint32 baseHints;
    //     bool withActiveStakeHint;
    //     uint32 activeStakeHint;
    //     bool withNetworkLimitHint;
    //     uint32 networkLimitHint;
    //     bool withOperatorNetworkLimitHint;
    //     uint32 operatorNetworkLimitHint;
    // }

    // function test_StakeHints(
    //     uint256 amount1,
    //     uint48 epochDuration,
    //     HintStruct memory hintStruct,
    //     StakeHintsUint32 memory stakeHintsUint32
    // ) public {
    //     amount1 = bound(amount1, 1, 100 * 10 ** 18);
    //     epochDuration = uint48(bound(epochDuration, 1, 7 days));
    //     hintStruct.num = bound(hintStruct.num, 0, 25);
    //     hintStruct.secondsAgo = bound(hintStruct.secondsAgo, 0, 1_720_700_948);
    //     if (stakeHintsUint32.baseHints.withOperatorVaultOptInHint) {
    //         stakeHintsUint32.baseHints.operatorVaultOptInHint =
    //             uint32(bound(stakeHintsUint32.baseHints.operatorVaultOptInHint, 0, 10 * hintStruct.num));
    //     }
    //     if (stakeHintsUint32.baseHints.withOperatorNetworkOptInHint) {
    //         stakeHintsUint32.baseHints.operatorNetworkOptInHint =
    //             uint32(bound(stakeHintsUint32.baseHints.operatorNetworkOptInHint, 0, 10 * hintStruct.num));
    //     }
    //     if (stakeHintsUint32.withActiveStakeHint) {
    //         stakeHintsUint32.activeStakeHint = uint32(bound(stakeHintsUint32.activeStakeHint, 0, 10 * hintStruct.num));
    //     }
    //     if (stakeHintsUint32.withNetworkLimitHint) {
    //         stakeHintsUint32.networkLimitHint = uint32(bound(stakeHintsUint32.networkLimitHint, 0, 10 * hintStruct.num));
    //     }
    //     if (stakeHintsUint32.withOperatorNetworkLimitHint) {
    //         stakeHintsUint32.operatorNetworkLimitHint =
    //             uint32(bound(stakeHintsUint32.operatorNetworkLimitHint, 0, 10 * hintStruct.num));
    //     }

    //     uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration);

    //     address network = alice;
    //     _registerNetwork(network, alice);

    //     _registerOperator(alice);

    //     for (uint256 i; i < hintStruct.num / 2; ++i) {
    //         _optInOperatorVault(alice);
    //         if (hintStruct.num % 2 == 0) {
    //             _optInOperatorNetwork(alice, address(network));
    //         }

    //         blockTimestamp = blockTimestamp + epochDuration;
    //         vm.warp(blockTimestamp);

    //         _optOutOperatorVault(alice);
    //         if (hintStruct.num % 2 == 0) {
    //             _optOutOperatorNetwork(alice, address(network));
    //         }
    //     }

    //     for (uint256 i; i < hintStruct.num / 2; ++i) {
    //         _optInOperatorVault(alice);
    //         if (hintStruct.num % 2 == 0) {
    //             _optInOperatorNetwork(alice, address(network));
    //         }

    //         blockTimestamp = blockTimestamp + epochDuration;
    //         vm.warp(blockTimestamp);

    //         _optOutOperatorVault(alice);
    //         if (hintStruct.num % 2 == 0) {
    //             _optOutOperatorNetwork(alice, address(network));
    //         }

    //         blockTimestamp = blockTimestamp + 1;
    //         vm.warp(blockTimestamp);
    //     }

    //     uint48 timestamp =
    //         uint48(hintStruct.back ? blockTimestamp - hintStruct.secondsAgo : blockTimestamp + hintStruct.secondsAgo);

    //     OptInServiceHints optInServiceHints = new OptInServiceHints();
    //     VaultHints vaultHints = new VaultHints();
    //     baseDelegatorHints = new BaseDelegatorHints(address(optInServiceHints), address(vaultHints));
    //     FullRestakeDelegatorHints fullRestakeDelegatorHints =
    //         FullRestakeDelegatorHints(baseDelegatorHints.FULL_RESTAKE_DELEGATOR_HINTS());
    //     bytes memory hints = fullRestakeDelegatorHints.stakeHints(address(delegator), network, alice, timestamp);

    //     GasStruct memory gasStruct = GasStruct({gasSpent1: 1, gasSpent2: 1});
    //     bytes memory stakeBaseHints;
    //     if (stakeHintsUint32.withBaseHints) {
    //         stakeBaseHints = abi.encode(
    //             IBaseDelegator.StakeBaseHints({
    //                 operatorVaultOptInHint: stakeHintsUint32.baseHints.withOperatorVaultOptInHint
    //                     ? abi.encode(stakeHintsUint32.baseHints.operatorVaultOptInHint)
    //                     : new bytes(0),
    //                 operatorNetworkOptInHint: stakeHintsUint32.baseHints.withOperatorNetworkOptInHint
    //                     ? abi.encode(stakeHintsUint32.baseHints.operatorNetworkOptInHint)
    //                     : new bytes(0)
    //             })
    //         );
    //     }

    //     bytes memory stakeHints = abi.encode(
    //         IFullRestakeDelegator.StakeHints({
    //             baseHints: stakeBaseHints,
    //             activeStakeHint: stakeHintsUint32.withActiveStakeHint
    //                 ? abi.encode(stakeHintsUint32.activeStakeHint)
    //                 : new bytes(0),
    //             networkLimitHint: stakeHintsUint32.withNetworkLimitHint
    //                 ? abi.encode(stakeHintsUint32.networkLimitHint)
    //                 : new bytes(0),
    //             operatorNetworkLimitHint: stakeHintsUint32.withOperatorNetworkLimitHint
    //                 ? abi.encode(stakeHintsUint32.operatorNetworkLimitHint)
    //                 : new bytes(0)
    //         })
    //     );

    //     try delegator.stakeAt(network, alice, timestamp, stakeHints) {
    //         gasStruct.gasSpent1 = vm.lastCallGas().gasTotalUsed;
    //     } catch {
    //         delegator.stakeAt(network, alice, timestamp, new bytes(0));
    //         gasStruct.gasSpent1 = vm.lastCallGas().gasTotalUsed;
    //     }

    //     delegator.stakeAt(network, alice, timestamp, hints);
    //     gasStruct.gasSpent2 = vm.lastCallGas().gasTotalUsed;
    //     assertGe(gasStruct.gasSpent1, gasStruct.gasSpent2);
    // }

    // function test_BaseStakeHints(
    //     uint256 amount1,
    //     uint48 epochDuration,
    //     HintStruct memory hintStruct,
    //     StakeHintsUint32 memory stakeHintsUint32
    // ) public {
    //     amount1 = bound(amount1, 1, 100 * 10 ** 18);
    //     epochDuration = uint48(bound(epochDuration, 1, 7 days));
    //     hintStruct.num = bound(hintStruct.num, 0, 25);
    //     hintStruct.secondsAgo = bound(hintStruct.secondsAgo, 0, 1_720_700_948);
    //     if (stakeHintsUint32.baseHints.withOperatorVaultOptInHint) {
    //         stakeHintsUint32.baseHints.operatorVaultOptInHint =
    //             uint32(bound(stakeHintsUint32.baseHints.operatorVaultOptInHint, 0, 10 * hintStruct.num));
    //     }
    //     if (stakeHintsUint32.baseHints.withOperatorNetworkOptInHint) {
    //         stakeHintsUint32.baseHints.operatorNetworkOptInHint =
    //             uint32(bound(stakeHintsUint32.baseHints.operatorNetworkOptInHint, 0, 10 * hintStruct.num));
    //     }
    //     if (stakeHintsUint32.withActiveStakeHint) {
    //         stakeHintsUint32.activeStakeHint = uint32(bound(stakeHintsUint32.activeStakeHint, 0, 10 * hintStruct.num));
    //     }
    //     if (stakeHintsUint32.withNetworkLimitHint) {
    //         stakeHintsUint32.networkLimitHint = uint32(bound(stakeHintsUint32.networkLimitHint, 0, 10 * hintStruct.num));
    //     }
    //     if (stakeHintsUint32.withOperatorNetworkLimitHint) {
    //         stakeHintsUint32.operatorNetworkLimitHint =
    //             uint32(bound(stakeHintsUint32.operatorNetworkLimitHint, 0, 10 * hintStruct.num));
    //     }

    //     uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration);

    //     address network = alice;
    //     _registerNetwork(network, alice);

    //     _registerOperator(alice);

    //     for (uint256 i; i < hintStruct.num / 2; ++i) {
    //         _optInOperatorVault(alice);
    //         if (hintStruct.num % 2 == 0) {
    //             _optInOperatorNetwork(alice, address(network));
    //         }

    //         blockTimestamp = blockTimestamp + epochDuration;
    //         vm.warp(blockTimestamp);

    //         _optOutOperatorVault(alice);
    //         if (hintStruct.num % 2 == 0) {
    //             _optOutOperatorNetwork(alice, address(network));
    //         }
    //     }

    //     for (uint256 i; i < hintStruct.num / 2; ++i) {
    //         _optInOperatorVault(alice);
    //         if (hintStruct.num % 2 == 0) {
    //             _optInOperatorNetwork(alice, address(network));
    //         }

    //         blockTimestamp = blockTimestamp + epochDuration;
    //         vm.warp(blockTimestamp);

    //         _optOutOperatorVault(alice);
    //         if (hintStruct.num % 2 == 0) {
    //             _optOutOperatorNetwork(alice, address(network));
    //         }

    //         blockTimestamp = blockTimestamp + 1;
    //         vm.warp(blockTimestamp);
    //     }

    //     uint48 timestamp =
    //         uint48(hintStruct.back ? blockTimestamp - hintStruct.secondsAgo : blockTimestamp + hintStruct.secondsAgo);

    //     OptInServiceHints optInServiceHints = new OptInServiceHints();
    //     VaultHints vaultHints = new VaultHints();
    //     baseDelegatorHints = new BaseDelegatorHints(address(optInServiceHints), address(vaultHints));
    //     bytes memory hints = baseDelegatorHints.stakeHints(address(delegator), network, alice, timestamp);

    //     GasStruct memory gasStruct = GasStruct({gasSpent1: 1, gasSpent2: 1});
    //     bytes memory stakeBaseHints;
    //     if (stakeHintsUint32.withBaseHints) {
    //         stakeBaseHints = abi.encode(
    //             IBaseDelegator.StakeBaseHints({
    //                 operatorVaultOptInHint: stakeHintsUint32.baseHints.withOperatorVaultOptInHint
    //                     ? abi.encode(stakeHintsUint32.baseHints.operatorVaultOptInHint)
    //                     : new bytes(0),
    //                 operatorNetworkOptInHint: stakeHintsUint32.baseHints.withOperatorNetworkOptInHint
    //                     ? abi.encode(stakeHintsUint32.baseHints.operatorNetworkOptInHint)
    //                     : new bytes(0)
    //             })
    //         );
    //     }

    //     bytes memory stakeHints = abi.encode(
    //         IFullRestakeDelegator.StakeHints({
    //             baseHints: stakeBaseHints,
    //             activeStakeHint: stakeHintsUint32.withActiveStakeHint
    //                 ? abi.encode(stakeHintsUint32.activeStakeHint)
    //                 : new bytes(0),
    //             networkLimitHint: stakeHintsUint32.withNetworkLimitHint
    //                 ? abi.encode(stakeHintsUint32.networkLimitHint)
    //                 : new bytes(0),
    //             operatorNetworkLimitHint: stakeHintsUint32.withOperatorNetworkLimitHint
    //                 ? abi.encode(stakeHintsUint32.operatorNetworkLimitHint)
    //                 : new bytes(0)
    //         })
    //     );

    //     try delegator.stakeAt(network, alice, timestamp, stakeHints) {
    //         gasStruct.gasSpent1 = vm.lastCallGas().gasTotalUsed;
    //     } catch {
    //         delegator.stakeAt(network, alice, timestamp, new bytes(0));
    //         gasStruct.gasSpent1 = vm.lastCallGas().gasTotalUsed;
    //     }

    //     delegator.stakeAt(network, alice, timestamp, hints);
    //     gasStruct.gasSpent2 = vm.lastCallGas().gasTotalUsed;
    //     assertGe(gasStruct.gasSpent1, gasStruct.gasSpent2);
    // }

    // struct OnSlashHintsUint32 {
    //     bool withHints;
    //     StakeHintsUint32 hints;
    // }

    // function test_OnSlashHints(
    //     uint256 amount1,
    //     uint48 epochDuration,
    //     HintStruct memory hintStruct,
    //     OnSlashHintsUint32 memory onSlashHintsUint32
    // ) public {
    //     amount1 = bound(amount1, 1, 10 * 10 ** 18);
    //     epochDuration = uint48(bound(epochDuration, 1, 7 days));
    //     hintStruct.num = bound(hintStruct.num, 0, 25);
    //     hintStruct.secondsAgo = bound(hintStruct.secondsAgo, 0, 1_720_700_948);
    //     if (onSlashHintsUint32.hints.baseHints.withOperatorVaultOptInHint) {
    //         onSlashHintsUint32.hints.baseHints.operatorVaultOptInHint =
    //             uint32(bound(onSlashHintsUint32.hints.baseHints.operatorVaultOptInHint, 0, 10 * hintStruct.num));
    //     }
    //     if (onSlashHintsUint32.hints.baseHints.withOperatorNetworkOptInHint) {
    //         onSlashHintsUint32.hints.baseHints.operatorNetworkOptInHint =
    //             uint32(bound(onSlashHintsUint32.hints.baseHints.operatorNetworkOptInHint, 0, 10 * hintStruct.num));
    //     }
    //     if (onSlashHintsUint32.hints.withActiveStakeHint) {
    //         onSlashHintsUint32.hints.activeStakeHint =
    //             uint32(bound(onSlashHintsUint32.hints.activeStakeHint, 0, 10 * hintStruct.num));
    //     }
    //     if (onSlashHintsUint32.hints.withNetworkLimitHint) {
    //         onSlashHintsUint32.hints.networkLimitHint =
    //             uint32(bound(onSlashHintsUint32.hints.networkLimitHint, 0, 10 * hintStruct.num));
    //     }
    //     if (onSlashHintsUint32.hints.withOperatorNetworkLimitHint) {
    //         onSlashHintsUint32.hints.operatorNetworkLimitHint =
    //             uint32(bound(onSlashHintsUint32.hints.operatorNetworkLimitHint, 0, 10 * hintStruct.num));
    //     }

    //     uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration);

    //     // address network = alice;
    //     _registerNetwork(alice, alice);
    //     _setMaxNetworkLimit(alice, type(uint256).max);

    //     _registerOperator(alice);

    //     for (uint256 i; i < hintStruct.num / 2; ++i) {
    //         _optInOperatorVault(alice);
    //         if (hintStruct.num % 2 == 0) {
    //             _optInOperatorNetwork(alice, address(alice));
    //         }

    //         _deposit(alice, amount1);
    //         _setNetworkLimit(alice, alice, amount1);
    //         _setOperatorNetworkLimit(alice, alice, alice, amount1);

    //         blockTimestamp = blockTimestamp + epochDuration;
    //         vm.warp(blockTimestamp);

    //         _optOutOperatorVault(alice);
    //         if (hintStruct.num % 2 == 0) {
    //             _optOutOperatorNetwork(alice, address(alice));
    //         }
    //     }

    //     for (uint256 i; i < hintStruct.num / 2; ++i) {
    //         _optInOperatorVault(alice);
    //         if (hintStruct.num % 2 == 0) {
    //             _optInOperatorNetwork(alice, address(alice));
    //         }

    //         _deposit(alice, amount1);
    //         _setNetworkLimit(alice, alice, amount1);
    //         _setOperatorNetworkLimit(alice, alice, alice, amount1);

    //         blockTimestamp = blockTimestamp + epochDuration;
    //         vm.warp(blockTimestamp);

    //         _optOutOperatorVault(alice);
    //         if (hintStruct.num % 2 == 0) {
    //             _optOutOperatorNetwork(alice, address(alice));
    //         }

    //         blockTimestamp = blockTimestamp + 1;
    //         vm.warp(blockTimestamp);
    //     }

    //     uint48 timestamp =
    //         uint48(hintStruct.back ? blockTimestamp - hintStruct.secondsAgo : blockTimestamp + hintStruct.secondsAgo);

    //     baseDelegatorHints = new BaseDelegatorHints(address(new OptInServiceHints()), address(new VaultHints()));

    //     GasStruct memory gasStruct = GasStruct({gasSpent1: 1, gasSpent2: 1});

    //     bytes memory stakeHints;
    //     if (onSlashHintsUint32.withHints) {
    //         stakeHints = abi.encode(
    //             IFullRestakeDelegator.StakeHints({
    //                 baseHints: onSlashHintsUint32.hints.withBaseHints
    //                     ? abi.encode(
    //                         IBaseDelegator.StakeBaseHints({
    //                             operatorVaultOptInHint: onSlashHintsUint32.hints.baseHints.withOperatorVaultOptInHint
    //                                 ? abi.encode(onSlashHintsUint32.hints.baseHints.operatorVaultOptInHint)
    //                                 : new bytes(0),
    //                             operatorNetworkOptInHint: onSlashHintsUint32.hints.baseHints.withOperatorNetworkOptInHint
    //                                 ? abi.encode(onSlashHintsUint32.hints.baseHints.operatorNetworkOptInHint)
    //                                 : new bytes(0)
    //                         })
    //                     )
    //                     : new bytes(0),
    //                 activeStakeHint: onSlashHintsUint32.hints.withActiveStakeHint
    //                     ? abi.encode(onSlashHintsUint32.hints.activeStakeHint)
    //                     : new bytes(0),
    //                 networkLimitHint: onSlashHintsUint32.hints.withNetworkLimitHint
    //                     ? abi.encode(onSlashHintsUint32.hints.networkLimitHint)
    //                     : new bytes(0),
    //                 operatorNetworkLimitHint: onSlashHintsUint32.hints.withOperatorNetworkLimitHint
    //                     ? abi.encode(onSlashHintsUint32.hints.operatorNetworkLimitHint)
    //                     : new bytes(0)
    //             })
    //         );
    //     }

    //     try baseDelegatorHints._onSlash(
    //         address(delegator),
    //         alice,
    //         alice,
    //         amount1,
    //         timestamp,
    //         abi.encode(IBaseDelegator.OnSlashHints({stakeHints: stakeHints}))
    //     ) {
    //         gasStruct.gasSpent1 = vm.lastCallGas().gasTotalUsed;
    //     } catch {
    //         baseDelegatorHints._onSlash(address(delegator), alice, alice, amount1, timestamp, new bytes(0));
    //         gasStruct.gasSpent1 = vm.lastCallGas().gasTotalUsed;
    //     }

    //     bytes memory hints = baseDelegatorHints.onSlashHints(address(delegator), alice, alice, amount1, timestamp);
    //     baseDelegatorHints._onSlash(address(delegator), alice, alice, amount1, timestamp, hints);
    //     gasStruct.gasSpent2 = vm.lastCallGas().gasTotalUsed;
    //     assertGe(gasStruct.gasSpent1, gasStruct.gasSpent2);
    // }

    function _getVaultAndDelegator(
        uint48 epochDuration
    ) internal returns (Vault, FullRestakeDelegator) {
        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](1);
        operatorNetworkLimitSetRoleHolders[0] = alice;
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
                withSlasher: false,
                slasherIndex: 0,
                slasherParams: abi.encode(ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})}))
            })
        );

        return (Vault(vault_), FullRestakeDelegator(delegator_));
    }

    function _getVaultAndDelegatorAndSlasher(
        uint48 epochDuration
    ) internal returns (Vault, FullRestakeDelegator, Slasher) {
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
                slasherIndex: 0,
                slasherParams: abi.encode(ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})}))
            })
        );

        return (Vault(vault_), FullRestakeDelegator(delegator_), Slasher(slasher_));
    }

    function _getSlasher(
        address vault_
    ) internal returns (Slasher) {
        return Slasher(
            slasherFactory.create(
                0,
                abi.encode(
                    address(vault_),
                    abi.encode(ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})}))
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

    function _slash(
        address user,
        address network,
        address operator,
        uint256 amount,
        uint48 captureTimestamp,
        bytes memory hints
    ) internal returns (uint256 slashAmount) {
        vm.startPrank(user);
        slashAmount = slasher.slash(network.subnetwork(0), operator, amount, captureTimestamp, hints);
        vm.stopPrank();
    }

    function _setMaxNetworkLimit(address user, uint96 identifier, uint256 amount) internal {
        vm.startPrank(user);
        delegator.setMaxNetworkLimit(identifier, amount);
        vm.stopPrank();
    }

    function _setHook(address user, address hook) internal {
        vm.startPrank(user);
        delegator.setHook(hook);
        vm.stopPrank();
    }
}
