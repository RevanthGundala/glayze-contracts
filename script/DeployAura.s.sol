// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {Aura} from "../src/Aura.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployAura is Script {
    function run() external returns (Aura) {
        HelperConfig helperConfig = new HelperConfig();
        (, , uint256 deployerKey) = helperConfig.activeNetworkConfig();

        vm.startBroadcast(deployerKey);
        Aura aura = new Aura();
        vm.stopBroadcast();
        return aura;
    }
}
