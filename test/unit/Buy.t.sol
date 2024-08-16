// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import "forge-std/Console2.sol";
import {GlayzeManager} from "../../src/GlayzeManager.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployGlayzeManager} from "../../script/DeployGlayzeManager.s.sol";
import {FixedPointMathLib} from "../../src/lib/FixedPointMathLib.sol";

contract Buy is Test {
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

    function testBuySharesWithoutAuraWithoutRealCreator() public {
        vm.startPrank(address(glayzeManager));
        glayzeManager.approve(address(glayzeManager), 0, type(uint256).max);
        vm.stopPrank();
        USDC.mint(alice, STARTING_USER_BALANCE);
        vm.startPrank(alice);
        buySharesWithoutAura(address(0));
        vm.stopPrank();
    }

    function testBuySharesWithoutAuraWithRealCreator() public {
        vm.startPrank(address(glayzeManager));
        glayzeManager.approve(address(glayzeManager), 0, type(uint256).max);
        vm.stopPrank();
        USDC.mint(alice, STARTING_USER_BALANCE);
        vm.startPrank(alice);
        buySharesWithoutAura(bob);
        vm.stopPrank();
    }

    function testBuySharesWithAuraGreaterThanFeesWithoutRealCreator() public {
        vm.startPrank(address(glayzeManager));
        glayzeManager.approve(address(glayzeManager), 0, type(uint256).max);
        vm.stopPrank();
        USDC.mint(alice, STARTING_USER_BALANCE);
        vm.startPrank(alice);
        buySharesWithAura(100, (address(0)));
        vm.stopPrank();
    }

    function testBuySharesWithAuraLessThanFeesWithoutRealCreator() public {}

    function testBuySharesWithAuraGreaterThanFeesWithRealCreator() public {}

    function testBuySharesWithAuraLessThanFeesWithRealCreator() public {}

    // function testBuySharesWithAuraGreaterThanFeesWithoutRealCreator() public {
    //     USDC.mint(alice, STARTING_USER_BALANCE);
    //     AURA.mint(alice, STARTING_USER_BALANCE);
    //     vm.startPrank(alice);

    //     // Approve GlayzeManager to spend Alice's USDC
    //     USDC.approve(address(glayzeManager), type(uint256).max);
    //     AURA.approve(address(glayzeManager), type(uint256).max);

    //     glayzeManager.createPost("Test Post", "TST", "");

    //     uint256 initialAliceUsdcBalance = USDC.balanceOf(alice);
    //     uint256 initialContractBalance = glayzeManager.balanceOf(address(glayzeManager), 0);
    //     uint256 initialAliceBalance = glayzeManager.balanceOf(alice, 0);
    //     uint256 initialOwnerBalance = USDC.balanceOf(owner);

    //     uint256 buyAmount = 100;
    //     uint256 buyPriceAfterFees = glayzeManager.getBuyPriceAfterFees(0, buyAmount);
    //     uint256 buyPrice = glayzeManager.getBuyPrice(0, buyAmount);

    //     // Expect the Trade event
    //     vm.expectEmit(true, true, true, true);
    //     emit Trade(0, alice, true, 100, buyPrice, buyAmount, 100, buyPrice, block.timestamp);

    //     // Expect the TradeFees event
    //     // vm.expectEmit(true, true, true, true);
    //     // emit TradeFees(0, protocolFee, contractCreatorFee, realCreatorFee, block.timestamp);

    //     // Buy tokens
    //     glayzeManager.buyShares(0, buyAmount, 100);

    //     // Shares
    //     assertEq(
    //         glayzeManager.balanceOf(alice, 0), initialAliceBalance + buyAmount, "Alice should have bought 100 tokens"
    //     );
    //     assertEq(
    //         glayzeManager.balanceOf(address(glayzeManager), 0),
    //         initialContractBalance - buyAmount,
    //         "Contract balance should decrease by 100"
    //     );

    //     (uint256 auraProtocolFee, uint256 auraGlayzeCreatorFee, uint256 auraRealCreatorFee) =
    //         glayzeManager.getFeeSplit(0, glayzeManager.getTotalFees(0, buyPrice));
    //     // AURA
    //     assertEq(
    //         AURA.balanceOf(alice),
    //         initialAliceGlayzeBalance - auraProtocolFee - auraRealCreatorFee + auraGlayzeCreatorFee,
    //         "Alice should have her new aura amount"
    //     );
    //     assertEq(
    //         AURA.balanceOf(owner),
    //         initialOwnerAuraBalance + auraProtocolFee,
    //         "Owner should have received the protocol fee"
    //     );
    //     assertEq(
    //         AURA.balanceOf(bob),
    //         initialBobAuraBalance + auraRealCreatorFee,
    //         "Bob should have received the real creator fee"
    //     );

    //     // (uint256 usdcProtocolFee, uint256 usdcGlayzeCreatorFee, uint256 usdcRealCreatorFee) =
    //     //     glayzeManager.getFeeSplit(0, buyPrice - 100);
    //     // // USDC
    //     // assertEq(USDC.balanceOf(address(glayzeManager)), buyPrice, "Contract should be paid");
    //     // assertEq(
    //     //     USDC.balanceOf(owner),
    //     //     initialOwnerBalance + usdcProtocolFee + usdcRealCreatorFee,
    //     //     "Owner should have received the protocol fee"
    //     // );
    //     // assertEq(
    //     //     USDC.balanceOf(alice),
    //     //     initialAliceUsdcBalance - buyPriceAfterFees + usdcGlayzeCreatorFee,
    //     //     "Alice should have not used usdc for protocol fee"
    //     // );

    //     // assertEq(glayzeManager.totalValueDeposited(), buyPrice, "Total value deposited should be the buy price");
    //     vm.stopPrank();
    // }

    // function testBuySharesWithAuraLessThanProtocolFeeWithoutRealCreator() public {
    //     USDC.mint(alice, STARTING_USER_BALANCE);
    //     AURA.mint(alice, STARTING_USER_BALANCE);
    //     vm.startPrank(alice);

    //     // Approve GlayzeManager to spend Alice's USDC
    //     USDC.approve(address(glayzeManager), type(uint256).max);
    //     AURA.approve(address(glayzeManager), type(uint256).max);

    //     glayzeManager.createPost("Test Post", "TST", "");

    //     uint256 initialAliceUsdcBalance = USDC.balanceOf(alice);
    //     uint256 initialContractBalance = glayzeManager.balanceOf(address(glayzeManager), 0);
    //     uint256 initialAliceBalance = glayzeManager.balanceOf(alice, 0);
    //     uint256 initialOwnerBalance = USDC.balanceOf(owner);
    //     uint256 initialAliceGlayzeBalance = AURA.balanceOf(alice);

    //     uint256 buyPriceAfterFees = glayzeManager.getBuyPriceAfterFees(0, 100);
    //     uint256 buyPrice = glayzeManager.getBuyPrice(0, 100);

    //     (uint256 protocolFee, uint256 contractCreatorFee, uint256 realCreatorFee) =
    //         glayzeManager.getFeeSplit(0, buyPrice);

    //     // Expect the Trade event
    //     vm.expectEmit(true, true, true, true);
    //     emit Trade(0, alice, true, 1, buyPrice, 100, 100, buyPrice, block.timestamp);

    //     // Expect the TradeFees event
    //     vm.expectEmit(true, true, true, true);
    //     // emit TradeFees(0, protocolFee, contractCreatorFee, realCreatorFee, block.timestamp);

    //     // Buy tokens
    //     glayzeManager.buyShares(0, 100, 1);

    //     // Tokens
    //     assertEq(glayzeManager.balanceOf(alice, 0), initialAliceBalance + 100, "Alice should have bought 100 tokens");
    //     assertEq(
    //         glayzeManager.balanceOf(address(glayzeManager), 0),
    //         initialContractBalance - 100,
    //         "Contract balance should decrease by 100"
    //     );

    //     // USDC
    //     assertEq(USDC.balanceOf(address(glayzeManager)), buyPrice, "Contract should be paid");
    //     assertEq(
    //         USDC.balanceOf(owner),
    //         initialOwnerBalance + realCreatorFee + protocolFee - 1,
    //         "Owner should have received the protocol fee"
    //     );
    //     assertEq(
    //         USDC.balanceOf(alice),
    //         initialAliceUsdcBalance - buyPriceAfterFees + contractCreatorFee + 1,
    //         "Alice should have used usdc for protocol fee"
    //     );
    //     assertEq(AURA.balanceOf(alice), initialAliceGlayzeBalance - 1, "Alice should have her new glayze amount");

    //     assertEq(glayzeManager.totalValueDeposited(), buyPrice, "Total value deposited should be the buy price");
    //     vm.stopPrank();
    // }

    // function testBuySharesWithAuraLessThanProtocolFeeWithRealCreator() public {
    //     USDC.mint(alice, STARTING_USER_BALANCE);
    //     AURA.mint(alice, STARTING_USER_BALANCE);
    //     vm.startPrank(alice);

    //     // Approve GlayzeManager to spend Alice's USDC
    //     USDC.approve(address(glayzeManager), type(uint256).max);
    //     AURA.approve(address(glayzeManager), type(uint256).max);

    //     glayzeManager.createPost("Test Post", "TST", "");
    //     vm.stopPrank();

    //     vm.startPrank(owner);
    //     glayzeManager.setRealCreator(0, bob);
    //     vm.stopPrank();
    //     (,,,, address realCreator) = glayzeManager.posts(0);
    //     assertEq(realCreator, bob, "Real creator should be set");
    //     vm.startPrank(alice);
    //     uint256 initialAliceUsdcBalance = USDC.balanceOf(alice);
    //     uint256 initialContractBalance = glayzeManager.balanceOf(address(glayzeManager), 0);
    //     uint256 initialAliceBalance = glayzeManager.balanceOf(alice, 0);
    //     uint256 initialOwnerBalance = USDC.balanceOf(owner);
    //     uint256 initialBobBalance = USDC.balanceOf(bob);

    //     uint256 buyPriceAfterFees = glayzeManager.getBuyPriceAfterFees(0, 100);
    //     uint256 buyPrice = glayzeManager.getBuyPrice(0, 100);

    //     (uint256 protocolFee, uint256 contractCreatorFee, uint256 realCreatorFee) =
    //         glayzeManager.getFeeSplit(0, buyPrice);

    //     // Expect the Trade event
    //     vm.expectEmit(true, true, true, true);
    //     emit Trade(0, alice, true, 1, buyPrice, 100, 100, buyPrice, block.timestamp);

    //     // Expect the TradeFees event
    //     // vm.expectEmit(true, true, true, true);
    //     // emit TradeFees(0, protocolFee, contractCreatorFee, realCreatorFee, block.timestamp);

    //     // Buy tokens
    //     glayzeManager.buyShares(0, 100, 1);

    //     // Assertions
    //     // Tokens
    //     assertEq(glayzeManager.balanceOf(alice, 0), initialAliceBalance + 100, "Alice should have bought 100 tokens");
    //     assertEq(
    //         glayzeManager.balanceOf(address(glayzeManager), 0),
    //         initialContractBalance - 100,
    //         "Contract balance should decrease by 100"
    //     );

    //     // USDC
    //     assertEq(USDC.balanceOf(address(glayzeManager)), buyPrice, "Contract should be paid");
    //     assertEq(
    //         USDC.balanceOf(owner), initialOwnerBalance + protocolFee - 1, "Owner should have received the protocol fee"
    //     );
    //     assertEq(
    //         USDC.balanceOf(bob), initialBobBalance + realCreatorFee, "Bob should have received the real creator fee"
    //     );
    //     assertEq(
    //         USDC.balanceOf(alice),
    //         initialAliceUsdcBalance - buyPriceAfterFees + contractCreatorFee + 1,
    //         "Alice should have received the contract creator fee"
    //     );
    //     assertEq(glayzeManager.totalValueDeposited(), buyPrice, "Total value deposited should be the buy price");
    //     vm.stopPrank();
    // }

    function testBuySharesRevertsWithERC20InsufficientBalance() public {
        USDC.mint(alice, glayzeManager.usdcCreationPayment());
        vm.startPrank(alice);

        // Approve GlayzeManager to spend Alice's USDC
        USDC.approve(address(glayzeManager), type(uint256).max);
        glayzeManager.createPost(0, "Test Post", "TST", "");
        uint256 buyPrice = glayzeManager.getBuyPrice(0, 100);
        uint256 totalFees = glayzeManager.getTotalFees(0, buyPrice);
        (, uint256 glayzeCreatorUsdcFee,) = glayzeManager.getFeeSplit(0, totalFees);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, glayzeCreatorUsdcFee)
        );

        // Buy shares
        glayzeManager.buyShares(0, 100, 0);
        vm.stopPrank();
    }

    function testBuySharesRevertsWithInvalidPostId() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(GlayzeManager.InvalidPostId.selector, 0));
        glayzeManager.buyShares(0, 1, 0);
        vm.stopPrank();
    }

    function testBuySharesRevertsWithTokenAmountZero() public {
        vm.startPrank(alice);
        USDC.mint(alice, STARTING_USER_BALANCE);
        USDC.approve(address(glayzeManager), glayzeManager.usdcCreationPayment());
        glayzeManager.createPost(0, "Test Post", "TST", "");
        vm.expectRevert(abi.encodeWithSelector(GlayzeManager.SharesZero.selector, 0));
        glayzeManager.buyShares(0, 0, 0);
        vm.stopPrank();
    }

    function testGetFeeSplit() public {
        USDC.mint(alice, glayzeManager.usdcCreationPayment());
        vm.startPrank(alice);
        USDC.approve(address(glayzeManager), glayzeManager.usdcCreationPayment());
        glayzeManager.createPost(0, "Test Post", "TST", "");
        uint256 price = glayzeManager.getBuyPrice(0, 1);
        uint256 priceAfterFees = glayzeManager.getBuyPriceAfterFees(0, 1, 0);
        (uint256 protocolFee, uint256 contractCreatorFee, uint256 realCreatorFee) = glayzeManager.getFeeSplit(0, price);
        assertEq(
            protocolFee,
            (price * glayzeManager.protocolFee()) / FixedPointMathLib.PRECISION,
            "Protocol fee should be correct"
        );
        assertEq(
            contractCreatorFee,
            (price * glayzeManager.glayzeCreatorFee()) / FixedPointMathLib.PRECISION,
            "Contract creator fee should be correct"
        );
        assertEq(
            realCreatorFee,
            (price * glayzeManager.realCreatorFee()) / FixedPointMathLib.PRECISION,
            "Real creator fee should be correct"
        );
        assertEq(
            priceAfterFees,
            price + protocolFee + contractCreatorFee + realCreatorFee,
            "Price after fees should be correct"
        );
        vm.stopPrank();
    }

    function testGetBuyPriceAfterFeesWithoutAura() public {
        USDC.mint(alice, glayzeManager.usdcCreationPayment());
        vm.startPrank(alice);
        USDC.approve(address(glayzeManager), glayzeManager.usdcCreationPayment());
        glayzeManager.createPost(1811899344876110166, "Test Post", "TST", "");
        uint256 buyPrice = glayzeManager.getBuyPrice(1811899344876110166, 1);
        uint256 buyPriceAfterFees = glayzeManager.getBuyPriceAfterFees(1811899344876110166, 1, 0);
        assertEq(
            buyPriceAfterFees,
            buyPrice + glayzeManager.getTotalFees(1811899344876110166, buyPrice),
            "Buy price after fees should be correct"
        );
    }

    function testGetBuyPriceAfterFeesWithAura() public {
        USDC.mint(alice, glayzeManager.usdcCreationPayment());
        vm.startPrank(alice);
        USDC.approve(address(glayzeManager), glayzeManager.usdcCreationPayment());
        glayzeManager.createPost(1811899344876110166, "Test Post", "TST", "");
        uint256 buyPrice = glayzeManager.getBuyPrice(1811899344876110166, 100234790);
        uint256 buyPriceAfterFees = glayzeManager.getBuyPriceAfterFees(1811899344876110166, 100234790, 20);
        console2.log("Buy price: ", buyPriceAfterFees);
        assertEq(
            buyPriceAfterFees,
            buyPrice + glayzeManager.getTotalFees(1811899344876110166, buyPrice) - 20,
            "Buy price after fees should be correct"
        );
    }

    function testGetTotalFees() public {
        USDC.mint(alice, glayzeManager.usdcCreationPayment());
        vm.startPrank(alice);
        USDC.approve(address(glayzeManager), glayzeManager.usdcCreationPayment());
        glayzeManager.createPost(0, "Test Post", "TST", "");
        uint256 buyPrice = glayzeManager.getBuyPrice(0, 1000);
        uint256 totalFees = glayzeManager.getTotalFees(0, buyPrice);
        uint256 buyPriceAfterFees = glayzeManager.getBuyPriceAfterFees(0, 1000, 0);
        assertEq(totalFees, buyPriceAfterFees - buyPrice, "Total fees should be correct");
    }

    function testBuyPriceShouldBeZero() public {
        USDC.mint(alice, glayzeManager.usdcCreationPayment());
        vm.startPrank(alice);
        USDC.approve(address(glayzeManager), glayzeManager.usdcCreationPayment());
        glayzeManager.createPost(0, "Test Post", "TST", "");
        vm.stopPrank();
        uint256 price = glayzeManager.getBuyPrice(0, 1);
        assertEq(price, 0, "Price should be 0");
    }

    function testAuraDoesNotChange() public {
        vm.startPrank(address(glayzeManager));
        glayzeManager.approve(address(glayzeManager), 0, type(uint256).max);
        vm.stopPrank();
        USDC.mint(alice, STARTING_USER_BALANCE);
        vm.startPrank(alice);
        USDC.approve(address(glayzeManager), type(uint256).max);
        glayzeManager.createPost(0, "Test Post", "TST", "");
        uint256 initialAliceAuraBalance = AURA.balanceOf(alice);
        uint256 initialOwnerAuraBalance = AURA.balanceOf(owner);
        uint256 initialBobAuraBalance = AURA.balanceOf(bob);

        uint256 buyAmount = 100;

        // Buy tokens
        glayzeManager.buyShares(0, buyAmount, 0);

        assertEq(AURA.balanceOf(alice), initialAliceAuraBalance, "Alice's AURA balance should not change");
        assertEq(AURA.balanceOf(owner), initialOwnerAuraBalance, "Owner's AURA balance should be zero");
        assertEq(AURA.balanceOf(bob), initialBobAuraBalance, "Real creator's AURA balance should be zero");
        vm.stopPrank();
    }

    function buySharesWithoutAura(address realCreator) internal {
        // Approve GlayzeManager to spend Alice's USDC
        USDC.approve(address(glayzeManager), type(uint256).max);
        glayzeManager.createPost(0, "Test Post", "TST", "");

        if (realCreator != address(0)) {
            vm.stopPrank();
            vm.startPrank(owner);
            glayzeManager.setRealCreator(0, realCreator);
            vm.stopPrank();
            vm.startPrank(alice);
        }
        // Get Initial Balances
        uint256 initialAliceUsdcBalance = USDC.balanceOf(alice);
        uint256 initialContractShareBalance = glayzeManager.balanceOf(address(glayzeManager), 0);
        uint256 initialAliceShareBalance = glayzeManager.balanceOf(alice, 0);
        uint256 initialOwnerUsdcBalance = USDC.balanceOf(owner);
        uint256 initialRealCreatorUsdcBalance = USDC.balanceOf(realCreator);

        uint256 buyAmount = 100;
        uint256 buyPriceAfterFees = glayzeManager.getBuyPriceAfterFees(0, buyAmount, 0);
        uint256 buyPrice = glayzeManager.getBuyPrice(0, buyAmount);
        uint256 totalFees = glayzeManager.getTotalFees(0, buyPrice);

        (uint256 protocolUsdcFee, uint256 glayzeCreatorUsdcFee, uint256 realCreatorUsdcFee) =
            glayzeManager.getFeeSplit(0, totalFees);
        assertEq(totalFees, protocolUsdcFee + glayzeCreatorUsdcFee + realCreatorUsdcFee, "fees not equal");
        assertEq(buyPriceAfterFees, buyPrice + totalFees, "Buy price fees are not the same");

        // Buy Shares
        glayzeManager.buyShares(0, buyAmount, 0);

        // Shares
        assertEq(
            glayzeManager.balanceOf(alice, 0),
            initialAliceShareBalance + buyAmount,
            "Alice should have bought 100 tokens"
        );
        assertEq(
            glayzeManager.balanceOf(address(glayzeManager), 0),
            initialContractShareBalance - buyAmount,
            "Contract balance should decrease by 100"
        );

        // USDC
        assertEq(USDC.balanceOf(address(glayzeManager)), buyPrice, "Contract should receive buyPrice in USDC");
        assertGt(glayzeCreatorUsdcFee, 0, "Glayze Creator fee should be greater than zero");
        if (realCreator != address(0)) {
            assertEq(
                USDC.balanceOf(realCreator),
                initialRealCreatorUsdcBalance + realCreatorUsdcFee,
                "The real creator should have received the real creator fee"
            );
            assertEq(
                USDC.balanceOf(owner),
                initialOwnerUsdcBalance + protocolUsdcFee,
                "Owner should have received the protocol fee"
            );
        } else {
            assertEq(
                USDC.balanceOf(owner),
                initialOwnerUsdcBalance + protocolUsdcFee + realCreatorUsdcFee,
                "Owner should have received the protocol fee and the real creator fee"
            );
        }
        assertEq(
            USDC.balanceOf(alice),
            initialAliceUsdcBalance - buyPriceAfterFees + glayzeCreatorUsdcFee,
            "Alice should have received the contract creator fee"
        );

        assertEq(glayzeManager.totalValueDeposited(), buyPrice, "Total value deposited should be the buy price");
    }

    function buySharesWithAura(uint256 aura, address realCreator) internal {
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

        uint256 initialAliceUsdcBalance = USDC.balanceOf(alice);
        uint256 initialOwnerUsdcBalance = USDC.balanceOf(owner);
        uint256 initialRealCreatorUsdcBalance = USDC.balanceOf(realCreator);

        uint256 buyAmount = 100;
        // uint256 buyPriceAfterFees = glayzeManager.getBuyPriceAfterFees(0, buyAmount);
        uint256 buyPrice = glayzeManager.getBuyPrice(0, buyAmount);
        uint256 totalFees = glayzeManager.getTotalFees(0, buyPrice);
        console2.log("totalFees", totalFees);

        // Buy tokens
        glayzeManager.buyShares(0, buyAmount, aura);

        // uint256 feesPaidInAura;
        uint256 feesPaidInUsdc;

        if (aura >= totalFees) {
            // feesPaidInAura = totalFees;
            feesPaidInUsdc = 0;
        } else {
            //feesPaidInAura = aura;
            feesPaidInUsdc = totalFees - aura;
        }
        // TODO: Check if feesPaidInAura is correct
        // console2.log("feesPaidInAura", feesPaidInAura);
        console2.log("feesPaidInUsdc", feesPaidInUsdc);

        (uint256 usdcProtocolFee, uint256 usdcGlayzeCreatorFee, uint256 usdcRealCreatorFee) =
            glayzeManager.getFeeSplit(0, feesPaidInUsdc);

        // USDC
        assertEq(USDC.balanceOf(address(glayzeManager)), buyPrice, "Contract should be paid");
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
            initialAliceUsdcBalance - buyPrice - feesPaidInUsdc + usdcGlayzeCreatorFee + 2, //TODO: Check if precision is correct
            "Alice USDC balance incorrect"
        );

        assertEq(glayzeManager.totalValueDeposited(), buyPrice, "Total value deposited should be the buy price");
        vm.stopPrank();
    }
}
