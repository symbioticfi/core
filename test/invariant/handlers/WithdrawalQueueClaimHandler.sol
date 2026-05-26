// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {WithdrawalQueue} from "../../../src/contracts/vault/WithdrawalQueue.sol";
import {WithdrawalQueueFactory} from "../../../src/contracts/vault/WithdrawalQueueFactory.sol";

import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract WithdrawalQueueInvariantToken is ERC20 {
    constructor() ERC20("Token", "TKN") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract WithdrawalQueueInvariantDelegator {
    function onWithdrawRequest() external {}

    function sweepPending() external pure returns (uint256) {
        return 0;
    }
}

contract WithdrawalQueueInvariantVault is ERC20 {
    using Math for uint256;

    address public immutable collateral;
    address public delegator;
    uint256 public managedAssets;
    uint256 public virtualSharesValue = 1;

    constructor(address collateral_) ERC20("Vault Share", "vTKN") {
        collateral = collateral_;
    }

    function setDelegator(address delegator_) external {
        delegator = delegator_;
    }

    function mintShares(address account, uint256 shares, uint256 assets) external {
        _mint(account, shares);
        managedAssets += assets;
        WithdrawalQueueInvariantToken(collateral).mint(address(this), assets);
    }

    function increaseAssets(uint256 assets) external {
        managedAssets += assets;
        WithdrawalQueueInvariantToken(collateral).mint(address(this), assets);
    }

    function decreaseAssets(uint256 assets) external {
        managedAssets -= assets;
    }

    function reduceLiquidity(uint256 assets) external {
        WithdrawalQueueInvariantToken token = WithdrawalQueueInvariantToken(collateral);
        token.transfer(address(0xDEAD), Math.min(assets, token.balanceOf(address(this))));
    }

    function asset() external view returns (address) {
        return collateral;
    }

    function virtualShares() external view returns (uint256) {
        return virtualSharesValue;
    }

    function totalAssets() external view returns (uint256) {
        return managedAssets;
    }

    function previewRedeem(uint256 shares) external view returns (uint256) {
        return shares.mulDiv(managedAssets + 1, totalSupply() + virtualSharesValue);
    }

    function previewDeposit(uint256 assets) external view returns (uint256) {
        return managedAssets == 0 ? 0 : assets.mulDiv(totalSupply() + virtualSharesValue, managedAssets + 1);
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        return totalSupply() == 0 ? 0 : shares.mulDiv(managedAssets, totalSupply());
    }

    function maxRedeem(address owner) external view returns (uint256) {
        uint256 byLiquidity = managedAssets == 0
            ? 0
            : WithdrawalQueueInvariantToken(collateral).balanceOf(address(this)).mulDiv(totalSupply(), managedAssets);
        return Math.min(balanceOf(owner), byLiquidity);
    }

    function withdrawable() external view returns (uint256) {
        return WithdrawalQueueInvariantToken(collateral).balanceOf(address(this));
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        assets = shares.mulDiv(managedAssets + 1, totalSupply() + virtualSharesValue);
        _burn(owner, shares);
        managedAssets -= assets;
        WithdrawalQueueInvariantToken(collateral).transfer(receiver, assets);
    }
}

contract WithdrawalQueueHarness is WithdrawalQueue {
    using Checkpoints for Checkpoints.Trace256;

    constructor(address factory) WithdrawalQueue(factory) {}

    function nextTokenId() public view returns (uint256) {
        return _nextTokenId;
    }

    function checkpointLength() public view returns (uint256) {
        return _cumulSharesToCumulAssets.length();
    }

    function checkpointAt(uint32 i) public view returns (uint256 key, uint256 cumulAssets, uint32 packedIndex) {
        Checkpoints.Checkpoint256 memory checkpoint = _cumulSharesToCumulAssets.at(i);
        key = checkpoint._key;
        cumulAssets = uint224(checkpoint._value);
        packedIndex = uint32(checkpoint._value >> 224);
    }

    function latestCumulAssets() public view returns (uint256) {
        return uint224(_cumulSharesToCumulAssets.latest());
    }
}

contract WithdrawalQueueClaimHandler is Test {
    using Math for uint256;

    struct RequestModel {
        uint256 shares;
        uint256 claimedShares;
        uint256 prevRequestSum;
        uint256 claimedAssets;
        address owner;
    }

    uint256 internal constant MAX_REQUEST_SHARES = 1e18;
    uint256 internal constant MAX_ASSET_CHANGE = 10e18;

    WithdrawalQueueInvariantToken public collateral;
    WithdrawalQueueInvariantVault public vault;
    WithdrawalQueueInvariantDelegator public delegator;
    WithdrawalQueueHarness public queue;

    uint256 public modelTotalRequested;
    uint256 public modelTotalFilled;
    uint256 public modelFilledAssets;
    uint256 public modelClaimedAssets;

    address[] internal _actors;
    RequestModel[] internal _requests;
    uint256[] internal _cumulShares;
    uint256[] internal _cumulAssets;

    constructor() {
        collateral = new WithdrawalQueueInvariantToken();
        vault = new WithdrawalQueueInvariantVault(address(collateral));
        delegator = new WithdrawalQueueInvariantDelegator();
        vault.setDelegator(address(delegator));

        WithdrawalQueueFactory factory = new WithdrawalQueueFactory(address(this));
        factory.whitelist(address(new WithdrawalQueueHarness(address(factory))));
        queue = WithdrawalQueueHarness(factory.create(1, address(vault), abi.encode(vault.name(), vault.symbol())));

        _actors.push(address(0xA11CE));
        _actors.push(address(0xB0B));
        _actors.push(address(0xCAFE));
        _actors.push(address(0xD00D));
    }

    function request(uint256 actorSeed, uint256 sharesSeed) external {
        address actor = _actor(actorSeed);
        uint256 shares = bound(sharesSeed, 1, MAX_REQUEST_SHARES);

        vault.mintShares(actor, shares, shares);

        vm.startPrank(actor);
        vault.approve(address(queue), shares);
        uint256 tokenId = queue.requestRedeem(shares, actor);
        vm.stopPrank();

        _requests.push(
            RequestModel({
                shares: shares, claimedShares: 0, prevRequestSum: modelTotalRequested, claimedAssets: 0, owner: actor
            })
        );
        assertEq(tokenId, _requests.length - 1);
        modelTotalRequested += shares;
    }

    function increaseAssets(uint256 assetsSeed) external {
        uint256 assets = bound(assetsSeed, 0, MAX_ASSET_CHANGE);
        vault.increaseAssets(assets);
    }

    function decreaseAssets(uint256 assetsSeed) external {
        uint256 managedAssets = vault.managedAssets();
        if (managedAssets == 0) {
            return;
        }

        vault.decreaseAssets(bound(assetsSeed, 0, managedAssets));
    }

    function reduceLiquidity(uint256 assetsSeed) external {
        uint256 balance = collateral.balanceOf(address(vault));
        if (balance == 0) {
            return;
        }

        vault.reduceLiquidity(bound(assetsSeed, 0, balance));
    }

    function fill() external {
        if (queue.pendingShares() == 0) {
            return;
        }

        uint256 totalFilledBefore = queue.totalFilled();
        uint256 pendingSharesBefore = queue.pendingShares();
        uint256 withdrawableBefore = vault.withdrawable();
        uint256 expectedMaxFilledShares = Math.min(pendingSharesBefore, vault.previewDeposit(withdrawableBefore));
        uint256 queueBalanceBefore = collateral.balanceOf(address(queue));

        (uint256 assetsReceived, uint256 shares) = queue.fill();

        assertLe(assetsReceived, withdrawableBefore);
        assertEq(assetsReceived, collateral.balanceOf(address(queue)) - queueBalanceBefore);
        assertEq(shares, queue.totalFilled() - totalFilledBefore);
        assertEq(shares, expectedMaxFilledShares);
        if (shares == 0) {
            assertEq(assetsReceived, 0);
            assertEq(queue.totalFilled(), modelTotalFilled);
            return;
        }

        modelFilledAssets += collateral.balanceOf(address(queue)) - queueBalanceBefore;
        modelTotalFilled += shares;
        _cumulShares.push(modelTotalFilled);
        _cumulAssets.push(modelFilledAssets);
        assertEq(queue.totalFilled(), modelTotalFilled);
        assertEq(queue.pendingAssets(), vault.previewRedeem(queue.pendingShares()));
    }

    function claim(uint256 tokenSeed) external {
        _claim(tokenSeed);
    }

    function transferPosition(uint256 tokenSeed, uint256 actorSeed) external {
        if (_requests.length == 0) {
            return;
        }

        uint256 tokenId = tokenSeed % _requests.length;
        address from = queue.ownerOf(tokenId);
        address to = _actor(actorSeed);
        if (from == to) {
            return;
        }

        vm.prank(from);
        queue.transferFrom(from, to, tokenId);
        _requests[tokenId].owner = to;
    }

    function assertClaimableMatchesModel() external {
        assertEq(queue.totalRequested(), modelTotalRequested);
        assertEq(queue.totalFilled(), modelTotalFilled);
        assertEq(queue.pendingShares(), modelTotalRequested - modelTotalFilled);

        uint256 requestClaimedAssets;
        uint256 requestClaimableAssets;
        uint256 requestAccountedShares;
        for (uint256 tokenId; tokenId < _requests.length; ++tokenId) {
            (uint256 expectedAssets, uint256 expectedShares) = modelClaimable(tokenId);
            (uint256 actualAssets, uint256 actualShares) = queue.claimable(tokenId);
            (, uint256 actualClaimedShares,) = queue.requests(tokenId);

            assertEq(actualAssets, expectedAssets);
            assertEq(actualShares, expectedShares);
            assertEq(actualClaimedShares, _requests[tokenId].claimedShares);
            assertEq(queue.ownerOf(tokenId), _requests[tokenId].owner);
            requestClaimedAssets += _requests[tokenId].claimedAssets;
            requestClaimableAssets += actualAssets;
            requestAccountedShares += _requests[tokenId].claimedShares + actualShares;
        }
        assertEq(requestClaimedAssets, modelClaimedAssets);
        assertLe(requestClaimableAssets, collateral.balanceOf(address(queue)));
        assertLe(requestClaimedAssets + requestClaimableAssets, modelFilledAssets);
        assertLe(requestAccountedShares, modelTotalFilled);
    }

    function assertShareConservationAndRequestLedger() external view {
        uint256 requested = queue.totalRequested();
        uint256 filled = queue.totalFilled();
        uint256 nextTokenId = queue.nextTokenId();

        assertEq(requested, modelTotalRequested);
        assertEq(filled, modelTotalFilled);
        assertLe(filled, requested);
        assertEq(queue.pendingShares(), requested - filled);
        assertEq(vault.balanceOf(address(queue)), queue.pendingShares());
        assertEq(nextTokenId, _requests.length);

        uint256 running;
        uint256 totalFilledAllocated;
        uint256 totalClaimedShares;
        uint256 totalClaimableShares;
        for (uint256 tokenId; tokenId < nextTokenId; ++tokenId) {
            (uint256 shares, uint256 claimedShares, uint256 prevRequestSum) = queue.requests(tokenId);

            assertEq(prevRequestSum, running);
            assertGt(shares, 0);
            assertLe(claimedShares, shares);
            assertEq(shares, _requests[tokenId].shares);
            assertEq(claimedShares, _requests[tokenId].claimedShares);
            assertEq(prevRequestSum, _requests[tokenId].prevRequestSum);

            uint256 filledAfterPrev = filled > prevRequestSum ? filled - prevRequestSum : 0;
            uint256 filledForRequest = Math.min(filledAfterPrev, shares);
            (, uint256 claimableShares) = queue.claimable(tokenId);

            assertLe(claimedShares, filledForRequest);
            assertEq(claimableShares, filledForRequest - claimedShares);

            running += shares;
            totalFilledAllocated += filledForRequest;
            totalClaimedShares += claimedShares;
            totalClaimableShares += claimableShares;
        }

        assertEq(running, requested);
        assertEq(totalFilledAllocated, filled);
        assertEq(totalClaimedShares + totalClaimableShares, filled);
    }

    function assertClaimableAssetsBackedByQueueBalance() external view {
        uint256 sumClaimableAssets;
        for (uint256 tokenId; tokenId < _requests.length; ++tokenId) {
            (uint256 assets,) = queue.claimable(tokenId);
            sumClaimableAssets += assets;
        }

        assertEq(sumClaimableAssets, collateral.balanceOf(address(queue)));
        assertEq(collateral.balanceOf(address(queue)), modelFilledAssets - modelClaimedAssets);
    }

    function assertCheckpointsMatchFillModel() external view {
        uint256 length = queue.checkpointLength();

        assertEq(length, _cumulShares.length + 1);
        assertGe(length, 1);
        assertLe(length, uint256(type(uint32).max));

        uint256 lastKey;
        uint256 lastAssets;
        for (uint32 i; i < length; ++i) {
            (uint256 key, uint256 cumulAssets, uint32 packedIndex) = queue.checkpointAt(i);

            assertEq(packedIndex, i);
            if (i == 0) {
                assertEq(key, 0);
                assertEq(cumulAssets, 0);
            } else {
                assertGt(key, lastKey);
                assertGe(cumulAssets, lastAssets);
                assertEq(key, _cumulShares[i - 1]);
                assertEq(cumulAssets, _cumulAssets[i - 1]);
            }
            assertLe(key, queue.totalRequested());

            lastKey = key;
            lastAssets = cumulAssets;
        }

        assertEq(lastKey, queue.totalFilled());
        assertEq(queue.latestCumulAssets(), modelFilledAssets);
    }

    function assertActorBalancesMatchClaims() external view {
        uint256 actorBalance;
        for (uint256 i; i < _actors.length; ++i) {
            actorBalance += collateral.balanceOf(_actors[i]);
        }

        assertEq(actorBalance, modelClaimedAssets);
        assertLe(modelClaimedAssets, modelFilledAssets);
        assertEq(collateral.balanceOf(address(queue)), modelFilledAssets - modelClaimedAssets);
    }

    function modelClaimable(uint256 tokenId) public view returns (uint256 assetsClaimed, uint256 sharesClaimed) {
        return _modelClaimable(tokenId);
    }

    function requestCount() external view returns (uint256) {
        return _requests.length;
    }

    function _claim(uint256 tokenSeed) internal {
        if (_requests.length == 0) {
            return;
        }

        uint256 tokenId = tokenSeed % _requests.length;
        (uint256 expectedAssets, uint256 expectedShares) = _modelClaimable(tokenId);

        address owner = queue.ownerOf(tokenId);
        uint256 ownerBalanceBefore = collateral.balanceOf(owner);
        uint256 queueBalanceBefore = collateral.balanceOf(address(queue));

        (uint256 assetsClaimed, uint256 sharesClaimed) = queue.claim(tokenId);
        uint256 assetsPaidOut = queueBalanceBefore - collateral.balanceOf(address(queue));

        assertEq(assetsClaimed, expectedAssets);
        assertEq(sharesClaimed, expectedShares);
        assertEq(assetsPaidOut, assetsClaimed);
        assertEq(collateral.balanceOf(owner), ownerBalanceBefore + expectedAssets);
        (, uint256 actualClaimedShares,) = queue.requests(tokenId);

        _requests[tokenId].claimedShares += sharesClaimed;
        _requests[tokenId].claimedAssets += assetsPaidOut;
        modelClaimedAssets += assetsPaidOut;

        assertLe(modelClaimedAssets, modelFilledAssets);
        assertEq(actualClaimedShares, _requests[tokenId].claimedShares);
    }

    function _modelClaimable(uint256 tokenId) internal view returns (uint256 assetsClaimed, uint256 sharesClaimed) {
        RequestModel storage requestModel = _requests[tokenId];

        uint256 start = requestModel.prevRequestSum + requestModel.claimedShares;
        uint256 end = Math.min(requestModel.prevRequestSum + requestModel.shares, modelTotalFilled);
        if (end <= start) {
            return (0, 0);
        }

        assetsClaimed = _assetsAt(end) - _assetsAt(start);
        sharesClaimed = end - start;
    }

    function _assetsAt(uint256 sharePos) internal view returns (uint256) {
        if (sharePos == 0) {
            return 0;
        }

        uint256 length = _cumulShares.length;
        if (length == 0) {
            return 0;
        }

        if (sharePos >= modelTotalFilled) {
            return _cumulAssets[length - 1];
        }

        uint256 lo;
        uint256 hi = length - 1;
        while (lo < hi) {
            uint256 mid = (lo + hi) >> 1;
            if (_cumulShares[mid] < sharePos) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }

        uint256 prevShares;
        uint256 prevAssets;
        if (lo != 0) {
            prevShares = _cumulShares[lo - 1];
            prevAssets = _cumulAssets[lo - 1];
        }

        return prevAssets + (sharePos - prevShares).mulDiv(_cumulAssets[lo] - prevAssets, _cumulShares[lo] - prevShares);
    }

    function _actor(uint256 actorSeed) internal view returns (address) {
        return _actors[actorSeed % _actors.length];
    }
}
