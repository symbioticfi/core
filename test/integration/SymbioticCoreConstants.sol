// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SymbioticCoreImports.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

library SymbioticCoreConstants {
    using Strings for string;

    struct Core {
        ISymbioticVaultFactory vaultFactory;
        ISymbioticDelegatorFactory delegatorFactory;
        ISymbioticSlasherFactory slasherFactory;
        ISymbioticNetworkRegistry networkRegistry;
        ISymbioticMetadataService networkMetadataService;
        ISymbioticNetworkMiddlewareService networkMiddlewareService;
        ISymbioticOperatorRegistry operatorRegistry;
        ISymbioticMetadataService operatorMetadataService;
        ISymbioticOptInService operatorVaultOptInService;
        ISymbioticOptInService operatorNetworkOptInService;
        ISymbioticVaultConfigurator vaultConfigurator;
    }

    function core() internal view returns (Core memory) {
        if (block.chainid == 1) {
            // mainnet
            revert("SymbioticCoreConstants.core(): mainnet not supported yet");
        } else if (block.chainid == 17_000) {
            // holesky
            return Core({
                vaultFactory: ISymbioticVaultFactory(0x407A039D94948484D356eFB765b3c74382A050B4),
                delegatorFactory: ISymbioticDelegatorFactory(0x890CA3f95E0f40a79885B7400926544B2214B03f),
                slasherFactory: ISymbioticSlasherFactory(0xbf34bf75bb779c383267736c53a4ae86ac7bB299),
                networkRegistry: ISymbioticNetworkRegistry(0x7d03b7343BF8d5cEC7C0C27ecE084a20113D15C9),
                networkMetadataService: ISymbioticMetadataService(0x0F7E58Cc4eA615E8B8BEB080dF8B8FDB63C21496),
                networkMiddlewareService: ISymbioticNetworkMiddlewareService(0x62a1ddfD86b4c1636759d9286D3A0EC722D086e3),
                operatorRegistry: ISymbioticOperatorRegistry(0x6F75a4ffF97326A00e52662d82EA4FdE86a2C548),
                operatorMetadataService: ISymbioticMetadataService(0x0999048aB8eeAfa053bF8581D4Aa451ab45755c9),
                operatorVaultOptInService: ISymbioticOptInService(0x95CC0a052ae33941877c9619835A233D21D57351),
                operatorNetworkOptInService: ISymbioticOptInService(0x58973d16FFA900D11fC22e5e2B6840d9f7e13401),
                vaultConfigurator: ISymbioticVaultConfigurator(0xD2191FE92987171691d552C219b8caEf186eb9cA)
            });
        } else if (block.chainid == 11_155_111) {
            // sepolia
            return Core({
                vaultFactory: ISymbioticVaultFactory(0x407A039D94948484D356eFB765b3c74382A050B4),
                delegatorFactory: ISymbioticDelegatorFactory(0x890CA3f95E0f40a79885B7400926544B2214B03f),
                slasherFactory: ISymbioticSlasherFactory(0xbf34bf75bb779c383267736c53a4ae86ac7bB299),
                networkRegistry: ISymbioticNetworkRegistry(0x7d03b7343BF8d5cEC7C0C27ecE084a20113D15C9),
                networkMetadataService: ISymbioticMetadataService(0x0F7E58Cc4eA615E8B8BEB080dF8B8FDB63C21496),
                networkMiddlewareService: ISymbioticNetworkMiddlewareService(0x62a1ddfD86b4c1636759d9286D3A0EC722D086e3),
                operatorRegistry: ISymbioticOperatorRegistry(0x6F75a4ffF97326A00e52662d82EA4FdE86a2C548),
                operatorMetadataService: ISymbioticMetadataService(0x0999048aB8eeAfa053bF8581D4Aa451ab45755c9),
                operatorVaultOptInService: ISymbioticOptInService(0x95CC0a052ae33941877c9619835A233D21D57351),
                operatorNetworkOptInService: ISymbioticOptInService(0x58973d16FFA900D11fC22e5e2B6840d9f7e13401),
                vaultConfigurator: ISymbioticVaultConfigurator(0xD2191FE92987171691d552C219b8caEf186eb9cA)
            });
        } else {
            revert("SymbioticCoreConstants.core(): chainid not supported");
        }
    }

    function token(
        string memory symbol
    ) internal view returns (address) {
        if (symbol.equal("wstETH")) {
            return wstETH();
        } else if (symbol.equal("cbETH")) {
            return cbETH();
        } else if (symbol.equal("wBETH")) {
            return wBETH();
        } else if (symbol.equal("rETH")) {
            return rETH();
        } else if (symbol.equal("mETH")) {
            return mETH();
        } else if (symbol.equal("swETH")) {
            return swETH();
        } else if (symbol.equal("sfrxETH")) {
            return sfrxETH();
        } else if (symbol.equal("ETHx")) {
            return ETHx();
        } else if (symbol.equal("ENA")) {
            return ENA();
        } else if (symbol.equal("sUSDe")) {
            return sUSDe();
        } else if (symbol.equal("WBTC")) {
            return WBTC();
        } else if (symbol.equal("tBTC")) {
            return tBTC();
        } else if (symbol.equal("LsETH")) {
            return LsETH();
        } else if (symbol.equal("osETH")) {
            return osETH();
        } else if (symbol.equal("ETHFI")) {
            return ETHFI();
        } else if (symbol.equal("FXS")) {
            return FXS();
        } else if (symbol.equal("LBTC")) {
            return LBTC();
        } else if (symbol.equal("SWELL")) {
            return SWELL();
        } else {
            revert("SymbioticCoreConstants.token(): symbol not supported");
        }
    }

    function tokenSupported(
        string memory symbol
    ) internal view returns (bool) {
        if (symbol.equal("wstETH")) {
            return wstETHSupported();
        } else if (symbol.equal("cbETH")) {
            return cbETHSupported();
        } else if (symbol.equal("wBETH")) {
            return wBETHSupported();
        } else if (symbol.equal("rETH")) {
            return rETHSupported();
        } else if (symbol.equal("mETH")) {
            return mETHSupported();
        } else if (symbol.equal("swETH")) {
            return swETHSupported();
        } else if (symbol.equal("sfrxETH")) {
            return sfrxETHSupported();
        } else if (symbol.equal("ETHx")) {
            return ETHxSupported();
        } else if (symbol.equal("ENA")) {
            return ENASupported();
        } else if (symbol.equal("sUSDe")) {
            return sUSDeSupported();
        } else if (symbol.equal("WBTC")) {
            return WBTCSupported();
        } else if (symbol.equal("tBTC")) {
            return tBTCSupported();
        } else if (symbol.equal("LsETH")) {
            return LsETHSupported();
        } else if (symbol.equal("osETH")) {
            return osETHSupported();
        } else if (symbol.equal("ETHFI")) {
            return ETHFISupported();
        } else if (symbol.equal("FXS")) {
            return FXSSupported();
        } else if (symbol.equal("LBTC")) {
            return LBTCSupported();
        } else if (symbol.equal("SWELL")) {
            return SWELLSupported();
        } else {
            revert("SymbioticCoreConstants.tokenSupported(): symbol not supported");
        }
    }

    function wstETH() internal view returns (address) {
        if (block.chainid == 1) {
            // mainnet
            return 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        } else if (block.chainid == 17_000) {
            // holesky
            return 0x8d09a4502Cc8Cf1547aD300E066060D043f6982D;
        } else if (block.chainid == 11_155_111) {
            // sepolia
            return 0xB82381A3fBD3FaFA77B3a7bE693342618240067b;
        } else {
            revert("SymbioticCoreConstants.wstETH(): chainid not supported");
        }
    }

    function cbETH() internal view returns (address) {
        if (block.chainid == 1) {
            // mainnet
            return 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;
        } else {
            revert("SymbioticCoreConstants.cbETH(): chainid not supported");
        }
    }

    function wBETH() internal view returns (address) {
        if (block.chainid == 1) {
            // mainnet
            return 0xa2E3356610840701BDf5611a53974510Ae27E2e1;
        } else {
            revert("SymbioticCoreConstants.wBETH(): chainid not supported");
        }
    }

    function rETH() internal view returns (address) {
        if (block.chainid == 1) {
            // mainnet
            return 0xae78736Cd615f374D3085123A210448E74Fc6393;
        } else if (block.chainid == 17_000) {
            // holesky
            return 0x7322c24752f79c05FFD1E2a6FCB97020C1C264F1;
        } else {
            revert("SymbioticCoreConstants.rETH(): chainid not supported");
        }
    }

    function mETH() internal view returns (address) {
        if (block.chainid == 1) {
            // mainnet
            return 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa;
        } else if (block.chainid == 17_000) {
            // holesky
            return 0xe3C063B1BEe9de02eb28352b55D49D85514C67FF;
        } else if (block.chainid == 11_155_111) {
            // sepolia
            return 0x072d71b257ECa6B60b5333626F6a55ea1B0c451c;
        } else {
            revert("SymbioticCoreConstants.mETH(): chainid not supported");
        }
    }

    function swETH() internal view returns (address) {
        if (block.chainid == 1) {
            // mainnet
            return 0xf951E335afb289353dc249e82926178EaC7DEd78;
        } else {
            revert("SymbioticCoreConstants.swETH(): chainid not supported");
        }
    }

    function sfrxETH() internal view returns (address) {
        if (block.chainid == 1) {
            // mainnet
            return 0xac3E018457B222d93114458476f3E3416Abbe38F;
        } else {
            revert("SymbioticCoreConstants.sfrxETH(): chainid not supported");
        }
    }

    function ETHx() internal view returns (address) {
        if (block.chainid == 1) {
            // mainnet
            return 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b;
        } else if (block.chainid == 17_000) {
            // holesky
            return 0xB4F5fc289a778B80392b86fa70A7111E5bE0F859;
        } else {
            revert("SymbioticCoreConstants.ETHx(): chainid not supported");
        }
    }

    function ENA() internal view returns (address) {
        if (block.chainid == 1) {
            // mainnet
            return 0x57e114B691Db790C35207b2e685D4A43181e6061;
        } else {
            revert("SymbioticCoreConstants.ENA(): chainid not supported");
        }
    }

    function sUSDe() internal view returns (address) {
        if (block.chainid == 1) {
            // mainnet
            return 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
        } else {
            revert("SymbioticCoreConstants.sUSDe(): chainid not supported");
        }
    }

    function WBTC() internal view returns (address) {
        if (block.chainid == 1) {
            // mainnet
            return 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        } else {
            revert("SymbioticCoreConstants.WBTC(): chainid not supported");
        }
    }

    function tBTC() internal view returns (address) {
        if (block.chainid == 1) {
            // mainnet
            return 0x18084fbA666a33d37592fA2633fD49a74DD93a88;
        } else if (block.chainid == 11_155_111) {
            // sepolia
            return 0x517f2982701695D4E52f1ECFBEf3ba31Df470161;
        } else {
            revert("SymbioticCoreConstants.tBTC(): chainid not supported");
        }
    }

    function LsETH() internal view returns (address) {
        if (block.chainid == 1) {
            // mainnet
            return 0x8c1BEd5b9a0928467c9B1341Da1D7BD5e10b6549;
        } else if (block.chainid == 17_000) {
            // holesky
            return 0x1d8b30cC38Dba8aBce1ac29Ea27d9cFd05379A09;
        } else {
            revert("SymbioticCoreConstants.LsETH(): chainid not supported");
        }
    }

    function osETH() internal view returns (address) {
        if (block.chainid == 1) {
            // mainnet
            return 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38;
        } else if (block.chainid == 17_000) {
            // holesky
            return 0xF603c5A3F774F05d4D848A9bB139809790890864;
        } else {
            revert("SymbioticCoreConstants.osETH(): chainid not supported");
        }
    }

    function ETHFI() internal view returns (address) {
        if (block.chainid == 1) {
            // mainnet
            return 0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB;
        } else {
            revert("SymbioticCoreConstants.ETHFI(): chainid not supported");
        }
    }

    function FXS() internal view returns (address) {
        if (block.chainid == 1) {
            // mainnet
            return 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;
        } else {
            revert("SymbioticCoreConstants.FXS(): chainid not supported");
        }
    }

    function LBTC() internal view returns (address) {
        if (block.chainid == 1) {
            // mainnet
            return 0x8236a87084f8B84306f72007F36F2618A5634494;
        } else {
            revert("SymbioticCoreConstants.LBTC(): chainid not supported");
        }
    }

    function SWELL() internal view returns (address) {
        if (block.chainid == 1) {
            // mainnet
            return 0x0a6E7Ba5042B38349e437ec6Db6214AEC7B35676;
        } else {
            revert("SymbioticCoreConstants.SWELL(): chainid not supported");
        }
    }

    function wstETHSupported() internal view returns (bool) {
        return (block.chainid == 1 || block.chainid == 17_000 || block.chainid == 11_155_111);
    }

    function cbETHSupported() internal view returns (bool) {
        return block.chainid == 1;
    }

    function wBETHSupported() internal view returns (bool) {
        return block.chainid == 1;
    }

    function rETHSupported() internal view returns (bool) {
        return (block.chainid == 1 || block.chainid == 17_000);
    }

    function mETHSupported() internal view returns (bool) {
        return (block.chainid == 1 || block.chainid == 17_000 || block.chainid == 11_155_111);
    }

    function swETHSupported() internal view returns (bool) {
        return block.chainid == 1;
    }

    function sfrxETHSupported() internal view returns (bool) {
        return block.chainid == 1;
    }

    function ETHxSupported() internal view returns (bool) {
        return (block.chainid == 1 || block.chainid == 17_000);
    }

    function ENASupported() internal view returns (bool) {
        return block.chainid == 1;
    }

    function sUSDeSupported() internal view returns (bool) {
        return block.chainid == 1;
    }

    function WBTCSupported() internal view returns (bool) {
        return block.chainid == 1;
    }

    function tBTCSupported() internal view returns (bool) {
        return (block.chainid == 1 || block.chainid == 11_155_111);
    }

    function LsETHSupported() internal view returns (bool) {
        return (block.chainid == 1 || block.chainid == 17_000);
    }

    function osETHSupported() internal view returns (bool) {
        return (block.chainid == 1 || block.chainid == 17_000);
    }

    function ETHFISupported() internal view returns (bool) {
        return block.chainid == 1;
    }

    function FXSSupported() internal view returns (bool) {
        return block.chainid == 1;
    }

    function LBTCSupported() internal view returns (bool) {
        return block.chainid == 1;
    }

    function SWELLSupported() internal view returns (bool) {
        return block.chainid == 1;
    }

    function allTokens() internal view returns (string[] memory result) {
        result = new string[](18);
        result[0] = "wstETH";
        result[1] = "cbETH";
        result[2] = "wBETH";
        result[3] = "rETH";
        result[4] = "mETH";
        result[5] = "swETH";
        result[6] = "sfrxETH";
        result[7] = "ETHx";
        result[8] = "ENA";
        result[9] = "sUSDe";
        result[10] = "WBTC";
        result[11] = "tBTC";
        result[12] = "LsETH";
        result[13] = "osETH";
        result[14] = "ETHFI";
        result[15] = "FXS";
        result[16] = "LBTC";
        result[17] = "SWELL";
    }

    function supportedTokens() internal view returns (string[] memory result) {
        string[] memory tokens = allTokens();
        result = new string[](tokens.length);

        uint256 count;
        for (uint256 i; i < tokens.length; ++i) {
            if (tokenSupported(tokens[i])) {
                result[count] = tokens[i];
                ++count;
            }
        }

        assembly ("memory-safe") {
            mstore(result, count)
        }
    }
}
