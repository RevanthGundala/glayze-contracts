// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import "forge-std/Console2.sol";
import {GlayzeManager} from "../../src/GlayzeManager.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployGlayzeManager} from "../../script/DeployGlayzeManager.s.sol";

contract GlayzeManagerTest is Test {
    GlayzeManager public glayzeManager;
    HelperConfig public helperConfig;

    address public owner;
    address public alice = address(1);
    address public bob = address(2);
    ERC20Mock public USDC;
    ERC20Mock public GLAYZE;
    uint256 public constant STARTING_USER_BALANCE = 1000000e6;
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e6;

    event PostCreated(uint256 postId, address creator, string name, string symbol, string postURI, uint256 timestamp);
    event Trade(
        uint256 postId,
        address trader,
        bool isBuy,
        uint256 glayzeAmount,
        uint256 usdcAmount,
        uint256 tokenAmount,
        uint256 newSupply,
        uint256 newPrice,
        uint256 timestamp
    );

    event TradeFees(
        uint256 postId, uint256 protocolFee, uint256 contractCreatorFee, uint256 realCreatorFee, uint256 timestamp
    );
    event RealCreatorSet(uint256 postId, address realCreator, uint256 timestamp);
    event Refer(address userReferred, address referredBy, uint256 timestamp);

    function setUp() public {
        DeployGlayzeManager deployer = new DeployGlayzeManager();
        (glayzeManager, helperConfig) = deployer.run();
        owner = glayzeManager.owner();
        (address usdc, address glayze,) = helperConfig.activeNetworkConfig();
        USDC = ERC20Mock(usdc);
        GLAYZE = ERC20Mock(glayze);
    }

    function testInitialSetup() public view {
        assertTrue(address(glayzeManager) != address(0), "Contract should be deployed");
    }

    function testCanCreatePost() public {
        vm.startPrank(alice);

        string memory name = "Test Post";
        string memory symbol = "TST";
        string memory postURI = "";

        // Approve USDC spending
        USDC.mint(alice, STARTING_USER_BALANCE);
        USDC.approve(address(glayzeManager), glayzeManager.USDC_CREATION_PAYMENT());

        // Expect the PostCreated event
        vm.expectEmit(true, true, true, true);
        emit PostCreated(0, alice, name, symbol, postURI, block.timestamp);

        // Call the function that should emit the event
        glayzeManager.createPost(name, symbol, postURI);

        // Check the post details
        (
            string memory postName,
            string memory postSymbol,
            string memory postURIResult,
            address contractCreator,
            address realCreator
        ) = glayzeManager.posts(0);

        assertEq(postName, name, "Name should be set");
        assertEq(postSymbol, symbol, "Symbol should be set");
        assertEq(postURIResult, postURI, "Post URI should be set");
        assertEq(contractCreator, alice, "Contract creator should be set");
        assertEq(realCreator, address(0), "Real creator should be set");
        assertEq(glayzeManager.postIdCounter(), 1, "Post should be created");
        assertEq(
            glayzeManager.balanceOf(address(glayzeManager), 0),
            glayzeManager.MAX_SUPPLY(),
            "Contract should have max supply of new token"
        );
        assertEq(USDC.balanceOf(owner), glayzeManager.USDC_CREATION_PAYMENT(), "Owner should receive USDC payment");
        assertEq(
            USDC.balanceOf(alice),
            STARTING_USER_BALANCE - glayzeManager.USDC_CREATION_PAYMENT(),
            "Alice's USDC balance should decrease"
        );

        vm.stopPrank();
    }

    function testCreatePostRevertsWithInsufficientBalance() public {
        vm.startPrank(alice);

        USDC.approve(address(glayzeManager), glayzeManager.USDC_CREATION_PAYMENT());
        // Expect the revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, glayzeManager.USDC_CREATION_PAYMENT()
            )
        );

        glayzeManager.createPost("Test Post", "TST", "");

        vm.stopPrank();
    }

    function testBuyTokensWithoutGlayze() public {
        USDC.mint(alice, STARTING_USER_BALANCE);
        USDC.mint(owner, STARTING_USER_BALANCE);
        vm.startPrank(alice);
        USDC.approve(address(glayzeManager), glayzeManager.MAX_SUPPLY());
        glayzeManager.createPost("Test Post", "TST", "");
        uint256 aliceUsdcBalance = USDC.balanceOf(alice);
        uint256 buyPrice = glayzeManager.getBuyPriceAfterFees(0, 1);
        glayzeManager.buyTokens(0, 100, 0);
        // vm.expectEmit(true, true, true, true);
        // emit Trade(0, alice, true, 1, 1, 1, 1, block.timestamp);
        assertEq(glayzeManager.balanceOf(alice, 0), 1, "Alice should have bought 1 token");
        assertEq(USDC.balanceOf(alice), aliceUsdcBalance - buyPrice, "Alice should have paid the correct amount");
        vm.stopPrank();
    }

    // function testBuyTokensWithGlayzeWithRealCreator() public {}

    // function testBuyTokensWithGlayzeWithoutRealCreator() public {}

    // function testBuyTokensRevertsWithInsufficientBalance() public {}

    function testBuyTokensRevertsWithInvalidPostId() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(GlayzeManager.InvalidPostId.selector, 0));
        glayzeManager.buyTokens(0, 1, 0);
        vm.stopPrank();
    }

    // function testSellTokensWithoutGlayze() public {}

    // function testSellTokensWithGlayzeWithRealCreator() public {}

    // function testSellTokensWithGlayzeWithoutRealCreator() public {}

    // function testSellTokensRevertsWithInsufficientBalance() public {}

    // function testSellTokensRevertsWithInsufficientSupply() public {}

    // function testSellTokensRevertsWithInsufficientTokenBalance() public {}

    function testSellTokensRevertsWithInvalidPostId() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(GlayzeManager.InvalidPostId.selector, 0));
        glayzeManager.sellTokens(0, 1, 0);
        vm.stopPrank();
    }

    function testCanReferUser() public {
        // Mint GLAYZE tokens to the owner first
        uint256 referralAmount = glayzeManager.GLAYZE_REFERRAL_AMOUNT();
        GLAYZE.mint(owner, referralAmount * 2); // Double the amount for both transfers
        // Owner approves GlayzeManager to spend GLAYZE tokens

        vm.startPrank(owner);
        GLAYZE.approve(address(glayzeManager), referralAmount * 2);
        // Perform the referral
        glayzeManager.refer(bob, alice);

        vm.stopPrank();

        // Assert that Bob is now referred
        assertEq(glayzeManager.usersReferred(bob), true, "User should be referred");

        // Check that Bob received the referral amount
        assertEq(GLAYZE.balanceOf(bob), referralAmount, "Bob should have received the referral amount");

        // Check that the owner (referrer) also received the referral amount
        assertEq(GLAYZE.balanceOf(alice), referralAmount, "Owner should have received the referral amount");
    }

    function testReferUserRevertsWithUserAlreadyReferred() public {
        uint256 referralAmount = glayzeManager.GLAYZE_REFERRAL_AMOUNT();
        GLAYZE.mint(owner, referralAmount * 2); // Double the amount for both transfers
        vm.startPrank(owner);
        GLAYZE.approve(address(glayzeManager), referralAmount * 2);
        glayzeManager.refer(bob, alice);
        vm.expectRevert(abi.encodeWithSelector(GlayzeManager.UserAlreadyReferred.selector, bob));
        glayzeManager.refer(bob, alice);
        vm.stopPrank();
    }

    function testCanSetRealCreator() public {
        vm.startPrank(owner);
        // Call the function that should emit the event
        USDC.mint(owner, glayzeManager.USDC_CREATION_PAYMENT());
        USDC.approve(address(glayzeManager), glayzeManager.USDC_CREATION_PAYMENT());
        glayzeManager.createPost("Test Post", "TST  ", "");
        glayzeManager.setRealCreator(0, bob);
        vm.stopPrank();
        (,,,, address realCreator) = glayzeManager.posts(0);
        assertEq(realCreator, bob, "Real creator should be set");
    }

    function testSetRealCreatorRevertsWithCreatorAlreadyExists() public {
        vm.startPrank(owner);
        USDC.mint(owner, glayzeManager.USDC_CREATION_PAYMENT());
        USDC.approve(address(glayzeManager), glayzeManager.USDC_CREATION_PAYMENT());
        glayzeManager.createPost("Test Post", "TST  ", "");
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

    function testBuyPriceShouldBeZero() public {
        USDC.mint(alice, glayzeManager.USDC_CREATION_PAYMENT());
        vm.startPrank(alice);
        USDC.approve(address(glayzeManager), glayzeManager.USDC_CREATION_PAYMENT());
        glayzeManager.createPost("Test Post", "TST", "");
        vm.stopPrank();
        uint256 price = glayzeManager.getBuyPrice(0, 1);
        assertEq(price, 0, "Price should be 0");
    }

    // function testCanGetBuyPriceAfterFees() public view {
    //     uint256 price = glayzeManager.getBuyPriceAfterFees(100, 100);
    //     console2.log("Price: ", price);
    // }

    // function testCanGetSellPriceAfterFees() public view {
    //     uint256 price = glayzeManager.getSellPriceAfterFees(100, 100);
    //     console2.log("Price: ", price);
    // }

    // function testCanGetBuyPrice() public view {
    //     uint256 price = glayzeManager.getBuyPrice(1000000000000000000, 1000000000000000000);
    //     console2.log("Price: ", price);
    // }

    // function testCanGetSellPrice() public view {
    //     uint256 price = glayzeManager.getSellPrice(1000, 100);
    //     console2.log("Price: ", price);
    // }

    // function testCanGetPrice() public view {
    //     uint256 price = glayzeManager.getPrice(1000000000000000000, 1000000000000000000);
    //     console2.log("Price: ", price);
    // }
}
