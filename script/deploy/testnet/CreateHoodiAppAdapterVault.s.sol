// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console2} from "forge-std/Script.sol";

import {IAdapterRegistry} from "src/interfaces/IAdapterRegistry.sol";
import {IAppAdapter} from "src/interfaces/adapters/IAppAdapter.sol";
import {IRegistry} from "src/interfaces/common/IRegistry.sol";
import {IMigratablesFactory} from "src/interfaces/common/IMigratablesFactory.sol";
import {IUniversalDelegator, MAX_SHARE} from "src/interfaces/delegator/IUniversalDelegator.sol";
import {INetworkMiddlewareService} from "src/interfaces/service/INetworkMiddlewareService.sol";
import {IVaultV2, VAULT_V2_VERSION} from "src/interfaces/vault/IVaultV2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface INetworkRegistryExercise is IRegistry {
    function registerNetwork() external;
}

interface IOperatorRegistryExercise is IRegistry {
    function registerOperator() external;
}

interface ITestnetERC20Mintable {
    function mint(address to, uint256 amount) external;
}

interface ITestnetBurnerRouterFactory {
    struct NetworkReceiver {
        address network;
        address receiver;
    }

    struct OperatorNetworkReceiver {
        address network;
        address operator;
        address receiver;
    }

    struct InitParams {
        address owner;
        address collateral;
        uint48 delay;
        address globalReceiver;
        NetworkReceiver[] networkReceivers;
        OperatorNetworkReceiver[] operatorNetworkReceivers;
    }

    function create(InitParams calldata params) external returns (address router);
}

contract CreateHoodiAppAdapterVault is Script {
    address internal constant OWNER = 0xc056736be7C05790667CDb678c03eb09F616E157;

    address internal constant VAULT_FACTORY = 0x600Fcd6256DDaB8C649d599fC5b8031bD5F912DA;
    address internal constant ADAPTER_REGISTRY = 0x32b7a1Cbd387aC9aC7f3fb06F889575924a2F988;
    address internal constant APP_ADAPTER_FACTORY = 0xC879456C5Ce99d3a6B81797f40b0BF28143E1640;
    address internal constant BURNER_ROUTER_FACTORY = 0xAD7E40d665f8fcc1eC27b8c9B8Dd8494e86F6B06;
    address internal constant NETWORK_REGISTRY = 0xb2EfA49BB2Aa418ac55bA7DdaA1Cf647F7fb465f;
    address internal constant OPERATOR_REGISTRY = 0xca9cc351C8165d22D0Fd0831C560474b94be5CcD;
    address internal constant NETWORK_MIDDLEWARE_SERVICE = 0xf431e69aa7329CaDBc44AF07504cadA9817975F9;
    address internal constant USDC = 0x9B97F7eDAbd9Ef43cAcE2eaFDD1DE5721aE3Bdd3;

    uint48 internal constant DURATION = 30 seconds;
    uint96 internal constant SUBNETWORK_IDENTIFIER = 3030;
    uint256 internal constant DEPOSIT_AMOUNT = 1000e6;

    function run() external {
        vm.startBroadcast();

        _registerNetworkOperatorAndMiddleware();

        address vault = IMigratablesFactory(VAULT_FACTORY).create(VAULT_V2_VERSION, OWNER, _vaultParams());
        address delegator = IVaultV2(vault).delegator();
        address burner = _createBurner();
        address adapter = _createAppAdapter(vault, burner);

        IAdapterRegistry(ADAPTER_REGISTRY).setWhitelistedStatus(vault, adapter, true);
        IUniversalDelegator(delegator).addAdapter(adapter);
        IUniversalDelegator(delegator).setLimits(adapter, type(uint256).max, MAX_SHARE);

        address[] memory autoAllocateAdapters = new address[](1);
        autoAllocateAdapters[0] = adapter;
        IUniversalDelegator(delegator).setAutoAllocateAdapters(autoAllocateAdapters);

        ITestnetERC20Mintable(USDC).mint(OWNER, DEPOSIT_AMOUNT);
        IERC20(USDC).approve(vault, DEPOSIT_AMOUNT);
        IERC4626(vault).deposit(DEPOSIT_AMOUNT, OWNER);

        vm.stopBroadcast();

        _log(vault, delegator, burner, adapter);
    }

    function _registerNetworkOperatorAndMiddleware() internal {
        if (!IRegistry(NETWORK_REGISTRY).isEntity(OWNER)) {
            INetworkRegistryExercise(NETWORK_REGISTRY).registerNetwork();
        }

        if (!IRegistry(OPERATOR_REGISTRY).isEntity(OWNER)) {
            IOperatorRegistryExercise(OPERATOR_REGISTRY).registerOperator();
        }

        if (INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).middleware(OWNER) != OWNER) {
            INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).setMiddleware(OWNER);
        }
    }

    function _vaultParams() internal pure returns (bytes memory) {
        return abi.encode(
            IVaultV2.InitParams({
                name: "Hoodi 30s AppAdapter Vault",
                symbol: "h30APP",
                asset: USDC,
                depositWhitelist: false,
                depositorToWhitelist: address(0),
                depositLimit: type(uint256).max,
                isDepositLimit: true,
                defaultAdminRoleHolder: OWNER,
                managementFeeRoleHolder: OWNER,
                performanceFeeRoleHolder: OWNER,
                depositLimitSetRoleHolder: OWNER,
                depositorWhitelistRoleHolder: OWNER,
                isDepositLimitSetRoleHolder: OWNER,
                depositWhitelistSetRoleHolder: OWNER,
                delegatorParams: abi.encode(
                    IUniversalDelegator.InitParams({
                        allocateRoleHolder: OWNER,
                        deallocateRoleHolder: OWNER,
                        addAdapterRoleHolder: OWNER,
                        swapAdaptersRoleHolder: OWNER,
                        defaultAdminRoleHolder: OWNER,
                        removeAdapterRoleHolder: OWNER,
                        forceDeallocateRoleHolder: OWNER,
                        setAdapterLimitsRoleHolder: OWNER,
                        setAutoAllocateAdaptersRoleHolder: OWNER
                    })
                )
            })
        );
    }

    function _createBurner() internal returns (address) {
        ITestnetBurnerRouterFactory.NetworkReceiver[] memory networkReceivers =
            new ITestnetBurnerRouterFactory.NetworkReceiver[](0);
        ITestnetBurnerRouterFactory.OperatorNetworkReceiver[] memory operatorNetworkReceivers =
            new ITestnetBurnerRouterFactory.OperatorNetworkReceiver[](0);

        return ITestnetBurnerRouterFactory(BURNER_ROUTER_FACTORY)
            .create(
                ITestnetBurnerRouterFactory.InitParams({
                owner: OWNER,
                collateral: USDC,
                delay: 0,
                globalReceiver: OWNER,
                networkReceivers: networkReceivers,
                operatorNetworkReceivers: operatorNetworkReceivers
            })
            );
    }

    function _createAppAdapter(address vault, address burner) internal returns (address) {
        address[] memory converters = new address[](0);

        return IMigratablesFactory(APP_ADAPTER_FACTORY)
            .create(
                1,
                OWNER,
                abi.encode(
                    vault,
                    abi.encode(
                        IAppAdapter.InitParams({
                        burner: burner,
                        duration: DURATION,
                        operator: OWNER,
                        subnetwork: _subnetwork(OWNER, SUBNETWORK_IDENTIFIER),
                        converters: converters
                    })
                    )
                )
            );
    }

    function _subnetwork(address network, uint96 identifier) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(network)) << 96 | identifier);
    }

    function _log(address vault, address delegator, address burner, address adapter) internal view {
        console2.log("Vault:", vault);
        console2.log("Delegator:", delegator);
        console2.log("Burner:", burner);
        console2.log("AppAdapter:", adapter);
        console2.log("Asset:", IERC4626(vault).asset());
        console2.log("Duration:", IAppAdapter(adapter).duration());
        console2.log("AutoAllocate[0]:", IUniversalDelegator(delegator).autoAllocateAdapters(0));
        console2.log("AbsoluteLimit:", IUniversalDelegator(delegator).absoluteLimitOf(adapter));
        console2.log("ShareLimit:", IUniversalDelegator(delegator).shareLimitOf(adapter));
        console2.log("VaultShares:", IERC20(vault).balanceOf(OWNER));
        console2.log("VaultTotalAssets:", IERC4626(vault).totalAssets());
        console2.log("AdapterTotalAssets:", IAppAdapter(adapter).totalAssets());
        console2.log("AdapterSlashable:", IAppAdapter(adapter).slashable());
    }
}
