// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {AdapterFactory} from "../../../src/contracts/adapters/AdapterFactory.sol";
import {ThreeFAdapter} from "../../../src/contracts/adapters/ThreeFAdapter.sol";

import {IThreeFAdapter} from "../../../src/interfaces/adapters/IThreeFAdapter.sol";
import {IRegistry} from "../../../src/interfaces/common/IRegistry.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

// forge script script/deploy/testnet/DeploySepoliaOldVaultThreeFAdapter.s.sol:DeploySepoliaOldVaultThreeFAdapter --rpc-url=$ETH_RPC_URL_SEPOLIA --account=$ACCOUNT --sender=$SENDER --broadcast
contract DeploySepoliaOldVaultThreeFAdapter is Script {
    uint256 internal constant SEPOLIA_CHAIN_ID = 11_155_111;

    address internal constant VAULT = 0xAb89E82C75ca7477c35f44BfA858fF83b086B8b0;
    address internal constant ASSET = 0x809e6c18bC13Cc7C9F7b8000d74243BAaccE84d7;
    address internal constant OLD_VAULT_FACTORY = 0x158Bb64B79CADa5a259d46cc2354db9D018D9f3E;
    address internal constant REQUEST_WHITELIST = 0xA80b976A357aC24f3c38F7E5ED3Dd5b813bb09E1;
    address internal constant OFFER_SIGNER = 0x5eF12ab8B02F1418D17D65F005c56E5d2Cb026F3;

    struct Deployment {
        address adapterFactory;
        address adapterImplementation;
        address adapter;
    }

    function run() external returns (Deployment memory deployment) {
        _validatePreconditions();

        address broadcaster = _scriptOwner();

        vm.startBroadcast();

        deployment.adapterFactory = address(new AdapterFactory(broadcaster));
        deployment.adapterImplementation =
            address(new ThreeFAdapter(OLD_VAULT_FACTORY, deployment.adapterFactory, REQUEST_WHITELIST));

        AdapterFactory(deployment.adapterFactory).whitelist(deployment.adapterImplementation);

        deployment.adapter =
            AdapterFactory(deployment.adapterFactory).create(1, broadcaster, abi.encode(VAULT, bytes("")));
        IThreeFAdapter(deployment.adapter).setOfferSigner(OFFER_SIGNER);

        if (broadcaster != OFFER_SIGNER) {
            Ownable(deployment.adapter).transferOwnership(OFFER_SIGNER);
            Ownable(deployment.adapterFactory).transferOwnership(OFFER_SIGNER);
        }

        vm.stopBroadcast();

        _validateDeployment(deployment);
        _log(deployment);
    }

    function _validatePreconditions() internal view {
        require(block.chainid == SEPOLIA_CHAIN_ID, "wrong chain");
        require(IRegistry(OLD_VAULT_FACTORY).isEntity(VAULT), "vault not in old factory");
        require(IERC4626(VAULT).asset() == ASSET, "asset mismatch");
    }

    function _validateDeployment(Deployment memory deployment) internal view {
        require(Ownable(deployment.adapterFactory).owner() == OFFER_SIGNER, "factory owner mismatch");
        require(Ownable(deployment.adapter).owner() == OFFER_SIGNER, "adapter owner mismatch");
        require(
            AdapterFactory(deployment.adapterFactory).implementation(1) == deployment.adapterImplementation,
            "implementation mismatch"
        );
        require(AdapterFactory(deployment.adapterFactory).isEntity(deployment.adapter), "adapter is not factory entity");
        require(
            IThreeFAdapter(deployment.adapterImplementation).FACTORY() == deployment.adapterFactory,
            "implementation factory mismatch"
        );
        require(
            IThreeFAdapter(deployment.adapterImplementation).REQUEST_WHITELIST() == REQUEST_WHITELIST,
            "whitelist mismatch"
        );
        require(IThreeFAdapter(deployment.adapter).vault() == VAULT, "adapter vault mismatch");
        require(IThreeFAdapter(deployment.adapter).offerSigner() == OFFER_SIGNER, "offer signer mismatch");
    }

    function _scriptOwner() internal view returns (address owner_) {
        (,, address origin) = vm.readCallers();
        return origin == address(0) ? msg.sender : origin;
    }

    function _log(Deployment memory deployment) internal view {
        console2.log("Sepolia old-vault 3F adapter deployed");
        console2.log("AdapterFactory:", deployment.adapterFactory);
        console2.log("AdapterImplementation:", deployment.adapterImplementation);
        console2.log("Adapter:", deployment.adapter);
        console2.log("Vault:", IThreeFAdapter(deployment.adapter).vault());
        console2.log("Asset:", IERC4626(VAULT).asset());
        console2.log("RequestWhitelist:", IThreeFAdapter(deployment.adapterImplementation).REQUEST_WHITELIST());
        console2.log("OfferSigner:", IThreeFAdapter(deployment.adapter).offerSigner());
        console2.log("Owner:", Ownable(deployment.adapter).owner());
    }
}
