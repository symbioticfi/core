// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {WeETHOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/WeETHOracle.sol";
import {WstETHOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/WstETHOracle.sol";
import {weETH_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/weETH_Account.sol";
import {wstETH_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/wstETH_Account.sol";
import {
    IEtherFiRedemptionManager
} from "../../../src/interfaces/adapters/ll-adapter/etherfi/IEtherFiRedemptionManager.sol";

contract EthNativeOraclesMainnetTest is Test {
    uint256 internal constant PINNED_FORK_BLOCK = 25_675_677;

    address internal constant COW_SWAP_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address internal constant EETH = 0x35fA164735182de50811E8e2E824cFb9B6118ac2;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address internal constant ETHERFI_LIQUIDITY_POOL = 0x308861A430be4cce5502d0A12724771Fc6DaF216;
    address internal constant ETHERFI_REDEMPTION_MANAGER = 0xDadEf1fFBFeaAB4f68A9fD181395F68b4e4E7Ae0;
    address internal constant ETHERFI_WITHDRAW_REQUEST_NFT = 0x7d5706f6ef3F89B3951E23e557CDFBC3239D4E2c;

    address internal constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant LIDO_WITHDRAWAL_QUEUE = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;

    string internal mainnetRpcUrl;

    function setUp() public {
        mainnetRpcUrl = vm.envOr("ETH_RPC_URL", string(""));
    }

    function testWeETHAccountBindsLiveMainnetTopologyAndRate() public {
        uint256 forkBlock = _forkMainnet();

        weETH_Account implementation = new weETH_Account(makeAddr("factory"), COW_SWAP_SETTLEMENT);
        WeETHOracle oracle = WeETHOracle(implementation.ORACLE());

        assertGt(EETH.code.length, 0);
        assertGt(WETH.code.length, 0);
        assertGt(WEETH.code.length, 0);
        assertGt(ETHERFI_LIQUIDITY_POOL.code.length, 0);
        assertGt(ETHERFI_REDEMPTION_MANAGER.code.length, 0);
        assertGt(ETHERFI_WITHDRAW_REQUEST_NFT.code.length, 0);

        assertEq(implementation.EETH(), EETH);
        assertEq(implementation.WETH(), WETH);
        assertEq(implementation.TOKEN_TO_REDEEM(), WEETH);
        assertEq(implementation.LIQUIDITY_POOL(), ETHERFI_LIQUIDITY_POOL);
        assertEq(implementation.REDEMPTION_MANAGER(), ETHERFI_REDEMPTION_MANAGER);
        assertEq(implementation.WITHDRAW_REQUEST_NFT(), ETHERFI_WITHDRAW_REQUEST_NFT);
        assertEq(oracle.WEETH(), WEETH);
        assertEq(oracle.MIN_PRICE(), 0.5e18);
        assertEq(oracle.MAX_PRICE(), 2.5e18);
        IEtherFiRedemptionManager redemptionManager = IEtherFiRedemptionManager(implementation.REDEMPTION_MANAGER());
        IEtherFiRedemptionManager.BucketLimit memory limit;
        (limit,,,) = redemptionManager.tokenToRedemptionInfo(redemptionManager.ETH_ADDRESS());
        assertGt(limit.capacity, 0);
        _assertLiveRate(oracle.getPrice(), 1.100671697449813541e18, forkBlock);
    }

    function testWstETHAccountBindsLiveMainnetTopologyAndRate() public {
        uint256 forkBlock = _forkMainnet();

        wstETH_Account implementation = new wstETH_Account(makeAddr("factory"), COW_SWAP_SETTLEMENT);
        WstETHOracle oracle = WstETHOracle(implementation.ORACLE());

        assertGt(STETH.code.length, 0);
        assertGt(WETH.code.length, 0);
        assertGt(WSTETH.code.length, 0);
        assertGt(LIDO_WITHDRAWAL_QUEUE.code.length, 0);

        assertEq(implementation.STETH(), STETH);
        assertEq(implementation.WETH(), WETH);
        assertEq(implementation.WSTETH(), WSTETH);
        assertEq(implementation.TOKEN_TO_REDEEM(), WSTETH);
        assertEq(implementation.WITHDRAWAL_QUEUE(), LIDO_WITHDRAWAL_QUEUE);
        assertEq(oracle.WSTETH(), WSTETH);
        assertEq(oracle.MIN_PRICE(), 0.5e18);
        assertEq(oracle.MAX_PRICE(), 2.5e18);
        _assertLiveRate(oracle.getPrice(), 1.240847166477700567e18, forkBlock);
    }

    function _forkMainnet() internal returns (uint256 forkBlock) {
        if (bytes(mainnetRpcUrl).length == 0) {
            vm.skip(true, "ETH_RPC_URL is required for ETH-native mainnet checks");
        }
        forkBlock = vm.envOr("MAINNET_FORK_BLOCK", uint256(0));
        if (forkBlock == 0) {
            vm.createSelectFork(mainnetRpcUrl);
            forkBlock = block.number;
        } else {
            vm.createSelectFork(mainnetRpcUrl, forkBlock);
        }
    }

    function _assertLiveRate(uint256 rate, uint256 pinnedRate, uint256 forkBlock) internal pure {
        if (forkBlock == PINNED_FORK_BLOCK) {
            assertApproxEqAbs(rate, pinnedRate, 1e12);
            return;
        }
        assertGt(rate, 1e18);
        assertGe(rate, 0.5e18);
        assertLe(rate, 2.5e18);
    }
}
