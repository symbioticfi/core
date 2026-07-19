// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {ParetoOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/ParetoOracle.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
import {ICoWSwapConverter, ICoWSwapSettlement} from "../../../src/interfaces/adapters/common/ICoWSwapConverter.sol";
import {ILiquidLaneAdapter} from "../../../src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {IAccount} from "../../../src/interfaces/adapters/ll-adapter/IAccount.sol";
import {IAccountRegistry} from "../../../src/interfaces/adapters/ll-adapter/IAccountRegistry.sol";
import {IParetoAccount} from "../../../src/interfaces/adapters/ll-adapter/pareto/IParetoAccount.sol";
import {IParetoCDO} from "../../../src/interfaces/adapters/ll-adapter/pareto/IParetoCDO.sol";
import {IParetoCreditVault} from "../../../src/interfaces/adapters/ll-adapter/pareto/IParetoCreditVault.sol";
import {IParetoWithdrawalQueue} from "../../../src/interfaces/adapters/ll-adapter/pareto/IParetoWithdrawalQueue.sol";
import {IMigratableEntity} from "../../../src/interfaces/common/IMigratableEntity.sol";
import {IGnosisSafe} from "../../utils/interfaces/IGnosisSafe.sol";

// PARETO_ACCOUNT_FACTORY=... PARETO_ACCOUNT=... \
// PARETO_ACCOUNT_REGISTRY=... PARETO_LIQUID_LANE_ADAPTER=... PARETO_VAULT=... \
// forge script script/deploy/adapters/ValidateParetoAccount.s.sol:ValidateParetoAccountScript --rpc-url=RPC

/// @notice Read-only readiness gate for a created Pareto account proxy.
contract ValidateParetoAccountScript is Script {
    address public constant FACTORY_OWNER = 0x5721ce64Ee0D772Ce613b62D411350091C544cD0;
    address public constant COW_SWAP_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant AA_FALCONX = 0xC26A6Fa2C37b38E549a4a1807543801Db684f99C;
    address public constant PARETO_CDO = 0x433D5B175148dA32Ffe1e1A37a939E1b7e79be4d;
    address public constant PARETO_RECEIPT = 0x17E9Ab2992dfecBe779a06A92a6cDB9fE6aEeEf3;
    address public constant PARETO_WITHDRAWAL_QUEUE = 0x5cC24f44cCAa80DD2c079156753fc1e908F495DC;
    address public constant PARETO_KEYRING = 0x6a6A91c7c7C05f9f6B8bC9F6e5eA231e460450e3;
    address public constant AUDITED_CDO_IMPLEMENTATION = 0xDD596250f838Af8862d30E9C78A143356894A18D;
    address public constant AUDITED_RECEIPT_IMPLEMENTATION = 0x62568889198F1bAb603E26dA7b6c1808838fE489;
    address public constant AUDITED_QUEUE_IMPLEMENTATION = 0xC05B41EF0567C7644d1C40feCB951100a30814E4;
    uint256 public constant PARETO_KEYRING_POLICY = 18;
    uint256 public constant MIN_PRICE = 0.9e18;
    uint256 public constant MAX_PRICE = 1.5e18;

    bytes32 internal constant ERC1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function run() public {
        validate(
            vm.envAddress("PARETO_ACCOUNT_FACTORY"),
            vm.envAddress("PARETO_ACCOUNT"),
            vm.envAddress("PARETO_ACCOUNT_REGISTRY"),
            vm.envAddress("PARETO_LIQUID_LANE_ADAPTER"),
            vm.envAddress("PARETO_VAULT")
        );
    }

    function validate(
        address factoryAddress,
        address accountAddress,
        address accountRegistry,
        address liquidLaneAdapter,
        address vault
    ) public view {
        require(block.chainid == 1, "not ethereum mainnet");
        require(_proxyImplementation(PARETO_CDO) == AUDITED_CDO_IMPLEMENTATION, "unaudited cdo implementation");
        require(
            _proxyImplementation(PARETO_RECEIPT) == AUDITED_RECEIPT_IMPLEMENTATION, "unaudited receipt implementation"
        );
        require(
            _proxyImplementation(PARETO_WITHDRAWAL_QUEUE) == AUDITED_QUEUE_IMPLEMENTATION,
            "unaudited queue implementation"
        );
        _validateProtocolTopology();

        uint64 version = IMigratableEntity(accountAddress).version();
        address implementation = MigratablesFactory(factoryAddress).implementation(version);

        require(Ownable(factoryAddress).owner() == FACTORY_OWNER, "invalid factory owner");
        require(MigratablesFactory(factoryAddress).isEntity(accountAddress), "account is not factory entity");
        require(!MigratablesFactory(factoryAddress).blacklisted(version), "account version blacklisted");
        require(IMigratableEntity(implementation).FACTORY() == factoryAddress, "implementation factory mismatch");

        require(
            IAccountRegistry(accountRegistry).accountFactories(USDC, AA_FALCONX) == factoryAddress,
            "account factory not registered"
        );
        require(
            ILiquidLaneAdapter(liquidLaneAdapter).accounts(AA_FALCONX) == accountAddress, "adapter account mismatch"
        );
        require(IAccount(accountAddress).adapter() == liquidLaneAdapter, "account adapter mismatch");
        require(IAccount(accountAddress).vault() == vault, "account vault mismatch");
        require(IERC4626(vault).asset() == USDC, "vault asset mismatch");

        require(IAccount(accountAddress).TOKEN_TO_REDEEM() == AA_FALCONX, "account tranche mismatch");
        require(IParetoAccount(accountAddress).WITHDRAWAL_QUEUE() == PARETO_WITHDRAWAL_QUEUE, "account queue mismatch");
        require(
            ICoWSwapConverter(accountAddress).COW_SWAP_SETTLEMENT() == COW_SWAP_SETTLEMENT, "cow settlement mismatch"
        );
        address cowSwapVaultRelayer = ICoWSwapConverter(accountAddress).COW_SWAP_VAULT_RELAYER();
        require(cowSwapVaultRelayer == ICoWSwapSettlement(COW_SWAP_SETTLEMENT).vaultRelayer(), "cow relayer mismatch");

        address oracleAddress = IAccount(accountAddress).ORACLE();
        require(ParetoOracle(oracleAddress).IDLE_CDO() == PARETO_CDO, "oracle cdo mismatch");
        require(ParetoOracle(oracleAddress).TOKEN_TO_REDEEM() == AA_FALCONX, "oracle tranche mismatch");
        require(
            ParetoOracle(oracleAddress).MIN_PRICE() == MIN_PRICE
                && ParetoOracle(oracleAddress).MAX_PRICE() == MAX_PRICE,
            "oracle bounds mismatch"
        );
        ParetoOracle(oracleAddress).getPrice();

        require(
            IERC20(AA_FALCONX).allowance(accountAddress, PARETO_WITHDRAWAL_QUEUE) == type(uint256).max,
            "queue allowance missing"
        );
        require(IParetoCDO(PARETO_CDO).isWalletAllowed(accountAddress), "account is not keyring allowed");
    }

    function _validateProtocolTopology() private view {
        require(COW_SWAP_SETTLEMENT.code.length > 0, "missing cow settlement");
        require(FACTORY_OWNER.code.length > 0, "missing factory owner");
        require(IGnosisSafe(FACTORY_OWNER).getThreshold() > 1, "unsafe factory owner threshold");
        require(PARETO_KEYRING.code.length > 0, "missing keyring");

        require(IParetoCDO(PARETO_CDO).token() == USDC, "invalid cdo underlying");
        require(IParetoCDO(PARETO_CDO).AATranche() == AA_FALCONX, "invalid cdo tranche");
        require(IParetoCDO(PARETO_CDO).strategy() == PARETO_RECEIPT, "invalid cdo strategy");
        require(IParetoCDO(PARETO_CDO).strategyToken() == PARETO_RECEIPT, "invalid cdo strategy token");
        require(IParetoCDO(PARETO_CDO).oneToken() == 1e6, "invalid cdo underlying unit");
        require(IParetoCDO(PARETO_CDO).ONE_TRANCHE_TOKEN() == 1e18, "invalid cdo tranche unit");
        require(IERC20Metadata(USDC).decimals() == 6, "invalid underlying decimals");
        require(IERC20Metadata(AA_FALCONX).decimals() == 18, "invalid tranche decimals");
        require(IERC20Metadata(PARETO_RECEIPT).decimals() == 6, "invalid receipt decimals");
        require(IParetoCreditVault(PARETO_RECEIPT).idleCDO() == PARETO_CDO, "invalid receipt cdo");
        require(IParetoCreditVault(PARETO_RECEIPT).token() == USDC, "invalid receipt underlying");
        require(IParetoWithdrawalQueue(PARETO_WITHDRAWAL_QUEUE).idleCDOEpoch() == PARETO_CDO, "invalid queue cdo");
        require(IParetoWithdrawalQueue(PARETO_WITHDRAWAL_QUEUE).strategy() == PARETO_RECEIPT, "invalid queue strategy");
        require(IParetoWithdrawalQueue(PARETO_WITHDRAWAL_QUEUE).tranche() == AA_FALCONX, "invalid queue tranche");
        require(IParetoWithdrawalQueue(PARETO_WITHDRAWAL_QUEUE).underlying() == USDC, "invalid queue underlying");
        require(IParetoCDO(PARETO_CDO).keyring() == PARETO_KEYRING, "invalid keyring");
        require(IParetoCDO(PARETO_CDO).keyringPolicyId() == PARETO_KEYRING_POLICY, "invalid keyring policy");
    }

    function _proxyImplementation(address proxy) private view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967_IMPLEMENTATION_SLOT))));
    }
}
