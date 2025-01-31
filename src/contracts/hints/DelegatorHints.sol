// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IBaseDelegator} from "../../interfaces/delegator/IBaseDelegator.sol";
import {Hints} from "./Hints.sol";
import {INetworkRestakeDelegator} from "../../interfaces/delegator/INetworkRestakeDelegator.sol";
import {IFullRestakeDelegator} from "../../interfaces/delegator/IFullRestakeDelegator.sol";
import {IOperatorSpecificDelegator} from "../../interfaces/delegator/IOperatorSpecificDelegator.sol";
import {IOperatorNetworkSpecificDelegator} from "../../interfaces/delegator/IOperatorNetworkSpecificDelegator.sol";
import {OptInServiceHints} from "./OptInServiceHints.sol";
import {VaultHints} from "./VaultHints.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";
import {Subnetwork} from "../libraries/Subnetwork.sol";

contract BaseDelegatorHints is Hints {
    using Checkpoints for Checkpoints.Trace256;
    using Subnetwork for bytes32;

    address public immutable OPT_IN_SERVICE_HINTS;
    address public immutable NETWORK_RESTAKE_DELEGATOR_HINTS;
    address public immutable FULL_RESTAKE_DELEGATOR_HINTS;
    address public immutable OPERATOR_SPECIFIC_DELEGATOR_HINTS;
    address public immutable OPERATOR_NETWORK_SPECIFIC_DELEGATOR_HINTS;

    address public vault;
    address public hook;
    mapping(bytes32 subnetwork => uint256 value) public maxNetworkLimit;

    constructor(address optInServiceHints, address vaultHints_) {
        OPT_IN_SERVICE_HINTS = optInServiceHints;
        NETWORK_RESTAKE_DELEGATOR_HINTS = address(new NetworkRestakeDelegatorHints(address(this), vaultHints_));
        FULL_RESTAKE_DELEGATOR_HINTS = address(new FullRestakeDelegatorHints(address(this), vaultHints_));
        OPERATOR_SPECIFIC_DELEGATOR_HINTS = address(new OperatorSpecificDelegatorHints(address(this), vaultHints_));
        OPERATOR_NETWORK_SPECIFIC_DELEGATOR_HINTS =
            address(new OperatorNetworkSpecificDelegatorHints(address(this), vaultHints_));
    }

    function stakeHints(
        address delegator,
        bytes32 subnetwork,
        address operator,
        uint48 timestamp
    ) public view returns (bytes memory hints) {
        if (IBaseDelegator(delegator).TYPE() == 0) {
            hints = NetworkRestakeDelegatorHints(NETWORK_RESTAKE_DELEGATOR_HINTS).stakeHints(
                delegator, subnetwork, operator, timestamp
            );
        } else if (IBaseDelegator(delegator).TYPE() == 1) {
            hints = FullRestakeDelegatorHints(FULL_RESTAKE_DELEGATOR_HINTS).stakeHints(
                delegator, subnetwork, operator, timestamp
            );
        } else if (IBaseDelegator(delegator).TYPE() == 2) {
            hints = OperatorSpecificDelegatorHints(OPERATOR_SPECIFIC_DELEGATOR_HINTS).stakeHints(
                delegator, subnetwork, operator, timestamp
            );
        } else if (IBaseDelegator(delegator).TYPE() == 3) {
            hints = OperatorNetworkSpecificDelegatorHints(OPERATOR_NETWORK_SPECIFIC_DELEGATOR_HINTS).stakeHints(
                delegator, subnetwork, operator, timestamp
            );
        }
    }

    function stakeBaseHints(
        address delegator,
        bytes32 subnetwork,
        address operator,
        uint48 timestamp
    ) external view returns (bytes memory baseHints) {
        bytes memory operatorVaultOptInHint = OptInServiceHints(OPT_IN_SERVICE_HINTS).optInHint(
            IBaseDelegator(delegator).OPERATOR_VAULT_OPT_IN_SERVICE(),
            operator,
            IBaseDelegator(delegator).vault(),
            timestamp
        );
        bytes memory operatorNetworkOptInHint = OptInServiceHints(OPT_IN_SERVICE_HINTS).optInHint(
            IBaseDelegator(delegator).OPERATOR_NETWORK_OPT_IN_SERVICE(), operator, subnetwork.network(), timestamp
        );

        if (operatorVaultOptInHint.length != 0 || operatorNetworkOptInHint.length != 0) {
            baseHints = abi.encode(
                IBaseDelegator.StakeBaseHints({
                    operatorVaultOptInHint: operatorVaultOptInHint,
                    operatorNetworkOptInHint: operatorNetworkOptInHint
                })
            );
        }
    }
}

contract NetworkRestakeDelegatorHints is Hints {
    using Checkpoints for Checkpoints.Trace256;

    address public immutable BASE_DELEGATOR_HINTS;
    address public immutable VAULT_HINTS;

    address public vault;
    address public hook;
    mapping(bytes32 subnetwork => uint256 value) public maxNetworkLimit;

    mapping(bytes32 subnetwork => Checkpoints.Trace256 value) internal _networkLimit;
    mapping(bytes32 subnetwork => Checkpoints.Trace256 shares) internal _totalOperatorNetworkShares;
    mapping(bytes32 subnetwork => mapping(address operator => Checkpoints.Trace256 shares)) internal
        _operatorNetworkShares;

    constructor(address baseDelegatorHints, address vaultHints) {
        BASE_DELEGATOR_HINTS = baseDelegatorHints;
        VAULT_HINTS = vaultHints;
    }

    function networkLimitHintInternal(
        bytes32 subnetwork,
        uint48 timestamp
    ) external view internalFunction returns (bool exists, uint32 hint) {
        (exists,,, hint) = _networkLimit[subnetwork].upperLookupRecentCheckpoint(timestamp);
    }

    function networkLimitHint(
        address delegator,
        bytes32 subnetwork,
        uint48 timestamp
    ) public view returns (bytes memory hint) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                delegator,
                abi.encodeCall(NetworkRestakeDelegatorHints.networkLimitHintInternal, (subnetwork, timestamp))
            ),
            (bool, uint32)
        );

        if (exists) {
            hint = abi.encode(hint_);
        }
    }

    function operatorNetworkSharesHintInternal(
        bytes32 subnetwork,
        address operator,
        uint48 timestamp
    ) external view internalFunction returns (bool exists, uint32 hint) {
        (exists,,, hint) = _operatorNetworkShares[subnetwork][operator].upperLookupRecentCheckpoint(timestamp);
    }

    function operatorNetworkSharesHint(
        address delegator,
        bytes32 subnetwork,
        address operator,
        uint48 timestamp
    ) public view returns (bytes memory hint) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                delegator,
                abi.encodeCall(
                    NetworkRestakeDelegatorHints.operatorNetworkSharesHintInternal, (subnetwork, operator, timestamp)
                )
            ),
            (bool, uint32)
        );

        if (exists) {
            hint = abi.encode(hint_);
        }
    }

    function totalOperatorNetworkSharesHintInternal(
        bytes32 subnetwork,
        uint48 timestamp
    ) external view internalFunction returns (bool exists, uint32 hint) {
        (exists,,, hint) = _totalOperatorNetworkShares[subnetwork].upperLookupRecentCheckpoint(timestamp);
    }

    function totalOperatorNetworkSharesHint(
        address delegator,
        bytes32 subnetwork,
        uint48 timestamp
    ) public view returns (bytes memory hint) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                delegator,
                abi.encodeCall(
                    NetworkRestakeDelegatorHints.totalOperatorNetworkSharesHintInternal, (subnetwork, timestamp)
                )
            ),
            (bool, uint32)
        );

        if (exists) {
            hint = abi.encode(hint_);
        }
    }

    function stakeHints(
        address delegator,
        bytes32 subnetwork,
        address operator,
        uint48 timestamp
    ) external view returns (bytes memory hints) {
        bytes memory baseHints =
            BaseDelegatorHints(BASE_DELEGATOR_HINTS).stakeBaseHints(delegator, subnetwork, operator, timestamp);

        bytes memory activeStakeHint =
            VaultHints(VAULT_HINTS).activeStakeHint(IBaseDelegator(delegator).vault(), timestamp);

        bytes memory networkLimitHint_ = networkLimitHint(delegator, subnetwork, timestamp);
        bytes memory operatorNetworkSharesHint_ = operatorNetworkSharesHint(delegator, subnetwork, operator, timestamp);
        bytes memory totalOperatorNetworkSharesHint_ = totalOperatorNetworkSharesHint(delegator, subnetwork, timestamp);

        if (
            baseHints.length != 0 || activeStakeHint.length != 0 || networkLimitHint_.length != 0
                || operatorNetworkSharesHint_.length != 0 || totalOperatorNetworkSharesHint_.length != 0
        ) {
            hints = abi.encode(
                INetworkRestakeDelegator.StakeHints({
                    baseHints: baseHints,
                    activeStakeHint: activeStakeHint,
                    networkLimitHint: networkLimitHint_,
                    operatorNetworkSharesHint: operatorNetworkSharesHint_,
                    totalOperatorNetworkSharesHint: totalOperatorNetworkSharesHint_
                })
            );
        }
    }
}

contract FullRestakeDelegatorHints is Hints {
    using Checkpoints for Checkpoints.Trace256;

    address public immutable BASE_DELEGATOR_HINTS;
    address public immutable VAULT_HINTS;

    address public vault;
    address public hook;
    mapping(bytes32 subnetwork => uint256 value) public maxNetworkLimit;

    mapping(bytes32 subnetwork => Checkpoints.Trace256 value) internal _networkLimit;
    mapping(bytes32 subnetwork => mapping(address operator => Checkpoints.Trace256 value)) internal
        _operatorNetworkLimit;

    constructor(address baseDelegatorHints, address vaultHints) {
        BASE_DELEGATOR_HINTS = baseDelegatorHints;
        VAULT_HINTS = vaultHints;
    }

    function networkLimitHintInternal(
        bytes32 subnetwork,
        uint48 timestamp
    ) external view internalFunction returns (bool exists, uint32 hint) {
        (exists,,, hint) = _networkLimit[subnetwork].upperLookupRecentCheckpoint(timestamp);
    }

    function networkLimitHint(
        address delegator,
        bytes32 subnetwork,
        uint48 timestamp
    ) public view returns (bytes memory hint) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                delegator, abi.encodeCall(FullRestakeDelegatorHints.networkLimitHintInternal, (subnetwork, timestamp))
            ),
            (bool, uint32)
        );

        if (exists) {
            hint = abi.encode(hint_);
        }
    }

    function operatorNetworkLimitHintInternal(
        bytes32 subnetwork,
        address operator,
        uint48 timestamp
    ) external view internalFunction returns (bool exists, uint32 hint) {
        (exists,,, hint) = _operatorNetworkLimit[subnetwork][operator].upperLookupRecentCheckpoint(timestamp);
    }

    function operatorNetworkLimitHint(
        address delegator,
        bytes32 subnetwork,
        address operator,
        uint48 timestamp
    ) public view returns (bytes memory hint) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                delegator,
                abi.encodeCall(
                    FullRestakeDelegatorHints.operatorNetworkLimitHintInternal, (subnetwork, operator, timestamp)
                )
            ),
            (bool, uint32)
        );

        if (exists) {
            hint = abi.encode(hint_);
        }
    }

    function stakeHints(
        address delegator,
        bytes32 subnetwork,
        address operator,
        uint48 timestamp
    ) external view returns (bytes memory hints) {
        bytes memory baseHints =
            BaseDelegatorHints(BASE_DELEGATOR_HINTS).stakeBaseHints(delegator, subnetwork, operator, timestamp);

        bytes memory activeStakeHint =
            VaultHints(VAULT_HINTS).activeStakeHint(IBaseDelegator(delegator).vault(), timestamp);

        bytes memory networkLimitHint_ = networkLimitHint(delegator, subnetwork, timestamp);
        bytes memory operatorNetworkLimitHint_ = operatorNetworkLimitHint(delegator, subnetwork, operator, timestamp);

        if (
            baseHints.length != 0 || activeStakeHint.length != 0 || networkLimitHint_.length != 0
                || operatorNetworkLimitHint_.length != 0
        ) {
            hints = abi.encode(
                IFullRestakeDelegator.StakeHints({
                    baseHints: baseHints,
                    activeStakeHint: activeStakeHint,
                    networkLimitHint: networkLimitHint_,
                    operatorNetworkLimitHint: operatorNetworkLimitHint_
                })
            );
        }
    }
}

contract OperatorSpecificDelegatorHints is Hints {
    using Checkpoints for Checkpoints.Trace256;

    address public immutable BASE_DELEGATOR_HINTS;
    address public immutable VAULT_HINTS;

    address public vault;
    address public hook;
    mapping(bytes32 subnetwork => uint256 value) public maxNetworkLimit;

    mapping(bytes32 subnetwork => Checkpoints.Trace256 value) internal _networkLimit;
    address public operator;

    constructor(address baseDelegatorHints, address vaultHints) {
        BASE_DELEGATOR_HINTS = baseDelegatorHints;
        VAULT_HINTS = vaultHints;
    }

    function networkLimitHintInternal(
        bytes32 subnetwork,
        uint48 timestamp
    ) external view internalFunction returns (bool exists, uint32 hint) {
        (exists,,, hint) = _networkLimit[subnetwork].upperLookupRecentCheckpoint(timestamp);
    }

    function networkLimitHint(
        address delegator,
        bytes32 subnetwork,
        uint48 timestamp
    ) public view returns (bytes memory hint) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                delegator,
                abi.encodeWithSelector(
                    OperatorSpecificDelegatorHints.networkLimitHintInternal.selector, subnetwork, timestamp
                )
            ),
            (bool, uint32)
        );

        if (exists) {
            hint = abi.encode(hint_);
        }
    }

    function stakeHints(
        address delegator,
        bytes32 subnetwork,
        address operator_,
        uint48 timestamp
    ) external view returns (bytes memory hints) {
        bytes memory baseHints =
            BaseDelegatorHints(BASE_DELEGATOR_HINTS).stakeBaseHints(delegator, subnetwork, operator_, timestamp);

        bytes memory activeStakeHint =
            VaultHints(VAULT_HINTS).activeStakeHint(IBaseDelegator(delegator).vault(), timestamp);

        bytes memory networkLimitHint_ = networkLimitHint(delegator, subnetwork, timestamp);

        if (baseHints.length != 0 || activeStakeHint.length != 0 || networkLimitHint_.length != 0) {
            hints = abi.encode(
                IOperatorSpecificDelegator.StakeHints({
                    baseHints: baseHints,
                    activeStakeHint: activeStakeHint,
                    networkLimitHint: networkLimitHint_
                })
            );
        }
    }
}

contract OperatorNetworkSpecificDelegatorHints is Hints {
    using Checkpoints for Checkpoints.Trace256;

    address public immutable BASE_DELEGATOR_HINTS;
    address public immutable VAULT_HINTS;

    address public vault;
    address public hook;
    mapping(bytes32 subnetwork => uint256 value) public maxNetworkLimit;

    mapping(bytes32 subnetwork => Checkpoints.Trace256 value) internal _maxNetworkLimit;
    address public network;
    address public operator;

    constructor(address baseDelegatorHints, address vaultHints) {
        BASE_DELEGATOR_HINTS = baseDelegatorHints;
        VAULT_HINTS = vaultHints;
    }

    function maxNetworkLimitHintInternal(
        bytes32 subnetwork,
        uint48 timestamp
    ) external view internalFunction returns (bool exists, uint32 hint) {
        (exists,,, hint) = _maxNetworkLimit[subnetwork].upperLookupRecentCheckpoint(timestamp);
    }

    function maxNetworkLimitHint(
        address delegator,
        bytes32 subnetwork,
        uint48 timestamp
    ) public view returns (bytes memory hint) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                delegator,
                abi.encodeWithSelector(
                    OperatorNetworkSpecificDelegatorHints.maxNetworkLimitHintInternal.selector, subnetwork, timestamp
                )
            ),
            (bool, uint32)
        );

        if (exists) {
            hint = abi.encode(hint_);
        }
    }

    function stakeHints(
        address delegator,
        bytes32 subnetwork,
        address operator_,
        uint48 timestamp
    ) external view returns (bytes memory hints) {
        bytes memory baseHints =
            BaseDelegatorHints(BASE_DELEGATOR_HINTS).stakeBaseHints(delegator, subnetwork, operator_, timestamp);

        bytes memory activeStakeHint =
            VaultHints(VAULT_HINTS).activeStakeHint(IBaseDelegator(delegator).vault(), timestamp);

        bytes memory maxNetworkLimitHint_ = maxNetworkLimitHint(delegator, subnetwork, timestamp);

        if (baseHints.length != 0 || activeStakeHint.length != 0 || maxNetworkLimitHint_.length != 0) {
            hints = abi.encode(
                IOperatorNetworkSpecificDelegator.StakeHints({
                    baseHints: baseHints,
                    activeStakeHint: activeStakeHint,
                    maxNetworkLimitHint: maxNetworkLimitHint_
                })
            );
        }
    }
}
