// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SymbioticCounter} from "../../test/integration/SymbioticCounter.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Script} from "forge-std/Script.sol";
import {Vm, VmSafe} from "forge-std/Vm.sol";

contract SymbioticInit is Script, SymbioticCounter {
    using Math for uint256;
    using SafeERC20 for IERC20;

    // General config

    uint256 public SYMBIOTIC_SEED;

    function run(
        uint256 seed
    ) public virtual {
        SYMBIOTIC_SEED = seed;
    }

    // ------------------------------------------------------------ GENERAL HELPERS ------------------------------------------------------------ //

    function _random_Symbiotic() internal virtual returns (uint256) {
        return uint256(
            keccak256(abi.encode(SYMBIOTIC_SEED, vm.getBlockTimestamp(), vm.getBlockNumber(), _count_Symbiotic()))
        );
    }

    function _randomWithBounds_Symbiotic(uint256 lower, uint256 upper) internal virtual returns (uint256) {
        return _bound(_random_Symbiotic(), lower, upper);
    }

    function _randomChoice_Symbiotic(
        uint256 coef
    ) internal virtual returns (bool) {
        return _randomWithBounds_Symbiotic(0, coef) == 0;
    }

    function _randomPick_Symbiotic(
        address[] memory array
    ) internal virtual returns (address) {
        return array[_randomWithBounds_Symbiotic(0, array.length - 1)];
    }

    function _randomPick_Symbiotic(
        uint256[] memory array
    ) internal virtual returns (uint256) {
        return array[_randomWithBounds_Symbiotic(0, array.length - 1)];
    }

    function _randomPick_Symbiotic(
        uint64[] memory array
    ) internal virtual returns (uint64) {
        return array[_randomWithBounds_Symbiotic(0, array.length - 1)];
    }

    function _getAccount_Symbiotic() internal virtual returns (Vm.Wallet memory) {
        return vm.createWallet(_random_Symbiotic());
    }

    function _contains_Symbiotic(address[] memory array, address element) internal virtual returns (bool) {
        for (uint256 i; i < array.length; ++i) {
            if (array[i] == element) {
                return true;
            }
        }
        return false;
    }

    function _contains_Symbiotic(Vm.Wallet[] memory array, Vm.Wallet memory element) internal virtual returns (bool) {
        for (uint256 i; i < array.length; ++i) {
            if (array[i].addr == element.addr) {
                return true;
            }
        }
        return false;
    }

    function _createWalletByAddress_Symbiotic(
        address addr
    ) internal virtual returns (Vm.Wallet memory) {
        return VmSafe.Wallet({addr: addr, publicKeyX: 0, publicKeyY: 0, privateKey: 0});
    }

    function _getWalletByAddress_Symbiotic(
        Vm.Wallet[] memory array,
        address element
    ) internal virtual returns (Vm.Wallet memory) {
        for (uint256 i; i < array.length; ++i) {
            if (array[i].addr == element) {
                return array[i];
            }
        }
        revert("Wallet not found");
    }

    function _deal_Symbiotic(address token, address to, uint256 give) public virtual {
        vm.startBroadcast(tx.origin);
        IERC20(token).safeTransfer(to, give);
        vm.stopBroadcast();
    }

    function _deal_Symbiotic(address to, uint256 give) public virtual {
        vm.startBroadcast(tx.origin);
        to.call{value: give}("");
        vm.stopBroadcast();
    }

    function _vmWalletToAddress_Symbiotic(
        Vm.Wallet memory wallet
    ) internal pure virtual returns (address) {
        return wallet.addr;
    }

    function _vmWalletsToAddresses_Symbiotic(
        Vm.Wallet[] memory wallets
    ) internal pure virtual returns (address[] memory result) {
        result = new address[](wallets.length);
        for (uint256 i; i < wallets.length; ++i) {
            result[i] = wallets[i].addr;
        }
    }

    function _normalizeForToken_Symbiotic(uint256 amount, address token) internal virtual returns (uint256) {
        return amount.mulDiv(10 ** ERC20(token).decimals(), 1e18);
    }

    modifier equalLengthsAddressAddress_Symbiotic(address[] memory a, address[] memory b) {
        require(a.length == b.length, "Arrays must have equal lengths");
        _;
    }

    modifier equalLengthsUint96Address_Symbiotic(uint96[] memory a, address[] memory b) {
        require(a.length == b.length, "Arrays must have equal lengths");
        _;
    }

    modifier equalLengthsUint96Uint256_SymbioticCore(uint96[] memory a, uint256[] memory b) {
        require(a.length == b.length, "Arrays must have equal lengths");
        _;
    }
}
