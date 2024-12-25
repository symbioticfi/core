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

import {IVaultStorage} from "../../src/interfaces/vault/IVaultStorage.sol";
import {IBaseSlasher} from "../../src/interfaces/slasher/IBaseSlasher.sol";
import {ISlasher} from "../../src/interfaces/slasher/ISlasher.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {BaseSlasherHints, SlasherHints} from "../../src/contracts/hints/SlasherHints.sol";
import {BaseDelegatorHints} from "../../src/contracts/hints/DelegatorHints.sol";
import {OptInServiceHints} from "../../src/contracts/hints/OptInServiceHints.sol";
import {VaultHints} from "../../src/contracts/hints/VaultHints.sol";
import {Subnetwork} from "../../src/contracts/libraries/Subnetwork.sol";

import {SimpleBurner} from "../mocks/SimpleBurner.sol";

contract SlasherTest is Test {
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

    OptInServiceHints optInServiceHints;
    BaseDelegatorHints baseDelegatorHints;
    BaseSlasherHints baseSlasherHints;
    SlasherHints slasherHints;

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

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        slasher = _getSlasher(address(vault));

        assertEq(slasher.VAULT_FACTORY(), address(vaultFactory));
        assertEq(slasher.NETWORK_MIDDLEWARE_SERVICE(), address(networkMiddlewareService));
        assertEq(slasher.vault(), address(vault));
        assertEq(slasher.cumulativeSlashAt(alice.subnetwork(0), alice, 0, ""), 0);
        assertEq(slasher.cumulativeSlash(alice.subnetwork(0), alice), 0);
        assertEq(slasher.slashableStake(alice.subnetwork(0), alice, 0, ""), 0);
    }

    function test_CreateRevertNoBurner(
        uint48 epochDuration
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

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
                        burner: address(0),
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

        vault = Vault(vault_);
        delegator = FullRestakeDelegator(delegator_);

        vm.expectRevert(IBaseSlasher.NoBurner.selector);
        slasherFactory.create(
            0,
            abi.encode(
                address(vault),
                abi.encode(ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: true})}))
            )
        );
    }

    function test_CreateRevertNotVault(
        uint48 epochDuration
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        (vault,) = _getVaultAndDelegator(epochDuration);

        vm.expectRevert(IBaseSlasher.NotVault.selector);
        slasherFactory.create(
            0,
            abi.encode(
                address(1),
                abi.encode(ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})}))
            )
        );
    }

    function test_Slash(
        uint48 epochDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 operatorNetworkLimit2,
        uint256 slashAmount1,
        uint256 slashAmount2,
        uint256 slashAmount3
    ) public {
        epochDuration = uint48(bound(epochDuration, 2, 10 days));
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        operatorNetworkLimit2 = bound(operatorNetworkLimit2, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);
        slashAmount2 = bound(slashAmount2, 1, type(uint256).max);
        slashAmount3 = bound(slashAmount3, 1, type(uint256).max);

        uint256 blockTimestamp = vm.getBlockTimestamp();
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

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(
            slasher.slashableStake(network.subnetwork(0), alice, uint48(blockTimestamp - epochDuration - 1), ""), 0
        );
        assertEq(slasher.slashableStake(network.subnetwork(0), alice, uint48(blockTimestamp), ""), 0);
        assertEq(
            slasher.slashableStake(network.subnetwork(0), alice, uint48(blockTimestamp - 1), ""),
            delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 1), "")
        );
        assertEq(slasher.latestSlashedCaptureTimestamp(network.subnetwork(0), alice), 0);

        assertEq(
            Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 1), "")),
            _slash(alice, network, alice, slashAmount1, uint48(blockTimestamp - 1), "")
        );

        assertEq(slasher.latestSlashedCaptureTimestamp(network.subnetwork(0), alice), uint48(blockTimestamp - 1));
        assertEq(slasher.cumulativeSlashAt(alice.subnetwork(0), alice, uint48(blockTimestamp - 1), ""), 0);
        assertEq(
            slasher.cumulativeSlashAt(alice.subnetwork(0), alice, uint48(blockTimestamp), ""),
            Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 1), ""))
        );
        assertEq(
            slasher.cumulativeSlash(alice.subnetwork(0), alice),
            Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 1), ""))
        );
        assertEq(slasher.slashableStake(network.subnetwork(0), alice, uint48(blockTimestamp - 2), ""), 0);
        assertEq(
            slasher.slashableStake(network.subnetwork(0), alice, uint48(blockTimestamp - 1), ""),
            delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 1), "")
                - Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 1), ""))
        );

        assertEq(slasher.latestSlashedCaptureTimestamp(network.subnetwork(0), bob), 0);
        assertEq(slasher.slashableStake(network.subnetwork(0), bob, uint48(blockTimestamp - epochDuration - 1), ""), 0);
        assertEq(slasher.slashableStake(network.subnetwork(0), bob, uint48(blockTimestamp), ""), 0);
        assertEq(
            slasher.slashableStake(network.subnetwork(0), bob, uint48(blockTimestamp - 1), ""),
            delegator.stakeAt(network.subnetwork(0), bob, uint48(blockTimestamp - 1), "")
        );

        assertEq(
            Math.min(slashAmount2, delegator.stakeAt(network.subnetwork(0), bob, uint48(blockTimestamp - 1), "")),
            _slash(alice, network, bob, slashAmount2, uint48(blockTimestamp - 1), "")
        );

        assertEq(slasher.latestSlashedCaptureTimestamp(network.subnetwork(0), bob), uint48(blockTimestamp - 1));
        assertEq(slasher.cumulativeSlashAt(alice.subnetwork(0), bob, uint48(blockTimestamp - 1), ""), 0);
        assertEq(
            slasher.cumulativeSlashAt(alice.subnetwork(0), bob, uint48(blockTimestamp), ""),
            Math.min(slashAmount2, delegator.stakeAt(network.subnetwork(0), bob, uint48(blockTimestamp - 1), ""))
        );
        assertEq(
            slasher.cumulativeSlash(alice.subnetwork(0), bob),
            Math.min(slashAmount2, delegator.stakeAt(network.subnetwork(0), bob, uint48(blockTimestamp - 1), ""))
        );
        assertEq(
            slasher.slashableStake(network.subnetwork(0), bob, uint48(blockTimestamp - 1), ""),
            delegator.stakeAt(network.subnetwork(0), bob, uint48(blockTimestamp - 1), "")
                - Math.min(slashAmount2, delegator.stakeAt(network.subnetwork(0), bob, uint48(blockTimestamp - 1), ""))
        );

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 slashAmountReal3 = Math.min(
            slashAmount3,
            delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 2), "")
                - Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 2), ""))
        );
        vm.assume(slashAmountReal3 > 0);
        assertEq(slashAmountReal3, _slash(alice, network, alice, slashAmount3, uint48(blockTimestamp - 2), ""));

        assertEq(slasher.latestSlashedCaptureTimestamp(network.subnetwork(0), alice), uint48(blockTimestamp - 2));
        assertEq(slasher.cumulativeSlashAt(alice.subnetwork(0), alice, uint48(blockTimestamp - 2), ""), 0);
        assertEq(
            slasher.cumulativeSlashAt(alice.subnetwork(0), alice, uint48(blockTimestamp - 1), ""),
            Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 2), ""))
        );
        assertEq(
            slasher.cumulativeSlashAt(alice.subnetwork(0), alice, uint48(blockTimestamp), ""),
            Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 2), ""))
                + slashAmountReal3
        );
        assertEq(
            slasher.cumulativeSlash(alice.subnetwork(0), alice),
            Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 2), ""))
                + slashAmountReal3
        );
        assertEq(
            slasher.slashableStake(network.subnetwork(0), alice, uint48(blockTimestamp - 2), ""),
            delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 2), "")
                - Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 2), ""))
                - slashAmountReal3
        );
        assertEq(
            slasher.cumulativeSlashAt(alice.subnetwork(0), alice, uint48(blockTimestamp), abi.encode(1)),
            Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 2), ""))
                + slashAmountReal3
        );
    }

    function test_SlashSubnetworks(
        uint48 epochDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 operatorNetworkLimit2,
        uint256 slashAmount1,
        uint256 slashAmount2,
        uint256 slashAmount3
    ) public {
        epochDuration = uint48(bound(epochDuration, 2, 10 days));
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        operatorNetworkLimit2 = bound(operatorNetworkLimit2, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);
        slashAmount2 = bound(slashAmount2, 1, type(uint256).max);
        slashAmount3 = bound(slashAmount3, 1, type(uint256).max);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration);

        address network = alice;
        _registerNetwork(network, alice);

        _registerOperator(alice);
        _registerOperator(bob);

        _optInOperatorVault(alice);
        _optInOperatorVault(bob);

        _optInOperatorNetwork(alice, address(network));
        _optInOperatorNetwork(bob, address(network));

        _deposit(alice, depositAmount);

        vm.startPrank(network);
        delegator.setMaxNetworkLimit(0, type(uint256).max);
        vm.stopPrank();

        vm.startPrank(alice);
        delegator.setNetworkLimit(network.subnetwork(0), networkLimit);
        vm.stopPrank();

        vm.startPrank(alice);
        delegator.setOperatorNetworkLimit(network.subnetwork(0), alice, operatorNetworkLimit1);
        vm.stopPrank();
        vm.startPrank(alice);
        delegator.setOperatorNetworkLimit(network.subnetwork(0), bob, operatorNetworkLimit2);
        vm.stopPrank();

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(
            slasher.slashableStake(network.subnetwork(0), alice, uint48(blockTimestamp - epochDuration - 1), ""), 0
        );
        assertEq(slasher.slashableStake(network.subnetwork(0), alice, uint48(blockTimestamp), ""), 0);
        assertEq(
            slasher.slashableStake(network.subnetwork(0), alice, uint48(blockTimestamp - 1), ""),
            delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 1), "")
        );

        vm.startPrank(alice);
        assertEq(
            Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 1), "")),
            slasher.slash(network.subnetwork(0), alice, slashAmount1, uint48(blockTimestamp - 1), "")
        );
        vm.stopPrank();

        assertEq(slasher.cumulativeSlashAt(alice.subnetwork(0), alice, uint48(blockTimestamp - 1), ""), 0);
        assertEq(
            slasher.cumulativeSlashAt(alice.subnetwork(0), alice, uint48(blockTimestamp), ""),
            Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 1), ""))
        );
        assertEq(
            slasher.cumulativeSlash(alice.subnetwork(0), alice),
            Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 1), ""))
        );
        assertEq(
            slasher.slashableStake(network.subnetwork(0), alice, uint48(blockTimestamp - 1), ""),
            delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 1), "")
                - Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 1), ""))
        );

        assertEq(slasher.slashableStake(network.subnetwork(0), bob, uint48(blockTimestamp - epochDuration - 1), ""), 0);
        assertEq(slasher.slashableStake(network.subnetwork(0), bob, uint48(blockTimestamp), ""), 0);
        assertEq(
            slasher.slashableStake(network.subnetwork(0), bob, uint48(blockTimestamp - 1), ""),
            delegator.stakeAt(network.subnetwork(0), bob, uint48(blockTimestamp - 1), "")
        );

        vm.startPrank(alice);
        assertEq(
            Math.min(slashAmount2, delegator.stakeAt(network.subnetwork(0), bob, uint48(blockTimestamp - 1), "")),
            slasher.slash(network.subnetwork(0), bob, slashAmount2, uint48(blockTimestamp - 1), "")
        );
        vm.stopPrank();

        assertEq(slasher.cumulativeSlashAt(alice.subnetwork(0), bob, uint48(blockTimestamp - 1), ""), 0);
        assertEq(
            slasher.cumulativeSlashAt(alice.subnetwork(0), bob, uint48(blockTimestamp), ""),
            Math.min(slashAmount2, delegator.stakeAt(network.subnetwork(0), bob, uint48(blockTimestamp - 1), ""))
        );
        assertEq(
            slasher.cumulativeSlash(alice.subnetwork(0), bob),
            Math.min(slashAmount2, delegator.stakeAt(network.subnetwork(0), bob, uint48(blockTimestamp - 1), ""))
        );
        assertEq(
            slasher.slashableStake(network.subnetwork(0), bob, uint48(blockTimestamp - 1), ""),
            delegator.stakeAt(network.subnetwork(0), bob, uint48(blockTimestamp - 1), "")
                - Math.min(slashAmount2, delegator.stakeAt(network.subnetwork(0), bob, uint48(blockTimestamp - 1), ""))
        );

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 slashAmountReal3 = Math.min(
            slashAmount3,
            delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 2), "")
                - Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 2), ""))
        );
        vm.assume(slashAmountReal3 > 0);

        vm.startPrank(alice);
        assertEq(
            slashAmountReal3, slasher.slash(network.subnetwork(0), alice, slashAmount3, uint48(blockTimestamp - 2), "")
        );
        vm.stopPrank();

        assertEq(slasher.cumulativeSlashAt(alice.subnetwork(0), alice, uint48(blockTimestamp - 2), ""), 0);
        assertEq(
            slasher.cumulativeSlashAt(alice.subnetwork(0), alice, uint48(blockTimestamp - 1), ""),
            Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 2), ""))
        );
        assertEq(
            slasher.cumulativeSlashAt(alice.subnetwork(0), alice, uint48(blockTimestamp), ""),
            Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 2), ""))
                + slashAmountReal3
        );
        assertEq(
            slasher.cumulativeSlash(alice.subnetwork(0), alice),
            Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 2), ""))
                + slashAmountReal3
        );
        assertEq(
            slasher.slashableStake(network.subnetwork(0), alice, uint48(blockTimestamp - 2), ""),
            delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 2), "")
                - Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 2), ""))
                - slashAmountReal3
        );
        assertEq(
            slasher.cumulativeSlashAt(alice.subnetwork(0), alice, uint48(blockTimestamp), abi.encode(1)),
            Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(0), alice, uint48(blockTimestamp - 2), ""))
                + slashAmountReal3
        );

        _deposit(alice, depositAmount);

        vm.startPrank(network);
        delegator.setMaxNetworkLimit(1, type(uint256).max);
        vm.stopPrank();

        vm.startPrank(alice);
        delegator.setNetworkLimit(network.subnetwork(1), networkLimit);
        vm.stopPrank();

        vm.startPrank(alice);
        delegator.setOperatorNetworkLimit(network.subnetwork(1), alice, operatorNetworkLimit1);
        vm.stopPrank();
        vm.startPrank(alice);
        delegator.setOperatorNetworkLimit(network.subnetwork(1), bob, operatorNetworkLimit2);
        vm.stopPrank();

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(
            slasher.slashableStake(network.subnetwork(1), alice, uint48(blockTimestamp - epochDuration - 1), ""), 0
        );
        assertEq(slasher.slashableStake(network.subnetwork(1), alice, uint48(blockTimestamp), ""), 0);
        assertEq(
            slasher.slashableStake(network.subnetwork(1), alice, uint48(blockTimestamp - 1), ""),
            delegator.stakeAt(network.subnetwork(1), alice, uint48(blockTimestamp - 1), "")
        );

        vm.startPrank(alice);
        assertEq(
            Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(1), alice, uint48(blockTimestamp - 1), "")),
            slasher.slash(network.subnetwork(1), alice, slashAmount1, uint48(blockTimestamp - 1), "")
        );
        vm.stopPrank();

        assertEq(slasher.cumulativeSlashAt(alice.subnetwork(1), alice, uint48(blockTimestamp - 1), ""), 0);
        assertEq(
            slasher.cumulativeSlashAt(alice.subnetwork(1), alice, uint48(blockTimestamp), ""),
            Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(1), alice, uint48(blockTimestamp - 1), ""))
        );
        assertEq(
            slasher.cumulativeSlash(alice.subnetwork(1), alice),
            Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(1), alice, uint48(blockTimestamp - 1), ""))
        );
        assertEq(
            slasher.slashableStake(network.subnetwork(1), alice, uint48(blockTimestamp - 1), ""),
            delegator.stakeAt(network.subnetwork(1), alice, uint48(blockTimestamp - 1), "")
                - Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(1), alice, uint48(blockTimestamp - 1), ""))
        );

        assertEq(slasher.slashableStake(network.subnetwork(1), bob, uint48(blockTimestamp - epochDuration - 1), ""), 0);
        assertEq(slasher.slashableStake(network.subnetwork(1), bob, uint48(blockTimestamp), ""), 0);
        assertEq(
            slasher.slashableStake(network.subnetwork(1), bob, uint48(blockTimestamp - 1), ""),
            delegator.stakeAt(network.subnetwork(1), bob, uint48(blockTimestamp - 1), "")
        );

        vm.startPrank(alice);
        assertEq(
            Math.min(slashAmount2, delegator.stakeAt(network.subnetwork(1), bob, uint48(blockTimestamp - 1), "")),
            slasher.slash(network.subnetwork(1), bob, slashAmount2, uint48(blockTimestamp - 1), "")
        );
        vm.stopPrank();

        assertEq(slasher.cumulativeSlashAt(alice.subnetwork(1), bob, uint48(blockTimestamp - 1), ""), 0);
        assertEq(
            slasher.cumulativeSlashAt(alice.subnetwork(1), bob, uint48(blockTimestamp), ""),
            Math.min(slashAmount2, delegator.stakeAt(network.subnetwork(1), bob, uint48(blockTimestamp - 1), ""))
        );
        assertEq(
            slasher.cumulativeSlash(alice.subnetwork(1), bob),
            Math.min(slashAmount2, delegator.stakeAt(network.subnetwork(1), bob, uint48(blockTimestamp - 1), ""))
        );
        assertEq(
            slasher.slashableStake(network.subnetwork(1), bob, uint48(blockTimestamp - 1), ""),
            delegator.stakeAt(network.subnetwork(1), bob, uint48(blockTimestamp - 1), "")
                - Math.min(slashAmount2, delegator.stakeAt(network.subnetwork(1), bob, uint48(blockTimestamp - 1), ""))
        );

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        slashAmountReal3 = Math.min(
            slashAmount3,
            delegator.stakeAt(network.subnetwork(1), alice, uint48(blockTimestamp - 2), "")
                - Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(1), alice, uint48(blockTimestamp - 2), ""))
        );
        vm.assume(slashAmountReal3 > 0);
        vm.startPrank(alice);
        assertEq(
            slashAmountReal3, slasher.slash(network.subnetwork(1), alice, slashAmount3, uint48(blockTimestamp - 2), "")
        );
        vm.stopPrank();

        assertEq(slasher.cumulativeSlashAt(alice.subnetwork(1), alice, uint48(blockTimestamp - 2), ""), 0);
        assertEq(
            slasher.cumulativeSlashAt(alice.subnetwork(1), alice, uint48(blockTimestamp - 1), ""),
            Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(1), alice, uint48(blockTimestamp - 2), ""))
        );
        assertEq(
            slasher.cumulativeSlashAt(alice.subnetwork(1), alice, uint48(blockTimestamp), ""),
            Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(1), alice, uint48(blockTimestamp - 2), ""))
                + slashAmountReal3
        );
        assertEq(
            slasher.cumulativeSlash(alice.subnetwork(1), alice),
            Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(1), alice, uint48(blockTimestamp - 2), ""))
                + slashAmountReal3
        );
        assertEq(
            slasher.slashableStake(network.subnetwork(1), alice, uint48(blockTimestamp - 2), ""),
            delegator.stakeAt(network.subnetwork(1), alice, uint48(blockTimestamp - 2), "")
                - Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(1), alice, uint48(blockTimestamp - 2), ""))
                - slashAmountReal3
        );
        assertEq(
            slasher.cumulativeSlashAt(alice.subnetwork(1), alice, uint48(blockTimestamp), abi.encode(1)),
            Math.min(slashAmount1, delegator.stakeAt(network.subnetwork(1), alice, uint48(blockTimestamp - 2), ""))
                + slashAmountReal3
        );
    }

    function test_SlashRevertInsufficientSlash1(
        uint48 epochDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 operatorNetworkLimit2,
        uint256 slashAmount1,
        uint256 slashAmount2
    ) public {
        epochDuration = uint48(bound(epochDuration, 2, 10 days));
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        operatorNetworkLimit2 = bound(operatorNetworkLimit2, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);
        slashAmount2 = bound(slashAmount2, 1, type(uint256).max);

        uint256 blockTimestamp = vm.getBlockTimestamp();
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

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        _slash(alice, network, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        vm.expectRevert(ISlasher.InsufficientSlash.selector);
        _slash(alice, network, alice, slashAmount2, uint48(blockTimestamp - 2), "");
    }

    function test_SlashRevertNotNetworkMiddleware(
        uint48 epochDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 slashAmount1
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration);

        address network = alice;
        _registerNetwork(network, alice);
        _setMaxNetworkLimit(network, 0, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(network));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, network, networkLimit);
        _setNetworkLimit(alice, network, networkLimit - 1);

        _setOperatorNetworkLimit(alice, network, alice, operatorNetworkLimit1);

        _setOperatorNetworkLimit(alice, network, alice, operatorNetworkLimit1 - 1);

        vm.assume(slashAmount1 < depositAmount && slashAmount1 < networkLimit);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.expectRevert(IBaseSlasher.NotNetworkMiddleware.selector);
        _slash(bob, network, alice, slashAmount1, uint48(blockTimestamp - 1), "");
    }

    function test_SlashRevertInsufficientSlash2(
        uint48 epochDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 slashAmount1,
        bool zeroSlashAmount
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration);

        address network = alice;
        _registerNetwork(network, alice);
        _setMaxNetworkLimit(network, 0, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(network));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, network, networkLimit);
        _setNetworkLimit(alice, network, networkLimit - 1);

        vm.assume(slashAmount1 < depositAmount && slashAmount1 < networkLimit);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.expectRevert(ISlasher.InsufficientSlash.selector);
        _slash(alice, network, alice, zeroSlashAmount ? 0 : slashAmount1, uint48(blockTimestamp - 1), "");
    }

    function test_SlashRevertInvalidCaptureTimestamp(
        uint48 epochDuration,
        uint256 depositAmount,
        uint256 networkLimit,
        uint256 operatorNetworkLimit1,
        uint256 slashAmount1,
        uint256 captureAgo
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 10 days));
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorNetworkLimit1 = bound(operatorNetworkLimit1, 1, type(uint256).max / 2);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration);

        address network = alice;
        _registerNetwork(network, alice);
        _setMaxNetworkLimit(network, 0, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorNetwork(alice, address(network));

        _optInOperatorVault(alice);

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, network, networkLimit);

        _setOperatorNetworkLimit(alice, network, alice, operatorNetworkLimit1);

        blockTimestamp = blockTimestamp + 10 * epochDuration;
        vm.warp(blockTimestamp);

        vm.assume(captureAgo <= 10 * epochDuration && (captureAgo > epochDuration || captureAgo == 0));

        vm.expectRevert(ISlasher.InvalidCaptureTimestamp.selector);
        _slash(alice, network, alice, slashAmount1, uint48(blockTimestamp - captureAgo), "");
    }

    function test_SlashWithBurner(
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

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        address burner = address(new SimpleBurner(address(collateral)));
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
                        burner: burner,
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
                            hook: address(0),
                            hookSetRoleHolder: address(0)
                        }),
                        networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                        operatorNetworkLimitSetRoleHolders: operatorNetworkLimitSetRoleHolders
                    })
                ),
                withSlasher: true,
                slasherIndex: 0,
                slasherParams: abi.encode(ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: true})}))
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

        _slash(alice, network, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        assertEq(SimpleBurner(burner).counter1(), 1);
    }

    function test_SlashWithBurnerDisabled(
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

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        address burner = address(new SimpleBurner(address(collateral)));
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
                        burner: burner,
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
                            hook: address(0),
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

        _slash(alice, network, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        assertEq(SimpleBurner(burner).counter1(), 0);
    }

    function test_SlashWithBurnerGas(
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

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        address burner = address(new SimpleBurner(address(collateral)));
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
                        burner: burner,
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
                            hook: address(0),
                            hookSetRoleHolder: address(0)
                        }),
                        networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                        operatorNetworkLimitSetRoleHolders: operatorNetworkLimitSetRoleHolders
                    })
                ),
                withSlasher: true,
                slasherIndex: 0,
                slasherParams: abi.encode(ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: true})}))
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

        _slash(alice, network, alice, slashAmount1, uint48(blockTimestamp - 1), "");

        vm.startPrank(alice);
        uint256 HOOK_GAS_LIMIT = delegator.HOOK_GAS_LIMIT();
        uint256 BURNER_GAS_LIMIT = slasher.BURNER_GAS_LIMIT();
        vm.expectRevert(IBaseSlasher.InsufficientBurnerGas.selector);
        slasher.slash{gas: BURNER_GAS_LIMIT}(network.subnetwork(0), alice, slashAmount1, uint48(blockTimestamp - 1), "");
        vm.stopPrank();

        vm.startPrank(alice);
        (bool success,) = address(slasher).call{gas: totalGas}(
            abi.encodeCall(ISlasher.slash, (network.subnetwork(0), alice, slashAmount1, uint48(blockTimestamp - 1), ""))
        );
        vm.stopPrank();

        if (success) {
            assertEq(SimpleBurner(burner).counter1(), 2);
        }
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

    // function test_CumulativeSlashHint(
    //     uint48 epochDuration,
    //     uint256 depositAmount,
    //     uint256 slashAmount1,
    //     HintStruct memory hintStruct
    // ) public {
    //     epochDuration = uint48(bound(epochDuration, 1, 7 days));
    //     hintStruct.num = bound(hintStruct.num, 0, 25);
    //     hintStruct.secondsAgo = bound(hintStruct.secondsAgo, 0, 1_720_700_948);
    //     slashAmount1 = bound(slashAmount1, 1, 10 * 10 ** 18);
    //     depositAmount = bound(depositAmount, Math.max(1, hintStruct.num * slashAmount1), 1000 * 10 ** 18);

    //     uint256 blockTimestamp = vm.getBlockTimestamp();
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration);

    //     address network = alice;
    //     _registerNetwork(network, alice);
    //     _setMaxNetworkLimit(network, type(uint256).max);

    //     _registerOperator(alice);

    //     _optInOperatorVault(alice);

    //     _optInOperatorNetwork(alice, address(network));

    //     _deposit(alice, depositAmount);

    //     _setNetworkLimit(alice, network, type(uint256).max);

    //     _setOperatorNetworkLimit(alice, network, alice, type(uint256).max);

    //     for (uint256 i; i < hintStruct.num; ++i) {
    //         blockTimestamp = blockTimestamp + 1;
    //         vm.warp(blockTimestamp);

    //         _slash(alice, network, alice, slashAmount1, uint48(blockTimestamp - 1), "");
    //     }

    //     uint48 timestamp =
    //         uint48(hintStruct.back ? blockTimestamp - hintStruct.secondsAgo : blockTimestamp + hintStruct.secondsAgo);

    //     optInServiceHints = new OptInServiceHints();
    //     VaultHints vaultHints = new VaultHints();
    //     baseDelegatorHints = new BaseDelegatorHints(address(optInServiceHints), address(vaultHints));
    //     baseSlasherHints = new BaseSlasherHints(address(baseDelegatorHints), address(optInServiceHints));
    //     bytes memory hint = baseSlasherHints.cumulativeSlashHint(address(slasher), network, alice, timestamp);

    //     GasStruct memory gasStruct = GasStruct({gasSpent1: 1, gasSpent2: 1});
    //     slasher.cumulativeSlashAt(network, alice, timestamp, new bytes(0));
    //     gasStruct.gasSpent1 = vm.lastCallGas().gasTotalUsed;
    //     slasher.cumulativeSlashAt(network, alice, timestamp, hint);
    //     gasStruct.gasSpent2 = vm.lastCallGas().gasTotalUsed;
    //     assertGe(gasStruct.gasSpent1, gasStruct.gasSpent2);
    // }

    // function test_OptInsHints(uint48 epochDuration, HintStruct memory hintStruct) public {
    //     epochDuration = uint48(bound(epochDuration, 1, 7 days));
    //     hintStruct.num = bound(hintStruct.num, 0, 25);
    //     hintStruct.secondsAgo = bound(hintStruct.secondsAgo, 0, 1_720_700_948);

    //     uint256 blockTimestamp = vm.getBlockTimestamp();
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

    //     optInServiceHints = new OptInServiceHints();
    //     VaultHints vaultHints = new VaultHints();
    //     baseDelegatorHints = new BaseDelegatorHints(address(optInServiceHints), address(vaultHints));
    //     baseSlasherHints = new BaseSlasherHints(address(baseDelegatorHints), address(optInServiceHints));
    //     bytes memory hints = baseSlasherHints.optInHints(address(slasher), network, alice, timestamp);

    //     GasStruct memory gasStruct = GasStruct({gasSpent1: 1, gasSpent2: 1});
    //     baseSlasherHints._optIns(address(slasher), network, alice, timestamp, "");
    //     gasStruct.gasSpent1 = vm.lastCallGas().gasTotalUsed;
    //     baseSlasherHints._optIns(address(slasher), network, alice, timestamp, hints);
    //     gasStruct.gasSpent2 = vm.lastCallGas().gasTotalUsed;
    //     assertGe(gasStruct.gasSpent1, gasStruct.gasSpent2);
    // }

    // function test_SlashableStakeHints(
    //     uint48 epochDuration,
    //     uint256 depositAmount,
    //     uint256 slashAmount1,
    //     HintStruct memory hintStruct
    // ) public {
    //     epochDuration = uint48(bound(epochDuration, 1, 7 days));
    //     hintStruct.num = bound(hintStruct.num, 0, 25);
    //     hintStruct.secondsAgo = bound(hintStruct.secondsAgo, 0, 2 * epochDuration);
    //     slashAmount1 = bound(slashAmount1, 1, 10 * 10 ** 18);
    //     depositAmount = bound(depositAmount, Math.max(1, hintStruct.num * slashAmount1), 1000 * 10 ** 18);

    //     uint256 blockTimestamp = vm.getBlockTimestamp();
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration);

    //     address network = alice;
    //     _registerNetwork(network, alice);
    //     _setMaxNetworkLimit(network, type(uint256).max);

    //     _registerOperator(alice);

    //     _deposit(alice, depositAmount);

    //     _setNetworkLimit(alice, network, type(uint256).max);

    //     _setOperatorNetworkLimit(alice, network, alice, type(uint256).max);

    //     for (uint256 i; i < hintStruct.num; ++i) {
    //         _optInOperatorVault(alice);
    //         if (hintStruct.num % 2 == 0) {
    //             _optInOperatorNetwork(alice, address(network));
    //         }

    //         blockTimestamp = blockTimestamp + 1;
    //         vm.warp(blockTimestamp);

    //         vm.startPrank(alice);
    //         try slasher.slash(network, alice, slashAmount1, uint48(blockTimestamp - 1), "") {} catch {}
    //         vm.stopPrank();

    //         _optOutOperatorVault(alice);
    //         if (hintStruct.num % 2 == 0) {
    //             _optOutOperatorNetwork(alice, address(network));
    //         }
    //     }

    //     uint48 timestamp =
    //         uint48(hintStruct.back ? blockTimestamp - hintStruct.secondsAgo : blockTimestamp + hintStruct.secondsAgo);

    //     optInServiceHints = new OptInServiceHints();
    //     VaultHints vaultHints = new VaultHints();
    //     baseDelegatorHints = new BaseDelegatorHints(address(optInServiceHints), address(vaultHints));
    //     baseSlasherHints = new BaseSlasherHints(address(baseDelegatorHints), address(optInServiceHints));
    //     bytes memory hint = baseSlasherHints.slashableStakeHints(address(slasher), network, alice, timestamp);

    //     GasStruct memory gasStruct = GasStruct({gasSpent1: 1, gasSpent2: 1});
    //     slasher.slashableStake(network, alice, timestamp, new bytes(0));
    //     gasStruct.gasSpent1 = vm.lastCallGas().gasTotalUsed;
    //     slasher.slashableStake(network, alice, timestamp, hint);
    //     gasStruct.gasSpent2 = vm.lastCallGas().gasTotalUsed;
    //     assertGe(gasStruct.gasSpent1, gasStruct.gasSpent2);
    // }

    // function test_OnSlashHints(uint256 amount1, uint48 epochDuration, HintStruct memory hintStruct) public {
    //     amount1 = bound(amount1, 1, 10 * 10 ** 18);
    //     epochDuration = uint48(bound(epochDuration, 1, 7 days));
    //     hintStruct.num = bound(hintStruct.num, 0, 25);
    //     hintStruct.secondsAgo = bound(hintStruct.secondsAgo, 0, 1_720_700_948);

    //     uint256 blockTimestamp = vm.getBlockTimestamp();
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration);

    //     address network = alice;
    //     _registerNetwork(network, alice);
    //     _setMaxNetworkLimit(network, type(uint256).max);

    //     _registerOperator(alice);

    //     for (uint256 i; i < hintStruct.num / 2; ++i) {
    //         _optInOperatorVault(alice);
    //         if (hintStruct.num % 2 == 0) {
    //             _optInOperatorNetwork(alice, address(network));
    //         }

    //         _deposit(alice, amount1);
    //         _setNetworkLimit(alice, network, amount1);
    //         _setOperatorNetworkLimit(alice, network, alice, amount1);

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
    //

    //         _deposit(alice, amount1);
    //         _setNetworkLimit(alice, network, amount1);
    //         _setOperatorNetworkLimit(alice, network, alice, amount1);

    //         blockTimestamp = blockTimestamp + epochDuration;
    //         vm.warp(blockTimestamp);

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
    //     baseDelegatorHints = new BaseDelegatorHints(address(optInServiceHints), address(new VaultHints()));
    //     baseSlasherHints = new BaseSlasherHints(address(baseDelegatorHints), address(optInServiceHints));

    //     GasStruct memory gasStruct = GasStruct({gasSpent1: 1, gasSpent2: 1});
    //     baseSlasherHints._onSlash(address(slasher), network, alice, amount1, timestamp, "");
    //     gasStruct.gasSpent1 = vm.lastCallGas().gasTotalUsed;

    //     bytes memory hints = baseSlasherHints.onSlashHints(address(slasher), network, alice, amount1, timestamp);
    //     baseSlasherHints._onSlash(address(slasher), network, alice, amount1, timestamp, hints);
    //     gasStruct.gasSpent2 = vm.lastCallGas().gasTotalUsed;
    //     assertGe(gasStruct.gasSpent1, gasStruct.gasSpent2);
    // }

    // struct InputParams {
    //     uint256 depositAmount;
    //     uint256 networkLimit;
    //     uint256 operatorNetworkLimit;
    //     uint256 slashAmount;
    // }

    // function test_SlashHints(
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

    //     uint256 blockTimestamp = vm.getBlockTimestamp();
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration);
    //     SlasherHintsHelper slasherHintsHelper = new SlasherHintsHelper();

    //     address network = alice;
    //     address middleware = address(slasherHintsHelper);
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
    //             try slasher.slash(network, alice, inputParams.slashAmount, uint48(blockTimestamp - 1), "") {} catch {}
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
    //             try slasher.slash(network, alice, inputParams.slashAmount, uint48(blockTimestamp - 1), "") {} catch {}
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
    //     baseDelegatorHints = new BaseDelegatorHints(address(optInServiceHints), address(new VaultHints()));
    //     baseSlasherHints = new BaseSlasherHints(address(baseDelegatorHints), address(optInServiceHints));
    //     slasherHints = SlasherHints(baseSlasherHints.SLASHER_HINTS());

    //     GasStruct memory gasStruct = GasStruct({gasSpent1: 1, gasSpent2: 1});
    //     try slasherHintsHelper.trySlash(address(slasher), network, alice, inputParams.slashAmount, timestamp, "") {}
    //     catch (bytes memory data) {
    //         (bool reverted, uint256 gasSpent) = abi.decode(data, (bool, uint256));
    //         gasStruct.gasSpent1 = gasSpent;
    //     }

    //     bytes memory hints =
    //         slasherHints.slashHints(address(slasher), middleware, network, alice, inputParams.slashAmount, timestamp);
    //     try slasherHintsHelper.trySlash(address(slasher), network, alice, inputParams.slashAmount, timestamp, hints) {}
    //     catch (bytes memory data) {
    //         (bool reverted, uint256 gasSpent) = abi.decode(data, (bool, uint256));
    //         gasStruct.gasSpent2 = gasSpent;
    //     }
    //     assertGe(gasStruct.gasSpent1, gasStruct.gasSpent2);
    // }

    // function test_SlashHintsCompare(
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
    //     inputParams.depositAmount =
    //         bound(inputParams.depositAmount, Math.max(1, inputParams.slashAmount * hintStruct.num), 1000 * 10 ** 18);
    //     inputParams.networkLimit = bound(inputParams.networkLimit, inputParams.slashAmount, type(uint256).max);
    //     inputParams.operatorNetworkLimit =
    //         bound(inputParams.operatorNetworkLimit, inputParams.slashAmount, type(uint256).max);

    //     uint256 blockTimestamp = vm.getBlockTimestamp();
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration);
    //     SlasherHintsHelper slasherHintsHelper = new SlasherHintsHelper();

    //     address network = alice;
    //     address middleware = address(slasherHintsHelper);
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
    //             try slasher.slash(network, alice, inputParams.slashAmount, uint48(blockTimestamp - 1), "") {} catch {}
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
    //             try slasher.slash(network, alice, inputParams.slashAmount, uint48(blockTimestamp - 1), "") {} catch {}
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

    //     uint48 timestamp = uint48(blockTimestamp - hintStruct.secondsAgo);

    //     optInServiceHints = new OptInServiceHints();
    //     baseDelegatorHints = new BaseDelegatorHints(address(optInServiceHints), address(new VaultHints()));
    //     baseSlasherHints = new BaseSlasherHints(address(baseDelegatorHints), address(optInServiceHints));
    //     slasherHints = SlasherHints(baseSlasherHints.SLASHER_HINTS());

    //     GasStruct memory gasStruct = GasStruct({gasSpent1: 1, gasSpent2: 1});
    //     try slasherHintsHelper.trySlash(address(slasher), network, alice, inputParams.slashAmount, timestamp, "") {}
    //     catch (bytes memory data) {
    //         (bool reverted, uint256 gasSpent) = abi.decode(data, (bool, uint256));
    //         vm.assume(!reverted);
    //         gasStruct.gasSpent1 = gasSpent;
    //     }

    //     bytes memory hints =
    //         slasherHints.slashHints(address(slasher), middleware, network, alice, inputParams.slashAmount, timestamp);
    //     try slasherHintsHelper.trySlash(address(slasher), network, alice, inputParams.slashAmount, timestamp, hints) {}
    //     catch (bytes memory data) {
    //         (bool reverted, uint256 gasSpent) = abi.decode(data, (bool, uint256));
    //         gasStruct.gasSpent2 = gasSpent;
    //     }
    //     console2.log(gasStruct.gasSpent1, gasStruct.gasSpent2);
    //     assertLt(gasStruct.gasSpent1 - gasStruct.gasSpent2, 60_000);
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
}

contract SlasherHintsHelper is Test {
    function trySlash(
        address slasher,
        bytes32 subnetwork,
        address operator,
        uint256 amount,
        uint48 captureTimestamp,
        bytes memory hints
    ) external returns (bool reverted) {
        try Slasher(slasher).slash(subnetwork, operator, amount, captureTimestamp, hints) {}
        catch {
            reverted = true;
        }
        bytes memory revertData = abi.encode(reverted, vm.lastCallGas().gasTotalUsed);
        assembly {
            revert(add(32, revertData), mload(revertData))
        }
    }
}
