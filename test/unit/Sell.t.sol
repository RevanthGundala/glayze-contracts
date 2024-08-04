// // SPDX-License-Identifier: MIT

// pragma solidity ^0.8.19;

// import {Test, console} from "forge-std/Test.sol";
// import "forge-std/Console2.sol";
// import {GlayzeManager} from "../../src/GlayzeManager.sol";
// import {ERC20Mock} from "../mocks/ERC20Mock.sol";
// import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {DeployGlayzeManager} from "../../script/DeployGlayzeManager.s.sol";

// contract Sell is Test {
//     GlayzeManager public glayzeManager;
//     HelperConfig public helperConfig;
//     address public owner;
//     address public alice = address(1);
//     address public bob = address(2);
//     ERC20Mock public USDC;
//     ERC20Mock public AURA;
//     uint256 public constant STARTING_USER_BALANCE = 10000000000e6;

//     event PostCreated(uint256 postId, address creator, string name, string symbol, string postURI, uint256 timestamp);
//     event Trade(
//         uint256 postId,
//         address trader,
//         bool isBuy,
//         uint256 aura,
//         uint256 usdc,
//         uint256 shares,
//         uint256 newSupply,
//         uint256 newPrice,
//         uint256 timestamp
//     );

//     event TradeFees(uint256 postId, address trader, bool isBuy, uint256 aura, uint256 usdc, uint256 timestamp);
//     event RealCreatorSet(uint256 postId, address realCreator, uint256 timestamp);
//     event Referral(address userReferred, address referredBy, uint256 timestamp);

//     function setUp() public {
//         DeployGlayzeManager deployer = new DeployGlayzeManager();
//         (glayzeManager, helperConfig) = deployer.run();
//         owner = glayzeManager.owner();
//         (address usdc, address aura,) = helperConfig.activeNetworkConfig();
//         USDC = ERC20Mock(usdc);
//         AURA = ERC20Mock(aura);
//         AURA.mint(owner, glayzeManager.MAX_SUPPLY());
//     }

//     function testSellSharesWithoutGlayze() public {
//         USDC.mint(alice, STARTING_USER_BALANCE);
//         vm.startPrank(alice);

//         // Approve GlayzeManager to spend Alice's USDC
//         USDC.approve(address(glayzeManager), type(uint256).max);

//         glayzeManager.createPost("Test Post", "TST", "");

//         // Buy tokens
//         glayzeManager.buyShares(0, 100, 0);
//         uint256 sellAmount = 100;
//         uint256 initialAliceUsdcBalance = USDC.balanceOf(alice);
//         uint256 initialContractBalance = glayzeManager.balanceOf(address(glayzeManager), 0);
//         uint256 initialAliceBalance = glayzeManager.balanceOf(alice, 0);
//         uint256 initialOwnerBalance = USDC.balanceOf(owner);
//         uint256 sellPrice = glayzeManager.getSellPrice(0, sellAmount);
//         uint256 sellPriceAfterFees = glayzeManager.getSellPriceAfterFees(0, sellAmount);
//         (uint256 protocolFee, uint256 contractCreatorFee, uint256 realCreatorFee) =
//             glayzeManager.getFeeSplit(0, sellPrice);

//         vm.expectEmit(true, true, true, true);
//         emit Trade(0, alice, false, 0, sellPrice, sellAmount, 0, 0, block.timestamp);

//         // vm.expectEmit(true, true, true, true);
//         // emit TradeFees(0, protocolFee, contractCreatorFee, realCreatorFee, block.timestamp);

//         glayzeManager.sellShares(0, sellAmount, 0);

//         // Tokens
//         assertEq(
//             glayzeManager.balanceOf(alice, 0), initialAliceBalance - sellAmount, "Alice should have sold 100 tokens"
//         );
//         assertEq(
//             glayzeManager.balanceOf(address(glayzeManager), 0),
//             initialContractBalance + sellAmount,
//             "Contract balance should increase by 100"
//         );

//         // USDC
//         assertEq(
//             USDC.balanceOf(alice),
//             initialAliceUsdcBalance + sellPriceAfterFees + contractCreatorFee,
//             "Alice should have received the buy amount"
//         );
//         assertEq(
//             USDC.balanceOf(owner),
//             initialOwnerBalance + protocolFee + realCreatorFee,
//             "Owner should have received the protocol fee"
//         );

//         assertEq(
//             glayzeManager.totalValueDeposited(),
//             glayzeManager.getBuyPrice(0, 100) - sellPrice,
//             "Total value deposited should be buy - sell price"
//         );
//         vm.stopPrank();
//     }

//     // function testsellSharesWithAuraWithRealCreator() public {}

//     function testsellSharesWithAuraWithoutRealCreator() public {
//         USDC.mint(alice, STARTING_USER_BALANCE);
//         AURA.mint(alice, 100);
//         vm.startPrank(alice);

//         // Approve GlayzeManager to spend Alice's USDC
//         USDC.approve(address(glayzeManager), type(uint256).max);
//         AURA.approve(address(glayzeManager), 100);

//         glayzeManager.createPost("Test Post", "TST", "");

//         // Buy tokens
//         glayzeManager.buyShares(0, 100, 0);
//         uint256 sellAmount = 100;
//         uint256 initialAliceUsdcBalance = USDC.balanceOf(alice);
//         uint256 initialContractBalance = glayzeManager.balanceOf(address(glayzeManager), 0);
//         uint256 initialAliceBalance = glayzeManager.balanceOf(alice, 0);
//         uint256 initialOwnerBalance = USDC.balanceOf(owner);
//         uint256 sellPrice = glayzeManager.getSellPrice(0, sellAmount);
//         uint256 sellPriceAfterFees = glayzeManager.getSellPriceAfterFees(0, sellAmount);
//         (uint256 protocolFee, uint256 contractCreatorFee, uint256 realCreatorFee) =
//             glayzeManager.getFeeSplit(0, sellPrice);

//         glayzeManager.sellShares(0, sellAmount, 100);

//         // Tokens
//         assertEq(
//             glayzeManager.balanceOf(alice, 0), initialAliceBalance - sellAmount, "Alice should have sold 100 tokens"
//         );
//         assertEq(
//             glayzeManager.balanceOf(address(glayzeManager), 0),
//             initialContractBalance + sellAmount,
//             "Contract balance should increase by 100"
//         );

//         // USDC
//         assertEq(
//             USDC.balanceOf(alice),
//             initialAliceUsdcBalance + sellPriceAfterFees + contractCreatorFee + protocolFee,
//             "Alice should have received the buy amount"
//         );
//         assertEq(
//             USDC.balanceOf(owner), initialOwnerBalance + realCreatorFee, "Owner should have received the protocol fee"
//         );

//         assertEq(
//             glayzeManager.totalValueDeposited(),
//             glayzeManager.getBuyPrice(0, 100) - sellPrice,
//             "Total value deposited should be buy - sell price"
//         );
//         vm.stopPrank();
//     }

//     function testsellSharesRevertsWithInsufficientTokenSupply() public {
//         vm.startPrank(address(glayzeManager));
//         glayzeManager.approve(address(glayzeManager), 0, type(uint256).max);
//         vm.stopPrank();

//         USDC.mint(alice, STARTING_USER_BALANCE);
//         vm.startPrank(alice);

//         // Approve GlayzeManager to spend Alice's USDC
//         USDC.approve(address(glayzeManager), type(uint256).max);
//         glayzeManager.createPost("Test Post", "TST", "");

//         uint256 buyAmount = 100;
//         // Buy tokens
//         glayzeManager.buyShares(0, buyAmount, 0);
//         vm.expectRevert(abi.encodeWithSelector(GlayzeManager.InsufficientShareSupply.selector, 0, buyAmount));
//         glayzeManager.sellShares(0, buyAmount + 1, 0);

//         // Tokens
//         vm.stopPrank();
//     }

//     function testsellSharesRevertsWithInsufficientTokenBalance() public {
//         USDC.mint(alice, STARTING_USER_BALANCE);
//         USDC.mint(owner, STARTING_USER_BALANCE);
//         vm.startPrank(alice);
//         USDC.approve(address(glayzeManager), type(uint256).max);
//         glayzeManager.createPost("Test Post", "TST", "");
//         uint256 buyAmount = 100;
//         glayzeManager.buyShares(0, buyAmount, 0);
//         vm.stopPrank();

//         vm.startPrank(owner);
//         USDC.approve(address(glayzeManager), type(uint256).max);
//         glayzeManager.buyShares(0, buyAmount, 0);
//         vm.stopPrank();

//         vm.startPrank(alice);
//         vm.expectRevert(abi.encodeWithSelector(GlayzeManager.InsufficientShareBalance.selector, 0, alice, buyAmount));
//         glayzeManager.sellShares(0, buyAmount + 1, 0);
//         vm.stopPrank();
//     }

//     function testsellSharesRevertsWithInvalidPostId() public {
//         vm.startPrank(alice);
//         vm.expectRevert(abi.encodeWithSelector(GlayzeManager.InvalidPostId.selector, 0));
//         glayzeManager.sellShares(0, 1, 0);
//         vm.stopPrank();
//     }

//     function testsellSharesRevertsWithTokenAmountZero() public {
//         vm.startPrank(alice);
//         USDC.mint(alice, STARTING_USER_BALANCE);
//         USDC.approve(address(glayzeManager), glayzeManager.USDC_CREATION_PAYMENT());

//         // Call the function that should emit the event
//         glayzeManager.createPost("Test Post", "TST", "");

//         vm.expectRevert(abi.encodeWithSelector(GlayzeManager.SharesZero.selector, 0));
//         glayzeManager.sellShares(0, 0, 0);
//         vm.stopPrank();
//     }
// }
