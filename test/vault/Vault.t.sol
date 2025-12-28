// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2, stdError} from "forge-std/Test.sol";

import {VaultFactory} from "../../src/contracts/VaultFactory.sol";
import {DelegatorFactory} from "../../src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "../../src/contracts/SlasherFactory.sol";
import {NetworkRegistry} from "../../src/contracts/NetworkRegistry.sol";
import {OperatorRegistry} from "../../src/contracts/OperatorRegistry.sol";
import {MetadataService} from "../../src/contracts/service/MetadataService.sol";
import {NetworkMiddlewareService} from "../../src/contracts/service/NetworkMiddlewareService.sol";
import {OptInService} from "../../src/contracts/service/OptInService.sol";
import {Checkpoints} from "../../src/contracts/libraries/Checkpoints.sol";

import {Vault} from "../../src/contracts/vault/Vault.sol";
import {VaultV1} from "../helpers/v1/VaultV1.sol";
import {NetworkRestakeDelegator} from "../../src/contracts/delegator/NetworkRestakeDelegator.sol";
import {FullRestakeDelegator} from "../../src/contracts/delegator/FullRestakeDelegator.sol";
import {OperatorSpecificDelegator} from "../../src/contracts/delegator/OperatorSpecificDelegator.sol";
import {OperatorNetworkSpecificDelegator} from "../../src/contracts/delegator/OperatorNetworkSpecificDelegator.sol";
import {Slasher} from "../../src/contracts/slasher/Slasher.sol";
import {VetoSlasher} from "../../src/contracts/slasher/VetoSlasher.sol";

import {IVault} from "../../src/interfaces/vault/IVault.sol";

import {Token} from "../mocks/Token.sol";
import {FeeOnTransferToken} from "../mocks/FeeOnTransferToken.sol";
import {VaultConfigurator} from "../../src/contracts/VaultConfigurator.sol";
import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";
import {INetworkRestakeDelegator} from "../../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IFullRestakeDelegator} from "../../src/interfaces/delegator/IFullRestakeDelegator.sol";
import {IBaseDelegator} from "../../src/interfaces/delegator/IBaseDelegator.sol";
import {ISlasher} from "../../src/interfaces/slasher/ISlasher.sol";
import {IBaseSlasher} from "../../src/interfaces/slasher/IBaseSlasher.sol";

import {IVaultStorage} from "../../src/interfaces/vault/IVaultStorage.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {VaultHints} from "../../src/contracts/hints/VaultHints.sol";
import {Subnetwork} from "../../src/contracts/libraries/Subnetwork.sol";
import {VaultTestHelper} from "../helpers/VaultTestHelper.sol";

contract VaultTest is Test {
    using Math for uint256;
    using Subnetwork for bytes32;
    using Subnetwork for address;
    using Checkpoints for Checkpoints.Trace208;

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
    FeeOnTransferToken feeOnTransferCollateral;
    VaultConfigurator vaultConfigurator;
    VaultTestHelper vaultTestHelper;

    IVault vault;
    FullRestakeDelegator delegator;
    Slasher slasher;

    function setUp() public virtual {
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

        vaultTestHelper = new VaultTestHelper();

        address vaultImplV1 =
            _createVaultV1Impl(address(delegatorFactory), address(slasherFactory), address(vaultFactory));
        vaultFactory.whitelist(vaultImplV1);

        address vaultImpl = _createVaultImpl(address(delegatorFactory), address(slasherFactory), address(vaultFactory));

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
        feeOnTransferCollateral = new FeeOnTransferToken("FeeOnTransferToken");

        vaultConfigurator =
            new VaultConfigurator(address(vaultFactory), address(delegatorFactory), address(slasherFactory));
    }

    function test_Create2(
        address burner,
        uint48 epochDuration,
        bool depositWhitelist,
        bool isDepositLimit,
        uint256 depositLimit
    ) public virtual {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
        (IVault vault_, address delegator_, address slasher_) = _createInitializedVault(
            epochDuration,
            networkLimitSetRoleHolders,
            operatorNetworkSharesSetRoleHolders,
            vaultFactory.lastVersion(),
            burner,
            depositWhitelist,
            isDepositLimit,
            depositLimit
        );
        vault = vault_;

        assertEq(vault.DEPOSIT_WHITELIST_SET_ROLE(), keccak256("DEPOSIT_WHITELIST_SET_ROLE"));
        assertEq(vault.DEPOSITOR_WHITELIST_ROLE(), keccak256("DEPOSITOR_WHITELIST_ROLE"));
        assertEq(vault.DELEGATOR_FACTORY(), address(delegatorFactory));
        assertEq(vault.SLASHER_FACTORY(), address(slasherFactory));

        assertEq(Vault(address(vault)).owner(), address(0));
        assertEq(vault.collateral(), address(collateral));
        assertEq(vault.delegator(), delegator_);
        assertEq(vault.slasher(), slasher_);
        assertEq(vault.burner(), burner);
        assertEq(vault.epochDuration(), epochDuration);
        assertEq(vault.depositWhitelist(), depositWhitelist);
        assertEq(Vault(address(vault)).hasRole(Vault(address(vault)).DEFAULT_ADMIN_ROLE(), alice), true);
        assertEq(Vault(address(vault)).hasRole(vault.DEPOSITOR_WHITELIST_ROLE(), alice), true);
        assertEq(vault.epochDuration(), epochDuration);
        assertEq(vault.currentEpochStart(), blockTimestamp);
        assertEq(vault.totalStake(), 0);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), ""), 0);
        assertEq(vault.activeShares(), 0);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), ""), 0);
        assertEq(vault.activeStake(), 0);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp), ""), 0);
        assertEq(vault.activeSharesOf(alice), 0);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp), ""), 0);
        assertEq(vault.activeBalanceOf(alice), 0);
        assertEq(vault.withdrawalsLength(alice), 0);
        assertEq(vault.withdrawals(0), 0);
        assertEq(vault.withdrawalShares(0), 0);
        assertEq(vault.depositWhitelist(), depositWhitelist);
        assertEq(vault.isDepositorWhitelisted(alice), false);
        assertEq(vault.isDelegatorInitialized(), true);
        assertEq(vault.isSlasherInitialized(), true);
        assertEq(vault.isInitialized(), true);
    }

    function test_CreateRevertInvalidEpochDuration() public {
        uint48 epochDuration = 0;

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
        uint64 lastVersion = vaultFactory.lastVersion();
        vm.expectRevert(IVault.InvalidEpochDuration.selector);
        _createInitializedVault(
            epochDuration,
            networkLimitSetRoleHolders,
            operatorNetworkSharesSetRoleHolders,
            lastVersion,
            address(0xdEaD),
            false,
            false,
            0
        );
    }

    function test_CreateRevertInvalidCollateral(uint48 epochDuration) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
        uint64 lastVersion = vaultFactory.lastVersion();
        collateral = Token(address(0));
        vm.expectRevert(IVault.InvalidCollateral.selector);
        _createInitializedVault(
            epochDuration,
            networkLimitSetRoleHolders,
            operatorNetworkSharesSetRoleHolders,
            lastVersion,
            address(0xdEaD),
            false,
            false,
            0
        );
    }

    function test_CreateRevertMissingRoles1(uint48 epochDuration) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        uint64 lastVersion = vaultFactory.lastVersion();

        vm.expectRevert(IVault.MissingRoles.selector);
        vault = IVault(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: epochDuration,
                        depositWhitelist: true,
                        isDepositLimit: false,
                        depositLimit: 0,
                        defaultAdminRoleHolder: address(0),
                        depositWhitelistSetRoleHolder: address(0),
                        depositorWhitelistRoleHolder: address(0),
                        isDepositLimitSetRoleHolder: alice,
                        depositLimitSetRoleHolder: address(0)
                    })
                )
            )
        );
    }

    function test_CreateRevertMissingRoles2(uint48 epochDuration) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        uint64 lastVersion = vaultFactory.lastVersion();

        vm.expectRevert(IVault.MissingRoles.selector);
        vault = IVault(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: epochDuration,
                        depositWhitelist: false,
                        isDepositLimit: true,
                        depositLimit: 0,
                        defaultAdminRoleHolder: address(0),
                        depositWhitelistSetRoleHolder: alice,
                        depositorWhitelistRoleHolder: address(0),
                        isDepositLimitSetRoleHolder: address(0),
                        depositLimitSetRoleHolder: address(0)
                    })
                )
            )
        );
    }

    function test_CreateRevertMissingRoles3(uint48 epochDuration) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        uint64 lastVersion = vaultFactory.lastVersion();

        vm.expectRevert(IVault.MissingRoles.selector);
        vault = IVault(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: epochDuration,
                        depositWhitelist: false,
                        isDepositLimit: false,
                        depositLimit: 0,
                        defaultAdminRoleHolder: address(0),
                        depositWhitelistSetRoleHolder: alice,
                        depositorWhitelistRoleHolder: address(0),
                        isDepositLimitSetRoleHolder: address(0),
                        depositLimitSetRoleHolder: alice
                    })
                )
            )
        );
    }

    function test_CreateRevertMissingRoles4(uint48 epochDuration) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        uint64 lastVersion = vaultFactory.lastVersion();

        vm.expectRevert(IVault.MissingRoles.selector);
        vault = IVault(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: epochDuration,
                        depositWhitelist: false,
                        isDepositLimit: false,
                        depositLimit: 1,
                        defaultAdminRoleHolder: address(0),
                        depositWhitelistSetRoleHolder: alice,
                        depositorWhitelistRoleHolder: address(0),
                        isDepositLimitSetRoleHolder: address(0),
                        depositLimitSetRoleHolder: address(0)
                    })
                )
            )
        );
    }

    function test_CreateRevertMissingRoles5(uint48 epochDuration) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        uint64 lastVersion = vaultFactory.lastVersion();

        vm.expectRevert(IVault.MissingRoles.selector);
        vault = IVault(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: epochDuration,
                        depositWhitelist: false,
                        isDepositLimit: false,
                        depositLimit: 0,
                        defaultAdminRoleHolder: address(0),
                        depositWhitelistSetRoleHolder: address(0),
                        depositorWhitelistRoleHolder: alice,
                        isDepositLimitSetRoleHolder: alice,
                        depositLimitSetRoleHolder: address(0)
                    })
                )
            )
        );
    }

    function test_SetDelegator() public {
        uint64 lastVersion = vaultFactory.lastVersion();

        vault = IVault(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
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
                )
            )
        );

        assertEq(vault.isDelegatorInitialized(), false);

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](1);
        operatorNetworkLimitSetRoleHolders[0] = alice;
        delegator = FullRestakeDelegator(
            delegatorFactory.create(
                1,
                abi.encode(
                    address(vault),
                    abi.encode(
                        IFullRestakeDelegator.InitParams({
                            baseParams: IBaseDelegator.BaseParams({
                                defaultAdminRoleHolder: alice, hook: address(0), hookSetRoleHolder: alice
                            }),
                            networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                            operatorNetworkLimitSetRoleHolders: operatorNetworkLimitSetRoleHolders
                        })
                    )
                )
            )
        );

        vault.setDelegator(address(delegator));

        assertEq(vault.delegator(), address(delegator));
        assertEq(vault.isDelegatorInitialized(), true);
        assertEq(vault.isInitialized(), false);
    }

    function test_SetDelegatorRevertDelegatorAlreadyInitialized() public {
        uint64 lastVersion = vaultFactory.lastVersion();

        vault = IVault(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
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
                )
            )
        );

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](1);
        operatorNetworkLimitSetRoleHolders[0] = alice;
        delegator = FullRestakeDelegator(
            delegatorFactory.create(
                1,
                abi.encode(
                    address(vault),
                    abi.encode(
                        IFullRestakeDelegator.InitParams({
                            baseParams: IBaseDelegator.BaseParams({
                                defaultAdminRoleHolder: alice, hook: address(0), hookSetRoleHolder: alice
                            }),
                            networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                            operatorNetworkLimitSetRoleHolders: operatorNetworkLimitSetRoleHolders
                        })
                    )
                )
            )
        );

        vault.setDelegator(address(delegator));

        vm.expectRevert(IVault.DelegatorAlreadyInitialized.selector);
        vault.setDelegator(address(delegator));
    }

    function test_SetDelegatorRevertNotDelegator() public {
        uint64 lastVersion = vaultFactory.lastVersion();

        vault = IVault(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
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
                )
            )
        );

        vm.expectRevert(IVault.NotDelegator.selector);
        vault.setDelegator(address(1));
    }

    function test_SetDelegatorRevertInvalidDelegator() public {
        uint64 lastVersion = vaultFactory.lastVersion();

        vault = IVault(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
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
                )
            )
        );

        address vault2 = vaultFactory.create(
            lastVersion,
            alice,
            _getEncodedVaultParams(
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
            )
        );

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](1);
        operatorNetworkLimitSetRoleHolders[0] = alice;
        delegator = FullRestakeDelegator(
            delegatorFactory.create(
                1,
                abi.encode(
                    address(vault2),
                    abi.encode(
                        IFullRestakeDelegator.InitParams({
                            baseParams: IBaseDelegator.BaseParams({
                                defaultAdminRoleHolder: alice, hook: address(0), hookSetRoleHolder: alice
                            }),
                            networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                            operatorNetworkLimitSetRoleHolders: operatorNetworkLimitSetRoleHolders
                        })
                    )
                )
            )
        );

        vm.expectRevert(IVault.InvalidDelegator.selector);
        vault.setDelegator(address(delegator));
    }

    function test_SetSlasher() public {
        uint64 lastVersion = vaultFactory.lastVersion();

        vault = IVault(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
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
                )
            )
        );

        assertEq(vault.isSlasherInitialized(), false);

        slasher = Slasher(
            slasherFactory.create(
                0,
                abi.encode(
                    address(vault),
                    abi.encode(ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})}))
                )
            )
        );

        vault.setSlasher(address(slasher));

        assertEq(vault.slasher(), address(slasher));
        assertEq(vault.isSlasherInitialized(), true);
        assertEq(vault.isInitialized(), false);
    }

    function test_SetSlasherRevertSlasherAlreadyInitialized() public {
        uint64 lastVersion = vaultFactory.lastVersion();

        vault = IVault(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
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
                )
            )
        );

        slasher = Slasher(
            slasherFactory.create(
                0,
                abi.encode(
                    address(vault),
                    abi.encode(ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})}))
                )
            )
        );

        vault.setSlasher(address(slasher));

        vm.expectRevert(IVault.SlasherAlreadyInitialized.selector);
        vault.setSlasher(address(slasher));
    }

    function test_SetSlasherRevertNotSlasher() public {
        uint64 lastVersion = vaultFactory.lastVersion();

        vault = IVault(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
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
                )
            )
        );

        slasher = Slasher(
            slasherFactory.create(
                0,
                abi.encode(
                    address(vault),
                    abi.encode(ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})}))
                )
            )
        );

        vm.expectRevert(IVault.NotSlasher.selector);
        vault.setSlasher(address(1));
    }

    function test_SetSlasherRevertInvalidSlasher() public {
        uint64 lastVersion = vaultFactory.lastVersion();

        vault = IVault(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
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
                )
            )
        );

        address vault2 = vaultFactory.create(
            lastVersion,
            alice,
            _getEncodedVaultParams(
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
            )
        );

        slasher = Slasher(
            slasherFactory.create(
                0,
                abi.encode(
                    address(vault2),
                    abi.encode(ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})}))
                )
            )
        );

        vm.expectRevert(IVault.InvalidSlasher.selector);
        vault.setSlasher(address(slasher));
    }

    function test_SetSlasherZeroAddress() public {
        uint64 lastVersion = vaultFactory.lastVersion();

        vault = IVault(
            vaultFactory.create(
                lastVersion,
                alice,
                _getEncodedVaultParams(
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
                )
            )
        );

        vault.setSlasher(address(0));
    }

    function test_DepositTwice(uint256 amount1, uint256 amount2) public virtual {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        uint256 tokensBefore = collateral.balanceOf(address(vault));
        uint256 shares1 = amount1 * 10 ** 0;
        {
            (uint256 depositedAmount, uint256 mintedShares) = _deposit(alice, amount1);
            assertEq(depositedAmount, amount1);
            assertEq(mintedShares, shares1);
        }
        assertEq(collateral.balanceOf(address(vault)) - tokensBefore, amount1);

        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1), ""), 0);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), ""), shares1);
        assertEq(vault.activeShares(), shares1);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), ""), 0);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), ""), amount1);
        assertEq(vault.activeStake(), amount1);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1), ""), 0);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp), ""), shares1);
        assertEq(vault.activeSharesOf(alice), shares1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1), ""), 0);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp), ""), amount1);
        assertEq(vault.activeBalanceOf(alice), amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 shares2 = amount2 * (shares1 + 10 ** 0) / (amount1 + 1);
        {
            (uint256 depositedAmount, uint256 mintedShares) = _deposit(alice, amount2);
            assertEq(depositedAmount, amount2);
            assertEq(mintedShares, shares2);
        }

        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1), ""), shares1);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), ""), shares1 + shares2);
        assertEq(vault.activeShares(), shares1 + shares2);
        uint256 gasLeft = gasleft();
        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1), abi.encode(1)), shares1);
        uint256 gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1), abi.encode(0)), shares1);
        assertGt(gasSpent, gasLeft - gasleft());
        gasLeft = gasleft();
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), abi.encode(0)), shares1 + shares2);
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), abi.encode(1)), shares1 + shares2);
        assertGt(gasSpent, gasLeft - gasleft());
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), ""), amount1);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), ""), amount1 + amount2);
        assertEq(vault.activeStake(), amount1 + amount2);
        gasLeft = gasleft();
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), abi.encode(1)), amount1);
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), abi.encode(0)), amount1);
        assertGt(gasSpent, gasLeft - gasleft());
        gasLeft = gasleft();
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), abi.encode(0)), amount1 + amount2);
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), abi.encode(1)), amount1 + amount2);
        assertGt(gasSpent, gasLeft - gasleft());
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), ""), shares1);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), ""), shares1 + shares2);
        assertEq(vault.activeSharesOf(alice), shares1 + shares2);
        gasLeft = gasleft();
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1), abi.encode(1)), shares1);
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1), abi.encode(0)), shares1);
        assertGt(gasSpent, gasLeft - gasleft());
        gasLeft = gasleft();
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp), abi.encode(0)), shares1 + shares2);
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp), abi.encode(1)), shares1 + shares2);
        assertGt(gasSpent, gasLeft - gasleft());
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1), ""), amount1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp), ""), amount1 + amount2);
        assertEq(vault.activeBalanceOf(alice), amount1 + amount2);
        gasLeft = gasleft();
        assertEq(
            vault.activeBalanceOfAt(
                alice,
                uint48(blockTimestamp - 1),
                abi.encode(
                    IVault.ActiveBalanceOfHints({
                        activeSharesOfHint: abi.encode(1),
                        activeStakeHint: abi.encode(1),
                        activeSharesHint: abi.encode(1)
                    })
                )
            ),
            amount1
        );
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(
            vault.activeBalanceOfAt(
                alice,
                uint48(blockTimestamp - 1),
                abi.encode(
                    IVault.ActiveBalanceOfHints({
                        activeSharesOfHint: abi.encode(0),
                        activeStakeHint: abi.encode(0),
                        activeSharesHint: abi.encode(0)
                    })
                )
            ),
            amount1
        );
        assertGt(gasSpent, gasLeft - gasleft());
        gasLeft = gasleft();
        assertEq(
            vault.activeBalanceOfAt(
                alice,
                uint48(blockTimestamp),
                abi.encode(
                    IVault.ActiveBalanceOfHints({
                        activeSharesOfHint: abi.encode(0),
                        activeStakeHint: abi.encode(0),
                        activeSharesHint: abi.encode(0)
                    })
                )
            ),
            amount1 + amount2
        );
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(
            vault.activeBalanceOfAt(
                alice,
                uint48(blockTimestamp),
                abi.encode(
                    IVault.ActiveBalanceOfHints({
                        activeSharesOfHint: abi.encode(1),
                        activeStakeHint: abi.encode(1),
                        activeSharesHint: abi.encode(1)
                    })
                )
            ),
            amount1 + amount2
        );
        assertGt(gasSpent, gasLeft - gasleft());
    }

    function test_DepositTwiceFeeOnTransferCollateral(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 2, 100 * 10 ** 18);
        amount2 = bound(amount2, 2, 100 * 10 ** 18);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        {
            address[] memory networkLimitSetRoleHolders = new address[](1);
            networkLimitSetRoleHolders[0] = alice;
            address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
            operatorNetworkSharesSetRoleHolders[0] = alice;
            collateral = Token(address(feeOnTransferCollateral));
            (vault,,) = _createInitializedVault(
                epochDuration,
                networkLimitSetRoleHolders,
                operatorNetworkSharesSetRoleHolders,
                vaultFactory.lastVersion(),
                address(0xdEaD),
                false,
                false,
                0
            );
        }

        uint256 tokensBefore = feeOnTransferCollateral.balanceOf(address(vault));
        uint256 shares1 = (amount1 - 1) * 10 ** 0;
        feeOnTransferCollateral.transfer(alice, amount1 + 1);
        vm.startPrank(alice);
        feeOnTransferCollateral.approve(address(vault), amount1);
        {
            (uint256 depositedAmount, uint256 mintedShares) = vault.deposit(alice, amount1);
            assertEq(depositedAmount, amount1 - 1);
            assertEq(mintedShares, shares1);
        }
        vm.stopPrank();
        assertEq(feeOnTransferCollateral.balanceOf(address(vault)) - tokensBefore, amount1 - 1);

        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1), ""), 0);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), ""), shares1);
        assertEq(vault.activeShares(), shares1);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), ""), 0);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), ""), amount1 - 1);
        assertEq(vault.activeStake(), amount1 - 1);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1), ""), 0);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp), ""), shares1);
        assertEq(vault.activeSharesOf(alice), shares1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1), ""), 0);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp), ""), amount1 - 1);
        assertEq(vault.activeBalanceOf(alice), amount1 - 1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 shares2 = (amount2 - 1) * (shares1 + 10 ** 0) / (amount1 - 1 + 1);
        feeOnTransferCollateral.transfer(alice, amount2 + 1);
        vm.startPrank(alice);
        feeOnTransferCollateral.approve(address(vault), amount2);
        {
            (uint256 depositedAmount, uint256 mintedShares) = vault.deposit(alice, amount2);
            assertEq(depositedAmount, amount2 - 1);
            assertEq(mintedShares, shares2);
        }
        vm.stopPrank();

        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1), ""), shares1);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), ""), shares1 + shares2);
        assertEq(vault.activeShares(), shares1 + shares2);
        uint256 gasLeft = gasleft();
        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1), abi.encode(1)), shares1);
        uint256 gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1), abi.encode(0)), shares1);
        assertGt(gasSpent, gasLeft - gasleft());
        gasLeft = gasleft();
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), abi.encode(0)), shares1 + shares2);
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), abi.encode(1)), shares1 + shares2);
        assertGt(gasSpent, gasLeft - gasleft());
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), ""), amount1 - 1);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), ""), amount1 - 1 + amount2 - 1);
        assertEq(vault.activeStake(), amount1 - 1 + amount2 - 1);
        gasLeft = gasleft();
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), abi.encode(1)), amount1 - 1);
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), abi.encode(0)), amount1 - 1);
        assertGt(gasSpent, gasLeft - gasleft());
        gasLeft = gasleft();
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), abi.encode(0)), amount1 - 1 + amount2 - 1);
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), abi.encode(1)), amount1 - 1 + amount2 - 1);
        assertGt(gasSpent, gasLeft - gasleft());
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), ""), shares1);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), ""), shares1 + shares2);
        assertEq(vault.activeSharesOf(alice), shares1 + shares2);
        gasLeft = gasleft();
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1), abi.encode(1)), shares1);
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1), abi.encode(0)), shares1);
        assertGt(gasSpent, gasLeft - gasleft());
        gasLeft = gasleft();
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp), abi.encode(0)), shares1 + shares2);
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp), abi.encode(1)), shares1 + shares2);
        assertGt(gasSpent, gasLeft - gasleft());
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1), ""), amount1 - 1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp), ""), amount1 - 1 + amount2 - 1);
        assertEq(vault.activeBalanceOf(alice), amount1 - 1 + amount2 - 1);
        gasLeft = gasleft();
        assertEq(
            vault.activeBalanceOfAt(
                alice,
                uint48(blockTimestamp - 1),
                abi.encode(
                    IVault.ActiveBalanceOfHints({
                        activeSharesOfHint: abi.encode(1),
                        activeStakeHint: abi.encode(1),
                        activeSharesHint: abi.encode(1)
                    })
                )
            ),
            amount1 - 1
        );
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(
            vault.activeBalanceOfAt(
                alice,
                uint48(blockTimestamp - 1),
                abi.encode(
                    IVault.ActiveBalanceOfHints({
                        activeSharesOfHint: abi.encode(0),
                        activeStakeHint: abi.encode(0),
                        activeSharesHint: abi.encode(0)
                    })
                )
            ),
            amount1 - 1
        );
        assertGt(gasSpent, gasLeft - gasleft());
        gasLeft = gasleft();
        assertEq(
            vault.activeBalanceOfAt(
                alice,
                uint48(blockTimestamp),
                abi.encode(
                    IVault.ActiveBalanceOfHints({
                        activeSharesOfHint: abi.encode(0),
                        activeStakeHint: abi.encode(0),
                        activeSharesHint: abi.encode(0)
                    })
                )
            ),
            amount1 - 1 + amount2 - 1
        );
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(
            vault.activeBalanceOfAt(
                alice,
                uint48(blockTimestamp),
                abi.encode(
                    IVault.ActiveBalanceOfHints({
                        activeSharesOfHint: abi.encode(1),
                        activeStakeHint: abi.encode(1),
                        activeSharesHint: abi.encode(1)
                    })
                )
            ),
            amount1 - 1 + amount2 - 1
        );
        assertGt(gasSpent, gasLeft - gasleft());
    }

    function test_DepositBoth(uint256 amount1, uint256 amount2) public virtual {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        uint256 shares1 = amount1 * 10 ** 0;
        {
            (uint256 depositedAmount, uint256 mintedShares) = _deposit(alice, amount1);
            assertEq(depositedAmount, amount1);
            assertEq(mintedShares, shares1);
        }

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 shares2 = amount2 * (shares1 + 10 ** 0) / (amount1 + 1);
        {
            (uint256 depositedAmount, uint256 mintedShares) = _deposit(bob, amount2);
            assertEq(depositedAmount, amount2);
            assertEq(mintedShares, shares2);
        }

        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1), ""), shares1);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), ""), shares1 + shares2);
        assertEq(vault.activeShares(), shares1 + shares2);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), ""), amount1);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), ""), amount1 + amount2);
        assertEq(vault.activeStake(), amount1 + amount2);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1), ""), shares1);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp), ""), shares1);
        assertEq(vault.activeSharesOf(alice), shares1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1), ""), amount1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp), ""), amount1);
        assertEq(vault.activeBalanceOf(alice), amount1);
        assertEq(vault.activeSharesOfAt(bob, uint48(blockTimestamp - 1), ""), 0);
        assertEq(vault.activeSharesOfAt(bob, uint48(blockTimestamp), ""), shares2);
        assertEq(vault.activeSharesOf(bob), shares2);
        assertEq(vault.activeBalanceOfAt(bob, uint48(blockTimestamp - 1), ""), 0);
        assertEq(vault.activeBalanceOfAt(bob, uint48(blockTimestamp), ""), amount2);
        assertEq(vault.activeBalanceOf(bob), amount2);
    }

    function test_DepositRevertInvalidOnBehalfOf(uint256 amount1) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        vm.startPrank(alice);
        vm.expectRevert(IVault.InvalidOnBehalfOf.selector);
        vault.deposit(address(0), amount1);
        vm.stopPrank();
    }

    function test_DepositRevertInsufficientDeposit() public {
        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        vm.startPrank(alice);
        vm.expectRevert(IVault.InsufficientDeposit.selector);
        vault.deposit(alice, 0);
        vm.stopPrank();
    }

    function test_WithdrawTwice(uint256 amount1, uint256 amount2, uint256 amount3) public virtual {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount3, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2 + amount3);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        // uint48 epochDuration = 1;
        vault = _getVault(1);

        (, uint256 shares) = _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 burnedShares = amount2 * (shares + 10 ** 0) / (amount1 + 1);
        uint256 mintedShares = amount2 * 10 ** 0;
        (uint256 burnedShares_, uint256 mintedShares_) = _withdraw(alice, amount2);
        assertEq(burnedShares_, burnedShares);
        assertEq(mintedShares_, mintedShares);

        assertEq(vault.totalStake(), _expectedTotalStake(uint48(blockTimestamp)));
        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1), ""), shares);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), ""), shares - burnedShares);
        assertEq(vault.activeShares(), shares - burnedShares);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), ""), amount1);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), ""), amount1 - amount2);
        assertEq(vault.activeStake(), amount1 - amount2);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1), ""), shares);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp), ""), shares - burnedShares);
        assertEq(vault.activeSharesOf(alice), shares - burnedShares);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1), ""), amount1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp), ""), amount1 - amount2);
        assertEq(vault.activeBalanceOf(alice), amount1 - amount2);
        uint256 lastBucket = _latestWithdrawalBucket();
        assertEq(vault.withdrawals(lastBucket), amount2);
        assertEq(vault.withdrawalShares(lastBucket), mintedShares);
        assertEq(vault.withdrawalSharesOf(0, alice), amount2);

        shares -= burnedShares;

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        burnedShares = amount3 * (shares + 10 ** 0) / (amount1 - amount2 + 1);
        mintedShares = amount3 * 10 ** 0;
        (burnedShares_, mintedShares_) = _withdraw(alice, amount3);
        assertEq(burnedShares_, burnedShares);
        assertEq(mintedShares_, mintedShares);

        assertEq(vault.totalStake(), _expectedTotalStake(uint48(blockTimestamp)));
        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1), ""), shares);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), ""), shares - burnedShares);
        assertEq(vault.activeShares(), shares - burnedShares);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), ""), amount1 - amount2);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), ""), amount1 - amount2 - amount3);
        assertEq(vault.activeStake(), amount1 - amount2 - amount3);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1), ""), shares);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp), ""), shares - burnedShares);
        assertEq(vault.activeSharesOf(alice), shares - burnedShares);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1), ""), amount1 - amount2);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp), ""), amount1 - amount2 - amount3);
        assertEq(vault.activeBalanceOf(alice), amount1 - amount2 - amount3);
        assertEq(vault.withdrawals(lastBucket), amount2 + amount3);
        assertEq(vault.withdrawalShares(lastBucket), amount2 + amount3);
        assertEq(vault.withdrawalSharesOf(1, alice), amount3);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(vault.totalStake(), _expectedTotalStake(uint48(blockTimestamp)));
    }

    function test_WithdrawUnlockAtAndLength(uint256 amount1, uint256 amount2, uint256 amount3) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount3, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2 + amount3);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 7;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 3;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        assertEq(vault.withdrawalsLength(alice), 1);
        assertEq(vault.withdrawalUnlockAt(0, alice), uint48(blockTimestamp + epochDuration));

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount3);

        assertEq(vault.withdrawalsLength(alice), 2);
        assertEq(vault.withdrawalUnlockAt(1, alice), uint48(blockTimestamp + epochDuration));
    }

    function test_WithdrawRecordsClaimer(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, amount1);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 5;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.startPrank(alice);
        (, uint256 mintedShares) = vault.withdraw(bob, amount2);
        vm.stopPrank();

        assertEq(vault.withdrawalsLength(alice), 0);
        assertEq(vault.withdrawalsLength(bob), 1);
        assertEq(vault.withdrawalUnlockAt(0, bob), uint48(blockTimestamp + epochDuration));
        assertEq(vault.withdrawalSharesOf(0, bob), mintedShares);
    }

    function test_WithdrawRevertInvalidClaimer(uint256 amount1) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        vm.expectRevert(IVault.InvalidClaimer.selector);
        vm.startPrank(alice);
        vault.withdraw(address(0), amount1);
        vm.stopPrank();
    }

    function test_WithdrawRevertInsufficientWithdrawal(uint256 amount1) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        vm.expectRevert(IVault.InsufficientWithdrawal.selector);
        _withdraw(alice, 0);
    }

    function test_WithdrawRevertTooMuchWithdraw(uint256 amount1) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        vm.expectRevert(IVault.TooMuchWithdraw.selector);
        _withdraw(alice, amount1 + 1);
    }

    function test_RedeemTwice(uint256 amount1, uint256 amount2, uint256 amount3) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount3, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2 + amount3);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        // uint48 epochDuration = 1;
        vault = _getVault(1);

        (, uint256 shares) = _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 withdrawnAssets2 = amount2 * (amount1 + 1) / (shares + 10 ** 0);
        uint256 mintedShares = amount2 * 10 ** 0;
        (uint256 withdrawnAssets_, uint256 mintedShares_) = _redeem(alice, amount2);
        assertEq(withdrawnAssets_, withdrawnAssets2);
        assertEq(mintedShares_, mintedShares);

        assertEq(vault.totalStake(), _expectedTotalStake(uint48(blockTimestamp)));
        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1), ""), shares);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), ""), shares - amount2);
        assertEq(vault.activeShares(), shares - amount2);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), ""), amount1);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), ""), amount1 - withdrawnAssets2);
        assertEq(vault.activeStake(), amount1 - withdrawnAssets2);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1), ""), shares);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp), ""), shares - amount2);
        assertEq(vault.activeSharesOf(alice), shares - amount2);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1), ""), amount1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp), ""), amount1 - withdrawnAssets2);
        assertEq(vault.activeBalanceOf(alice), amount1 - withdrawnAssets2);
        uint256 lastBucket = _latestWithdrawalBucket();
        assertEq(vault.withdrawals(lastBucket), withdrawnAssets2);
        assertEq(vault.withdrawalShares(lastBucket), mintedShares);
        assertEq(vault.withdrawalSharesOf(0, alice), mintedShares);

        shares -= amount2;

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 withdrawnAssets3 = amount3 * (amount1 - withdrawnAssets2 + 1) / (shares + 10 ** 0);
        mintedShares = amount3 * 10 ** 0;
        (withdrawnAssets_, mintedShares_) = _redeem(alice, amount3);
        assertEq(withdrawnAssets_, withdrawnAssets3);
        assertEq(mintedShares_, mintedShares);

        assertEq(vault.totalStake(), _expectedTotalStake(uint48(blockTimestamp)));
        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1), ""), shares);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), ""), shares - amount3);
        assertEq(vault.activeShares(), shares - amount3);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp - 1), ""), amount1 - withdrawnAssets2);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), ""), amount1 - withdrawnAssets2 - withdrawnAssets3);
        assertEq(vault.activeStake(), amount1 - withdrawnAssets2 - withdrawnAssets3);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1), ""), shares);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp), ""), shares - amount3);
        assertEq(vault.activeSharesOf(alice), shares - amount3);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1), ""), amount1 - withdrawnAssets2);
        assertEq(
            vault.activeBalanceOfAt(alice, uint48(blockTimestamp), ""), amount1 - withdrawnAssets2 - withdrawnAssets3
        );
        assertEq(vault.activeBalanceOf(alice), amount1 - withdrawnAssets2 - withdrawnAssets3);
        assertEq(vault.withdrawals(lastBucket), withdrawnAssets2 + withdrawnAssets3);
        assertEq(vault.withdrawalShares(lastBucket), withdrawnAssets2 + withdrawnAssets3);
        assertEq(vault.withdrawalSharesOf(1, alice), withdrawnAssets3);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(vault.totalStake(), _expectedTotalStake(uint48(blockTimestamp)));
    }

    function test_RedeemRevertInvalidClaimer(uint256 amount1) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        vm.expectRevert(IVault.InvalidClaimer.selector);
        vm.startPrank(alice);
        vault.redeem(address(0), amount1);
        vm.stopPrank();
    }

    function test_RedeemRevertInsufficientRedeemption(uint256 amount1) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        vm.expectRevert(IVault.InsufficientRedemption.selector);
        _redeem(alice, 0);
    }

    function test_RedeemRevertTooMuchRedeem(uint256 amount1) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        vm.expectRevert(IVault.TooMuchRedeem.selector);
        _redeem(alice, amount1 + 1);
    }

    function test_Claim(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        uint256 tokensBefore = collateral.balanceOf(address(vault));
        uint256 tokensBeforeAlice = collateral.balanceOf(alice);
        assertEq(_claim(alice, 0), amount2);
        assertEq(tokensBefore - collateral.balanceOf(address(vault)), amount2);
        assertEq(collateral.balanceOf(alice) - tokensBeforeAlice, amount2);

        assertEq(vault.isWithdrawalsClaimed(0, alice), true);
    }

    function test_ClaimRevertInvalidRecipient(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        vm.startPrank(alice);
        vm.expectRevert(IVault.InvalidRecipient.selector);
        vault.claim(address(0), 0);
        vm.stopPrank();
    }

    function test_ClaimRevertInvalidIndex(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        vm.expectRevert(stdError.indexOOBError);
        _claim(alice, 10);
    }

    function test_ClaimRevertAlreadyClaimed(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        _claim(alice, 0);

        vm.expectRevert(IVault.AlreadyClaimed.selector);
        _claim(alice, 0);
    }

    function test_ClaimRevertWithdrawalNotMatured(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 7;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        vm.expectRevert(IVault.WithdrawalNotMatured.selector);
        _claim(alice, 0);
    }

    function test_ClaimBatch(uint256 amount1, uint256 amount2, uint256 amount3) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount3, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2 + amount3);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount3);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        uint256[] memory indexes = new uint256[](2);
        indexes[0] = 0;
        indexes[1] = 1;

        uint256 tokensBefore = collateral.balanceOf(address(vault));
        uint256 tokensBeforeAlice = collateral.balanceOf(alice);
        assertEq(_claimBatch(alice, indexes), amount2 + amount3);
        assertEq(tokensBefore - collateral.balanceOf(address(vault)), amount2 + amount3);
        assertEq(collateral.balanceOf(alice) - tokensBeforeAlice, amount2 + amount3);

        assertEq(vault.isWithdrawalsClaimed(0, alice), true);
    }

    function test_ClaimBatchRevertInvalidRecipient(uint256 amount1, uint256 amount2, uint256 amount3) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount3, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2 + amount3);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount3);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        uint256[] memory indexes = new uint256[](2);
        indexes[0] = 0;
        indexes[1] = 1;

        vm.expectRevert(IVault.InvalidRecipient.selector);
        vm.startPrank(alice);
        vault.claimBatch(address(0), indexes);
        vm.stopPrank();
    }

    function test_ClaimBatchRevertInvalidLengthEpochs(uint256 amount1, uint256 amount2, uint256 amount3) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount3, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2 + amount3);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount3);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        uint256[] memory indexes = new uint256[](0);
        vm.expectRevert(IVault.InvalidLengthEpochs.selector);
        _claimBatch(alice, indexes);
    }

    function test_ClaimBatchRevertInvalidEpoch(uint256 amount1, uint256 amount2, uint256 amount3) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount3, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2 + amount3);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount3);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        uint256[] memory indexes = new uint256[](2);
        indexes[0] = 0;
        indexes[1] = 2;

        vm.expectRevert(stdError.indexOOBError);
        _claimBatch(alice, indexes);
    }

    function test_ClaimBatchRevertAlreadyClaimed(uint256 amount1, uint256 amount2, uint256 amount3) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount3, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2 + amount3);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount3);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        uint256[] memory indexes = new uint256[](2);
        indexes[0] = 0;
        indexes[1] = 0;

        vm.expectRevert(IVault.AlreadyClaimed.selector);
        _claimBatch(alice, indexes);
    }

    function test_ClaimBatchRevertInsufficientClaim(uint256 amount1, uint256 amount2, uint256 amount3) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount3, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2 + amount3);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount3);

        uint256[] memory indexes = new uint256[](2);
        indexes[0] = 0;
        indexes[1] = 1;

        vm.expectRevert(IVault.WithdrawalNotMatured.selector);
        _claimBatch(alice, indexes);
    }

    function test_TotalStakeUnlockBoundary(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, amount1);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 10;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        uint48 unlockAt = vault.withdrawalUnlockAt(0, alice);
        assertEq(unlockAt, uint48(blockTimestamp + epochDuration));
        assertEq(vault.totalStake(), amount1);

        vm.warp(unlockAt);
        assertEq(vault.totalStake(), amount1 - amount2);

        vm.expectRevert(IVault.WithdrawalNotMatured.selector);
        _claim(alice, 0);

        vm.warp(uint256(unlockAt) + 1);
        assertEq(_claim(alice, 0), amount2);
    }

    function test_SetDepositWhitelist() public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);
        assertEq(vault.depositWhitelist(), true);

        _setDepositWhitelist(alice, false);
        assertEq(vault.depositWhitelist(), false);
    }

    function test_SetDepositWhitelistRevertNotWhitelistedDepositor() public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        _deposit(alice, 1);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);

        vm.startPrank(alice);
        vm.expectRevert(IVault.NotWhitelistedDepositor.selector);
        vault.deposit(alice, 1);
        vm.stopPrank();
    }

    function test_SetDepositWhitelistRevertAlreadySet() public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);

        vm.expectRevert(IVault.AlreadySet.selector);
        _setDepositWhitelist(alice, true);
    }

    function test_SetDepositorWhitelistStatus() public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);

        _grantDepositorWhitelistRole(alice, alice);

        _setDepositorWhitelistStatus(alice, bob, true);
        assertEq(vault.isDepositorWhitelisted(bob), true);

        _deposit(bob, 1);

        _setDepositWhitelist(alice, false);

        _deposit(bob, 1);
    }

    function test_SetDepositorWhitelistStatusRevertInvalidAccount() public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);

        _grantDepositorWhitelistRole(alice, alice);

        vm.expectRevert(IVault.InvalidAccount.selector);
        _setDepositorWhitelistStatus(alice, address(0), true);
    }

    function test_SetDepositorWhitelistStatusRevertAlreadySet() public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);

        _grantDepositorWhitelistRole(alice, alice);

        _setDepositorWhitelistStatus(alice, bob, true);

        vm.expectRevert(IVault.AlreadySet.selector);
        _setDepositorWhitelistStatus(alice, bob, true);
    }

    function test_SetIsDepositLimit() public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        _grantIsDepositLimitSetRole(alice, alice);
        _setIsDepositLimit(alice, true);
        assertEq(vault.isDepositLimit(), true);

        _setIsDepositLimit(alice, false);
        assertEq(vault.isDepositLimit(), false);
    }

    function test_SetIsDepositLimitRevertAlreadySet() public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        _grantIsDepositLimitSetRole(alice, alice);
        _setIsDepositLimit(alice, true);

        vm.expectRevert(IVault.AlreadySet.selector);
        _setIsDepositLimit(alice, true);
    }

    function test_SetDepositLimit(uint256 limit1, uint256 limit2, uint256 depositAmount) public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        _grantIsDepositLimitSetRole(alice, alice);
        _setIsDepositLimit(alice, true);
        assertEq(vault.depositLimit(), 0);

        limit1 = bound(limit1, 1, type(uint256).max);
        _grantDepositLimitSetRole(alice, alice);
        _setDepositLimit(alice, limit1);
        assertEq(vault.depositLimit(), limit1);

        limit2 = bound(limit2, 1, 1000 ether);
        vm.assume(limit2 != limit1);
        _setDepositLimit(alice, limit2);
        assertEq(vault.depositLimit(), limit2);

        depositAmount = bound(depositAmount, 1, limit2);
        _deposit(alice, depositAmount);
    }

    function test_SetDepositLimitToNull(uint256 limit1) public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        limit1 = bound(limit1, 1, type(uint256).max);
        _grantIsDepositLimitSetRole(alice, alice);
        _setIsDepositLimit(alice, true);
        _grantDepositLimitSetRole(alice, alice);
        _setDepositLimit(alice, limit1);

        _setIsDepositLimit(alice, false);

        _setDepositLimit(alice, 0);

        assertEq(vault.depositLimit(), 0);
    }

    function test_SetDepositLimitRevertDepositLimitReached(uint256 depositAmount, uint256 limit) public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        _deposit(alice, 1);

        limit = bound(limit, 2, 1000 ether);
        _grantIsDepositLimitSetRole(alice, alice);
        _setIsDepositLimit(alice, true);
        _grantDepositLimitSetRole(alice, alice);
        _setDepositLimit(alice, limit);

        depositAmount = bound(depositAmount, limit, 2000 ether);

        collateral.transfer(alice, depositAmount);
        vm.startPrank(alice);
        collateral.approve(address(vault), depositAmount);
        vm.expectRevert(IVault.DepositLimitReached.selector);
        vault.deposit(alice, depositAmount);
        vm.stopPrank();
    }

    function test_SetDepositLimitRevertAlreadySet(uint256 limit) public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        limit = bound(limit, 1, type(uint256).max);
        _grantIsDepositLimitSetRole(alice, alice);
        _setIsDepositLimit(alice, true);
        _grantDepositLimitSetRole(alice, alice);
        _setDepositLimit(alice, limit);

        vm.expectRevert(IVault.AlreadySet.selector);
        _setDepositLimit(alice, limit);
    }

    function test_MigrateWithdrawals_FactoryUpgradePath() public {
        uint48 epochDuration = 10;

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
        (IVault vault_,, ) = _createInitializedVaultWithOwner(
            epochDuration,
            networkLimitSetRoleHolders,
            operatorNetworkSharesSetRoleHolders,
            1,
            address(0xdEaD),
            false,
            false,
            0,
            address(this)
        );
        VaultV1 vaultV1 = VaultV1(address(vault_));
        vault = IVault(address(vaultV1));

        uint256 aliceDeposit = 1000;
        uint256 bobDeposit = 500;
        _deposit(alice, aliceDeposit);
        _deposit(bob, bobDeposit);

        uint256 aliceWithdrawEpoch0 = 200;
        uint256 bobWithdrawEpoch0 = 100;
        _withdraw(alice, aliceWithdrawEpoch0);
        _withdraw(bob, bobWithdrawEpoch0);

        uint256 epoch1Start = blockTimestamp + epochDuration;
        vm.warp(epoch1Start + 1);

        uint256 aliceWithdrawEpoch1 = 150;
        uint256 bobWithdrawEpoch1 = 60;
        _withdraw(alice, aliceWithdrawEpoch1);
        _withdraw(bob, bobWithdrawEpoch1);

        uint256 epoch2Start = blockTimestamp + 2 * epochDuration;
        vm.warp(epoch2Start + 1);

        uint256 epoch1Withdrawals = aliceWithdrawEpoch0 + bobWithdrawEpoch0;
        uint256 epoch2Withdrawals = aliceWithdrawEpoch1 + bobWithdrawEpoch1;
        uint256 expectedAliceEpoch1 = Math.mulDiv(aliceWithdrawEpoch0, epoch1Withdrawals + 1, epoch1Withdrawals + 1);

        vm.startPrank(alice);
        assertEq(vault.claim(alice, 1), expectedAliceEpoch1);
        vm.stopPrank();

        uint256 migrateTimestamp = epoch2Start + epochDuration / 2;
        vm.warp(migrateTimestamp);

        vaultFactory.migrate(address(vaultV1), vaultFactory.lastVersion(), "");

        IVault vaultV2 = IVault(address(vaultV1));

        uint48 nextEpochStart = uint48(blockTimestamp + 3 * epochDuration);
        assertEq(vaultTestHelper.withdrawalSharesPrefixesLength(address(vaultV2)), 2);

        (uint48 prefixKey0, uint256 prefixVal0) = vaultTestHelper.withdrawalSharesPrefixesAt(address(vaultV2), 0);
        assertEq(prefixKey0, nextEpochStart);
        assertEq(prefixVal0, epoch2Withdrawals);

        (uint48 prefixKey1, uint256 prefixVal1) = vaultTestHelper.withdrawalSharesPrefixesAt(address(vaultV2), 1);
        assertEq(prefixKey1, uint48(nextEpochStart + epochDuration));
        assertEq(prefixVal1, epoch2Withdrawals);

        assertEq(vaultTestHelper.timeToBucketLength(address(vaultV2)), 3);
        (uint48 bucketKey, uint208 bucketVal) = vaultTestHelper.timeToBucketAt(address(vaultV2), 2);
        assertEq(bucketKey, nextEpochStart);
        assertEq(bucketVal, 2);

        vm.expectRevert();
        vaultV2.migrateWithdrawalsOf(alice, 1);

        vaultV2.migrateWithdrawalsOf(bob, 1);
        vaultV2.migrateWithdrawalsOf(alice, 2);
        vaultV2.migrateWithdrawalsOf(bob, 2);

        assertEq(vaultV2.withdrawalsLength(bob), 2);
        assertEq(vaultV2.withdrawalsLength(alice), 1);

        assertEq(vaultV2.withdrawalUnlockAt(0, bob), uint48(epoch2Start));
        assertEq(vaultV2.withdrawalUnlockAt(1, bob), nextEpochStart);
        assertEq(vaultV2.withdrawalUnlockAt(0, alice), nextEpochStart);

        (uint48 bucketKeyPre, uint208 bucketValPre) = vaultTestHelper.timeToBucketAt(address(vaultV2), 1);
        assertEq(bucketKeyPre, uint48(epoch2Start));
        assertEq(bucketValPre, 1);

        uint256 expectedBobEpoch1 = Math.mulDiv(bobWithdrawEpoch0, epoch1Withdrawals + 1, epoch1Withdrawals + 1);
        uint256 expectedAliceEpoch2 = Math.mulDiv(aliceWithdrawEpoch1, epoch2Withdrawals + 1, epoch2Withdrawals + 1);
        uint256 expectedBobEpoch2 = Math.mulDiv(bobWithdrawEpoch1, epoch2Withdrawals + 1, epoch2Withdrawals + 1);

        assertEq(vaultV2.withdrawalSharesOf(0, bob), bobWithdrawEpoch0);
        assertEq(vaultV2.withdrawalSharesOf(1, bob), expectedBobEpoch2);
        assertEq(vaultV2.withdrawalSharesOf(0, alice), expectedAliceEpoch2);

        assertEq(vaultV2.withdrawalsOf(0, bob), expectedBobEpoch1);
        assertEq(vaultV2.withdrawalsOf(1, bob), expectedBobEpoch2);
        assertEq(vaultV2.withdrawalsOf(0, alice), expectedAliceEpoch2);

        uint256 bobBalanceBefore = collateral.balanceOf(bob);
        vm.startPrank(bob);
        vaultV2.claim(bob, 0);
        vm.stopPrank();
        assertEq(collateral.balanceOf(bob) - bobBalanceBefore, expectedBobEpoch1);

        vm.startPrank(alice);
        vm.expectRevert(IVault.WithdrawalNotMatured.selector);
        vaultV2.claim(alice, 0);
        vm.stopPrank();

        vm.warp(uint256(nextEpochStart) + 1);
        uint256 aliceBalanceBefore = collateral.balanceOf(alice);
        vm.startPrank(alice);
        vaultV2.claim(alice, 0);
        vm.stopPrank();
        assertEq(collateral.balanceOf(alice) - aliceBalanceBefore, expectedAliceEpoch2);
    }

    function test_MigrateWithdrawals_ClaimAfterUpgrade() public {
        uint48 epochDuration = 5;

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
        (IVault vault_,, ) = _createInitializedVaultWithOwner(
            epochDuration,
            networkLimitSetRoleHolders,
            operatorNetworkSharesSetRoleHolders,
            1,
            address(0xdEaD),
            false,
            false,
            0,
            address(this)
        );
        VaultV1 vaultV1 = VaultV1(address(vault_));
        vault = IVault(address(vaultV1));

        uint256 aliceDeposit = 1000;
        _deposit(alice, aliceDeposit);

        uint256 withdrawEpoch0 = 250;
        _withdraw(alice, withdrawEpoch0);

        uint256 epoch1Start = blockTimestamp + epochDuration;
        vm.warp(epoch1Start + 1);

        uint256 withdrawEpoch1 = 180;
        _withdraw(alice, withdrawEpoch1);

        uint256 epoch2Start = blockTimestamp + 2 * epochDuration;
        vm.warp(epoch2Start + epochDuration / 2);

        vaultFactory.migrate(address(vaultV1), vaultFactory.lastVersion(), "");

        IVault vaultV2 = IVault(address(vaultV1));
        vaultV2.migrateWithdrawalsOf(alice, 1);
        vaultV2.migrateWithdrawalsOf(alice, 2);

        uint256 expectedEpoch1 = Math.mulDiv(withdrawEpoch0, withdrawEpoch0 + 1, withdrawEpoch0 + 1);
        uint256 expectedEpoch2 = Math.mulDiv(withdrawEpoch1, withdrawEpoch1 + 1, withdrawEpoch1 + 1);

        uint256 aliceBalanceBefore = collateral.balanceOf(alice);
        vm.startPrank(alice);
        vaultV2.claim(alice, 0);
        vm.stopPrank();
        assertEq(collateral.balanceOf(alice) - aliceBalanceBefore, expectedEpoch1);
        assertEq(vaultV2.isWithdrawalsClaimed(0, alice), true);

        uint48 nextEpochStart = uint48(blockTimestamp + 3 * epochDuration);
        vm.warp(uint256(nextEpochStart) + 1);

        aliceBalanceBefore = collateral.balanceOf(alice);
        vm.startPrank(alice);
        vaultV2.claim(alice, 1);
        vm.stopPrank();
        assertEq(collateral.balanceOf(alice) - aliceBalanceBefore, expectedEpoch2);
        assertEq(vaultV2.isWithdrawalsClaimed(1, alice), true);
    }

    function test_OnSlashRevertNotSlasher() public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        vm.startPrank(alice);
        vm.expectRevert(IVault.NotSlasher.selector);
        vault.onSlash(0, 0);
        vm.stopPrank();
    }

    struct Test_SlashStruct {
        uint256 slashAmountReal1;
        uint256 tokensBeforeBurner;
        uint256 activeStake1;
        uint256 withdrawals1;
        uint256 nextWithdrawals1;
        uint256 slashAmountSlashed2;
    }

    function test_Slash_NoWithdrawals(
        // uint48 withdrawalDelay,
        uint256 depositAmount,
        uint256 withdrawAmount1,
        uint256 withdrawAmount2,
        uint256 slashAmount1,
        uint256 slashAmount2,
        uint256 captureAgo
    ) public {
        // withdrawalDelay = uint48(bound(withdrawalDelay, 2, 10 days));
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        captureAgo = bound(captureAgo, 1, 7 days);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max / 2);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(7 days);

        _prepareVault();

        _deposit(alice, depositAmount);
        blockTimestamp = blockTimestamp + captureAgo;
        vm.warp(blockTimestamp);

        assertEq(
            _slash(alice, alice, alice, slashAmount1, uint48(blockTimestamp - captureAgo), ""),
            Math.min(slashAmount1, depositAmount)
        );
    }

    function test_Slash_MaturedWithdrawals(
        uint256 depositAmount,
        uint256 withdrawAmount1,
        uint256 withdrawAmount2,
        uint256 slashAmount1,
        uint256 slashAmount2,
        uint256 captureAgo
    ) public {
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        withdrawAmount1 = bound(withdrawAmount1, 1, 100 * 10 ** 18);
        withdrawAmount2 = bound(withdrawAmount2, 1, 100 * 10 ** 18);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max / 2);
        slashAmount2 = bound(slashAmount2, 1, type(uint256).max / 2);
        captureAgo = bound(captureAgo, 1, 10 days);
        vm.assume(captureAgo <= 7 days);
        vm.assume(depositAmount > withdrawAmount1 + withdrawAmount2);
        vm.assume(depositAmount > slashAmount1);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(7 days);

        _prepareVault();

        _deposit(alice, depositAmount);
        _withdraw(alice, withdrawAmount1);

        blockTimestamp = blockTimestamp + 10;
        vm.warp(blockTimestamp);

        _withdraw(alice, withdrawAmount2);

        blockTimestamp = blockTimestamp + 7 days + 1;
        vm.warp(blockTimestamp);

        uint256 activeStake = depositAmount - withdrawAmount1 - withdrawAmount2;
        assertEq(vault.totalStake(), _expectedTotalStake(uint48(blockTimestamp)));
        assertEq(vault.activeStake(), activeStake);
        uint256 lastBucket = _latestWithdrawalBucket();
        assertEq(vault.withdrawals(lastBucket), withdrawAmount1 + withdrawAmount2);

        blockTimestamp = blockTimestamp + vault.epochDuration();
        vm.warp(blockTimestamp);

        uint256 slashAmountReal = Math.min(slashAmount1, activeStake);
        uint256 tokensBeforeBurner = collateral.balanceOf(address(vault.burner()));
        assertEq(_slash(alice, alice, alice, slashAmount1, uint48(blockTimestamp - captureAgo), ""), slashAmountReal);
        assertEq(collateral.balanceOf(address(vault.burner())) - tokensBeforeBurner, slashAmountReal);
        assertApproxEqAbs(vault.activeStake(), activeStake - slashAmountReal, 10);
    }

    function test_Slash_NotMaturedWithdrawals(
        uint256 depositAmount,
        uint256 withdrawAmount1,
        uint256 withdrawAmount2,
        uint256 slashAmount1,
        uint256 slashAmount2,
        uint256 captureAgo
    ) public {
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        withdrawAmount1 = bound(withdrawAmount1, 1, 100 * 10 ** 18);
        withdrawAmount2 = bound(withdrawAmount2, 1, 100 * 10 ** 18);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max / 2);
        slashAmount2 = bound(slashAmount2, 1, type(uint256).max / 2);
        captureAgo = 1 days;
        vm.assume(depositAmount > withdrawAmount1 + withdrawAmount2);
        vm.assume(depositAmount > slashAmount1);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(7 days);

        _prepareVault();

        _deposit(alice, depositAmount);
        _withdraw(alice, withdrawAmount1);

        blockTimestamp = blockTimestamp + 10;
        vm.warp(blockTimestamp);

        _withdraw(alice, withdrawAmount2);

        blockTimestamp = blockTimestamp + captureAgo;
        vm.warp(blockTimestamp);

        uint256 activeStake = vault.activeStake();
        uint256 lastBucket = _latestWithdrawalBucket();
        uint256 lastWithdrawals = vault.withdrawals(lastBucket);
        uint256 lastWithdrawalShares = vault.withdrawalShares(lastBucket);
        uint256 unmaturedWithdrawalShares = _unmaturedWithdrawalShares(uint48(blockTimestamp));
        uint256 unmaturedWithdrawals =
            lastWithdrawalShares == 0 ? 0 : unmaturedWithdrawalShares.mulDiv(lastWithdrawals, lastWithdrawalShares);
        uint256 slashableStake = activeStake + unmaturedWithdrawals;
        uint256 slashAmountReal = Math.min(slashAmount1, activeStake);
        uint256 tokensBeforeBurner = collateral.balanceOf(address(vault.burner()));
        console2.log("-------slasher", address(slasher));

        assertEq(_slash(alice, alice, alice, slashAmount1, uint48(blockTimestamp - captureAgo), ""), slashAmountReal);
        assertEq(collateral.balanceOf(address(vault.burner())) - tokensBeforeBurner, slashAmountReal);

        uint256 activeSlashed = slashAmountReal.mulDiv(activeStake, slashableStake);
        uint256 activeStakeAfter = activeStake - activeSlashed;
        assertApproxEqAbs(vault.activeStake(), activeStakeAfter, 10);

        uint256 unmaturedSlashed = slashAmountReal - activeSlashed;
        uint256 withdrawalsAfter = unmaturedWithdrawals - unmaturedSlashed;
        assertApproxEqAbs(vault.withdrawals(lastBucket + 1), withdrawalsAfter, 10);
    }

    function test_SlashTwice(
        uint256 depositAmount,
        uint256 withdrawAmount1,
        uint256 withdrawAmount2,
        uint256 slashAmount1,
        uint256 slashAmount2,
        uint256 captureAgo
    ) public {
        depositAmount = bound(depositAmount, 1, 100 * 10 ** 18);
        withdrawAmount1 = bound(withdrawAmount1, 1, 100 * 10 ** 18);
        withdrawAmount2 = bound(withdrawAmount2, 1, 100 * 10 ** 18);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max / 2);
        slashAmount2 = bound(slashAmount2, 1, type(uint256).max / 2);
        captureAgo = 1 days;
        vm.assume(depositAmount > withdrawAmount1 + withdrawAmount2);
        vm.assume(depositAmount > slashAmount1 + slashAmount2);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(7 days);

        _prepareVault();

        _deposit(alice, depositAmount);
        _withdraw(alice, withdrawAmount1);

        blockTimestamp = blockTimestamp + 10;
        vm.warp(blockTimestamp);

        _withdraw(alice, withdrawAmount2);

        blockTimestamp = blockTimestamp + captureAgo;
        vm.warp(blockTimestamp);

        // First slash
        uint256 slashAmountReal1 = _slash(alice, alice, alice, slashAmount1, uint48(blockTimestamp - captureAgo), "");

        blockTimestamp = blockTimestamp + captureAgo;
        vm.warp(blockTimestamp);

        // Second slash
        // Calculate unmatured withdrawals the same way the slash function does
        uint256 lastBucket2 = _latestWithdrawalBucket();
        uint256 lastWithdrawals2 = vault.withdrawals(lastBucket2);
        uint256 lastWithdrawalShares2 = vault.withdrawalShares(lastBucket2);
        uint256 unmaturedWithdrawalShares2 =
            vaultTestHelper.withdrawalSharesPrefixesLatest(address(vault))
                - vaultTestHelper.withdrawalSharesPrefixesUpperLookupRecent(address(vault), uint48(blockTimestamp));
        uint256 unmaturedWithdrawals2 =
            lastWithdrawalShares2 == 0 ? 0 : unmaturedWithdrawalShares2.mulDiv(lastWithdrawals2, lastWithdrawalShares2);

        uint256 activeStake2 = vault.activeStake();
        uint256 slashableStake2 = activeStake2 + unmaturedWithdrawals2;

        uint256 slashAmountReal2 = _slash(alice, alice, alice, slashAmount2, uint48(blockTimestamp - captureAgo), "");

        // Calculate state after second slash
        uint256 activeSlashed2 = slashAmountReal2.mulDiv(activeStake2, slashableStake2);
        uint256 activeStakeAfter = activeStake2 - activeSlashed2;
        assertApproxEqAbs(vault.activeStake(), activeStakeAfter, 10);

        // The unmatured withdrawals are slashed proportionally
        uint256 unmaturedSlashed2 = slashAmountReal2 - activeSlashed2;
        uint256 withdrawalsAfter = unmaturedWithdrawals2 - unmaturedSlashed2;
        assertApproxEqAbs(vault.withdrawals(lastBucket2 + 1), withdrawalsAfter, 10);
    }

    function _latestWithdrawalBucket() internal view returns (uint256) {
        return vaultTestHelper.timeToBucketLatest(address(vault));
    }

    function _unmaturedWithdrawalShares(uint48 timestamp) internal view returns (uint256) {
        return vaultTestHelper.withdrawalSharesPrefixesLatest(address(vault))
            - vaultTestHelper.withdrawalSharesPrefixesUpperLookupRecent(address(vault), timestamp);
    }

    function _expectedTotalStake(uint48 timestamp) internal view returns (uint256) {
        uint256 lastBucket = _latestWithdrawalBucket();
        uint256 lastWithdrawalShares = vault.withdrawalShares(lastBucket);
        uint256 activeStake_ = vault.activeStake();
        if (lastWithdrawalShares == 0) {
            return activeStake_;
        }
        uint256 unmaturedShares = _unmaturedWithdrawalShares(timestamp);
        return activeStake_ + unmaturedShares.mulDiv(vault.withdrawals(lastBucket), lastWithdrawalShares);
    }

    function _prepareVault() internal {
        _registerNetwork(alice, alice);
        _setMaxNetworkLimit(alice, 0, type(uint256).max);

        _registerOperator(alice);
        _registerOperator(bob);

        _optInOperatorVault(alice);
        _optInOperatorVault(bob);

        _optInOperatorNetwork(alice, address(alice));
        _optInOperatorNetwork(bob, address(alice));

        _setNetworkLimit(alice, alice, type(uint256).max);

        _setOperatorNetworkLimit(alice, alice, alice, type(uint256).max / 2);
        _setOperatorNetworkLimit(alice, alice, bob, type(uint256).max / 2);
    }

    function _getVault(uint48 epochDuration) internal returns (IVault) {
        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
        (IVault vault_,,) = _createInitializedVault(
            epochDuration,
            networkLimitSetRoleHolders,
            operatorNetworkSharesSetRoleHolders,
            vaultFactory.lastVersion(),
            address(0xdEaD),
            false,
            false,
            0
        );
        return vault_;
    }

    function _getVaultAndDelegatorAndSlasher(uint48 epochDuration)
        internal
        returns (IVault, FullRestakeDelegator, Slasher)
    {
        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](1);
        operatorNetworkLimitSetRoleHolders[0] = alice;
        (IVault vault_, address delegator_, address slasher_) = _createInitializedVault(
            epochDuration,
            networkLimitSetRoleHolders,
            operatorNetworkLimitSetRoleHolders,
            vaultFactory.lastVersion(),
            address(0xdEaD),
            false,
            false,
            0
        );

        return (IVault(vault_), FullRestakeDelegator(delegator_), Slasher(slasher_));
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

    function _grantDepositorWhitelistRole(address user, address account) internal virtual {
        vm.startPrank(user);
        Vault(address(vault)).grantRole(vault.DEPOSITOR_WHITELIST_ROLE(), account);
        vm.stopPrank();
    }

    function _grantDepositWhitelistSetRole(address user, address account) internal virtual {
        vm.startPrank(user);
        Vault(address(vault)).grantRole(vault.DEPOSIT_WHITELIST_SET_ROLE(), account);
        vm.stopPrank();
    }

    function _grantIsDepositLimitSetRole(address user, address account) internal virtual {
        vm.startPrank(user);
        Vault(address(vault)).grantRole(vault.IS_DEPOSIT_LIMIT_SET_ROLE(), account);
        vm.stopPrank();
    }

    function _grantDepositLimitSetRole(address user, address account) internal virtual {
        vm.startPrank(user);
        Vault(address(vault)).grantRole(vault.DEPOSIT_LIMIT_SET_ROLE(), account);
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

    function _redeem(address user, uint256 shares) internal returns (uint256 withdrawnAssets, uint256 mintedShares) {
        vm.startPrank(user);
        (withdrawnAssets, mintedShares) = vault.redeem(user, shares);
        vm.stopPrank();
    }

    function _claim(address user, uint256 epoch) internal returns (uint256 amount) {
        vm.startPrank(user);
        amount = vault.claim(user, epoch);
        vm.stopPrank();
    }

    function _claimBatch(address user, uint256[] memory indexes) internal returns (uint256 amount) {
        vm.startPrank(user);
        amount = vault.claimBatch(user, indexes);
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

    function _setDepositWhitelist(address user, bool status) internal {
        vm.startPrank(user);
        vault.setDepositWhitelist(status);
        vm.stopPrank();
    }

    function _setDepositorWhitelistStatus(address user, address depositor, bool status) internal {
        vm.startPrank(user);
        vault.setDepositorWhitelistStatus(depositor, status);
        vm.stopPrank();
    }

    function _setIsDepositLimit(address user, bool status) internal {
        vm.startPrank(user);
        vault.setIsDepositLimit(status);
        vm.stopPrank();
    }

    function _setDepositLimit(address user, uint256 amount) internal {
        vm.startPrank(user);
        vault.setDepositLimit(amount);
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

    function _createVaultImpl(address delegatorFactory, address slasherFactory, address vaultFactory)
        internal
        virtual
        returns (address)
    {
        return address(new Vault(delegatorFactory, slasherFactory, vaultFactory));
    }

    function _createVaultV1Impl(address delegatorFactory, address slasherFactory, address vaultFactory)
        internal
        virtual
        returns (address)
    {
        return address(new VaultV1(delegatorFactory, slasherFactory, vaultFactory));
    }

    function _createInitializedVault(
        uint48 epochDuration,
        address[] memory networkLimitSetRoleHolders,
        address[] memory operatorNetworkSharesSetRoleHolders,
        uint64 version,
        address burner,
        bool depositWhitelist,
        bool isDepositLimit,
        uint256 depositLimit
    ) internal virtual returns (IVault, address, address) {
        return _createInitializedVaultWithOwner(
            epochDuration,
            networkLimitSetRoleHolders,
            operatorNetworkSharesSetRoleHolders,
            version,
            burner,
            depositWhitelist,
            isDepositLimit,
            depositLimit,
            address(0)
        );
    }

    function _createInitializedVaultWithOwner(
        uint48 epochDuration,
        address[] memory networkLimitSetRoleHolders,
        address[] memory operatorNetworkSharesSetRoleHolders,
        uint64 version,
        address burner,
        bool depositWhitelist,
        bool isDepositLimit,
        uint256 depositLimit,
        address owner_
    ) internal virtual returns (IVault, address, address) {
        (address vault_, address delegator_, address slasher_) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: version,
                owner: owner_,
                vaultParams: abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: burner,
                        epochDuration: epochDuration,
                        depositWhitelist: depositWhitelist,
                        isDepositLimit: isDepositLimit,
                        depositLimit: depositLimit,
                        defaultAdminRoleHolder: alice,
                        depositWhitelistSetRoleHolder: alice,
                        depositorWhitelistRoleHolder: alice,
                        isDepositLimitSetRoleHolder: alice,
                        depositLimitSetRoleHolder: alice
                    })
                ),
                delegatorIndex: 1,
                delegatorParams: abi.encode(
                    INetworkRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: alice, hook: address(0), hookSetRoleHolder: alice
                        }),
                        networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                        operatorNetworkSharesSetRoleHolders: operatorNetworkSharesSetRoleHolders
                    })
                ),
                withSlasher: true,
                slasherIndex: 0,
                slasherParams: abi.encode(
                    ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})})
                )
            })
        );

        return (IVault(vault_), address(delegator_), address(slasher_));
    }

    function _getEncodedVaultParams(IVault.InitParams memory params) internal pure virtual returns (bytes memory) {
        return abi.encode(params);
    }
}
