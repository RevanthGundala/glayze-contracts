// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {ContractA} from "../src/ContractA.sol";
import {ContractB} from "../src/ContractB.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

contract Upgrade is Script {
    function run() external returns (address) {
        address mostRecentlyDeployedProxy = DevOpsTools.get_most_recent_deployment("ERC1967Proxy", block.chainid);

        vm.startBroadcast();
        ContractB newAddy = new ContractB(); //gets the address of contractB
        vm.stopBroadcast();
        address proxy = upgradeAddy(mostRecentlyDeployedProxy, address(newAddy)); //upgrades contractA to contractB
        return proxy;
    }

    function upgradeAddy(address proxyAddress, address newAddy) public returns (address) {
        vm.startBroadcast();
        ContractA proxy = ContractA(payable(proxyAddress)); //we want to make a function call on this address
        // proxy.upgradeTo(address(newAddy)); //proxy address now points to this new address
        vm.stopBroadcast();
        return address(proxy);
    }
}
