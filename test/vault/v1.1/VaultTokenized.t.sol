// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {VaultFactory} from "../../../src/contracts/VaultFactory.sol";
import {DelegatorFactory} from "../../../src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "../../../src/contracts/SlasherFactory.sol";
import {NetworkRegistry} from "../../../src/contracts/NetworkRegistry.sol";
import {OperatorRegistry} from "../../../src/contracts/OperatorRegistry.sol";
import {MetadataService} from "../../../src/contracts/service/MetadataService.sol";
import {NetworkMiddlewareService} from "../../../src/contracts/service/NetworkMiddlewareService.sol";
import {OptInService} from "../../../src/contracts/service/OptInService.sol";

import {Vault as VaultV1} from "../../../src/contracts/vault/Vault.sol";
import {VaultTokenized as VaultTokenizedV1} from "../../../src/contracts/vault/VaultTokenized.sol";
import {VaultTokenizedImplementation} from "../../../src/contracts/vault/v1.1/VaultTokenizedImplementation.sol";
import {VaultTokenized} from "../../../src/contracts/vault/v1.1/VaultTokenized.sol";
import {Vault} from "../../../src/contracts/vault/v1.1/Vault.sol";
import {VaultImplementation} from "../../../src/contracts/vault/v1.1/VaultImplementation.sol";
import {NetworkRestakeDelegator} from "../../../src/contracts/delegator/NetworkRestakeDelegator.sol";
import {FullRestakeDelegator} from "../../../src/contracts/delegator/FullRestakeDelegator.sol";
import {OperatorSpecificDelegator} from "../../../src/contracts/delegator/OperatorSpecificDelegator.sol";
import {OperatorNetworkSpecificDelegator} from "../../../src/contracts/delegator/OperatorNetworkSpecificDelegator.sol";
import {Slasher} from "../../../src/contracts/slasher/Slasher.sol";
import {VetoSlasher} from "../../../src/contracts/slasher/VetoSlasher.sol";

import {IVault} from "../../../src/interfaces/vault/v1.1/IVault.sol";
import {IVaultTokenized} from "../../../src/interfaces/vault/v1.1/IVaultTokenized.sol";
import {IVault as IVaultV1} from "../../../src/interfaces/vault/IVault.sol";
import {IVaultTokenized as IVaultTokenizedV1} from "../../../src/interfaces/vault/IVaultTokenized.sol";
import {Token} from "../../mocks/Token.sol";
import {FeeOnTransferToken} from "../../mocks/FeeOnTransferToken.sol";
import {VaultConfigurator} from "../../../src/contracts/VaultConfigurator.sol";
import {IVaultConfigurator} from "../../../src/interfaces/IVaultConfigurator.sol";
import {INetworkRestakeDelegator} from "../../../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IFullRestakeDelegator} from "../../../src/interfaces/delegator/IFullRestakeDelegator.sol";
import {IBaseDelegator} from "../../../src/interfaces/delegator/IBaseDelegator.sol";
import {ISlasher} from "../../../src/interfaces/slasher/ISlasher.sol";
import {IBaseSlasher} from "../../../src/interfaces/slasher/IBaseSlasher.sol";

import {IVaultStorage} from "../../../src/interfaces/vault/v1.1/IVaultStorage.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {VaultHints} from "../../../src/contracts/hints/VaultHints.sol";
import {Subnetwork} from "../../../src/contracts/libraries/Subnetwork.sol";

contract VaultTokenizedTest is Test {
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

    VaultTokenizedImplementation vault;
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

        address vaultV1Impl =
            address(new VaultV1(address(delegatorFactory), address(slasherFactory), address(vaultFactory)));
        vaultFactory.whitelist(vaultV1Impl);

        address vaultTokenizedV1Impl =
            address(new VaultTokenizedV1(address(delegatorFactory), address(slasherFactory), address(vaultFactory)));
        vaultFactory.whitelist(vaultTokenizedV1Impl);

        address vaultImplementation =
            address(new VaultImplementation(address(vaultFactory), address(delegatorFactory), address(slasherFactory)));
        address vaultImpl = address(new Vault(address(vaultFactory), vaultImplementation));
        vaultFactory.whitelist(vaultImpl);

        address vaultTokenizedImplementation =
            address(new VaultTokenizedImplementation(address(vaultFactory), vaultImplementation));
        address vaultTokenizedImpl = address(new VaultTokenized(address(vaultFactory), vaultTokenizedImplementation));
        vaultFactory.whitelist(vaultTokenizedImpl);

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
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
        (address vault_, address delegator_,) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: 3,
                owner: address(0),
                vaultParams: abi.encode(
                    IVaultTokenized.InitParamsTokenized({
                        baseParams: abi.encode(
                            IVault.InitParams({
                                collateral: address(collateral),
                                burner: burner,
                                epochDuration: epochDuration,
                                depositWhitelist: depositWhitelist,
                                isDepositLimit: isDepositLimit,
                                depositLimit: depositLimit,
                                epochDurationSetEpochsDelay: 3,
                                flashLoanEnabled: false,
                                flashFeeRate: 1,
                                flashFeeReceiver: alice,
                                defaultAdminRoleHolder: alice,
                                depositWhitelistSetRoleHolder: alice,
                                depositorWhitelistRoleHolder: alice,
                                depositorsWhitelisted: new address[](0),
                                isDepositLimitSetRoleHolder: alice,
                                depositLimitSetRoleHolder: alice,
                                epochDurationSetRoleHolder: alice,
                                flashLoanEnabledSetRoleHolder: alice,
                                flashFeeRateSetRoleHolder: alice,
                                flashFeeReceiverSetRoleHolder: alice
                            })
                        ),
                        name: "Test",
                        symbol: "TEST"
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

        vault = VaultTokenizedImplementation(payable(vault_));

        assertEq(vault.DEPOSIT_WHITELIST_SET_ROLE(), keccak256("DEPOSIT_WHITELIST_SET_ROLE"));
        assertEq(vault.DEPOSITOR_WHITELIST_ROLE(), keccak256("DEPOSITOR_WHITELIST_ROLE"));
        assertEq(VaultImplementation(payable(address(vault))).DELEGATOR_FACTORY(), address(delegatorFactory));
        assertEq(VaultImplementation(payable(address(vault))).SLASHER_FACTORY(), address(slasherFactory));

        assertEq(VaultTokenized(payable(address(vault))).owner(), address(0));
        assertEq(vault.collateral(), address(collateral));
        assertEq(vault.delegator(), delegator_);
        assertEq(vault.slasher(), address(0));
        assertEq(vault.burner(), burner);
        assertEq(VaultImplementation(payable(address(vault))).epochDuration(), epochDuration);
        assertEq(vault.depositWhitelist(), depositWhitelist);
        assertEq(
            VaultImplementation(payable(address(vault))).hasRole(
                VaultImplementation(payable(address(vault))).DEFAULT_ADMIN_ROLE(), alice
            ),
            true
        );
        assertEq(
            VaultImplementation(payable(address(vault))).hasRole(
                VaultImplementation(payable(address(vault))).DEPOSITOR_WHITELIST_ROLE(), alice
            ),
            true
        );
        assertEq(VaultImplementation(payable(address(vault))).epochDurationInit(), blockTimestamp);
        assertEq(VaultImplementation(payable(address(vault))).epochDuration(), epochDuration);
        vm.expectRevert(IVault.InvalidTimestamp.selector);
        assertEq(VaultImplementation(payable(address(vault))).epochAt(0), 0);
        assertEq(VaultImplementation(payable(address(vault))).epochAt(uint48(blockTimestamp)), 0);
        assertEq(VaultImplementation(payable(address(vault))).currentEpoch(), 0);
        assertEq(VaultImplementation(payable(address(vault))).currentEpochStart(), blockTimestamp);
        vm.expectRevert(IVault.NoPreviousEpoch.selector);
        VaultImplementation(payable(address(vault))).previousEpochStart();
        assertEq(VaultImplementation(payable(address(vault))).nextEpochStart(), blockTimestamp + epochDuration);
        assertEq(VaultImplementation(payable(address(vault))).totalStake(), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp), ""), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeShares(), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp), ""), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeStake(), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeSharesOfAt(alice, uint48(blockTimestamp), ""), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeSharesOf(alice), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeBalanceOfAt(alice, uint48(blockTimestamp), ""), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeBalanceOf(alice), 0);
        assertEq(VaultImplementation(payable(address(vault))).withdrawals(0), 0);
        assertEq(VaultImplementation(payable(address(vault))).withdrawalShares(0), 0);
        assertEq(VaultImplementation(payable(address(vault))).isWithdrawalsClaimed(0, alice), false);
        assertEq(VaultImplementation(payable(address(vault))).depositWhitelist(), depositWhitelist);
        assertEq(VaultImplementation(payable(address(vault))).isDepositorWhitelisted(alice), false);
        assertEq(VaultImplementation(payable(address(vault))).slashableBalanceOf(alice), 0);
        assertEq(VaultImplementation(payable(address(vault))).isDelegatorInitialized(), true);
        assertEq(VaultImplementation(payable(address(vault))).isSlasherInitialized(), true);
        assertEq(VaultImplementation(payable(address(vault))).isInitialized(), true);

        blockTimestamp = blockTimestamp + VaultImplementation(payable(address(vault))).epochDuration() - 1;
        vm.warp(blockTimestamp);

        assertEq(VaultImplementation(payable(address(vault))).epochAt(uint48(blockTimestamp)), 0);
        assertEq(VaultImplementation(payable(address(vault))).epochAt(uint48(blockTimestamp + 1)), 1);
        assertEq(VaultImplementation(payable(address(vault))).currentEpoch(), 0);
        assertEq(
            VaultImplementation(payable(address(vault))).currentEpochStart(),
            blockTimestamp - (VaultImplementation(payable(address(vault))).epochDuration() - 1)
        );
        vm.expectRevert(IVault.NoPreviousEpoch.selector);
        VaultImplementation(payable(address(vault))).previousEpochStart();
        assertEq(VaultImplementation(payable(address(vault))).nextEpochStart(), blockTimestamp + 1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(VaultImplementation(payable(address(vault))).epochAt(uint48(blockTimestamp)), 1);
        assertEq(
            VaultImplementation(payable(address(vault))).epochAt(
                uint48(blockTimestamp + 2 * VaultImplementation(payable(address(vault))).epochDuration())
            ),
            3
        );
        assertEq(VaultImplementation(payable(address(vault))).currentEpoch(), 1);
        assertEq(VaultImplementation(payable(address(vault))).currentEpochStart(), blockTimestamp);
        assertEq(
            VaultImplementation(payable(address(vault))).previousEpochStart(),
            blockTimestamp - VaultImplementation(payable(address(vault))).epochDuration()
        );
        assertEq(
            VaultImplementation(payable(address(vault))).nextEpochStart(),
            blockTimestamp + VaultImplementation(payable(address(vault))).epochDuration()
        );

        blockTimestamp = blockTimestamp + VaultImplementation(payable(address(vault))).epochDuration() - 1;
        vm.warp(blockTimestamp);

        assertEq(VaultImplementation(payable(address(vault))).epochAt(uint48(blockTimestamp)), 1);
        assertEq(VaultImplementation(payable(address(vault))).epochAt(uint48(blockTimestamp + 1)), 2);
        assertEq(VaultImplementation(payable(address(vault))).currentEpoch(), 1);
        assertEq(
            VaultImplementation(payable(address(vault))).currentEpochStart(),
            blockTimestamp - (VaultImplementation(payable(address(vault))).epochDuration() - 1)
        );
        assertEq(
            VaultImplementation(payable(address(vault))).previousEpochStart(),
            blockTimestamp - (VaultImplementation(payable(address(vault))).epochDuration() - 1)
                - VaultImplementation(payable(address(vault))).epochDuration()
        );
        assertEq(VaultImplementation(payable(address(vault))).nextEpochStart(), blockTimestamp + 1);

        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.allowance(alice, alice), 0);
        assertEq(vault.decimals(), collateral.decimals());
        assertEq(vault.symbol(), "TEST");
        assertEq(vault.name(), "Test");
    }

    function test_CreateRevertInvalidEpochDuration() public {
        uint48 epochDuration = 0;

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
                    IVaultTokenized.InitParamsTokenized({
                        baseParams: abi.encode(
                            IVault.InitParams({
                                collateral: address(collateral),
                                burner: address(0xdEaD),
                                epochDuration: epochDuration,
                                depositWhitelist: true,
                                isDepositLimit: false,
                                depositLimit: 0,
                                epochDurationSetEpochsDelay: 3,
                                flashLoanEnabled: false,
                                flashFeeRate: 1,
                                flashFeeReceiver: alice,
                                defaultAdminRoleHolder: alice,
                                depositWhitelistSetRoleHolder: alice,
                                depositorWhitelistRoleHolder: alice,
                                depositorsWhitelisted: new address[](0),
                                isDepositLimitSetRoleHolder: alice,
                                depositLimitSetRoleHolder: alice,
                                epochDurationSetRoleHolder: alice,
                                flashLoanEnabledSetRoleHolder: alice,
                                flashFeeRateSetRoleHolder: alice,
                                flashFeeReceiverSetRoleHolder: alice
                            })
                        ),
                        name: "Test",
                        symbol: "TEST"
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
    }

    function test_CreateRevertInvalidCollateral(
        uint48 epochDuration
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

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
                    IVaultTokenized.InitParamsTokenized({
                        baseParams: abi.encode(
                            IVault.InitParams({
                                collateral: address(0),
                                burner: address(0xdEaD),
                                epochDuration: epochDuration,
                                depositWhitelist: true,
                                isDepositLimit: false,
                                depositLimit: 0,
                                epochDurationSetEpochsDelay: 3,
                                flashLoanEnabled: false,
                                flashFeeRate: 1,
                                flashFeeReceiver: alice,
                                defaultAdminRoleHolder: alice,
                                depositWhitelistSetRoleHolder: alice,
                                depositorWhitelistRoleHolder: alice,
                                depositorsWhitelisted: new address[](0),
                                isDepositLimitSetRoleHolder: alice,
                                depositLimitSetRoleHolder: alice,
                                epochDurationSetRoleHolder: alice,
                                flashLoanEnabledSetRoleHolder: alice,
                                flashFeeRateSetRoleHolder: alice,
                                flashFeeReceiverSetRoleHolder: alice
                            })
                        ),
                        name: "Test",
                        symbol: "TEST"
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
    }

    function test_CreateRevertMissingRoles1(
        uint48 epochDuration
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        uint64 lastVersion = vaultFactory.lastVersion();

        vm.expectRevert(IVault.MissingRoles.selector);
        vault = VaultTokenizedImplementation(
            payable(
                vaultFactory.create(
                    lastVersion,
                    alice,
                    abi.encode(
                        IVaultTokenized.InitParamsTokenized({
                            baseParams: abi.encode(
                                IVault.InitParams({
                                    collateral: address(collateral),
                                    burner: address(0xdEaD),
                                    epochDuration: epochDuration,
                                    depositWhitelist: true,
                                    isDepositLimit: false,
                                    depositLimit: 0,
                                    epochDurationSetEpochsDelay: 3,
                                    flashLoanEnabled: false,
                                    flashFeeRate: 1,
                                    flashFeeReceiver: alice,
                                    defaultAdminRoleHolder: address(0),
                                    depositWhitelistSetRoleHolder: address(0),
                                    depositorWhitelistRoleHolder: address(0),
                                    depositorsWhitelisted: new address[](0),
                                    isDepositLimitSetRoleHolder: alice,
                                    depositLimitSetRoleHolder: address(0),
                                    epochDurationSetRoleHolder: alice,
                                    flashLoanEnabledSetRoleHolder: alice,
                                    flashFeeRateSetRoleHolder: alice,
                                    flashFeeReceiverSetRoleHolder: alice
                                })
                            ),
                            name: "Test",
                            symbol: "TEST"
                        })
                    )
                )
            )
        );
    }

    function test_CreateRevertMissingRoles2(
        uint48 epochDuration
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        uint64 lastVersion = vaultFactory.lastVersion();

        vm.expectRevert(IVault.MissingRoles.selector);
        vault = VaultTokenizedImplementation(
            payable(
                vaultFactory.create(
                    lastVersion,
                    alice,
                    abi.encode(
                        IVaultTokenized.InitParamsTokenized({
                            baseParams: abi.encode(
                                IVault.InitParams({
                                    collateral: address(collateral),
                                    burner: address(0xdEaD),
                                    epochDuration: epochDuration,
                                    depositWhitelist: false,
                                    isDepositLimit: true,
                                    depositLimit: 0,
                                    epochDurationSetEpochsDelay: 3,
                                    flashLoanEnabled: false,
                                    flashFeeRate: 0,
                                    flashFeeReceiver: address(0),
                                    defaultAdminRoleHolder: address(0),
                                    depositWhitelistSetRoleHolder: alice,
                                    depositorWhitelistRoleHolder: address(0),
                                    depositorsWhitelisted: new address[](0),
                                    isDepositLimitSetRoleHolder: address(0),
                                    depositLimitSetRoleHolder: address(0),
                                    epochDurationSetRoleHolder: address(0),
                                    flashLoanEnabledSetRoleHolder: address(0),
                                    flashFeeRateSetRoleHolder: address(0),
                                    flashFeeReceiverSetRoleHolder: address(0)
                                })
                            ),
                            name: "Test",
                            symbol: "TEST"
                        })
                    )
                )
            )
        );
    }

    function test_CreateRevertMissingRoles3(
        uint48 epochDuration
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        uint64 lastVersion = vaultFactory.lastVersion();

        vm.expectRevert(IVault.MissingRoles.selector);
        vault = VaultTokenizedImplementation(
            payable(
                vaultFactory.create(
                    lastVersion,
                    alice,
                    abi.encode(
                        IVaultTokenized.InitParamsTokenized({
                            baseParams: abi.encode(
                                IVault.InitParams({
                                    collateral: address(collateral),
                                    burner: address(0xdEaD),
                                    epochDuration: epochDuration,
                                    depositWhitelist: false,
                                    isDepositLimit: false,
                                    depositLimit: 0,
                                    epochDurationSetEpochsDelay: 3,
                                    flashLoanEnabled: false,
                                    flashFeeRate: 1,
                                    flashFeeReceiver: alice,
                                    defaultAdminRoleHolder: address(0),
                                    depositWhitelistSetRoleHolder: alice,
                                    depositorWhitelistRoleHolder: address(0),
                                    depositorsWhitelisted: new address[](0),
                                    isDepositLimitSetRoleHolder: address(0),
                                    depositLimitSetRoleHolder: alice,
                                    epochDurationSetRoleHolder: alice,
                                    flashLoanEnabledSetRoleHolder: alice,
                                    flashFeeRateSetRoleHolder: alice,
                                    flashFeeReceiverSetRoleHolder: alice
                                })
                            ),
                            name: "Test",
                            symbol: "TEST"
                        })
                    )
                )
            )
        );
    }

    function test_CreateRevertMissingRoles4(
        uint48 epochDuration
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        uint64 lastVersion = vaultFactory.lastVersion();

        vm.expectRevert(IVault.MissingRoles.selector);
        vault = VaultTokenizedImplementation(
            payable(
                vaultFactory.create(
                    lastVersion,
                    alice,
                    abi.encode(
                        IVaultTokenized.InitParamsTokenized({
                            baseParams: abi.encode(
                                IVault.InitParams({
                                    collateral: address(collateral),
                                    burner: address(0xdEaD),
                                    epochDuration: epochDuration,
                                    depositWhitelist: false,
                                    isDepositLimit: false,
                                    depositLimit: 1,
                                    epochDurationSetEpochsDelay: 3,
                                    flashLoanEnabled: false,
                                    flashFeeRate: 0,
                                    flashFeeReceiver: address(0),
                                    defaultAdminRoleHolder: address(0),
                                    depositWhitelistSetRoleHolder: alice,
                                    depositorWhitelistRoleHolder: address(0),
                                    depositorsWhitelisted: new address[](0),
                                    isDepositLimitSetRoleHolder: address(0),
                                    depositLimitSetRoleHolder: address(0),
                                    epochDurationSetRoleHolder: address(0),
                                    flashLoanEnabledSetRoleHolder: address(0),
                                    flashFeeRateSetRoleHolder: address(0),
                                    flashFeeReceiverSetRoleHolder: address(0)
                                })
                            ),
                            name: "Test",
                            symbol: "TEST"
                        })
                    )
                )
            )
        );
    }

    function test_CreateRevertMissingRoles5(
        uint48 epochDuration
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));

        uint64 lastVersion = vaultFactory.lastVersion();

        vm.expectRevert(IVault.MissingRoles.selector);
        vault = VaultTokenizedImplementation(
            payable(
                vaultFactory.create(
                    lastVersion,
                    alice,
                    abi.encode(
                        IVaultTokenized.InitParamsTokenized({
                            baseParams: abi.encode(
                                IVault.InitParams({
                                    collateral: address(collateral),
                                    burner: address(0xdEaD),
                                    epochDuration: epochDuration,
                                    depositWhitelist: false,
                                    isDepositLimit: false,
                                    depositLimit: 0,
                                    epochDurationSetEpochsDelay: 3,
                                    flashLoanEnabled: false,
                                    flashFeeRate: 1,
                                    flashFeeReceiver: alice,
                                    defaultAdminRoleHolder: address(0),
                                    depositWhitelistSetRoleHolder: address(0),
                                    depositorWhitelistRoleHolder: alice,
                                    depositorsWhitelisted: new address[](0),
                                    isDepositLimitSetRoleHolder: alice,
                                    depositLimitSetRoleHolder: address(0),
                                    epochDurationSetRoleHolder: alice,
                                    flashLoanEnabledSetRoleHolder: alice,
                                    flashFeeRateSetRoleHolder: alice,
                                    flashFeeReceiverSetRoleHolder: alice
                                })
                            ),
                            name: "Test",
                            symbol: "TEST"
                        })
                    )
                )
            )
        );
    }

    function test_SetDelegator() public {
        uint64 lastVersion = vaultFactory.lastVersion();

        vault = VaultTokenizedImplementation(
            payable(
                vaultFactory.create(
                    lastVersion,
                    alice,
                    abi.encode(
                        IVaultTokenized.InitParamsTokenized({
                            baseParams: abi.encode(
                                IVault.InitParams({
                                    collateral: address(collateral),
                                    burner: address(0xdEaD),
                                    epochDuration: 7 days,
                                    depositWhitelist: false,
                                    isDepositLimit: false,
                                    depositLimit: 0,
                                    epochDurationSetEpochsDelay: 3,
                                    flashLoanEnabled: false,
                                    flashFeeRate: 1,
                                    flashFeeReceiver: alice,
                                    defaultAdminRoleHolder: alice,
                                    depositWhitelistSetRoleHolder: alice,
                                    depositorWhitelistRoleHolder: alice,
                                    depositorsWhitelisted: new address[](0),
                                    isDepositLimitSetRoleHolder: alice,
                                    depositLimitSetRoleHolder: alice,
                                    epochDurationSetRoleHolder: alice,
                                    flashLoanEnabledSetRoleHolder: alice,
                                    flashFeeRateSetRoleHolder: alice,
                                    flashFeeReceiverSetRoleHolder: alice
                                })
                            ),
                            name: "Test",
                            symbol: "TEST"
                        })
                    )
                )
            )
        );

        assertEq(VaultImplementation(payable(address(vault))).isDelegatorInitialized(), false);

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
                                defaultAdminRoleHolder: alice,
                                hook: address(0),
                                hookSetRoleHolder: alice
                            }),
                            networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                            operatorNetworkLimitSetRoleHolders: operatorNetworkLimitSetRoleHolders
                        })
                    )
                )
            )
        );

        VaultImplementation(payable(address(vault))).setDelegator(address(delegator));

        assertEq(vault.delegator(), address(delegator));
        assertEq(VaultImplementation(payable(address(vault))).isDelegatorInitialized(), true);
        assertEq(VaultImplementation(payable(address(vault))).isInitialized(), false);
    }

    function test_SetDelegatorRevertDelegatorAlreadyInitialized() public {
        uint64 lastVersion = vaultFactory.lastVersion();

        vault = VaultTokenizedImplementation(
            payable(
                vaultFactory.create(
                    lastVersion,
                    alice,
                    abi.encode(
                        IVaultTokenized.InitParamsTokenized({
                            baseParams: abi.encode(
                                IVault.InitParams({
                                    collateral: address(collateral),
                                    burner: address(0xdEaD),
                                    epochDuration: 7 days,
                                    depositWhitelist: false,
                                    isDepositLimit: false,
                                    depositLimit: 0,
                                    epochDurationSetEpochsDelay: 3,
                                    flashLoanEnabled: false,
                                    flashFeeRate: 1,
                                    flashFeeReceiver: alice,
                                    defaultAdminRoleHolder: alice,
                                    depositWhitelistSetRoleHolder: alice,
                                    depositorWhitelistRoleHolder: alice,
                                    depositorsWhitelisted: new address[](0),
                                    isDepositLimitSetRoleHolder: alice,
                                    depositLimitSetRoleHolder: alice,
                                    epochDurationSetRoleHolder: alice,
                                    flashLoanEnabledSetRoleHolder: alice,
                                    flashFeeRateSetRoleHolder: alice,
                                    flashFeeReceiverSetRoleHolder: alice
                                })
                            ),
                            name: "Test",
                            symbol: "TEST"
                        })
                    )
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
                                defaultAdminRoleHolder: alice,
                                hook: address(0),
                                hookSetRoleHolder: alice
                            }),
                            networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                            operatorNetworkLimitSetRoleHolders: operatorNetworkLimitSetRoleHolders
                        })
                    )
                )
            )
        );

        VaultImplementation(payable(address(vault))).setDelegator(address(delegator));

        vm.expectRevert(IVault.DelegatorAlreadyInitialized.selector);
        VaultImplementation(payable(address(vault))).setDelegator(address(delegator));
    }

    function test_SetDelegatorRevertNotDelegator() public {
        uint64 lastVersion = vaultFactory.lastVersion();

        vault = VaultTokenizedImplementation(
            payable(
                vaultFactory.create(
                    lastVersion,
                    alice,
                    abi.encode(
                        IVaultTokenized.InitParamsTokenized({
                            baseParams: abi.encode(
                                IVault.InitParams({
                                    collateral: address(collateral),
                                    burner: address(0xdEaD),
                                    epochDuration: 7 days,
                                    depositWhitelist: false,
                                    isDepositLimit: false,
                                    depositLimit: 0,
                                    epochDurationSetEpochsDelay: 3,
                                    flashLoanEnabled: false,
                                    flashFeeRate: 1,
                                    flashFeeReceiver: alice,
                                    defaultAdminRoleHolder: alice,
                                    depositWhitelistSetRoleHolder: alice,
                                    depositorWhitelistRoleHolder: alice,
                                    depositorsWhitelisted: new address[](0),
                                    isDepositLimitSetRoleHolder: alice,
                                    depositLimitSetRoleHolder: alice,
                                    epochDurationSetRoleHolder: alice,
                                    flashLoanEnabledSetRoleHolder: alice,
                                    flashFeeRateSetRoleHolder: alice,
                                    flashFeeReceiverSetRoleHolder: alice
                                })
                            ),
                            name: "Test",
                            symbol: "TEST"
                        })
                    )
                )
            )
        );

        vm.expectRevert(IVault.NotDelegator.selector);
        VaultImplementation(payable(address(vault))).setDelegator(address(1));
    }

    function test_SetDelegatorRevertInvalidDelegator() public {
        uint64 lastVersion = vaultFactory.lastVersion();

        vault = VaultTokenizedImplementation(
            payable(
                vaultFactory.create(
                    lastVersion,
                    alice,
                    abi.encode(
                        IVaultTokenized.InitParamsTokenized({
                            baseParams: abi.encode(
                                IVault.InitParams({
                                    collateral: address(collateral),
                                    burner: address(0xdEaD),
                                    epochDuration: 7 days,
                                    depositWhitelist: false,
                                    isDepositLimit: false,
                                    depositLimit: 0,
                                    epochDurationSetEpochsDelay: 3,
                                    flashLoanEnabled: false,
                                    flashFeeRate: 1,
                                    flashFeeReceiver: alice,
                                    defaultAdminRoleHolder: alice,
                                    depositWhitelistSetRoleHolder: alice,
                                    depositorWhitelistRoleHolder: alice,
                                    depositorsWhitelisted: new address[](0),
                                    isDepositLimitSetRoleHolder: alice,
                                    depositLimitSetRoleHolder: alice,
                                    epochDurationSetRoleHolder: alice,
                                    flashLoanEnabledSetRoleHolder: alice,
                                    flashFeeRateSetRoleHolder: alice,
                                    flashFeeReceiverSetRoleHolder: alice
                                })
                            ),
                            name: "Test",
                            symbol: "TEST"
                        })
                    )
                )
            )
        );

        VaultTokenizedImplementation vault2 = VaultTokenizedImplementation(
            payable(
                vaultFactory.create(
                    lastVersion,
                    alice,
                    abi.encode(
                        IVaultTokenized.InitParamsTokenized({
                            baseParams: abi.encode(
                                IVault.InitParams({
                                    collateral: address(collateral),
                                    burner: address(0xdEaD),
                                    epochDuration: 7 days,
                                    depositWhitelist: false,
                                    isDepositLimit: false,
                                    depositLimit: 0,
                                    epochDurationSetEpochsDelay: 3,
                                    flashLoanEnabled: false,
                                    flashFeeRate: 1,
                                    flashFeeReceiver: alice,
                                    defaultAdminRoleHolder: alice,
                                    depositWhitelistSetRoleHolder: alice,
                                    depositorWhitelistRoleHolder: alice,
                                    depositorsWhitelisted: new address[](0),
                                    isDepositLimitSetRoleHolder: alice,
                                    depositLimitSetRoleHolder: alice,
                                    epochDurationSetRoleHolder: alice,
                                    flashLoanEnabledSetRoleHolder: alice,
                                    flashFeeRateSetRoleHolder: alice,
                                    flashFeeReceiverSetRoleHolder: alice
                                })
                            ),
                            name: "Test",
                            symbol: "TEST"
                        })
                    )
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
                                defaultAdminRoleHolder: alice,
                                hook: address(0),
                                hookSetRoleHolder: alice
                            }),
                            networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                            operatorNetworkLimitSetRoleHolders: operatorNetworkLimitSetRoleHolders
                        })
                    )
                )
            )
        );

        vm.expectRevert(IVault.InvalidDelegator.selector);
        VaultImplementation(payable(address(vault))).setDelegator(address(delegator));
    }

    function test_SetSlasher() public {
        uint64 lastVersion = vaultFactory.lastVersion();

        vault = VaultTokenizedImplementation(
            payable(
                vaultFactory.create(
                    lastVersion,
                    alice,
                    abi.encode(
                        IVaultTokenized.InitParamsTokenized({
                            baseParams: abi.encode(
                                IVault.InitParams({
                                    collateral: address(collateral),
                                    burner: address(0xdEaD),
                                    epochDuration: 7 days,
                                    depositWhitelist: false,
                                    isDepositLimit: false,
                                    depositLimit: 0,
                                    epochDurationSetEpochsDelay: 3,
                                    flashLoanEnabled: false,
                                    flashFeeRate: 1,
                                    flashFeeReceiver: alice,
                                    defaultAdminRoleHolder: alice,
                                    depositWhitelistSetRoleHolder: alice,
                                    depositorWhitelistRoleHolder: alice,
                                    depositorsWhitelisted: new address[](0),
                                    isDepositLimitSetRoleHolder: alice,
                                    depositLimitSetRoleHolder: alice,
                                    epochDurationSetRoleHolder: alice,
                                    flashLoanEnabledSetRoleHolder: alice,
                                    flashFeeRateSetRoleHolder: alice,
                                    flashFeeReceiverSetRoleHolder: alice
                                })
                            ),
                            name: "Test",
                            symbol: "TEST"
                        })
                    )
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

        VaultImplementation(payable(address(vault))).setSlasher(address(slasher));

        assertEq(vault.slasher(), address(slasher));
        assertEq(vault.isSlasherInitialized(), true);
        assertEq(VaultImplementation(payable(address(vault))).isInitialized(), false);
    }

    function test_SetSlasherRevertSlasherAlreadyInitialized() public {
        uint64 lastVersion = vaultFactory.lastVersion();

        vault = VaultTokenizedImplementation(
            payable(
                vaultFactory.create(
                    lastVersion,
                    alice,
                    abi.encode(
                        IVaultTokenized.InitParamsTokenized({
                            baseParams: abi.encode(
                                IVault.InitParams({
                                    collateral: address(collateral),
                                    burner: address(0xdEaD),
                                    epochDuration: 7 days,
                                    depositWhitelist: false,
                                    isDepositLimit: false,
                                    depositLimit: 0,
                                    epochDurationSetEpochsDelay: 3,
                                    flashLoanEnabled: false,
                                    flashFeeRate: 1,
                                    flashFeeReceiver: alice,
                                    defaultAdminRoleHolder: alice,
                                    depositWhitelistSetRoleHolder: alice,
                                    depositorWhitelistRoleHolder: alice,
                                    depositorsWhitelisted: new address[](0),
                                    isDepositLimitSetRoleHolder: alice,
                                    depositLimitSetRoleHolder: alice,
                                    epochDurationSetRoleHolder: alice,
                                    flashLoanEnabledSetRoleHolder: alice,
                                    flashFeeRateSetRoleHolder: alice,
                                    flashFeeReceiverSetRoleHolder: alice
                                })
                            ),
                            name: "Test",
                            symbol: "TEST"
                        })
                    )
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

        VaultImplementation(payable(address(vault))).setSlasher(address(slasher));

        vm.expectRevert(IVault.SlasherAlreadyInitialized.selector);
        VaultImplementation(payable(address(vault))).setSlasher(address(slasher));
    }

    function test_SetSlasherRevertNotSlasher() public {
        uint64 lastVersion = vaultFactory.lastVersion();

        vault = VaultTokenizedImplementation(
            payable(
                vaultFactory.create(
                    lastVersion,
                    alice,
                    abi.encode(
                        IVaultTokenized.InitParamsTokenized({
                            baseParams: abi.encode(
                                IVault.InitParams({
                                    collateral: address(collateral),
                                    burner: address(0xdEaD),
                                    epochDuration: 7 days,
                                    depositWhitelist: false,
                                    isDepositLimit: false,
                                    depositLimit: 0,
                                    epochDurationSetEpochsDelay: 3,
                                    flashLoanEnabled: false,
                                    flashFeeRate: 1,
                                    flashFeeReceiver: alice,
                                    defaultAdminRoleHolder: alice,
                                    depositWhitelistSetRoleHolder: alice,
                                    depositorWhitelistRoleHolder: alice,
                                    depositorsWhitelisted: new address[](0),
                                    isDepositLimitSetRoleHolder: alice,
                                    depositLimitSetRoleHolder: alice,
                                    epochDurationSetRoleHolder: alice,
                                    flashLoanEnabledSetRoleHolder: alice,
                                    flashFeeRateSetRoleHolder: alice,
                                    flashFeeReceiverSetRoleHolder: alice
                                })
                            ),
                            name: "Test",
                            symbol: "TEST"
                        })
                    )
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
        VaultImplementation(payable(address(vault))).setSlasher(address(1));
    }

    function test_SetSlasherRevertInvalidSlasher() public {
        uint64 lastVersion = vaultFactory.lastVersion();

        vault = VaultTokenizedImplementation(
            payable(
                vaultFactory.create(
                    lastVersion,
                    alice,
                    abi.encode(
                        IVaultTokenized.InitParamsTokenized({
                            baseParams: abi.encode(
                                IVault.InitParams({
                                    collateral: address(collateral),
                                    burner: address(0xdEaD),
                                    epochDuration: 7 days,
                                    depositWhitelist: false,
                                    isDepositLimit: false,
                                    depositLimit: 0,
                                    epochDurationSetEpochsDelay: 3,
                                    flashLoanEnabled: false,
                                    flashFeeRate: 1,
                                    flashFeeReceiver: alice,
                                    defaultAdminRoleHolder: alice,
                                    depositWhitelistSetRoleHolder: alice,
                                    depositorWhitelistRoleHolder: alice,
                                    depositorsWhitelisted: new address[](0),
                                    isDepositLimitSetRoleHolder: alice,
                                    depositLimitSetRoleHolder: alice,
                                    epochDurationSetRoleHolder: alice,
                                    flashLoanEnabledSetRoleHolder: alice,
                                    flashFeeRateSetRoleHolder: alice,
                                    flashFeeReceiverSetRoleHolder: alice
                                })
                            ),
                            name: "Test",
                            symbol: "TEST"
                        })
                    )
                )
            )
        );

        VaultTokenizedImplementation vault2 = VaultTokenizedImplementation(
            payable(
                vaultFactory.create(
                    lastVersion,
                    alice,
                    abi.encode(
                        IVaultTokenized.InitParamsTokenized({
                            baseParams: abi.encode(
                                IVault.InitParams({
                                    collateral: address(collateral),
                                    burner: address(0xdEaD),
                                    epochDuration: 7 days,
                                    depositWhitelist: false,
                                    isDepositLimit: false,
                                    depositLimit: 0,
                                    epochDurationSetEpochsDelay: 3,
                                    flashLoanEnabled: false,
                                    flashFeeRate: 1,
                                    flashFeeReceiver: alice,
                                    defaultAdminRoleHolder: alice,
                                    depositWhitelistSetRoleHolder: alice,
                                    depositorWhitelistRoleHolder: alice,
                                    depositorsWhitelisted: new address[](0),
                                    isDepositLimitSetRoleHolder: alice,
                                    depositLimitSetRoleHolder: alice,
                                    epochDurationSetRoleHolder: alice,
                                    flashLoanEnabledSetRoleHolder: alice,
                                    flashFeeRateSetRoleHolder: alice,
                                    flashFeeReceiverSetRoleHolder: alice
                                })
                            ),
                            name: "Test",
                            symbol: "TEST"
                        })
                    )
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
        VaultImplementation(payable(address(vault))).setSlasher(address(slasher));
    }

    function test_SetSlasherZeroAddress() public {
        uint64 lastVersion = vaultFactory.lastVersion();

        vault = VaultTokenizedImplementation(
            payable(
                vaultFactory.create(
                    lastVersion,
                    alice,
                    abi.encode(
                        IVaultTokenized.InitParamsTokenized({
                            baseParams: abi.encode(
                                IVault.InitParams({
                                    collateral: address(collateral),
                                    burner: address(0xdEaD),
                                    epochDuration: 7 days,
                                    depositWhitelist: false,
                                    isDepositLimit: false,
                                    depositLimit: 0,
                                    epochDurationSetEpochsDelay: 3,
                                    flashLoanEnabled: false,
                                    flashFeeRate: 1,
                                    flashFeeReceiver: alice,
                                    defaultAdminRoleHolder: alice,
                                    depositWhitelistSetRoleHolder: alice,
                                    depositorWhitelistRoleHolder: alice,
                                    depositorsWhitelisted: new address[](0),
                                    isDepositLimitSetRoleHolder: alice,
                                    depositLimitSetRoleHolder: alice,
                                    epochDurationSetRoleHolder: alice,
                                    flashLoanEnabledSetRoleHolder: alice,
                                    flashFeeRateSetRoleHolder: alice,
                                    flashFeeReceiverSetRoleHolder: alice
                                })
                            ),
                            name: "Test",
                            symbol: "TEST"
                        })
                    )
                )
            )
        );

        VaultImplementation(payable(address(vault))).setSlasher(address(0));
    }

    function test_DepositTwice(uint256 amount1, uint256 amount2) public {
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

            assertEq(vault.balanceOf(alice), shares1);
            assertEq(vault.totalSupply(), shares1);
        }
        assertEq(collateral.balanceOf(address(vault)) - tokensBefore, amount1);

        assertEq(VaultImplementation(payable(address(vault))).totalStake(), amount1);
        assertEq(VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp - 1), ""), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp), ""), shares1);
        assertEq(VaultImplementation(payable(address(vault))).activeShares(), shares1);
        assertEq(VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp - 1), ""), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp), ""), amount1);
        assertEq(VaultImplementation(payable(address(vault))).activeStake(), amount1);
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesOfAt(alice, uint48(blockTimestamp - 1), ""), 0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesOfAt(alice, uint48(blockTimestamp), ""), shares1
        );
        assertEq(VaultImplementation(payable(address(vault))).activeSharesOf(alice), shares1);
        assertEq(
            VaultImplementation(payable(address(vault))).activeBalanceOfAt(alice, uint48(blockTimestamp - 1), ""), 0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).activeBalanceOfAt(alice, uint48(blockTimestamp), ""), amount1
        );
        assertEq(VaultImplementation(payable(address(vault))).activeBalanceOf(alice), amount1);
        assertEq(VaultImplementation(payable(address(vault))).slashableBalanceOf(alice), amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 shares2 = amount2 * (shares1 + 10 ** 0) / (amount1 + 1);
        {
            (uint256 depositedAmount, uint256 mintedShares) = _deposit(alice, amount2);
            assertEq(depositedAmount, amount2);
            assertEq(mintedShares, shares2);

            assertEq(vault.balanceOf(alice), shares1 + shares2);
            assertEq(vault.totalSupply(), shares1 + shares2);
        }

        assertEq(VaultImplementation(payable(address(vault))).totalStake(), amount1 + amount2);
        assertEq(VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp - 1), ""), shares1);
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp), ""), shares1 + shares2
        );
        assertEq(VaultImplementation(payable(address(vault))).activeShares(), shares1 + shares2);
        uint256 gasLeft = gasleft();
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp - 1), abi.encode(1)),
            shares1
        );
        uint256 gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp - 1), abi.encode(0)),
            shares1
        );
        assertGt(gasSpent, gasLeft - gasleft());
        gasLeft = gasleft();
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp), abi.encode(0)),
            shares1 + shares2
        );
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp), abi.encode(1)),
            shares1 + shares2
        );
        assertGt(gasSpent, gasLeft - gasleft());
        assertEq(VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp - 1), ""), amount1);
        assertEq(
            VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp), ""), amount1 + amount2
        );
        assertEq(VaultImplementation(payable(address(vault))).activeStake(), amount1 + amount2);
        gasLeft = gasleft();
        assertEq(
            VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp - 1), abi.encode(1)),
            amount1
        );
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(
            VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp - 1), abi.encode(0)),
            amount1
        );
        assertGt(gasSpent, gasLeft - gasleft());
        gasLeft = gasleft();
        assertEq(
            VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp), abi.encode(0)),
            amount1 + amount2
        );
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(
            VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp), abi.encode(1)),
            amount1 + amount2
        );
        assertGt(gasSpent, gasLeft - gasleft());
        assertEq(VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp - 1), ""), shares1);
        assertEq(
            VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp), ""), shares1 + shares2
        );
        assertEq(VaultImplementation(payable(address(vault))).activeSharesOf(alice), shares1 + shares2);
        gasLeft = gasleft();
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesOfAt(
                alice, uint48(blockTimestamp - 1), abi.encode(1)
            ),
            shares1
        );
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesOfAt(
                alice, uint48(blockTimestamp - 1), abi.encode(0)
            ),
            shares1
        );
        assertGt(gasSpent, gasLeft - gasleft());
        gasLeft = gasleft();
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesOfAt(alice, uint48(blockTimestamp), abi.encode(0)),
            shares1 + shares2
        );
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesOfAt(alice, uint48(blockTimestamp), abi.encode(1)),
            shares1 + shares2
        );
        assertGt(gasSpent, gasLeft - gasleft());
        assertEq(
            VaultImplementation(payable(address(vault))).activeBalanceOfAt(alice, uint48(blockTimestamp - 1), ""),
            amount1
        );
        assertEq(
            VaultImplementation(payable(address(vault))).activeBalanceOfAt(alice, uint48(blockTimestamp), ""),
            amount1 + amount2
        );
        assertEq(VaultImplementation(payable(address(vault))).activeBalanceOf(alice), amount1 + amount2);
        assertEq(VaultImplementation(payable(address(vault))).slashableBalanceOf(alice), amount1 + amount2);
        gasLeft = gasleft();
        assertEq(
            VaultImplementation(payable(address(vault))).activeBalanceOfAt(
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
            VaultImplementation(payable(address(vault))).activeBalanceOfAt(
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
            VaultImplementation(payable(address(vault))).activeBalanceOfAt(
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
            VaultImplementation(payable(address(vault))).activeBalanceOfAt(
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
            (address vault_,,) = vaultConfigurator.create(
                IVaultConfigurator.InitParams({
                    version: 3,
                    owner: alice,
                    vaultParams: abi.encode(
                        IVaultTokenized.InitParamsTokenized({
                            baseParams: abi.encode(
                                IVault.InitParams({
                                    collateral: address(feeOnTransferCollateral),
                                    burner: address(0xdEaD),
                                    epochDuration: 7 days,
                                    depositWhitelist: false,
                                    isDepositLimit: false,
                                    depositLimit: 0,
                                    epochDurationSetEpochsDelay: 3,
                                    flashLoanEnabled: false,
                                    flashFeeRate: 1,
                                    flashFeeReceiver: alice,
                                    defaultAdminRoleHolder: alice,
                                    depositWhitelistSetRoleHolder: alice,
                                    depositorWhitelistRoleHolder: alice,
                                    depositorsWhitelisted: new address[](0),
                                    isDepositLimitSetRoleHolder: alice,
                                    depositLimitSetRoleHolder: alice,
                                    epochDurationSetRoleHolder: alice,
                                    flashLoanEnabledSetRoleHolder: alice,
                                    flashFeeRateSetRoleHolder: alice,
                                    flashFeeReceiverSetRoleHolder: alice
                                })
                            ),
                            name: "Test",
                            symbol: "TEST"
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
                    slasherParams: ""
                })
            );

            vault = VaultTokenizedImplementation(payable(vault_));
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

        assertEq(VaultImplementation(payable(address(vault))).totalStake(), amount1 - 1);
        assertEq(VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp - 1), ""), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp), ""), shares1);
        assertEq(VaultImplementation(payable(address(vault))).activeShares(), shares1);
        assertEq(VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp - 1), ""), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp), ""), amount1 - 1);
        assertEq(VaultImplementation(payable(address(vault))).activeStake(), amount1 - 1);
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesOfAt(alice, uint48(blockTimestamp - 1), ""), 0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesOfAt(alice, uint48(blockTimestamp), ""), shares1
        );
        assertEq(VaultImplementation(payable(address(vault))).activeSharesOf(alice), shares1);
        assertEq(
            VaultImplementation(payable(address(vault))).activeBalanceOfAt(alice, uint48(blockTimestamp - 1), ""), 0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).activeBalanceOfAt(alice, uint48(blockTimestamp), ""),
            amount1 - 1
        );
        assertEq(VaultImplementation(payable(address(vault))).activeBalanceOf(alice), amount1 - 1);
        assertEq(VaultImplementation(payable(address(vault))).slashableBalanceOf(alice), amount1 - 1);

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

        assertEq(VaultImplementation(payable(address(vault))).totalStake(), amount1 - 1 + amount2 - 1);
        assertEq(VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp - 1), ""), shares1);
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp), ""), shares1 + shares2
        );
        assertEq(VaultImplementation(payable(address(vault))).activeShares(), shares1 + shares2);
        uint256 gasLeft = gasleft();
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp - 1), abi.encode(1)),
            shares1
        );
        uint256 gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp - 1), abi.encode(0)),
            shares1
        );
        assertGt(gasSpent, gasLeft - gasleft());
        gasLeft = gasleft();
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp), abi.encode(0)),
            shares1 + shares2
        );
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp), abi.encode(1)),
            shares1 + shares2
        );
        assertGt(gasSpent, gasLeft - gasleft());
        assertEq(
            VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp - 1), ""), amount1 - 1
        );
        assertEq(
            VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp), ""),
            amount1 - 1 + amount2 - 1
        );
        assertEq(VaultImplementation(payable(address(vault))).activeStake(), amount1 - 1 + amount2 - 1);
        gasLeft = gasleft();
        assertEq(
            VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp - 1), abi.encode(1)),
            amount1 - 1
        );
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(
            VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp - 1), abi.encode(0)),
            amount1 - 1
        );
        assertGt(gasSpent, gasLeft - gasleft());
        gasLeft = gasleft();
        assertEq(
            VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp), abi.encode(0)),
            amount1 - 1 + amount2 - 1
        );
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(
            VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp), abi.encode(1)),
            amount1 - 1 + amount2 - 1
        );
        assertGt(gasSpent, gasLeft - gasleft());
        assertEq(VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp - 1), ""), shares1);
        assertEq(
            VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp), ""), shares1 + shares2
        );
        assertEq(VaultImplementation(payable(address(vault))).activeSharesOf(alice), shares1 + shares2);
        gasLeft = gasleft();
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesOfAt(
                alice, uint48(blockTimestamp - 1), abi.encode(1)
            ),
            shares1
        );
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesOfAt(
                alice, uint48(blockTimestamp - 1), abi.encode(0)
            ),
            shares1
        );
        assertGt(gasSpent, gasLeft - gasleft());
        gasLeft = gasleft();
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesOfAt(alice, uint48(blockTimestamp), abi.encode(0)),
            shares1 + shares2
        );
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesOfAt(alice, uint48(blockTimestamp), abi.encode(1)),
            shares1 + shares2
        );
        assertGt(gasSpent, gasLeft - gasleft());
        assertEq(
            VaultImplementation(payable(address(vault))).activeBalanceOfAt(alice, uint48(blockTimestamp - 1), ""),
            amount1 - 1
        );
        assertEq(
            VaultImplementation(payable(address(vault))).activeBalanceOfAt(alice, uint48(blockTimestamp), ""),
            amount1 - 1 + amount2 - 1
        );
        assertEq(VaultImplementation(payable(address(vault))).activeBalanceOf(alice), amount1 - 1 + amount2 - 1);
        assertEq(VaultImplementation(payable(address(vault))).slashableBalanceOf(alice), amount1 - 1 + amount2 - 1);
        gasLeft = gasleft();
        assertEq(
            VaultImplementation(payable(address(vault))).activeBalanceOfAt(
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
            VaultImplementation(payable(address(vault))).activeBalanceOfAt(
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
            VaultImplementation(payable(address(vault))).activeBalanceOfAt(
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
            VaultImplementation(payable(address(vault))).activeBalanceOfAt(
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

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        uint256 shares1 = amount1 * 10 ** 0;
        {
            (uint256 depositedAmount, uint256 mintedShares) = _deposit(alice, amount1);
            assertEq(depositedAmount, amount1);
            assertEq(mintedShares, shares1);

            assertEq(vault.balanceOf(alice), shares1);
            assertEq(vault.totalSupply(), shares1);
        }

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 shares2 = amount2 * (shares1 + 10 ** 0) / (amount1 + 1);
        {
            (uint256 depositedAmount, uint256 mintedShares) = _deposit(bob, amount2);
            assertEq(depositedAmount, amount2);
            assertEq(mintedShares, shares2);

            assertEq(vault.balanceOf(bob), shares2);
            assertEq(vault.totalSupply(), shares1 + shares2);
        }

        assertEq(VaultImplementation(payable(address(vault))).totalStake(), amount1 + amount2);
        assertEq(VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp - 1), ""), shares1);
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp), ""), shares1 + shares2
        );
        assertEq(VaultImplementation(payable(address(vault))).activeShares(), shares1 + shares2);
        assertEq(VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp - 1), ""), amount1);
        assertEq(
            VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp), ""), amount1 + amount2
        );
        assertEq(VaultImplementation(payable(address(vault))).activeStake(), amount1 + amount2);
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesOfAt(alice, uint48(blockTimestamp - 1), ""),
            shares1
        );
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesOfAt(alice, uint48(blockTimestamp), ""), shares1
        );
        assertEq(VaultImplementation(payable(address(vault))).activeSharesOf(alice), shares1);
        assertEq(
            VaultImplementation(payable(address(vault))).activeBalanceOfAt(alice, uint48(blockTimestamp - 1), ""),
            amount1
        );
        assertEq(
            VaultImplementation(payable(address(vault))).activeBalanceOfAt(alice, uint48(blockTimestamp), ""), amount1
        );
        assertEq(VaultImplementation(payable(address(vault))).activeBalanceOf(alice), amount1);
        assertEq(VaultImplementation(payable(address(vault))).slashableBalanceOf(alice), amount1);
        assertEq(VaultImplementation(payable(address(vault))).activeSharesOfAt(bob, uint48(blockTimestamp - 1), ""), 0);
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesOfAt(bob, uint48(blockTimestamp), ""), shares2
        );
        assertEq(VaultImplementation(payable(address(vault))).activeSharesOf(bob), shares2);
        assertEq(VaultImplementation(payable(address(vault))).activeBalanceOfAt(bob, uint48(blockTimestamp - 1), ""), 0);
        assertEq(
            VaultImplementation(payable(address(vault))).activeBalanceOfAt(bob, uint48(blockTimestamp), ""), amount2
        );
        assertEq(VaultImplementation(payable(address(vault))).activeBalanceOf(bob), amount2);
        assertEq(VaultImplementation(payable(address(vault))).slashableBalanceOf(bob), amount2);
    }

    function test_DepositRevertInvalidOnBehalfOf(
        uint256 amount1
    ) public {
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

    function test_WithdrawTwice(uint256 amount1, uint256 amount2, uint256 amount3) public {
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

        assertEq(vault.balanceOf(alice), amount1 - burnedShares_);
        assertEq(vault.totalSupply(), amount1 - burnedShares_);

        assertEq(VaultImplementation(payable(address(vault))).totalStake(), amount1);
        assertEq(VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp - 1), ""), shares);
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp), ""),
            shares - burnedShares
        );
        assertEq(VaultImplementation(payable(address(vault))).activeShares(), shares - burnedShares);
        assertEq(VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp - 1), ""), amount1);
        assertEq(
            VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp), ""), amount1 - amount2
        );
        assertEq(VaultImplementation(payable(address(vault))).activeStake(), amount1 - amount2);
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesOfAt(alice, uint48(blockTimestamp - 1), ""), shares
        );
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesOfAt(alice, uint48(blockTimestamp), ""),
            shares - burnedShares
        );
        assertEq(VaultImplementation(payable(address(vault))).activeSharesOf(alice), shares - burnedShares);
        assertEq(
            VaultImplementation(payable(address(vault))).activeBalanceOfAt(alice, uint48(blockTimestamp - 1), ""),
            amount1
        );
        assertEq(
            VaultImplementation(payable(address(vault))).activeBalanceOfAt(alice, uint48(blockTimestamp), ""),
            amount1 - amount2
        );
        assertEq(VaultImplementation(payable(address(vault))).activeBalanceOf(alice), amount1 - amount2);
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawals(
                VaultImplementation(payable(address(vault))).currentEpoch()
            ),
            0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawals(
                VaultImplementation(payable(address(vault))).currentEpoch() + 1
            ),
            amount2
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawals(
                VaultImplementation(payable(address(vault))).currentEpoch() + 2
            ),
            0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalShares(
                VaultImplementation(payable(address(vault))).currentEpoch()
            ),
            0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalShares(
                VaultImplementation(payable(address(vault))).currentEpoch() + 1
            ),
            mintedShares
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalShares(
                VaultImplementation(payable(address(vault))).currentEpoch() + 2
            ),
            0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalSharesOf(
                VaultImplementation(payable(address(vault))).currentEpoch(), alice
            ),
            0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalSharesOf(
                VaultImplementation(payable(address(vault))).currentEpoch() + 1, alice
            ),
            mintedShares
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalSharesOf(
                VaultImplementation(payable(address(vault))).currentEpoch() + 2, alice
            ),
            0
        );
        assertEq(VaultImplementation(payable(address(vault))).slashableBalanceOf(alice), amount1);

        shares -= burnedShares;

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        burnedShares = amount3 * (shares + 10 ** 0) / (amount1 - amount2 + 1);
        mintedShares = amount3 * 10 ** 0;
        (burnedShares_, mintedShares_) = _withdraw(alice, amount3);
        assertEq(burnedShares_, burnedShares);
        assertEq(mintedShares_, mintedShares);

        assertEq(vault.balanceOf(alice), amount1 - amount2 - amount3);
        assertEq(vault.totalSupply(), amount1 - amount2 - amount3);

        assertEq(VaultImplementation(payable(address(vault))).totalStake(), amount1);
        assertEq(VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp - 1), ""), shares);
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp), ""),
            shares - burnedShares
        );
        assertEq(VaultImplementation(payable(address(vault))).activeShares(), shares - burnedShares);
        assertEq(
            VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp - 1), ""),
            amount1 - amount2
        );
        assertEq(
            VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp), ""),
            amount1 - amount2 - amount3
        );
        assertEq(VaultImplementation(payable(address(vault))).activeStake(), amount1 - amount2 - amount3);
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesOfAt(alice, uint48(blockTimestamp - 1), ""), shares
        );
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesOfAt(alice, uint48(blockTimestamp), ""),
            shares - burnedShares
        );
        assertEq(VaultImplementation(payable(address(vault))).activeSharesOf(alice), shares - burnedShares);
        assertEq(
            VaultImplementation(payable(address(vault))).activeBalanceOfAt(alice, uint48(blockTimestamp - 1), ""),
            amount1 - amount2
        );
        assertEq(
            VaultImplementation(payable(address(vault))).activeBalanceOfAt(alice, uint48(blockTimestamp), ""),
            amount1 - amount2 - amount3
        );
        assertEq(VaultImplementation(payable(address(vault))).activeBalanceOf(alice), amount1 - amount2 - amount3);
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawals(
                VaultImplementation(payable(address(vault))).currentEpoch() - 1
            ),
            0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawals(
                VaultImplementation(payable(address(vault))).currentEpoch()
            ),
            amount2
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawals(
                VaultImplementation(payable(address(vault))).currentEpoch() + 1
            ),
            amount3
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawals(
                VaultImplementation(payable(address(vault))).currentEpoch() + 2
            ),
            0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalShares(
                VaultImplementation(payable(address(vault))).currentEpoch() - 1
            ),
            0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalShares(
                VaultImplementation(payable(address(vault))).currentEpoch()
            ),
            amount2 * 10 ** 0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalShares(
                VaultImplementation(payable(address(vault))).currentEpoch() + 1
            ),
            amount3 * 10 ** 0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalShares(
                VaultImplementation(payable(address(vault))).currentEpoch() + 2
            ),
            0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalSharesOf(
                VaultImplementation(payable(address(vault))).currentEpoch() - 1, alice
            ),
            0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalSharesOf(
                VaultImplementation(payable(address(vault))).currentEpoch(), alice
            ),
            amount2 * 10 ** 0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalSharesOf(
                VaultImplementation(payable(address(vault))).currentEpoch() + 1, alice
            ),
            amount3 * 10 ** 0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalSharesOf(
                VaultImplementation(payable(address(vault))).currentEpoch() + 2, alice
            ),
            0
        );
        assertEq(VaultImplementation(payable(address(vault))).slashableBalanceOf(alice), amount1);

        shares -= burnedShares;

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(VaultImplementation(payable(address(vault))).totalStake(), amount1 - amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(VaultImplementation(payable(address(vault))).totalStake(), amount1 - amount2 - amount3);
    }

    function test_WithdrawRevertInvalidClaimer(
        uint256 amount1
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        vm.expectRevert(IVault.InvalidClaimer.selector);
        vm.startPrank(alice);
        vault.withdraw(address(0), amount1);
        vm.stopPrank();
    }

    function test_WithdrawRevertInsufficientWithdrawal(
        uint256 amount1
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        vm.expectRevert(IVault.InsufficientWithdrawal.selector);
        _withdraw(alice, 0);
    }

    function test_WithdrawRevertTooMuchWithdraw(
        uint256 amount1
    ) public {
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

        assertEq(VaultImplementation(payable(address(vault))).totalStake(), amount1);
        assertEq(VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp - 1), ""), shares);
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp), ""), shares - amount2
        );
        assertEq(VaultImplementation(payable(address(vault))).activeShares(), shares - amount2);
        assertEq(VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp - 1), ""), amount1);
        assertEq(
            VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp), ""),
            amount1 - withdrawnAssets2
        );
        assertEq(VaultImplementation(payable(address(vault))).activeStake(), amount1 - withdrawnAssets2);
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesOfAt(alice, uint48(blockTimestamp - 1), ""), shares
        );
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesOfAt(alice, uint48(blockTimestamp), ""),
            shares - amount2
        );
        assertEq(VaultImplementation(payable(address(vault))).activeSharesOf(alice), shares - amount2);
        assertEq(
            VaultImplementation(payable(address(vault))).activeBalanceOfAt(alice, uint48(blockTimestamp - 1), ""),
            amount1
        );
        assertEq(
            VaultImplementation(payable(address(vault))).activeBalanceOfAt(alice, uint48(blockTimestamp), ""),
            amount1 - withdrawnAssets2
        );
        assertEq(VaultImplementation(payable(address(vault))).activeBalanceOf(alice), amount1 - withdrawnAssets2);
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawals(
                VaultImplementation(payable(address(vault))).currentEpoch()
            ),
            0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawals(
                VaultImplementation(payable(address(vault))).currentEpoch() + 1
            ),
            withdrawnAssets2
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawals(
                VaultImplementation(payable(address(vault))).currentEpoch() + 2
            ),
            0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalShares(
                VaultImplementation(payable(address(vault))).currentEpoch()
            ),
            0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalShares(
                VaultImplementation(payable(address(vault))).currentEpoch() + 1
            ),
            mintedShares
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalShares(
                VaultImplementation(payable(address(vault))).currentEpoch() + 2
            ),
            0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalSharesOf(
                VaultImplementation(payable(address(vault))).currentEpoch(), alice
            ),
            0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalSharesOf(
                VaultImplementation(payable(address(vault))).currentEpoch() + 1, alice
            ),
            mintedShares
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalSharesOf(
                VaultImplementation(payable(address(vault))).currentEpoch() + 2, alice
            ),
            0
        );
        assertEq(VaultImplementation(payable(address(vault))).slashableBalanceOf(alice), amount1);

        shares -= amount2;

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 withdrawnAssets3 = amount3 * (amount1 - withdrawnAssets2 + 1) / (shares + 10 ** 0);
        mintedShares = amount3 * 10 ** 0;
        (withdrawnAssets_, mintedShares_) = _redeem(alice, amount3);
        assertEq(withdrawnAssets_, withdrawnAssets3);
        assertEq(mintedShares_, mintedShares);

        assertEq(VaultImplementation(payable(address(vault))).totalStake(), amount1);
        assertEq(VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp - 1), ""), shares);
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp), ""), shares - amount3
        );
        assertEq(VaultImplementation(payable(address(vault))).activeShares(), shares - amount3);
        assertEq(
            VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp - 1), ""),
            amount1 - withdrawnAssets2
        );
        assertEq(
            VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp), ""),
            amount1 - withdrawnAssets2 - withdrawnAssets3
        );
        assertEq(
            VaultImplementation(payable(address(vault))).activeStake(), amount1 - withdrawnAssets2 - withdrawnAssets3
        );
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesOfAt(alice, uint48(blockTimestamp - 1), ""), shares
        );
        assertEq(
            VaultImplementation(payable(address(vault))).activeSharesOfAt(alice, uint48(blockTimestamp), ""),
            shares - amount3
        );
        assertEq(VaultImplementation(payable(address(vault))).activeSharesOf(alice), shares - amount3);
        assertEq(
            VaultImplementation(payable(address(vault))).activeBalanceOfAt(alice, uint48(blockTimestamp - 1), ""),
            amount1 - withdrawnAssets2
        );
        assertEq(
            VaultImplementation(payable(address(vault))).activeBalanceOfAt(alice, uint48(blockTimestamp), ""),
            amount1 - withdrawnAssets2 - withdrawnAssets3
        );
        assertEq(
            VaultImplementation(payable(address(vault))).activeBalanceOf(alice),
            amount1 - withdrawnAssets2 - withdrawnAssets3
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawals(
                VaultImplementation(payable(address(vault))).currentEpoch() - 1
            ),
            0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawals(
                VaultImplementation(payable(address(vault))).currentEpoch()
            ),
            withdrawnAssets2
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawals(
                VaultImplementation(payable(address(vault))).currentEpoch() + 1
            ),
            withdrawnAssets3
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawals(
                VaultImplementation(payable(address(vault))).currentEpoch() + 2
            ),
            0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalShares(
                VaultImplementation(payable(address(vault))).currentEpoch() - 1
            ),
            0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalShares(
                VaultImplementation(payable(address(vault))).currentEpoch()
            ),
            withdrawnAssets2 * 10 ** 0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalShares(
                VaultImplementation(payable(address(vault))).currentEpoch() + 1
            ),
            withdrawnAssets3 * 10 ** 0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalShares(
                VaultImplementation(payable(address(vault))).currentEpoch() + 2
            ),
            0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalSharesOf(
                VaultImplementation(payable(address(vault))).currentEpoch() - 1, alice
            ),
            0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalSharesOf(
                VaultImplementation(payable(address(vault))).currentEpoch(), alice
            ),
            withdrawnAssets2 * 10 ** 0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalSharesOf(
                VaultImplementation(payable(address(vault))).currentEpoch() + 1, alice
            ),
            withdrawnAssets3 * 10 ** 0
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawalSharesOf(
                VaultImplementation(payable(address(vault))).currentEpoch() + 2, alice
            ),
            0
        );
        assertEq(VaultImplementation(payable(address(vault))).slashableBalanceOf(alice), amount1);

        shares -= amount3;

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(VaultImplementation(payable(address(vault))).totalStake(), amount1 - withdrawnAssets2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(
            VaultImplementation(payable(address(vault))).totalStake(), amount1 - withdrawnAssets2 - withdrawnAssets3
        );
    }

    function test_RedeemRevertInvalidClaimer(
        uint256 amount1
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        vm.expectRevert(IVault.InvalidClaimer.selector);
        vm.startPrank(alice);
        vault.redeem(address(0), amount1);
        vm.stopPrank();
    }

    function test_RedeemRevertInsufficientRedeemption(
        uint256 amount1
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        vm.expectRevert(IVault.InsufficientRedemption.selector);
        _redeem(alice, 0);
    }

    function test_RedeemRevertTooMuchRedeem(
        uint256 amount1
    ) public {
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
        assertEq(_claim(alice, VaultImplementation(payable(address(vault))).currentEpoch() - 1), amount2);
        assertEq(tokensBefore - collateral.balanceOf(address(vault)), amount2);
        assertEq(collateral.balanceOf(alice) - tokensBeforeAlice, amount2);

        assertEq(
            vault.isWithdrawalsClaimed(VaultImplementation(payable(address(vault))).currentEpoch() - 1, alice), true
        );
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
        uint256 currentEpoch = VaultImplementation(payable(address(vault))).currentEpoch();
        vm.expectRevert(IVault.InvalidRecipient.selector);
        VaultImplementation(payable(address(vault))).claim(address(0), currentEpoch - 1);
        vm.stopPrank();
    }

    function test_ClaimRevertInvalidEpoch(uint256 amount1, uint256 amount2) public {
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

        uint256 currentEpoch = VaultImplementation(payable(address(vault))).currentEpoch();
        vm.expectRevert(IVault.InvalidEpoch.selector);
        _claim(alice, currentEpoch);
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

        uint256 currentEpoch = VaultImplementation(payable(address(vault))).currentEpoch();
        _claim(alice, currentEpoch - 1);

        vm.expectRevert(IVault.AlreadyClaimed.selector);
        _claim(alice, currentEpoch - 1);
    }

    function test_ClaimRevertInsufficientClaim(uint256 amount1, uint256 amount2) public {
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

        uint256 currentEpoch = VaultImplementation(payable(address(vault))).currentEpoch();
        vm.expectRevert(IVault.InsufficientClaim.selector);
        _claim(alice, currentEpoch - 2);
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

        uint256[] memory epochs = new uint256[](2);
        epochs[0] = VaultImplementation(payable(address(vault))).currentEpoch() - 1;
        epochs[1] = VaultImplementation(payable(address(vault))).currentEpoch() - 2;

        uint256 tokensBefore = collateral.balanceOf(address(vault));
        uint256 tokensBeforeAlice = collateral.balanceOf(alice);
        assertEq(_claimBatch(alice, epochs), amount2 + amount3);
        assertEq(tokensBefore - collateral.balanceOf(address(vault)), amount2 + amount3);
        assertEq(collateral.balanceOf(alice) - tokensBeforeAlice, amount2 + amount3);

        assertEq(
            vault.isWithdrawalsClaimed(VaultImplementation(payable(address(vault))).currentEpoch() - 1, alice), true
        );
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

        uint256[] memory epochs = new uint256[](2);
        epochs[0] = VaultImplementation(payable(address(vault))).currentEpoch() - 1;
        epochs[1] = VaultImplementation(payable(address(vault))).currentEpoch() - 2;

        vm.expectRevert(IVault.InvalidRecipient.selector);
        vm.startPrank(alice);
        VaultImplementation(payable(address(vault))).claimBatch(address(0), epochs);
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

        uint256[] memory epochs = new uint256[](0);
        vm.expectRevert(IVault.InvalidLengthEpochs.selector);
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

        uint256[] memory epochs = new uint256[](2);
        epochs[0] = VaultImplementation(payable(address(vault))).currentEpoch() - 1;
        epochs[1] = VaultImplementation(payable(address(vault))).currentEpoch();

        vm.expectRevert(IVault.InvalidEpoch.selector);
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

        uint256[] memory epochs = new uint256[](2);
        epochs[0] = VaultImplementation(payable(address(vault))).currentEpoch() - 1;
        epochs[1] = VaultImplementation(payable(address(vault))).currentEpoch() - 1;

        vm.expectRevert(IVault.AlreadyClaimed.selector);
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

        uint256[] memory epochs = new uint256[](2);
        epochs[0] = VaultImplementation(payable(address(vault))).currentEpoch() - 1;
        epochs[1] = VaultImplementation(payable(address(vault))).currentEpoch() - 3;

        vm.expectRevert(IVault.InsufficientClaim.selector);
        _claimBatch(alice, epochs);
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

    function test_SetDepositLimitToNull(
        uint256 limit1
    ) public {
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

    function test_SetDepositLimitRevertAlreadySet(
        uint256 limit
    ) public {
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

    function test_OnSlashRevertNotSlasher() public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        vm.startPrank(alice);
        vm.expectRevert(IVault.NotSlasher.selector);
        VaultImplementation(payable(address(vault))).onSlash(0, 0);
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
        // uint48 epochDuration,
        uint256 depositAmount,
        uint256 withdrawAmount1,
        uint256 withdrawAmount2,
        uint256 slashAmount1,
        uint256 slashAmount2,
        uint256 captureAgo
    ) public {
        // epochDuration = uint48(bound(epochDuration, 2, 10 days));
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

        blockTimestamp = blockTimestamp + VaultImplementation(payable(address(vault))).epochDuration();
        vm.warp(blockTimestamp);

        _withdraw(alice, withdrawAmount2);

        assertEq(VaultImplementation(payable(address(vault))).totalStake(), depositAmount);
        assertEq(
            VaultImplementation(payable(address(vault))).activeStake(),
            depositAmount - withdrawAmount1 - withdrawAmount2
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawals(
                VaultImplementation(payable(address(vault))).currentEpoch()
            ),
            withdrawAmount1
        );
        assertEq(
            VaultImplementation(payable(address(vault))).withdrawals(
                VaultImplementation(payable(address(vault))).currentEpoch() + 1
            ),
            withdrawAmount2
        );

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        Test_SlashStruct memory test_SlashStruct;

        if (
            VaultImplementation(payable(address(vault))).epochAt(uint48(blockTimestamp - captureAgo))
                != VaultImplementation(payable(address(vault))).currentEpoch()
        ) {
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
                - (depositAmount - withdrawAmount1 - withdrawAmount2).mulDiv(
                    test_SlashStruct.slashAmountReal1, depositAmount
                );
            test_SlashStruct.withdrawals1 =
                withdrawAmount1 - withdrawAmount1.mulDiv(test_SlashStruct.slashAmountReal1, depositAmount);
            test_SlashStruct.nextWithdrawals1 =
                withdrawAmount2 - withdrawAmount2.mulDiv(test_SlashStruct.slashAmountReal1, depositAmount);
            assertEq(
                VaultImplementation(payable(address(vault))).totalStake(),
                depositAmount - test_SlashStruct.slashAmountReal1
            );
            assertTrue(
                test_SlashStruct.withdrawals1
                    - vault.withdrawals(VaultImplementation(payable(address(vault))).currentEpoch()) <= 2
            );
            assertTrue(
                test_SlashStruct.nextWithdrawals1
                    - vault.withdrawals(VaultImplementation(payable(address(vault))).currentEpoch() + 1) <= 1
            );
            assertEq(VaultImplementation(payable(address(vault))).activeStake(), test_SlashStruct.activeStake1);

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

            assertEq(
                VaultImplementation(payable(address(vault))).totalStake(),
                depositAmount - test_SlashStruct.slashAmountReal1 - test_SlashStruct.slashAmountSlashed2
            );
            assertTrue(
                (
                    test_SlashStruct.withdrawals1
                        - test_SlashStruct.withdrawals1.mulDiv(
                            test_SlashStruct.slashAmountSlashed2, depositAmount - test_SlashStruct.slashAmountReal1
                        )
                )
                    - VaultImplementation(payable(address(vault))).withdrawals(
                        VaultImplementation(payable(address(vault))).currentEpoch()
                    ) <= 4
            );
            assertTrue(
                (
                    test_SlashStruct.nextWithdrawals1
                        - test_SlashStruct.nextWithdrawals1.mulDiv(
                            test_SlashStruct.slashAmountSlashed2, depositAmount - test_SlashStruct.slashAmountReal1
                        )
                )
                    - VaultImplementation(payable(address(vault))).withdrawals(
                        VaultImplementation(payable(address(vault))).currentEpoch() + 1
                    ) <= 2
            );
            assertEq(
                VaultImplementation(payable(address(vault))).activeStake(),
                test_SlashStruct.activeStake1
                    - test_SlashStruct.activeStake1.mulDiv(
                        test_SlashStruct.slashAmountSlashed2, depositAmount - test_SlashStruct.slashAmountReal1
                    )
            );
        } else {
            test_SlashStruct.slashAmountReal1 =
                Math.min(slashAmount1, depositAmount - withdrawAmount1 - withdrawAmount2);
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
                - (depositAmount - withdrawAmount1 - withdrawAmount2).mulDiv(
                    test_SlashStruct.slashAmountReal1, depositAmount - withdrawAmount1
                );
            test_SlashStruct.withdrawals1 = withdrawAmount1;
            test_SlashStruct.nextWithdrawals1 = withdrawAmount2
                - withdrawAmount2.mulDiv(test_SlashStruct.slashAmountReal1, depositAmount - withdrawAmount1);
            assertEq(
                VaultImplementation(payable(address(vault))).totalStake(),
                depositAmount - test_SlashStruct.slashAmountReal1
            );
            assertEq(
                vault.withdrawals(VaultImplementation(payable(address(vault))).currentEpoch()),
                test_SlashStruct.withdrawals1
            );
            assertTrue(
                test_SlashStruct.nextWithdrawals1
                    - VaultImplementation(payable(address(vault))).withdrawals(
                        VaultImplementation(payable(address(vault))).currentEpoch() + 1
                    ) <= 1
            );
            assertEq(VaultImplementation(payable(address(vault))).activeStake(), test_SlashStruct.activeStake1);

            test_SlashStruct.slashAmountSlashed2 = Math.min(
                depositAmount - withdrawAmount1 - test_SlashStruct.slashAmountReal1,
                Math.min(slashAmount2, depositAmount - withdrawAmount1 - withdrawAmount2)
            );
            test_SlashStruct.tokensBeforeBurner = collateral.balanceOf(address(vault.burner()));
            assertEq(
                _slash(alice, alice, bob, slashAmount2, uint48(blockTimestamp - captureAgo), ""),
                Math.min(slashAmount2, depositAmount - withdrawAmount1 - withdrawAmount2)
            );
            assertEq(
                collateral.balanceOf(address(vault.burner())) - test_SlashStruct.tokensBeforeBurner,
                test_SlashStruct.slashAmountSlashed2
            );

            assertEq(
                VaultImplementation(payable(address(vault))).totalStake(),
                depositAmount - test_SlashStruct.slashAmountReal1 - test_SlashStruct.slashAmountSlashed2
            );
            assertEq(
                VaultImplementation(payable(address(vault))).withdrawals(
                    VaultImplementation(payable(address(vault))).currentEpoch()
                ),
                test_SlashStruct.withdrawals1
            );
            assertTrue(
                (
                    test_SlashStruct.nextWithdrawals1
                        - test_SlashStruct.nextWithdrawals1.mulDiv(
                            test_SlashStruct.slashAmountSlashed2,
                            depositAmount - withdrawAmount1 - test_SlashStruct.slashAmountReal1
                        )
                )
                    - VaultImplementation(payable(address(vault))).withdrawals(
                        VaultImplementation(payable(address(vault))).currentEpoch() + 1
                    ) <= 2
            );
            assertEq(
                VaultImplementation(payable(address(vault))).activeStake(),
                test_SlashStruct.activeStake1
                    - test_SlashStruct.activeStake1.mulDiv(
                        test_SlashStruct.slashAmountSlashed2,
                        depositAmount - withdrawAmount1 - test_SlashStruct.slashAmountReal1
                    )
            );
        }
    }

    function test_Migrate1() public {
        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
        (address vault_,,) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: 3,
                owner: alice,
                vaultParams: abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: 7 days,
                        depositWhitelist: false,
                        isDepositLimit: false,
                        depositLimit: 0,
                        epochDurationSetEpochsDelay: 3,
                        flashLoanEnabled: false,
                        flashFeeRate: 1,
                        flashFeeReceiver: alice,
                        defaultAdminRoleHolder: alice,
                        depositWhitelistSetRoleHolder: alice,
                        depositorWhitelistRoleHolder: alice,
                        depositorsWhitelisted: new address[](0),
                        isDepositLimitSetRoleHolder: alice,
                        depositLimitSetRoleHolder: alice,
                        epochDurationSetRoleHolder: alice,
                        flashLoanEnabledSetRoleHolder: alice,
                        flashFeeRateSetRoleHolder: alice,
                        flashFeeReceiverSetRoleHolder: alice
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

        vault = VaultTokenizedImplementation(payable(vault_));

        assertEq(vault.DEPOSIT_WHITELIST_SET_ROLE(), keccak256("DEPOSIT_WHITELIST_SET_ROLE"));
        assertEq(vault.DEPOSITOR_WHITELIST_ROLE(), keccak256("DEPOSITOR_WHITELIST_ROLE"));
        assertEq(VaultImplementation(payable(address(vault))).DELEGATOR_FACTORY(), address(delegatorFactory));
        assertEq(VaultImplementation(payable(address(vault))).SLASHER_FACTORY(), address(slasherFactory));

        assertEq(VaultTokenized(payable(address(vault))).owner(), alice);
        assertEq(vault.collateral(), address(collateral));
        assertEq(
            VaultImplementation(payable(address(vault))).hasRole(
                VaultImplementation(payable(address(vault))).DEFAULT_ADMIN_ROLE(), alice
            ),
            true
        );
        assertEq(
            VaultImplementation(payable(address(vault))).hasRole(
                VaultImplementation(payable(address(vault))).DEPOSITOR_WHITELIST_ROLE(), alice
            ),
            true
        );
        assertEq(VaultImplementation(payable(address(vault))).epochDurationInit(), blockTimestamp);
        assertEq(VaultImplementation(payable(address(vault))).epochDuration(), 7 days);
        vm.expectRevert(IVault.InvalidTimestamp.selector);
        assertEq(VaultImplementation(payable(address(vault))).epochAt(0), 0);
        assertEq(VaultImplementation(payable(address(vault))).epochAt(uint48(blockTimestamp)), 0);
        assertEq(VaultImplementation(payable(address(vault))).currentEpoch(), 0);
        assertEq(VaultImplementation(payable(address(vault))).currentEpochStart(), blockTimestamp);
        vm.expectRevert(IVault.NoPreviousEpoch.selector);
        VaultImplementation(payable(address(vault))).previousEpochStart();
        assertEq(VaultImplementation(payable(address(vault))).nextEpochStart(), blockTimestamp + 7 days);
        assertEq(VaultImplementation(payable(address(vault))).totalStake(), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp), ""), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeShares(), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp), ""), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeStake(), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeSharesOfAt(alice, uint48(blockTimestamp), ""), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeSharesOf(alice), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeBalanceOfAt(alice, uint48(blockTimestamp), ""), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeBalanceOf(alice), 0);
        assertEq(VaultImplementation(payable(address(vault))).withdrawals(0), 0);
        assertEq(VaultImplementation(payable(address(vault))).withdrawalShares(0), 0);
        assertEq(VaultImplementation(payable(address(vault))).isWithdrawalsClaimed(0, alice), false);
        assertEq(VaultImplementation(payable(address(vault))).depositWhitelist(), false);
        assertEq(VaultImplementation(payable(address(vault))).isDepositorWhitelisted(alice), false);
        assertEq(VaultImplementation(payable(address(vault))).slashableBalanceOf(alice), 0);
        assertEq(VaultImplementation(payable(address(vault))).isDelegatorInitialized(), true);
        assertEq(VaultImplementation(payable(address(vault))).isSlasherInitialized(), true);
        assertEq(VaultImplementation(payable(address(vault))).isInitialized(), true);
        assertEq(Vault(payable(address(vault))).version(), 3);

        uint256 decimals = collateral.decimals();
        vm.expectRevert();
        vault.balanceOf(alice);
        vm.expectRevert();
        vault.totalSupply();
        vm.expectRevert();
        vault.allowance(alice, alice);
        vm.expectRevert();
        vault.decimals();
        vm.expectRevert();
        vault.symbol();
        vm.expectRevert();
        vault.name();

        vm.expectRevert();
        VaultImplementation(payable(address(vault))).flashFeeRate();
        vm.expectRevert();
        VaultImplementation(payable(address(vault))).epochDurationSetEpochsDelay();

        vm.startPrank(alice);
        vaultFactory.migrate(
            address(vault), 4, abi.encode(IVaultTokenized.MigrateParamsTokenized({name: "test1", symbol: "TEST1"}))
        );
        vm.stopPrank();

        assertEq(Vault(payable(address(vault))).version(), 4);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.allowance(alice, alice), 0);
        assertEq(vault.decimals(), decimals);
        assertEq(vault.symbol(), "TEST1");
        assertEq(vault.name(), "test1");

        assertEq(VaultImplementation(payable(address(vault))).flashFeeRate(), 1);
        assertEq(VaultImplementation(payable(address(vault))).epochDurationSetEpochsDelay(), 3);
    }

    function test_Migrate2() public {
        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
        (address vault_,,) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: 2,
                owner: alice,
                vaultParams: abi.encode(
                    IVaultTokenizedV1.InitParamsTokenized({
                        baseParams: IVaultV1.InitParams({
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
                        }),
                        name: "test",
                        symbol: "TEST"
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

        vault = VaultTokenizedImplementation(payable(vault_));

        assertEq(vault.DEPOSIT_WHITELIST_SET_ROLE(), keccak256("DEPOSIT_WHITELIST_SET_ROLE"));
        assertEq(vault.DEPOSITOR_WHITELIST_ROLE(), keccak256("DEPOSITOR_WHITELIST_ROLE"));
        assertEq(VaultImplementation(payable(address(vault))).DELEGATOR_FACTORY(), address(delegatorFactory));
        assertEq(VaultImplementation(payable(address(vault))).SLASHER_FACTORY(), address(slasherFactory));

        assertEq(VaultTokenized(payable(address(vault))).owner(), alice);
        assertEq(vault.collateral(), address(collateral));
        assertEq(
            VaultImplementation(payable(address(vault))).hasRole(
                VaultImplementation(payable(address(vault))).DEFAULT_ADMIN_ROLE(), alice
            ),
            true
        );
        assertEq(
            VaultImplementation(payable(address(vault))).hasRole(
                VaultImplementation(payable(address(vault))).DEPOSITOR_WHITELIST_ROLE(), alice
            ),
            true
        );
        assertEq(VaultImplementation(payable(address(vault))).epochDurationInit(), blockTimestamp);
        assertEq(VaultImplementation(payable(address(vault))).epochDuration(), 7 days);
        vm.expectRevert(IVault.InvalidTimestamp.selector);
        assertEq(VaultImplementation(payable(address(vault))).epochAt(0), 0);
        assertEq(VaultImplementation(payable(address(vault))).epochAt(uint48(blockTimestamp)), 0);
        assertEq(VaultImplementation(payable(address(vault))).currentEpoch(), 0);
        assertEq(VaultImplementation(payable(address(vault))).currentEpochStart(), blockTimestamp);
        vm.expectRevert(IVault.NoPreviousEpoch.selector);
        VaultImplementation(payable(address(vault))).previousEpochStart();
        assertEq(VaultImplementation(payable(address(vault))).nextEpochStart(), blockTimestamp + 7 days);
        assertEq(VaultImplementation(payable(address(vault))).totalStake(), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeSharesAt(uint48(blockTimestamp), ""), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeShares(), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeStakeAt(uint48(blockTimestamp), ""), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeStake(), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeSharesOfAt(alice, uint48(blockTimestamp), ""), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeSharesOf(alice), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeBalanceOfAt(alice, uint48(blockTimestamp), ""), 0);
        assertEq(VaultImplementation(payable(address(vault))).activeBalanceOf(alice), 0);
        assertEq(VaultImplementation(payable(address(vault))).withdrawals(0), 0);
        assertEq(VaultImplementation(payable(address(vault))).withdrawalShares(0), 0);
        assertEq(VaultImplementation(payable(address(vault))).isWithdrawalsClaimed(0, alice), false);
        assertEq(VaultImplementation(payable(address(vault))).depositWhitelist(), false);
        assertEq(VaultImplementation(payable(address(vault))).isDepositorWhitelisted(alice), false);
        assertEq(VaultImplementation(payable(address(vault))).slashableBalanceOf(alice), 0);
        assertEq(VaultImplementation(payable(address(vault))).isDelegatorInitialized(), true);
        assertEq(VaultImplementation(payable(address(vault))).isSlasherInitialized(), true);
        assertEq(VaultImplementation(payable(address(vault))).isInitialized(), true);
        assertEq(Vault(payable(address(vault))).version(), 2);

        uint256 decimals = collateral.decimals();
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.allowance(alice, alice), 0);
        assertEq(vault.decimals(), decimals);
        assertEq(vault.symbol(), "TEST");
        assertEq(vault.name(), "test");

        vm.expectRevert();
        VaultImplementation(payable(address(vault))).flashFeeRate();
        vm.expectRevert();
        VaultImplementation(payable(address(vault))).epochDurationSetEpochsDelay();

        vm.startPrank(alice);
        vaultFactory.migrate(
            address(vault),
            4,
            abi.encode(
                IVault.MigrateParams({
                    epochDurationSetEpochsDelay: 3,
                    flashFeeRate: 1,
                    flashFeeReceiver: alice,
                    flashLoanEnabled: false,
                    epochDurationSetRoleHolder: alice,
                    flashLoanEnabledSetRoleHolder: alice,
                    flashFeeRateSetRoleHolder: alice,
                    flashFeeReceiverSetRoleHolder: alice
                })
            )
        );
        vm.stopPrank();

        assertEq(Vault(payable(address(vault))).version(), 4);
        assertEq(VaultImplementation(payable(address(vault))).flashFeeRate(), 1);
        assertEq(VaultImplementation(payable(address(vault))).epochDurationSetEpochsDelay(), 3);
    }

    function test_MigrateRevertInsufficientExitWindow() public {
        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
        (address vault_,,) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: 2,
                owner: alice,
                vaultParams: abi.encode(
                    IVaultTokenizedV1.InitParamsTokenized({
                        baseParams: IVaultV1.InitParams({
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
                        }),
                        name: "test",
                        symbol: "TEST"
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

        vault = VaultTokenizedImplementation(payable(vault_));

        vm.startPrank(alice);
        vm.expectRevert(IVault.InsufficientExitWindow.selector);
        vaultFactory.migrate(
            address(vault),
            4,
            abi.encode(
                IVault.MigrateParams({
                    epochDurationSetEpochsDelay: 7 days + 1,
                    flashFeeRate: 1,
                    flashFeeReceiver: alice,
                    flashLoanEnabled: false,
                    epochDurationSetRoleHolder: alice,
                    flashLoanEnabledSetRoleHolder: alice,
                    flashFeeRateSetRoleHolder: alice,
                    flashFeeReceiverSetRoleHolder: alice
                })
            )
        );
        vm.stopPrank();

        vm.startPrank(alice);
        vaultFactory.migrate(
            address(vault),
            4,
            abi.encode(
                IVault.MigrateParams({
                    epochDurationSetEpochsDelay: 7 days + 2,
                    flashFeeRate: 1,
                    flashFeeReceiver: alice,
                    flashLoanEnabled: false,
                    epochDurationSetRoleHolder: alice,
                    flashLoanEnabledSetRoleHolder: alice,
                    flashFeeRateSetRoleHolder: alice,
                    flashFeeReceiverSetRoleHolder: alice
                })
            )
        );
        vm.stopPrank();
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

    // function test_ActiveSharesHint(uint256 amount1, uint48 epochDuration, HintStruct memory hintStruct) public {
    //     amount1 = bound(amount1, 1, 100 * 10 ** 18);
    //     epochDuration = uint48(bound(epochDuration, 1, 7 days));
    //     hintStruct.num = bound(hintStruct.num, 0, 25);
    //     hintStruct.secondsAgo = bound(hintStruct.secondsAgo, 0, 1_720_700_948);

    //     uint256 blockTimestamp = vm.getBlockTimestamp();
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     vault = _getVault(epochDuration);

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

    // function test_ActiveStakeHint(uint256 amount1, uint48 epochDuration, HintStruct memory hintStruct) public {
    //     amount1 = bound(amount1, 1, 100 * 10 ** 18);
    //     epochDuration = uint48(bound(epochDuration, 1, 7 days));
    //     hintStruct.num = bound(hintStruct.num, 0, 25);
    //     hintStruct.secondsAgo = bound(hintStruct.secondsAgo, 0, 1_720_700_948);

    //     uint256 blockTimestamp = vm.getBlockTimestamp();
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     vault = _getVault(epochDuration);

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

    // function test_ActiveSharesOfHint(uint256 amount1, uint48 epochDuration, HintStruct memory hintStruct) public {
    //     amount1 = bound(amount1, 1, 100 * 10 ** 18);
    //     epochDuration = uint48(bound(epochDuration, 1, 7 days));
    //     hintStruct.num = bound(hintStruct.num, 0, 25);
    //     hintStruct.secondsAgo = bound(hintStruct.secondsAgo, 0, 1_720_700_948);

    //     uint256 blockTimestamp = vm.getBlockTimestamp();
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     vault = _getVault(epochDuration);

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
    //     uint48 epochDuration,
    //     HintStruct memory hintStruct,
    //     ActiveBalanceOfHintsUint32 memory activeBalanceOfHintsUint32
    // ) public {
    //     amount1 = bound(amount1, 1, 100 * 10 ** 18);
    //     epochDuration = uint48(bound(epochDuration, 1, 7 days));
    //     hintStruct.num = bound(hintStruct.num, 0, 25);
    //     hintStruct.secondsAgo = bound(hintStruct.secondsAgo, 0, 1_720_700_948);

    //     uint256 blockTimestamp = vm.getBlockTimestamp();
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     vault = _getVault(epochDuration);

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
    //     uint48 epochDuration,
    //     HintStruct memory hintStruct
    // ) public {
    //     amount1 = bound(amount1, 1, 1 * 10 ** 18);
    //     epochDuration = uint48(bound(epochDuration, 1, 7 days));
    //     hintStruct.num = 500;
    //     hintStruct.secondsAgo = bound(hintStruct.secondsAgo, 0, 1_720_700_948);

    //     uint256 blockTimestamp = vm.getBlockTimestamp();
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     vault = _getVault(epochDuration);

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

    function test_Transfer(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        (, uint256 mintedShares) = _deposit(alice, amount1);

        assertEq(vault.balanceOf(alice), mintedShares);
        assertEq(vault.totalSupply(), mintedShares);
        assertEq(VaultImplementation(payable(address(vault))).activeSharesOf(alice), mintedShares);
        assertEq(VaultImplementation(payable(address(vault))).activeShares(), mintedShares);

        if (amount2 > mintedShares) {
            vm.startPrank(alice);

            vm.expectRevert();
            vault.transfer(bob, amount2);

            vm.stopPrank();
        } else {
            vm.startPrank(alice);

            vault.transfer(bob, amount2);

            assertEq(vault.balanceOf(alice), mintedShares - amount2);
            assertEq(vault.totalSupply(), mintedShares);
            assertEq(VaultImplementation(payable(address(vault))).activeSharesOf(alice), mintedShares - amount2);
            assertEq(VaultImplementation(payable(address(vault))).activeShares(), mintedShares);

            assertEq(vault.balanceOf(bob), amount2);
            assertEq(VaultImplementation(payable(address(vault))).activeSharesOf(bob), amount2);

            vm.stopPrank();

            vm.startPrank(bob);
            vault.approve(alice, amount2);
            vm.stopPrank();

            assertEq(vault.allowance(bob, alice), amount2);

            vm.startPrank(alice);
            vault.transferFrom(bob, alice, amount2);
            vm.stopPrank();

            assertEq(vault.balanceOf(alice), mintedShares);
            assertEq(vault.totalSupply(), mintedShares);
            assertEq(VaultImplementation(payable(address(vault))).activeSharesOf(alice), mintedShares);
            assertEq(VaultImplementation(payable(address(vault))).activeShares(), mintedShares);
        }
    }

    function _getVault(
        uint48 epochDuration
    ) internal returns (VaultTokenizedImplementation) {
        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
        (address vault_,,) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: 3,
                owner: alice,
                vaultParams: abi.encode(
                    IVaultTokenized.InitParamsTokenized({
                        baseParams: abi.encode(
                            IVault.InitParams({
                                collateral: address(collateral),
                                burner: address(0xdEaD),
                                epochDuration: epochDuration,
                                depositWhitelist: false,
                                isDepositLimit: false,
                                depositLimit: 0,
                                epochDurationSetEpochsDelay: 3,
                                flashLoanEnabled: false,
                                flashFeeRate: 1,
                                flashFeeReceiver: alice,
                                defaultAdminRoleHolder: alice,
                                depositWhitelistSetRoleHolder: alice,
                                depositorWhitelistRoleHolder: alice,
                                depositorsWhitelisted: new address[](0),
                                isDepositLimitSetRoleHolder: alice,
                                depositLimitSetRoleHolder: alice,
                                epochDurationSetRoleHolder: alice,
                                flashLoanEnabledSetRoleHolder: alice,
                                flashFeeRateSetRoleHolder: alice,
                                flashFeeReceiverSetRoleHolder: alice
                            })
                        ),
                        name: "Test",
                        symbol: "TEST"
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

        return VaultTokenizedImplementation(payable(vault_));
    }

    function _getVaultAndDelegatorAndSlasher(
        uint48 epochDuration
    ) internal returns (VaultTokenizedImplementation, FullRestakeDelegator, Slasher) {
        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](1);
        operatorNetworkLimitSetRoleHolders[0] = alice;
        (address vault_, address delegator_, address slasher_) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: 3,
                owner: alice,
                vaultParams: abi.encode(
                    IVaultTokenized.InitParamsTokenized({
                        baseParams: abi.encode(
                            IVault.InitParams({
                                collateral: address(collateral),
                                burner: address(0xdEaD),
                                epochDuration: epochDuration,
                                depositWhitelist: false,
                                isDepositLimit: false,
                                depositLimit: 0,
                                epochDurationSetEpochsDelay: 3,
                                flashLoanEnabled: false,
                                flashFeeRate: 1,
                                flashFeeReceiver: alice,
                                defaultAdminRoleHolder: alice,
                                depositWhitelistSetRoleHolder: alice,
                                depositorWhitelistRoleHolder: alice,
                                depositorsWhitelisted: new address[](0),
                                isDepositLimitSetRoleHolder: alice,
                                depositLimitSetRoleHolder: alice,
                                epochDurationSetRoleHolder: alice,
                                flashLoanEnabledSetRoleHolder: alice,
                                flashFeeRateSetRoleHolder: alice,
                                flashFeeReceiverSetRoleHolder: alice
                            })
                        ),
                        name: "Test",
                        symbol: "TEST"
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

        return (VaultTokenizedImplementation(payable(vault_)), FullRestakeDelegator(delegator_), Slasher(slasher_));
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
        VaultTokenized(payable(address(vault))).grantRole(vault.DEPOSITOR_WHITELIST_ROLE(), account);
        vm.stopPrank();
    }

    function _grantDepositWhitelistSetRole(address user, address account) internal {
        vm.startPrank(user);
        VaultTokenized(payable(address(vault))).grantRole(vault.DEPOSIT_WHITELIST_SET_ROLE(), account);
        vm.stopPrank();
    }

    function _grantIsDepositLimitSetRole(address user, address account) internal {
        vm.startPrank(user);
        VaultTokenized(payable(address(vault))).grantRole(vault.IS_DEPOSIT_LIMIT_SET_ROLE(), account);
        vm.stopPrank();
    }

    function _grantDepositLimitSetRole(address user, address account) internal {
        vm.startPrank(user);
        VaultTokenized(payable(address(vault))).grantRole(vault.DEPOSIT_LIMIT_SET_ROLE(), account);
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
        amount = VaultImplementation(payable(address(vault))).claim(user, epoch);
        vm.stopPrank();
    }

    function _claimBatch(address user, uint256[] memory epochs) internal returns (uint256 amount) {
        vm.startPrank(user);
        amount = VaultImplementation(payable(address(vault))).claimBatch(user, epochs);
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

    function _setDepositWhitelist(address user, bool status) internal {
        vm.startPrank(user);
        VaultImplementation(payable(address(vault))).setDepositWhitelist(status);
        vm.stopPrank();
    }

    function _setDepositorWhitelistStatus(address user, address depositor, bool status) internal {
        vm.startPrank(user);
        VaultImplementation(payable(address(vault))).setDepositorWhitelistStatus(depositor, status);
        vm.stopPrank();
    }

    function _setIsDepositLimit(address user, bool status) internal {
        vm.startPrank(user);
        VaultImplementation(payable(address(vault))).setIsDepositLimit(status);
        vm.stopPrank();
    }

    function _setDepositLimit(address user, uint256 amount) internal {
        vm.startPrank(user);
        VaultImplementation(payable(address(vault))).setDepositLimit(amount);
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
