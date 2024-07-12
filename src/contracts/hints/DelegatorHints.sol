// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Hints} from "./Hints.sol";
import {BaseDelegator} from "src/contracts/delegator/BaseDelegator.sol";
import {FullRestakeDelegator} from "src/contracts/delegator/FullRestakeDelegator.sol";
import {NetworkRestakeDelegator} from "src/contracts/delegator/NetworkRestakeDelegator.sol";
import {Vault} from "src/contracts/vault/Vault.sol";
import {VaultHints} from "./VaultHints.sol";
import {OptInServiceHints} from "./OptInServiceHints.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";

contract BaseDelegatorHints is Hints, BaseDelegator {
    using Checkpoints for Checkpoints.Trace256;

    address public immutable networkRestakeDelegatorHints;
    address public immutable fullRestakeDelegatorHints;

    constructor(
        address vaultHints_,
        address optInServiceHints_
    ) BaseDelegator(address(0), address(0), address(0), address(0), address(0), 0) {
        networkRestakeDelegatorHints = address(new NetworkRestakeDelegatorHints(vaultHints_, optInServiceHints_));
        fullRestakeDelegatorHints = address(new FullRestakeDelegatorHints(vaultHints_, optInServiceHints_));
    }

    function stakeHints(
        address delegator,
        address network,
        address operator,
        uint48 captureTimestamp
    ) external returns (bytes memory) {
        if (BaseDelegator(address(this)).TYPE() == 0) {
            return NetworkRestakeDelegatorHints(networkRestakeDelegatorHints).stakeHints(
                delegator, network, operator, captureTimestamp
            );
        } else if (BaseDelegator(address(this)).TYPE() == 1) {
            return FullRestakeDelegatorHints(fullRestakeDelegatorHints).stakeHints(
                delegator, network, operator, captureTimestamp
            );
        }
    }
}

contract NetworkRestakeDelegatorHints is Hints, NetworkRestakeDelegator {
    using Checkpoints for Checkpoints.Trace256;

    address public immutable vaultHints;
    address public immutable optInServiceHints;

    constructor(
        address vaultHints_,
        address optInServiceHints_
    ) NetworkRestakeDelegator(address(0), address(0), address(0), address(0), address(0), 0) {
        vaultHints = vaultHints_;
        optInServiceHints = optInServiceHints_;
    }

    function stakeHintsInner(
        address network,
        address operator,
        uint48 captureTimestamp
    ) external returns (StakeHints memory) {
        bytes memory operatorVaultOptInHint = OptInServiceHints(optInServiceHints).optInHint(
            BaseDelegator(address(this)).OPERATOR_VAULT_OPT_IN_SERVICE(), operator, vault, captureTimestamp
        );
        bytes memory operatorNetworkOptInHint = OptInServiceHints(optInServiceHints).optInHint(
            BaseDelegator(address(this)).OPERATOR_NETWORK_OPT_IN_SERVICE(), operator, network, captureTimestamp
        );

        bytes memory activeStakeHint = VaultHints(vaultHints).activeStakeHint(vault, captureTimestamp);
        (,,, uint32 networkLimitHint) = _networkLimit[network].upperLookupRecentCheckpoint(captureTimestamp);
        (,,, uint32 operatorNetworkSharesHint) =
            _operatorNetworkShares[network][operator].upperLookupRecentCheckpoint(captureTimestamp);
        (,,, uint32 totalOperatorNetworkSharesHint) =
            _totalOperatorNetworkShares[network].upperLookupRecentCheckpoint(captureTimestamp);

        return StakeHints({
            baseHints: StakeBaseHints({
                operatorVaultOptInHint: operatorVaultOptInHint,
                operatorNetworkOptInHint: operatorNetworkOptInHint
            }),
            activeStakeHint: activeStakeHint,
            networkLimitHint: abi.encode(networkLimitHint),
            operatorNetworkSharesHint: abi.encode(operatorNetworkSharesHint),
            totalOperatorNetworkSharesHint: abi.encode(totalOperatorNetworkSharesHint)
        });
    }

    function stakeHints(
        address delegator,
        address network,
        address operator,
        uint48 captureTimestamp
    ) external returns (bytes memory) {
        return _selfStaticDelegateCall(
            delegator,
            abi.encodeWithSelector(
                NetworkRestakeDelegatorHints.stakeHintsInner.selector, network, operator, captureTimestamp
            )
        );
    }
}

contract FullRestakeDelegatorHints is Hints, FullRestakeDelegator {
    using Checkpoints for Checkpoints.Trace256;

    address public immutable vaultHints;
    address public immutable optInServiceHints;

    constructor(
        address vaultHints_,
        address optInServiceHints_
    ) FullRestakeDelegator(address(0), address(0), address(0), address(0), address(0), 0) {
        vaultHints = vaultHints_;
        optInServiceHints = optInServiceHints_;
    }

    function stakeHintsInner(
        address network,
        address operator,
        uint48 captureTimestamp
    ) external returns (StakeHints memory) {
        bytes memory operatorVaultOptInHint = OptInServiceHints(optInServiceHints).optInHint(
            BaseDelegator(address(this)).OPERATOR_VAULT_OPT_IN_SERVICE(), operator, vault, captureTimestamp
        );
        bytes memory operatorNetworkOptInHint = OptInServiceHints(optInServiceHints).optInHint(
            BaseDelegator(address(this)).OPERATOR_NETWORK_OPT_IN_SERVICE(), operator, network, captureTimestamp
        );

        bytes memory activeStakeHint = VaultHints(vaultHints).activeStakeHint(vault, captureTimestamp);
        (,,, uint32 networkLimitHint) = _networkLimit[network].upperLookupRecentCheckpoint(captureTimestamp);
        (,,, uint32 operatorNetworkLimitHint) =
            _operatorNetworkLimit[network][operator].upperLookupRecentCheckpoint(captureTimestamp);

        return StakeHints({
            baseHints: StakeBaseHints({
                operatorVaultOptInHint: operatorVaultOptInHint,
                operatorNetworkOptInHint: operatorNetworkOptInHint
            }),
            activeStakeHint: activeStakeHint,
            networkLimitHint: abi.encode(networkLimitHint),
            operatorNetworkLimitHint: abi.encode(operatorNetworkLimitHint)
        });
    }

    function stakeHints(
        address delegator,
        address network,
        address operator,
        uint48 captureTimestamp
    ) external returns (bytes memory) {
        return _selfStaticDelegateCall(
            delegator,
            abi.encodeWithSelector(
                FullRestakeDelegatorHints.stakeHintsInner.selector, network, operator, captureTimestamp
            )
        );
    }
}
