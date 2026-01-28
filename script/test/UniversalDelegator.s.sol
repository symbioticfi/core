// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Registry} from "../../src/contracts/common/Registry.sol";
import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";

import {IBaseDelegator} from "../../src/interfaces/delegator/IBaseDelegator.sol";
import {IUniversalDelegator} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IEntity} from "../../src/interfaces/common/IEntity.sol";

contract MutableRegistry is Registry {
    function addEntity(address entity_) external {
        _addEntity(entity_);
    }
}

contract MockOptInService {
    function isOptedInAt(address, address, uint48, bytes calldata) external pure returns (bool) {
        return true;
    }

    function isOptedIn(address, address) external pure returns (bool) {
        return true;
    }
}

contract MockVaultForUniversalDelegator {
    uint256 public activeStake;
    uint48 public epochDurationInit;
    uint48 public epochDuration;
    address public slasher;

    constructor(uint256 activeStake_, uint48 epochDuration_, address slasher_) {
        activeStake = activeStake_;
        epochDurationInit = uint48(block.timestamp);
        epochDuration = epochDuration_;
        slasher = slasher_;
    }

    function activeStakeAt(uint48, bytes memory) external view returns (uint256) {
        return activeStake;
    }

    function setActiveStake(uint256 nextActiveStake) external {
        activeStake = nextActiveStake;
    }
}

// Local UI setup (anvil):
// forge script script/test/UniversalDelegator.s.sol:UniversalDelegatorUiSetup --rpc-url http://127.0.0.1:8545 --private-key <ANVIL_KEY> --broadcast
contract UniversalDelegatorUiSetup is Script {
    function run() external {
        vm.startBroadcast();
        (,, address broadcaster) = vm.readCallers();

        MutableRegistry registry = new MutableRegistry();
        MockOptInService optInService = new MockOptInService();

        MockVaultForUniversalDelegator vault = new MockVaultForUniversalDelegator({
            activeStake_: 1000 ether, epochDuration_: 1 days, slasher_: address(0)
        });
        registry.addEntity(address(vault));

        UniversalDelegator implementation = new UniversalDelegator({
            networkRegistry: address(registry),
            vaultFactory: address(registry),
            operatorVaultOptInService: address(optInService),
            operatorNetworkOptInService: address(optInService),
            delegatorFactory: address(0),
            entityType: 0,
            networkMiddlewareService: address(0)
        });

        IBaseDelegator.BaseParams memory baseParams = IBaseDelegator.BaseParams({
            defaultAdminRoleHolder: broadcaster, hook: address(0), hookSetRoleHolder: broadcaster
        });
        IUniversalDelegator.InitParams memory initParams = IUniversalDelegator.InitParams({
            baseParams: baseParams,
            createSlotRoleHolder: broadcaster,
            setIsSharedRoleHolder: broadcaster,
            setSizeRoleHolder: broadcaster,
            setShareRoleHolder: broadcaster,
            swapSlotsRoleHolder: broadcaster,
            assignNetworkRoleHolder: broadcaster,
            unassignNetworkRoleHolder: broadcaster,
            assignOperatorRoleHolder: broadcaster,
            unassignOperatorRoleHolder: broadcaster,
            withdrawalBuffer: 0
        });

        bytes memory initCalldata =
            abi.encodeCall(IEntity.initialize, (abi.encode(address(vault), abi.encode(initParams))));
        ERC1967Proxy delegatorProxy = new ERC1967Proxy(address(implementation), initCalldata);
        address delegator = address(delegatorProxy);

        vm.stopBroadcast();

        console2.log("Role holder/admin:", broadcaster);
        console2.log("Vault (mock):", address(vault));
        console2.log("Vault activeStake:", vault.activeStake());
        console2.log("Vault epochDuration:", uint256(vault.epochDuration()));
        console2.log("VaultFactory registry (mock):", address(registry));
        console2.log("UniversalDelegator implementation:", address(implementation));
        console2.log("UniversalDelegator instance (proxy):", delegator);
    }
}
