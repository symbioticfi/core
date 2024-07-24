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
    ) public view returns (bytes memory) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                slasher,
                abi.encodeWithSelector(
                    BaseSlasherHints.cumulativeSlashHintInternal.selector, network, operator, timestamp
                )
            ),
            (bool, uint32)
        );

        if (exists) {
            return abi.encode(hint_);
        }
    }

    function slashableStakeHints(
        address slasher,
        address network,
        address operator,
        uint48 captureTimestamp
    ) external view returns (bytes memory) {
        bytes memory stakeHints = BaseDelegatorHints(BASE_DELEGATOR_HINTS).stakeHints(
            Vault(BaseSlasher(slasher).vault()).delegator(), network, operator, captureTimestamp
        );

        bytes memory cumulativeSlashFromHint = cumulativeSlashHint(slasher, network, operator, captureTimestamp);

        if (stakeHints.length > 0 || cumulativeSlashFromHint.length > 0) {
            return abi.encode(
                SlashableStakeHints({stakeHints: stakeHints, cumulativeSlashFromHint: cumulativeSlashFromHint})
            );
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
    ) external view returns (bytes memory) {
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
            return abi.encode(
                OptInHints({
                    networkVaultOptInHint: networkVaultOptInHint,
                    operatorVaultOptInHint: operatorVaultOptInHint,
                    operatorNetworkOptInHint: operatorNetworkOptInHint
                })
            );
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
    ) external view returns (bytes memory) {
        bytes memory delegatorOnSlashHints = BaseDelegatorHints(BASE_DELEGATOR_HINTS).onSlashHints(
            Vault(BaseSlasher(slasher).vault()).delegator(), network, operator, amount, captureTimestamp
        );

        if (delegatorOnSlashHints.length > 0) {
            return abi.encode(OnSlashHints({delegatorOnSlashHints: delegatorOnSlashHints}));
        }
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
    ) external view returns (bytes memory) {
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
            return abi.encode(
                SlashHints({
                    optInHints: optInHints,
                    slashableStakeHints: slashableStakeHints,
                    onSlashHints: onSlashHints
                })
            );
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
    ) public view returns (bytes memory) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                slasher,
                abi.encodeWithSelector(
                    VetoSlasherHints.resolverSharesHintInternal.selector, network, resolver, timestamp
                )
            ),
            (bool, uint32)
        );

        if (exists) {
            return abi.encode(hint_);
        }
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
    ) external view returns (bytes memory) {
        bytes memory optInHints =
            BaseSlasherHints(BASE_SLASHER_HINTS).optInHints(slasher, network, operator, captureTimestamp);
        bytes memory slashableStakeHints =
            BaseSlasherHints(BASE_SLASHER_HINTS).slashableStakeHints(slasher, network, operator, captureTimestamp);

        if (optInHints.length > 0 || slashableStakeHints.length > 0) {
            return abi.encode(RequestSlashHints({optInHints: optInHints, slashableStakeHints: slashableStakeHints}));
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
    ) external view returns (bytes memory) {
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
            return abi.encode(ExecuteSlashHints({slashableStakeHints: slashableStakeHints, onSlashHints: onSlashHints}));
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

    function vetoSlashHints(
        address slasher,
        address msgSender,
        uint256 slashIndex
    ) external view returns (bytes memory) {
        (address network, address operator, uint256 amount, uint48 captureTimestamp,, uint256 vetoedShares,) =
            VetoSlasher(slasher).slashRequests(slashIndex);

        bytes memory resolverSharesHint_ = resolverSharesHint(slasher, network, msgSender, Time.timestamp());

        if (resolverSharesHint_.length > 0) {
            return abi.encode(VetoSlashHints({resolverSharesHint: resolverSharesHint_}));
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
    ) external view returns (bytes memory) {
        bytes memory resolverSharesHint_ = resolverSharesHint(slasher, msgSender, resolver, Time.timestamp());

        if (resolverSharesHint_.length > 0) {
            return abi.encode(SetResolverSharesHints({resolverSharesHint: resolverSharesHint_}));
        }
    }
}
