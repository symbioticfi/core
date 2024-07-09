pragma solidity 0.8.25;

interface IFullRestakeDelegatorHook {
    /**
     * @notice Called when a slash happens.
     * @param network address of the network
     * @param operator address of the operator
     * @param slashedAmount amount of the collateral slashed
     * @param captureTimestamp time point when the stake was captured
     * @return networkLimit new network limit
     * @return operatorNetworkLimit new operator network limit
     */
    function onSlash(
        address network,
        address operator,
        uint256 slashedAmount,
        uint48 captureTimestamp
    ) external returns (uint256 networkLimit, uint256 operatorNetworkLimit);
}
