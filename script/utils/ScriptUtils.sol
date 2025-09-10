import {VmSafe} from "forge-std/Vm.sol";

library ScriptUtils {
    VmSafe private constant vm = VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));

    function createArray(
        address element
    ) public pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = element;
        return arr;
    }

    function parseAddressesFromString(
        string memory addressString
    ) public pure returns (address[] memory) {
        // Split the string by comma delimiter
        string[] memory addressStrings = vm.split(addressString, ",");

        // Create array for addresses
        address[] memory addresses = new address[](addressStrings.length);

        // Parse each string to address
        for (uint256 i = 0; i < addressStrings.length; i++) {
            addresses[i] = vm.parseAddress(addressStrings[i]);
        }

        return addresses;
    }
}
