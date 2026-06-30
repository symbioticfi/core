// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {AdapterFactory} from "../../src/contracts/adapters/AdapterFactory.sol";
import {ThreeFAdapter} from "../../src/contracts/adapters/ThreeFAdapter.sol";

import {IThreeFAdapter} from "../../src/interfaces/adapters/IThreeFAdapter.sol";
import {IThreeFRequest} from "../../src/interfaces/adapters/3f-adapter/IThreeFRequest.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct ThreeFMainnetAsset {
    address asset;
    bool isPositionManager;
}

struct ThreeFMainnetIntentProperties {
    ThreeFMainnetAsset depositAsset;
    ThreeFMainnetAsset targetAsset;
    uint256 depositCap;
    address guardKey;
    uint40 resolveStart;
    uint8 quorum;
    bool transferableIntent;
}

interface IThreeFMainnetFacility {
    function getIntent(uint256 id)
        external
        view
        returns (ThreeFMainnetIntentProperties memory properties, address fund, address request, bool resolved);
}

interface IThreeFMainnetRequest is IThreeFRequest {
    function canWithdraw() external view returns (bool status);
    function balancesOf(address account) external view returns (uint256 ptShares, uint256 ytShares);
    function totalSupplies() external view returns (uint128 ptSupply, uint128 ytSupply);
    function totalAssets() external view returns (uint256 pAssets, uint256 yAssets);
    function isRepaid() external view returns (bool status);
}

contract ThreeFAdapterMainnetAccountingTest is Test {
    address internal constant MAINNET_FACILITY = 0x4e013ca8fF612a58F53C822904cDD0eC538a4A4F;
    uint256 internal constant DEFAULT_MAINNET_INTENT_ID = 178;
    uint256 internal constant COMPLETED_MAINNET_INTENT_ID = 72;
    uint256 internal constant FALLBACK_COMPLETED_MAINNET_INTENT_ID = 195;
    bytes32 internal constant REQUEST_STORAGE_SLOT = 0xb094c22784bf6cbc6b58dc638ba7a1e443b696c9c43939e48b3762e49818c300;

    /// @dev Mainnet-fork regression for the 3F Request accounting branch used by ThreeFAdapter.totalAssets().
    function test_MainnetRequestConversionBeforeWithdrawalUsesCurrentBalanceWhenNonZero() public {
        _forkMainnet("ETH_RPC_URL is required for the 3F mainnet request accounting test");

        (,, address request,) = IThreeFMainnetFacility(MAINNET_FACILITY)
            .getIntent(vm.envOr("MAINNET_THREEF_INTENT_ID", DEFAULT_MAINNET_INTENT_ID));
        request = vm.envOr("MAINNET_THREEF_REQUEST", request);
        if (request == address(0) || request.code.length == 0) {
            vm.skip(true, "configured 3F mainnet request is not deployed");
        }

        (uint128 ptSupply, uint128 ytSupply) = IThreeFMainnetRequest(request).totalSupplies();
        if (ptSupply == 0) {
            vm.skip(true, "configured 3F mainnet request has no live principal supply");
        }
        if (IThreeFMainnetRequest(request).isRepaid()) {
            vm.skip(true, "configured 3F mainnet request is already explicitly repaid");
        }

        address asset = IThreeFRequest(request).asset();
        uint64 repaymentDeadline = _repaymentDeadline(request);
        if (repaymentDeadline <= 1) {
            vm.skip(true, "configured 3F mainnet request has no readable repayment deadline");
        }

        vm.warp(repaymentDeadline - 1);
        assertFalse(IThreeFRequest(request).canWithdraw());

        vm.mockCall(asset, abi.encodeCall(IERC20.balanceOf, (request)), abi.encode(uint256(0)));
        (uint256 zeroPrincipalAssets, uint256 zeroYieldAssets) =
            IThreeFRequest(request).convertToAssets(ptSupply, ytSupply);

        assertEq(zeroPrincipalAssets, ptSupply);
        assertEq(zeroYieldAssets, 0);

        vm.mockCall(asset, abi.encodeCall(IERC20.balanceOf, (request)), abi.encode(uint256(1)));
        (uint256 lowPrincipalAssets, uint256 lowYieldAssets) =
            IThreeFRequest(request).convertToAssets(ptSupply, ytSupply);

        assertEq(lowPrincipalAssets, 1);
        assertEq(lowYieldAssets, 0);
    }

    function test_MainnetRequestFullSupplyConversionMatchesTotalAssetsWhenWithdrawable() public {
        _forkMainnet("ETH_RPC_URL is required for the 3F mainnet request accounting test");

        (,, address request,) = IThreeFMainnetFacility(MAINNET_FACILITY)
            .getIntent(vm.envOr("MAINNET_THREEF_INTENT_ID", DEFAULT_MAINNET_INTENT_ID));
        request = vm.envOr("MAINNET_THREEF_REQUEST", request);
        if (request == address(0) || request.code.length == 0) {
            vm.skip(true, "configured 3F mainnet request is not deployed");
        }

        (uint128 ptSupply, uint128 ytSupply) = IThreeFMainnetRequest(request).totalSupplies();
        if (ptSupply == 0) {
            vm.skip(true, "configured 3F mainnet request has no live principal supply");
        }

        uint64 repaymentDeadline = _repaymentDeadline(request);
        if (!IThreeFRequest(request).canWithdraw() && repaymentDeadline > block.timestamp) {
            vm.warp(repaymentDeadline);
        }
        assertTrue(IThreeFRequest(request).canWithdraw());

        (uint256 totalPrincipalAssets, uint256 totalYieldAssets) = IThreeFMainnetRequest(request).totalAssets();
        (uint256 convertedPrincipalAssets, uint256 convertedYieldAssets) =
            IThreeFRequest(request).convertToAssets(ptSupply, ytSupply);

        assertEq(convertedPrincipalAssets, totalPrincipalAssets);
        assertEq(convertedYieldAssets, totalYieldAssets);
    }

    function test_MainnetCompletedRequestDataSimulatesAdapterAccountingTimeline() public {
        _forkMainnet("ETH_RPC_URL is required for the completed 3F request accounting simulation");

        (uint256 intentId, address request) = _findCompletedRequest();
        if (request == address(0)) {
            vm.skip(true, "no configured completed 3F mainnet request has live supply");
        }

        (uint128 ptSupply, uint128 ytSupply) = IThreeFMainnetRequest(request).totalSupplies();
        (uint256 totalPrincipalAssets, uint256 totalYieldAssets) = IThreeFMainnetRequest(request).totalAssets();
        address asset = IThreeFRequest(request).asset();

        assertEq(intentId == COMPLETED_MAINNET_INTENT_ID || intentId == FALLBACK_COMPLETED_MAINNET_INTENT_ID, true);
        assertTrue(IThreeFMainnetRequest(request).isRepaid());
        assertTrue(IThreeFRequest(request).canWithdraw());
        assertGt(ptSupply, 0);
        assertGt(totalPrincipalAssets + totalYieldAssets, 0);
        assertEq(IERC20(asset).balanceOf(request), totalPrincipalAssets + totalYieldAssets);

        address adapter = _deployAdapter(asset);
        MainnetThreeFAdapterHarness(adapter).pushRequest(request, ptSupply);

        vm.mockCall(
            request,
            abi.encodeCall(IThreeFMainnetRequest.balancesOf, (adapter)),
            abi.encode(uint256(ptSupply), uint256(ytSupply))
        );

        assertEq(IThreeFAdapter(adapter).totalAssets(), totalPrincipalAssets + totalYieldAssets);

        vm.mockCall(request, abi.encodeCall(IThreeFMainnetRequest.canWithdraw, ()), abi.encode(false));

        assertEq(IThreeFAdapter(adapter).totalAssets(), ptSupply);
    }

    function _findCompletedRequest() internal view returns (uint256 intentId, address request) {
        for (uint256 i; i < 2; ++i) {
            intentId = i == 0 ? COMPLETED_MAINNET_INTENT_ID : FALLBACK_COMPLETED_MAINNET_INTENT_ID;
            bool resolved;
            (,, request, resolved) = IThreeFMainnetFacility(MAINNET_FACILITY).getIntent(intentId);
            if (!resolved || request == address(0) || request.code.length == 0) {
                continue;
            }

            (uint128 ptSupply,) = IThreeFMainnetRequest(request).totalSupplies();
            if (ptSupply > 0 && IThreeFMainnetRequest(request).isRepaid() && IThreeFRequest(request).canWithdraw()) {
                return (intentId, request);
            }
        }

        return (0, address(0));
    }

    function _deployAdapter(address asset) internal returns (address adapter) {
        MainnetThreeFAdapterVaultFactoryMock vaultFactory = new MainnetThreeFAdapterVaultFactoryMock();
        MainnetThreeFAdapterVaultMock vault = new MainnetThreeFAdapterVaultMock(asset);
        vaultFactory.setEntity(address(vault), true);

        AdapterFactory adapterFactory = new AdapterFactory(address(this));
        adapterFactory.whitelist(
            address(new MainnetThreeFAdapterHarness(address(vaultFactory), address(adapterFactory)))
        );

        adapter = adapterFactory.create(1, address(this), abi.encode(address(vault), bytes("")));
    }

    function _repaymentDeadline(address request) internal view returns (uint64) {
        return uint64(uint256(vm.load(request, REQUEST_STORAGE_SLOT)) >> 160);
    }

    function _forkMainnet(string memory reason) internal {
        string memory rpcUrl = vm.envOr("ETH_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            vm.skip(true, reason);
        }
        uint256 forkBlock = vm.envOr("MAINNET_FORK_BLOCK", uint256(0));
        if (forkBlock == 0) {
            vm.createSelectFork(rpcUrl);
        } else {
            vm.createSelectFork(rpcUrl, forkBlock);
        }
    }
}

contract MainnetThreeFAdapterHarness is ThreeFAdapter {
    constructor(address vaultFactory, address adapterFactory)
        ThreeFAdapter(vaultFactory, adapterFactory, address(0x1234))
    {}

    function pushRequest(address request, uint256 principalAssets) external {
        requests.push(request);
        requestIndex[request] = requests.length;
        pendingAssets[request] = principalAssets;
    }
}

contract MainnetThreeFAdapterVaultFactoryMock {
    mapping(address entity => bool status) public isEntity;

    function setEntity(address entity, bool status) external {
        isEntity[entity] = status;
    }
}

contract MainnetThreeFAdapterVaultMock {
    address public immutable asset;
    address public delegator;

    constructor(address asset_) {
        asset = asset_;
    }
}
