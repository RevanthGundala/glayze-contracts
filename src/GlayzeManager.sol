// SPDX-License-Identifier: MIT
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {ERC6909} from "@solmate/tokens/ERC6909.sol";
import {FixedPointMathLib} from "./lib/FixedPointMathLib.sol";
import {console2} from "forge-std/console2.sol";

pragma solidity ^0.8.19;

// V1 Has USDC and aura sent to EOA
// Tokens remain in contract
// Creators always get paid in usdc (cannot pay for aura for their share, so lower their fee share)

contract GlayzeManager is ERC6909, Owned, ReentrancyGuard {
    using FixedPointMathLib for uint256;

    ///////////////////
    // Errors
    ///////////////////
    error InsufficientShareBalance(uint256 postId, address user, uint256 balance);
    error InsufficientShareSupply(uint256 postId, uint256 supply);
    error InvalidPostId(uint256 postId);
    error RealCreatorAlreadyExists(uint256 postId, address creator);
    error UserAlreadyReferred(address user);
    error SharesZero(uint256 postId);
    error PostAlreadyExists(uint256 postId, string postURI);

    ///////////////////
    // Constants
    ///////////////////
    uint256 public constant DECIMALS = 1e4;
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e6; // 1 billion
    uint256 public constant SCALING_FACTOR = 1e6; // Adjusted for 6 decimals
    uint256 public constant USDC_CREATION_PAYMENT = 1e6; // 1 USDC
    uint256 public constant PROTOCOL_FEE = 250; // 2.5%
    uint256 public constant REAL_CREATOR_FEE = 50; // 0.05%
    uint256 public constant GLAYZE_CREATOR_FEE = 10; // 0.01%
    // TODO: calclate aura token value
    uint256 public constant AURA_REFERRAL_AMOUNT = 100000000000000000; // 100 aura

    ///////////////////
    // State variables
    ///////////////////
    IERC20 public immutable USDC;
    IERC20 public immutable AURA;
    address public immutable protocolFeeDestination;
    uint256 public totalValueDeposited;
    uint256 public postIdCounter;
    mapping(uint256 id => Post post) public posts;
    mapping(string uri => uint256 postId) public postURIs;
    mapping(uint256 id => ShareInfo shareInfo) public shareInfo;
    mapping(uint256 id => uint256 remainingEarnings) public glayzeCreatorRemainingEarnings;
    mapping(address user => bool isReferred) public usersReferred;

    ///////////////////
    // Structs
    ///////////////////
    struct Post {
        string name;
        string symbol;
        string postURI;
        address glayzeCreator;
        address realCreator;
    }

    struct ShareInfo {
        uint256 price;
        uint256 supply;
    }

    ///////////////////
    // Events
    ///////////////////
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

    ///////////////////
    // Modifiers
    ///////////////////
    modifier validPost(uint256 postId) {
        if (postId >= postIdCounter) revert InvalidPostId(postId);
        _;
    }

    modifier sharesNotZero(uint256 postId, uint256 shares) {
        if (shares == 0) revert SharesZero(postId);
        _;
    }

    constructor(address _usdc, address _aura) Owned(msg.sender) {
        USDC = IERC20(_usdc);
        AURA = IERC20(_aura);
        protocolFeeDestination = msg.sender;
        totalValueDeposited = 0;
        postIdCounter = 0;
    }

    function createPost(string memory name, string memory symbol, string memory postURI) external {
        // Check if the postURI is unique
        if (postURIs[postURI] != 0) revert PostAlreadyExists(postURIs[postURI], postURI);

        // Set postIdCounter to local variable for reads
        uint256 postId = postIdCounter;

        // Create post and initialize TokenInfo
        posts[postId] =
            Post({name: name, symbol: symbol, postURI: postURI, glayzeCreator: msg.sender, realCreator: address(0)});
        shareInfo[postId] = ShareInfo({price: 0, supply: 0});
        postURIs[postURI] = postId;

        // Set remaining earnings for Glayze Creator
        glayzeCreatorRemainingEarnings[postId] = USDC_CREATION_PAYMENT;

        // Increment postIdCounter
        postIdCounter++;

        // Emit event
        emit PostCreated(postId, msg.sender, name, symbol, postURI, block.timestamp);

        // Mint MAX_SUPPLY posts to the contract
        _mint(address(this), postId, MAX_SUPPLY);

        // Transfer USDC_CREATION_PAYMENT to Protocol
        require(USDC.transferFrom(msg.sender, protocolFeeDestination, USDC_CREATION_PAYMENT), "InsufficientUsdcBalance");
    }

    function buyShares(uint256 postId, uint256 shares, uint256 aura)
        external
        nonReentrant
        validPost(postId)
        sharesNotZero(postId, shares)
    {
        (uint256 buyPrice, uint256 newSupply, uint256 newPrice) = _updateBuyState(postId, shares);

        // Emit event
        emit Trade(postId, msg.sender, true, aura, buyPrice, shares, newSupply, newPrice, block.timestamp);

        // Distribute the fee to the creators
        _handleBuy(postId, shares, buyPrice, aura);
    }

    function sellShares(uint256 postId, uint256 shares, uint256 aura)
        external
        nonReentrant
        validPost(postId)
        sharesNotZero(postId, shares)
    {
        (uint256 sellPrice, uint256 newSupply, uint256 newPrice) = _updateSellState(postId, shares);

        // Emit event
        emit Trade(postId, msg.sender, false, aura, sellPrice, shares, newSupply, newPrice, block.timestamp);

        _handleSell(postId, shares, sellPrice, aura);
    }

    function setRealCreator(uint256 postId, address realCreator) external onlyOwner validPost(postId) {
        if (posts[postId].realCreator != address(0)) revert RealCreatorAlreadyExists(postId, realCreator);
        posts[postId].realCreator = realCreator;
        emit RealCreatorSet(postId, realCreator, block.timestamp);
    }

    function refer(address user, address referrer) external onlyOwner {
        if (usersReferred[user]) revert UserAlreadyReferred(user);
        usersReferred[user] = true;
        emit Referral(user, referrer, block.timestamp);
        require(
            AURA.transferFrom(protocolFeeDestination, user, AURA_REFERRAL_AMOUNT)
                && AURA.transferFrom(protocolFeeDestination, referrer, AURA_REFERRAL_AMOUNT),
            "TransferFailed"
        );
    }

    function getBuyPriceAfterFees(uint256 postId, uint256 shares) public view validPost(postId) returns (uint256) {
        uint256 price = getBuyPrice(postId, shares);
        return price + getTotalFees(postId, price);
    }

    function getSellPriceAfterFees(uint256 postId, uint256 shares) public view validPost(postId) returns (uint256) {
        uint256 price = getSellPrice(postId, shares);
        return price - getTotalFees(postId, price);
    }

    function getBuyPrice(uint256 postId, uint256 shares) public view validPost(postId) returns (uint256) {
        return getPrice(shareInfo[postId].supply, shares);
    }

    function getSellPrice(uint256 postId, uint256 shares) public view validPost(postId) returns (uint256) {
        return getPrice(shareInfo[postId].supply - shares, shares);
    }

    function getPrice(uint256 supply, uint256 amount) public pure returns (uint256 price) {
        // Calculate sum of squares to get the price
        uint256 sum1 = supply == 0 ? 0 : ((supply - 1) * (supply) * (2 * (supply - 1) + 1)) / 6;
        uint256 sum2 = ((supply + amount - 1) * (supply + amount) * (2 * (supply + amount - 1) + 1)) / 6;
        uint256 summation = sum2 > sum1 ? sum2 - sum1 : 0;

        // Adjust for scaling factor
        price = FixedPointMathLib.mulWadDown(summation, SCALING_FACTOR);
    }

    // TODO: Remove variables and just return sum
    function getTotalFees(uint256 postId, uint256 price) public view validPost(postId) returns (uint256) {
        uint256 protocolFee = FixedPointMathLib.mulWadDown(price, PROTOCOL_FEE);
        uint256 glayzeCreatorFee =
            glayzeCreatorRemainingEarnings[postId] > 0 ? FixedPointMathLib.mulWadDown(price, GLAYZE_CREATOR_FEE) : 0;
        uint256 realCreatorFee = FixedPointMathLib.mulWadDown(price, REAL_CREATOR_FEE);
        return protocolFee + glayzeCreatorFee + realCreatorFee;
    }

    // TODO: Remove variables and just return
    function getFeeSplit(uint256 postId, uint256 totalFees)
        public
        view
        validPost(postId)
        returns (uint256, uint256, uint256)
    {
        uint256 totalFeePercentage = PROTOCOL_FEE + GLAYZE_CREATOR_FEE + REAL_CREATOR_FEE;
        uint256 protocolFeeDecimal = (totalFees * PROTOCOL_FEE) / totalFeePercentage;

        uint256 glayzeCreatorFeeDecimal =
            glayzeCreatorRemainingEarnings[postId] > 0 ? (totalFees * GLAYZE_CREATOR_FEE) / totalFeePercentage : 0;

        uint256 realCreatorFeeDecimal = (totalFees * REAL_CREATOR_FEE) / totalFeePercentage;

        return (protocolFeeDecimal, glayzeCreatorFeeDecimal, realCreatorFeeDecimal);
    }

    function _updateBuyState(uint256 postId, uint256 shares)
        internal
        returns (uint256 price, uint256 newSupply, uint256 newPrice)
    {
        // Store supply in local variable for reads
        uint256 supply = shareInfo[postId].supply;

        // Get the price of the post
        price = getBuyPrice(postId, shares);

        // Calculate new supply and price
        newSupply = supply + shares;
        newPrice = shareInfo[postId].price + price;

        // Update tokenInfo and totalValueDeposited
        shareInfo[postId].supply = newSupply;
        shareInfo[postId].price = newPrice;
        totalValueDeposited += price;
        return (price, newSupply, newPrice);
    }

    function _updateSellState(uint256 postId, uint256 shares)
        internal
        returns (uint256 sellPrice, uint256 newSupply, uint256 newPrice)
    {
        // Check if the supply is enough to sell
        uint256 supply = shareInfo[postId].supply;

        // Ensure atleast the amount of tokens to sell is available
        if (supply < shares) revert InsufficientShareSupply(postId, supply);

        // Get the price of the post
        sellPrice = getSellPrice(postId, shares);

        // Check if the user has enough tokens to sell
        if (balanceOf[msg.sender][postId] < shares) {
            revert InsufficientShareBalance(postId, msg.sender, balanceOf[msg.sender][postId]);
        }

        // Update tokenInfo and totalValueDeposited
        newSupply = supply - shares;
        newPrice = shareInfo[postId].price - sellPrice;

        shareInfo[postId].supply = newSupply;
        shareInfo[postId].price = newPrice;
        totalValueDeposited -= sellPrice;

        return (sellPrice, newSupply, newPrice);
    }

    function _handleBuy(uint256 postId, uint256 shares, uint256 buyPrice, uint256 aura) internal {
        _distributeFees(postId, buyPrice, aura, true);

        // Transfer price to contract
        require(USDC.transferFrom(msg.sender, address(this), buyPrice), "USDCTransferFailed");

        // Transfer tokens to user
        // require(transferFrom(address(this), msg.sender, postId, shares), "BuyFailed");
        _transfer(address(this), msg.sender, postId, shares);
    }

    function _handleSell(uint256 postId, uint256 shares, uint256 sellPrice, uint256 aura) internal {
        _distributeFees(postId, sellPrice, aura, false);

        // Transfer price to sender
        require(USDC.transfer(msg.sender, sellPrice), "USDCTransferFailed");

        // Transfer tokens to contract
        require(transferFrom(msg.sender, address(this), postId, shares), "SellFailed");
    }

    function _distributeFees(uint256 postId, uint256 price, uint256 aura, bool isBuy) internal {
        uint256 fees = getTotalFees(postId, price);
        address realCreator = posts[postId].realCreator;
        uint256 feesPaidInAura;
        uint256 feesPaidInUsdc;
        if (aura >= fees) {
            feesPaidInAura = fees;
            feesPaidInUsdc = 0;
        } else {
            feesPaidInAura = aura;
            feesPaidInUsdc = fees - aura;
        }

        emit TradeFees(postId, msg.sender, isBuy, feesPaidInAura, feesPaidInUsdc, block.timestamp);
        // Pay fees with aura
        if (feesPaidInAura > 0) {
            (uint256 protocolFee, uint256 glayzeCreatorFee, uint256 realCreatorFee) =
                getFeeSplit(postId, feesPaidInAura);
            if (glayzeCreatorFee > 0) {
                require(
                    AURA.transferFrom(msg.sender, posts[postId].glayzeCreator, glayzeCreatorFee),
                    "AuraGlayzeCreatorTransferFailed"
                );
            }
            if (realCreator == address(0)) {
                require(
                    AURA.transferFrom(msg.sender, protocolFeeDestination, realCreatorFee + protocolFee),
                    "AuraRealCreatorFeeTransferFailed"
                );
            } else {
                require(AURA.transferFrom(msg.sender, realCreator, realCreatorFee), "AuraRealCreatorFeeTransferFailed");
                require(
                    AURA.transferFrom(msg.sender, protocolFeeDestination, protocolFee), "AuraProtocolFeeTransferFailed"
                );
            }
        }

        // Make user pay remaining amount in USDC
        if (feesPaidInUsdc > 0) {
            (uint256 protocolFee, uint256 glayzeCreatorFee, uint256 realCreatorFee) =
                getFeeSplit(postId, feesPaidInUsdc);
            if (glayzeCreatorFee > 0) {
                require(
                    USDC.transferFrom(msg.sender, posts[postId].glayzeCreator, glayzeCreatorFee),
                    "USDCGlayzeCreatorTransferFailed"
                );
            }
            if (realCreator == address(0)) {
                require(
                    USDC.transferFrom(msg.sender, protocolFeeDestination, realCreatorFee + protocolFee),
                    "USDCRealCreatorTransferFailed"
                );
            } else {
                require(USDC.transferFrom(msg.sender, realCreator, realCreatorFee), "USDCRealCreatorTransferFailed");
                require(
                    USDC.transferFrom(msg.sender, protocolFeeDestination, protocolFee), "USDCProtocolFeeTransferFailed"
                );
            }
        }
    }

    function _transfer(address from, address to, uint256 postId, uint256 amount) internal {
        balanceOf[from][postId] -= amount;
        balanceOf[to][postId] += amount;
    }
}
