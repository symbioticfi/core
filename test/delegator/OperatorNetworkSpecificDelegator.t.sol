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
import {IOperatorNetworkSpecificDelegator} from "../../src/interfaces/delegator/IOperatorNetworkSpecificDelegator.sol";
import {IFullRestakeDelegator} from "../../src/interfaces/delegator/IFullRestakeDelegator.sol";
import {IBaseDelegator} from "../../src/interfaces/delegator/IBaseDelegator.sol";
import {ISlasher} from "../../src/interfaces/slasher/ISlasher.sol";
import {IBaseSlasher} from "../../src/interfaces/slasher/IBaseSlasher.sol";

import {IVaultStorage} from "../../src/interfaces/vault/IVaultStorage.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SimpleOperatorNetworkSpecificDelegatorHook} from "../mocks/SimpleOperatorNetworkSpecificDelegatorHook.sol";

import {BaseDelegatorHints, OperatorNetworkSpecificDelegatorHints} from "../../src/contracts/hints/DelegatorHints.sol";
import {OptInServiceHints} from "../../src/contracts/hints/OptInServiceHints.sol";
import {VaultHints} from "../../src/contracts/hints/VaultHints.sol";
import {Subnetwork} from "../../src/contracts/libraries/Subnetwork.sol";

contract OperatorNetworkSpecificDelegatorTest is Test {
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
    OperatorNetworkSpecificDelegator delegator;
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
        assertEq(delegator.network(), bob);
        assertEq(delegator.operator(), alice);
        assertEq(delegator.maxNetworkLimit(alice.subnetwork(0)), 0);
        assertEq(delegator.stakeAt(alice.subnetwork(0), alice, 0, ""), 0);
        assertEq(delegator.stake(alice.subnetwork(0), alice), 0);
        assertEq(delegator.maxNetworkLimitAt(alice.subnetwork(0), 0, ""), 0);
    }

    function test_CreateRevertNotVault(
        uint48 epochDuration
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        vm.expectRevert(IBaseDelegator.NotVault.selector);
        delegatorFactory.create(
            2,
            abi.encode(
                address(1),
                abi.encode(
                    IOperatorNetworkSpecificDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: bob,
                            hook: address(0),
                            hookSetRoleHolder: bob
                        }),
                        network: bob,
                        operator: alice
                    })
                )
            )
        );
    }

    function test_CreateRevertNotNetwork(
        uint48 epochDuration
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        vm.expectRevert(IBaseDelegator.NotNetwork.selector);
        delegatorFactory.create(
            3,
            abi.encode(
                address(vault),
                abi.encode(
                    IOperatorNetworkSpecificDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: address(0),
                            hook: address(0),
                            hookSetRoleHolder: address(1)
                        }),
                        network: alice,
                        operator: alice
                    })
                )
            )
        );
    }

    function test_CreateRevertNotOperator(
        uint48 epochDuration
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        vm.expectRevert(IOperatorNetworkSpecificDelegator.NotOperator.selector);
        delegatorFactory.create(
            3,
            abi.encode(
                address(vault),
                abi.encode(
                    IOperatorNetworkSpecificDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: address(0),
                            hook: address(0),
                            hookSetRoleHolder: address(1)
                        }),
                        network: bob,
                        operator: bob
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

    function test_SetMaxNetworkLimit(
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

        _setMaxNetworkLimit(network, 0, amount1);

        assertEq(delegator.maxNetworkLimitAt(network.subnetwork(0), uint48(blockTimestamp), ""), amount1);
        assertEq(delegator.maxNetworkLimitAt(network.subnetwork(0), uint48(blockTimestamp + 1), ""), amount1);
        assertEq(delegator.maxNetworkLimit(network.subnetwork(0)), amount1);

        _setMaxNetworkLimit(network, 0, amount2);

        assertEq(delegator.maxNetworkLimitAt(network.subnetwork(0), uint48(blockTimestamp), ""), amount2);
        assertEq(delegator.maxNetworkLimitAt(network.subnetwork(0), uint48(blockTimestamp + 1), ""), amount2);
        assertEq(delegator.maxNetworkLimit(network.subnetwork(0)), amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _setMaxNetworkLimit(network, 0, amount3);

        assertEq(delegator.maxNetworkLimitAt(network.subnetwork(0), uint48(blockTimestamp - 1), ""), amount2);
        assertEq(delegator.maxNetworkLimitAt(network.subnetwork(0), uint48(blockTimestamp), ""), amount3);
        assertEq(delegator.maxNetworkLimitAt(network.subnetwork(0), uint48(blockTimestamp + 1), ""), amount3);
        assertEq(delegator.maxNetworkLimit(network.subnetwork(0)), amount3);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _setMaxNetworkLimit(network, 0, amount4);

        assertEq(delegator.maxNetworkLimitAt(network.subnetwork(0), uint48(blockTimestamp - 2), ""), amount2);
        assertEq(delegator.maxNetworkLimitAt(network.subnetwork(0), uint48(blockTimestamp - 1), ""), amount3);
        assertEq(delegator.maxNetworkLimitAt(network.subnetwork(0), uint48(blockTimestamp), ""), amount4);
        assertEq(delegator.maxNetworkLimitAt(network.subnetwork(0), uint48(blockTimestamp + 1), ""), amount4);
        assertEq(delegator.maxNetworkLimit(network.subnetwork(0)), amount4);
    }

    function test_SetMaxNetworkLimitRevertNotNetwork(uint48 epochDuration, uint256 maxNetworkLimit) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));
        maxNetworkLimit = bound(maxNetworkLimit, 1, type(uint256).max);

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        vm.expectRevert(IBaseDelegator.NotNetwork.selector);
        _setMaxNetworkLimit(alice, 0, maxNetworkLimit);
    }

    function test_SetMaxNetworkLimitRevertAlreadySet(uint48 epochDuration, uint256 maxNetworkLimit) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));
        maxNetworkLimit = bound(maxNetworkLimit, 1, type(uint256).max);

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        _setMaxNetworkLimit(bob, 0, maxNetworkLimit);

        vm.expectRevert(IBaseDelegator.AlreadySet.selector);
        _setMaxNetworkLimit(bob, 0, maxNetworkLimit);
    }

    function test_SetMaxNetworkLimitRevertInvalidNetwork(uint48 epochDuration, uint256 maxNetworkLimit) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));
        maxNetworkLimit = bound(maxNetworkLimit, 1, type(uint256).max);

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        _setMaxNetworkLimit(bob, 0, maxNetworkLimit);

        _registerNetwork(alice, alice);

        vm.expectRevert(IOperatorNetworkSpecificDelegator.InvalidNetwork.selector);
        _setMaxNetworkLimit(alice, 0, maxNetworkLimit);
    }

    function test_Stakes(
        uint48 epochDuration,
        uint256 depositAmount,
        uint256 withdrawAmount,
        uint256 networkLimit1,
        uint256 networkLimit2
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        withdrawAmount = bound(withdrawAmount, 1, 100 * 10 ** 18);
        networkLimit1 = bound(networkLimit1, 1, type(uint256).max - 1);
        networkLimit2 = bound(networkLimit2, 0, type(uint256).max);
        vm.assume(withdrawAmount <= depositAmount);

        vm.assume(networkLimit1 != networkLimit2);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        address network = bob;
        _setMaxNetworkLimit(network, 0, type(uint256).max);

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
        _withdraw(alice, withdrawAmount);

        assertEq(delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 1), ""), 0);
        assertEq(delegator.stake(network.subnetwork(0), alice), depositAmount - withdrawAmount);
        assertEq(delegator.stake(network.subnetwork(0), bob), 0);

        _setMaxNetworkLimit(network, 0, networkLimit1);

        assertEq(delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 1), ""), 0);
        assertEq(delegator.stake(network.subnetwork(0), alice), Math.min(depositAmount - withdrawAmount, networkLimit1));
        assertEq(delegator.stake(network.subnetwork(0), bob), 0);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(
            delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 1), ""),
            Math.min(depositAmount - withdrawAmount, networkLimit1)
        );
        assertEq(delegator.stake(network.subnetwork(0), alice), Math.min(depositAmount - withdrawAmount, networkLimit1));
        assertEq(delegator.stake(network.subnetwork(0), bob), 0);

        _setMaxNetworkLimit(network, 0, networkLimit2);

        bytes memory hints = abi.encode(
            IOperatorNetworkSpecificDelegator.StakeHints({
                baseHints: "",
                activeStakeHint: abi.encode(0),
                maxNetworkLimitHint: abi.encode(0)
            })
        );
        uint256 gasLeft = gasleft();
        assertEq(
            delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp), hints),
            Math.min(depositAmount - withdrawAmount, networkLimit2)
        );
        uint256 gasSpent = gasLeft - gasleft();
        hints = abi.encode(
            IOperatorNetworkSpecificDelegator.StakeHints({
                baseHints: "",
                activeStakeHint: abi.encode(0),
                maxNetworkLimitHint: abi.encode(1)
            })
        );
        gasLeft = gasleft();
        assertEq(
            delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp), hints),
            Math.min(depositAmount - withdrawAmount, networkLimit2)
        );
        assertGt(gasSpent, gasLeft - gasleft());
    }

    function test_SlashBase(
        uint48 epochDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 slashAmount1,
        uint256 slashAmount2
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);
        slashAmount2 = bound(slashAmount2, 1, type(uint256).max);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration);

        // address network = bob;

        _registerOperator(bob);

        _optInOperatorVault(alice);
        _optInOperatorVault(bob);

        _optInOperatorNetwork(alice, address(bob));
        _optInOperatorNetwork(bob, address(bob));

        _deposit(alice, depositAmount);

        blockTimestamp = blockTimestamp + 2 * vault.epochDuration();
        vm.warp(blockTimestamp);

        _setMaxNetworkLimit(bob, 0, networkLimit);

        assertEq(
            delegator.maxNetworkLimitAt(bob.subnetwork(0), uint48(blockTimestamp + 2 * vault.epochDuration()), ""),
            networkLimit
        );
        assertEq(delegator.maxNetworkLimit(bob.subnetwork(0)), networkLimit);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 operatorNetworkStake1 = Math.min(networkLimit, depositAmount);
        vm.assume(operatorNetworkStake1 > 0);
        uint256 slashAmount1Real = Math.min(slashAmount1, operatorNetworkStake1);
        assertEq(_slash(bob, bob, alice, slashAmount1, uint48(blockTimestamp - 1), ""), slashAmount1Real);

        assertEq(
            delegator.maxNetworkLimitAt(bob.subnetwork(0), uint48(blockTimestamp + 2 * vault.epochDuration()), ""),
            networkLimit
        );
        assertEq(delegator.maxNetworkLimit(bob.subnetwork(0)), networkLimit);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 operatorNetworkStake2 =
            Math.min(networkLimit, depositAmount - Math.min(slashAmount1Real, depositAmount));
        vm.assume(operatorNetworkStake2 > 0);
        uint256 slashAmount2Real = Math.min(slashAmount2, operatorNetworkStake2);
        assertEq(_slash(bob, bob, alice, slashAmount2, uint48(blockTimestamp - 1), ""), slashAmount2Real);

        assertEq(
            delegator.maxNetworkLimitAt(bob.subnetwork(0), uint48(blockTimestamp + 2 * vault.epochDuration()), ""),
            networkLimit
        );
        assertEq(delegator.maxNetworkLimit(bob.subnetwork(0)), networkLimit);
    }

    function test_SlashWithHook(
        // uint48 epochDuration,
        uint256 depositAmount,
        // uint256 networkLimit,
        uint256 slashAmount1,
        uint256 slashAmount2
    ) public {
        // epochDuration = uint48(bound(epochDuration, 1, 10 days));
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        // networkLimit = bound(networkLimit, 1, type(uint256).max);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);
        slashAmount2 = bound(slashAmount2, 1, type(uint256).max);
        vm.assume(slashAmount1 < Math.min(depositAmount, type(uint256).max));

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        _registerNetwork(bob, bob);
        _registerOperator(alice);

        address hook = address(new SimpleOperatorNetworkSpecificDelegatorHook());

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
                delegatorIndex: 3,
                delegatorParams: abi.encode(
                    IOperatorNetworkSpecificDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: alice,
                            hook: hook,
                            hookSetRoleHolder: address(0)
                        }),
                        network: bob,
                        operator: alice
                    })
                ),
                withSlasher: true,
                slasherIndex: 0,
                slasherParams: abi.encode(ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})}))
            })
        );

        vault = Vault(vault_);
        delegator = OperatorNetworkSpecificDelegator(delegator_);
        slasher = Slasher(slasher_);

        address network = bob;

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(network));

        _deposit(alice, depositAmount);

        _setMaxNetworkLimit(network, 0, type(uint256).max);

        assertEq(delegator.maxNetworkLimit(network.subnetwork(0)), type(uint256).max);
        assertEq(SimpleOperatorNetworkSpecificDelegatorHook(hook).counter1(), 0);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _slash(bob, network, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        assertEq(delegator.maxNetworkLimit(network.subnetwork(0)), type(uint256).max);
        assertEq(SimpleOperatorNetworkSpecificDelegatorHook(hook).counter1(), 1);

        _slash(bob, network, alice, slashAmount2, uint48(blockTimestamp - 1), "");

        assertEq(delegator.maxNetworkLimit(network.subnetwork(0)), type(uint256).max);
        assertEq(SimpleOperatorNetworkSpecificDelegatorHook(hook).counter1(), 2);
    }

    function test_SlashWithHookGas(
        // uint48 epochDuration,
        uint256 depositAmount,
        // uint256 networkLimit,
        uint256 slashAmount1,
        uint256 totalGas
    ) public {
        // epochDuration = uint48(bound(epochDuration, 1, 10 days));
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        // networkLimit = bound(networkLimit, 1, type(uint256).max);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);
        totalGas = bound(totalGas, 1, 20_000_000);
        vm.assume(slashAmount1 < Math.min(depositAmount, type(uint256).max));

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        _registerNetwork(bob, bob);
        _registerOperator(alice);

        address hook = address(new SimpleOperatorNetworkSpecificDelegatorHook());
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
                delegatorIndex: 3,
                delegatorParams: abi.encode(
                    IOperatorNetworkSpecificDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: alice,
                            hook: hook,
                            hookSetRoleHolder: address(0)
                        }),
                        network: bob,
                        operator: alice
                    })
                ),
                withSlasher: true,
                slasherIndex: 0,
                slasherParams: abi.encode(ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})}))
            })
        );

        vault = Vault(vault_);
        delegator = OperatorNetworkSpecificDelegator(delegator_);
        slasher = Slasher(slasher_);

        address network = bob;
        _setMaxNetworkLimit(network, 0, type(uint256).max);

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(network));

        _deposit(alice, depositAmount);

        assertEq(delegator.maxNetworkLimit(network.subnetwork(0)), type(uint256).max);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _slash(bob, network, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        vm.startPrank(alice);
        uint256 HOOK_GAS_LIMIT = delegator.HOOK_GAS_LIMIT();
        vm.expectRevert(IBaseDelegator.InsufficientHookGas.selector);
        address(slasher).call{gas: HOOK_GAS_LIMIT}(
            abi.encodeWithSelector(
                ISlasher.slash.selector, network.subnetwork(0), alice, slashAmount1, uint48(blockTimestamp - 1), ""
            )
        );
        vm.stopPrank();

        vm.startPrank(alice);
        (bool success,) = address(slasher).call{gas: totalGas}(
            abi.encodeWithSelector(
                ISlasher.slash.selector, network.subnetwork(0), alice, slashAmount1, uint48(blockTimestamp - 1), ""
            )
        );
        vm.stopPrank();

        if (success) {
            assertEq(SimpleOperatorNetworkSpecificDelegatorHook(hook).counter1(), 2);
        } else {
            assertEq(SimpleOperatorNetworkSpecificDelegatorHook(hook).counter1(), 1);
        }
    }

    function test_SetHook(
        uint48 epochDuration
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        address hook = address(new SimpleOperatorNetworkSpecificDelegatorHook());

        assertEq(delegator.hook(), address(0));

        _setHook(alice, hook);

        assertEq(delegator.hook(), hook);

        hook = address(new SimpleOperatorNetworkSpecificDelegatorHook());

        _setHook(alice, hook);

        assertEq(delegator.hook(), hook);
    }

    function test_SetHookRevertAlreadySet(
        uint48 epochDuration
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        address hook = address(new SimpleOperatorNetworkSpecificDelegatorHook());

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

    // function test_MaxNetworkLimitHint(uint256 amount1, uint48 epochDuration, HintStruct memory hintStruct) public {
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
    //     _setMaxNetworkLimit(network, 0, type(uint256).max);

    //     for (uint256 i; i < hintStruct.num; ++i) {
    //         _setMaxNetworkLimit(network, 0, amount1);

    //         blockTimestamp = blockTimestamp + epochDuration;
    //         vm.warp(blockTimestamp);
    //     }

    //     uint48 timestamp =
    //         uint48(hintStruct.back ? blockTimestamp - hintStruct.secondsAgo : blockTimestamp + hintStruct.secondsAgo);

    //     OptInServiceHints optInServiceHints = new OptInServiceHints();
    //     VaultHints vaultHints = new VaultHints();
    //     baseDelegatorHints = new BaseDelegatorHints(address(optInServiceHints), address(vaultHints));
    //     OperatorNetworkSpecificDelegatorHints OperatorNetworkSpecificDelegatorHints =
    //         OperatorNetworkSpecificDelegatorHints(baseDelegatorHints.NETWORK_RESTAKE_DELEGATOR_HINTS());
    //     bytes memory hint = OperatorNetworkSpecificDelegatorHints.maxNetworkLimitHint(address(delegator), network, timestamp);

    //     GasStruct memory gasStruct = GasStruct({gasSpent1: 1, gasSpent2: 1});
    //     delegator.maxNetworkLimitAt(network, timestamp, new bytes(0));
    //     gasStruct.gasSpent1 = vm.lastCallGas().gasTotalUsed;
    //     delegator.maxNetworkLimitAt(network, timestamp, hint);
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
    //     uint32 maxNetworkLimitHint;
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
    //         stakeHintsUint32.maxNetworkLimitHint = uint32(bound(stakeHintsUint32.maxNetworkLimitHint, 0, 10 * hintStruct.num));
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
    //     OperatorNetworkSpecificDelegatorHints OperatorNetworkSpecificDelegatorHints =
    //         OperatorNetworkSpecificDelegatorHints(baseDelegatorHints.NETWORK_RESTAKE_DELEGATOR_HINTS());
    //     bytes memory hints = OperatorNetworkSpecificDelegatorHints.stakeHints(address(delegator), network, alice, timestamp);

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
    //         IOperatorNetworkSpecificDelegator.StakeHints({
    //             baseHints: stakeBaseHints,
    //             activeStakeHint: stakeHintsUint32.withActiveStakeHint
    //                 ? abi.encode(stakeHintsUint32.activeStakeHint)
    //                 : new bytes(0),
    //             maxNetworkLimitHint: stakeHintsUint32.withNetworkLimitHint
    //                 ? abi.encode(stakeHintsUint32.maxNetworkLimitHint)
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
    //         stakeHintsUint32.maxNetworkLimitHint = uint32(bound(stakeHintsUint32.maxNetworkLimitHint, 0, 10 * hintStruct.num));
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
    //     OperatorNetworkSpecificDelegatorHints OperatorNetworkSpecificDelegatorHints =
    //         OperatorNetworkSpecificDelegatorHints(baseDelegatorHints.NETWORK_RESTAKE_DELEGATOR_HINTS());
    //     bytes memory hints = OperatorNetworkSpecificDelegatorHints.stakeHints(address(delegator), network, alice, timestamp);

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
    //         IOperatorNetworkSpecificDelegator.StakeHints({
    //             baseHints: stakeBaseHints,
    //             activeStakeHint: stakeHintsUint32.withActiveStakeHint
    //                 ? abi.encode(stakeHintsUint32.activeStakeHint)
    //                 : new bytes(0),
    //             maxNetworkLimitHint: stakeHintsUint32.withNetworkLimitHint
    //                 ? abi.encode(stakeHintsUint32.maxNetworkLimitHint)
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
    //     amount1 = bound(amount1, 1, 100 * 10 ** 18);
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
    //         onSlashHintsUint32.hints.maxNetworkLimitHint =
    //             uint32(bound(onSlashHintsUint32.hints.maxNetworkLimitHint, 0, 10 * hintStruct.num));
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

    //     baseDelegatorHints = new BaseDelegatorHints(address(new OptInServiceHints()), address(new VaultHints()));

    //     GasStruct memory gasStruct = GasStruct({gasSpent1: 1, gasSpent2: 1});

    //     bytes memory stakeHints;
    //     if (onSlashHintsUint32.withHints) {
    //         stakeHints = abi.encode(
    //             IOperatorNetworkSpecificDelegator.StakeHints({
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
    //                 maxNetworkLimitHint: onSlashHintsUint32.hints.withNetworkLimitHint
    //                     ? abi.encode(onSlashHintsUint32.hints.maxNetworkLimitHint)
    //                     : new bytes(0)
    //             })
    //         );
    //     }

    //     try baseDelegatorHints._onSlash(
    //         address(delegator),
    //         network,
    //         alice,
    //         amount1,
    //         timestamp,
    //         abi.encode(IBaseDelegator.OnSlashHints({stakeHints: stakeHints}))
    //     ) {
    //         gasStruct.gasSpent1 = vm.lastCallGas().gasTotalUsed;
    //     } catch {
    //         baseDelegatorHints._onSlash(address(delegator), network, alice, amount1, timestamp, new bytes(0));
    //         gasStruct.gasSpent1 = vm.lastCallGas().gasTotalUsed;
    //     }

    //     bytes memory hints = baseDelegatorHints.onSlashHints(address(delegator), network, alice, amount1, timestamp);
    //     baseDelegatorHints._onSlash(address(delegator), network, alice, amount1, timestamp, hints);
    //     gasStruct.gasSpent2 = vm.lastCallGas().gasTotalUsed;
    //     assertGe(gasStruct.gasSpent1, gasStruct.gasSpent2);
    // }

    function _getVaultAndDelegator(
        uint48 epochDuration
    ) internal returns (Vault, OperatorNetworkSpecificDelegator) {
        _registerNetwork(bob, bob);
        _registerOperator(alice);

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
                delegatorIndex: 3,
                delegatorParams: abi.encode(
                    IOperatorNetworkSpecificDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: alice,
                            hook: address(0),
                            hookSetRoleHolder: alice
                        }),
                        network: bob,
                        operator: alice
                    })
                ),
                withSlasher: false,
                slasherIndex: 0,
                slasherParams: abi.encode(ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})}))
            })
        );

        return (Vault(vault_), OperatorNetworkSpecificDelegator(delegator_));
    }

    function _getVaultAndDelegatorAndSlasher(
        uint48 epochDuration
    ) internal returns (Vault, OperatorNetworkSpecificDelegator, Slasher) {
        _registerNetwork(bob, bob);
        _registerOperator(alice);

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
                delegatorIndex: 3,
                delegatorParams: abi.encode(
                    IOperatorNetworkSpecificDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: alice,
                            hook: address(0),
                            hookSetRoleHolder: alice
                        }),
                        network: bob,
                        operator: alice
                    })
                ),
                withSlasher: true,
                slasherIndex: 0,
                slasherParams: abi.encode(ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})}))
            })
        );

        return (Vault(vault_), OperatorNetworkSpecificDelegator(delegator_), Slasher(slasher_));
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
