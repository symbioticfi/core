// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {DeployAdapterBase} from "./base/DeployAdapterBase.sol";

import {ParetoOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/ParetoOracle.sol";
import {
    AA_FalconX_Account,
    AA_FalconX_AccountFactory
} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/AA_FalconX_Account.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
import {ICoWSwapConverter, ICoWSwapSettlement} from "../../../src/interfaces/adapters/common/ICoWSwapConverter.sol";
import {IAccount} from "../../../src/interfaces/adapters/ll-adapter/IAccount.sol";
import {IParetoOracle} from "../../../src/interfaces/adapters/ll-adapter/oracles/IParetoOracle.sol";
import {IParetoAccount} from "../../../src/interfaces/adapters/ll-adapter/pareto/IParetoAccount.sol";
import {IParetoCDO} from "../../../src/interfaces/adapters/ll-adapter/pareto/IParetoCDO.sol";
import {IParetoCreditVault} from "../../../src/interfaces/adapters/ll-adapter/pareto/IParetoCreditVault.sol";
import {IParetoWithdrawalQueue} from "../../../src/interfaces/adapters/ll-adapter/pareto/IParetoWithdrawalQueue.sol";
import {IMigratableEntity} from "../../../src/interfaces/common/IMigratableEntity.sol";
import {Logs} from "../../utils/Logs.sol";
import {IGnosisSafe} from "../../utils/interfaces/IGnosisSafe.sol";

// forge script script/deploy/adapters/DeployParetoAccount.s.sol:DeployParetoAccountScript --rpc-url=RPC --broadcast

/// @notice Deploys the FalconX Pareto oracle, account factory, and account implementation.
/// @dev Account-registry wiring and Keyring onboarding of each created account proxy are separate governance steps.
contract DeployParetoAccountScript is DeployAdapterBase {
    struct ParetoDeploymentData {
        address oracle;
        address factory;
        address implementation;
    }

    address public constant FACTORY_OWNER = 0x5721ce64Ee0D772Ce613b62D411350091C544cD0;
    address public constant COW_SWAP_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant AA_FALCONX = 0xC26A6Fa2C37b38E549a4a1807543801Db684f99C;
    address public constant PARETO_CDO = 0x433D5B175148dA32Ffe1e1A37a939E1b7e79be4d;
    address public constant PARETO_RECEIPT = 0x17E9Ab2992dfecBe779a06A92a6cDB9fE6aEeEf3;
    address public constant PARETO_WITHDRAWAL_QUEUE = 0x5cC24f44cCAa80DD2c079156753fc1e908F495DC;
    address public constant PARETO_KEYRING = 0x6a6A91c7c7C05f9f6B8bC9F6e5eA231e460450e3;

    // The queue and oracle rely on the pinned CDO, credit-vault, and queue implementations.
    address public constant AUDITED_CDO_IMPLEMENTATION = 0xDD596250f838Af8862d30E9C78A143356894A18D;
    address public constant AUDITED_RECEIPT_IMPLEMENTATION = 0x62568889198F1bAb603E26dA7b6c1808838fE489;
    address public constant AUDITED_QUEUE_IMPLEMENTATION = 0xC05B41EF0567C7644d1C40feCB951100a30814E4;

    uint256 public constant PARETO_KEYRING_POLICY = 18;
    uint256 public constant MIN_PRICE = 0.9e18;
    uint256 public constant MAX_PRICE = 1.5e18;

    bytes32 internal constant ERC1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function run() public returns (ParetoDeploymentData memory data) {
        _validateMainnetConfiguration();

        _startBroadcast();

        data.factory = address(new AA_FalconX_AccountFactory(_scriptOwner()));
        data.oracle = address(new ParetoOracle(MIN_PRICE, MAX_PRICE, AA_FALCONX, PARETO_CDO));
        data.implementation = address(new AA_FalconX_Account(data.oracle, data.factory, COW_SWAP_SETTLEMENT));
        MigratablesFactory(data.factory).whitelist(data.implementation);
        if (FACTORY_OWNER != _scriptOwner()) {
            Ownable(data.factory).transferOwnership(FACTORY_OWNER);
        }

        _stopBroadcast();

        _validateDeployment(data);
        _logDeployment(data);
    }

    function _validateMainnetConfiguration() internal view {
        require(block.chainid == 1, "not ethereum mainnet");
        require(FACTORY_OWNER.code.length > 0, "missing factory owner");
        require(IGnosisSafe(FACTORY_OWNER).getThreshold() > 1, "unsafe factory owner threshold");
        require(COW_SWAP_SETTLEMENT.code.length > 0, "missing cow settlement");
        require(PARETO_KEYRING.code.length > 0, "missing keyring");

        require(_proxyImplementation(PARETO_CDO) == AUDITED_CDO_IMPLEMENTATION, "unaudited cdo implementation");
        require(
            _proxyImplementation(PARETO_RECEIPT) == AUDITED_RECEIPT_IMPLEMENTATION, "unaudited receipt implementation"
        );
        require(
            _proxyImplementation(PARETO_WITHDRAWAL_QUEUE) == AUDITED_QUEUE_IMPLEMENTATION,
            "unaudited queue implementation"
        );

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

    function _validateDeployment(ParetoDeploymentData memory data) internal view {
        assert(Ownable(data.factory).owner() == FACTORY_OWNER);
        assert(MigratablesFactory(data.factory).lastVersion() == 1);
        assert(MigratablesFactory(data.factory).implementation(1) == data.implementation);
        assert(IMigratableEntity(data.implementation).FACTORY() == data.factory);
        assert(IAccount(data.implementation).TOKEN_TO_REDEEM() == AA_FALCONX);
        assert(IParetoAccount(data.implementation).WITHDRAWAL_QUEUE() == PARETO_WITHDRAWAL_QUEUE);
        assert(ICoWSwapConverter(data.implementation).COW_SWAP_SETTLEMENT() == COW_SWAP_SETTLEMENT);
        assert(
            ICoWSwapConverter(data.implementation).COW_SWAP_VAULT_RELAYER()
                == ICoWSwapSettlement(COW_SWAP_SETTLEMENT).vaultRelayer()
        );
        assert(IParetoOracle(data.oracle).IDLE_CDO() == PARETO_CDO);
        assert(IParetoOracle(data.oracle).TOKEN_TO_REDEEM() == AA_FALCONX);
        assert(ParetoOracle(data.oracle).MIN_PRICE() == MIN_PRICE);
        assert(ParetoOracle(data.oracle).MAX_PRICE() == MAX_PRICE);
        uint256 price = ParetoOracle(data.oracle).getPrice();
        assert(price >= MIN_PRICE && price <= MAX_PRICE);
    }

    function _proxyImplementation(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967_IMPLEMENTATION_SLOT))));
    }

    function _logDeployment(ParetoDeploymentData memory data) internal {
        Logs.log(
            string.concat(
                "Deployed Pareto FalconX account",
                "\n    oracle:",
                vm.toString(data.oracle),
                "\n    accountFactory:",
                vm.toString(data.factory),
                "\n    accountImplementation:",
                vm.toString(data.implementation),
                "\nNext: register USDC + AA_FalconX -> factory, create the account proxy, Keyring-onboard that proxy, then run ValidateParetoAccountScript before enabling a limit."
            )
        );
    }
}
