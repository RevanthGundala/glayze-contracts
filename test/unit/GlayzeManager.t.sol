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
    uint256 public constant STARTING_USER_BALANCE = 10000000000e6;
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
        GLAYZE.mint(owner, glayzeManager.MAX_SUPPLY());
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

    function testBuyTokensWithoutGlayzeWithoutRealCreator() public {
        vm.startPrank(address(glayzeManager));
        glayzeManager.approve(address(glayzeManager), 0, type(uint256).max);
        vm.stopPrank();

        USDC.mint(alice, STARTING_USER_BALANCE);
        vm.startPrank(alice);

        // Approve GlayzeManager to spend Alice's USDC
        USDC.approve(address(glayzeManager), type(uint256).max);
        glayzeManager.createPost("Test Post", "TST", "");
        uint256 initialAliceUsdcBalance = USDC.balanceOf(alice);
        uint256 initialContractBalance = glayzeManager.balanceOf(address(glayzeManager), 0);
        uint256 initialAliceBalance = glayzeManager.balanceOf(alice, 0);
        uint256 initialOwnerBalance = USDC.balanceOf(owner);

        uint256 buyAmount = 100;
        uint256 buyPriceAfterFees = glayzeManager.getBuyPriceAfterFees(0, buyAmount);
        uint256 buyPrice = glayzeManager.getBuyPrice(0, buyAmount);

        (uint256 protocolFee, uint256 contractCreatorFee, uint256 realCreatorFee) =
            glayzeManager.getFeeSplit(0, buyPrice);

        // Expect the Trade event
        vm.expectEmit(true, true, true, true);
        emit Trade(0, alice, true, 0, buyPrice, buyAmount, 100, buyPrice, block.timestamp);

        // Expect the TradeFees event
        vm.expectEmit(true, true, true, true);
        emit TradeFees(0, protocolFee, contractCreatorFee, realCreatorFee, block.timestamp);

        // Buy tokens
        glayzeManager.buyTokens(0, buyAmount, 0);

        // Tokens
        assertEq(
            glayzeManager.balanceOf(alice, 0), initialAliceBalance + buyAmount, "Alice should have bought 100 tokens"
        );
        assertEq(
            glayzeManager.balanceOf(address(glayzeManager), 0),
            initialContractBalance - buyAmount,
            "Contract balance should decrease by 100"
        );

        // USDC
        assertEq(USDC.balanceOf(address(glayzeManager)), buyPrice, "Contract should be paid");
        assertEq(
            USDC.balanceOf(owner),
            initialOwnerBalance + protocolFee + realCreatorFee,
            "Owner should have received the protocol fee"
        );
        assertEq(
            USDC.balanceOf(alice),
            initialAliceUsdcBalance - buyPriceAfterFees + contractCreatorFee,
            "Alice should have received the contract creator fee"
        );

        assertEq(glayzeManager.totalValueDeposited(), buyPrice, "Total value deposited should be the buy price");
        vm.stopPrank();
    }

    function testBuyTokensWithoutGlayzeWithRealCreator() public {
        USDC.mint(alice, STARTING_USER_BALANCE);
        vm.startPrank(alice);

        // Approve GlayzeManager to spend Alice's USDC
        USDC.approve(address(glayzeManager), type(uint256).max);

        glayzeManager.createPost("Test Post", "TST", "");
        vm.stopPrank();

        vm.startPrank(owner);
        glayzeManager.setRealCreator(0, bob);
        vm.stopPrank();
        (,,,, address realCreator) = glayzeManager.posts(0);
        assertEq(realCreator, bob, "Real creator should be set");
        vm.startPrank(alice);
        uint256 initialAliceUsdcBalance = USDC.balanceOf(alice);
        uint256 initialContractBalance = glayzeManager.balanceOf(address(glayzeManager), 0);
        uint256 initialAliceBalance = glayzeManager.balanceOf(alice, 0);
        uint256 initialOwnerBalance = USDC.balanceOf(owner);
        uint256 initialBobBalance = USDC.balanceOf(bob);

        uint256 buyAmount = 100;
        uint256 buyPriceAfterFees = glayzeManager.getBuyPriceAfterFees(0, buyAmount);
        uint256 buyPrice = glayzeManager.getBuyPrice(0, buyAmount);

        (uint256 protocolFee, uint256 contractCreatorFee, uint256 realCreatorFee) =
            glayzeManager.getFeeSplit(0, buyPrice);

        // Expect the Trade event
        vm.expectEmit(true, true, true, true);
        emit Trade(0, alice, true, 0, buyPrice, buyAmount, 100, buyPrice, block.timestamp);

        // Expect the TradeFees event
        vm.expectEmit(true, true, true, true);
        emit TradeFees(0, protocolFee, contractCreatorFee, realCreatorFee, block.timestamp);

        // Buy tokens
        glayzeManager.buyTokens(0, buyAmount, 0);

        // Assertions
        // Tokens
        assertEq(
            glayzeManager.balanceOf(alice, 0), initialAliceBalance + buyAmount, "Alice should have bought 100 tokens"
        );
        assertEq(
            glayzeManager.balanceOf(address(glayzeManager), 0),
            initialContractBalance - buyAmount,
            "Contract balance should decrease by 100"
        );

        // USDC
        assertEq(USDC.balanceOf(address(glayzeManager)), buyPrice, "Contract should be paid");
        assertEq(
            USDC.balanceOf(owner), initialOwnerBalance + protocolFee, "Owner should have received the protocol fee"
        );
        assertEq(
            USDC.balanceOf(bob), initialBobBalance + realCreatorFee, "Bob should have received the real creator fee"
        );
        assertEq(
            USDC.balanceOf(alice),
            initialAliceUsdcBalance - buyPriceAfterFees + contractCreatorFee,
            "Alice should have received the contract creator fee"
        );
        assertEq(glayzeManager.totalValueDeposited(), buyPrice, "Total value deposited should be the buy price");
        vm.stopPrank();
    }

    function testBuyTokensWithGlayzeGreaterThanProtocolFeeWithoutRealCreator() public {
        USDC.mint(alice, STARTING_USER_BALANCE);
        GLAYZE.mint(alice, STARTING_USER_BALANCE);
        vm.startPrank(alice);

        // Approve GlayzeManager to spend Alice's USDC
        USDC.approve(address(glayzeManager), type(uint256).max);
        GLAYZE.approve(address(glayzeManager), type(uint256).max);

        glayzeManager.createPost("Test Post", "TST", "");

        uint256 initialAliceUsdcBalance = USDC.balanceOf(alice);
        uint256 initialContractBalance = glayzeManager.balanceOf(address(glayzeManager), 0);
        uint256 initialAliceBalance = glayzeManager.balanceOf(alice, 0);
        uint256 initialOwnerBalance = USDC.balanceOf(owner);
        uint256 initialAliceGlayzeBalance = GLAYZE.balanceOf(alice);

        uint256 buyAmount = 100;
        uint256 buyPriceAfterFees = glayzeManager.getBuyPriceAfterFees(0, buyAmount);
        uint256 buyPrice = glayzeManager.getBuyPrice(0, buyAmount);

        (uint256 protocolFee, uint256 contractCreatorFee, uint256 realCreatorFee) =
            glayzeManager.getFeeSplit(0, buyPrice);

        // Expect the Trade event
        vm.expectEmit(true, true, true, true);
        emit Trade(0, alice, true, 100, buyPrice, buyAmount, 100, buyPrice, block.timestamp);

        // Expect the TradeFees event
        vm.expectEmit(true, true, true, true);
        emit TradeFees(0, protocolFee, contractCreatorFee, realCreatorFee, block.timestamp);

        // Buy tokens
        glayzeManager.buyTokens(0, buyAmount, 100);

        // Tokens
        assertEq(
            glayzeManager.balanceOf(alice, 0), initialAliceBalance + buyAmount, "Alice should have bought 100 tokens"
        );
        assertEq(
            glayzeManager.balanceOf(address(glayzeManager), 0),
            initialContractBalance - buyAmount,
            "Contract balance should decrease by 100"
        );

        // USDC
        assertEq(USDC.balanceOf(address(glayzeManager)), buyPrice, "Contract should be paid");
        assertEq(
            USDC.balanceOf(owner), initialOwnerBalance + realCreatorFee, "Owner should have received the protocol fee"
        );
        assertEq(
            USDC.balanceOf(alice),
            initialAliceUsdcBalance - buyPriceAfterFees + contractCreatorFee + protocolFee,
            "Alice should have not used usdc for protocol fee"
        );
        assertEq(
            GLAYZE.balanceOf(alice), initialAliceGlayzeBalance - protocolFee, "Alice should have her new glayze amount"
        );

        assertEq(glayzeManager.totalValueDeposited(), buyPrice, "Total value deposited should be the buy price");
        vm.stopPrank();
    }

    function testBuyTokensWithGlayzeLessThanProtocolFeeWithoutRealCreator() public {
        USDC.mint(alice, STARTING_USER_BALANCE);
        GLAYZE.mint(alice, STARTING_USER_BALANCE);
        vm.startPrank(alice);

        // Approve GlayzeManager to spend Alice's USDC
        USDC.approve(address(glayzeManager), type(uint256).max);
        GLAYZE.approve(address(glayzeManager), type(uint256).max);

        glayzeManager.createPost("Test Post", "TST", "");

        uint256 initialAliceUsdcBalance = USDC.balanceOf(alice);
        uint256 initialContractBalance = glayzeManager.balanceOf(address(glayzeManager), 0);
        uint256 initialAliceBalance = glayzeManager.balanceOf(alice, 0);
        uint256 initialOwnerBalance = USDC.balanceOf(owner);
        uint256 initialAliceGlayzeBalance = GLAYZE.balanceOf(alice);

        uint256 buyPriceAfterFees = glayzeManager.getBuyPriceAfterFees(0, 100);
        uint256 buyPrice = glayzeManager.getBuyPrice(0, 100);

        (uint256 protocolFee, uint256 contractCreatorFee, uint256 realCreatorFee) =
            glayzeManager.getFeeSplit(0, buyPrice);

        // Expect the Trade event
        vm.expectEmit(true, true, true, true);
        emit Trade(0, alice, true, 1, buyPrice, 100, 100, buyPrice, block.timestamp);

        // Expect the TradeFees event
        vm.expectEmit(true, true, true, true);
        emit TradeFees(0, protocolFee, contractCreatorFee, realCreatorFee, block.timestamp);

        // Buy tokens
        glayzeManager.buyTokens(0, 100, 1);

        // Tokens
        assertEq(glayzeManager.balanceOf(alice, 0), initialAliceBalance + 100, "Alice should have bought 100 tokens");
        assertEq(
            glayzeManager.balanceOf(address(glayzeManager), 0),
            initialContractBalance - 100,
            "Contract balance should decrease by 100"
        );

        // USDC
        assertEq(USDC.balanceOf(address(glayzeManager)), buyPrice, "Contract should be paid");
        assertEq(
            USDC.balanceOf(owner),
            initialOwnerBalance + realCreatorFee + protocolFee - 1,
            "Owner should have received the protocol fee"
        );
        assertEq(
            USDC.balanceOf(alice),
            initialAliceUsdcBalance - buyPriceAfterFees + contractCreatorFee + 1,
            "Alice should have used usdc for protocol fee"
        );
        assertEq(GLAYZE.balanceOf(alice), initialAliceGlayzeBalance - 1, "Alice should have her new glayze amount");

        assertEq(glayzeManager.totalValueDeposited(), buyPrice, "Total value deposited should be the buy price");
        vm.stopPrank();
    }

    function testBuyTokensWithGlayzeLessThanProtocolFeeWithRealCreator() public {
        USDC.mint(alice, STARTING_USER_BALANCE);
        GLAYZE.mint(alice, STARTING_USER_BALANCE);
        vm.startPrank(alice);

        // Approve GlayzeManager to spend Alice's USDC
        USDC.approve(address(glayzeManager), type(uint256).max);
        GLAYZE.approve(address(glayzeManager), type(uint256).max);

        glayzeManager.createPost("Test Post", "TST", "");
        vm.stopPrank();

        vm.startPrank(owner);
        glayzeManager.setRealCreator(0, bob);
        vm.stopPrank();
        (,,,, address realCreator) = glayzeManager.posts(0);
        assertEq(realCreator, bob, "Real creator should be set");
        vm.startPrank(alice);
        uint256 initialAliceUsdcBalance = USDC.balanceOf(alice);
        uint256 initialContractBalance = glayzeManager.balanceOf(address(glayzeManager), 0);
        uint256 initialAliceBalance = glayzeManager.balanceOf(alice, 0);
        uint256 initialOwnerBalance = USDC.balanceOf(owner);
        uint256 initialBobBalance = USDC.balanceOf(bob);

        uint256 buyPriceAfterFees = glayzeManager.getBuyPriceAfterFees(0, 100);
        uint256 buyPrice = glayzeManager.getBuyPrice(0, 100);

        (uint256 protocolFee, uint256 contractCreatorFee, uint256 realCreatorFee) =
            glayzeManager.getFeeSplit(0, buyPrice);

        // Expect the Trade event
        vm.expectEmit(true, true, true, true);
        emit Trade(0, alice, true, 1, buyPrice, 100, 100, buyPrice, block.timestamp);

        // Expect the TradeFees event
        vm.expectEmit(true, true, true, true);
        emit TradeFees(0, protocolFee, contractCreatorFee, realCreatorFee, block.timestamp);

        // Buy tokens
        glayzeManager.buyTokens(0, 100, 1);

        // Assertions
        // Tokens
        assertEq(glayzeManager.balanceOf(alice, 0), initialAliceBalance + 100, "Alice should have bought 100 tokens");
        assertEq(
            glayzeManager.balanceOf(address(glayzeManager), 0),
            initialContractBalance - 100,
            "Contract balance should decrease by 100"
        );

        // USDC
        assertEq(USDC.balanceOf(address(glayzeManager)), buyPrice, "Contract should be paid");
        assertEq(
            USDC.balanceOf(owner), initialOwnerBalance + protocolFee - 1, "Owner should have received the protocol fee"
        );
        assertEq(
            USDC.balanceOf(bob), initialBobBalance + realCreatorFee, "Bob should have received the real creator fee"
        );
        assertEq(
            USDC.balanceOf(alice),
            initialAliceUsdcBalance - buyPriceAfterFees + contractCreatorFee + 1,
            "Alice should have received the contract creator fee"
        );
        assertEq(glayzeManager.totalValueDeposited(), buyPrice, "Total value deposited should be the buy price");
        vm.stopPrank();
    }

    function testBuyTokensRevertsWithERC20InsufficientBalance() public {
        USDC.mint(alice, glayzeManager.USDC_CREATION_PAYMENT());
        vm.startPrank(alice);

        // Approve GlayzeManager to spend Alice's USDC
        USDC.approve(address(glayzeManager), type(uint256).max);
        glayzeManager.createPost("Test Post", "TST", "");
        uint256 buyPrice = glayzeManager.getBuyPrice(0, 100);
        (uint256 protocolFee,,) = glayzeManager.getFeeSplit(0, buyPrice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, protocolFee));

        // Buy tokens
        glayzeManager.buyTokens(0, 100, 0);
        vm.stopPrank();
    }

    function testBuyTokensRevertsWithInvalidPostId() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(GlayzeManager.InvalidPostId.selector, 0));
        glayzeManager.buyTokens(0, 1, 0);
        vm.stopPrank();
    }

    function testBuyTokensRevertsWithTokenAmountZero() public {
        vm.startPrank(alice);
        USDC.mint(alice, STARTING_USER_BALANCE);
        USDC.approve(address(glayzeManager), glayzeManager.USDC_CREATION_PAYMENT());
        glayzeManager.createPost("Test Post", "TST", "");
        vm.expectRevert(abi.encodeWithSelector(GlayzeManager.TokenAmountZero.selector, 0));
        glayzeManager.buyTokens(0, 0, 0);
        vm.stopPrank();
    }

    function testSellTokensWithoutGlayze() public {
        USDC.mint(alice, STARTING_USER_BALANCE);
        vm.startPrank(alice);

        // Approve GlayzeManager to spend Alice's USDC
        USDC.approve(address(glayzeManager), type(uint256).max);

        glayzeManager.createPost("Test Post", "TST", "");

        // Buy tokens
        glayzeManager.buyTokens(0, 100, 0);
        uint256 sellAmount = 100;
        uint256 initialAliceUsdcBalance = USDC.balanceOf(alice);
        uint256 initialContractBalance = glayzeManager.balanceOf(address(glayzeManager), 0);
        uint256 initialAliceBalance = glayzeManager.balanceOf(alice, 0);
        uint256 initialOwnerBalance = USDC.balanceOf(owner);
        uint256 sellPrice = glayzeManager.getSellPrice(0, sellAmount);
        uint256 sellPriceAfterFees = glayzeManager.getSellPriceAfterFees(0, sellAmount);
        (uint256 protocolFee, uint256 contractCreatorFee, uint256 realCreatorFee) =
            glayzeManager.getFeeSplit(0, sellPrice);

        vm.expectEmit(true, true, true, true);
        emit Trade(0, alice, false, 0, sellPrice, sellAmount, 0, 0, block.timestamp);

        vm.expectEmit(true, true, true, true);
        emit TradeFees(0, protocolFee, contractCreatorFee, realCreatorFee, block.timestamp);

        glayzeManager.sellTokens(0, sellAmount, 0);

        // Tokens
        assertEq(
            glayzeManager.balanceOf(alice, 0), initialAliceBalance - sellAmount, "Alice should have sold 100 tokens"
        );
        assertEq(
            glayzeManager.balanceOf(address(glayzeManager), 0),
            initialContractBalance + sellAmount,
            "Contract balance should increase by 100"
        );

        // USDC
        assertEq(
            USDC.balanceOf(alice),
            initialAliceUsdcBalance + sellPriceAfterFees + contractCreatorFee,
            "Alice should have received the buy amount"
        );
        assertEq(
            USDC.balanceOf(owner),
            initialOwnerBalance + protocolFee + realCreatorFee,
            "Owner should have received the protocol fee"
        );

        assertEq(
            glayzeManager.totalValueDeposited(),
            glayzeManager.getBuyPrice(0, 100) - sellPrice,
            "Total value deposited should be buy - sell price"
        );
        vm.stopPrank();
    }

    // function testSellTokensWithGlayzeWithRealCreator() public {}

    function testSellTokensWithGlayzeWithoutRealCreator() public {
        USDC.mint(alice, STARTING_USER_BALANCE);
        GLAYZE.mint(alice, 100);
        vm.startPrank(alice);

        // Approve GlayzeManager to spend Alice's USDC
        USDC.approve(address(glayzeManager), type(uint256).max);
        GLAYZE.approve(address(glayzeManager), 100);

        glayzeManager.createPost("Test Post", "TST", "");

        // Buy tokens
        glayzeManager.buyTokens(0, 100, 0);
        uint256 sellAmount = 100;
        uint256 initialAliceUsdcBalance = USDC.balanceOf(alice);
        uint256 initialContractBalance = glayzeManager.balanceOf(address(glayzeManager), 0);
        uint256 initialAliceBalance = glayzeManager.balanceOf(alice, 0);
        uint256 initialOwnerBalance = USDC.balanceOf(owner);
        uint256 sellPrice = glayzeManager.getSellPrice(0, sellAmount);
        uint256 sellPriceAfterFees = glayzeManager.getSellPriceAfterFees(0, sellAmount);
        (uint256 protocolFee, uint256 contractCreatorFee, uint256 realCreatorFee) =
            glayzeManager.getFeeSplit(0, sellPrice);

        glayzeManager.sellTokens(0, sellAmount, 100);

        // Tokens
        assertEq(
            glayzeManager.balanceOf(alice, 0), initialAliceBalance - sellAmount, "Alice should have sold 100 tokens"
        );
        assertEq(
            glayzeManager.balanceOf(address(glayzeManager), 0),
            initialContractBalance + sellAmount,
            "Contract balance should increase by 100"
        );

        // USDC
        assertEq(
            USDC.balanceOf(alice),
            initialAliceUsdcBalance + sellPriceAfterFees + contractCreatorFee + protocolFee,
            "Alice should have received the buy amount"
        );
        assertEq(
            USDC.balanceOf(owner), initialOwnerBalance + realCreatorFee, "Owner should have received the protocol fee"
        );

        assertEq(
            glayzeManager.totalValueDeposited(),
            glayzeManager.getBuyPrice(0, 100) - sellPrice,
            "Total value deposited should be buy - sell price"
        );
        vm.stopPrank();
    }

    function testSellTokensRevertsWithInsufficientTokenSupply() public {
        vm.startPrank(address(glayzeManager));
        glayzeManager.approve(address(glayzeManager), 0, type(uint256).max);
        vm.stopPrank();

        USDC.mint(alice, STARTING_USER_BALANCE);
        vm.startPrank(alice);

        // Approve GlayzeManager to spend Alice's USDC
        USDC.approve(address(glayzeManager), type(uint256).max);
        glayzeManager.createPost("Test Post", "TST", "");

        uint256 buyAmount = 100;
        // Buy tokens
        glayzeManager.buyTokens(0, buyAmount, 0);
        vm.expectRevert(abi.encodeWithSelector(GlayzeManager.InsufficientTokenSupply.selector, 0, buyAmount));
        glayzeManager.sellTokens(0, buyAmount + 1, 0);

        // Tokens
        vm.stopPrank();
    }

    function testSellTokensRevertsWithInsufficientTokenBalance() public {
        USDC.mint(alice, STARTING_USER_BALANCE);
        USDC.mint(owner, STARTING_USER_BALANCE);
        vm.startPrank(alice);
        USDC.approve(address(glayzeManager), type(uint256).max);
        glayzeManager.createPost("Test Post", "TST", "");
        uint256 buyAmount = 100;
        glayzeManager.buyTokens(0, buyAmount, 0);
        vm.stopPrank();

        vm.startPrank(owner);
        USDC.approve(address(glayzeManager), type(uint256).max);
        glayzeManager.buyTokens(0, buyAmount, 0);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(GlayzeManager.InsufficientTokenBalance.selector, 0, alice, buyAmount));
        glayzeManager.sellTokens(0, buyAmount + 1, 0);
        vm.stopPrank();
    }

    function testSellTokensRevertsWithInvalidPostId() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(GlayzeManager.InvalidPostId.selector, 0));
        glayzeManager.sellTokens(0, 1, 0);
        vm.stopPrank();
    }

    function testSellTokensRevertsWithTokenAmountZero() public {
        vm.startPrank(alice);
        USDC.mint(alice, STARTING_USER_BALANCE);
        USDC.approve(address(glayzeManager), glayzeManager.USDC_CREATION_PAYMENT());

        // Call the function that should emit the event
        glayzeManager.createPost("Test Post", "TST", "");

        vm.expectRevert(abi.encodeWithSelector(GlayzeManager.TokenAmountZero.selector, 0));
        glayzeManager.sellTokens(0, 0, 0);
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

    function testGetFeeSplit() public {
        USDC.mint(alice, glayzeManager.USDC_CREATION_PAYMENT());
        vm.startPrank(alice);
        USDC.approve(address(glayzeManager), glayzeManager.USDC_CREATION_PAYMENT());
        glayzeManager.createPost("Test Post", "TST  ", "");
        uint256 price = glayzeManager.getBuyPrice(0, 1);
        uint256 priceAfterFees = glayzeManager.getBuyPriceAfterFees(0, 1);
        (uint256 protocolFee, uint256 contractCreatorFee, uint256 realCreatorFee) = glayzeManager.getFeeSplit(0, price);
        assertEq(
            protocolFee,
            price * glayzeManager.PROTOCOL_FEE() / glayzeManager.DECIMALS(),
            "Protocol fee should be correct"
        );
        assertEq(
            contractCreatorFee,
            price * glayzeManager.CONTRACT_CREATOR_FEE() / glayzeManager.DECIMALS(),
            "Contract creator fee should be correct"
        );
        assertEq(
            realCreatorFee,
            price * glayzeManager.REAL_CREATOR_FEE() / glayzeManager.DECIMALS(),
            "Real creator fee should be correct"
        );
        assertEq(
            priceAfterFees,
            price + protocolFee + contractCreatorFee + realCreatorFee,
            "Price after fees should be correct"
        );
        vm.stopPrank();
    }

    function testGetTotalFees() public {
        USDC.mint(alice, glayzeManager.USDC_CREATION_PAYMENT());
        vm.startPrank(alice);
        USDC.approve(address(glayzeManager), glayzeManager.USDC_CREATION_PAYMENT());
        glayzeManager.createPost("Test Post", "TST  ", "");
        uint256 buyPrice = glayzeManager.getBuyPrice(0, 1000);
        uint256 totalFees = glayzeManager.getTotalFees(0, buyPrice);
        uint256 buyPriceAfterFees = glayzeManager.getBuyPriceAfterFees(0, 1000);
        assertEq(totalFees, buyPriceAfterFees - buyPrice, "Total fees should be correct");
    }
}
