// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Hints} from "./Hints.sol";
import {IVault} from "../../interfaces/vault/IVault.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";

contract VaultHints is Hints {
    using Checkpoints for Checkpoints.Trace256;

    bool public depositWhitelist;
    bool public isDepositLimit;
    address public collateral;
    address public burner;
    uint48 public epochDurationInit;
    uint48 public epochDuration;
    address public delegator;
    bool public isDelegatorInitialized;
    address public slasher;
    bool public isSlasherInitialized;
    uint256 public depositLimit;
    mapping(address account => bool value) public isDepositorWhitelisted;
    mapping(uint256 epoch => uint256 amount) public withdrawals;
    mapping(uint256 epoch => uint256 amount) public withdrawalShares;
    mapping(uint256 epoch => mapping(address account => uint256 amount)) public withdrawalSharesOf;
    mapping(uint256 epoch => mapping(address account => bool value)) public isWithdrawalsClaimed;
    Checkpoints.Trace256 internal _activeShares;
    Checkpoints.Trace256 internal _activeStake;
    mapping(address account => Checkpoints.Trace256 shares) internal _activeSharesOf;

    constructor() {}

    function activeStakeHintInternal(
        uint48 timestamp
    ) external view internalFunction returns (bool exists, uint32 hint) {
        (exists,,, hint) = _activeStake.upperLookupRecentCheckpoint(timestamp);
    }

    function activeStakeHint(address vault, uint48 timestamp) public view returns (bytes memory hint) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(vault, abi.encodeCall(VaultHints.activeStakeHintInternal, (timestamp))),
            (bool, uint32)
        );

        if (exists) {
            hint = abi.encode(hint_);
        }
    }

    function activeSharesHintInternal(
        uint48 timestamp
    ) external view internalFunction returns (bool exists, uint32 hint) {
        (exists,,, hint) = _activeShares.upperLookupRecentCheckpoint(timestamp);
    }

    function activeSharesHint(address vault, uint48 timestamp) public view returns (bytes memory hint) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(vault, abi.encodeCall(VaultHints.activeSharesHintInternal, (timestamp))),
            (bool, uint32)
        );

        if (exists) {
            hint = abi.encode(hint_);
        }
    }

    function activeSharesOfHintInternal(
        address account,
        uint48 timestamp
    ) external view internalFunction returns (bool exists, uint32 hint) {
        (exists,,, hint) = _activeSharesOf[account].upperLookupRecentCheckpoint(timestamp);
    }

    function activeSharesOfHint(
        address vault,
        address account,
        uint48 timestamp
    ) public view returns (bytes memory hint) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(vault, abi.encodeCall(VaultHints.activeSharesOfHintInternal, (account, timestamp))),
            (bool, uint32)
        );

        if (exists) {
            hint = abi.encode(hint_);
        }
    }

    function activeBalanceOfHints(
        address vault,
        address account,
        uint48 timestamp
    ) external view returns (bytes memory hints) {
        bytes memory activeSharesOfHint_ = activeSharesOfHint(vault, account, timestamp);
        bytes memory activeStakeHint_ = activeStakeHint(vault, timestamp);
        bytes memory activeSharesHint_ = activeSharesHint(vault, timestamp);

        if (activeSharesOfHint_.length > 0 || activeStakeHint_.length > 0 || activeSharesHint_.length > 0) {
            hints = abi.encode(
                IVault.ActiveBalanceOfHints({
                    activeSharesOfHint: activeSharesOfHint_,
                    activeStakeHint: activeStakeHint_,
                    activeSharesHint: activeSharesHint_
                })
            );
        }
    }
}
