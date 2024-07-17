// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Hints} from "./Hints.sol";
import {BaseDelegator} from "src/contracts/delegator/BaseDelegator.sol";
import {FullRestakeDelegator} from "src/contracts/delegator/FullRestakeDelegator.sol";
import {NetworkRestakeDelegator} from "src/contracts/delegator/NetworkRestakeDelegator.sol";
import {Vault} from "src/contracts/vault/Vault.sol";
import {VaultHints} from "./VaultHints.sol";
import {OptInServiceHints} from "./OptInServiceHints.sol";

import {IOptInService} from "src/interfaces/service/IOptInService.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";

contract BaseDelegatorHints is Hints, BaseDelegator {
    using Checkpoints for Checkpoints.Trace256;

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
        address network,
        address operator,
        uint48 timestamp
    ) public returns (bytes memory) {
        if (BaseDelegator(delegator).TYPE() == 0) {
            return NetworkRestakeDelegatorHints(NETWORK_RESTAKE_DELEGATOR_HINTS).stakeHints(
                delegator, network, operator, timestamp
            );
        } else if (BaseDelegator(delegator).TYPE() == 1) {
            return FullRestakeDelegatorHints(FULL_RESTAKE_DELEGATOR_HINTS).stakeHints(
                delegator, network, operator, timestamp
            );
        }
    }

    function _stakeBaseHints(
        address delegator,
        address network,
        address operator,
        uint48 timestamp,
        bytes memory hints
    ) external view returns (bool) {
        StakeBaseHints memory baseHints;
        if (hints.length > 0) {
            baseHints = abi.decode(hints, (StakeBaseHints));
        }

        if (
            !IOptInService(BaseDelegator(delegator).OPERATOR_VAULT_OPT_IN_SERVICE()).isOptedInAt(
                operator, BaseDelegator(delegator).vault(), timestamp, baseHints.operatorVaultOptInHint
            )
                || !IOptInService(BaseDelegator(delegator).OPERATOR_NETWORK_OPT_IN_SERVICE()).isOptedInAt(
                    operator, network, timestamp, baseHints.operatorNetworkOptInHint
                )
        ) {
            return true;
        }
    }

    function stakeBaseHints(
        address delegator,
        address network,
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
            BaseDelegator(delegator).OPERATOR_NETWORK_OPT_IN_SERVICE(), operator, network, timestamp
        );

        if (operatorVaultOptInHint.length != 0 || operatorNetworkOptInHint.length != 0) {
            uint256 N = 3;
            bytes[] memory hints = new bytes[](N);
            hints[0] = new bytes(0);
            hints[1] = abi.encode(
                StakeBaseHints({operatorVaultOptInHint: operatorVaultOptInHint, operatorNetworkOptInHint: new bytes(0)})
            );
            hints[2] = abi.encode(
                StakeBaseHints({
                    operatorVaultOptInHint: operatorVaultOptInHint,
                    operatorNetworkOptInHint: operatorNetworkOptInHint
                })
            );

            bytes[] memory datas = new bytes[](N);
            for (uint256 i; i < N; ++i) {
                datas[i] = abi.encodeWithSelector(
                    BaseDelegatorHints._stakeBaseHints.selector, delegator, network, operator, timestamp, hints[i]
                );
            }

            return _optimizeHint(address(this), datas, hints);
        }
    }

    function _onSlash(
        address delegator,
        address network,
        address operator,
        uint256 amount,
        uint48 captureTimestamp,
        bytes memory hints
    ) external view returns (bool) {
        OnSlashHints memory onSlashHints_;
        if (hints.length > 0) {
            onSlashHints_ = abi.decode(hints, (OnSlashHints));
        }

        if (amount > BaseDelegator(delegator).stakeAt(network, operator, captureTimestamp, onSlashHints_.stakeHints)) {
            return true;
        }
    }

    function onSlashHints(
        address delegator,
        address network,
        address operator,
        uint256 amount,
        uint48 captureTimestamp
    ) external returns (bytes memory) {
        bytes memory stakeHints_ = stakeHints(delegator, network, operator, captureTimestamp);
        bytes memory hints_;
        if (stakeHints_.length != 0) {
            hints_ = abi.encode(OnSlashHints({stakeHints: stakeHints_}));
        }

        if (hints_.length > 0) {
            uint256 N = 2;
            bytes[] memory hints = new bytes[](N);
            hints[0] = new bytes(0);
            hints[1] = hints_;

            bytes[] memory datas = new bytes[](N);
            for (uint256 i; i < N; ++i) {
                datas[i] = abi.encodeWithSelector(
                    BaseDelegatorHints._onSlash.selector,
                    delegator,
                    network,
                    operator,
                    amount,
                    captureTimestamp,
                    hints[i]
                );
            }

            return _optimizeHint(address(this), datas, hints);
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
        address network,
        uint48 timestamp
    ) external view internalFunction returns (bool exists, uint32 hint) {
        (exists,,, hint) = _networkLimit[network].upperLookupRecentCheckpoint(timestamp);
    }

    function networkLimitHint(address delegator, address network, uint48 timestamp) public returns (bytes memory) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                delegator,
                abi.encodeWithSelector(
                    NetworkRestakeDelegatorHints.networkLimitHintInternal.selector, network, timestamp
                )
            ),
            (bool, uint32)
        );
        bytes memory hint;
        if (exists) {
            hint = abi.encode(hint_);
        }

        uint256 N = 2;
        bytes[] memory hints = new bytes[](N);
        hints[0] = new bytes(0);
        hints[1] = hint;
        bytes[] memory datas = new bytes[](N);
        for (uint256 i; i < N; ++i) {
            datas[i] =
                abi.encodeWithSelector(NetworkRestakeDelegator.networkLimitAt.selector, network, timestamp, hints[i]);
        }

        return _optimizeHint(delegator, datas, hints);
    }

    function operatorNetworkSharesHintInternal(
        address network,
        address operator,
        uint48 timestamp
    ) external view internalFunction returns (bool exists, uint32 hint) {
        (exists,,, hint) = _operatorNetworkShares[network][operator].upperLookupRecentCheckpoint(timestamp);
    }

    function operatorNetworkSharesHint(
        address delegator,
        address network,
        address operator,
        uint48 timestamp
    ) public returns (bytes memory) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                delegator,
                abi.encodeWithSelector(
                    NetworkRestakeDelegatorHints.operatorNetworkSharesHintInternal.selector,
                    network,
                    operator,
                    timestamp
                )
            ),
            (bool, uint32)
        );
        bytes memory hint;
        if (exists) {
            hint = abi.encode(hint_);
        }

        uint256 N = 2;
        bytes[] memory hints = new bytes[](N);
        hints[0] = new bytes(0);
        hints[1] = hint;
        bytes[] memory datas = new bytes[](N);
        for (uint256 i; i < N; ++i) {
            datas[i] = abi.encodeWithSelector(
                NetworkRestakeDelegator.operatorNetworkSharesAt.selector, network, operator, timestamp, hints[i]
            );
        }

        return _optimizeHint(delegator, datas, hints);
    }

    function totalOperatorNetworkSharesHintInternal(
        address network,
        uint48 timestamp
    ) external view internalFunction returns (bool exists, uint32 hint) {
        (exists,,, hint) = _totalOperatorNetworkShares[network].upperLookupRecentCheckpoint(timestamp);
    }

    function totalOperatorNetworkSharesHint(
        address delegator,
        address network,
        uint48 timestamp
    ) public returns (bytes memory) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                delegator,
                abi.encodeWithSelector(
                    NetworkRestakeDelegatorHints.totalOperatorNetworkSharesHintInternal.selector, network, timestamp
                )
            ),
            (bool, uint32)
        );
        bytes memory hint;
        if (exists) {
            hint = abi.encode(hint_);
        }

        uint256 N = 2;
        bytes[] memory hints = new bytes[](N);
        hints[0] = new bytes(0);
        hints[1] = hint;
        bytes[] memory datas = new bytes[](N);
        for (uint256 i; i < N; ++i) {
            datas[i] = abi.encodeWithSelector(
                NetworkRestakeDelegator.totalOperatorNetworkSharesAt.selector, network, timestamp, hints[i]
            );
        }

        return _optimizeHint(delegator, datas, hints);
    }

    function stakeHints(
        address delegator,
        address network,
        address operator,
        uint48 timestamp
    ) external returns (bytes memory) {
        bytes memory baseHints =
            BaseDelegatorHints(BASE_DELEGATOR_HINTS).stakeBaseHints(delegator, network, operator, timestamp);

        bytes memory activeStakeHint =
            VaultHints(VAULT_HINTS).activeStakeHint(BaseDelegator(delegator).vault(), timestamp);

        bytes memory networkLimitHint_ = networkLimitHint(delegator, network, timestamp);
        bytes memory operatorNetworkSharesHint_ = operatorNetworkSharesHint(delegator, network, operator, timestamp);
        bytes memory totalOperatorNetworkSharesHint_ = totalOperatorNetworkSharesHint(delegator, network, timestamp);

        if (
            baseHints.length != 0 || activeStakeHint.length != 0 || networkLimitHint_.length != 0
                || operatorNetworkSharesHint_.length != 0 || totalOperatorNetworkSharesHint_.length != 0
        ) {
            uint256 N = 2;
            bytes[] memory hints = new bytes[](N);
            hints[0] = new bytes(0);
            hints[1] = abi.encode(
                StakeHints({
                    baseHints: baseHints,
                    activeStakeHint: activeStakeHint,
                    networkLimitHint: networkLimitHint_,
                    operatorNetworkSharesHint: operatorNetworkSharesHint_,
                    totalOperatorNetworkSharesHint: totalOperatorNetworkSharesHint_
                })
            );
            bytes[] memory datas = new bytes[](N);
            for (uint256 i; i < N; ++i) {
                datas[i] =
                    abi.encodeWithSelector(BaseDelegator.stakeAt.selector, network, operator, timestamp, hints[i]);
            }

            return _optimizeHint(delegator, datas, hints);
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
        address network,
        uint48 timestamp
    ) external view internalFunction returns (bool exists, uint32 hint) {
        (exists,,, hint) = _networkLimit[network].upperLookupRecentCheckpoint(timestamp);
    }

    function networkLimitHint(address delegator, address network, uint48 timestamp) public returns (bytes memory) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                delegator,
                abi.encodeWithSelector(FullRestakeDelegatorHints.networkLimitHintInternal.selector, network, timestamp)
            ),
            (bool, uint32)
        );
        bytes memory hint;
        if (exists) {
            hint = abi.encode(hint_);
        }

        uint256 N = 2;
        bytes[] memory hints = new bytes[](N);
        hints[0] = new bytes(0);
        hints[1] = hint;
        bytes[] memory datas = new bytes[](N);
        for (uint256 i; i < N; ++i) {
            datas[i] =
                abi.encodeWithSelector(FullRestakeDelegator.networkLimitAt.selector, network, timestamp, hints[i]);
        }

        return _optimizeHint(delegator, datas, hints);
    }

    function operatorNetworkLimitHintInternal(
        address network,
        address operator,
        uint48 timestamp
    ) external view internalFunction returns (bool exists, uint32 hint) {
        (exists,,, hint) = _operatorNetworkLimit[network][operator].upperLookupRecentCheckpoint(timestamp);
    }

    function operatorNetworkLimitHint(
        address delegator,
        address network,
        address operator,
        uint48 timestamp
    ) public returns (bytes memory) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                delegator,
                abi.encodeWithSelector(
                    FullRestakeDelegatorHints.operatorNetworkLimitHintInternal.selector, network, operator, timestamp
                )
            ),
            (bool, uint32)
        );
        bytes memory hint;
        if (exists) {
            hint = abi.encode(hint_);
        }

        uint256 N = 2;
        bytes[] memory hints = new bytes[](N);
        hints[0] = new bytes(0);
        hints[1] = hint;
        bytes[] memory datas = new bytes[](N);
        for (uint256 i; i < N; ++i) {
            datas[i] = abi.encodeWithSelector(
                FullRestakeDelegator.operatorNetworkLimitAt.selector, network, operator, timestamp, hints[i]
            );
        }

        return _optimizeHint(delegator, datas, hints);
    }

    function stakeHints(
        address delegator,
        address network,
        address operator,
        uint48 timestamp
    ) external returns (bytes memory) {
        bytes memory baseHints =
            BaseDelegatorHints(BASE_DELEGATOR_HINTS).stakeBaseHints(delegator, network, operator, timestamp);

        bytes memory activeStakeHint =
            VaultHints(VAULT_HINTS).activeStakeHint(BaseDelegator(delegator).vault(), timestamp);

        bytes memory networkLimitHint_ = networkLimitHint(delegator, network, timestamp);
        bytes memory operatorNetworkLimitHint_ = operatorNetworkLimitHint(delegator, network, operator, timestamp);

        if (
            baseHints.length != 0 || activeStakeHint.length != 0 || networkLimitHint_.length != 0
                || operatorNetworkLimitHint_.length != 0
        ) {
            uint256 N = 2;
            bytes[] memory hints = new bytes[](N);
            hints[0] = new bytes(0);
            hints[1] = abi.encode(
                StakeHints({
                    baseHints: baseHints,
                    activeStakeHint: activeStakeHint,
                    networkLimitHint: networkLimitHint_,
                    operatorNetworkLimitHint: operatorNetworkLimitHint_
                })
            );
            bytes[] memory datas = new bytes[](N);
            for (uint256 i; i < N; ++i) {
                datas[i] =
                    abi.encodeWithSelector(BaseDelegator.stakeAt.selector, network, operator, timestamp, hints[i]);
            }

            return _optimizeHint(delegator, datas, hints);
        }
    }
}
