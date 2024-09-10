// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import "forge-std/Console2.sol";
import {GlayzeManager} from "../../src/GlayzeManager.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployGlayzeManager} from "../../script/DeployGlayzeManager.s.sol";

contract Sell is Test {
    GlayzeManager public glayzeManager;
    HelperConfig public helperConfig;
    address public owner;
    address public alice = address(1);
    address public bob = address(2);
    ERC20Mock public USDC;
    ERC20Mock public AURA;
    uint256 public constant STARTING_USER_BALANCE = 10000000000e6;

    event PostCreated(uint256 postId, address creator, string name, string symbol, string postURI, uint256 timestamp);
    event Trade(
        uint256 postId,
        address trader,
        bool isBuy,
        uint256 aura,
        uint256 usdc,
        uint256 shares,
        uint256 price,
        uint256 supply,
        uint256 timestamp
    );

    event TradeFees(uint256 postId, address trader, bool isSell, uint256 aura, uint256 usdc, uint256 timestamp);
    event RealCreatorSet(uint256 postId, address realCreator, uint256 timestamp);
    event Referral(address userReferred, address referredBy, uint256 timestamp);

    function setUp() public {
        DeployGlayzeManager deployer = new DeployGlayzeManager();
        (glayzeManager, helperConfig) = deployer.run();
        owner = glayzeManager.owner();
        (address usdc, address aura,) = helperConfig.activeNetworkConfig();
        USDC = ERC20Mock(usdc);
        AURA = ERC20Mock(aura);
        AURA.mint(owner, glayzeManager.MAX_SUPPLY());
    }

    function testSellSharesWithoutAuraWithoutRealCreator() public {
        vm.startPrank(address(glayzeManager));
        glayzeManager.approve(address(glayzeManager), 0, type(uint256).max);
        vm.stopPrank();
        USDC.mint(alice, STARTING_USER_BALANCE);
        vm.startPrank(alice);
        sellSharesWithoutAura(address(0));
        vm.stopPrank();
    }

    function sellSharesWithoutAura(address realCreator) internal {
        USDC.mint(alice, STARTING_USER_BALANCE);
        AURA.mint(alice, STARTING_USER_BALANCE);
        vm.startPrank(alice);

        // Approve GlayzeManager to spend Alice's USDC
        USDC.approve(address(glayzeManager), type(uint256).max);
        AURA.approve(address(glayzeManager), type(uint256).max);

        glayzeManager.createPost(0, "Test Post", "TST", "");

        if (realCreator != address(0)) {
            vm.stopPrank();
            vm.startPrank(owner);
            glayzeManager.setRealCreator(0, realCreator);
            vm.stopPrank();
            vm.startPrank(alice);
        }

        glayzeManager.buyShares(0, 100, 0);

        uint256 initialAliceUsdcBalance = USDC.balanceOf(alice);
        uint256 initialOwnerUsdcBalance = USDC.balanceOf(owner);
        uint256 initialRealCreatorUsdcBalance = USDC.balanceOf(realCreator);

        uint256 sellAmount = 100;
        uint256 sellPrice = glayzeManager.getSellPrice(0, sellAmount);
        uint256 totalFees = glayzeManager.getTotalFees(0, sellPrice);
        console2.log("totalFees", totalFees);

        // Sell tokens
        glayzeManager.sellShares(0, sellAmount, 0);

        (uint256 usdcProtocolFee, uint256 usdcGlayzeCreatorFee, uint256 usdcRealCreatorFee) =
            glayzeManager.getFeeSplit(0, totalFees);

        // USDC
        assertEq(USDC.balanceOf(address(glayzeManager)), 0, "Contract should be paid");
        if (realCreator != address(0)) {
            assertEq(
                USDC.balanceOf(realCreator),
                initialRealCreatorUsdcBalance + usdcRealCreatorFee,
                "The real creator should have received the real creator fee"
            );
            assertEq(
                USDC.balanceOf(owner),
                initialOwnerUsdcBalance + usdcProtocolFee,
                "Owner should have received the protocol fee"
            );
        } else {
            assertEq(
                USDC.balanceOf(owner),
                initialOwnerUsdcBalance + usdcProtocolFee + usdcRealCreatorFee,
                "Owner should have received the protocol and real creator fee"
            );
        }

        assertEq(
            USDC.balanceOf(alice),
            initialAliceUsdcBalance + sellPrice - totalFees + usdcGlayzeCreatorFee,
            "Alice USDC balance incorrect"
        );

        vm.stopPrank();
    }
}
