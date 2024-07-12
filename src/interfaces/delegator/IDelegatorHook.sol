pragma solidity 0.8.25;

interface IDelegatorHook {
    /**
     * @notice Called when a slash happens.
     * @param network address of the network
     * @param operator address of the operator
     * @param slashedAmount amount of the collateral slashed
     * @param captureTimestamp time point when the stake was captured
     */
    function onSlash(address network, address operator, uint256 slashedAmount, uint48 captureTimestamp) external;
}
