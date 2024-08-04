// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {GlayzeManager} from "../src/GlayzeManager.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployGlayzeManager is Script {
    function run() external returns (GlayzeManager, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address usdc, address aura, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        vm.startBroadcast(deployerKey);
        GlayzeManager glayzeManager = new GlayzeManager(usdc, aura);
        vm.stopBroadcast();
        return (glayzeManager, helperConfig);
    }
}
