// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {VaultFactory} from "src/contracts/VaultFactory.sol";
import {DelegatorFactory} from "src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "src/contracts/SlasherFactory.sol";
import {NetworkRegistry} from "src/contracts/NetworkRegistry.sol";
import {OperatorRegistry} from "src/contracts/OperatorRegistry.sol";
import {MetadataService} from "src/contracts/service/MetadataService.sol";
import {NetworkMiddlewareService} from "src/contracts/service/NetworkMiddlewareService.sol";
import {OptInService} from "src/contracts/service/OptInService.sol";

import {Vault} from "src/contracts/vault/Vault.sol";
import {NetworkRestakeDelegator} from "src/contracts/delegator/NetworkRestakeDelegator.sol";
import {FullRestakeDelegator} from "src/contracts/delegator/FullRestakeDelegator.sol";
import {Slasher} from "src/contracts/slasher/Slasher.sol";
import {VetoSlasher} from "src/contracts/slasher/VetoSlasher.sol";

import {IVault} from "src/interfaces/vault/IVault.sol";
import {SimpleCollateral} from "test/mocks/SimpleCollateral.sol";
import {Token} from "test/mocks/Token.sol";
import {VaultConfigurator} from "src/contracts/VaultConfigurator.sol";
import {IVaultConfigurator} from "src/interfaces/IVaultConfigurator.sol";
import {INetworkRestakeDelegator} from "src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IFullRestakeDelegator} from "src/interfaces/delegator/IFullRestakeDelegator.sol";
import {IBaseDelegator} from "src/interfaces/delegator/IBaseDelegator.sol";

import {IVaultStorage} from "src/interfaces/vault/IVaultStorage.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract FullRestakeDelegatorTest is Test {
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
    OptInService networkVaultOptInService;
    OptInService operatorVaultOptInService;
    OptInService operatorNetworkOptInService;

    SimpleCollateral collateral;
    VaultConfigurator vaultConfigurator;

    Vault vault;
    FullRestakeDelegator delegator;
    Slasher slasher;

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
        networkVaultOptInService = new OptInService(address(networkRegistry), address(vaultFactory));
        operatorVaultOptInService = new OptInService(address(operatorRegistry), address(vaultFactory));
        operatorNetworkOptInService = new OptInService(address(operatorRegistry), address(networkRegistry));

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

        address slasherImpl = address(
            new Slasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(networkVaultOptInService),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(slasherFactory),
                slasherFactory.totalTypes()
            )
        );
        slasherFactory.whitelist(slasherImpl);

        address vetoSlasherImpl = address(
            new VetoSlasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(networkVaultOptInService),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(networkRegistry),
                address(slasherFactory),
                slasherFactory.totalTypes()
            )
        );
        slasherFactory.whitelist(vetoSlasherImpl);

        Token token = new Token("Token");
        collateral = new SimpleCollateral(address(token));

        collateral.mint(token.totalSupply());

        vaultConfigurator =
            new VaultConfigurator(address(vaultFactory), address(delegatorFactory), address(slasherFactory));
    }

    function test_Create(uint48 epochDuration) public {
        epochDuration = uint48(bound(epochDuration, 1, type(uint48).max));

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        assertEq(delegator.VERSION(), 1);
        assertEq(delegator.NETWORK_REGISTRY(), address(networkRegistry));
        assertEq(delegator.VAULT_FACTORY(), address(vaultFactory));
        assertEq(delegator.OPERATOR_VAULT_OPT_IN_SERVICE(), address(operatorVaultOptInService));
        assertEq(delegator.OPERATOR_NETWORK_OPT_IN_SERVICE(), address(operatorNetworkOptInService));
        assertEq(delegator.vault(), address(vault));
        assertEq(delegator.maxNetworkLimit(alice), 0);
        assertEq(delegator.stakeAt(alice, alice, 0), 0);
        assertEq(delegator.stake(alice, alice), 0);
        assertEq(delegator.NETWORK_LIMIT_SET_ROLE(), keccak256("NETWORK_LIMIT_SET_ROLE"));
        assertEq(delegator.OPERATOR_NETWORK_LIMIT_SET_ROLE(), keccak256("OPERATOR_NETWORK_LIMIT_SET_ROLE"));
        assertEq(delegator.networkLimitAt(alice, 0), 0);
        assertEq(delegator.networkLimit(alice), 0);
        assertEq(delegator.totalOperatorNetworkLimitAt(alice, 0), 0);
        assertEq(delegator.totalOperatorNetworkLimit(alice), 0);
        assertEq(delegator.operatorNetworkLimitAt(alice, alice, 0), 0);
        assertEq(delegator.operatorNetworkLimit(alice, alice), 0);
    }

    function test_CreateRevertNotVault(uint48 epochDuration) public {
        epochDuration = uint48(bound(epochDuration, 1, type(uint48).max));

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        vm.expectRevert(IBaseDelegator.NotVault.selector);
        delegatorFactory.create(
            1,
            true,
            abi.encode(
                address(1),
                abi.encode(
                    IFullRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: bob,
                            hook: address(0),
                            hookSetRoleHolder: bob
                        }),
                        networkLimitSetRoleHolder: bob,
                        operatorNetworkLimitSetRoleHolder: bob
                    })
                )
            )
        );
    }

    function test_CreateRevertMissingRoleHolders(uint48 epochDuration) public {
        epochDuration = uint48(bound(epochDuration, 1, type(uint48).max));

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        vm.expectRevert(IFullRestakeDelegator.MissingRoleHolders.selector);
        delegatorFactory.create(
            1,
            true,
            abi.encode(
                address(vault),
                abi.encode(
                    IFullRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: address(0),
                            hook: address(0),
                            hookSetRoleHolder: address(1)
                        }),
                        networkLimitSetRoleHolder: address(0),
                        operatorNetworkLimitSetRoleHolder: bob
                    })
                )
            )
        );
    }

    function test_OnSlashRevertNotSlasher(uint48 epochDuration) public {
        epochDuration = uint48(bound(epochDuration, 1, type(uint48).max));

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        vm.startPrank(alice);
        vm.expectRevert(IBaseDelegator.NotSlasher.selector);
        delegator.onSlash(address(0), address(0), 0, 0);
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

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        address network = bob;
        _registerNetwork(network, bob);

        _setMaxNetworkLimit(network, type(uint256).max);

        _setNetworkLimit(alice, network, amount1);

        assertEq(delegator.networkLimitAt(network, uint48(blockTimestamp)), amount1);
        assertEq(delegator.networkLimitAt(network, uint48(blockTimestamp + 1)), amount1);
        assertEq(delegator.networkLimit(network), amount1);

        _setNetworkLimit(alice, network, amount2);

        assertEq(delegator.networkLimitAt(network, uint48(blockTimestamp)), amount2);
        assertEq(delegator.networkLimitAt(network, uint48(blockTimestamp + 1)), amount2);
        assertEq(delegator.networkLimit(network), amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _setNetworkLimit(alice, network, amount3);

        assertEq(delegator.networkLimitAt(network, uint48(blockTimestamp - 1)), amount2);
        assertEq(delegator.networkLimitAt(network, uint48(blockTimestamp)), amount3);
        assertEq(delegator.networkLimitAt(network, uint48(blockTimestamp + 1)), amount3);
        assertEq(delegator.networkLimit(network), amount3);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _setNetworkLimit(alice, network, amount4);

        assertEq(delegator.networkLimitAt(network, uint48(blockTimestamp - 2)), amount2);
        assertEq(delegator.networkLimitAt(network, uint48(blockTimestamp - 1)), amount3);
        assertEq(delegator.networkLimitAt(network, uint48(blockTimestamp)), amount4);
        assertEq(delegator.networkLimitAt(network, uint48(blockTimestamp + 1)), amount4);
        assertEq(delegator.networkLimit(network), amount4);
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

        _setMaxNetworkLimit(network, maxNetworkLimit);
        _optInNetworkVault(network);

        vm.expectRevert(IFullRestakeDelegator.ExceedsMaxNetworkLimit.selector);
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

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        address network = bob;
        _registerNetwork(network, bob);
        address operator = bob;
        _registerOperator(operator);

        _setOperatorNetworkLimit(alice, network, operator, amount1);

        assertEq(delegator.operatorNetworkLimitAt(network, operator, uint48(blockTimestamp)), amount1);
        assertEq(delegator.operatorNetworkLimitAt(network, operator, uint48(blockTimestamp + 1)), amount1);
        assertEq(delegator.operatorNetworkLimit(network, operator), amount1);
        assertEq(delegator.totalOperatorNetworkLimitAt(network, uint48(blockTimestamp)), amount1);
        assertEq(delegator.totalOperatorNetworkLimitAt(network, uint48(blockTimestamp + 1)), amount1);
        assertEq(delegator.totalOperatorNetworkLimit(network), amount1);

        _setOperatorNetworkLimit(alice, network, operator, amount2);

        assertEq(delegator.operatorNetworkLimitAt(network, operator, uint48(blockTimestamp)), amount2);
        assertEq(delegator.operatorNetworkLimitAt(network, operator, uint48(blockTimestamp + 1)), amount2);
        assertEq(delegator.operatorNetworkLimit(network, operator), amount2);
        assertEq(delegator.totalOperatorNetworkLimitAt(network, uint48(blockTimestamp)), amount2);
        assertEq(delegator.totalOperatorNetworkLimitAt(network, uint48(blockTimestamp + 1)), amount2);
        assertEq(delegator.totalOperatorNetworkLimit(network), amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _setOperatorNetworkLimit(alice, network, operator, amount3);

        assertEq(delegator.operatorNetworkLimitAt(network, operator, uint48(blockTimestamp - 1)), amount2);
        assertEq(delegator.operatorNetworkLimitAt(network, operator, uint48(blockTimestamp)), amount3);
        assertEq(delegator.operatorNetworkLimitAt(network, operator, uint48(blockTimestamp + 1)), amount3);
        assertEq(delegator.operatorNetworkLimit(network, operator), amount3);
        assertEq(delegator.totalOperatorNetworkLimitAt(network, uint48(blockTimestamp - 1)), amount2);
        assertEq(delegator.totalOperatorNetworkLimitAt(network, uint48(blockTimestamp)), amount3);
        assertEq(delegator.totalOperatorNetworkLimitAt(network, uint48(blockTimestamp + 1)), amount3);
        assertEq(delegator.totalOperatorNetworkLimit(network), amount3);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _setOperatorNetworkLimit(alice, network, operator, amount4);

        assertEq(delegator.operatorNetworkLimitAt(network, operator, uint48(blockTimestamp - 2)), amount2);
        assertEq(delegator.operatorNetworkLimitAt(network, operator, uint48(blockTimestamp - 1)), amount3);
        assertEq(delegator.operatorNetworkLimitAt(network, operator, uint48(blockTimestamp)), amount4);
        assertEq(delegator.operatorNetworkLimitAt(network, operator, uint48(blockTimestamp + 1)), amount4);
        assertEq(delegator.operatorNetworkLimit(network, operator), amount4);
        assertEq(delegator.totalOperatorNetworkLimitAt(network, uint48(blockTimestamp - 2)), amount2);
        assertEq(delegator.totalOperatorNetworkLimitAt(network, uint48(blockTimestamp - 1)), amount3);
        assertEq(delegator.totalOperatorNetworkLimitAt(network, uint48(blockTimestamp)), amount4);
        assertEq(delegator.totalOperatorNetworkLimitAt(network, uint48(blockTimestamp + 1)), amount4);
        assertEq(delegator.totalOperatorNetworkLimit(network), amount4);
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

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        address network = bob;
        _registerNetwork(network, bob);
        _registerOperator(alice);
        _registerOperator(bob);

        _setOperatorNetworkLimit(alice, network, alice, amount1);

        assertEq(delegator.operatorNetworkLimitAt(network, alice, uint48(blockTimestamp + 1)), amount1);
        assertEq(delegator.operatorNetworkLimit(network, alice), amount1);
        assertEq(delegator.totalOperatorNetworkLimitAt(network, uint48(blockTimestamp + 1)), amount1);
        assertEq(delegator.totalOperatorNetworkLimit(network), amount1);

        _setOperatorNetworkLimit(alice, network, bob, amount2);

        assertEq(delegator.operatorNetworkLimitAt(network, bob, uint48(blockTimestamp + 1)), amount2);
        assertEq(delegator.operatorNetworkLimit(network, bob), amount2);
        assertEq(delegator.totalOperatorNetworkLimitAt(network, uint48(blockTimestamp + 1)), amount1 + amount2);
        assertEq(delegator.totalOperatorNetworkLimit(network), amount1 + amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _setOperatorNetworkLimit(alice, network, bob, amount3);

        assertEq(delegator.operatorNetworkLimitAt(network, bob, uint48(blockTimestamp - 1)), amount2);
        assertEq(delegator.operatorNetworkLimitAt(network, bob, uint48(blockTimestamp + 1)), amount3);
        assertEq(delegator.operatorNetworkLimit(network, bob), amount3);
        assertEq(delegator.totalOperatorNetworkLimitAt(network, uint48(blockTimestamp - 1)), amount1 + amount2);
        assertEq(delegator.totalOperatorNetworkLimitAt(network, uint48(blockTimestamp + 1)), amount1 + amount3);
        assertEq(delegator.totalOperatorNetworkLimit(network), amount1 + amount3);
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

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        address network = alice;
        _registerNetwork(network, alice);

        _setMaxNetworkLimit(network, maxNetworkLimit1);

        assertEq(delegator.maxNetworkLimit(network), maxNetworkLimit1);

        _setNetworkLimit(alice, network, networkLimit1);

        assertEq(delegator.networkLimitAt(network, uint48(blockTimestamp + 2 * vault.epochDuration())), networkLimit1);

        blockTimestamp = vault.currentEpochStart() + vault.epochDuration();
        vm.warp(blockTimestamp);

        _setNetworkLimit(alice, network, networkLimit1);

        assertEq(delegator.networkLimitAt(network, uint48(blockTimestamp + vault.epochDuration())), networkLimit1);
        assertEq(delegator.networkLimitAt(network, uint48(blockTimestamp + 2 * vault.epochDuration())), networkLimit1);

        _setMaxNetworkLimit(network, maxNetworkLimit2);

        assertEq(delegator.maxNetworkLimit(network), maxNetworkLimit2);
        assertEq(delegator.networkLimitAt(network, uint48(blockTimestamp + vault.epochDuration())), maxNetworkLimit2);
        assertEq(
            delegator.networkLimitAt(network, uint48(blockTimestamp + 2 * vault.epochDuration())), maxNetworkLimit2
        );
    }

    function test_SetMaxNetworkLimitRevertNotNetwork(uint48 epochDuration, uint256 maxNetworkLimit) public {
        epochDuration = uint48(bound(epochDuration, 1, type(uint48).max));
        maxNetworkLimit = bound(maxNetworkLimit, 1, type(uint256).max);

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        _registerNetwork(alice, alice);

        vm.expectRevert(IBaseDelegator.NotNetwork.selector);
        _setMaxNetworkLimit(bob, maxNetworkLimit);
    }

    function test_SetMaxNetworkLimitRevertAlreadySet(uint48 epochDuration, uint256 maxNetworkLimit) public {
        epochDuration = uint48(bound(epochDuration, 1, type(uint48).max));
        maxNetworkLimit = bound(maxNetworkLimit, 1, type(uint256).max);

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        _registerNetwork(alice, alice);

        _setMaxNetworkLimit(alice, maxNetworkLimit);

        vm.expectRevert(IBaseDelegator.AlreadySet.selector);
        _setMaxNetworkLimit(alice, maxNetworkLimit);
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
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 0, type(uint256).max / 2);
        operatorNetworkLimit2 = bound(operatorNetworkLimit2, 1, type(uint256).max / 2);
        operatorNetworkLimit3 = bound(operatorNetworkLimit3, 0, type(uint256).max / 2);

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        address network = alice;
        _registerNetwork(network, alice);
        _setMaxNetworkLimit(network, type(uint256).max);

        _registerOperator(alice);
        _registerOperator(bob);

        assertEq(delegator.stake(network, alice), 0);
        assertEq(delegator.stake(network, bob), 0);

        _optInOperatorVault(alice);
        _optInOperatorVault(bob);

        assertEq(delegator.stake(network, alice), 0);
        assertEq(delegator.stake(network, bob), 0);

        _optInOperatorNetwork(alice, address(network));
        _optInOperatorNetwork(bob, address(network));

        assertEq(delegator.stake(network, alice), 0);
        assertEq(delegator.stake(network, bob), 0);

        _deposit(alice, depositAmount);

        assertEq(delegator.stake(network, alice), 0);
        assertEq(delegator.stake(network, bob), 0);

        _setNetworkLimit(alice, network, networkLimit);

        assertEq(delegator.stake(network, alice), 0);
        assertEq(delegator.stake(network, bob), 0);

        _setOperatorNetworkLimit(alice, network, alice, operatorNetworkLimit1);

        assertEq(
            delegator.stakeAt(network, alice, uint48(blockTimestamp)),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1))
        );
        assertEq(
            delegator.stake(network, alice), Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1))
        );
        assertEq(delegator.stakeAt(network, bob, uint48(blockTimestamp)), 0);
        assertEq(delegator.stake(network, bob), 0);

        _setOperatorNetworkLimit(alice, network, bob, operatorNetworkLimit2);

        assertEq(
            delegator.stakeAt(network, alice, uint48(blockTimestamp)),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1))
        );
        assertEq(
            delegator.stake(network, alice), Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1))
        );
        assertEq(
            delegator.stakeAt(network, bob, uint48(blockTimestamp)),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit2))
        );
        assertEq(delegator.stake(network, bob), Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit2)));

        _setOperatorNetworkLimit(alice, network, bob, operatorNetworkLimit2 - 1);

        assertEq(
            delegator.stakeAt(network, alice, uint48(blockTimestamp)),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1))
        );
        assertEq(
            delegator.stake(network, alice), Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1))
        );
        assertEq(
            delegator.stakeAt(network, bob, uint48(blockTimestamp)),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit2 - 1))
        );
        assertEq(
            delegator.stake(network, bob), Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit2 - 1))
        );

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _setOperatorNetworkLimit(alice, network, bob, operatorNetworkLimit3);

        assertEq(
            delegator.stakeAt(network, alice, uint48(blockTimestamp - 1)),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1))
        );
        assertEq(
            delegator.stake(network, alice), Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1))
        );
        assertEq(
            delegator.stakeAt(network, bob, uint48(blockTimestamp - 1)),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit2 - 1))
        );
        assertEq(delegator.stake(network, bob), Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit3)));

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(
            delegator.stakeAt(network, alice, uint48(blockTimestamp - 2)),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1))
        );
        assertEq(
            delegator.stakeAt(network, alice, uint48(blockTimestamp - 1)),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1))
        );
        assertEq(
            delegator.stake(network, alice), Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1))
        );
        assertEq(
            delegator.stakeAt(network, bob, uint48(blockTimestamp - 2)),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit2 - 1))
        );
        assertEq(
            delegator.stakeAt(network, bob, uint48(blockTimestamp - 1)),
            Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit3))
        );
        assertEq(delegator.stake(network, bob), Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit3)));
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

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        address network = alice;
        _registerNetwork(network, alice);
        _setMaxNetworkLimit(network, type(uint256).max);

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

        _optInNetworkVault(network);

        assertEq(delegator.networkLimit(network), networkLimit);
        assertEq(delegator.totalOperatorNetworkLimit(network), operatorNetworkLimit1 + operatorNetworkLimit2);
        assertEq(delegator.operatorNetworkLimit(network, alice), operatorNetworkLimit1);
        assertEq(delegator.operatorNetworkLimit(network, bob), operatorNetworkLimit2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 slashAmount1Real =
            Math.min(slashAmount1, Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit1)));
        assertEq(_slash(alice, network, alice, slashAmount1, uint48(blockTimestamp - 1)), slashAmount1Real);

        assertEq(delegator.networkLimit(network), networkLimit);
        assertEq(delegator.totalOperatorNetworkLimit(network), operatorNetworkLimit1 + operatorNetworkLimit2);
        assertEq(delegator.operatorNetworkLimit(network, alice), operatorNetworkLimit1);
        assertEq(delegator.operatorNetworkLimit(network, bob), operatorNetworkLimit2);

        uint256 slashAmount2Real =
            Math.min(slashAmount2, Math.min(depositAmount, Math.min(networkLimit, operatorNetworkLimit2)));
        assertEq(_slash(alice, network, bob, slashAmount2, uint48(blockTimestamp - 1)), slashAmount2Real);

        assertEq(delegator.networkLimit(network), networkLimit);
        assertEq(delegator.totalOperatorNetworkLimit(network), operatorNetworkLimit1 + operatorNetworkLimit2);
        assertEq(delegator.operatorNetworkLimit(network, alice), operatorNetworkLimit1);
        assertEq(delegator.operatorNetworkLimit(network, bob), operatorNetworkLimit2);
    }

    function _getVaultAndDelegator(uint48 epochDuration) internal returns (Vault, FullRestakeDelegator) {
        (address vault_, address delegator_,) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: vaultFactory.lastVersion(),
                owner: alice,
                vaultParams: IVault.InitParams({
                    collateral: address(collateral),
                    delegator: address(0),
                    slasher: address(0),
                    burner: address(0xdEaD),
                    epochDuration: epochDuration,
                    slasherSetEpochsDelay: 3,
                    depositWhitelist: false,
                    defaultAdminRoleHolder: alice,
                    slasherSetRoleHolder: alice,
                    depositorWhitelistRoleHolder: alice
                }),
                delegatorIndex: 1,
                delegatorParams: abi.encode(
                    IFullRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: alice,
                            hook: address(0),
                            hookSetRoleHolder: alice
                        }),
                        networkLimitSetRoleHolder: alice,
                        operatorNetworkLimitSetRoleHolder: alice
                    })
                ),
                withSlasher: false,
                slasherIndex: 0,
                slasherParams: ""
            })
        );

        return (Vault(vault_), FullRestakeDelegator(delegator_));
    }

    function _getVaultAndDelegatorAndSlasher(uint48 epochDuration)
        internal
        returns (Vault, FullRestakeDelegator, Slasher)
    {
        (address vault_, address delegator_, address slasher_) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: vaultFactory.lastVersion(),
                owner: alice,
                vaultParams: IVault.InitParams({
                    collateral: address(collateral),
                    delegator: address(0),
                    slasher: address(0),
                    burner: address(0xdEaD),
                    epochDuration: epochDuration,
                    slasherSetEpochsDelay: 3,
                    depositWhitelist: false,
                    defaultAdminRoleHolder: alice,
                    slasherSetRoleHolder: alice,
                    depositorWhitelistRoleHolder: alice
                }),
                delegatorIndex: 1,
                delegatorParams: abi.encode(
                    IFullRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: alice,
                            hook: address(0),
                            hookSetRoleHolder: alice
                        }),
                        networkLimitSetRoleHolder: alice,
                        operatorNetworkLimitSetRoleHolder: alice
                    })
                ),
                withSlasher: true,
                slasherIndex: 0,
                slasherParams: ""
            })
        );

        return (Vault(vault_), FullRestakeDelegator(delegator_), Slasher(slasher_));
    }

    function _getSlasher(address vault_) internal returns (Slasher) {
        return Slasher(slasherFactory.create(0, true, abi.encode(address(vault_), "")));
    }

    function _registerOperator(address user) internal {
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

    function _deposit(address user, uint256 amount) internal returns (uint256 shares) {
        collateral.transfer(user, amount);
        vm.startPrank(user);
        collateral.approve(address(vault), amount);
        shares = vault.deposit(user, amount);
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

    function _optInNetworkVault(address user) internal {
        vm.startPrank(user);
        networkVaultOptInService.optIn(address(vault));
        vm.stopPrank();
    }

    function _optOutNetworkVault(address user) internal {
        vm.startPrank(user);
        networkVaultOptInService.optOut(address(vault));
        vm.stopPrank();
    }

    function _optInOperatorVault(address user) internal {
        vm.startPrank(user);
        operatorVaultOptInService.optIn(address(vault));
        vm.stopPrank();
    }

    function _optOutOperatorVault(address user) internal {
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

    function _setSlasher(address user, address slasher_) internal {
        vm.startPrank(user);
        vault.setSlasher(slasher_);
        vm.stopPrank();
    }

    function _setNetworkLimit(address user, address network, uint256 amount) internal {
        vm.startPrank(user);
        delegator.setNetworkLimit(network, amount);
        vm.stopPrank();
    }

    function _setOperatorNetworkLimit(address user, address network, address operator, uint256 amount) internal {
        vm.startPrank(user);
        delegator.setOperatorNetworkLimit(network, operator, amount);
        vm.stopPrank();
    }

    function _slash(
        address user,
        address network,
        address operator,
        uint256 amount,
        uint48 captureTimestamp
    ) internal returns (uint256 slashAmount) {
        vm.startPrank(user);
        slashAmount = slasher.slash(network, operator, amount, captureTimestamp);
        vm.stopPrank();
    }

    function _setMaxNetworkLimit(address user, uint256 amount) internal {
        vm.startPrank(user);
        delegator.setMaxNetworkLimit(amount);
        vm.stopPrank();
    }
}
