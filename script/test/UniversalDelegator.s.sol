// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Registry} from "../../src/contracts/common/Registry.sol";
import {MigratableEntityProxy} from "../../src/contracts/common/MigratableEntityProxy.sol";
import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";
import {VaultV2} from "../../src/contracts/vault/VaultV2.sol";

import {IUniversalDelegator} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IEntity} from "../../src/interfaces/common/IEntity.sol";
import {IMigratableEntity} from "../../src/interfaces/common/IMigratableEntity.sol";
import {IVaultV2, VAULT_V2_VERSION} from "../../src/interfaces/vault/IVaultV2.sol";

import {Token} from "../../test/mocks/Token.sol";

contract MutableRegistry is Registry {
    function addEntity(address entity_) external {
        _addEntity(entity_);
    }
}

// Local UI setup (anvil):
// forge script script/test/UniversalDelegator.s.sol:UniversalDelegatorUiSetup --rpc-url http://127.0.0.1:8545 --private-key <ANVIL_KEY> --broadcast
contract UniversalDelegatorUiSetup is Script {
    function run() external {
        vm.startBroadcast();
        (,, address broadcaster) = vm.readCallers();

        MutableRegistry registry = new MutableRegistry();

        Token collateral = new Token("Symbiotic Collateral");

        VaultV2 vaultImpl = new VaultV2({
            delegatorFactory: address(registry),
            slasherFactory: address(registry),
            vaultFactory: address(registry),
            rewards: address(0),
            pluginRegistry: address(registry)
        });

        IVaultV2.InitParams memory vaultParams = IVaultV2.InitParams({
            name: "Symbiotic Vault",
            symbol: "symVault",
            collateral: address(collateral),
            burner: address(0),
            epochDuration: 1 days,
            depositWhitelist: false,
            depositorToWhitelist: broadcaster,
            isDepositLimit: false,
            depositLimit: 0,
            defaultAdminRoleHolder: broadcaster,
            depositWhitelistSetRoleHolder: broadcaster,
            depositorWhitelistRoleHolder: broadcaster,
            isDepositLimitSetRoleHolder: broadcaster,
            depositLimitSetRoleHolder: broadcaster,
            setPluginLimitRoleHolder: broadcaster,
            allocatePluginRoleHolder: broadcaster
        });

        bytes memory vaultInitCalldata =
            abi.encodeCall(IMigratableEntity.initialize, (VAULT_V2_VERSION, broadcaster, abi.encode(vaultParams)));
        MigratableEntityProxy vaultProxy = new MigratableEntityProxy(address(vaultImpl), vaultInitCalldata);
        VaultV2 vault = VaultV2(address(vaultProxy));

        registry.addEntity(address(vault));

        UniversalDelegator implementation = new UniversalDelegator({
            networkRegistry: address(registry),
            vaultFactory: address(registry),
            delegatorFactory: address(0),
            entityType: 0,
            networkMiddlewareService: address(0)
        });

        IUniversalDelegator.InitParams memory initParams = IUniversalDelegator.InitParams({
            defaultAdminRoleHolder: broadcaster,
            hook: address(0),
            hookSetRoleHolder: broadcaster,
            createSlotRoleHolder: broadcaster,
            setSizeRoleHolder: broadcaster,
            swapSlotsRoleHolder: broadcaster,
            withdrawalBufferSize: type(uint128).max
        });

        bytes memory initCalldata =
            abi.encodeCall(IEntity.initialize, (abi.encode(address(vault), abi.encode(initParams))));
        ERC1967Proxy delegatorProxy = new ERC1967Proxy(address(implementation), initCalldata);
        address delegator = address(delegatorProxy);

        registry.addEntity(delegator);
        vault.setDelegator(delegator);

        uint256 depositAmount = 1000 ether;
        collateral.approve(address(vault), depositAmount);
        vault.deposit(broadcaster, depositAmount);

        vm.stopBroadcast();

        console2.log("Role holder/admin:", broadcaster);
        console2.log("Vault:", address(vault));
        console2.log("Vault epochDuration:", uint256(vault.epochDuration()));
        console2.log("Vault activeStake:", vault.activeStake());
        console2.log("Vault allocatable:", vault.allocatable());
        console2.log("Collateral:", address(collateral));
        console2.log("Deposited:", depositAmount);
        console2.log("VaultFactory registry (mock):", address(registry));
        console2.log("UniversalDelegator implementation:", address(implementation));
        console2.log("UniversalDelegator instance (proxy):", delegator);
    }
}
