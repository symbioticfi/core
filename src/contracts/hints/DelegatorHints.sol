// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {BaseDelegator} from "../delegator/BaseDelegator.sol";
import {Hints} from "./Hints.sol";
import {NetworkRestakeDelegator} from "../delegator/NetworkRestakeDelegator.sol";
import {FullRestakeDelegator} from "../delegator/FullRestakeDelegator.sol";
import {OperatorSpecificDelegator} from "../delegator/OperatorSpecificDelegator.sol";
import {OperatorNetworkSpecificDelegator} from "../delegator/OperatorNetworkSpecificDelegator.sol";
import {OptInServiceHints} from "./OptInServiceHints.sol";
import {VaultHints} from "./VaultHints.sol";
import {Vault} from "../vault/Vault.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";
import {Subnetwork} from "../libraries/Subnetwork.sol";

contract BaseDelegatorHints is Hints, BaseDelegator {
    using Checkpoints for Checkpoints.Trace256;
    using Subnetwork for bytes32;

    address public immutable OPT_IN_SERVICE_HINTS;
    address public immutable NETWORK_RESTAKE_DELEGATOR_HINTS;
    address public immutable FULL_RESTAKE_DELEGATOR_HINTS;

    constructor(
        address optInServiceHints,
        address vaultHints_
    ) BaseDelegator(address(0), address(0), address(0), address(0), address(0), 0) {
        OPT_IN_SERVICE_HINTS = optInServiceHints;
        NETWORK_RESTAKE_DELEGATOR_HINTS =
            address(new NetworkRestakeDelegatorHints(address(this), vaultHints_, optInServiceHints));
        FULL_RESTAKE_DELEGATOR_HINTS =
            address(new FullRestakeDelegatorHints(address(this), vaultHints_, optInServiceHints));
    }

    function stakeHints(
        address delegator,
        bytes32 subnetwork,
        address operator,
        uint48 timestamp
    ) public view returns (bytes memory) {
        if (BaseDelegator(delegator).TYPE() == 0) {
            return NetworkRestakeDelegatorHints(NETWORK_RESTAKE_DELEGATOR_HINTS).stakeHints(
                delegator, subnetwork, operator, timestamp
            );
        } else if (BaseDelegator(delegator).TYPE() == 1) {
            return FullRestakeDelegatorHints(FULL_RESTAKE_DELEGATOR_HINTS).stakeHints(
                delegator, subnetwork, operator, timestamp
            );
        }
    }

    function stakeBaseHints(
        address delegator,
        bytes32 subnetwork,
        address operator,
        uint48 timestamp
    ) external view returns (bytes memory) {
        bytes memory operatorVaultOptInHint = OptInServiceHints(OPT_IN_SERVICE_HINTS).optInHint(
            BaseDelegator(delegator).OPERATOR_VAULT_OPT_IN_SERVICE(),
            operator,
            BaseDelegator(delegator).vault(),
            timestamp
        );
        bytes memory operatorNetworkOptInHint = OptInServiceHints(OPT_IN_SERVICE_HINTS).optInHint(
            BaseDelegator(delegator).OPERATOR_NETWORK_OPT_IN_SERVICE(), operator, subnetwork.network(), timestamp
        );

        if (operatorVaultOptInHint.length != 0 || operatorNetworkOptInHint.length != 0) {
            return abi.encode(
                StakeBaseHints({
                    operatorVaultOptInHint: operatorVaultOptInHint,
                    operatorNetworkOptInHint: operatorNetworkOptInHint
                })
            );
        }
    }
}

contract NetworkRestakeDelegatorHints is Hints, NetworkRestakeDelegator {
    using Checkpoints for Checkpoints.Trace256;

    address public immutable BASE_DELEGATOR_HINTS;
    address public immutable VAULT_HINTS;
    address public immutable OPT_IN_SERVICE_HINTS;

    constructor(
        address baseDelegatorHints,
        address vaultHints,
        address optInServiceHints
    ) NetworkRestakeDelegator(address(0), address(0), address(0), address(0), address(0), 0) {
        BASE_DELEGATOR_HINTS = baseDelegatorHints;
        VAULT_HINTS = vaultHints;
        OPT_IN_SERVICE_HINTS = optInServiceHints;
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
    ) public view returns (bytes memory) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                delegator,
                abi.encodeCall(NetworkRestakeDelegatorHints.networkLimitHintInternal, (subnetwork, timestamp))
            ),
            (bool, uint32)
        );

        if (exists) {
            return abi.encode(hint_);
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
    ) public view returns (bytes memory) {
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
            return abi.encode(hint_);
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
    ) public view returns (bytes memory) {
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
            return abi.encode(hint_);
        }
    }

    function stakeHints(
        address delegator,
        bytes32 subnetwork,
        address operator,
        uint48 timestamp
    ) external view returns (bytes memory) {
        bytes memory baseHints =
            BaseDelegatorHints(BASE_DELEGATOR_HINTS).stakeBaseHints(delegator, subnetwork, operator, timestamp);

        bytes memory activeStakeHint =
            VaultHints(VAULT_HINTS).activeStakeHint(BaseDelegator(delegator).vault(), timestamp);

        bytes memory networkLimitHint_ = networkLimitHint(delegator, subnetwork, timestamp);
        bytes memory operatorNetworkSharesHint_ = operatorNetworkSharesHint(delegator, subnetwork, operator, timestamp);
        bytes memory totalOperatorNetworkSharesHint_ = totalOperatorNetworkSharesHint(delegator, subnetwork, timestamp);

        if (
            baseHints.length != 0 || activeStakeHint.length != 0 || networkLimitHint_.length != 0
                || operatorNetworkSharesHint_.length != 0 || totalOperatorNetworkSharesHint_.length != 0
        ) {
            return abi.encode(
                StakeHints({
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

contract FullRestakeDelegatorHints is Hints, FullRestakeDelegator {
    using Checkpoints for Checkpoints.Trace256;

    address public immutable BASE_DELEGATOR_HINTS;
    address public immutable VAULT_HINTS;
    address public immutable OPT_IN_SERVICE_HINTS;

    constructor(
        address baseDelegatorHints,
        address vaultHints,
        address optInServiceHints
    ) FullRestakeDelegator(address(0), address(0), address(0), address(0), address(0), 0) {
        BASE_DELEGATOR_HINTS = baseDelegatorHints;
        VAULT_HINTS = vaultHints;
        OPT_IN_SERVICE_HINTS = optInServiceHints;
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
    ) public view returns (bytes memory) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                delegator, abi.encodeCall(FullRestakeDelegatorHints.networkLimitHintInternal, (subnetwork, timestamp))
            ),
            (bool, uint32)
        );

        if (exists) {
            return abi.encode(hint_);
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
    ) public view returns (bytes memory) {
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
            return abi.encode(hint_);
        }
    }

    function stakeHints(
        address delegator,
        bytes32 subnetwork,
        address operator,
        uint48 timestamp
    ) external view returns (bytes memory) {
        bytes memory baseHints =
            BaseDelegatorHints(BASE_DELEGATOR_HINTS).stakeBaseHints(delegator, subnetwork, operator, timestamp);

        bytes memory activeStakeHint =
            VaultHints(VAULT_HINTS).activeStakeHint(BaseDelegator(delegator).vault(), timestamp);

        bytes memory networkLimitHint_ = networkLimitHint(delegator, subnetwork, timestamp);
        bytes memory operatorNetworkLimitHint_ = operatorNetworkLimitHint(delegator, subnetwork, operator, timestamp);

        if (
            baseHints.length != 0 || activeStakeHint.length != 0 || networkLimitHint_.length != 0
                || operatorNetworkLimitHint_.length != 0
        ) {
            return abi.encode(
                StakeHints({
                    baseHints: baseHints,
                    activeStakeHint: activeStakeHint,
                    networkLimitHint: networkLimitHint_,
                    operatorNetworkLimitHint: operatorNetworkLimitHint_
                })
            );
        }
    }
}

contract OperatorSpecificDelegatorHints is Hints, OperatorSpecificDelegator {
    using Checkpoints for Checkpoints.Trace256;

    address public immutable BASE_DELEGATOR_HINTS;
    address public immutable VAULT_HINTS;
    address public immutable OPT_IN_SERVICE_HINTS;

    constructor(
        address baseDelegatorHints,
        address vaultHints,
        address optInServiceHints
    ) OperatorSpecificDelegator(address(0), address(0), address(0), address(0), address(0), address(0), 0) {
        BASE_DELEGATOR_HINTS = baseDelegatorHints;
        VAULT_HINTS = vaultHints;
        OPT_IN_SERVICE_HINTS = optInServiceHints;
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
    ) public view returns (bytes memory) {
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
            return abi.encode(hint_);
        }
    }

    function stakeHints(
        address delegator,
        bytes32 subnetwork,
        address operator,
        uint48 timestamp
    ) external view returns (bytes memory) {
        bytes memory baseHints =
            BaseDelegatorHints(BASE_DELEGATOR_HINTS).stakeBaseHints(delegator, subnetwork, operator, timestamp);

        bytes memory activeStakeHint =
            VaultHints(VAULT_HINTS).activeStakeHint(BaseDelegator(delegator).vault(), timestamp);

        bytes memory networkLimitHint_ = networkLimitHint(delegator, subnetwork, timestamp);

        if (baseHints.length != 0 || activeStakeHint.length != 0 || networkLimitHint_.length != 0) {
            return abi.encode(
                StakeHints({baseHints: baseHints, activeStakeHint: activeStakeHint, networkLimitHint: networkLimitHint_})
            );
        }
    }
}

contract OperatorNetworkSpecificDelegatorHints is Hints, OperatorNetworkSpecificDelegator {
    using Checkpoints for Checkpoints.Trace256;

    address public immutable BASE_DELEGATOR_HINTS;
    address public immutable VAULT_HINTS;
    address public immutable OPT_IN_SERVICE_HINTS;

    constructor(
        address baseDelegatorHints,
        address vaultHints,
        address optInServiceHints
    ) OperatorNetworkSpecificDelegator(address(0), address(0), address(0), address(0), address(0), address(0), 0) {
        BASE_DELEGATOR_HINTS = baseDelegatorHints;
        VAULT_HINTS = vaultHints;
        OPT_IN_SERVICE_HINTS = optInServiceHints;
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
    ) public view returns (bytes memory) {
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
            return abi.encode(hint_);
        }
    }

    function stakeHints(
        address delegator,
        bytes32 subnetwork,
        address operator,
        uint48 timestamp
    ) external view returns (bytes memory) {
        bytes memory baseHints =
            BaseDelegatorHints(BASE_DELEGATOR_HINTS).stakeBaseHints(delegator, subnetwork, operator, timestamp);

        bytes memory activeStakeHint =
            VaultHints(VAULT_HINTS).activeStakeHint(BaseDelegator(delegator).vault(), timestamp);

        bytes memory maxNetworkLimitHint_ = maxNetworkLimitHint(delegator, subnetwork, timestamp);

        if (baseHints.length != 0 || activeStakeHint.length != 0 || maxNetworkLimitHint_.length != 0) {
            return abi.encode(
                StakeHints({
                    baseHints: baseHints,
                    activeStakeHint: activeStakeHint,
                    maxNetworkLimitHint: maxNetworkLimitHint_
                })
            );
        }
    }
}
