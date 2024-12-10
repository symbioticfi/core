// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console2} from "forge-std/Test.sol";

import {IVaultFactory} from "../src/interfaces/IVaultFactory.sol";
import {IDelegatorFactory} from "../src/interfaces/IDelegatorFactory.sol";
import {ISlasherFactory} from "../src/interfaces/ISlasherFactory.sol";
import {INetworkRegistry} from "../src/interfaces/INetworkRegistry.sol";
import {IOperatorRegistry} from "../src/interfaces/IOperatorRegistry.sol";
import {IMetadataService} from "../src/interfaces/service/IMetadataService.sol";
import {INetworkMiddlewareService} from "../src/interfaces/service/INetworkMiddlewareService.sol";
import {IOptInService} from "../src/interfaces/service/IOptInService.sol";

import {IBaseDelegator} from "../src/interfaces/delegator/IBaseDelegator.sol";
import {IBaseSlasher} from "../src/interfaces/slasher/IBaseSlasher.sol";
import {IVault} from "../src/interfaces/vault/IVault.sol";
import {IVaultTokenized} from "../src/interfaces/vault/IVaultTokenized.sol";
import {INetworkRestakeDelegator} from "../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IFullRestakeDelegator} from "../src/interfaces/delegator/IFullRestakeDelegator.sol";
import {IOperatorSpecificDelegator} from "../src/interfaces/delegator/IOperatorSpecificDelegator.sol";
import {IOperatorNetworkSpecificDelegator} from "../src/interfaces/delegator/IOperatorNetworkSpecificDelegator.sol";
import {ISlasher} from "../src/interfaces/slasher/ISlasher.sol";
import {IVetoSlasher} from "../src/interfaces/slasher/IVetoSlasher.sol";

import {IVaultConfigurator} from "../src/interfaces/IVaultConfigurator.sol";

import {Token} from "./mocks/Token.sol";
import {FeeOnTransferToken} from "./mocks/FeeOnTransferToken.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

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

    IVaultFactory public vaultFactory;
    IDelegatorFactory public delegatorFactory;
    ISlasherFactory public slasherFactory;
    INetworkRegistry public networkRegistry;
    IOperatorRegistry public operatorRegistry;
    IMetadataService public operatorMetadataService;
    IMetadataService public networkMetadataService;
    INetworkMiddlewareService public networkMiddlewareService;
    IOptInService public operatorVaultOptInService;
    IOptInService public operatorNetworkOptInService;

    Token public collateral;
    FeeOnTransferToken public feeOnTransferCollateral;
    IVaultConfigurator public vaultConfigurator;

    IVault public vault1;
    INetworkRestakeDelegator public delegator1;
    ISlasher public slasher1;

    IVault public vault2;
    IFullRestakeDelegator public delegator2;
    ISlasher public slasher2;

    IVault public vault3;
    INetworkRestakeDelegator public delegator3;
    IVetoSlasher public slasher3;

    IVault public vault4;
    IFullRestakeDelegator public delegator4;
    IVetoSlasher public slasher4;

    string public SYMBIOTIC_CORE_PROJECT_ROOT;

    function setUp() public virtual {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        vaultFactory = IVaultFactory(
            deployCode(
                string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/VaultFactory.sol/VaultFactory.json"), abi.encode(owner)
            )
        );
        delegatorFactory = IDelegatorFactory(
            deployCode(
                string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/DelegatorFactory.sol/DelegatorFactory.json"),
                abi.encode(owner)
            )
        );
        slasherFactory = ISlasherFactory(
            deployCode(
                string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/SlasherFactory.sol/SlasherFactory.json"),
                abi.encode(owner)
            )
        );
        networkRegistry = INetworkRegistry(
            deployCode(string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/NetworkRegistry.sol/NetworkRegistry.json"))
        );
        operatorRegistry = IOperatorRegistry(
            deployCode(string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/OperatorRegistry.sol/OperatorRegistry.json"))
        );
        operatorMetadataService = IMetadataService(
            deployCode(
                string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/MetadataService.sol/MetadataService.json"),
                abi.encode(address(operatorRegistry))
            )
        );
        networkMetadataService = IMetadataService(
            deployCode(
                string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/MetadataService.sol/MetadataService.json"),
                abi.encode(address(networkRegistry))
            )
        );
        networkMiddlewareService = INetworkMiddlewareService(
            deployCode(
                string.concat(
                    SYMBIOTIC_CORE_PROJECT_ROOT, "out/NetworkMiddlewareService.sol/NetworkMiddlewareService.json"
                ),
                abi.encode(address(networkRegistry))
            )
        );
        operatorVaultOptInService = IOptInService(
            deployCode(
                string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/OptInService.sol/OptInService.json"),
                abi.encode(address(operatorRegistry), address(vaultFactory), "OperatorVaultOptInService")
            )
        );
        operatorNetworkOptInService = IOptInService(
            deployCode(
                string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/OptInService.sol/OptInService.json"),
                abi.encode(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService")
            )
        );

        address vaultImpl = deployCode(
            string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/Vault.sol/Vault.json"),
            abi.encode(address(delegatorFactory), address(slasherFactory), address(vaultFactory))
        );
        vaultFactory.whitelist(vaultImpl);

        address vaultTokenizedImpl = deployCode(
            string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/VaultTokenized.sol/VaultTokenized.json"),
            abi.encode(address(delegatorFactory), address(slasherFactory), address(vaultFactory))
        );
        vaultFactory.whitelist(vaultTokenizedImpl);

        address networkRestakeDelegatorImpl = deployCode(
            string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/NetworkRestakeDelegator.sol/NetworkRestakeDelegator.json"),
            abi.encode(
                address(networkRegistry),
                address(vaultFactory),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(delegatorFactory),
                delegatorFactory.totalTypes()
            )
        );
        delegatorFactory.whitelist(networkRestakeDelegatorImpl);

        address fullRestakeDelegatorImpl = deployCode(
            string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/FullRestakeDelegator.sol/FullRestakeDelegator.json"),
            abi.encode(
                address(networkRegistry),
                address(vaultFactory),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(delegatorFactory),
                delegatorFactory.totalTypes()
            )
        );
        delegatorFactory.whitelist(fullRestakeDelegatorImpl);

        address operatorSpecificDelegatorImpl = deployCode(
            string.concat(
                SYMBIOTIC_CORE_PROJECT_ROOT, "out/OperatorSpecificDelegator.sol/OperatorSpecificDelegator.json"
            ),
            abi.encode(
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

        address operatorNetworkSpecificDelegatorImpl = deployCode(
            string.concat(
                SYMBIOTIC_CORE_PROJECT_ROOT,
                "out/OperatorNetworkSpecificDelegator.sol/OperatorNetworkSpecificDelegator.json"
            ),
            abi.encode(
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

        address slasherImpl = deployCode(
            string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/Slasher.sol/Slasher.json"),
            abi.encode(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(slasherFactory),
                slasherFactory.totalTypes()
            )
        );
        slasherFactory.whitelist(slasherImpl);

        address vetoSlasherImpl = deployCode(
            string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/VetoSlasher.sol/VetoSlasher.json"),
            abi.encode(
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

        vaultConfigurator = IVaultConfigurator(
            deployCode(
                string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/VaultConfigurator.sol/VaultConfigurator.json"),
                abi.encode(address(vaultFactory), address(delegatorFactory), address(slasherFactory))
            )
        );

        (vault1, delegator1, slasher1) = _getVaultAndNetworkRestakeDelegatorAndSlasher(7 days);

        (vault2, delegator2, slasher2) = _getVaultAndFullRestakeDelegatorAndSlasher(7 days);

        (vault3, delegator3, slasher3) = _getVaultAndNetworkRestakeDelegatorAndVetoSlasher(7 days, 1 days);

        (vault4, delegator4, slasher4) = _getVaultAndFullRestakeDelegatorAndVetoSlasher(7 days, 1 days);
    }

    function _getVault(
        uint48 epochDuration
    ) internal returns (IVault) {
        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
        (address vault_,,) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: 1,
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

        return IVault(vault_);
    }

    function _getVaultAndNetworkRestakeDelegatorAndSlasher(
        uint48 epochDuration
    ) internal returns (IVault, INetworkRestakeDelegator, ISlasher) {
        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
        (address vault_, address delegator_, address slasher_) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: 1,
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

        return (IVault(vault_), INetworkRestakeDelegator(delegator_), ISlasher(slasher_));
    }

    function _getVaultAndFullRestakeDelegatorAndSlasher(
        uint48 epochDuration
    ) internal returns (IVault, IFullRestakeDelegator, ISlasher) {
        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](1);
        operatorNetworkLimitSetRoleHolders[0] = alice;
        (address vault_, address delegator_, address slasher_) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: 1,
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

        return (IVault(vault_), IFullRestakeDelegator(delegator_), ISlasher(slasher_));
    }

    function _getVaultAndNetworkRestakeDelegatorAndVetoSlasher(
        uint48 epochDuration,
        uint48 vetoDuration
    ) internal returns (IVault, INetworkRestakeDelegator, IVetoSlasher) {
        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = alice;
        (address vault_, address delegator_, address slasher_) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: 1,
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

        return (IVault(vault_), INetworkRestakeDelegator(delegator_), IVetoSlasher(slasher_));
    }

    function _getVaultAndFullRestakeDelegatorAndVetoSlasher(
        uint48 epochDuration,
        uint48 vetoDuration
    ) internal returns (IVault, IFullRestakeDelegator, IVetoSlasher) {
        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = alice;
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](1);
        operatorNetworkLimitSetRoleHolders[0] = alice;
        (address vault_, address delegator_, address slasher_) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: 1,
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

        return (IVault(vault_), IFullRestakeDelegator(delegator_), IVetoSlasher(slasher_));
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

    function _grantDepositorWhitelistRole(IVault vault, address user, address account) internal {
        vm.startPrank(user);
        IAccessControl(address(vault)).grantRole(vault.DEPOSITOR_WHITELIST_ROLE(), account);
        vm.stopPrank();
    }

    function _grantDepositWhitelistSetRole(IVault vault, address user, address account) internal {
        vm.startPrank(user);
        IAccessControl(address(vault)).grantRole(vault.DEPOSIT_WHITELIST_SET_ROLE(), account);
        vm.stopPrank();
    }

    function _grantIsDepositLimitSetRole(IVault vault, address user, address account) internal {
        vm.startPrank(user);
        IAccessControl(address(vault)).grantRole(vault.IS_DEPOSIT_LIMIT_SET_ROLE(), account);
        vm.stopPrank();
    }

    function _grantDepositLimitSetRole(IVault vault, address user, address account) internal {
        vm.startPrank(user);
        IAccessControl(address(vault)).grantRole(vault.DEPOSIT_LIMIT_SET_ROLE(), account);
        vm.stopPrank();
    }

    function _deposit(
        IVault vault,
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
        IVault vault,
        address user,
        uint256 amount
    ) internal returns (uint256 burnedShares, uint256 mintedShares) {
        vm.startPrank(user);
        (burnedShares, mintedShares) = vault.withdraw(user, amount);
        vm.stopPrank();
    }

    function _redeem(
        IVault vault,
        address user,
        uint256 shares
    ) internal returns (uint256 withdrawnAssets, uint256 mintedShares) {
        vm.startPrank(user);
        (withdrawnAssets, mintedShares) = vault.redeem(user, shares);
        vm.stopPrank();
    }

    function _claim(IVault vault, address user, uint256 epoch) internal returns (uint256 amount) {
        vm.startPrank(user);
        amount = vault.claim(user, epoch);
        vm.stopPrank();
    }

    function _claimBatch(IVault vault, address user, uint256[] memory epochs) internal returns (uint256 amount) {
        vm.startPrank(user);
        amount = vault.claimBatch(user, epochs);
        vm.stopPrank();
    }

    function _optInOperatorVault(IVault vault, address user) internal {
        vm.startPrank(user);
        operatorVaultOptInService.optIn(address(vault));
        vm.stopPrank();
    }

    function _optOutOperatorVault(IVault vault, address user) internal {
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

    function _setDepositWhitelist(IVault vault, address user, bool status) internal {
        vm.startPrank(user);
        vault.setDepositWhitelist(status);
        vm.stopPrank();
    }

    function _setDepositorWhitelistStatus(IVault vault, address user, address depositor, bool status) internal {
        vm.startPrank(user);
        vault.setDepositorWhitelistStatus(depositor, status);
        vm.stopPrank();
    }

    function _setIsDepositLimit(IVault vault, address user, bool status) internal {
        vm.startPrank(user);
        vault.setIsDepositLimit(status);
        vm.stopPrank();
    }

    function _setDepositLimit(IVault vault, address user, uint256 amount) internal {
        vm.startPrank(user);
        vault.setDepositLimit(amount);
        vm.stopPrank();
    }

    function _setNetworkLimitNetwork(
        INetworkRestakeDelegator delegator,
        address user,
        address network,
        uint256 amount
    ) internal {
        vm.startPrank(user);
        delegator.setNetworkLimit(network.subnetwork(0), amount);
        vm.stopPrank();
    }

    function _setNetworkLimitFull(
        IFullRestakeDelegator delegator,
        address user,
        address network,
        uint256 amount
    ) internal {
        vm.startPrank(user);
        delegator.setNetworkLimit(network.subnetwork(0), amount);
        vm.stopPrank();
    }

    function _setOperatorNetworkShares(
        INetworkRestakeDelegator delegator,
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
        IFullRestakeDelegator delegator,
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
        ISlasher slasher,
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
        IVetoSlasher slasher,
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
        IVetoSlasher slasher,
        address user,
        uint256 slashIndex,
        bytes memory hints
    ) internal returns (uint256 slashAmount) {
        vm.startPrank(user);
        slashAmount = slasher.executeSlash(slashIndex, hints);
        vm.stopPrank();
    }

    function _vetoSlash(IVetoSlasher slasher, address user, uint256 slashIndex, bytes memory hints) internal {
        vm.startPrank(user);
        slasher.vetoSlash(slashIndex, hints);
        vm.stopPrank();
    }

    function _setResolver(
        IVetoSlasher slasher,
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
