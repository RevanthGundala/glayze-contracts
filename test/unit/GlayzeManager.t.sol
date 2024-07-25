// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import "forge-std/Console2.sol";
import {GlayzeManager} from "../../src/GlayzeManager.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GlayzeManagerTest is Test {
    GlayzeManager public manager;

    address alice = address(0x1);
    address usdc = address(0x2);
    address user = address(0x3);

    function setUp() public {
        vm.prank(alice);
        manager = new GlayzeManager(usdc, alice);
    }

    function testInitialSetup() public view {
        assertTrue(address(manager) != address(0), "Contract should be deployed");
    }

    function testGetOwner() public view {
        assertEq(manager.owner(), alice, "Owner should be set");
    }

    // function testGetPrice() public view {
    //     uint256 price = manager.getBuyPrice(1, 2);
    //     console2.log(price);
    // }

    // function testCreatePost() public {
    //     vm.startPrank(alice);
    //     string memory name = "Test Post";
    //     string memory symbol = "TST";
    //     string memory postURI = "";
    //     manager.createPost(name, symbol, postURI);
    //     (string memory postName, string memory postSymbol, string memory postURIResult, ) = manager.posts(0);
    //     assertEq(postName, name, "Name should be set");
    //     assertEq(postSymbol, symbol, "Symbol should be set");
    //     assertEq(postURIResult, postURI, "Post URI should be set");
    //     assertEq(manager.postIdCounter(), 1, "Post should be created");
    //     // vm.expectEmit(0, alice, name, symbol, postURI, block.timestamp);
    //     vm.stopPrank();
    // }

    // function testBuyTokens() public {
    //     vm.startPrank(alice);
    //     manager.buyTokens(0, 1, 100);
    //     vm.stopPrank();
    // }

    // function testSellTokens() public {}

    // function testBuyTokensRevertsIfInvalidPostId() public {
    //     vm.startPrank(alice);
    //     vm.expectRevert(InvalidPostId.selector);
    //     manager.buyTokens(0, 1, 100);
    //     vm.stopPrank();
    // }

    // function testSellTokensRevertsIfInvalidPostId() public {
    //     vm.startPrank(alice);
    //     vm.expectRevert(InvalidPostId.selector);
    //     manager.sellTokens(0, 1);
    //     vm.stopPrank();
    // }
}
