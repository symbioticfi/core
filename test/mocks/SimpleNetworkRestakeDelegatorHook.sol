// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {INetworkRestakeDelegator} from "../../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IDelegatorHook} from "../../src/interfaces/delegator/IDelegatorHook.sol";
import {IBaseSlasher} from "../../src/interfaces/slasher/IBaseSlasher.sol";
import {ISlasher} from "../../src/interfaces/slasher/ISlasher.sol";
import {IVetoSlasher} from "../../src/interfaces/slasher/IVetoSlasher.sol";

contract SimpleNetworkRestakeDelegatorHook is IDelegatorHook {
    uint256 public counter1;
    uint256 public counter2;
    uint256 public counter3;

    uint256 slasherType;
    uint256 slashableStake;
    uint256 stakeAt;
    uint256 slashIndex;

    function setData(uint64 slasherType_, uint256 slashableStake_, uint256 stakeAt_, uint256 slashIndex_) external {
        slasherType = slasherType_;
        slashableStake = slashableStake_;
        stakeAt = stakeAt_;
        slashIndex = slashIndex_;
    }

    function onSlash(bytes32 subnetwork, address operator, uint256, uint48, bytes calldata data) external {
        IBaseSlasher.GeneralDelegatorData memory generalDelegatorData =
            abi.decode(data, (IBaseSlasher.GeneralDelegatorData));

        assert(generalDelegatorData.slasherType == slasherType);
        if (generalDelegatorData.slasherType == 0) {
            ISlasher.DelegatorData memory delegatorData =
                abi.decode(generalDelegatorData.data, (ISlasher.DelegatorData));

            assert(delegatorData.slashableStake == slashableStake);
            assert(delegatorData.stakeAt == stakeAt);
        } else if (generalDelegatorData.slasherType == 1) {
            IVetoSlasher.DelegatorData memory delegatorData =
                abi.decode(generalDelegatorData.data, (IVetoSlasher.DelegatorData));

            assert(delegatorData.slashableStake == slashableStake);
            assert(delegatorData.stakeAt == stakeAt);
            assert(delegatorData.slashIndex == slashIndex);
        }

        ++counter1;
        ++counter2;
        ++counter3;
        if (counter1 == 2) {
            INetworkRestakeDelegator(msg.sender).setOperatorNetworkShares(subnetwork, operator, 0);
        }
    }
}
