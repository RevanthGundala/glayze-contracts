// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";
import {Aura} from "../src/Aura.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    uint8 public constant DECIMALS = 6;

    struct NetworkConfig {
        address usdc;
        address aura;
        uint256 deployerKey;
    }

    uint256 public DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 public BASE_SEPOLIA_CHAIN_ID = 84532;
    address public BASE_SEPOLIA_USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    constructor() {
        if (block.chainid == BASE_SEPOLIA_CHAIN_ID) {
            Aura aura = new Aura();
            activeNetworkConfig = getBaseSepoliaEthConfig(address(aura));
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getBaseSepoliaEthConfig(address aura)
        public
        view
        returns (NetworkConfig memory baseSepoliaNetworkConfig)
    {
        baseSepoliaNetworkConfig =
            NetworkConfig({usdc: BASE_SEPOLIA_USDC, aura: aura, deployerKey: vm.envUint("PRIVATE_KEY")});
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        // Check to see if we set an active network config
        if (activeNetworkConfig.usdc != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        ERC20Mock usdcMock = new ERC20Mock("USDC", "USDC", msg.sender, 1000e6);
        ERC20Mock auraMock = new ERC20Mock("AURA", "AURA", msg.sender, 1000e6);
        vm.stopBroadcast();

        anvilNetworkConfig =
            NetworkConfig({usdc: address(usdcMock), aura: address(auraMock), deployerKey: DEFAULT_ANVIL_PRIVATE_KEY});
    }
}
