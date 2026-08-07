// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {DeployAccountPauseScript} from "../../../../script/deploy/adapters/pause/DeployAccountPause.s.sol";
import {DeployAdapterPauseScript} from "../../../../script/deploy/adapters/pause/DeployAdapterPause.s.sol";
import {MigratableEntity} from "../../../../src/contracts/common/MigratableEntity.sol";
import {MigratablesFactory} from "../../../../src/contracts/common/MigratablesFactory.sol";
import {IAccount} from "../../../../src/interfaces/adapters/ll-adapter/IAccount.sol";
import {IAdapter} from "../../../../src/interfaces/adapters/IAdapter.sol";
import {ICoWSwapConverter} from "../../../../src/interfaces/adapters/common/ICoWSwapConverter.sol";
import {IConverter} from "../../../../src/interfaces/adapters/common/IConverter.sol";
import {IMigratableEntity} from "../../../../src/interfaces/common/IMigratableEntity.sol";
import {IMulticallable} from "../../../../src/interfaces/common/IMulticallable.sol";
import {IStaticDelegateCallable} from "../../../../src/interfaces/common/IStaticDelegateCallable.sol";

interface IDeployPauseScript {
    function run(address factory) external returns (address implementation);
}

interface INonces {
    function nonces(address owner) external view returns (uint256 nonce);
}

contract RecoveryImplementation is MigratableEntity {
    constructor(address factory) MigratableEntity(factory) {}

    function active() public pure returns (bool) {
        return true;
    }
}

contract PauseDeploymentsTest is Test {
    string internal constant ACCOUNT_SCRIPT =
        "script/deploy/adapters/pause/DeployAccountPause.s.sol:DeployAccountPauseScript";
    string internal constant ADAPTER_SCRIPT =
        "script/deploy/adapters/pause/DeployAdapterPause.s.sol:DeployAdapterPauseScript";

    bytes4 internal constant ACCOUNT_INVALID_FACTORY = bytes4(keccak256("DeployAccountPauseScript__InvalidFactory()"));
    bytes4 internal constant ADAPTER_INVALID_FACTORY = bytes4(keccak256("DeployAdapterPauseScript__InvalidFactory()"));

    function test_AccountPauseDeploymentUsesFactory() public {
        MigratablesFactory factory = new MigratablesFactory(address(this));

        address implementation = _runScript(ACCOUNT_SCRIPT, address(factory));

        assertEq(IMigratableEntity(implementation).FACTORY(), address(factory));
    }

    function test_AdapterPauseDeploymentUsesFactory() public {
        MigratablesFactory factory = new MigratablesFactory(address(this));

        address implementation = _runScript(ADAPTER_SCRIPT, address(factory));

        assertEq(IMigratableEntity(implementation).FACTORY(), address(factory));
    }

    function test_AccountPauseRejectsZeroFactory() public {
        address script = vm.deployCode(ACCOUNT_SCRIPT);

        vm.expectRevert(ACCOUNT_INVALID_FACTORY);
        IDeployPauseScript(script).run(address(0));
    }

    function test_AdapterPauseRejectsZeroFactory() public {
        address script = vm.deployCode(ADAPTER_SCRIPT);

        vm.expectRevert(ADAPTER_INVALID_FACTORY);
        IDeployPauseScript(script).run(address(0));
    }

    function test_AccountPauseFreezesBusinessCallsAndCanRecover() public {
        (MigratablesFactory factory, address entity) = _createEntity();
        address pauseImplementation = _runScript(ACCOUNT_SCRIPT, address(factory));
        factory.whitelist(pauseImplementation);

        factory.migrate(entity, 2, "");

        _assertAccountBusinessCallsRevert(entity);
        _assertArbitrarySelectorReverts(entity);
        _assertCanRecover(factory, entity);
    }

    function test_AdapterPauseFreezesBusinessCallsAndCanRecover() public {
        (MigratablesFactory factory, address entity) = _createEntity();
        address pauseImplementation = _runScript(ADAPTER_SCRIPT, address(factory));
        factory.whitelist(pauseImplementation);

        factory.migrate(entity, 2, "");

        _assertAdapterBusinessCallsRevert(entity);
        _assertArbitrarySelectorReverts(entity);
        _assertCanRecover(factory, entity);
    }

    function _createEntity() internal returns (MigratablesFactory factory, address entity) {
        factory = new MigratablesFactory(address(this));
        factory.whitelist(address(new RecoveryImplementation(address(factory))));
        entity = factory.create(1, address(this), "");
    }

    function _runScript(string memory artifact, address factory) internal returns (address implementation) {
        address script = vm.deployCode(artifact);
        implementation = IDeployPauseScript(script).run(factory);
    }

    function _assertArbitrarySelectorReverts(address entity) internal {
        _assertCallReverts(entity, abi.encodeWithSignature("futureBusinessFunction(uint256)", 1));
    }

    function _assertAccountBusinessCallsRevert(address entity) internal {
        _assertCallReverts(entity, abi.encodeCall(IAccount.TOKEN_TO_REDEEM, ()));
        _assertCallReverts(entity, abi.encodeCall(IAccount.ORACLE, ()));
        _assertCallReverts(entity, abi.encodeCall(IAccount.adapter, ()));
        _assertCallReverts(entity, abi.encodeCall(IAccount.vault, ()));
        _assertCallReverts(entity, abi.encodeCall(IAccount.totalAssets, ()));
        _assertCallReverts(entity, abi.encodeCall(IAccount.sync, ()));

        _assertCallReverts(entity, abi.encodeCall(ICoWSwapConverter.COW_SWAP_SETTLEMENT, ()));
        _assertCallReverts(entity, abi.encodeCall(ICoWSwapConverter.COW_SWAP_VAULT_RELAYER, ()));
        _assertCallReverts(entity, abi.encodeCall(ICoWSwapConverter.executableAt, (0, bytes32(0))));
        _assertCallReverts(entity, abi.encodeCall(ICoWSwapConverter.converters, (0)));
        _assertCallReverts(entity, abi.encodeCall(IConverter.convert, (address(1), 1, address(2), "")));
        _assertCallReverts(entity, abi.encodeCall(ICoWSwapConverter.prepareConvert, (address(1), 1, address(2), "")));

        address[] memory converters = new address[](0);
        _assertCallReverts(entity, abi.encodeCall(ICoWSwapConverter.setConverters, (converters)));
        _assertCallReverts(entity, abi.encodeCall(ICoWSwapConverter.invalidateConvert, ("")));
        _assertCallReverts(entity, abi.encodeCall(ICoWSwapConverter.invalidateConverts, (address(1))));
        _assertCallReverts(entity, abi.encodeCall(INonces.nonces, (address(this))));

        bytes[] memory calls = new bytes[](0);
        _assertCallReverts(entity, abi.encodeCall(IMulticallable.multicall, (calls)));
    }

    function _assertAdapterBusinessCallsRevert(address entity) internal {
        _assertCallReverts(entity, abi.encodeCall(IAdapter.vault, ()));
        _assertCallReverts(entity, abi.encodeCall(IAdapter.allocatable, ()));
        _assertCallReverts(entity, abi.encodeCall(IAdapter.totalAssets, ()));
        _assertCallReverts(entity, abi.encodeCall(IAdapter.freeAssets, ()));
        _assertCallReverts(entity, abi.encodeCall(IAdapter.allocate, (1)));
        _assertCallReverts(entity, abi.encodeCall(IAdapter.deallocate, (1)));
        _assertCallReverts(entity, abi.encodeCall(IAdapter.requestDeallocate, (1)));

        bytes[] memory calls = new bytes[](0);
        _assertCallReverts(entity, abi.encodeCall(IMulticallable.multicall, (calls)));
        _assertCallReverts(entity, abi.encodeCall(IStaticDelegateCallable.staticDelegateCall, (address(1), "")));
    }

    function _assertCallReverts(address entity, bytes memory data) internal {
        (bool success, bytes memory returnData) = entity.call(data);
        assertFalse(success);
        assertEq(returnData.length, 0);
    }

    function _assertCanRecover(MigratablesFactory factory, address entity) internal {
        factory.whitelist(address(new RecoveryImplementation(address(factory))));
        factory.migrate(entity, 3, "");

        assertTrue(RecoveryImplementation(entity).active());
        assertEq(IMigratableEntity(entity).version(), 3);
    }
}
