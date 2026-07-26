// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {DeployParetoAccountScript} from "../../script/deploy/adapters/DeployParetoAccount.s.sol";
import {ValidateParetoAccountScript} from "../../script/deploy/adapters/ValidateParetoAccount.s.sol";
import {MigratablesFactory} from "../../src/contracts/common/MigratablesFactory.sol";
import {IAccount} from "../../src/interfaces/adapters/ll-adapter/IAccount.sol";
import {IParetoAccount} from "../../src/interfaces/adapters/ll-adapter/pareto/IParetoAccount.sol";
import {IParetoCDO} from "../../src/interfaces/adapters/ll-adapter/pareto/IParetoCDO.sol";
import {IParetoCreditVault} from "../../src/interfaces/adapters/ll-adapter/pareto/IParetoCreditVault.sol";
import {IParetoWithdrawalQueue} from "../../src/interfaces/adapters/ll-adapter/pareto/IParetoWithdrawalQueue.sol";

contract DeployParetoAccountScriptHarness is DeployParetoAccountScript {
    function _startBroadcast() internal override {}

    function _stopBroadcast() internal override {}

    function _scriptOwner() internal view override returns (address) {
        return address(this);
    }
}

contract ParetoReadinessVault {
    address public immutable asset;

    constructor(address asset_) {
        asset = asset_;
    }
}

contract DeployParetoAccountMainnetTest is Test {
    function test_MainnetDeploymentReadinessAndQueueRequest() public {
        string memory rpcUrl = vm.envOr("ETH_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            vm.skip(true);
        }
        vm.createSelectFork(rpcUrl);

        DeployParetoAccountScriptHarness harness = new DeployParetoAccountScriptHarness();
        DeployParetoAccountScript.ParetoDeploymentData memory data = harness.run();
        address adapter = makeAddr("liquidLaneAdapter");
        address accountRegistry = makeAddr("accountRegistry");
        address vault = address(new ParetoReadinessVault(harness.USDC()));
        address account = MigratablesFactory(data.factory).create(1, address(this), abi.encode(vault, adapter));

        vm.mockCall(
            accountRegistry,
            abi.encodeWithSignature("accountFactories(address,address)", harness.USDC(), harness.AA_FALCONX()),
            abi.encode(data.factory)
        );
        vm.mockCall(adapter, abi.encodeWithSignature("accounts(address)", harness.AA_FALCONX()), abi.encode(account));
        vm.mockCall(harness.PARETO_CDO(), abi.encodeCall(IParetoCDO.isWalletAllowed, (account)), abi.encode(true));

        new ValidateParetoAccountScript().validate(data.factory, account, accountRegistry, adapter, vault);

        vm.mockCall(harness.PARETO_CDO(), abi.encodeCall(IParetoCDO.isEpochRunning, ()), abi.encode(true));
        uint256 amount = 1e18;
        deal(harness.AA_FALCONX(), account, amount);
        IAccount(account).sync();

        address queue = IParetoAccount(account).WITHDRAWAL_QUEUE();
        uint256 epoch = IParetoCreditVault(IParetoWithdrawalQueue(queue).strategy()).epochNumber() + 1;
        assertEq(IParetoWithdrawalQueue(queue).userWithdrawalsEpochs(account, epoch), amount);
        assertEq(IParetoAccount(account).queueEpochs(0), epoch);
        assertEq(IERC20(harness.AA_FALCONX()).balanceOf(account), 0);
        assertEq(IAccount(account).totalAssets(), IParetoCDO(harness.PARETO_CDO()).virtualPrice(harness.AA_FALCONX()));
    }
}
