// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IDefaultOperatorRewardsDistributor} from
    "src/interfaces/defaultOperatorRewardsDistributor/IDefaultOperatorRewardsDistributor.sol";
import {INetworkMiddlewareService} from "src/interfaces/service/INetworkMiddlewareService.sol";
import {IRegistry} from "src/interfaces/common/IRegistry.sol";

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract DefaultOperatorRewardsDistributor is Initializable, IDefaultOperatorRewardsDistributor {
    using SafeERC20 for IERC20;

    /**
     * @inheritdoc IDefaultOperatorRewardsDistributor
     */
    address public immutable VAULT_FACTORY;

    /**
     * @inheritdoc IDefaultOperatorRewardsDistributor
     */
    address public immutable NETWORK_REGISTRY;

    /**
     * @inheritdoc IDefaultOperatorRewardsDistributor
     */
    address public immutable NETWORK_MIDDLEWARE_SERVICE;

    /**
     * @inheritdoc IDefaultOperatorRewardsDistributor
     */
    address public vault;

    /**
     * @inheritdoc IDefaultOperatorRewardsDistributor
     */
    mapping(address network => mapping(address token => bytes32 value)) public root;

    /**
     * @inheritdoc IDefaultOperatorRewardsDistributor
     */
    mapping(address network => mapping(address account => mapping(address token => uint256 amount))) public claimed;

    constructor(address vaultFactory, address networkMiddlewareService) {
        _disableInitializers();

        VAULT_FACTORY = vaultFactory;
        NETWORK_MIDDLEWARE_SERVICE = networkMiddlewareService;
    }

    function initialize(address vault_) external initializer {
        if (!IRegistry(VAULT_FACTORY).isEntity(vault_)) {
            revert NotVault();
        }

        vault = vault_;
    }

    /**
     * @inheritdoc IDefaultOperatorRewardsDistributor
     */
    function distributeReward(address network, address token, uint256 amount, bytes32 root_) external {
        if (INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).middleware(network) != msg.sender) {
            revert NotNetworkMiddleware();
        }

        if (root_ == root[network][token]) {
            revert AlreadySet();
        }

        if (amount != 0) {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        root[network][token] = root_;

        emit DistributeReward(network, token, amount, root_);
    }

    /**
     * @inheritdoc IDefaultOperatorRewardsDistributor
     */
    function claimReward(
        address network,
        address account,
        address token,
        uint256 totalClaimable,
        bytes32[] calldata proof
    ) external returns (uint256 amount) {
        bytes32 root_ = root[network][token];
        if (root_ == bytes32(0)) {
            revert RootNotSet();
        }

        if (!MerkleProof.verifyCalldata(proof, root_, keccak256(abi.encode(account, token, totalClaimable)))) {
            revert InvalidProof();
        }

        uint256 claimed_ = claimed[network][account][token];
        if (totalClaimable <= claimed_) {
            revert InsufficientTotalClaimable();
        }

        claimed[network][account][token] = totalClaimable;

        amount = totalClaimable - claimed_;

        IERC20(token).safeTransfer(account, amount);

        emit ClaimReward(network, account, token, amount);
    }
}
