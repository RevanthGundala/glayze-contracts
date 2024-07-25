// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.19;

// import {Script} from "forge-std/Script.sol";
// import {ContractA} from "../src/ContractA.sol";
// import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// contract DeployContractA is Script {
//     function run() external returns (address) {
//         uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
//         vm.startBroadcast(deployerPrivateKey);

//         // Deploy the implementation contract
//         ContractA implementation = new ContractA();

//         // // Encode the initialization call
//         // bytes memory data = abi.encodeCall(ContractA.initialize, ());

//         // // Deploy the proxy and initialize it in one step
//         // ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

//         // vm.stopBroadcast();

//         // return address(proxy);

//         return address(implementation);
//     }
// }
