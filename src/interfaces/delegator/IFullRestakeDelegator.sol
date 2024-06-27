pragma solidity 0.8.25;

import {IBaseDelegator} from "./IBaseDelegator.sol";

interface IFullRestakeDelegator is IBaseDelegator {
    error ExceedsMaxNetworkLimit();

    struct InitParams {
        address vault;
    }

    event SetNetworkLimit(address indexed network, uint256 amount);

    event SetOperatorNetworkLimit(address indexed network, address indexed operator, uint256 amount);

    function NETWORK_LIMIT_SET_ROLE() external view returns (bytes32);

    function OPERATOR_NETWORK_LIMIT_SET_ROLE() external view returns (bytes32);

    function networkLimitIn(address network, uint48 duration) external view returns (uint256);

    function networkLimit(address network) external view returns (uint256);

    function totalOperatorNetworkLimitIn(address network, uint48 duration) external view returns (uint256);

    function totalOperatorNetworkLimit(address network) external view returns (uint256);

    function operatorNetworkLimitIn(
        address network,
        address operator,
        uint48 duration
    ) external view returns (uint256);

    function operatorNetworkLimit(address network, address operator) external view returns (uint256);

    function setNetworkLimit(address network, uint256 amount) external;

    function setOperatorNetworkLimit(address network, address operator, uint256 amount) external;
}
