// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IMerklDistributor
 * @notice Minimal Merkl distributor interface.
 */
interface IMerklDistributor {
    /* FUNCTIONS */

    /**
     * @notice Claims Merkl rewards for users and tokens.
     * @param users Users receiving rewards.
     * @param tokens Reward tokens.
     * @param amounts Cumulative reward amounts.
     * @param proofs Merkle proofs.
     */
    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external;
}

/**
 * @title IMerklRedistributor
 * @notice Interface for forwarding Merkl distributor claims.
 */
interface IMerklRedistributor {
    /* FUNCTIONS */

    /**
     * @notice Returns the Merkl distributor used for claims.
     * @return distributor Merkl distributor address.
     */
    function MERKL_DISTRIBUTOR() external view returns (address distributor);

    /**
     * @notice Claims Merkl rewards through the configured distributor.
     * @param users Users receiving rewards.
     * @param tokens Reward tokens.
     * @param amounts Cumulative reward amounts.
     * @param proofs Merkle proofs.
     */
    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external;
}
