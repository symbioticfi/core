// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {OperatorRegistry} from "../../src/contracts/OperatorRegistry.sol";
import {NetworkRegistry} from "../../src/contracts/NetworkRegistry.sol";

import {OptInService} from "../../src/contracts/service/OptInService.sol";
import {IOptInService} from "../../src/interfaces/service/IOptInService.sol";

import {OptInServiceHints} from "../../src/contracts/hints/OptInServiceHints.sol";

import {IERC5267} from "@openzeppelin/contracts/interfaces/IERC5267.sol";

contract OperatorOptInServiceTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    OperatorRegistry operatorRegistry;
    NetworkRegistry networkRegistry;

    IOptInService service;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        operatorRegistry = new OperatorRegistry();
        networkRegistry = new NetworkRegistry();
    }

    function test_Create() public {
        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        service = IOptInService(
            address(
                new OptInService(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService")
            )
        );

        assertEq(service.WHERE_REGISTRY(), address(networkRegistry));
        assertEq(service.isOptedInAt(alice, alice, 0, ""), false);
        assertEq(service.isOptedIn(alice, alice), false);
        assertEq(service.nonces(alice, alice), 0);

        address operator = alice;
        address where = bob;

        vm.startPrank(operator);
        operatorRegistry.registerOperator();
        vm.stopPrank();

        vm.startPrank(where);
        networkRegistry.registerNetwork();
        vm.stopPrank();

        vm.startPrank(operator);
        service.optIn(where);
        vm.stopPrank();

        assertEq(service.isOptedInAt(operator, where, uint48(blockTimestamp - 1), ""), false);
        assertEq(service.isOptedInAt(operator, where, uint48(blockTimestamp), ""), true);
        assertEq(service.isOptedInAt(operator, where, uint48(blockTimestamp + 1), ""), true);
        assertEq(service.isOptedIn(operator, where), true);
        assertEq(service.isOptedInAt(operator, where, uint48(blockTimestamp + 1), abi.encode(0)), true);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(service.isOptedIn(operator, where), true);

        vm.startPrank(operator);
        service.optOut(where);
        vm.stopPrank();

        assertEq(service.isOptedInAt(operator, where, uint48(blockTimestamp - 1), ""), true);
        assertEq(service.isOptedIn(operator, where), false);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(service.isOptedIn(operator, where), false);

        vm.startPrank(operator);
        service.optIn(where);
        vm.stopPrank();

        assertEq(service.isOptedIn(operator, where), true);

        vm.startPrank(operator);
        vm.expectRevert(IOptInService.OptOutCooldown.selector);
        service.optOut(where);
        vm.stopPrank();

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.startPrank(operator);
        service.optOut(where);
        vm.stopPrank();

        assertEq(service.isOptedIn(operator, where), false);
    }

    function test_OptInRevertNotEntity() public {
        service = IOptInService(
            address(
                new OptInService(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService")
            )
        );

        address operator = alice;
        address where = bob;

        vm.startPrank(where);
        networkRegistry.registerNetwork();
        vm.stopPrank();

        vm.startPrank(operator);
        vm.expectRevert(IOptInService.NotWho.selector);
        service.optIn(where);
        vm.stopPrank();
    }

    function test_OptInRevertNotWhereEntity() public {
        service = IOptInService(
            address(
                new OptInService(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService")
            )
        );

        address operator = alice;
        address where = bob;

        vm.startPrank(operator);
        operatorRegistry.registerOperator();
        vm.stopPrank();

        vm.startPrank(operator);
        vm.expectRevert(IOptInService.NotWhereEntity.selector);
        service.optIn(where);
        vm.stopPrank();
    }

    function test_OptInRevertAlreadyOptedIn() public {
        service = IOptInService(
            address(
                new OptInService(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService")
            )
        );

        address operator = alice;
        address where = bob;

        vm.startPrank(operator);
        operatorRegistry.registerOperator();
        vm.stopPrank();

        vm.startPrank(where);
        networkRegistry.registerNetwork();
        vm.stopPrank();

        vm.startPrank(operator);
        service.optIn(where);
        vm.stopPrank();

        vm.startPrank(operator);
        vm.expectRevert(IOptInService.AlreadyOptedIn.selector);
        service.optIn(where);
        vm.stopPrank();
    }

    function test_OptOutRevertNotOptedIn() public {
        service = IOptInService(
            address(
                new OptInService(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService")
            )
        );

        address operator = alice;
        address where = bob;

        vm.startPrank(operator);
        operatorRegistry.registerOperator();
        vm.stopPrank();

        vm.startPrank(where);
        networkRegistry.registerNetwork();
        vm.stopPrank();

        vm.startPrank(operator);
        vm.expectRevert(IOptInService.NotOptedIn.selector);
        service.optOut(where);
        vm.stopPrank();
    }

    struct GasStruct {
        uint256 gasSpent1;
        uint256 gasSpent2;
    }

    struct HintStruct {
        uint256 num;
        bool back;
        uint256 secondsAgo;
    }

    // function test_OptInWithHint(uint48 epochDuration, uint256 num, HintStruct memory hintStruct) public {
    //     epochDuration = uint48(bound(epochDuration, 1, 7 days));
    //     hintStruct.num = bound(hintStruct.num, 0, 25);
    //     hintStruct.secondsAgo = bound(hintStruct.secondsAgo, 0, 1_720_700_948);

    //     uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
    //     blockTimestamp = blockTimestamp + 1_720_700_948;
    //     vm.warp(blockTimestamp);

    //     service = IOptInService(address(new OptInService(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService")));

    //     address operator = alice;
    //     address where = bob;

    //     vm.startPrank(operator);
    //     operatorRegistry.registerOperator();
    //     vm.stopPrank();

    //     vm.startPrank(where);
    //     networkRegistry.registerNetwork();
    //     vm.stopPrank();

    //     for (uint256 i; i < hintStruct.num / 2; ++i) {
    //         vm.startPrank(operator);
    //         service.optIn(where);
    //         vm.stopPrank();

    //         blockTimestamp = blockTimestamp + epochDuration;
    //         vm.warp(blockTimestamp);

    //         vm.startPrank(operator);
    //         service.optOut(where);
    //         vm.stopPrank();
    //     }

    //     for (uint256 i; i < hintStruct.num / 2; ++i) {
    //         vm.startPrank(operator);
    //         service.optIn(where);
    //         vm.stopPrank();

    //         blockTimestamp = blockTimestamp + epochDuration;
    //         vm.warp(blockTimestamp);

    //         vm.startPrank(operator);
    //         service.optOut(where);
    //         vm.stopPrank();

    //         blockTimestamp = blockTimestamp + 1;
    //         vm.warp(blockTimestamp);
    //     }

    //     uint48 timestamp =
    //         uint48(hintStruct.back ? blockTimestamp - hintStruct.secondsAgo : blockTimestamp + hintStruct.secondsAgo);

    //     OptInServiceHints optInServiceHints = new OptInServiceHints();
    //     bytes memory hint = optInServiceHints.optInHint(address(service), operator, where, timestamp);

    //     GasStruct memory gasStruct = GasStruct({gasSpent1: 1, gasSpent2: 1});
    //     service.isOptedInAt(operator, where, timestamp, "");
    //     gasStruct.gasSpent1 = vm.lastCallGas().gasTotalUsed;
    //     service.isOptedInAt(operator, where, timestamp, hint);
    //     gasStruct.gasSpent2 = vm.lastCallGas().gasTotalUsed;
    //     assertGe(gasStruct.gasSpent1, gasStruct.gasSpent2);
    // }

    function test_OptInWithSignature() public {
        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        service = new OptInService(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService");

        address operator = alice;
        address where = bob;

        vm.startPrank(operator);
        operatorRegistry.registerOperator();
        vm.stopPrank();

        vm.startPrank(where);
        networkRegistry.registerNetwork();
        vm.stopPrank();

        uint48 deadline = uint48(blockTimestamp);

        bytes32 digest = computeOptInDigest(service, operator, where, 0, deadline);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        service.optIn(operator, where, deadline, signature);

        assertEq(service.isOptedIn(operator, where), true);

        assertEq(service.nonces(operator, where), 1);
    }

    function test_OptInWithInvalidSignature() public {
        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        service = new OptInService(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService");

        address operator = alice;
        address where = bob;

        vm.startPrank(operator);
        operatorRegistry.registerOperator();
        vm.stopPrank();

        vm.startPrank(where);
        networkRegistry.registerNetwork();
        vm.stopPrank();

        uint48 deadline = uint48(blockTimestamp);

        bytes32 digest = computeOptInDigest(service, operator, where, 0, deadline);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(IOptInService.InvalidSignature.selector);
        service.optIn(operator, where, deadline, signature);
    }

    function test_OptInWithExpiredDeadline() public {
        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        service = new OptInService(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService");

        address operator = alice;
        address where = bob;

        vm.startPrank(operator);
        operatorRegistry.registerOperator();
        vm.stopPrank();

        vm.startPrank(where);
        networkRegistry.registerNetwork();
        vm.stopPrank();

        uint48 deadline = uint48(blockTimestamp - 1);

        bytes32 digest = computeOptInDigest(service, operator, where, 0, deadline);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(IOptInService.ExpiredSignature.selector);
        service.optIn(operator, where, deadline, signature);
    }

    function test_IncreaseNonce() public {
        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        service = new OptInService(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService");

        address operator = alice;
        address where = bob;

        vm.startPrank(operator);
        operatorRegistry.registerOperator();
        vm.stopPrank();

        vm.startPrank(where);
        networkRegistry.registerNetwork();
        vm.stopPrank();

        uint48 deadline = uint48(blockTimestamp);

        bytes32 digest = computeOptInDigest(service, operator, where, 0, deadline);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.startPrank(operator);
        service.increaseNonce(where);
        vm.stopPrank();

        assertEq(service.nonces(operator, where), 1);

        vm.expectRevert();
        service.optIn(operator, where, deadline, signature);
    }

    function test_OptOutWithSignature() public {
        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        service = new OptInService(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService");

        address operator = alice;
        address where = bob;

        vm.startPrank(operator);
        operatorRegistry.registerOperator();
        vm.stopPrank();

        vm.startPrank(where);
        networkRegistry.registerNetwork();
        vm.stopPrank();

        vm.startPrank(operator);
        service.optIn(where);
        vm.stopPrank();

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint48 deadline = uint48(blockTimestamp);

        bytes32 digest = computeOptOutDigest(service, operator, where, 1, deadline);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        service.optOut(operator, where, deadline, signature);

        assertEq(service.isOptedIn(operator, where), false);

        assertEq(service.nonces(operator, where), 2);
    }

    function test_OptOutWithInvalidSignature() public {
        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        service = new OptInService(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService");

        address operator = alice;
        address where = bob;

        vm.startPrank(operator);
        operatorRegistry.registerOperator();
        vm.stopPrank();

        vm.startPrank(where);
        networkRegistry.registerNetwork();
        vm.stopPrank();

        vm.startPrank(operator);
        service.optIn(where);
        vm.stopPrank();

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint48 deadline = uint48(blockTimestamp);

        bytes32 digest = computeOptOutDigest(service, operator, where, 1, deadline);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(IOptInService.InvalidSignature.selector);
        service.optOut(operator, where, deadline, signature);
    }

    function test_OptOutWithExpiredDeadline() public {
        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        service = new OptInService(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService");

        address operator = alice;
        address where = bob;

        vm.startPrank(operator);
        operatorRegistry.registerOperator();
        vm.stopPrank();

        vm.startPrank(where);
        networkRegistry.registerNetwork();
        vm.stopPrank();

        vm.startPrank(operator);
        service.optIn(where);
        vm.stopPrank();

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint48 deadline = uint48(blockTimestamp - 1);

        bytes32 digest = computeOptOutDigest(service, operator, where, 1, deadline);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(IOptInService.ExpiredSignature.selector);
        service.optOut(operator, where, deadline, signature);
    }

    function computeOptInDigest(
        IOptInService _service,
        address who,
        address where,
        uint256 nonce,
        uint48 deadline
    ) internal view returns (bytes32) {
        bytes32 OPT_IN_TYPEHASH = keccak256("OptIn(address who,address where,uint256 nonce,uint48 deadline)");
        bytes32 structHash = keccak256(abi.encode(OPT_IN_TYPEHASH, who, where, nonce, deadline));

        bytes32 domainSeparator = _computeDomainSeparator(address(_service));

        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function computeOptOutDigest(
        IOptInService _service,
        address who,
        address where,
        uint256 nonce,
        uint48 deadline
    ) internal view returns (bytes32) {
        bytes32 OPT_OUT_TYPEHASH = keccak256("OptOut(address who,address where,uint256 nonce,uint48 deadline)");
        bytes32 structHash = keccak256(abi.encode(OPT_OUT_TYPEHASH, who, where, nonce, deadline));

        bytes32 domainSeparator = _computeDomainSeparator(address(_service));

        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function _computeDomainSeparator(
        address _service
    ) internal view returns (bytes32) {
        bytes32 DOMAIN_TYPEHASH =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

        (, string memory name, string memory version,,,,) = IERC5267(_service).eip712Domain();
        bytes32 NAME_HASH = keccak256(bytes(name));
        bytes32 VERSION_HASH = keccak256(bytes(version));
        uint256 chainId = block.chainid;

        return keccak256(abi.encode(DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, chainId, _service));
    }
}
