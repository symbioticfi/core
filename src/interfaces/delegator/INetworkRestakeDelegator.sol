pragma solidity 0.8.25;

import {IBaseDelegator} from "./IBaseDelegator.sol";

interface INetworkRestakeDelegator is IBaseDelegator {
    error ExceedsMaxNetworkLimit();

    struct InitParams {
        address vault;
    }

    event SetNetworkLimit(address indexed network, uint256 amount);

    event SetOperatorNetworkShares(address indexed network, address indexed operator, uint256 shares);

    function NETWORK_LIMIT_SET_ROLE() external view returns (bytes32);

    function OPERATOR_NETWORK_SHARES_SET_ROLE() external view returns (bytes32);

    function networkLimitIn(address network, uint48 duration) external view returns (uint256);

    function networkLimit(address network) external view returns (uint256);

    function totalOperatorNetworkSharesIn(address network, uint48 duration) external view returns (uint256);

    function totalOperatorNetworkShares(address network) external view returns (uint256);

    function operatorNetworkSharesIn(
        address network,
        address operator,
        uint48 duration
    ) external view returns (uint256);

    function operatorNetworkShares(address network, address operator) external view returns (uint256);

    function setNetworkLimit(address network, uint256 amount) external;

    function setOperatorNetworkShares(address network, address operator, uint256 shares) external;
}
