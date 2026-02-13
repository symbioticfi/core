// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IPluginBase} from "../../src/interfaces/vault/IPluginBase.sol";
import {IVaultV2Storage} from "../../src/interfaces/vault/IVaultV2Storage.sol";

import {ERC4626Math} from "../../src/contracts/libraries/ERC4626Math.sol";
import {IVaultV2} from "../../src/interfaces/vault/IVaultV2.sol";

import {SafeTransferLib as SafeERC20} from "@solady/src/utils/SafeTransferLib.sol";

import {FixedPointMathLib as Math} from "@solady/src/utils/FixedPointMathLib.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IERC2612 {
    function permit(address owner, address spender, uint256 shares, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;
    function nonces(address owner) external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

struct Caps {
    uint256 allocation;
    uint128 absoluteCap;
    uint128 relativeCap;
}

interface IMorphoVault is IERC4626, IERC2612 {
    // State variables
    function virtualShares() external view returns (uint256);
    function owner() external view returns (address);
    function curator() external view returns (address);
    function receiveSharesGate() external view returns (address);
    function sendSharesGate() external view returns (address);
    function receiveAssetsGate() external view returns (address);
    function sendAssetsGate() external view returns (address);
    function adapterRegistry() external view returns (address);
    function isSentinel(address account) external view returns (bool);
    function isAllocator(address account) external view returns (bool);
    function firstTotalAssets() external view returns (uint256);
    function _totalAssets() external view returns (uint128);
    function lastUpdate() external view returns (uint64);
    function maxRate() external view returns (uint64);
    function adapters(uint256 index) external view returns (address);
    function adaptersLength() external view returns (uint256);
    function isAdapter(address account) external view returns (bool);
    function allocation(bytes32 id) external view returns (uint256);
    function absoluteCap(bytes32 id) external view returns (uint256);
    function relativeCap(bytes32 id) external view returns (uint256);
    function forceDeallocatePenalty(address adapter) external view returns (uint256);
    function liquidityAdapter() external view returns (address);
    function liquidityData() external view returns (bytes memory);
    function timelock(bytes4 selector) external view returns (uint256);
    function abdicated(bytes4 selector) external view returns (bool);
    function executableAt(bytes memory data) external view returns (uint256);
    function performanceFee() external view returns (uint96);
    function performanceFeeRecipient() external view returns (address);
    function managementFee() external view returns (uint96);
    function managementFeeRecipient() external view returns (address);

    // Gating
    function canSendShares(address account) external view returns (bool);
    function canReceiveShares(address account) external view returns (bool);
    function canSendAssets(address account) external view returns (bool);
    function canReceiveAssets(address account) external view returns (bool);

    // Multicall
    function multicall(bytes[] memory data) external;

    // Owner functions
    function setOwner(address newOwner) external;
    function setCurator(address newCurator) external;
    function setIsSentinel(address account, bool isSentinel) external;
    function setName(string memory newName) external;
    function setSymbol(string memory newSymbol) external;

    // Timelocks for curator functions
    function submit(bytes memory data) external;
    function revoke(bytes memory data) external;

    // Curator functions
    function setIsAllocator(address account, bool newIsAllocator) external;
    function setReceiveSharesGate(address newReceiveSharesGate) external;
    function setSendSharesGate(address newSendSharesGate) external;
    function setReceiveAssetsGate(address newReceiveAssetsGate) external;
    function setSendAssetsGate(address newSendAssetsGate) external;
    function setAdapterRegistry(address newAdapterRegistry) external;
    function addAdapter(address account) external;
    function removeAdapter(address account) external;
    function increaseTimelock(bytes4 selector, uint256 newDuration) external;
    function decreaseTimelock(bytes4 selector, uint256 newDuration) external;
    function abdicate(bytes4 selector) external;
    function setPerformanceFee(uint256 newPerformanceFee) external;
    function setManagementFee(uint256 newManagementFee) external;
    function setPerformanceFeeRecipient(address newPerformanceFeeRecipient) external;
    function setManagementFeeRecipient(address newManagementFeeRecipient) external;
    function increaseAbsoluteCap(bytes memory idData, uint256 newAbsoluteCap) external;
    function decreaseAbsoluteCap(bytes memory idData, uint256 newAbsoluteCap) external;
    function increaseRelativeCap(bytes memory idData, uint256 newRelativeCap) external;
    function decreaseRelativeCap(bytes memory idData, uint256 newRelativeCap) external;
    function setMaxRate(uint256 newMaxRate) external;
    function setForceDeallocatePenalty(address adapter, uint256 newForceDeallocatePenalty) external;

    // Allocator functions
    function allocate(address adapter, bytes memory data, uint256 assets) external;
    function deallocate(address adapter, bytes memory data, uint256 assets) external;
    function setLiquidityAdapterAndData(address newLiquidityAdapter, bytes memory newLiquidityData) external;

    // Exchange rate
    function accrueInterest() external;
    function accrueInterestView()
        external
        view
        returns (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares);

    // Force deallocate
    function forceDeallocate(address adapter, bytes memory data, uint256 assets, address onBehalf)
        external
        returns (uint256 penaltyShares);
}

interface IRewardsDonate {
    function donate(address vault, uint256 amount) external;
}

interface ICuratorRegistry {
    function getCurator(address vault) external view returns (address);
}

contract MockMorphoAllocatePlugin is Ownable, IPluginBase {
    using SafeERC20 for address;
    using Math for uint256;

    /* ERRORS */

    error NotCurator();
    error InvalidMorphoVault();

    /* IMMUTABLE VARIABLES */

    address public immutable REWARDS;
    address public immutable CURATOR;

    /* STATE VARIABLES */

    mapping(address vault => address morphoVault) public morphoVaults;

    mapping(address token => uint256 globalLimit) public globalLimits;

    mapping(address morphoVault => uint256 shares) totalVaultShares;
    mapping(address morphoVault => mapping(address vault => uint256 shares)) vaultShares;

    mapping(address vault => uint256 amount) internal _lastBalance;

    /* MODIFIERS */

    modifier onlyCurator(address vault) {
        if (ICuratorRegistry(CURATOR).getCurator(vault) != msg.sender) {
            revert NotCurator();
        }
        _;
    }

    /* CONSTRUCTOR */

    constructor(address rewards) Ownable(msg.sender) {
        REWARDS = rewards;
    }

    /* VIEW FUNCTIONS */

    function skimmable(address vault) public view returns (uint256) {
        address morphoVault = morphoVaults[vault];
        return _getPluginAssets(morphoVault).saturatingSub(_lastBalance[vault]);
    }

    function allocatable(address vault) public view returns (uint256) {
        address token = IVaultV2(vault).collateral();
        return globalLimits[token].saturatingSub(token.balanceOf(address(this)));
    }

    function deallocatable(address vault) public view returns (uint256) {
        address morphoVault = morphoVaults[vault];
        return Math.max(
            Math.min(_getVaultAssets(vault), IMorphoVault(morphoVault).asset().balanceOf(morphoVault)),
            IVaultV2(vault).pluginAllocated(address(this))
        );
    }

    /* PUBLIC FUNCTIONS */

    function allocate(uint256 amount) public {
        skim(msg.sender);

        address morphoVault = morphoVaults[msg.sender];

        if (amount > 0) {
            IMorphoVault(morphoVault).asset().safeApprove(address(morphoVault), amount);
            IMorphoVault(morphoVault).deposit(amount, address(this));

            vaultShares[
                morphoVault
            ][
                msg.sender
            ] += ERC4626Math.previewDeposit(amount, totalVaultShares[morphoVault], _getPluginAssets(morphoVault));

            _lastBalance[msg.sender] = _getVaultAssets(msg.sender);
        }
    }

    function deallocate(uint256 amount) public returns (uint256) {
        skim(msg.sender);

        address morphoVault = morphoVaults[msg.sender];
        uint256 deallocatableAmount = deallocatable(msg.sender);

        if (deallocatableAmount < amount) {
            amount = deallocatableAmount;
        }
        if (amount > 0) {
            IMorphoVault(morphoVault).withdraw(amount, address(this), address(this));

            _lastBalance[msg.sender] = _getVaultAssets(morphoVault);
        }

        return amount;
    }

    function skim(address vault) public returns (uint256 amount) {
        address morphoVault = morphoVaults[vault];
        address collateral = IMorphoVault(morphoVault).asset();

        amount = skimmable(vault);
        if (amount > 0) {
            IMorphoVault(morphoVault).withdraw(amount, address(this), address(this));

            collateral.safeApprove(REWARDS, amount);
            IRewardsDonate(REWARDS).donate(vault, amount);
        }
    }

    /* INTERNAL FUNCTIONS */

    function _getPluginAssets(address morphoVault) internal view returns (uint256) {
        return IMorphoVault(morphoVault).previewRedeem(morphoVault.balanceOf(address(this)));
    }

    function _getVaultAssets(address vault) internal view returns (uint256) {
        address morphoVault = morphoVaults[vault];
        return ERC4626Math.previewRedeem(
            vaultShares[morphoVault][vault], _getPluginAssets(morphoVault), totalVaultShares[morphoVault]
        );
    }

    /* CURATOR FUNCTIONS */

    function setMorhpoVault(address vault, address morphoVault) public onlyCurator(vault) {
        if (IMorphoVault(morphoVault).asset() != IVaultV2(vault).collateral()) {
            revert InvalidMorphoVault();
        }
        morphoVaults[vault] = morphoVault;
    }

    /* OWNER FUNCTIONS */

    function setGlobalLimit(address token, uint256 limit) public onlyOwner {
        globalLimits[token] = limit;
    }
}
