// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SymbioticUtils} from "./SymbioticUtils.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Test} from "forge-std/Test.sol";
import {Vm, VmSafe} from "forge-std/Vm.sol";

contract SymbioticInit is SymbioticUtils, Test {
    using Math for uint256;

    // General config

    uint256 public SYMBIOTIC_INIT_TIMESTAMP = 1_731_324_431;
    uint256 public SYMBIOTIC_INIT_BLOCK = 21_164_139;
    uint256 public SYMBIOTIC_BLOCK_TIME = 12;

    function setUp() public virtual {
        vm.setSeed(SYMBIOTIC_SEED);

        try vm.activeFork() returns (uint256 forkId) {
            vm.rollFork(forkId, SYMBIOTIC_INIT_BLOCK);
        } catch {
            vm.roll(SYMBIOTIC_INIT_BLOCK);
            vm.warp(SYMBIOTIC_INIT_TIMESTAMP);
        }
    }

    function _skipBlocks_Symbiotic(uint256 number) internal virtual {
        vm.roll(vm.getBlockNumber() + number);
        vm.warp(vm.getBlockTimestamp() + number * SYMBIOTIC_BLOCK_TIME);
    }

    function _deal_Symbiotic(address token, address to, uint256 give, bool adjust) public virtual {
        deal(token, to, give, adjust);
    }

    function _supportsDeal_Symbiotic(address token) internal virtual returns (bool) {
        if (token == 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0) {
            return false;
        }

        if (token.code.length == 0) {
            return false;
        }

        address to = address(this);
        (bool success, bytes memory balData) = token.staticcall(abi.encodeWithSelector(0x70a08231, to));
        if (!success) {
            return false;
        }
        uint256 initialBalance = abi.decode(balData, (uint256));
        uint256 give = initialBalance + 111;

        try this._deal_Symbiotic(token, to, give, true) {
            _deal_Symbiotic(token, to, initialBalance, true);
            return true;
        } catch {
            return false;
        }
    }
}
