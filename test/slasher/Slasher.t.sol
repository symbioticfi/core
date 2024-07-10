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
import {IBaseSlasher} from "src/interfaces/slasher/IBaseSlasher.sol";
import {ISlasher} from "src/interfaces/slasher/ISlasher.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract SlasherTest is Test {
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

        slasher = _getSlasher(address(vault));

        assertEq(slasher.VAULT_FACTORY(), address(vaultFactory));
        assertEq(slasher.NETWORK_MIDDLEWARE_SERVICE(), address(networkMiddlewareService));
        assertEq(slasher.NETWORK_VAULT_OPT_IN_SERVICE(), address(networkVaultOptInService));
        assertEq(slasher.OPERATOR_VAULT_OPT_IN_SERVICE(), address(operatorVaultOptInService));
        assertEq(slasher.OPERATOR_NETWORK_OPT_IN_SERVICE(), address(operatorNetworkOptInService));
        assertEq(slasher.vault(), address(vault));
        assertEq(slasher.cumulativeSlashAt(alice, alice, 0), 0);
        assertEq(slasher.cumulativeSlash(alice, alice), 0);
        assertEq(slasher.slashAtDuring(alice, alice, 0, 0), 0);
    }

    function test_CreateRevertNotVault(uint48 epochDuration) public {
        epochDuration = uint48(bound(epochDuration, 1, type(uint48).max));

        (vault,) = _getVaultAndDelegator(epochDuration);

        vm.expectRevert(IBaseSlasher.NotVault.selector);
        slasherFactory.create(0, true, abi.encode(address(1), ""));
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

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(
            Math.min(slashAmount1, delegator.stakeAt(network, alice, uint48(blockTimestamp - 1))),
            _slash(alice, network, alice, slashAmount1, uint48(blockTimestamp - 1))
        );

        assertEq(slasher.cumulativeSlashAt(alice, alice, uint48(blockTimestamp - 1)), 0);
        assertEq(
            slasher.cumulativeSlashAt(alice, alice, uint48(blockTimestamp)),
            Math.min(slashAmount1, delegator.stakeAt(network, alice, uint48(blockTimestamp - 1)))
        );
        assertEq(
            slasher.cumulativeSlash(alice, alice),
            Math.min(slashAmount1, delegator.stakeAt(network, alice, uint48(blockTimestamp - 1)))
        );
        assertEq(slasher.slashAtDuring(alice, alice, uint48(blockTimestamp - 1), 0), 0);
        assertEq(
            slasher.slashAtDuring(alice, alice, uint48(blockTimestamp - 1), 1),
            Math.min(slashAmount1, delegator.stakeAt(network, alice, uint48(blockTimestamp - 1)))
        );
        assertEq(slasher.slashAtDuring(alice, alice, uint48(blockTimestamp), 0), 0);
        assertEq(slasher.slashAtDuring(alice, alice, uint48(blockTimestamp), 1), 0);

        assertEq(
            Math.min(slashAmount2, delegator.stakeAt(network, bob, uint48(blockTimestamp - 1))),
            _slash(alice, network, bob, slashAmount2, uint48(blockTimestamp - 1))
        );

        assertEq(slasher.cumulativeSlashAt(alice, bob, uint48(blockTimestamp - 1)), 0);
        assertEq(
            slasher.cumulativeSlashAt(alice, bob, uint48(blockTimestamp)),
            Math.min(slashAmount2, delegator.stakeAt(network, bob, uint48(blockTimestamp - 1)))
        );
        assertEq(
            slasher.cumulativeSlash(alice, bob),
            Math.min(slashAmount2, delegator.stakeAt(network, bob, uint48(blockTimestamp - 1)))
        );
        assertEq(slasher.slashAtDuring(alice, bob, uint48(blockTimestamp - 1), 0), 0);
        assertEq(
            slasher.slashAtDuring(alice, bob, uint48(blockTimestamp - 1), 1),
            Math.min(slashAmount2, delegator.stakeAt(network, bob, uint48(blockTimestamp - 1)))
        );
        assertEq(slasher.slashAtDuring(alice, bob, uint48(blockTimestamp), 0), 0);
        assertEq(slasher.slashAtDuring(alice, bob, uint48(blockTimestamp), 1), 0);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 slashAmountReal3 = Math.min(
            slashAmount3,
            delegator.stakeAt(network, alice, uint48(blockTimestamp - 2))
                - Math.min(slashAmount1, delegator.stakeAt(network, alice, uint48(blockTimestamp - 2)))
        );
        vm.assume(slashAmountReal3 > 0);
        assertEq(slashAmountReal3, _slash(alice, network, alice, slashAmount3, uint48(blockTimestamp - 2)));

        assertEq(slasher.cumulativeSlashAt(alice, alice, uint48(blockTimestamp - 2)), 0);
        assertEq(
            slasher.cumulativeSlashAt(alice, alice, uint48(blockTimestamp - 1)),
            Math.min(slashAmount1, delegator.stakeAt(network, alice, uint48(blockTimestamp - 2)))
        );
        assertEq(
            slasher.cumulativeSlashAt(alice, alice, uint48(blockTimestamp)),
            Math.min(slashAmount1, delegator.stakeAt(network, alice, uint48(blockTimestamp - 2))) + slashAmountReal3
        );
        assertEq(
            slasher.cumulativeSlash(alice, alice),
            Math.min(slashAmount1, delegator.stakeAt(network, alice, uint48(blockTimestamp - 2))) + slashAmountReal3
        );
        assertEq(slasher.slashAtDuring(alice, alice, uint48(blockTimestamp - 2), 0), 0);
        assertEq(
            slasher.slashAtDuring(alice, alice, uint48(blockTimestamp - 2), 1),
            Math.min(slashAmount1, delegator.stakeAt(network, alice, uint48(blockTimestamp - 2)))
        );
        assertEq(
            slasher.slashAtDuring(alice, alice, uint48(blockTimestamp - 2), 2),
            Math.min(slashAmount1, delegator.stakeAt(network, alice, uint48(blockTimestamp - 2))) + slashAmountReal3
        );
        assertEq(slasher.slashAtDuring(alice, alice, uint48(blockTimestamp - 1), 0), 0);
        assertEq(slasher.slashAtDuring(alice, alice, uint48(blockTimestamp - 1), 1), slashAmountReal3);
        assertEq(slasher.slashAtDuring(alice, alice, uint48(blockTimestamp - 1), 2), slashAmountReal3);
        assertEq(slasher.slashAtDuring(alice, alice, uint48(blockTimestamp), 0), 0);
        assertEq(slasher.slashAtDuring(alice, alice, uint48(blockTimestamp), 1), 0);
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

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        address network = alice;
        _registerNetwork(network, alice);
        _setMaxNetworkLimit(network, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(network));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, network, networkLimit);
        _setNetworkLimit(alice, network, networkLimit - 1);

        _setOperatorNetworkLimit(alice, network, alice, operatorNetworkLimit1);

        _setOperatorNetworkLimit(alice, network, alice, operatorNetworkLimit1 - 1);

        vm.assume(slashAmount1 < depositAmount && slashAmount1 < networkLimit);

        _optInNetworkVault(network);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.expectRevert(IBaseSlasher.NotNetworkMiddleware.selector);
        _slash(bob, network, alice, slashAmount1, uint48(blockTimestamp - 1));
    }

    function test_SlashRevertNetworkNotOptedInVault(
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

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        address network = alice;
        _registerNetwork(network, alice);
        _setMaxNetworkLimit(network, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(network));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, network, networkLimit);
        _setNetworkLimit(alice, network, networkLimit - 1);

        _setOperatorNetworkLimit(alice, network, alice, operatorNetworkLimit1);

        _setOperatorNetworkLimit(alice, network, alice, operatorNetworkLimit1 - 1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.assume(slashAmount1 < depositAmount && slashAmount1 < networkLimit);

        vm.expectRevert(IBaseSlasher.NetworkNotOptedInVault.selector);
        _slash(alice, network, alice, slashAmount1, uint48(blockTimestamp - 1));
    }

    function test_SlashRevertOperatorNotOptedInVault(
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

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        address network = alice;
        _registerNetwork(network, alice);
        _setMaxNetworkLimit(network, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorNetwork(alice, address(network));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, network, networkLimit);
        _setNetworkLimit(alice, network, networkLimit - 1);

        _setOperatorNetworkLimit(alice, network, alice, operatorNetworkLimit1);

        _setOperatorNetworkLimit(alice, network, alice, operatorNetworkLimit1 - 1);

        vm.assume(slashAmount1 < depositAmount && slashAmount1 < networkLimit);

        _optInNetworkVault(network);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.expectRevert(IBaseSlasher.OperatorNotOptedInVault.selector);
        _slash(alice, network, alice, slashAmount1, uint48(blockTimestamp - 1));
    }

    function test_SlashRevertOperatorNotOptedInNetwork(
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

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        address network = alice;
        _registerNetwork(network, alice);
        _setMaxNetworkLimit(network, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorVault(alice);

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, network, networkLimit);
        _setNetworkLimit(alice, network, networkLimit - 1);

        _setOperatorNetworkLimit(alice, network, alice, operatorNetworkLimit1);

        _setOperatorNetworkLimit(alice, network, alice, operatorNetworkLimit1 - 1);

        vm.assume(slashAmount1 < depositAmount && slashAmount1 < networkLimit);

        _optInNetworkVault(network);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.expectRevert(IBaseSlasher.OperatorNotOptedInNetwork.selector);
        _slash(alice, network, alice, slashAmount1, uint48(blockTimestamp - 1));
    }

    function test_SlashRevertInsufficientSlash(
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

        (vault, delegator, slasher) = _getVaultAndDelegatorAndSlasher(epochDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        address network = alice;
        _registerNetwork(network, alice);
        _setMaxNetworkLimit(network, type(uint256).max);

        _registerOperator(alice);

        _optInOperatorVault(alice);

        _optInOperatorNetwork(alice, address(network));

        _deposit(alice, depositAmount);

        _setNetworkLimit(alice, network, networkLimit);
        _setNetworkLimit(alice, network, networkLimit - 1);

        vm.assume(slashAmount1 < depositAmount && slashAmount1 < networkLimit);

        _optInNetworkVault(network);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.expectRevert(ISlasher.InsufficientSlash.selector);
        _slash(alice, network, alice, zeroSlashAmount ? 0 : slashAmount1, uint48(blockTimestamp - 1));
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
