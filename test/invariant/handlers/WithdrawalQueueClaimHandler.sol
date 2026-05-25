// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {WithdrawalQueue} from "../../../src/contracts/vault/WithdrawalQueue.sol";

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
        return totalSupply() == 0 ? 0 : shares.mulDiv(managedAssets, totalSupply());
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
        assets = shares.mulDiv(managedAssets, totalSupply());
        _burn(owner, shares);
        managedAssets -= assets;
        WithdrawalQueueInvariantToken(collateral).transfer(receiver, assets);
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

    struct PriceCheckpoint {
        uint256 totalAssets;
        uint256 totalShares;
    }

    uint256 internal constant MAX_REQUEST_SHARES = 1e18;
    uint256 internal constant MAX_ASSET_CHANGE = 10e18;
    uint256 internal constant SHARE_PRICE_TOLERANCE_DECIMALS = 7;

    WithdrawalQueueInvariantToken public collateral;
    WithdrawalQueueInvariantVault public vault;
    WithdrawalQueueInvariantDelegator public delegator;
    WithdrawalQueue public queue;

    uint256 public modelTotalRequested;
    uint256 public modelTotalFilled;
    uint256 public modelFilledAssets;
    uint256 public modelClaimedAssets;

    address[] internal _actors;
    RequestModel[] internal _requests;
    PriceCheckpoint[] internal _checkpoints;
    uint256[] internal _checkpointKeys;

    constructor() {
        collateral = new WithdrawalQueueInvariantToken();
        vault = new WithdrawalQueueInvariantVault(address(collateral));
        delegator = new WithdrawalQueueInvariantDelegator();
        vault.setDelegator(address(delegator));

        queue = new WithdrawalQueue();
        vm.prank(address(vault));
        queue.initialize();

        _actors.push(address(0xA11CE));
        _actors.push(address(0xB0B));
        _actors.push(address(0xCAFE));
        _actors.push(address(0xD00D));

        _checkpoints.push(PriceCheckpoint({totalAssets: 1, totalShares: vault.virtualShares()}));
    }

    function request(uint256 actorSeed, uint256 sharesSeed) external {
        address actor = _actor(actorSeed);
        uint256 shares = bound(sharesSeed, 1, MAX_REQUEST_SHARES);

        vault.mintShares(actor, shares, shares);

        vm.startPrank(actor);
        vault.approve(address(queue), shares);
        uint256 tokenId = queue.requestWithdraw(shares, actor);
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
        PriceCheckpoint memory checkpoint = _checkpointForNextFill();

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

        if (_shouldPushCheckpoint(checkpoint)) {
            _checkpointKeys.push(modelTotalFilled);
            _checkpoints.push(checkpoint);
        }

        modelFilledAssets += collateral.balanceOf(address(queue)) - queueBalanceBefore;
        modelTotalFilled += shares;
        assertEq(queue.totalFilled(), modelTotalFilled);
        assertEq(queue.pendingAssets(), vault.previewRedeem(queue.pendingShares()));
    }

    function claim(uint256 tokenSeed) external {
        _claim(tokenSeed, type(uint256).max);
    }

    function claimLimited(uint256 tokenSeed, uint256 maxIterationsSeed) external {
        _claim(tokenSeed, bound(maxIterationsSeed, 0, 3));
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
            (uint256 actualAssets, uint256 actualShares) = queue.claimable(tokenId, type(uint256).max);
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
        return _modelClaimable(tokenId, type(uint256).max);
    }

    function requestCount() external view returns (uint256) {
        return _requests.length;
    }

    function _claim(uint256 tokenSeed, uint256 maxIterations) internal {
        if (_requests.length == 0) {
            return;
        }

        uint256 tokenId = tokenSeed % _requests.length;
        (uint256 expectedAssets, uint256 expectedShares) = _modelClaimable(tokenId, maxIterations);

        address owner = queue.ownerOf(tokenId);
        uint256 ownerBalanceBefore = collateral.balanceOf(owner);

        (uint256 assetsClaimed, uint256 sharesClaimed) = queue.claim(tokenId, maxIterations);

        assertEq(assetsClaimed, expectedAssets);
        assertEq(sharesClaimed, expectedShares);
        assertEq(collateral.balanceOf(owner), ownerBalanceBefore + expectedAssets);
        (, uint256 actualClaimedShares,) = queue.requests(tokenId);

        _requests[tokenId].claimedShares += sharesClaimed;
        _requests[tokenId].claimedAssets += assetsClaimed;
        modelClaimedAssets += assetsClaimed;

        assertLe(modelClaimedAssets, modelFilledAssets);
        assertEq(actualClaimedShares, _requests[tokenId].claimedShares);
    }

    function _modelClaimable(uint256 tokenId, uint256 maxIterations)
        internal
        view
        returns (uint256 assetsClaimed, uint256 sharesClaimed)
    {
        RequestModel storage requestModel = _requests[tokenId];

        uint256 claimStart = requestModel.prevRequestSum + requestModel.claimedShares;
        uint256 maxSharesToClaim =
            Math.min(requestModel.shares - requestModel.claimedShares, modelTotalFilled.saturatingSub(claimStart));
        uint256 cumClaimedShares = claimStart;
        uint256 checkpointIndex = _checkpointIndex(cumClaimedShares);

        while (maxSharesToClaim > 0 && maxIterations > 0) {
            --maxIterations;
            uint256 curRequestShares = maxSharesToClaim;
            if (_checkpointKeys.length > checkpointIndex) {
                curRequestShares = Math.min(_checkpointKeys[checkpointIndex] - cumClaimedShares, maxSharesToClaim);
            }

            PriceCheckpoint storage checkpoint = _checkpoints[checkpointIndex++];
            assetsClaimed += curRequestShares.mulDiv(
                checkpoint.totalAssets + 1, checkpoint.totalShares + vault.virtualShares()
            );
            cumClaimedShares += curRequestShares;
            maxSharesToClaim -= curRequestShares;
        }

        sharesClaimed = cumClaimedShares - claimStart;
    }

    function _checkpointForNextFill() internal view returns (PriceCheckpoint memory) {
        return PriceCheckpoint({totalAssets: vault.managedAssets(), totalShares: vault.totalSupply()});
    }

    function _shouldPushCheckpoint(PriceCheckpoint memory checkpoint) internal view returns (bool) {
        PriceCheckpoint storage lastCheckpoint = _checkpoints[_checkpoints.length - 1];

        uint256 sharePriceScale = 10 ** vault.decimals();
        uint256 virtualShares = vault.virtualShares();
        uint256 lastSharePrice =
            sharePriceScale.mulDiv(lastCheckpoint.totalAssets + 1, lastCheckpoint.totalShares + virtualShares);
        uint256 newSharePrice =
            sharePriceScale.mulDiv(checkpoint.totalAssets + 1, checkpoint.totalShares + virtualShares);

        if (newSharePrice < lastSharePrice) {
            return true;
        }

        return newSharePrice - lastSharePrice
            >= 10 ** uint256(collateral.decimals()).saturatingSub(SHARE_PRICE_TOLERANCE_DECIMALS);
    }

    function _checkpointIndex(uint256 sharePosition) internal view returns (uint256 index) {
        for (uint256 i; i < _checkpointKeys.length; ++i) {
            if (_checkpointKeys[i] > sharePosition) {
                break;
            }
            index = i + 1;
        }
    }

    function _actor(uint256 actorSeed) internal view returns (address) {
        return _actors[actorSeed % _actors.length];
    }
}
