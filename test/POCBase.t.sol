// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {VaultFactory} from "../src/contracts/VaultFactory.sol";
import {DelegatorFactory} from "../src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "../src/contracts/SlasherFactory.sol";
import {NetworkRegistry} from "../src/contracts/NetworkRegistry.sol";
import {OperatorRegistry} from "../src/contracts/OperatorRegistry.sol";
import {MetadataService} from "../src/contracts/service/MetadataService.sol";
import {NetworkMiddlewareService} from "../src/contracts/service/NetworkMiddlewareService.sol";
import {OptInService} from "../src/contracts/service/OptInService.sol";

import {Vault} from "../src/contracts/vault/Vault.sol";
import {NetworkRestakeDelegator} from "../src/contracts/delegator/NetworkRestakeDelegator.sol";
import {FullRestakeDelegator} from "../src/contracts/delegator/FullRestakeDelegator.sol";
import {OperatorSpecificDelegator} from "../src/contracts/delegator/OperatorSpecificDelegator.sol";
import {Slasher} from "../src/contracts/slasher/Slasher.sol";
import {VetoSlasher} from "../src/contracts/slasher/VetoSlasher.sol";

import {IVault} from "../src/interfaces/vault/IVault.sol";

import {Token} from "./mocks/Token.sol";
import {FeeOnTransferToken} from "./mocks/FeeOnTransferToken.sol";
import {VaultConfigurator} from "../src/contracts/VaultConfigurator.sol";
import {IVaultConfigurator} from "../src/interfaces/IVaultConfigurator.sol";
import {INetworkRestakeDelegator} from "../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IFullRestakeDelegator} from "../src/interfaces/delegator/IFullRestakeDelegator.sol";
import {IBaseDelegator} from "../src/interfaces/delegator/IBaseDelegator.sol";
import {IBaseSlasher} from "../src/interfaces/slasher/IBaseSlasher.sol";
import {ISlasher} from "../src/interfaces/slasher/ISlasher.sol";
import {IVetoSlasher} from "../src/interfaces/slasher/IVetoSlasher.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Subnetwork} from "../src/contracts/libraries/Subnetwork.sol";

contract POCBaseTest is Test {
    using Math for uint256;
    using Subnetwork for bytes32;
    using Subnetwork for address;

    address public owner;
    address public alice;
    uint256 public alicePrivateKey;
    address public bob;
    uint256 public bobPrivateKey;

    VaultFactory public vaultFactory;
    DelegatorFactory public delegatorFactory;
    SlasherFactory public slasherFactory;
    NetworkRegistry public networkRegistry;
    OperatorRegistry public operatorRegistry;
    MetadataService public operatorMetadataService;
    MetadataService public networkMetadataService;
    NetworkMiddlewareService public networkMiddlewareService;
    OptInService public operatorVaultOptInService;
    OptInService public operatorNetworkOptInService;

    Token public collateral;
    FeeOnTransferToken public feeOnTransferCollateral;
    VaultConfigurator public vaultConfigurator;

    Vault public vault1;
    NetworkRestakeDelegator public delegator1;
    Slasher public slasher1;

    Vault public vault2;
    FullRestakeDelegator public delegator2;
    Slasher public slasher2;

    Vault public vault3;
    NetworkRestakeDelegator public delegator3;
    VetoSlasher public slasher3;

    Vault public vault4;
    FullRestakeDelegator public delegator4;
    VetoSlasher public slasher4;

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

        (vault1, delegator1, slasher1) = _getVaultAndNetworkRestakeDelegatorAndSlasher(7 days);

        (vault2, delegator2, slasher2) = _getVaultAndFullRestakeDelegatorAndSlasher(7 days);

        (vault3, delegator3, slasher3) = _getVaultAndNetworkRestakeDelegatorAndVetoSlasher(7 days, 1 days);

        (vault4, delegator4, slasher4) = _getVaultAndFullRestakeDelegatorAndVetoSlasher(7 days, 1 days);
    }

    function _getVault(
        uint48 epochDuration
    ) internal returns (Vault) {
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

        return Vault(vault_);
    }

    function _getVaultAndNetworkRestakeDelegatorAndSlasher(
        uint48 epochDuration
    ) internal returns (Vault, NetworkRestakeDelegator, Slasher) {
        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
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
                withSlasher: true,
                slasherIndex: 0,
                slasherParams: abi.encode(ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})}))
            })
        );

        return (Vault(vault_), NetworkRestakeDelegator(delegator_), Slasher(slasher_));
    }

    function _getVaultAndFullRestakeDelegatorAndSlasher(
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

    function _getVaultAndNetworkRestakeDelegatorAndVetoSlasher(
        uint48 epochDuration,
        uint48 vetoDuration
    ) internal returns (Vault, NetworkRestakeDelegator, VetoSlasher) {
        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
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

        return (Vault(vault_), NetworkRestakeDelegator(delegator_), VetoSlasher(slasher_));
    }

    function _getVaultAndFullRestakeDelegatorAndVetoSlasher(
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

    function _grantDepositorWhitelistRole(Vault vault, address user, address account) internal {
        vm.startPrank(user);
        vault.grantRole(vault.DEPOSITOR_WHITELIST_ROLE(), account);
        vm.stopPrank();
    }

    function _grantDepositWhitelistSetRole(Vault vault, address user, address account) internal {
        vm.startPrank(user);
        vault.grantRole(vault.DEPOSIT_WHITELIST_SET_ROLE(), account);
        vm.stopPrank();
    }

    function _grantIsDepositLimitSetRole(Vault vault, address user, address account) internal {
        vm.startPrank(user);
        vault.grantRole(vault.IS_DEPOSIT_LIMIT_SET_ROLE(), account);
        vm.stopPrank();
    }

    function _grantDepositLimitSetRole(Vault vault, address user, address account) internal {
        vm.startPrank(user);
        vault.grantRole(vault.DEPOSIT_LIMIT_SET_ROLE(), account);
        vm.stopPrank();
    }

    function _deposit(
        Vault vault,
        address user,
        uint256 amount
    ) internal returns (uint256 depositedAmount, uint256 mintedShares) {
        collateral.transfer(user, amount);
        vm.startPrank(user);
        collateral.approve(address(vault), amount);
        (depositedAmount, mintedShares) = vault.deposit(user, amount);
        vm.stopPrank();
    }

    function _withdraw(
        Vault vault,
        address user,
        uint256 amount
    ) internal returns (uint256 burnedShares, uint256 mintedShares) {
        vm.startPrank(user);
        (burnedShares, mintedShares) = vault.withdraw(user, amount);
        vm.stopPrank();
    }

    function _redeem(
        Vault vault,
        address user,
        uint256 shares
    ) internal returns (uint256 withdrawnAssets, uint256 mintedShares) {
        vm.startPrank(user);
        (withdrawnAssets, mintedShares) = vault.redeem(user, shares);
        vm.stopPrank();
    }

    function _claim(Vault vault, address user, uint256 epoch) internal returns (uint256 amount) {
        vm.startPrank(user);
        amount = vault.claim(user, epoch);
        vm.stopPrank();
    }

    function _claimBatch(Vault vault, address user, uint256[] memory epochs) internal returns (uint256 amount) {
        vm.startPrank(user);
        amount = vault.claimBatch(user, epochs);
        vm.stopPrank();
    }

    function _optInOperatorVault(Vault vault, address user) internal {
        vm.startPrank(user);
        operatorVaultOptInService.optIn(address(vault));
        vm.stopPrank();
    }

    function _optOutOperatorVault(Vault vault, address user) internal {
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

    function _setDepositWhitelist(Vault vault, address user, bool status) internal {
        vm.startPrank(user);
        vault.setDepositWhitelist(status);
        vm.stopPrank();
    }

    function _setDepositorWhitelistStatus(Vault vault, address user, address depositor, bool status) internal {
        vm.startPrank(user);
        vault.setDepositorWhitelistStatus(depositor, status);
        vm.stopPrank();
    }

    function _setIsDepositLimit(Vault vault, address user, bool status) internal {
        vm.startPrank(user);
        vault.setIsDepositLimit(status);
        vm.stopPrank();
    }

    function _setDepositLimit(Vault vault, address user, uint256 amount) internal {
        vm.startPrank(user);
        vault.setDepositLimit(amount);
        vm.stopPrank();
    }

    function _setNetworkLimitNetwork(
        NetworkRestakeDelegator delegator,
        address user,
        address network,
        uint256 amount
    ) internal {
        vm.startPrank(user);
        delegator.setNetworkLimit(network.subnetwork(0), amount);
        vm.stopPrank();
    }

    function _setNetworkLimitFull(
        FullRestakeDelegator delegator,
        address user,
        address network,
        uint256 amount
    ) internal {
        vm.startPrank(user);
        delegator.setNetworkLimit(network.subnetwork(0), amount);
        vm.stopPrank();
    }

    function _setOperatorNetworkShares(
        NetworkRestakeDelegator delegator,
        address user,
        address network,
        address operator,
        uint256 shares
    ) internal {
        vm.startPrank(user);
        delegator.setOperatorNetworkShares(network.subnetwork(0), operator, shares);
        vm.stopPrank();
    }

    function _setOperatorNetworkLimit(
        FullRestakeDelegator delegator,
        address user,
        address network,
        address operator,
        uint256 amount
    ) internal {
        vm.startPrank(user);
        delegator.setOperatorNetworkLimit(network.subnetwork(0), operator, amount);
        vm.stopPrank();
    }

    function _setMaxNetworkLimit(address delegator, address user, uint96 identifier, uint256 amount) internal {
        vm.startPrank(user);
        IBaseDelegator(delegator).setMaxNetworkLimit(identifier, amount);
        vm.stopPrank();
    }

    function _slash(
        Slasher slasher,
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

    function _requestSlash(
        VetoSlasher slasher,
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
        VetoSlasher slasher,
        address user,
        uint256 slashIndex,
        bytes memory hints
    ) internal returns (uint256 slashAmount) {
        vm.startPrank(user);
        slashAmount = slasher.executeSlash(slashIndex, hints);
        vm.stopPrank();
    }

    function _vetoSlash(VetoSlasher slasher, address user, uint256 slashIndex, bytes memory hints) internal {
        vm.startPrank(user);
        slasher.vetoSlash(slashIndex, hints);
        vm.stopPrank();
    }

    function _setResolver(
        VetoSlasher slasher,
        address user,
        uint96 identifier,
        address resolver,
        bytes memory hints
    ) internal {
        vm.startPrank(user);
        slasher.setResolver(identifier, resolver, hints);
        vm.stopPrank();
    }
}
