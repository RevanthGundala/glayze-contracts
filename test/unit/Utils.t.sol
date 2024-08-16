// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import "forge-std/Console2.sol";
import {GlayzeManager} from "../../src/GlayzeManager.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployGlayzeManager} from "../../script/DeployGlayzeManager.s.sol";

contract Utils is Test {
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
        uint256 newSupply,
        uint256 newPrice,
        uint256 timestamp
    );

    event TradeFees(uint256 postId, address trader, bool isBuy, uint256 aura, uint256 usdc, uint256 timestamp);
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

    function testInitialSetup() public view {
        assertTrue(address(glayzeManager) != address(0), "Contract should be deployed");
    }

    function testCreatePost() public {
        vm.startPrank(alice);
        uint256 postId = 213490213414;
        string memory name = "Test Post With a bunch of characters";
        string memory symbol = "TSTINGMORE";
        string memory postURI = "ipfs://QmTGa3Vcds8EHWhrs9mdBMBvNwgVCaZVrikDkYLAtXRUrJ";

        // Approve USDC spending
        USDC.mint(alice, STARTING_USER_BALANCE);
        USDC.approve(address(glayzeManager), type(uint256).max);

        // Expect the PostCreated event
        vm.expectEmit(true, true, true, true);
        emit PostCreated(213490213414, alice, name, symbol, postURI, block.timestamp);

        // Call the function that should emit the event
        glayzeManager.createPost(postId, name, symbol, postURI);

        // Check the post details
        (
            string memory postName,
            string memory postSymbol,
            string memory postURIResult,
            address contractCreator,
            address realCreator
        ) = glayzeManager.posts(213490213414);

        assertEq(postName, name, "Name should be set");
        assertEq(postSymbol, symbol, "Symbol should be set");
        assertEq(postURIResult, postURI, "Post URI should be set");
        assertEq(contractCreator, alice, "Contract creator should be set");
        assertEq(realCreator, address(0), "Real creator should be set");
        assertEq(
            glayzeManager.balanceOf(address(glayzeManager), 213490213414),
            glayzeManager.MAX_SUPPLY(),
            "Contract should have max supply of new token"
        );
        assertEq(USDC.balanceOf(owner), glayzeManager.usdcCreationPayment(), "Owner should receive USDC payment");
        assertEq(
            USDC.balanceOf(alice),
            STARTING_USER_BALANCE - glayzeManager.usdcCreationPayment(),
            "Alice's USDC balance should decrease"
        );
        vm.stopPrank();
    }

    function testCreatePostRevertsWithInsufficientBalance() public {
        vm.startPrank(alice);
        USDC.approve(address(glayzeManager), glayzeManager.usdcCreationPayment());
        // Expect the revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, glayzeManager.usdcCreationPayment()
            )
        );
        glayzeManager.createPost(0, "Test Post", "TST", "");
        vm.stopPrank();
    }

    function testCanReferUser() public {
        // Mint AURA tokens to the owner first
        uint256 referralAmount = glayzeManager.auraReferralAmount();
        AURA.mint(owner, referralAmount * 2); // Double the amount for both transfers
        // Owner approves GlayzeManager to spend AURA tokens

        vm.startPrank(owner);
        AURA.approve(address(glayzeManager), referralAmount * 2);
        // Perform the referral
        glayzeManager.refer(bob, alice);

        vm.stopPrank();

        // Assert that Bob is now referred
        assertEq(glayzeManager.usersReferred(bob), true, "User should be referred");

        // Check that Bob received the referral amount
        assertEq(AURA.balanceOf(bob), referralAmount, "Bob should have received the referral amount");

        // Check that the owner (referrer) also received the referral amount
        assertEq(AURA.balanceOf(alice), referralAmount, "Owner should have received the referral amount");
    }

    function testReferUserRevertsWithUserAlreadyReferred() public {
        uint256 referralAmount = glayzeManager.auraReferralAmount();
        AURA.mint(owner, referralAmount * 2); // Double the amount for both transfers
        vm.startPrank(owner);
        AURA.approve(address(glayzeManager), referralAmount * 2);
        glayzeManager.refer(bob, alice);
        vm.expectRevert(abi.encodeWithSelector(GlayzeManager.UserAlreadyReferred.selector, bob));
        glayzeManager.refer(bob, alice);
        vm.stopPrank();
    }

    function testCanSetRealCreator() public {
        vm.startPrank(owner);
        // Call the function that should emit the event
        USDC.mint(owner, glayzeManager.usdcCreationPayment());
        USDC.approve(address(glayzeManager), glayzeManager.usdcCreationPayment());
        glayzeManager.createPost(0, "Test Post", "TST", "");
        glayzeManager.setRealCreator(0, bob);
        vm.stopPrank();
        (,,,, address realCreator) = glayzeManager.posts(0);
        assertEq(realCreator, bob, "Real creator should be set");
    }

    function testSetRealCreatorRevertsWithCreatorAlreadyExists() public {
        vm.startPrank(owner);
        USDC.mint(owner, glayzeManager.usdcCreationPayment());
        USDC.approve(address(glayzeManager), glayzeManager.usdcCreationPayment());
        glayzeManager.createPost(0, "Test Post", "TST", "");
        glayzeManager.setRealCreator(0, bob);
        vm.expectRevert(abi.encodeWithSelector(GlayzeManager.RealCreatorAlreadyExists.selector, 0, bob));
        glayzeManager.setRealCreator(0, bob);
        vm.stopPrank();
    }

    function testSetRealCreatorRevertsWithInvalidPostId() public {
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(GlayzeManager.InvalidPostId.selector, 0));
        glayzeManager.setRealCreator(0, bob);
        vm.stopPrank();
    }

    function testSetRealCreatorRevertsWithNotOwner() public {
        vm.startPrank(alice);
        vm.expectRevert("UNAUTHORIZED");
        glayzeManager.setRealCreator(0, bob);
        vm.stopPrank();
    }
}
