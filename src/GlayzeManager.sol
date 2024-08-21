// SPDX-License-Identifier: MIT
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {ERC6909} from "@solmate/tokens/ERC6909.sol";
import {FixedPointMathLib} from "./lib/FixedPointMathLib.sol";
import {console2} from "forge-std/console2.sol";

pragma solidity ^0.8.19;

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
    error PostAlreadyExists(uint256 postId);

    ///////////////////
    // Constants
    ///////////////////
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e6; // 1 billion
    uint256 public constant SCALING_FACTOR = 1e6; // Adjusted for 6 decimals

    ///////////////////
    // State variables
    ///////////////////
    IERC20 public immutable USDC;
    IERC20 public immutable AURA;
    address public immutable protocolFeeDestination;
    uint256 public usdcCreationPayment;
    uint256 public protocolFee;
    uint256 public realCreatorFee;
    uint256 public glayzeCreatorFee;
    uint256 public auraReferralAmount;
    mapping(uint256 id => Post post) public posts;
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
        if (posts[postId].glayzeCreator == address(0)) {
            revert InvalidPostId(postId);
        }
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
        usdcCreationPayment = 1e6; // 1 USDC
        protocolFee = 250; // 2.5%
        realCreatorFee = 50; // 0.05%
        glayzeCreatorFee = 10; // 0.01%
        auraReferralAmount = 1e6; // 1 aura
    }

    function createPost(uint256 postId, string memory name, string memory symbol, string memory postURI) external {
        // Check if the postId is unique
        if (posts[postId].glayzeCreator != address(0)) {
            revert PostAlreadyExists(postId);
        }

        // Create post and initialize TokenInfo
        posts[postId] =
            Post({name: name, symbol: symbol, postURI: postURI, glayzeCreator: msg.sender, realCreator: address(0)});
        shareInfo[postId] = ShareInfo({price: 0, supply: 0});

        // Set remaining earnings for Glayze Creator
        glayzeCreatorRemainingEarnings[postId] = usdcCreationPayment;

        // Emit event
        emit PostCreated(postId, msg.sender, name, symbol, postURI, block.timestamp);

        // Mint MAX_SUPPLY shares to the contract
        _mint(address(this), postId, MAX_SUPPLY);

        // Transfer usdcCreationPayment to Protocol
        require(USDC.transferFrom(msg.sender, protocolFeeDestination, usdcCreationPayment), "InsufficientUsdcBalance");
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

    function setUsdcCreationPayment(uint256 _usdcCreationPayment) external onlyOwner {
        usdcCreationPayment = _usdcCreationPayment;
    }

    function setAuraReferralAmount(uint256 _auraReferralAmount) external onlyOwner {
        auraReferralAmount = _auraReferralAmount;
    }

    function setProtocolFee(uint256 _protocolFee) external onlyOwner {
        protocolFee = _protocolFee;
    }

    function setGlazyCreatorFee(uint256 _glazyCreatorFee) external onlyOwner {
        glayzeCreatorFee = _glazyCreatorFee;
    }

    function setRealCreatorFee(uint256 _realCreatorFee) external onlyOwner {
        realCreatorFee = _realCreatorFee;
    }

    function setRealCreator(uint256 postId, address realCreator) external onlyOwner validPost(postId) {
        if (posts[postId].realCreator != address(0)) {
            revert RealCreatorAlreadyExists(postId, realCreator);
        }
        posts[postId].realCreator = realCreator;
        emit RealCreatorSet(postId, realCreator, block.timestamp);
    }

    function refer(address user, address referrer) external onlyOwner {
        if (usersReferred[user]) revert UserAlreadyReferred(user);
        usersReferred[user] = true;
        emit Referral(user, referrer, block.timestamp);
        require(
            AURA.transferFrom(protocolFeeDestination, user, auraReferralAmount)
                && AURA.transferFrom(protocolFeeDestination, referrer, auraReferralAmount),
            "TransferFailed"
        );
    }

    function getBuyPriceAfterFees(uint256 postId, uint256 shares, uint256 aura)
        external
        view
        validPost(postId)
        returns (uint256)
    {
        uint256 price = getBuyPrice(postId, shares);
        uint256 priceAfterFees = price + getTotalFees(postId, price);
        return priceAfterFees > aura ? priceAfterFees - aura : 0;
    }

    function getSellPriceAfterFees(uint256 postId, uint256 shares, uint256 aura)
        external
        view
        validPost(postId)
        returns (uint256)
    {
        uint256 price = getSellPrice(postId, shares);
        uint256 priceAfterFees = price - getTotalFees(postId, price);
        return priceAfterFees > aura ? priceAfterFees - aura : 0;
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
        price = FixedPointMathLib.mulDivDown(summation, SCALING_FACTOR);
    }

    function getTotalFees(uint256 postId, uint256 price) public view validPost(postId) returns (uint256) {
        uint256 glayzeCreatorFeeSplit =
            glayzeCreatorRemainingEarnings[postId] > 0 ? FixedPointMathLib.mulDivDown(price, glayzeCreatorFee) : 0;
        return FixedPointMathLib.mulDivDown(price, protocolFee) + glayzeCreatorFeeSplit
            + FixedPointMathLib.mulDivDown(price, realCreatorFee);
    }

    function getFeeSplit(uint256 postId, uint256 totalFees)
        public
        view
        validPost(postId)
        returns (uint256, uint256, uint256)
    {
        uint256 totalFeePercentage = protocolFee + glayzeCreatorFee + realCreatorFee;
        uint256 glayzeCreatorFeeDecimal =
            glayzeCreatorRemainingEarnings[postId] > 0 ? (totalFees * glayzeCreatorFee) / totalFeePercentage : 0;

        return (
            (totalFees * protocolFee) / totalFeePercentage,
            glayzeCreatorFeeDecimal,
            (totalFees * realCreatorFee) / totalFeePercentage
        );
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

        // Update tokenInfo
        shareInfo[postId].supply = newSupply;
        shareInfo[postId].price = newPrice;
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

        // Update tokenInfo
        newSupply = supply - shares;
        newPrice = shareInfo[postId].price - sellPrice;

        shareInfo[postId].supply = newSupply;
        shareInfo[postId].price = newPrice;

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
            (uint256 protocolFeeSplit, uint256 glayzeCreatorFeeSplit, uint256 realCreatorFeeSplit) =
                getFeeSplit(postId, feesPaidInAura);
            if (glayzeCreatorFeeSplit > 0) {
                require(
                    AURA.transferFrom(msg.sender, posts[postId].glayzeCreator, glayzeCreatorFeeSplit),
                    "AuraGlayzeCreatorTransferFailed"
                );
            }
            if (realCreator == address(0)) {
                require(
                    AURA.transferFrom(msg.sender, protocolFeeDestination, realCreatorFeeSplit + protocolFeeSplit),
                    "AuraRealCreatorFeeTransferFailed"
                );
            } else {
                require(
                    AURA.transferFrom(msg.sender, realCreator, realCreatorFeeSplit), "AuraRealCreatorFeeTransferFailed"
                );
                require(
                    AURA.transferFrom(msg.sender, protocolFeeDestination, protocolFeeSplit),
                    "AuraProtocolFeeTransferFailed"
                );
            }
        }

        // Make user pay remaining amount in USDC
        if (feesPaidInUsdc > 0) {
            (uint256 protocolFeeSplit, uint256 glayzeCreatorFeeSplit, uint256 realCreatorFeeSplit) =
                getFeeSplit(postId, feesPaidInUsdc);
            if (glayzeCreatorFeeSplit > 0) {
                require(
                    USDC.transferFrom(msg.sender, posts[postId].glayzeCreator, glayzeCreatorFeeSplit),
                    "USDCGlayzeCreatorTransferFailed"
                );
            }
            if (realCreator == address(0)) {
                require(
                    USDC.transferFrom(msg.sender, protocolFeeDestination, realCreatorFeeSplit + protocolFeeSplit),
                    "USDCRealCreatorTransferFailed"
                );
            } else {
                require(
                    USDC.transferFrom(msg.sender, realCreator, realCreatorFeeSplit), "USDCRealCreatorTransferFailed"
                );
                require(
                    USDC.transferFrom(msg.sender, protocolFeeDestination, protocolFeeSplit),
                    "USDCProtocolFeeTransferFailed"
                );
            }
        }
    }

    function _transfer(address from, address to, uint256 postId, uint256 amount) internal {
        balanceOf[from][postId] -= amount;
        balanceOf[to][postId] += amount;
    }
}
