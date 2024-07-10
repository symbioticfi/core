pragma solidity 0.8.25;

interface INetworkRestakeDelegatorHook {
    /**
     * @notice Called when a slash happens.
     * @param network address of the network
     * @param operator address of the operator
     * @param slashedAmount amount of the collateral slashed
     * @param captureTimestamp time point when the stake was captured
     * @return isUpdate if the network limit or operator network shares must be updated
     * @return networkLimit new network limit
     * @return operatorNetworkShares new operator network shares
     */
    function onSlash(
        address network,
        address operator,
        uint256 slashedAmount,
        uint48 captureTimestamp
    ) external returns (bool isUpdate, uint256 networkLimit, uint256 operatorNetworkShares);
}
