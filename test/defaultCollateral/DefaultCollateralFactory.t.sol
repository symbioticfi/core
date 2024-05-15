// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {DefaultCollateralFactory} from "src/contracts/defaultCollateral/DefaultCollateralFactory.sol";
import {DefaultCollateral} from "src/contracts/defaultCollateral/DefaultCollateral.sol";

import {Token} from "test/mocks/Token.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract DefaultCollateralFactoryTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    DefaultCollateralFactory defaultCollateralFactory;
    DefaultCollateral defaultCollateral;

    IERC20 token;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        token = IERC20(new Token("Token"));
    }

    function test_Create(uint256 initialLimit, address limitIncreaser) public {
        defaultCollateralFactory = new DefaultCollateralFactory();

        address defaultCollateralAddress = defaultCollateralFactory.create(address(token), initialLimit, limitIncreaser);
        defaultCollateral = DefaultCollateral(defaultCollateralAddress);
        assertEq(defaultCollateralFactory.isEntity(defaultCollateralAddress), true);

        assertEq(defaultCollateral.asset(), address(token));
        assertEq(defaultCollateral.decimals(), IERC20Metadata(address(token)).decimals());
        assertEq(defaultCollateral.totalRepaidDebt(), 0);
        assertEq(defaultCollateral.issuerRepaidDebt(alice), 0);
        assertEq(defaultCollateral.recipientRepaidDebt(alice), 0);
        assertEq(defaultCollateral.repaidDebt(alice, alice), 0);
        assertEq(defaultCollateral.totalDebt(), 0);
        assertEq(defaultCollateral.issuerDebt(alice), 0);
        assertEq(defaultCollateral.recipientDebt(alice), 0);
        assertEq(defaultCollateral.debt(alice, alice), 0);
        assertEq(defaultCollateral.limit(), initialLimit);
        assertEq(defaultCollateral.limitIncreaser(), limitIncreaser);
    }
}
