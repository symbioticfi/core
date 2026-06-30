// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {Test} from "forge-std/Test.sol";

import {AaveV3Adapter} from "../../src/contracts/adapters/AaveV3Adapter.sol";
import {AdapterFactory} from "../../src/contracts/adapters/AdapterFactory.sol";
import {MorphoVaultV2Adapter} from "../../src/contracts/adapters/MorphoVaultV2Adapter.sol";
import {Registry} from "../../src/contracts/common/Registry.sol";

import {IAaveV3Adapter} from "../../src/interfaces/adapters/IAaveV3Adapter.sol";
import {IMorphoVaultV2Adapter} from "../../src/interfaces/adapters/IMorphoVaultV2Adapter.sol";
import {ICoWSwapSettlement} from "../../src/interfaces/adapters/common/ICoWSwapConverter.sol";
import {IMorphoVaultV2} from "../../src/interfaces/adapters/morpho_vaultv2_adapter/IMorphoVaultV2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract AaveMorphoMainnetAccountingTest is Test {
    using stdStorage for StdStorage;

    address internal constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant MORPHO_VAULT_FACTORY = 0xA1D94F746dEfa1928926b84fB2596c06926C0405;
    address internal constant MORPHO_ADAPTER_REGISTRY = 0x3696c5eAe4a7Ffd04Ea163564571E9CD8Ed9364e;
    address internal constant DEFAULT_MORPHO_USDC_VAULT = 0x5e577eFb2807D106e2A8BDDE3fC5FCFffFC9ec13;

    address internal curator = makeAddr("curator");
    address internal delegator = makeAddr("delegator");
    address internal rewards = makeAddr("rewards");
    address internal settlement = makeAddr("settlement");
    address internal relayer = makeAddr("relayer");

    function test_AaveMainnetATokenRebaseIncreasesAdapterTotalAssets() public {
        _forkMainnet("ETH_RPC_URL is required for the Aave mainnet rebase accounting test");

        IAaveV3Adapter adapter = _deployAaveAdapter(USDC);
        uint256 amount = 10_000e6;
        deal(USDC, address(adapter), amount);

        vm.prank(delegator);
        assertEq(adapter.allocate(amount), amount);

        address aToken = adapter.aToken();
        uint256 assetsBefore = adapter.totalAssets();
        assertEq(assetsBefore, IERC20(aToken).balanceOf(address(adapter)));

        vm.warp(block.timestamp + 365 days);

        uint256 assetsAfter = adapter.totalAssets();
        uint256 aTokenBalanceAfter = IERC20(aToken).balanceOf(address(adapter));
        assertGt(aTokenBalanceAfter, assetsBefore, "aToken balance did not rebase");
        assertEq(assetsAfter, aTokenBalanceAfter);
        assertGt(assetsAfter, assetsBefore);
    }

    function test_MorphoMainnetSharePriceIncreaseIncreasesAdapterTotalAssets() public {
        _forkMainnet("ETH_RPC_URL is required for the Morpho mainnet share-price accounting test");

        address morphoVault = vm.envOr("MAINNET_MORPHO_VAULT", DEFAULT_MORPHO_USDC_VAULT);
        address asset = IERC4626(morphoVault).asset();
        IMorphoVaultV2Adapter adapter = _deployMorphoAdapter(asset, morphoVault);

        uint256 scale = 10 ** IERC20Metadata(asset).decimals();
        uint256 shares = IERC4626(morphoVault).convertToShares(1000 * scale);
        if (shares == 0) {
            vm.skip(true, "configured Morpho vault cannot quote shares for the requested assets");
        }

        stdstore.target(address(adapter)).sig(IMorphoVaultV2Adapter.totalShares.selector).checked_write(shares);

        uint256 assetsBefore = adapter.totalAssets();
        assertEq(assetsBefore, IMorphoVaultV2(morphoVault).previewRedeem(shares));

        uint256 donation = 1_000_000 * scale;
        deal(asset, morphoVault, IERC20(asset).balanceOf(morphoVault) + donation);

        uint256 expectedAssetsAfter = IMorphoVaultV2(morphoVault).previewRedeem(shares);
        assertGt(expectedAssetsAfter, assetsBefore, "Morpho vault share price did not increase");
        assertEq(adapter.totalAssets(), expectedAssetsAfter);
    }

    function _deployAaveAdapter(address asset) internal returns (IAaveV3Adapter) {
        MainnetVaultRegistryMock vaultFactory = new MainnetVaultRegistryMock();
        AdapterFactory adapterFactory = new AdapterFactory(address(this));
        MainnetAdapterVaultMock vault = new MainnetAdapterVaultMock(asset, delegator);
        vaultFactory.add(address(vault));

        vm.mockCall(settlement, abi.encodeCall(ICoWSwapSettlement.vaultRelayer, ()), abi.encode(relayer));
        AaveV3Adapter implementation =
            new AaveV3Adapter(AAVE_POOL, address(vaultFactory), address(adapterFactory), rewards, settlement);
        adapterFactory.whitelist(address(implementation));

        address[] memory converters = new address[](0);
        return IAaveV3Adapter(
            adapterFactory.create(
                1, curator, abi.encode(address(vault), abi.encode(IAaveV3Adapter.InitParams({converters: converters})))
            )
        );
    }

    function _deployMorphoAdapter(address asset, address morphoVault) internal returns (IMorphoVaultV2Adapter) {
        MainnetVaultRegistryMock vaultFactory = new MainnetVaultRegistryMock();
        AdapterFactory adapterFactory = new AdapterFactory(address(this));
        MainnetAdapterVaultMock vault = new MainnetAdapterVaultMock(asset, delegator);
        vaultFactory.add(address(vault));

        vm.mockCall(settlement, abi.encodeCall(ICoWSwapSettlement.vaultRelayer, ()), abi.encode(relayer));
        MorphoVaultV2Adapter implementation = new MorphoVaultV2Adapter(
            address(vaultFactory),
            address(adapterFactory),
            rewards,
            settlement,
            MORPHO_VAULT_FACTORY,
            MORPHO_ADAPTER_REGISTRY
        );
        adapterFactory.whitelist(address(implementation));

        address[] memory converters = new address[](0);
        return IMorphoVaultV2Adapter(
            adapterFactory.create(
                1,
                curator,
                abi.encode(
                    address(vault),
                    abi.encode(IMorphoVaultV2Adapter.InitParams({morphoVault: morphoVault, converters: converters}))
                )
            )
        );
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

contract MainnetVaultRegistryMock is Registry {
    function add(address entity) external {
        _addEntity(entity);
    }
}

contract MainnetAdapterVaultMock {
    address public immutable asset;
    address public immutable delegator;

    constructor(address asset_, address delegator_) {
        asset = asset_;
        delegator = delegator_;
    }
}
