// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Hints} from "./Hints.sol";
import {BaseDelegator} from "src/contracts/delegator/BaseDelegator.sol";
import {FullRestakeDelegator} from "src/contracts/delegator/FullRestakeDelegator.sol";
import {NetworkRestakeDelegator} from "src/contracts/delegator/NetworkRestakeDelegator.sol";
import {Vault} from "src/contracts/vault/Vault.sol";
import {VaultHints} from "./VaultHints.sol";
import {OptInServiceHints} from "./OptInServiceHints.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";
import {Subnetwork} from "src/contracts/libraries/Subnetwork.sol";

contract BaseDelegatorHints is Hints, BaseDelegator {
    using Checkpoints for Checkpoints.Trace256;
    using Subnetwork for bytes32;

    address public immutable OPT_IN_SERVICE_HINTS;
    address public immutable NETWORK_RESTAKE_DELEGATOR_HINTS;
    address public immutable FULL_RESTAKE_DELEGATOR_HINTS;

    constructor(
        address optInServiceHints,
        address vaultHints_,
        address optInServiceHints_
    ) BaseDelegator(address(0), address(0), address(0), address(0), address(0), 0) {
        OPT_IN_SERVICE_HINTS = optInServiceHints;
        NETWORK_RESTAKE_DELEGATOR_HINTS =
            address(new NetworkRestakeDelegatorHints(address(this), vaultHints_, optInServiceHints_));
        FULL_RESTAKE_DELEGATOR_HINTS =
            address(new FullRestakeDelegatorHints(address(this), vaultHints_, optInServiceHints_));
    }

    function stakeHints(
        address delegator,
        bytes32 subnetwork,
        address operator,
        uint48 timestamp
    ) public returns (bytes memory) {
        if (BaseDelegator(address(this)).TYPE() == 0) {
            return NetworkRestakeDelegatorHints(NETWORK_RESTAKE_DELEGATOR_HINTS).stakeHints(
                delegator, subnetwork, operator, timestamp
            );
        } else if (BaseDelegator(address(this)).TYPE() == 1) {
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
    ) external returns (bytes memory) {
        bytes memory operatorVaultOptInHint = OptInServiceHints(OPT_IN_SERVICE_HINTS).optInHint(
            BaseDelegator(delegator).OPERATOR_VAULT_OPT_IN_SERVICE(),
            operator,
            BaseDelegator(delegator).vault(),
            timestamp
        );
        bytes memory operatorNetworkOptInHint = OptInServiceHints(OPT_IN_SERVICE_HINTS).optInHint(
            BaseDelegator(delegator).OPERATOR_NETWORK_OPT_IN_SERVICE(), operator, subnetwork.network(), timestamp
        );

        bytes memory hints;
        if (operatorVaultOptInHint.length != 0 || operatorNetworkOptInHint.length != 0) {
            hints = abi.encode(
                StakeBaseHints({
                    operatorVaultOptInHint: operatorVaultOptInHint,
                    operatorNetworkOptInHint: operatorNetworkOptInHint
                })
            );
        }

        return hints;
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
    ) external view internalFunction returns (uint32 hint) {
        (,,, hint) = _networkLimit[subnetwork].upperLookupRecentCheckpoint(timestamp);
    }

    function networkLimitHint(address delegator, bytes32 subnetwork, uint48 timestamp) public returns (bytes memory) {
        bytes memory hint = _selfStaticDelegateCall(
            delegator,
            abi.encodeWithSelector(
                NetworkRestakeDelegatorHints.networkLimitHintInternal.selector, subnetwork, timestamp
            )
        );

        return _optimizeHint(
            delegator,
            abi.encodeWithSelector(NetworkRestakeDelegator.networkLimitAt.selector, subnetwork, timestamp, ""),
            abi.encodeWithSelector(NetworkRestakeDelegator.networkLimitAt.selector, subnetwork, timestamp, hint),
            hint
        );
    }

    function operatorNetworkSharesHintInternal(
        bytes32 subnetwork,
        address operator,
        uint48 timestamp
    ) external view internalFunction returns (uint32 hint) {
        (,,, hint) = _operatorNetworkShares[subnetwork][operator].upperLookupRecentCheckpoint(timestamp);
    }

    function operatorNetworkSharesHint(
        address delegator,
        bytes32 subnetwork,
        address operator,
        uint48 timestamp
    ) public returns (bytes memory) {
        bytes memory hint = _selfStaticDelegateCall(
            delegator,
            abi.encodeWithSelector(
                NetworkRestakeDelegatorHints.operatorNetworkSharesHintInternal.selector, subnetwork, operator, timestamp
            )
        );

        return _optimizeHint(
            delegator,
            abi.encodeWithSelector(
                NetworkRestakeDelegator.operatorNetworkSharesAt.selector, subnetwork, operator, timestamp, ""
            ),
            abi.encodeWithSelector(
                NetworkRestakeDelegator.operatorNetworkSharesAt.selector, subnetwork, operator, timestamp, hint
            ),
            hint
        );
    }

    function totalOperatorNetworkSharesHintInternal(
        bytes32 subnetwork,
        uint48 timestamp
    ) external view internalFunction returns (uint32 hint) {
        (,,, hint) = _totalOperatorNetworkShares[subnetwork].upperLookupRecentCheckpoint(timestamp);
    }

    function totalOperatorNetworkSharesHint(
        address delegator,
        bytes32 subnetwork,
        uint48 timestamp
    ) public returns (bytes memory) {
        bytes memory hint = _selfStaticDelegateCall(
            delegator,
            abi.encodeWithSelector(
                NetworkRestakeDelegatorHints.totalOperatorNetworkSharesHintInternal.selector, subnetwork, timestamp
            )
        );

        return _optimizeHint(
            delegator,
            abi.encodeWithSelector(
                NetworkRestakeDelegator.totalOperatorNetworkSharesAt.selector, subnetwork, timestamp, ""
            ),
            abi.encodeWithSelector(
                NetworkRestakeDelegator.totalOperatorNetworkSharesAt.selector, subnetwork, timestamp, hint
            ),
            hint
        );
    }

    function stakeHints(
        address delegator,
        bytes32 subnetwork,
        address operator,
        uint48 timestamp
    ) external returns (bytes memory) {
        bytes memory baseHints =
            BaseDelegatorHints(BASE_DELEGATOR_HINTS).stakeBaseHints(delegator, subnetwork, operator, timestamp);

        bytes memory activeStakeHint = VaultHints(VAULT_HINTS).activeStakeHint(vault, timestamp);

        bytes memory networkLimitHint_ = networkLimitHint(delegator, subnetwork, timestamp);
        bytes memory operatorNetworkSharesHint_ = operatorNetworkSharesHint(delegator, subnetwork, operator, timestamp);
        bytes memory totalOperatorNetworkSharesHint_ = totalOperatorNetworkSharesHint(delegator, subnetwork, timestamp);

        bytes memory hints;
        if (
            baseHints.length != 0 || activeStakeHint.length != 0 || networkLimitHint_.length != 0
                || operatorNetworkSharesHint_.length != 0 || totalOperatorNetworkSharesHint_.length != 0
        ) {
            hints = abi.encode(
                StakeHints({
                    baseHints: baseHints,
                    activeStakeHint: activeStakeHint,
                    networkLimitHint: networkLimitHint_,
                    operatorNetworkSharesHint: operatorNetworkSharesHint_,
                    totalOperatorNetworkSharesHint: totalOperatorNetworkSharesHint_
                })
            );
        }

        return hints;
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
    ) external view internalFunction returns (uint32 hint) {
        (,,, hint) = _networkLimit[subnetwork].upperLookupRecentCheckpoint(timestamp);
    }

    function networkLimitHint(address delegator, bytes32 subnetwork, uint48 timestamp) public returns (bytes memory) {
        bytes memory hint = _selfStaticDelegateCall(
            delegator,
            abi.encodeWithSelector(FullRestakeDelegatorHints.networkLimitHintInternal.selector, subnetwork, timestamp)
        );

        return _optimizeHint(
            delegator,
            abi.encodeWithSelector(FullRestakeDelegator.networkLimitAt.selector, subnetwork, timestamp, ""),
            abi.encodeWithSelector(FullRestakeDelegator.networkLimitAt.selector, subnetwork, timestamp, hint),
            hint
        );
    }

    function operatorNetworkLimitHintInternal(
        bytes32 subnetwork,
        address operator,
        uint48 timestamp
    ) external view internalFunction returns (uint32 hint) {
        (,,, hint) = _operatorNetworkLimit[subnetwork][operator].upperLookupRecentCheckpoint(timestamp);
    }

    function operatorNetworkLimitHint(
        address delegator,
        bytes32 subnetwork,
        address operator,
        uint48 timestamp
    ) public returns (bytes memory) {
        bytes memory hint = _selfStaticDelegateCall(
            delegator,
            abi.encodeWithSelector(
                FullRestakeDelegatorHints.operatorNetworkLimitHintInternal.selector, subnetwork, operator, timestamp
            )
        );

        return _optimizeHint(
            delegator,
            abi.encodeWithSelector(
                FullRestakeDelegator.operatorNetworkLimitAt.selector, subnetwork, operator, timestamp, ""
            ),
            abi.encodeWithSelector(
                FullRestakeDelegator.operatorNetworkLimitAt.selector, subnetwork, operator, timestamp, hint
            ),
            hint
        );
    }

    function stakeHints(
        address delegator,
        bytes32 subnetwork,
        address operator,
        uint48 timestamp
    ) external returns (bytes memory) {
        bytes memory baseHints =
            BaseDelegatorHints(BASE_DELEGATOR_HINTS).stakeBaseHints(delegator, subnetwork, operator, timestamp);

        bytes memory activeStakeHint = VaultHints(VAULT_HINTS).activeStakeHint(vault, timestamp);

        bytes memory networkLimitHint_ = networkLimitHint(delegator, subnetwork, timestamp);
        bytes memory operatorNetworkLimitHint_ = operatorNetworkLimitHint(delegator, subnetwork, operator, timestamp);

        bytes memory hints;
        if (
            baseHints.length != 0 || activeStakeHint.length != 0 || networkLimitHint_.length != 0
                || operatorNetworkLimitHint_.length != 0
        ) {
            hints = abi.encode(
                StakeHints({
                    baseHints: baseHints,
                    activeStakeHint: activeStakeHint,
                    networkLimitHint: networkLimitHint_,
                    operatorNetworkLimitHint: operatorNetworkLimitHint_
                })
            );
        }

        return hints;
    }
}
