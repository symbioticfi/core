// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IDefaultOperatorRewardsDistributor {
    error NotVault();
    error AlreadySet();
    error RootNotSet();
    error InvalidProof();
    error InsufficientTotalClaimable();
    error NotNetworkMiddleware();
    error InsufficientReward();

    event DistributeReward(address indexed network, address indexed token, uint256 amount, bytes32 root);

    event ClaimReward(address indexed network, address indexed account, address indexed token, uint256 amount);

    function VAULT_FACTORY() external view returns (address);

    function NETWORK_REGISTRY() external view returns (address);

    function NETWORK_MIDDLEWARE_SERVICE() external view returns (address);

    function vault() external view returns (address);

    function root(address network, address token) external view returns (bytes32);

    function claimed(address network, address account, address token) external view returns (uint256);

    function claimReward(
        address network,
        address account,
        address token,
        uint256 totalClaimable,
        bytes32[] calldata proof
    ) external returns (uint256 amount);

    function distributeReward(address network, address token, uint256 amount, bytes32 root) external;
}
