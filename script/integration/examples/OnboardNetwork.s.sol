// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../SymbioticCoreInit.sol";

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/integration/examples/OnboardNetwork.s.sol:OnboardNetworkScript SEED --sig "run(uint256)" --rpc-url=RPC --chain holesky --private-key PRIVATE_KEY --broadcast

contract OnboardNetworkScript is SymbioticCoreInit {
    using SymbioticSubnetwork for bytes32;
    using SymbioticSubnetwork for address;
    using SafeERC20 for IERC20;

    address[] public tokens_SymbioticCore;

    uint256 public SYMBIOTIC_CORE_NUMBER_OF_VAULTS = 2;
    uint256 public SYMBIOTIC_CORE_NUMBER_OF_OPERATORS = 3;
    uint256 public SYMBIOTIC_CORE_NUMBER_OF_STAKERS = 1;

    function run(
        uint256 seed
    ) public override {
        // ------------------------------------------------------ CONFIG ------------------------------------------------------ //

        SYMBIOTIC_CORE_PROJECT_ROOT = "";

        SYMBIOTIC_CORE_TOKENS_TO_SET_TIMES_1e18 = 0.1 * 1e18;
        SYMBIOTIC_CORE_MIN_TOKENS_TO_DEPOSIT_TIMES_1e18 = 0.001 * 1e18;
        SYMBIOTIC_CORE_MAX_TOKENS_TO_DEPOSIT_TIMES_1e18 = 0.01 * 1e18;

        SYMBIOTIC_CORE_MIN_MAX_NETWORK_LIMIT_TIMES_1e18 = 0.0001 * 1e18;
        SYMBIOTIC_CORE_MAX_MAX_NETWORK_LIMIT_TIMES_1e18 = 0.5 * 1e18;
        SYMBIOTIC_CORE_MIN_NETWORK_LIMIT_TIMES_1e18 = 0.0001 * 1e18;
        SYMBIOTIC_CORE_MAX_NETWORK_LIMIT_TIMES_1e18 = 0.5 * 1e18;
        SYMBIOTIC_CORE_MIN_OPERATOR_NETWORK_LIMIT_TIMES_1e18 = 0.0001 * 1e18;
        SYMBIOTIC_CORE_MAX_OPERATOR_NETWORK_LIMIT_TIMES_1e18 = 0.5 * 1e18;

        SYMBIOTIC_CORE_DELEGATOR_TYPES = [0, 2];

        address NETWORK = tx.origin;
        uint96 IDENTIFIER = 0;
        bytes32 SUBNETWORK = NETWORK.subnetwork(IDENTIFIER);
        address COLLATERAL = SymbioticCoreConstants.wstETH();

        // ------------------------------------------------------ RUN ------------------------------------------------------ //

        super.run(seed);

        if (COLLATERAL == SymbioticCoreConstants.wstETH()) {
            uint256 balanceBefore = IERC20(COLLATERAL).balanceOf(tx.origin);
            uint256 requiredAmount = _normalizeForToken_Symbiotic(SYMBIOTIC_CORE_TOKENS_TO_SET_TIMES_1e18, COLLATERAL)
                * SYMBIOTIC_CORE_NUMBER_OF_STAKERS;
            if (balanceBefore < requiredAmount) {
                address stETH = IwstETH(COLLATERAL).stETH();
                uint256 toSend = IwstETH(COLLATERAL).getStETHByWstETH(requiredAmount - balanceBefore) * 101 / 100;
                vm.startBroadcast(tx.origin);
                stETH.call{value: toSend}("");
                IERC20(stETH).forceApprove(COLLATERAL, toSend);
                IwstETH(COLLATERAL).wrap(toSend);
                vm.stopBroadcast();
            }
        }

        if (!symbioticCore.networkRegistry.isEntity(NETWORK)) {
            _networkRegister_SymbioticCore(NETWORK);
        }

        address[] memory tokens = new address[](1);
        tokens[0] = COLLATERAL;
        Vm.Wallet[] memory stakers = new Vm.Wallet[](SYMBIOTIC_CORE_NUMBER_OF_STAKERS);
        for (uint256 i; i < SYMBIOTIC_CORE_NUMBER_OF_STAKERS; ++i) {
            stakers[i] = _getStaker_SymbioticCore(tokens);
            vm.rememberKey(stakers[i].privateKey);
            _deal_Symbiotic(stakers[i].addr, 0.03 ether);
            console2.log("Staker -", stakers[i].addr, stakers[i].privateKey);
        }

        Vm.Wallet[] memory operators = new Vm.Wallet[](SYMBIOTIC_CORE_NUMBER_OF_OPERATORS);
        for (uint256 i; i < SYMBIOTIC_CORE_NUMBER_OF_OPERATORS; ++i) {
            operators[i] = _getAccount_Symbiotic();
            vm.rememberKey(operators[i].privateKey);
            _deal_Symbiotic(operators[i].addr, 0.03 ether);
            _operatorRegister_SymbioticCore(operators[i].addr);
            console2.log("Operator -", operators[i].addr, operators[i].privateKey);
        }

        address[] memory vaults = new address[](SYMBIOTIC_CORE_NUMBER_OF_VAULTS);
        for (uint256 i; i < SYMBIOTIC_CORE_NUMBER_OF_VAULTS; ++i) {
            vaults[i] = _getVaultRandom_SymbioticCore(_vmWalletsToAddresses_Symbiotic(operators), COLLATERAL);
            console2.log("Vault -", vaults[i]);
        }

        for (uint256 i; i < SYMBIOTIC_CORE_NUMBER_OF_STAKERS; ++i) {
            for (uint256 j; j < SYMBIOTIC_CORE_NUMBER_OF_VAULTS; ++j) {
                _stakerDepositRandom_SymbioticCore(stakers[i].addr, vaults[j]);
            }
        }

        for (uint256 i; i < SYMBIOTIC_CORE_NUMBER_OF_VAULTS; ++i) {
            _networkSetMaxNetworkLimitRandom_SymbioticCore(NETWORK, vaults[i], IDENTIFIER);
            _curatorDelegateNetworkRandom_SymbioticCore(Ownable(vaults[i]).owner(), vaults[i], SUBNETWORK);
        }

        for (uint256 i; i < SYMBIOTIC_CORE_NUMBER_OF_OPERATORS; ++i) {
            _operatorOptInWeak_SymbioticCore(operators[i].addr, NETWORK);
        }

        for (uint256 i; i < SYMBIOTIC_CORE_NUMBER_OF_VAULTS; ++i) {
            for (uint256 j; j < SYMBIOTIC_CORE_NUMBER_OF_OPERATORS; ++j) {
                _operatorOptInWeak_SymbioticCore(operators[j].addr, vaults[i]);
                _curatorDelegateOperatorRandom_SymbioticCore(
                    Ownable(vaults[i]).owner(), vaults[i], SUBNETWORK, operators[j].addr
                );
            }
        }

        // ------------------------------------------------------ VERIFY ------------------------------------------------------ //

        console2.log("Network:", NETWORK);
        console2.log("Identifier:", IDENTIFIER);
        for (uint256 i; i < SYMBIOTIC_CORE_NUMBER_OF_VAULTS; ++i) {
            console2.log("Vault -", vaults[i]);
            for (uint256 j; j < SYMBIOTIC_CORE_NUMBER_OF_OPERATORS; ++j) {
                console2.log("Operator -", operators[j].addr);
                console2.log(
                    "Stake:",
                    ISymbioticBaseDelegator(ISymbioticVault(vaults[i]).delegator()).stake(SUBNETWORK, operators[j].addr)
                );
            }
        }
    }
}

interface IwstETH {
    function stETH() external view returns (address);
    function getStETHByWstETH(
        uint256 _wstETHAmount
    ) external view returns (uint256);
    function wrap(
        uint256 _stETHAmount
    ) external returns (uint256);
}
