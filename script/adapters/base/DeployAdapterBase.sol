// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IAdapter} from "../../../src/interfaces/adapters/IAdapter.sol";
import {IMigratablesFactory} from "../../../src/interfaces/common/IMigratablesFactory.sol";
import {Logs} from "../../utils/Logs.sol";

contract DeployAdapterBase is Script {
    struct DeployParams {
        address adapterFactory;
        uint64 version;
        address owner;
        address vault;
        bytes initData;
    }

    struct DeploymentData {
        address adapter;
        address adapterFactory;
        uint64 version;
        address owner;
        address vault;
    }

    function runBase(DeployParams memory params) public virtual returns (DeploymentData memory data) {
        _validateParams(params);

        bytes memory createData = abi.encode(params.vault, params.initData);

        vm.startBroadcast();
        data.adapter = IMigratablesFactory(params.adapterFactory).create(params.version, params.owner, createData);
        vm.stopBroadcast();

        data.adapterFactory = params.adapterFactory;
        data.version = params.version;
        data.owner = params.owner;
        data.vault = params.vault;

        _validateDeployment(data);
        _logDeployment(data);
    }

    function _singleConverter(address converter) internal pure returns (address[] memory converters) {
        if (converter == address(0)) {
            return new address[](0);
        }

        converters = new address[](1);
        converters[0] = converter;
    }

    function _validateParams(DeployParams memory params) internal pure {
        require(params.adapterFactory != address(0), "invalid adapter factory");
        require(params.version != 0, "invalid version");
        require(params.owner != address(0), "invalid owner");
        require(params.vault != address(0), "invalid vault");
    }

    function _validateDeployment(DeploymentData memory data) internal view {
        assert(IAdapter(data.adapter).FACTORY() == data.adapterFactory);
        assert(IAdapter(data.adapter).version() == data.version);
        assert(Ownable(data.adapter).owner() == data.owner);
        assert(IAdapter(data.adapter).vault() == data.vault);
    }

    function _logDeployment(DeploymentData memory data) internal {
        Logs.log(
            string.concat(
                "Deployed adapter",
                "\n    adapter:",
                vm.toString(data.adapter),
                "\n    adapterFactory:",
                vm.toString(data.adapterFactory),
                "\n    version:",
                vm.toString(uint256(data.version)),
                "\n    owner:",
                vm.toString(data.owner),
                "\n    vault:",
                vm.toString(data.vault)
            )
        );
    }
}
