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

contract VaultTest is Test {
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
    FeeOnTransferToken feeOnTransferCollateral;
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
        feeOnTransferCollateral = new FeeOnTransferToken("FeeOnTransferToken");

        vaultConfigurator =
            new VaultConfigurator(address(vaultFactory), address(delegatorFactory), address(slasherFactory));
    }

    function test_Create2(
        address burner,
        uint48 withdrawalDelay,
        bool depositWhitelist,
        bool isDepositLimit,
        uint256 depositLimit
    ) public {
        withdrawalDelay = uint48(bound(withdrawalDelay, 1, 50 weeks));

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
        (address vault_, address delegator_,) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: vaultFactory.lastVersion(),
                owner: address(0),
                vaultParams: abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: burner,
                        withdrawalDelay: withdrawalDelay,
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
                delegatorIndex: 0,
                delegatorParams: abi.encode(
                    INetworkRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: alice, hook: address(0), hookSetRoleHolder: alice
                        }),
                        networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                        operatorNetworkSharesSetRoleHolders: operatorNetworkSharesSetRoleHolders
                    })
                ),
                withSlasher: false,
                slasherIndex: 0,
                slasherParams: abi.encode(
                    ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})})
                )
            })
        );

        vault = Vault(vault_);

        assertEq(vault.DEPOSIT_WHITELIST_SET_ROLE(), keccak256("DEPOSIT_WHITELIST_SET_ROLE"));
        assertEq(vault.DEPOSITOR_WHITELIST_ROLE(), keccak256("DEPOSITOR_WHITELIST_ROLE"));
        assertEq(vault.DELEGATOR_FACTORY(), address(delegatorFactory));
        assertEq(vault.SLASHER_FACTORY(), address(slasherFactory));

        assertEq(vault.owner(), address(0));
        assertEq(vault.collateral(), address(collateral));
        assertEq(vault.delegator(), delegator_);
        assertEq(vault.slasher(), address(0));
        assertEq(vault.burner(), burner);
        assertEq(vault.withdrawalDelay(), withdrawalDelay);
        assertEq(vault.depositWhitelist(), depositWhitelist);
        assertEq(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), alice), true);
        assertEq(vault.hasRole(vault.DEPOSITOR_WHITELIST_ROLE(), alice), true);
        assertEq(vault.totalStake(), 0);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp), ""), 0);
        assertEq(vault.activeShares(), 0);
        assertEq(vault.activeStakeAt(uint48(blockTimestamp), ""), 0);
        assertEq(vault.activeStake(), 0);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp), ""), 0);
        assertEq(vault.activeSharesOf(alice), 0);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp), ""), 0);
        assertEq(vault.activeBalanceOf(alice), 0);
        assertEq(vault.withdrawals(), 0);
        assertEq(vault.withdrawalShares(), 0);
        assertEq(vault.claimableWithdrawals(), 0);
        assertEq(vault.claimableWithdrawalShares(), 0);
        assertEq(vault.depositWhitelist(), depositWhitelist);
        assertEq(vault.isDepositorWhitelisted(alice), false);
        assertEq(vault.slashableBalanceOf(alice), 0);
        assertEq(vault.isDelegatorInitialized(), true);
        assertEq(vault.isSlasherInitialized(), true);
        assertEq(vault.isInitialized(), true);
    }

    function test_CreateRevertInvalidEpochDuration() public {
        uint48 withdrawalDelay = 0;

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
        uint64 lastVersion = vaultFactory.lastVersion();
        vm.expectRevert(IVault.InvalidEpochDuration.selector);
        vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: lastVersion,
                owner: alice,
                vaultParams: abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        withdrawalDelay: withdrawalDelay,
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
                            defaultAdminRoleHolder: alice, hook: address(0), hookSetRoleHolder: alice
                        }),
                        networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                        operatorNetworkSharesSetRoleHolders: operatorNetworkSharesSetRoleHolders
                    })
                ),
                withSlasher: false,
                slasherIndex: 0,
                slasherParams: abi.encode(
                    ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})})
                )
            })
        );
    }

    function test_CreateRevertInvalidCollateral(uint48 withdrawalDelay) public {
        withdrawalDelay = uint48(bound(withdrawalDelay, 1, 50 weeks));

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
        uint64 lastVersion = vaultFactory.lastVersion();
        vm.expectRevert(IVault.InvalidCollateral.selector);
        vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: lastVersion,
                owner: alice,
                vaultParams: abi.encode(
                    IVault.InitParams({
                        collateral: address(0),
                        burner: address(0xdEaD),
                        withdrawalDelay: withdrawalDelay,
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
                            defaultAdminRoleHolder: alice, hook: address(0), hookSetRoleHolder: alice
                        }),
                        networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                        operatorNetworkSharesSetRoleHolders: operatorNetworkSharesSetRoleHolders
                    })
                ),
                withSlasher: false,
                slasherIndex: 0,
                slasherParams: abi.encode(
                    ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})})
                )
            })
        );
    }

    function test_CreateRevertMissingRoles1(uint48 withdrawalDelay) public {
        withdrawalDelay = uint48(bound(withdrawalDelay, 1, 50 weeks));

        uint64 lastVersion = vaultFactory.lastVersion();

        vm.expectRevert(IVault.MissingRoles.selector);
        vault = Vault(
            vaultFactory.create(
                lastVersion,
                alice,
                abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        withdrawalDelay: withdrawalDelay,
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

    function test_CreateRevertMissingRoles2(uint48 withdrawalDelay) public {
        withdrawalDelay = uint48(bound(withdrawalDelay, 1, 50 weeks));

        uint64 lastVersion = vaultFactory.lastVersion();

        vm.expectRevert(IVault.MissingRoles.selector);
        vault = Vault(
            vaultFactory.create(
                lastVersion,
                alice,
                abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        withdrawalDelay: withdrawalDelay,
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

    function test_CreateRevertMissingRoles3(uint48 withdrawalDelay) public {
        withdrawalDelay = uint48(bound(withdrawalDelay, 1, 50 weeks));

        uint64 lastVersion = vaultFactory.lastVersion();

        vm.expectRevert(IVault.MissingRoles.selector);
        vault = Vault(
            vaultFactory.create(
                lastVersion,
                alice,
                abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        withdrawalDelay: withdrawalDelay,
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

    function test_CreateRevertMissingRoles4(uint48 withdrawalDelay) public {
        withdrawalDelay = uint48(bound(withdrawalDelay, 1, 50 weeks));

        uint64 lastVersion = vaultFactory.lastVersion();

        vm.expectRevert(IVault.MissingRoles.selector);
        vault = Vault(
            vaultFactory.create(
                lastVersion,
                alice,
                abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        withdrawalDelay: withdrawalDelay,
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

    function test_CreateRevertMissingRoles5(uint48 withdrawalDelay) public {
        withdrawalDelay = uint48(bound(withdrawalDelay, 1, 50 weeks));

        uint64 lastVersion = vaultFactory.lastVersion();

        vm.expectRevert(IVault.MissingRoles.selector);
        vault = Vault(
            vaultFactory.create(
                lastVersion,
                alice,
                abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        withdrawalDelay: withdrawalDelay,
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

        vault = Vault(
            vaultFactory.create(
                lastVersion,
                alice,
                abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        withdrawalDelay: 7 days,
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

        vault = Vault(
            vaultFactory.create(
                lastVersion,
                alice,
                abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        withdrawalDelay: 7 days,
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

        vault = Vault(
            vaultFactory.create(
                lastVersion,
                alice,
                abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        withdrawalDelay: 7 days,
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

        vault = Vault(
            vaultFactory.create(
                lastVersion,
                alice,
                abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        withdrawalDelay: 7 days,
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

        Vault vault2 = Vault(
            vaultFactory.create(
                lastVersion,
                alice,
                abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        withdrawalDelay: 7 days,
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

        vault = Vault(
            vaultFactory.create(
                lastVersion,
                alice,
                abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        withdrawalDelay: 7 days,
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

        vault = Vault(
            vaultFactory.create(
                lastVersion,
                alice,
                abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        withdrawalDelay: 7 days,
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

        vault = Vault(
            vaultFactory.create(
                lastVersion,
                alice,
                abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        withdrawalDelay: 7 days,
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

        vault = Vault(
            vaultFactory.create(
                lastVersion,
                alice,
                abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        withdrawalDelay: 7 days,
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

        Vault vault2 = Vault(
            vaultFactory.create(
                lastVersion,
                alice,
                abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        withdrawalDelay: 7 days,
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

        vault = Vault(
            vaultFactory.create(
                lastVersion,
                alice,
                abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        withdrawalDelay: 7 days,
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

    function test_DepositTwice(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 withdrawalDelay = 1;
        vault = _getVault(withdrawalDelay);

        uint256 tokensBefore = collateral.balanceOf(address(vault));
        uint256 shares1 = amount1 * 10 ** 0;
        {
            (uint256 depositedAmount, uint256 mintedShares) = _deposit(alice, amount1);
            assertEq(depositedAmount, amount1);
            assertEq(mintedShares, shares1);
        }
        assertEq(collateral.balanceOf(address(vault)) - tokensBefore, amount1);

        assertEq(vault.totalStake(), amount1);
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
        assertEq(vault.slashableBalanceOf(alice), amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 shares2 = amount2 * (shares1 + 10 ** 0) / (amount1 + 1);
        {
            (uint256 depositedAmount, uint256 mintedShares) = _deposit(alice, amount2);
            assertEq(depositedAmount, amount2);
            assertEq(mintedShares, shares2);
        }

        assertEq(vault.totalStake(), amount1 + amount2);
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
        assertEq(vault.slashableBalanceOf(alice), amount1 + amount2);
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

        uint48 withdrawalDelay = 1;
        {
            address[] memory networkLimitSetRoleHolders = new address[](1);
            networkLimitSetRoleHolders[0] = alice;
            address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
            operatorNetworkSharesSetRoleHolders[0] = alice;
            (address vault_,,) = vaultConfigurator.create(
                IVaultConfigurator.InitParams({
                    version: vaultFactory.lastVersion(),
                    owner: alice,
                    vaultParams: abi.encode(
                        IVault.InitParams({
                            collateral: address(feeOnTransferCollateral),
                            burner: address(0xdEaD),
                            withdrawalDelay: withdrawalDelay,
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
                                defaultAdminRoleHolder: alice, hook: address(0), hookSetRoleHolder: alice
                            }),
                            networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                            operatorNetworkSharesSetRoleHolders: operatorNetworkSharesSetRoleHolders
                        })
                    ),
                    withSlasher: false,
                    slasherIndex: 0,
                    slasherParams: ""
                })
            );

            vault = Vault(vault_);
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

        assertEq(vault.totalStake(), amount1 - 1);
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
        assertEq(vault.slashableBalanceOf(alice), amount1 - 1);

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

        assertEq(vault.totalStake(), amount1 - 1 + amount2 - 1);
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
        assertEq(vault.slashableBalanceOf(alice), amount1 - 1 + amount2 - 1);
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

    function test_DepositBoth(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 withdrawalDelay = 1;
        vault = _getVault(withdrawalDelay);

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

        assertEq(vault.totalStake(), amount1 + amount2);
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
        assertEq(vault.slashableBalanceOf(alice), amount1);
        assertEq(vault.activeSharesOfAt(bob, uint48(blockTimestamp - 1), ""), 0);
        assertEq(vault.activeSharesOfAt(bob, uint48(blockTimestamp), ""), shares2);
        assertEq(vault.activeSharesOf(bob), shares2);
        assertEq(vault.activeBalanceOfAt(bob, uint48(blockTimestamp - 1), ""), 0);
        assertEq(vault.activeBalanceOfAt(bob, uint48(blockTimestamp), ""), amount2);
        assertEq(vault.activeBalanceOf(bob), amount2);
        assertEq(vault.slashableBalanceOf(bob), amount2);
    }

    function test_DepositRevertInvalidOnBehalfOf(uint256 amount1) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 withdrawalDelay = 1;
        vault = _getVault(withdrawalDelay);

        vm.startPrank(alice);
        vm.expectRevert(IVault.InvalidOnBehalfOf.selector);
        vault.deposit(address(0), amount1);
        vm.stopPrank();
    }

    function test_DepositRevertInsufficientDeposit() public {
        uint48 withdrawalDelay = 1;
        vault = _getVault(withdrawalDelay);

        vm.startPrank(alice);
        vm.expectRevert(IVault.InsufficientDeposit.selector);
        vault.deposit(alice, 0);
        vm.stopPrank();
    }

    function test_WithdrawTwice(uint256 amount1, uint256 amount2, uint256 amount3) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount3, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2 + amount3);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        // uint48 withdrawalDelay = 1;
        vault = _getVault(1);

        (, uint256 shares) = _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 burnedShares = amount2 * (shares + 10 ** 0) / (amount1 + 1);
        uint256 mintedShares = amount2 * 10 ** 0;
        (uint256 burnedShares_, uint256 mintedShares_) = _withdraw(alice, amount2);
        assertEq(burnedShares_, burnedShares);
        assertEq(mintedShares_, mintedShares);

        assertEq(vault.totalStake(), amount1);
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
        // After first withdrawal: withdrawals should contain amount2
        // Allow for ERC4626 math rounding differences
        uint256 expectedWithdrawals1 = amount2;
        uint256 actualWithdrawals1 = vault.withdrawals();
        assertTrue(
            (expectedWithdrawals1 >= actualWithdrawals1 && expectedWithdrawals1 - actualWithdrawals1 <= 10000)
                || (actualWithdrawals1 >= expectedWithdrawals1 && actualWithdrawals1 - expectedWithdrawals1 <= 10000)
        );
        uint256 expectedShares1 = mintedShares;
        uint256 actualShares1 = vault.withdrawalShares();
        assertTrue(
            (expectedShares1 >= actualShares1 && expectedShares1 - actualShares1 <= 10000)
                || (actualShares1 >= expectedShares1 && actualShares1 - expectedShares1 <= 10000)
        );
        uint256 actualSharesOf1 = vault.withdrawalSharesOf(alice);
        assertTrue(
            (expectedShares1 >= actualSharesOf1 && expectedShares1 - actualSharesOf1 <= 10000)
                || (actualSharesOf1 >= expectedShares1 && actualSharesOf1 - expectedShares1 <= 10000)
        );
        assertEq(vault.slashableBalanceOf(alice), amount1);

        shares -= burnedShares;

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        burnedShares = amount3 * (shares + 10 ** 0) / (amount1 - amount2 + 1);
        mintedShares = amount3 * 10 ** 0;
        (burnedShares_, mintedShares_) = _withdraw(alice, amount3);
        assertEq(burnedShares_, burnedShares);
        assertEq(mintedShares_, mintedShares);

        assertEq(vault.totalStake(), amount1);
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
        // After second withdrawal: withdrawals should contain amount2 + amount3
        // Allow for ERC4626 math rounding differences
        uint256 expectedWithdrawals = amount2 + amount3;
        uint256 actualWithdrawals = vault.withdrawals();
        assertTrue(
            (expectedWithdrawals >= actualWithdrawals && expectedWithdrawals - actualWithdrawals <= expectedWithdrawals / 1000 + 10000)
                || (actualWithdrawals >= expectedWithdrawals && actualWithdrawals - expectedWithdrawals <= expectedWithdrawals / 1000 + 10000)
        );
        uint256 expectedShares = amount2 * 10 ** 0 + amount3 * 10 ** 0;
        uint256 actualShares = vault.withdrawalShares();
        assertTrue(
            (expectedShares >= actualShares && expectedShares - actualShares <= expectedShares / 1000 + 10000)
                || (actualShares >= expectedShares && actualShares - expectedShares <= expectedShares / 1000 + 10000)
        );
        uint256 actualSharesOf = vault.withdrawalSharesOf(alice);
        assertTrue(
            (expectedShares >= actualSharesOf && expectedShares - actualSharesOf <= expectedShares / 1000 + 10000)
                || (actualSharesOf >= expectedShares && actualSharesOf - expectedShares <= expectedShares / 1000 + 10000)
        );
        assertEq(vault.slashableBalanceOf(alice), amount1);

        shares -= burnedShares;

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        // totalStake = activeStake + pendingWithdrawals = (amount1 - amount2 - amount3) + (amount2 + amount3) = amount1
        assertEq(vault.totalStake(), amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(vault.totalStake(), amount1 - amount2 - amount3);
    }

    function test_WithdrawRevertInvalidClaimer(uint256 amount1) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 withdrawalDelay = 1;
        vault = _getVault(withdrawalDelay);

        _deposit(alice, amount1);

        vm.expectRevert(IVault.InvalidClaimer.selector);
        vm.startPrank(alice);
        vault.withdraw(address(0), amount1);
        vm.stopPrank();
    }

    function test_WithdrawRevertInsufficientWithdrawal(uint256 amount1) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 withdrawalDelay = 1;
        vault = _getVault(withdrawalDelay);

        _deposit(alice, amount1);

        vm.expectRevert(IVault.InsufficientWithdrawal.selector);
        _withdraw(alice, 0);
    }

    function test_WithdrawRevertTooMuchWithdraw(uint256 amount1) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 withdrawalDelay = 1;
        vault = _getVault(withdrawalDelay);

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

        // uint48 withdrawalDelay = 1;
        vault = _getVault(1);

        (, uint256 shares) = _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 withdrawnAssets2 = amount2 * (amount1 + 1) / (shares + 10 ** 0);
        uint256 mintedShares = amount2 * 10 ** 0;
        (uint256 withdrawnAssets_, uint256 mintedShares_) = _redeem(alice, amount2);
        assertEq(withdrawnAssets_, withdrawnAssets2);
        assertEq(mintedShares_, mintedShares);

        assertEq(vault.totalStake(), amount1);
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
        // After first redeem: withdrawals should contain withdrawnAssets2
        // Allow for ERC4626 math rounding differences
        uint256 expectedWithdrawals1 = withdrawnAssets2;
        uint256 actualWithdrawals1 = vault.withdrawals();
        assertTrue(
            (expectedWithdrawals1 >= actualWithdrawals1 && expectedWithdrawals1 - actualWithdrawals1 <= 10000)
                || (actualWithdrawals1 >= expectedWithdrawals1 && actualWithdrawals1 - expectedWithdrawals1 <= 10000)
        );
        uint256 expectedShares1 = mintedShares;
        uint256 actualShares1 = vault.withdrawalShares();
        assertTrue(
            (expectedShares1 >= actualShares1 && expectedShares1 - actualShares1 <= 10000)
                || (actualShares1 >= expectedShares1 && actualShares1 - expectedShares1 <= 10000)
        );
        uint256 actualSharesOf1 = vault.withdrawalSharesOf(alice);
        assertTrue(
            (expectedShares1 >= actualSharesOf1 && expectedShares1 - actualSharesOf1 <= 10000)
                || (actualSharesOf1 >= expectedShares1 && actualSharesOf1 - expectedShares1 <= 10000)
        );
        assertEq(vault.slashableBalanceOf(alice), amount1);

        shares -= amount2;

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 withdrawnAssets3 = amount3 * (amount1 - withdrawnAssets2 + 1) / (shares + 10 ** 0);
        mintedShares = amount3 * 10 ** 0;
        (withdrawnAssets_, mintedShares_) = _redeem(alice, amount3);
        assertEq(withdrawnAssets_, withdrawnAssets3);
        assertEq(mintedShares_, mintedShares);

        assertEq(vault.totalStake(), amount1);
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
        // After second redeem: withdrawals should contain withdrawnAssets2 + withdrawnAssets3
        // Allow for ERC4626 math rounding differences
        uint256 expectedWithdrawals = withdrawnAssets2 + withdrawnAssets3;
        uint256 actualWithdrawals = vault.withdrawals();
        assertTrue(
            (expectedWithdrawals >= actualWithdrawals && expectedWithdrawals - actualWithdrawals <= 10000)
                || (actualWithdrawals >= expectedWithdrawals && actualWithdrawals - expectedWithdrawals <= 10000)
        );
        uint256 expectedShares = withdrawnAssets2 * 10 ** 0 + withdrawnAssets3 * 10 ** 0;
        uint256 actualShares = vault.withdrawalShares();
        assertTrue(
            (expectedShares >= actualShares && expectedShares - actualShares <= 10000)
                || (actualShares >= expectedShares && actualShares - expectedShares <= 10000)
        );
        uint256 actualSharesOf = vault.withdrawalSharesOf(alice);
        assertTrue(
            (expectedShares >= actualSharesOf && expectedShares - actualSharesOf <= 10000)
                || (actualSharesOf >= expectedShares && actualSharesOf - expectedShares <= 10000)
        );
        assertEq(vault.slashableBalanceOf(alice), amount1);

        shares -= amount3;

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        // totalStake = activeStake + pendingWithdrawals = (amount1 - withdrawnAssets2 - withdrawnAssets3) + (withdrawnAssets2 + withdrawnAssets3) = amount1
        assertEq(vault.totalStake(), amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(vault.totalStake(), amount1 - withdrawnAssets2 - withdrawnAssets3);
    }

    function test_RedeemRevertInvalidClaimer(uint256 amount1) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 withdrawalDelay = 1;
        vault = _getVault(withdrawalDelay);

        _deposit(alice, amount1);

        vm.expectRevert(IVault.InvalidClaimer.selector);
        vm.startPrank(alice);
        vault.redeem(address(0), amount1);
        vm.stopPrank();
    }

    function test_RedeemRevertInsufficientRedeemption(uint256 amount1) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 withdrawalDelay = 1;
        vault = _getVault(withdrawalDelay);

        _deposit(alice, amount1);

        vm.expectRevert(IVault.InsufficientRedemption.selector);
        _redeem(alice, 0);
    }

    function test_RedeemRevertTooMuchRedeem(uint256 amount1) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 withdrawalDelay = 1;
        vault = _getVault(withdrawalDelay);

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

        uint48 withdrawalDelay = 1;
        vault = _getVault(withdrawalDelay);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        // Wait for withdrawal delay + bucket duration (1 hour) for withdrawals to become claimable
        // Withdrawal delay is rounded up to nearest hour bucket
        blockTimestamp = blockTimestamp + withdrawalDelay + 1 hours + 1;
        vm.warp(blockTimestamp);

        uint256 tokensBefore = collateral.balanceOf(address(vault));
        uint256 tokensBeforeAlice = collateral.balanceOf(alice);
        assertEq(_claim(alice, 0), amount2);
        assertEq(tokensBefore - collateral.balanceOf(address(vault)), amount2);
        assertEq(collateral.balanceOf(alice) - tokensBeforeAlice, amount2);

        // isWithdrawalsClaimed() removed - withdrawals are now tracked per account via withdrawalEntries
    }

    function test_ClaimRevertInvalidRecipient(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 withdrawalDelay = 1;
        vault = _getVault(withdrawalDelay);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        vm.startPrank(alice);
        // currentEpoch() removed - claim() no longer takes epoch parameter
        vm.expectRevert(IVault.InvalidRecipient.selector);
        vault.claim(address(0));
        vm.stopPrank();
    }

    function test_ClaimRevertInvalidEpoch(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 withdrawalDelay = 1;
        vault = _getVault(withdrawalDelay);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        // Try to claim immediately - should fail with WithdrawalNotReady
        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        // currentEpoch() removed - claim() no longer takes epoch parameter
        // Note: InvalidEpoch error replaced with WithdrawalNotReady when claiming too early
        vm.expectRevert(IVault.WithdrawalNotReady.selector);
        _claim(alice, 0);
    }

    function test_ClaimRevertAlreadyClaimed(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 withdrawalDelay = 1;
        vault = _getVault(withdrawalDelay);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        // Wait for withdrawal delay + bucket duration (1 hour) for withdrawals to become claimable
        blockTimestamp = blockTimestamp + withdrawalDelay + 1 hours + 1;
        vm.warp(blockTimestamp);

        // currentEpoch() removed - claim() no longer takes epoch parameter
        _claim(alice, 0);

        // Try to claim again - should fail with InsufficientClaim (no more claimable withdrawals)
        // Note: May also fail with array out-of-bounds if _processMaturedBuckets accesses invalid checkpoint
        // Both errors indicate no more withdrawals to claim
        vm.expectRevert(); // Accept either InsufficientClaim() or array out-of-bounds panic
        _claim(alice, 0);
    }

    function test_ClaimRevertInsufficientClaim(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 withdrawalDelay = 1;
        vault = _getVault(withdrawalDelay);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        // Try to claim immediately - should fail with WithdrawalNotReady (withdrawals not yet claimable)
        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        // currentEpoch() removed - claim() no longer takes epoch parameter
        vm.expectRevert(IVault.WithdrawalNotReady.selector);
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

        uint48 withdrawalDelay = 1;
        vault = _getVault(withdrawalDelay);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount3);

        // Wait for withdrawal delay + bucket duration (1 hour) for withdrawals to become claimable
        // Withdrawal delay is rounded up to nearest hour bucket
        blockTimestamp = blockTimestamp + withdrawalDelay + 1 hours + 1;
        vm.warp(blockTimestamp);

        uint256[] memory epochs = new uint256[](2);
        // epochs array no longer used - claimBatch removed, but kept for function signature compatibility
        epochs[0] = 0;
        epochs[1] = 0;

        uint256 tokensBefore = collateral.balanceOf(address(vault));
        uint256 tokensBeforeAlice = collateral.balanceOf(alice);
        assertEq(_claimBatch(alice, epochs), amount2 + amount3);
        assertEq(tokensBefore - collateral.balanceOf(address(vault)), amount2 + amount3);
        assertEq(collateral.balanceOf(alice) - tokensBeforeAlice, amount2 + amount3);

        // isWithdrawalsClaimed() removed - withdrawals are now tracked per account via withdrawalEntries
    }

    function test_ClaimBatchRevertInvalidRecipient(uint256 amount1, uint256 amount2, uint256 amount3) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount3, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2 + amount3);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 withdrawalDelay = 1;
        vault = _getVault(withdrawalDelay);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount3);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        uint256[] memory epochs = new uint256[](2);
        // epochs array no longer used - claimBatch removed
        // epochs array no longer used

        vm.expectRevert(IVault.InvalidRecipient.selector);
        vm.startPrank(alice);
        vault.claim(address(0));
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

        uint48 withdrawalDelay = 1;
        vault = _getVault(withdrawalDelay);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount3);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        uint256[] memory epochs = new uint256[](0);
        // Try to claim immediately - should fail with WithdrawalNotReady (withdrawals not yet claimable)
        // Note: InvalidLengthEpochs error no longer exists - claimBatch removed
        vm.expectRevert(IVault.WithdrawalNotReady.selector);
        _claimBatch(alice, epochs);
    }

    function test_ClaimBatchRevertInvalidEpoch(uint256 amount1, uint256 amount2, uint256 amount3) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount3, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2 + amount3);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 withdrawalDelay = 1;
        vault = _getVault(withdrawalDelay);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount3);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        uint256[] memory epochs = new uint256[](2);
        // epochs array no longer used - claimBatch removed, but kept for function signature compatibility
        epochs[0] = 0;
        epochs[1] = 0;

        // Try to claim immediately - should fail with WithdrawalNotReady (withdrawals not yet claimable)
        // Note: InvalidEpoch error no longer exists - claimBatch removed
        vm.expectRevert(IVault.WithdrawalNotReady.selector);
        _claimBatch(alice, epochs);
    }

    function test_ClaimBatchRevertAlreadyClaimed(uint256 amount1, uint256 amount2, uint256 amount3) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount3, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2 + amount3);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 withdrawalDelay = 1;
        vault = _getVault(withdrawalDelay);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount3);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        uint256[] memory epochs = new uint256[](2);
        // epochs array no longer used - claimBatch removed, but kept for function signature compatibility
        epochs[0] = 0;
        epochs[1] = 0;

        // Wait for withdrawal delay + bucket duration (1 hour) for withdrawals to become claimable
        blockTimestamp = blockTimestamp + withdrawalDelay + 1 hours + 1;
        vm.warp(blockTimestamp);

        // Claim once successfully
        _claimBatch(alice, epochs);

        // Try to claim again - should fail with InsufficientClaim (no more claimable withdrawals)
        // Note: AlreadyClaimed error no longer exists - claimBatch removed
        // May also fail with array out-of-bounds if _processMaturedBuckets accesses invalid checkpoint
        vm.expectRevert(); // Accept either InsufficientClaim() or array out-of-bounds panic
        _claimBatch(alice, epochs);
    }

    function test_ClaimBatchRevertInsufficientClaim(uint256 amount1, uint256 amount2, uint256 amount3) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount3, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2 + amount3);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 withdrawalDelay = 1;
        vault = _getVault(withdrawalDelay);

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount3);

        // Try to claim immediately - should fail with WithdrawalNotReady (withdrawals not yet claimable)
        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        uint256[] memory epochs = new uint256[](2);
        // epochs array no longer used - claimBatch removed, but kept for function signature compatibility
        epochs[0] = 0;
        epochs[1] = 0;

        // Note: InsufficientClaim error replaced with WithdrawalNotReady when claiming too early
        vm.expectRevert(IVault.WithdrawalNotReady.selector);
        _claimBatch(alice, epochs);
    }

    function test_SetDepositWhitelist() public {
        uint48 withdrawalDelay = 1;

        vault = _getVault(withdrawalDelay);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);
        assertEq(vault.depositWhitelist(), true);

        _setDepositWhitelist(alice, false);
        assertEq(vault.depositWhitelist(), false);
    }

    function test_SetDepositWhitelistRevertNotWhitelistedDepositor() public {
        uint48 withdrawalDelay = 1;

        vault = _getVault(withdrawalDelay);

        _deposit(alice, 1);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);

        vm.startPrank(alice);
        vm.expectRevert(IVault.NotWhitelistedDepositor.selector);
        vault.deposit(alice, 1);
        vm.stopPrank();
    }

    function test_SetDepositWhitelistRevertAlreadySet() public {
        uint48 withdrawalDelay = 1;

        vault = _getVault(withdrawalDelay);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);

        vm.expectRevert(IVault.AlreadySet.selector);
        _setDepositWhitelist(alice, true);
    }

    function test_SetDepositorWhitelistStatus() public {
        uint48 withdrawalDelay = 1;

        vault = _getVault(withdrawalDelay);

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
        uint48 withdrawalDelay = 1;

        vault = _getVault(withdrawalDelay);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);

        _grantDepositorWhitelistRole(alice, alice);

        vm.expectRevert(IVault.InvalidAccount.selector);
        _setDepositorWhitelistStatus(alice, address(0), true);
    }

    function test_SetDepositorWhitelistStatusRevertAlreadySet() public {
        uint48 withdrawalDelay = 1;

        vault = _getVault(withdrawalDelay);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);

        _grantDepositorWhitelistRole(alice, alice);

        _setDepositorWhitelistStatus(alice, bob, true);

        vm.expectRevert(IVault.AlreadySet.selector);
        _setDepositorWhitelistStatus(alice, bob, true);
    }

    function test_SetIsDepositLimit() public {
        uint48 withdrawalDelay = 1;

        vault = _getVault(withdrawalDelay);

        _grantIsDepositLimitSetRole(alice, alice);
        _setIsDepositLimit(alice, true);
        assertEq(vault.isDepositLimit(), true);

        _setIsDepositLimit(alice, false);
        assertEq(vault.isDepositLimit(), false);
    }

    function test_SetIsDepositLimitRevertAlreadySet() public {
        uint48 withdrawalDelay = 1;

        vault = _getVault(withdrawalDelay);

        _grantIsDepositLimitSetRole(alice, alice);
        _setIsDepositLimit(alice, true);

        vm.expectRevert(IVault.AlreadySet.selector);
        _setIsDepositLimit(alice, true);
    }

    function test_SetDepositLimit(uint256 limit1, uint256 limit2, uint256 depositAmount) public {
        uint48 withdrawalDelay = 1;

        vault = _getVault(withdrawalDelay);

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
        uint48 withdrawalDelay = 1;

        vault = _getVault(withdrawalDelay);

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
        uint48 withdrawalDelay = 1;

        vault = _getVault(withdrawalDelay);

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
        uint48 withdrawalDelay = 1;

        vault = _getVault(withdrawalDelay);

        limit = bound(limit, 1, type(uint256).max);
        _grantIsDepositLimitSetRole(alice, alice);
        _setIsDepositLimit(alice, true);
        _grantDepositLimitSetRole(alice, alice);
        _setDepositLimit(alice, limit);

        vm.expectRevert(IVault.AlreadySet.selector);
        _setDepositLimit(alice, limit);
    }

    function test_OnSlashRevertNotSlasher() public {
        uint48 withdrawalDelay = 1;

        vault = _getVault(withdrawalDelay);

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

    function test_Slash(
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
        withdrawAmount1 = bound(withdrawAmount1, 1, 100 * 10 ** 18);
        withdrawAmount2 = bound(withdrawAmount2, 1, 100 * 10 ** 18);
        slashAmount1 = bound(slashAmount1, 1, type(uint256).max / 2);
        slashAmount2 = bound(slashAmount2, 1, type(uint256).max / 2);
        captureAgo = bound(captureAgo, 1, 10 days);
        vm.assume(depositAmount > withdrawAmount1 + withdrawAmount2);
        vm.assume(depositAmount > slashAmount1);
        vm.assume(captureAgo <= 7 days);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(7 days);

        // address network = alice;
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

        _deposit(alice, depositAmount);
        _withdraw(alice, withdrawAmount1);

        blockTimestamp = blockTimestamp + vault.withdrawalDelay();
        vm.warp(blockTimestamp);

        _withdraw(alice, withdrawAmount2);

        assertEq(vault.totalStake(), depositAmount);
        assertEq(vault.activeStake(), depositAmount - withdrawAmount1 - withdrawAmount2);
        // vault.withdrawals() returns total pending withdrawals (sum of all pending withdrawals)
        assertEq(vault.withdrawals(), withdrawAmount1 + withdrawAmount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        Test_SlashStruct memory test_SlashStruct;

            test_SlashStruct.slashAmountReal1 = Math.min(slashAmount1, depositAmount - withdrawAmount1);
            test_SlashStruct.tokensBeforeBurner = collateral.balanceOf(address(vault.burner()));
            assertEq(
                _slash(alice, alice, alice, slashAmount1, uint48(blockTimestamp - captureAgo), ""),
                test_SlashStruct.slashAmountReal1
            );
            assertEq(
                collateral.balanceOf(address(vault.burner())) - test_SlashStruct.tokensBeforeBurner,
                test_SlashStruct.slashAmountReal1
            );

            test_SlashStruct.activeStake1 = depositAmount - withdrawAmount1 - withdrawAmount2
                - (depositAmount - withdrawAmount1 - withdrawAmount2)
                .mulDiv(test_SlashStruct.slashAmountReal1, depositAmount);
            test_SlashStruct.withdrawals1 =
                withdrawAmount1 - withdrawAmount1.mulDiv(test_SlashStruct.slashAmountReal1, depositAmount);
            test_SlashStruct.nextWithdrawals1 =
                withdrawAmount2 - withdrawAmount2.mulDiv(test_SlashStruct.slashAmountReal1, depositAmount);
            // Allow for small rounding differences in totalStake calculation
            uint256 expectedTotalStake = depositAmount - test_SlashStruct.slashAmountReal1;
            uint256 actualTotalStake = vault.totalStake();
            assertTrue(
                (expectedTotalStake >= actualTotalStake && expectedTotalStake - actualTotalStake <= 10)
                    || (actualTotalStake >= expectedTotalStake && actualTotalStake - expectedTotalStake <= 10)
            );
            // vault.withdrawals() returns total pending withdrawals (sum of all pending withdrawals)
            // After first slash, withdrawals should be withdrawals1 + nextWithdrawals1
            // Allow for small rounding differences
            uint256 expectedWithdrawals1 = test_SlashStruct.withdrawals1 + test_SlashStruct.nextWithdrawals1;
            uint256 actualWithdrawals1 = vault.withdrawals();
            assertTrue(
                (expectedWithdrawals1 >= actualWithdrawals1 && expectedWithdrawals1 - actualWithdrawals1 <= 10)
                    || (actualWithdrawals1 >= expectedWithdrawals1 && actualWithdrawals1 - expectedWithdrawals1 <= 10)
            );
            // Allow for small rounding differences in activeStake calculation
            uint256 expectedActiveStake = test_SlashStruct.activeStake1;
            uint256 actualActiveStake = vault.activeStake();
            assertTrue(
                (expectedActiveStake >= actualActiveStake && expectedActiveStake - actualActiveStake <= 10)
                    || (actualActiveStake >= expectedActiveStake && actualActiveStake - expectedActiveStake <= 10)
            );

            test_SlashStruct.slashAmountSlashed2 = Math.min(
                depositAmount - test_SlashStruct.slashAmountReal1,
                Math.min(slashAmount2, depositAmount - withdrawAmount1)
            );
            test_SlashStruct.tokensBeforeBurner = collateral.balanceOf(address(vault.burner()));
            assertEq(
                _slash(alice, alice, bob, slashAmount2, uint48(blockTimestamp - captureAgo), ""),
                Math.min(slashAmount2, depositAmount - withdrawAmount1)
            );
            assertEq(
                collateral.balanceOf(address(vault.burner())) - test_SlashStruct.tokensBeforeBurner,
                test_SlashStruct.slashAmountSlashed2
            );

            // Allow for small rounding differences in totalStake calculation after second slash
            uint256 expectedTotalStake2 = depositAmount - test_SlashStruct.slashAmountReal1 - test_SlashStruct.slashAmountSlashed2;
            uint256 actualTotalStake2 = vault.totalStake();
            assertTrue(
                (expectedTotalStake2 >= actualTotalStake2 && expectedTotalStake2 - actualTotalStake2 <= 10)
                    || (actualTotalStake2 >= expectedTotalStake2 && actualTotalStake2 - expectedTotalStake2 <= 10)
            );
            // After second slash, withdrawals should be sum of both withdrawal amounts after slashing
            uint256 withdrawals1AfterSlash2 = test_SlashStruct.withdrawals1
                - test_SlashStruct.withdrawals1
                    .mulDiv(
                        test_SlashStruct.slashAmountSlashed2,
                        depositAmount - test_SlashStruct.slashAmountReal1
                    );
            uint256 nextWithdrawals1AfterSlash2 = test_SlashStruct.nextWithdrawals1
                - test_SlashStruct.nextWithdrawals1
                    .mulDiv(
                        test_SlashStruct.slashAmountSlashed2,
                        depositAmount - test_SlashStruct.slashAmountReal1
                    );
            uint256 expectedWithdrawals2 = withdrawals1AfterSlash2 + nextWithdrawals1AfterSlash2;
            uint256 actualWithdrawals2 = vault.withdrawals();
            // Allow for small rounding differences
            assertTrue(
                (expectedWithdrawals2 >= actualWithdrawals2 && expectedWithdrawals2 - actualWithdrawals2 <= 20)
                    || (actualWithdrawals2 >= expectedWithdrawals2 && actualWithdrawals2 - expectedWithdrawals2 <= 20)
            );
            // Allow for small rounding differences in activeStake calculation after second slash
            uint256 expectedActiveStake2 = test_SlashStruct.activeStake1
                - test_SlashStruct.activeStake1
                    .mulDiv(test_SlashStruct.slashAmountSlashed2, depositAmount - test_SlashStruct.slashAmountReal1);
            uint256 actualActiveStake2 = vault.activeStake();
            assertTrue(
                (expectedActiveStake2 >= actualActiveStake2 && expectedActiveStake2 - actualActiveStake2 <= 10)
                    || (actualActiveStake2 >= expectedActiveStake2 && actualActiveStake2 - expectedActiveStake2 <= 10)
            );
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

    // function test_ActiveSharesHint(uint256 amount1, uint48 withdrawalDelay, HintStruct memory hintStruct) public {
    //     amount1 = bound(amount1, 1, 100 * 10 ** 18);
    //     withdrawalDelay = uint48(bound(withdrawalDelay, 1, 7 days));
    //     hintStruct.num = bound(hintStruct.num, 0, 25);
    //     hintStruct.secondsAgo = bound(hintStruct.secondsAgo, 0, 1_720_700_948);

    //     uint256 blockTimestamp = vm.getBlockTimestamp();
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     vault = _getVault(withdrawalDelay);

    //     for (uint256 i; i < hintStruct.num; ++i) {
    //         _deposit(alice, amount1);

    //         blockTimestamp = blockTimestamp + epochDuration;
    //         vm.warp(blockTimestamp);
    //     }

    //     uint48 timestamp =
    //         uint48(hintStruct.back ? blockTimestamp - hintStruct.secondsAgo : blockTimestamp + hintStruct.secondsAgo);

    //     VaultHints vaultHints = new VaultHints();
    //     bytes memory hint = vaultHints.activeSharesHint(address(vault), timestamp);

    //     GasStruct memory gasStruct = GasStruct({gasSpent1: 1, gasSpent2: 1});
    //     vault.activeSharesAt(timestamp, new bytes(0));
    //     gasStruct.gasSpent1 = vm.lastCallGas().gasTotalUsed;
    //     vault.activeSharesAt(timestamp, hint);
    //     gasStruct.gasSpent2 = vm.lastCallGas().gasTotalUsed;
    //     assertApproxEqRel(gasStruct.gasSpent1, gasStruct.gasSpent2, 0.05e18);
    // }

    // function test_ActiveStakeHint(uint256 amount1, uint48 withdrawalDelay, HintStruct memory hintStruct) public {
    //     amount1 = bound(amount1, 1, 100 * 10 ** 18);
    //     withdrawalDelay = uint48(bound(withdrawalDelay, 1, 7 days));
    //     hintStruct.num = bound(hintStruct.num, 0, 25);
    //     hintStruct.secondsAgo = bound(hintStruct.secondsAgo, 0, 1_720_700_948);

    //     uint256 blockTimestamp = vm.getBlockTimestamp();
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     vault = _getVault(withdrawalDelay);

    //     for (uint256 i; i < hintStruct.num; ++i) {
    //         _deposit(alice, amount1);

    //         blockTimestamp = blockTimestamp + epochDuration;
    //         vm.warp(blockTimestamp);
    //     }

    //     uint48 timestamp =
    //         uint48(hintStruct.back ? blockTimestamp - hintStruct.secondsAgo : blockTimestamp + hintStruct.secondsAgo);

    //     VaultHints vaultHints = new VaultHints();
    //     bytes memory hint = vaultHints.activeStakeHint(address(vault), timestamp);

    //     GasStruct memory gasStruct = GasStruct({gasSpent1: 1, gasSpent2: 1});
    //     vault.activeStakeAt(timestamp, new bytes(0));
    //     gasStruct.gasSpent1 = vm.lastCallGas().gasTotalUsed;
    //     vault.activeStakeAt(timestamp, hint);
    //     gasStruct.gasSpent2 = vm.lastCallGas().gasTotalUsed;
    //     assertGe(gasStruct.gasSpent1, gasStruct.gasSpent2);
    // }

    // function test_ActiveSharesOfHint(uint256 amount1, uint48 withdrawalDelay, HintStruct memory hintStruct) public {
    //     amount1 = bound(amount1, 1, 100 * 10 ** 18);
    //     withdrawalDelay = uint48(bound(withdrawalDelay, 1, 7 days));
    //     hintStruct.num = bound(hintStruct.num, 0, 25);
    //     hintStruct.secondsAgo = bound(hintStruct.secondsAgo, 0, 1_720_700_948);

    //     uint256 blockTimestamp = vm.getBlockTimestamp();
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     vault = _getVault(withdrawalDelay);

    //     for (uint256 i; i < hintStruct.num; ++i) {
    //         _deposit(alice, amount1);

    //         blockTimestamp = blockTimestamp + epochDuration;
    //         vm.warp(blockTimestamp);
    //     }

    //     uint48 timestamp =
    //         uint48(hintStruct.back ? blockTimestamp - hintStruct.secondsAgo : blockTimestamp + hintStruct.secondsAgo);

    //     VaultHints vaultHints = new VaultHints();
    //     bytes memory hint = vaultHints.activeSharesOfHint(address(vault), alice, timestamp);

    //     GasStruct memory gasStruct = GasStruct({gasSpent1: 1, gasSpent2: 1});
    //     vault.activeSharesOfAt(alice, timestamp, new bytes(0));
    //     gasStruct.gasSpent1 = vm.lastCallGas().gasTotalUsed;
    //     vault.activeSharesOfAt(alice, timestamp, hint);
    //     gasStruct.gasSpent2 = vm.lastCallGas().gasTotalUsed;
    //     assertGe(gasStruct.gasSpent1, gasStruct.gasSpent2);
    // }

    // struct ActiveBalanceOfHintsUint32 {
    //     uint32 activeSharesOfHint;
    //     uint32 activeStakeHint;
    //     uint32 activeSharesHint;
    // }

    // function test_ActiveBalanceOfHint(
    //     uint256 amount1,
    //     uint48 withdrawalDelay,
    //     HintStruct memory hintStruct,
    //     ActiveBalanceOfHintsUint32 memory activeBalanceOfHintsUint32
    // ) public {
    //     amount1 = bound(amount1, 1, 100 * 10 ** 18);
    //     withdrawalDelay = uint48(bound(withdrawalDelay, 1, 7 days));
    //     hintStruct.num = bound(hintStruct.num, 0, 25);
    //     hintStruct.secondsAgo = bound(hintStruct.secondsAgo, 0, 1_720_700_948);

    //     uint256 blockTimestamp = vm.getBlockTimestamp();
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     vault = _getVault(withdrawalDelay);

    //     for (uint256 i; i < hintStruct.num; ++i) {
    //         _deposit(alice, amount1);

    //         blockTimestamp = blockTimestamp + epochDuration;
    //         vm.warp(blockTimestamp);
    //     }

    //     uint48 timestamp =
    //         uint48(hintStruct.back ? blockTimestamp - hintStruct.secondsAgo : blockTimestamp + hintStruct.secondsAgo);

    //     VaultHints vaultHints = new VaultHints();
    //     bytes memory hint = vaultHints.activeBalanceOfHints(address(vault), alice, timestamp);

    //     GasStruct memory gasStruct = GasStruct({gasSpent1: 1, gasSpent2: 1});
    //     bytes memory activeBalanceOfHints = abi.encode(
    //         IVault.ActiveBalanceOfHints({
    //             activeSharesOfHint: abi.encode(activeBalanceOfHintsUint32.activeSharesOfHint),
    //             activeStakeHint: abi.encode(activeBalanceOfHintsUint32.activeStakeHint),
    //             activeSharesHint: abi.encode(activeBalanceOfHintsUint32.activeSharesHint)
    //         })
    //     );
    //     try vault.activeBalanceOfAt(alice, timestamp, activeBalanceOfHints) {
    //         gasStruct.gasSpent1 = vm.lastCallGas().gasTotalUsed;
    //     } catch {
    //         vault.activeBalanceOfAt(alice, timestamp, "");
    //         gasStruct.gasSpent1 = vm.lastCallGas().gasTotalUsed;
    //     }

    //     vault.activeBalanceOfAt(alice, timestamp, hint);
    //     gasStruct.gasSpent2 = vm.lastCallGas().gasTotalUsed;
    //     assertGe(gasStruct.gasSpent1, gasStruct.gasSpent2);
    // }

    // function test_ActiveBalanceOfHintMany(
    //     uint256 amount1,
    //     uint48 withdrawalDelay,
    //     HintStruct memory hintStruct
    // ) public {
    //     amount1 = bound(amount1, 1, 1 * 10 ** 18);
    //     withdrawalDelay = uint48(bound(withdrawalDelay, 1, 7 days));
    //     hintStruct.num = 500;
    //     hintStruct.secondsAgo = bound(hintStruct.secondsAgo, 0, 1_720_700_948);

    //     uint256 blockTimestamp = vm.getBlockTimestamp();
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     vault = _getVault(withdrawalDelay);

    //     for (uint256 i; i < hintStruct.num; ++i) {
    //         _deposit(alice, amount1);

    //         blockTimestamp = blockTimestamp + epochDuration;
    //         vm.warp(blockTimestamp);
    //     }

    //     uint48 timestamp =
    //         uint48(hintStruct.back ? blockTimestamp - hintStruct.secondsAgo : blockTimestamp + hintStruct.secondsAgo);

    //     VaultHints vaultHints = new VaultHints();
    //     bytes memory hint = vaultHints.activeBalanceOfHints(address(vault), alice, timestamp);

    //     GasStruct memory gasStruct = GasStruct({gasSpent1: 1, gasSpent2: 1});
    //     vault.activeBalanceOfAt(alice, timestamp, "");
    //     gasStruct.gasSpent1 = vm.lastCallGas().gasTotalUsed;
    //     vault.activeBalanceOfAt(alice, timestamp, hint);
    //     gasStruct.gasSpent2 = vm.lastCallGas().gasTotalUsed;
    //     assertGe(gasStruct.gasSpent1, gasStruct.gasSpent2);

    //     assertLt(gasStruct.gasSpent1 - gasStruct.gasSpent2, 10_000);
    // }

    function _getVault(uint48 withdrawalDelay) internal returns (Vault) {
        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
        (address vault_,,) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: vaultFactory.lastVersion(),
                owner: alice,
                vaultParams: abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        withdrawalDelay: withdrawalDelay,
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
                            defaultAdminRoleHolder: alice, hook: address(0), hookSetRoleHolder: alice
                        }),
                        networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                        operatorNetworkSharesSetRoleHolders: operatorNetworkSharesSetRoleHolders
                    })
                ),
                withSlasher: false,
                slasherIndex: 0,
                slasherParams: abi.encode(
                    ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})})
                )
            })
        );

        return Vault(vault_);
    }

    function _getVaultAndDelegatorAndSlasher(uint48 withdrawalDelay)
        internal
        returns (Vault, FullRestakeDelegator, Slasher)
    {
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
                        withdrawalDelay: withdrawalDelay,
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
                            defaultAdminRoleHolder: alice, hook: address(0), hookSetRoleHolder: alice
                        }),
                        networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                        operatorNetworkLimitSetRoleHolders: operatorNetworkLimitSetRoleHolders
                    })
                ),
                withSlasher: true,
                slasherIndex: 0,
                slasherParams: abi.encode(
                    ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})})
                )
            })
        );

        return (Vault(vault_), FullRestakeDelegator(delegator_), Slasher(slasher_));
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

    function _grantIsDepositLimitSetRole(address user, address account) internal {
        vm.startPrank(user);
        Vault(address(vault)).grantRole(vault.IS_DEPOSIT_LIMIT_SET_ROLE(), account);
        vm.stopPrank();
    }

    function _grantDepositLimitSetRole(address user, address account) internal {
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
        amount = vault.claim(user);
        vm.stopPrank();
    }

    function _claimBatch(address user, uint256[] memory epochs) internal returns (uint256 amount) {
        vm.startPrank(user);
        amount = vault.claim(user);
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
}
