// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Hints} from "./Hints.sol";
import {BaseSlasher} from "src/contracts/slasher/BaseSlasher.sol";
import {Slasher} from "src/contracts/slasher/Slasher.sol";
import {VetoSlasher} from "src/contracts/slasher/VetoSlasher.sol";
import {Vault} from "src/contracts/vault/Vault.sol";
import {BaseDelegatorHints} from "./DelegatorHints.sol";
import {OptInServiceHints} from "./OptInServiceHints.sol";

import {IOptInService} from "src/interfaces/service/IOptInService.sol";
import {INetworkMiddlewareService} from "src/interfaces/service/INetworkMiddlewareService.sol";
import {IRegistry} from "src/interfaces/common/IRegistry.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract BaseSlasherHints is Hints, BaseSlasher {
    using Checkpoints for Checkpoints.Trace256;

    address public immutable BASE_DELEGATOR_HINTS;
    address public immutable OPT_IN_SERVICE_HINTS;
    address public immutable SLASHER_HINTS;
    address public immutable VETO_SLASHER_HINTS;

    constructor(
        address baseDelegatorHints,
        address optInServiceHints
    ) BaseSlasher(address(0), address(0), address(0), address(0), address(0), address(0), 0) {
        BASE_DELEGATOR_HINTS = baseDelegatorHints;
        OPT_IN_SERVICE_HINTS = optInServiceHints;
        SLASHER_HINTS = address(new SlasherHints(address(this)));
        VETO_SLASHER_HINTS = address(new VetoSlasherHints(address(this)));
    }

    function cumulativeSlashHintInternal(
        address network,
        address operator,
        uint48 timestamp
    ) external view internalFunction returns (bool exists, uint32 hint) {
        (exists,,, hint) = _cumulativeSlash[network][operator].upperLookupRecentCheckpoint(timestamp);
    }

    function cumulativeSlashHint(
        address slasher,
        address network,
        address operator,
        uint48 timestamp
    ) public returns (bytes memory) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                slasher,
                abi.encodeWithSelector(
                    BaseSlasherHints.cumulativeSlashHintInternal.selector, network, operator, timestamp
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
                abi.encodeWithSelector(BaseSlasher.cumulativeSlashAt.selector, network, operator, timestamp, hints[i]);
        }

        return _optimizeHint(slasher, datas, hints);
    }

    function slashableStakeHints(
        address slasher,
        address network,
        address operator,
        uint48 captureTimestamp
    ) external returns (bytes memory) {
        bytes memory stakeHints = BaseDelegatorHints(BASE_DELEGATOR_HINTS).stakeHints(
            Vault(BaseSlasher(slasher).vault()).delegator(), network, operator, captureTimestamp
        );

        bytes memory cumulativeSlashFromHint = cumulativeSlashHint(slasher, network, operator, captureTimestamp);

        if (stakeHints.length > 0 || cumulativeSlashFromHint.length > 0) {
            uint256 N = 2;
            bytes[] memory hints = new bytes[](N);
            hints[0] = new bytes(0);
            hints[1] = abi.encode(
                SlashableStakeHints({stakeHints: stakeHints, cumulativeSlashFromHint: cumulativeSlashFromHint})
            );
            bytes[] memory datas = new bytes[](N);
            for (uint256 i; i < N; ++i) {
                datas[i] = abi.encodeWithSelector(
                    BaseSlasher.slashableStake.selector, network, operator, captureTimestamp, hints[i]
                );
            }

            return _optimizeHint(slasher, datas, hints);
        }
    }

    function _optIns(
        address slasher,
        address network,
        address operator,
        uint48 timestamp,
        bytes memory hints
    ) external view returns (bool) {
        OptInHints memory optInHints_;
        if (hints.length > 0) {
            optInHints_ = abi.decode(hints, (OptInHints));
        }

        address vault_ = BaseSlasher(slasher).vault();

        if (
            !IOptInService(BaseSlasher(slasher).NETWORK_VAULT_OPT_IN_SERVICE()).isOptedInAt(
                network, vault_, timestamp, optInHints_.networkVaultOptInHint
            )
        ) {
            return true;
        }

        if (
            !IOptInService(BaseSlasher(slasher).OPERATOR_VAULT_OPT_IN_SERVICE()).isOptedInAt(
                operator, vault_, timestamp, optInHints_.operatorVaultOptInHint
            )
        ) {
            return true;
        }

        if (
            !IOptInService(BaseSlasher(slasher).OPERATOR_NETWORK_OPT_IN_SERVICE()).isOptedInAt(
                operator, network, timestamp, optInHints_.operatorNetworkOptInHint
            )
        ) {
            return true;
        }
    }

    function optInHints(
        address slasher,
        address network,
        address operator,
        uint48 timestamp
    ) external returns (bytes memory) {
        bytes memory networkVaultOptInHint = OptInServiceHints(OPT_IN_SERVICE_HINTS).optInHint(
            BaseSlasher(slasher).NETWORK_VAULT_OPT_IN_SERVICE(), network, BaseSlasher(slasher).vault(), timestamp
        );

        bytes memory operatorVaultOptInHint = OptInServiceHints(OPT_IN_SERVICE_HINTS).optInHint(
            BaseSlasher(slasher).OPERATOR_VAULT_OPT_IN_SERVICE(), operator, BaseSlasher(slasher).vault(), timestamp
        );

        bytes memory operatorNetworkOptInHint = OptInServiceHints(OPT_IN_SERVICE_HINTS).optInHint(
            BaseSlasher(slasher).OPERATOR_NETWORK_OPT_IN_SERVICE(), operator, network, timestamp
        );

        if (
            networkVaultOptInHint.length > 0 || operatorVaultOptInHint.length > 0 || operatorNetworkOptInHint.length > 0
        ) {
            uint256 N = 4;
            bytes[] memory hints = new bytes[](N);
            hints[0] = new bytes(0);
            hints[1] = abi.encode(
                OptInHints({
                    networkVaultOptInHint: networkVaultOptInHint,
                    operatorVaultOptInHint: new bytes(0),
                    operatorNetworkOptInHint: new bytes(0)
                })
            );
            hints[2] = abi.encode(
                OptInHints({
                    networkVaultOptInHint: networkVaultOptInHint,
                    operatorVaultOptInHint: operatorVaultOptInHint,
                    operatorNetworkOptInHint: new bytes(0)
                })
            );
            hints[3] = abi.encode(
                OptInHints({
                    networkVaultOptInHint: networkVaultOptInHint,
                    operatorVaultOptInHint: operatorVaultOptInHint,
                    operatorNetworkOptInHint: operatorNetworkOptInHint
                })
            );
            bytes[] memory datas = new bytes[](N);
            for (uint256 i; i < N; ++i) {
                datas[i] = abi.encodeWithSelector(
                    BaseSlasherHints._optIns.selector, slasher, network, operator, timestamp, hints[i]
                );
            }

            return _optimizeHint(address(this), datas, hints);
        }
    }

    function _onSlash(
        address slasher,
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

        BaseDelegatorHints(BASE_DELEGATOR_HINTS)._onSlash(
            Vault(BaseSlasher(slasher).vault()).delegator(),
            network,
            operator,
            amount,
            captureTimestamp,
            onSlashHints_.delegatorOnSlashHints
        );
    }

    function onSlashHints(
        address slasher,
        address network,
        address operator,
        uint256 amount,
        uint48 captureTimestamp
    ) external returns (bytes memory) {
        bytes memory delegatorOnSlashHints = BaseDelegatorHints(BASE_DELEGATOR_HINTS).onSlashHints(
            Vault(BaseSlasher(slasher).vault()).delegator(), network, operator, amount, captureTimestamp
        );

        bytes memory hints_;
        if (delegatorOnSlashHints.length > 0) {
            hints_ = abi.encode(OnSlashHints({delegatorOnSlashHints: delegatorOnSlashHints}));
        }

        uint256 N = 2;
        bytes[] memory hints = new bytes[](N);
        hints[0] = new bytes(0);
        hints[1] = hints_;

        bytes[] memory datas = new bytes[](N);
        for (uint256 i; i < N; ++i) {
            datas[i] = abi.encodeWithSelector(
                BaseSlasherHints._onSlash.selector, slasher, network, operator, amount, captureTimestamp, hints[i]
            );
        }

        return _optimizeHint(address(this), datas, hints);
    }
}

contract SlasherHints is Hints, Slasher {
    address public immutable BASE_SLASHER_HINTS;

    constructor(address baseSlasherHints)
        Slasher(address(0), address(0), address(0), address(0), address(0), address(0), 0)
    {
        BASE_SLASHER_HINTS = baseSlasherHints;
    }

    function _slash(
        address slasher,
        address msgSender,
        address network,
        address operator,
        uint256 amount,
        uint48 captureTimestamp,
        bytes memory hints
    ) external view returns (bool) {
        if (
            INetworkMiddlewareService(BaseSlasher(slasher).NETWORK_MIDDLEWARE_SERVICE()).middleware(network)
                != msgSender
        ) {
            return true;
        }

        SlashHints memory slashHints_;
        if (hints.length > 0) {
            slashHints_ = abi.decode(hints, (SlashHints));
        }

        if (
            BaseSlasherHints(BASE_SLASHER_HINTS)._optIns(
                slasher, network, operator, captureTimestamp, slashHints_.optInHints
            )
        ) {
            return true;
        }

        if (
            captureTimestamp < Time.timestamp() - Vault(BaseSlasher(slasher).vault()).epochDuration()
                || captureTimestamp >= Time.timestamp()
        ) {
            return true;
        }

        uint256 slashedAmount = Math.min(
            amount,
            BaseSlasher(slasher).slashableStake(network, operator, captureTimestamp, slashHints_.slashableStakeHints)
        );

        if (slashedAmount == 0) {
            return true;
        }

        BaseSlasherHints(BASE_SLASHER_HINTS)._onSlash(
            slasher, network, operator, slashedAmount, captureTimestamp, slashHints_.onSlashHints
        );
    }

    function slashHints(
        address slasher,
        address msgSender,
        address network,
        address operator,
        uint256 amount,
        uint48 captureTimestamp
    ) external returns (bytes memory) {
        bytes memory onSlashHints = BaseSlasherHints(BASE_SLASHER_HINTS).onSlashHints(
            slasher,
            network,
            operator,
            Math.min(amount, BaseSlasher(slasher).slashableStake(network, operator, captureTimestamp, "")),
            captureTimestamp
        );
        bytes memory optInHints =
            BaseSlasherHints(BASE_SLASHER_HINTS).optInHints(slasher, network, operator, captureTimestamp);
        bytes memory slashableStakeHints =
            BaseSlasherHints(BASE_SLASHER_HINTS).slashableStakeHints(slasher, network, operator, captureTimestamp);

        if (optInHints.length > 0 || slashableStakeHints.length > 0 || onSlashHints.length > 0) {
            uint256 N = 4;
            bytes[] memory hints = new bytes[](N);
            hints[0] = new bytes(0);
            hints[1] = abi.encode(
                SlashHints({optInHints: optInHints, slashableStakeHints: new bytes(0), onSlashHints: new bytes(0)})
            );
            hints[2] = abi.encode(
                SlashHints({
                    optInHints: optInHints,
                    slashableStakeHints: slashableStakeHints,
                    onSlashHints: new bytes(0)
                })
            );
            hints[3] = abi.encode(
                SlashHints({
                    optInHints: optInHints,
                    slashableStakeHints: slashableStakeHints,
                    onSlashHints: onSlashHints
                })
            );

            bytes[] memory datas = new bytes[](N);
            for (uint256 i; i < N; ++i) {
                datas[i] = abi.encodeWithSelector(
                    SlasherHints._slash.selector,
                    slasher,
                    msgSender,
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

contract VetoSlasherHints is Hints, VetoSlasher {
    using Math for uint256;
    using Checkpoints for Checkpoints.Trace256;
    using SafeCast for uint256;

    address public immutable BASE_SLASHER_HINTS;

    constructor(address baseSlasherHints)
        VetoSlasher(address(0), address(0), address(0), address(0), address(0), address(0), address(0), 0)
    {
        BASE_SLASHER_HINTS = baseSlasherHints;
    }

    function resolverSharesHintInternal(
        address network,
        address resolver,
        uint48 timestamp
    ) external view internalFunction returns (bool exists, uint32 hint) {
        (exists,,, hint) = _resolverShares[network][resolver].upperLookupRecentCheckpoint(timestamp);
    }

    function resolverSharesHint(
        address slasher,
        address network,
        address resolver,
        uint48 timestamp
    ) public returns (bytes memory) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                slasher,
                abi.encodeWithSelector(
                    VetoSlasherHints.resolverSharesHintInternal.selector, network, resolver, timestamp
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
                abi.encodeWithSelector(VetoSlasher.resolverSharesAt.selector, network, resolver, timestamp, hints[i]);
        }

        return _optimizeHint(slasher, datas, hints);
    }

    function _requestSlash(
        address slasher,
        address msgSender,
        address network,
        address operator,
        uint256 amount,
        uint48 captureTimestamp,
        bytes memory hints
    ) external view returns (bool) {
        if (
            INetworkMiddlewareService(BaseSlasher(slasher).NETWORK_MIDDLEWARE_SERVICE()).middleware(network)
                != msgSender
        ) {
            return true;
        }

        RequestSlashHints memory requestSlashHints;
        if (hints.length > 0) {
            requestSlashHints = abi.decode(hints, (RequestSlashHints));
        }

        if (
            captureTimestamp
                < Time.timestamp() + VetoSlasher(slasher).vetoDuration()
                    - Vault(BaseSlasher(slasher).vault()).epochDuration() || captureTimestamp >= Time.timestamp()
        ) {
            return true;
        }

        if (
            BaseSlasherHints(BASE_SLASHER_HINTS)._optIns(
                slasher, network, operator, captureTimestamp, requestSlashHints.optInHints
            )
        ) {
            return true;
        }

        amount = Math.min(
            amount,
            BaseSlasher(slasher).slashableStake(
                network, operator, captureTimestamp, requestSlashHints.slashableStakeHints
            )
        );
        if (amount == 0) {
            return true;
        }
    }

    function requestSlashHints(
        address slasher,
        address msgSender,
        address network,
        address operator,
        uint256 amount,
        uint48 captureTimestamp
    ) external returns (bytes memory) {
        bytes memory optInHints =
            BaseSlasherHints(BASE_SLASHER_HINTS).optInHints(slasher, network, operator, captureTimestamp);
        bytes memory slashableStakeHints =
            BaseSlasherHints(BASE_SLASHER_HINTS).slashableStakeHints(slasher, network, operator, captureTimestamp);

        if (optInHints.length > 0 || slashableStakeHints.length > 0) {
            uint256 N = 3;
            bytes[] memory hints = new bytes[](N);
            hints[0] = new bytes(0);
            hints[1] = abi.encode(RequestSlashHints({optInHints: optInHints, slashableStakeHints: new bytes(0)}));
            hints[2] = abi.encode(RequestSlashHints({optInHints: optInHints, slashableStakeHints: slashableStakeHints}));

            bytes[] memory datas = new bytes[](N);
            for (uint256 i; i < N; ++i) {
                datas[i] = abi.encodeWithSelector(
                    VetoSlasherHints._requestSlash.selector,
                    slasher,
                    msgSender,
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

    function _executeSlash(
        address slasher,
        address msgSender,
        uint256 slashIndex,
        bytes memory hints
    ) external view returns (bool) {
        ExecuteSlashHints memory executeSlashHints;
        if (hints.length > 0) {
            executeSlashHints = abi.decode(hints, (ExecuteSlashHints));
        }

        if (slashIndex >= VetoSlasher(slasher).slashRequestsLength()) {
            return true;
        }

        (
            address network,
            address operator,
            uint256 amount,
            uint48 captureTimestamp,
            uint48 vetoDeadline,
            uint256 vetoedShares,
            bool completed
        ) = VetoSlasher(slasher).slashRequests(slashIndex);

        if (vetoDeadline > Time.timestamp()) {
            return true;
        }

        if (Time.timestamp() - captureTimestamp > Vault(BaseSlasher(slasher).vault()).epochDuration()) {
            return true;
        }

        if (completed) {
            return true;
        }

        uint256 slashedAmount = Math.min(
            amount,
            BaseSlasher(slasher).slashableStake(
                network, operator, captureTimestamp, executeSlashHints.slashableStakeHints
            )
        );

        slashedAmount -= slashedAmount.mulDiv(vetoedShares, SHARES_BASE, Math.Rounding.Ceil);

        if (slashedAmount > 0) {
            BaseSlasherHints(BASE_SLASHER_HINTS)._onSlash(
                slasher, network, operator, slashedAmount, captureTimestamp, executeSlashHints.onSlashHints
            );
        }
    }

    function executeSlashHints(
        address slasher,
        address msgSender,
        uint256 slashIndex
    ) external returns (bytes memory) {
        (address network, address operator, uint256 amount, uint48 captureTimestamp,, uint256 vetoedShares,) =
            VetoSlasher(slasher).slashRequests(slashIndex);

        bytes memory slashableStakeHints =
            BaseSlasherHints(BASE_SLASHER_HINTS).slashableStakeHints(slasher, network, operator, captureTimestamp);

        uint256 slashedAmount =
            Math.min(amount, BaseSlasher(slasher).slashableStake(network, operator, captureTimestamp, ""));
        slashedAmount -= slashedAmount.mulDiv(vetoedShares, SHARES_BASE, Math.Rounding.Ceil);
        bytes memory onSlashHints = BaseSlasherHints(BASE_SLASHER_HINTS).onSlashHints(
            slasher, network, operator, slashedAmount, captureTimestamp
        );

        if (slashableStakeHints.length > 0 || onSlashHints.length > 0) {
            uint256 N = 3;
            bytes[] memory hints = new bytes[](N);
            hints[0] = new bytes(0);
            hints[1] =
                abi.encode(ExecuteSlashHints({slashableStakeHints: slashableStakeHints, onSlashHints: new bytes(0)}));
            hints[2] =
                abi.encode(ExecuteSlashHints({slashableStakeHints: slashableStakeHints, onSlashHints: onSlashHints}));

            bytes[] memory datas = new bytes[](N);
            for (uint256 i; i < N; ++i) {
                datas[i] = abi.encodeWithSelector(
                    VetoSlasherHints._executeSlash.selector, slasher, msgSender, slashIndex, hints[i]
                );
            }

            return _optimizeHint(address(this), datas, hints);
        }
    }

    function _vetoSlash(
        address slasher,
        address msgSender,
        uint256 slashIndex,
        bytes memory hints
    ) external view returns (bool) {
        VetoSlashHints memory vetoSlashHints_;
        if (hints.length > 0) {
            vetoSlashHints_ = abi.decode(hints, (VetoSlashHints));
        }

        if (slashIndex >= VetoSlasher(slasher).slashRequestsLength()) {
            return true;
        }

        (
            address network,
            address operator,
            uint256 amount,
            uint48 captureTimestamp,
            uint48 vetoDeadline,
            uint256 vetoedShares,
            bool completed
        ) = VetoSlasher(slasher).slashRequests(slashIndex);

        uint256 resolverShares_ =
            VetoSlasher(slasher).resolverShares(network, msgSender, vetoSlashHints_.resolverSharesHint);

        if (resolverShares_ == 0) {
            return true;
        }

        if (vetoDeadline <= Time.timestamp()) {
            return true;
        }

        if (completed) {
            return true;
        }

        if (VetoSlasher(slasher).hasVetoed(msgSender, slashIndex)) {
            return true;
        }
    }

    function vetoSlashHints(address slasher, address msgSender, uint256 slashIndex) external returns (bytes memory) {
        (address network, address operator, uint256 amount, uint48 captureTimestamp,, uint256 vetoedShares,) =
            VetoSlasher(slasher).slashRequests(slashIndex);

        bytes memory resolverSharesHint_ = resolverSharesHint(slasher, network, msgSender, Time.timestamp());

        if (resolverSharesHint_.length > 0) {
            uint256 N = 2;
            bytes[] memory hints = new bytes[](N);
            hints[0] = new bytes(0);
            hints[1] = abi.encode(VetoSlashHints({resolverSharesHint: resolverSharesHint_}));

            bytes[] memory datas = new bytes[](N);
            for (uint256 i; i < N; ++i) {
                datas[i] = abi.encodeWithSelector(
                    VetoSlasherHints._vetoSlash.selector, slasher, msgSender, slashIndex, hints[i]
                );
            }

            return _optimizeHint(address(this), datas, hints);
        }
    }

    function _setResolverShares(
        address slasher,
        address msgSender,
        address resolver,
        uint256 shares,
        bytes memory hints
    ) external view returns (bool) {
        SetResolverSharesHints memory setResolverSharesHints_;
        if (hints.length > 0) {
            setResolverSharesHints_ = abi.decode(hints, (SetResolverSharesHints));
        }

        if (!IRegistry(VetoSlasher(slasher).NETWORK_REGISTRY()).isEntity(msgSender)) {
            return true;
        }

        if (shares > SHARES_BASE) {
            return true;
        }

        uint48 timestamp = shares
            > VetoSlasher(slasher).resolverShares(msgSender, resolver, setResolverSharesHints_.resolverSharesHint)
            ? Time.timestamp()
            : (
                Vault(BaseSlasher(slasher).vault()).currentEpochStart()
                    + VetoSlasher(slasher).resolverSetEpochsDelay() * Vault(VetoSlasher(slasher).vault()).epochDuration()
            ).toUint48();
    }

    function setResolverSharesHints(
        address slasher,
        address msgSender,
        address resolver,
        uint256 shares
    ) external returns (bytes memory) {
        bytes memory resolverSharesHint_ = resolverSharesHint(slasher, msgSender, resolver, Time.timestamp());

        if (resolverSharesHint_.length > 0) {
            uint256 N = 2;
            bytes[] memory hints = new bytes[](N);
            hints[0] = new bytes(0);
            hints[1] = abi.encode(SetResolverSharesHints({resolverSharesHint: resolverSharesHint_}));

            bytes[] memory datas = new bytes[](N);
            for (uint256 i; i < N; ++i) {
                datas[i] = abi.encodeWithSelector(
                    VetoSlasherHints._setResolverShares.selector, slasher, msgSender, resolver, shares, hints[i]
                );
            }

            return _optimizeHint(address(this), datas, hints);
        }
    }
}
