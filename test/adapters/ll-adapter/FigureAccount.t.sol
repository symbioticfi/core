// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccountsBase.t.sol";

import {FigureAccount, FigureSubAccount} from "../../../src/contracts/adapters/ll-adapter/FigureAccount.sol";
import {FigureOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/FigureOracle.sol";
import {
    AUTO_Account,
    AUTO_AccountFactory
} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/AUTO_Account.sol";
import {IFigureAccount} from "../../../src/interfaces/adapters/ll-adapter/figure/IFigureAccount.sol";

interface ILegacyFigureFinalizeRedeem {
    function finalizeRedeem() external;
}

interface ILegacyFigureRequestRedeem {
    function requestRedeem() external;
}

contract FigureAccountTest is AccountsBase {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function testAUTOAccountFactoryConfigurationAndCloneRedemptionPath() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault wylds = new MockAsyncRedeemVault("Wrapped YLDS", "wYLDS", 6, asset, 1e6);
        MockPrimeToken autoToken = new MockPrimeToken(wylds, 125e4);
        FigureOracle oracle = new FigureOracle(1, type(uint256).max, address(autoToken));
        AUTO_AccountFactory factory = new AUTO_AccountFactory(address(this));
        FigureSubAccount subAccountImplementation = new FigureSubAccount(address(wylds), address(asset));
        AUTO_Account implementation = new AUTO_Account(
            address(oracle), address(factory), address(autoToken), address(subAccountImplementation), cowSwapSettlement
        );
        factory.whitelist(address(implementation));
        AUTO_Account account =
            AUTO_Account(factory.create(1, address(this), _initData(address(asset), address(autoToken))));

        assertEq(factory.owner(), address(this));
        assertEq(factory.implementation(1), address(implementation));
        assertEq(implementation.FACTORY(), address(factory));
        assertEq(implementation.ORACLE(), address(oracle));
        assertEq(implementation.TOKEN_TO_REDEEM(), address(autoToken));
        assertEq(account.ORACLE(), address(oracle));
        assertEq(account.TOKEN_TO_REDEEM(), address(autoToken));
        assertEq(account.COOLDOWN(), 1 days);
        assertEq(oracle.ASYNC_REDEEM_VAULT(), address(wylds));

        autoToken.mint(address(account), 100e6);
        account.sync();

        address subAccount = account.subAccounts(0);
        (uint256 pendingShares,,) = wylds.pendingRedemptions(subAccount);
        assertEq(_cloneImplementation(subAccount), address(subAccountImplementation));
        assertEq(pendingShares, 125e6);

        wylds.completeFigureRedeem(subAccount);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 125e6);
        assertEq(account.totalAssets(), 125e6);
    }

    function testFigureAccountCreatesStandardCloneSubAccount() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault wylds = new MockAsyncRedeemVault("Wrapped YLDS", "wYLDS", 6, asset, 1e6);
        MockPrimeToken prime = new MockPrimeToken(wylds, 125e4);
        FigureOracle oracle = new FigureOracle(1, type(uint256).max, address(prime));
        PRIME_Account account = _deployPrime(prime, asset, address(oracle));

        prime.mint(address(account), 100e6);
        account.sync();

        assertEq(account.subAccounts(0).code.length, 45);
    }

    function testFigureAccountCloneUsesSuppliedSubAccountImplementation() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault wylds = new MockAsyncRedeemVault("Wrapped YLDS", "wYLDS", 6, asset, 1e6);
        MockPrimeToken prime = new MockPrimeToken(wylds, 125e4);
        FigureOracle oracle = new FigureOracle(1, type(uint256).max, address(prime));
        MigratablesFactory factory = new MigratablesFactory(address(this));
        FigureSubAccount subAccountImplementation = new FigureSubAccount(address(wylds), address(asset));
        PRIME_Account implementation = new PRIME_Account(
            address(oracle), address(factory), address(prime), address(subAccountImplementation), cowSwapSettlement
        );
        factory.whitelist(address(implementation));
        PRIME_Account account =
            PRIME_Account(factory.create(1, address(this), _initData(address(asset), address(prime))));

        prime.mint(address(account), 100e6);
        account.sync();

        assertEq(_cloneImplementation(account.subAccounts(0)), address(subAccountImplementation));
    }

    function testFigureSubAccountCannotBeReinitialized() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault wylds = new MockAsyncRedeemVault("Wrapped YLDS", "wYLDS", 6, asset, 1e6);
        MockPrimeToken prime = new MockPrimeToken(wylds, 125e4);
        FigureOracle oracle = new FigureOracle(1, type(uint256).max, address(prime));
        PRIME_Account account = _deployPrime(prime, asset, address(oracle));

        prime.mint(address(account), 100e6);
        account.sync();

        address subAccount = account.subAccounts(0);
        vm.expectRevert();
        FigureSubAccount(subAccount).initialize();
    }

    function testFigureSubAccountImplementationCanBeInitializedOnce() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault wylds = new MockAsyncRedeemVault("Wrapped YLDS", "wYLDS", 6, asset, 1e6);
        FigureSubAccount implementation = new FigureSubAccount(address(wylds), address(asset));

        implementation.initialize();
        assertEq(asset.allowance(address(implementation), address(this)), type(uint256).max);

        vm.expectRevert();
        implementation.initialize();
    }

    function testFigureSubAccountDoesNotExposeRequestRedeem() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault wylds = new MockAsyncRedeemVault("Wrapped YLDS", "wYLDS", 6, asset, 1e6);
        MockPrimeToken prime = new MockPrimeToken(wylds, 125e4);
        FigureOracle oracle = new FigureOracle(1, type(uint256).max, address(prime));
        PRIME_Account account = _deployPrime(prime, asset, address(oracle));

        prime.mint(address(account), 100e6);
        account.sync();

        address subAccount = account.subAccounts(0);
        (bool success,) = subAccount.call(abi.encodeCall(ILegacyFigureRequestRedeem.requestRedeem, ()));
        assertFalse(success);
    }

    function testFigureSubAccountApprovesOnlyParentToPullRedemptionToken() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault wylds = new MockAsyncRedeemVault("Wrapped YLDS", "wYLDS", 6, asset, 1e6);
        MockPrimeToken prime = new MockPrimeToken(wylds, 125e4);
        FigureOracle oracle = new FigureOracle(1, type(uint256).max, address(prime));
        PRIME_Account account = _deployPrime(prime, asset, address(oracle));

        prime.mint(address(account), 100e6);
        account.sync();

        address subAccount = account.subAccounts(0);
        assertEq(asset.allowance(subAccount, address(account)), type(uint256).max);
        assertEq(asset.allowance(subAccount, makeAddr("notParent")), 0);
    }

    function testFigureAccountTotalAssetsUsesConvertWhenPreviewWithdrawReverts() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault wylds = new MockAsyncRedeemVault("Wrapped YLDS", "wYLDS", 6, asset, 1e6);
        MockPrimeToken prime = new MockPrimeToken(wylds, 125e4);
        FigureOracle oracle = new FigureOracle(1, type(uint256).max, address(prime));
        PRIME_Account account = _deployPrime(prime, asset, address(oracle));

        wylds.mint(address(account), 125e6);
        wylds.setRevertPreviewWithdraw(true);

        assertEq(account.totalAssets(), 125e6);
    }

    function testFigureAccountInstantRedeemsPrimeThenRequestsWyldsRedeem() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault wylds = new MockAsyncRedeemVault("Wrapped YLDS", "wYLDS", 6, asset, 1e6);
        MockPrimeToken prime = new MockPrimeToken(wylds, 125e4);
        FigureOracle oracle = new FigureOracle(1, type(uint256).max, address(prime));
        PRIME_Account account = _deployPrime(prime, asset, address(oracle));

        prime.mint(address(account), 100e6);

        assertEq(account.totalAssets(), 125e6);

        account.sync();

        address subAccount = account.subAccounts(0);

        assertEq(prime.balanceOf(address(account)), 0);
        assertEq(wylds.balanceOf(address(wylds)), 125e6);
        assertEq(wylds.balanceOf(subAccount), 0);
        assertEq(account.totalAssets(), 125e6);

        wylds.completeFigureRedeem(subAccount);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 125e6);
        assertEq(account.totalAssets(), 125e6);
    }

    function testFigureAccountCreatesSubAccountPerCloseRequest() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault wylds = new MockAsyncRedeemVault("Wrapped YLDS", "wYLDS", 6, asset, 1e6);
        MockPrimeToken prime = new MockPrimeToken(wylds, 125e4);
        FigureOracle oracle = new FigureOracle(1, type(uint256).max, address(prime));
        PRIME_Account account = _deployPrime(prime, asset, address(oracle));

        prime.mint(address(account), 100e6);
        account.sync();

        address firstSubAccount = account.subAccounts(0);

        prime.mint(address(account), 40e6);
        account.sync();

        address secondSubAccount = account.subAccounts(1);

        (uint256 firstShares, uint256 firstAssets,) = wylds.pendingRedemptions(firstSubAccount);
        (uint256 secondShares, uint256 secondAssets,) = wylds.pendingRedemptions(secondSubAccount);
        assertNotEq(secondSubAccount, firstSubAccount);
        assertEq(firstShares, 125e6);
        assertEq(firstAssets, 125e6);
        assertEq(secondShares, 50e6);
        assertEq(secondAssets, 50e6);
        assertEq(account.totalAssets(), 175e6);

        wylds.completeFigureRedeem(firstSubAccount);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 125e6);
        assertEq(account.subAccounts(0), secondSubAccount);
        assertEq(account.totalAssets(), 175e6);

        wylds.completeFigureRedeem(secondSubAccount);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 175e6);
        vm.expectRevert();
        account.subAccounts(0);
        assertEq(account.totalAssets(), 175e6);
    }

    function testFigureAccountDoesNotPruneActiveZeroAssetRequest() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault wylds = new MockAsyncRedeemVault("Wrapped YLDS", "wYLDS", 6, asset, 0);
        MockPrimeToken prime = new MockPrimeToken(wylds, 1e6);
        FigureOracle oracle = new FigureOracle(1, type(uint256).max, address(prime));
        PRIME_Account account = _deployPrime(prime, asset, address(oracle));

        prime.mint(address(account), 1e6);
        account.sync();

        address subAccount = account.subAccounts(0);
        (, uint256 pendingAssets,) = wylds.pendingRedemptions(subAccount);
        assertEq(pendingAssets, 0);

        account.sync();

        assertEq(account.subAccounts(0), subAccount);
    }

    function testFigureSubAccountDoesNotExposeFinalizeRedeem() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault wylds = new MockAsyncRedeemVault("Wrapped YLDS", "wYLDS", 6, asset, 1e6);
        MockPrimeToken prime = new MockPrimeToken(wylds, 125e4);
        FigureOracle oracle = new FigureOracle(1, type(uint256).max, address(prime));
        PRIME_Account account = _deployPrime(prime, asset, address(oracle));

        prime.mint(address(account), 100e6);
        account.sync();

        address subAccount = account.subAccounts(0);

        (bool success,) = subAccount.staticcall(abi.encodeCall(ILegacyTotalAssets.totalAssets, ()));
        assertFalse(success);

        wylds.completeFigureRedeem(subAccount);

        vm.prank(address(account));
        (success,) = subAccount.call(abi.encodeCall(ILegacyFigureFinalizeRedeem.finalizeRedeem, ()));
        assertFalse(success);

        account.sync();

        assertEq(asset.balanceOf(address(account)), 125e6);
    }

    function testFigureAccountSupportsDifferentStableAssetAndCountsSettledRedemptionToken() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 usdt = new MockERC20("Tether USD", "USDT", 6);
        MockAsyncRedeemVault wylds = new MockAsyncRedeemVault("Wrapped YLDS", "wYLDS", 6, usdc, 1e6);
        MockPrimeToken prime = new MockPrimeToken(wylds, 125e4);
        FigureOracle oracle = new FigureOracle(1, type(uint256).max, address(prime));
        PRIME_Account account = _deployPrime(prime, usdt, address(oracle));

        prime.mint(address(account), 100e6);
        assertEq(account.totalAssets(), 125e6);

        account.sync();
        address subAccount = account.subAccounts(0);

        assertEq(account.totalAssets(), 125e6);

        wylds.completeFigureRedeem(subAccount);
        account.sync();

        assertEq(usdc.balanceOf(address(account)), 125e6);
        assertEq(usdt.balanceOf(address(account)), 0);
        assertEq(account.totalAssets(), 125e6);
    }

    function _cloneImplementation(address clone) internal view returns (address implementation) {
        assembly {
            let pointer := mload(0x40)
            extcodecopy(clone, pointer, 10, 20)
            implementation := shr(96, mload(pointer))
        }
    }
}
