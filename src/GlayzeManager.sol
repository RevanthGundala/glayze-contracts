// SPDX-License-Identifier: MIT
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {ERC6909} from "@solmate/tokens/ERC6909.sol";

pragma solidity ^0.8.19;

// V1 Has USDC and GLAYZE sent to EOA
// Tokens remain in contract

contract GlayzeManager is ERC6909, Owned, ReentrancyGuard {
    ///////////////////
    // Errors
    ///////////////////
    error InsufficientTokenBalance(uint256 postId, address user, uint256 balance);
    error InsufficientTokenSupply(uint256 postId, uint256 supply);
    error InvalidPostId(uint256 postId);
    error RealCreatorAlreadyExists(uint256 postId, address creator);
    error UserAlreadyReferred(address user);

    ///////////////////
    // Constants
    ///////////////////
    uint256 public constant DECIMALS = 1e6;
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e6; // 1 billion
    uint256 public constant PROTOCOL_FEE = 10000; // 1%
    uint256 public constant SCALING_FACTOR = 3000; // Adjusted for 6 decimals
    uint256 public constant USDC_CREATION_PAYMENT = 1000000; // 1 USDC
    uint256 public constant CONTRACT_CREATOR_FEE_SHARE = 1; // 0.01% of the 1% protocol fee
    uint256 public constant REAL_CREATOR_FEE_SHARE = 500; // 50% of the 1% protocol fee
    uint256 public constant GLAYZE_REFERRAL_AMOUNT = 100000000000000000; // 100 GLAYZE

    // TODO: Creators always get paid in usdc (cannot pay for glayze for their share, so lower their fee share)

    ///////////////////
    // State variables
    ///////////////////
    IERC20 public immutable USDC;
    IERC20 public immutable GLAYZE;
    address public immutable protocolFeeDestination;
    uint256 public totalValueDeposited;
    uint256 public postIdCounter;
    mapping(uint256 id => Post post) public posts;
    mapping(uint256 id => TokenInfo tokenInfo) public tokenInfo;
    mapping(uint256 id => uint256 remainingEarnings) public contractCreatorRemainingEarnings;
    mapping(address user => bool isReferred) public usersReferred;

    ///////////////////
    // Structs
    ///////////////////
    struct Post {
        string name;
        string symbol;
        string postURI;
        address contractCreator;
        address realCreator;
    }

    struct TokenInfo {
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

    ///////////////////
    // Modifiers
    ///////////////////
    modifier validPost(uint256 postId) {
        if (postId >= postIdCounter) revert InvalidPostId(postId);
        _;
    }

    modifier notReferred(address user) {
        if (usersReferred[user]) revert UserAlreadyReferred(user);
        _;
    }

    constructor(address _usdc, address _glayze) Owned(msg.sender) {
        USDC = IERC20(_usdc);
        GLAYZE = IERC20(_glayze);
        protocolFeeDestination = msg.sender;
        totalValueDeposited = 0;
        postIdCounter = 0;
    }

    function createPost(string memory name, string memory symbol, string memory postURI) external {
        // Set postIdCounter to local variable for reads
        uint256 postId = postIdCounter;

        // Create post and initialize TokenInfo
        posts[postId] =
            Post({name: name, symbol: symbol, postURI: postURI, contractCreator: msg.sender, realCreator: address(0)});
        tokenInfo[postId] = TokenInfo({price: 0, supply: 0});
        contractCreatorRemainingEarnings[postId] = USDC_CREATION_PAYMENT;

        // Emit event
        emit PostCreated(postId, msg.sender, name, symbol, postURI, block.timestamp);

        // Increment postIdCounter
        postIdCounter++;

        // Mint MAX_SUPPLY posts to the contract
        _mint(address(this), postId, MAX_SUPPLY);

        // Transfer USDC_CREATION_PAYMENT to Protocol
        require(USDC.transferFrom(msg.sender, protocolFeeDestination, USDC_CREATION_PAYMENT), "InsufficientUsdcBalance");
    }

    function buyTokens(uint256 postId, uint256 tokenAmount, uint256 glayzeAmount)
        external
        nonReentrant
        validPost(postId)
    {
        (uint256 fee, uint256 newSupply, uint256 newPrice) = _updateBuyState(postId, tokenAmount);

        // Emit event
        emit Trade(postId, msg.sender, true, glayzeAmount, fee, tokenAmount, newSupply, newPrice, block.timestamp);

        // Distribute the fee to the creators
        _handleBuy(postId, tokenAmount, fee, glayzeAmount);
    }

    function sellTokens(uint256 postId, uint256 tokenAmount, uint256 glayzeAmount)
        external
        nonReentrant
        validPost(postId)
    {
        (uint256 fee, uint256 newSupply, uint256 newPrice) = _updateSellState(postId, tokenAmount);

        // Emit event
        emit Trade(postId, msg.sender, false, glayzeAmount, tokenAmount, fee, newSupply, newPrice, block.timestamp);

        _handleSell(postId, tokenAmount, fee, newPrice, glayzeAmount);
    }

    function setRealCreator(uint256 postId, address realCreator) external onlyOwner validPost(postId) {
        if (posts[postId].realCreator != address(0)) revert RealCreatorAlreadyExists(postId, realCreator);
        posts[postId].realCreator = realCreator;
        emit RealCreatorSet(postId, realCreator, block.timestamp);
    }

    // TODO: calclate glayze token value
    function refer(address user, address referrer) external onlyOwner notReferred(user) {
        usersReferred[user] = true;
        emit Refer(user, referrer, block.timestamp);
        bool success = GLAYZE.transferFrom(protocolFeeDestination, user, GLAYZE_REFERRAL_AMOUNT);
        bool success2 = GLAYZE.transferFrom(protocolFeeDestination, referrer, GLAYZE_REFERRAL_AMOUNT);
        require(success && success2, "TransferFailed");
    }

    function getBuyPriceAfterFees(uint256 postId, uint256 tokenAmount) external view returns (uint256) {
        uint256 price = getBuyPrice(postId, tokenAmount);
        uint256 protocolFee = price * PROTOCOL_FEE / DECIMALS;
        return price + protocolFee;
    }

    function getSellPriceAfterFees(uint256 postId, uint256 tokenAmount) external view returns (uint256) {
        uint256 price = getSellPrice(postId, tokenAmount);
        uint256 protocolFee = price * PROTOCOL_FEE / DECIMALS;
        return price - protocolFee;
    }

    function getBuyPrice(uint256 postId, uint256 tokenAmount) public view returns (uint256) {
        return getPrice(tokenInfo[postId].supply, tokenAmount);
    }

    function getSellPrice(uint256 postId, uint256 tokenAmount) public view returns (uint256) {
        return getPrice(tokenInfo[postId].supply - tokenAmount, tokenAmount);
    }

    function getPrice(uint256 supply, uint256 amount) public pure returns (uint256 price) {
        // Calculate sum of squares to get the price
        uint256 sum1 = supply == 0 ? 0 : ((supply - 1) * (supply) * (2 * (supply - 1) + 1)) / 6;
        uint256 sum2 = ((supply + amount - 1) * (supply + amount) * (2 * (supply + amount - 1) + 1)) / 6;
        uint256 summation = sum2 > sum1 ? sum2 - sum1 : 0;

        // Adjust for scaling factor
        price = summation * SCALING_FACTOR / DECIMALS;
    }

    function getFeeSplit(uint256 postId, uint256 fee) public view returns (uint256, uint256, uint256) {
        uint256 realCreatorFee = posts[postId].realCreator == address(0) ? 0 : fee * REAL_CREATOR_FEE_SHARE / DECIMALS;
        uint256 contractCreatorFee =
            contractCreatorRemainingEarnings[postId] > 0 ? fee * CONTRACT_CREATOR_FEE_SHARE / DECIMALS : 0;
        return (realCreatorFee, contractCreatorFee, fee - contractCreatorFee - realCreatorFee);
    }

    function _updateBuyState(uint256 postId, uint256 tokenAmount)
        internal
        returns (uint256 fee, uint256 newSupply, uint256 newPrice)
    {
        // Store supply in local variable for reads
        uint256 supply = tokenInfo[postId].supply;

        // Get the price of the post
        uint256 price = getBuyPrice(postId, tokenAmount);

        // Calculate new supply and price
        newSupply = supply + tokenAmount;
        newPrice = tokenInfo[postId].price + price;

        // Update tokenInfo and totalValueDeposited
        tokenInfo[postId].supply = newSupply;
        tokenInfo[postId].price = newPrice;
        totalValueDeposited += price;

        return (price * PROTOCOL_FEE / DECIMALS, newSupply, newPrice);
    }

    function _updateSellState(uint256 postId, uint256 tokenAmount)
        internal
        returns (uint256 fee, uint256 newSupply, uint256 newPrice)
    {
        // Check if the supply is enough to sell
        uint256 supply = tokenInfo[postId].supply;

        // Ensure atleast the amount of tokens to sell is available and atleast 1 token is left
        if (supply <= tokenAmount) revert InsufficientTokenSupply(postId, supply);

        // Get the price of the post
        uint256 price = getSellPrice(postId, tokenAmount);

        // Check if the user has enough tokens to sell
        if (balanceOf[msg.sender][postId] < tokenAmount) {
            revert InsufficientTokenBalance(postId, msg.sender, balanceOf[msg.sender][postId]);
        }

        // Update tokenInfo and totalValueDeposited
        newSupply = supply - tokenAmount;
        newPrice = tokenInfo[postId].price - price;

        tokenInfo[postId].supply = newSupply;
        tokenInfo[postId].price = newPrice;
        totalValueDeposited -= price;

        return (price * PROTOCOL_FEE / DECIMALS, newSupply, newPrice);
    }

    function _handleBuy(uint256 postId, uint256 tokenAmount, uint256 fee, uint256 glayzeAmount) internal {
        uint256 usdcPayment = fee;
        uint256 glayzePayment = 0;

        // User is using glayze to pay for the purchase
        if (glayzeAmount > 0) {
            if (glayzeAmount >= fee) {
                glayzePayment = fee;
                usdcPayment = 0;
            } else {
                glayzePayment = glayzeAmount;
                usdcPayment = fee - glayzePayment;
            }
        }

        // Pay with GLAYZE
        if (glayzePayment > 0) {
            require(GLAYZE.transferFrom(msg.sender, protocolFeeDestination, glayzePayment), "GlayzeTransferFailed");
        }

        // Make user pay remaining amount in USDC
        if (usdcPayment > 0) {
            require(USDC.transferFrom(msg.sender, protocolFeeDestination, usdcPayment), "USDCTransferFailed");
        }

        _distributeCreatorEarnings(postId, fee);

        // Transfer tokens to user
        require(transferFrom(address(this), msg.sender, postId, tokenAmount), "BuyFailed");
    }

    function _handleSell(uint256 postId, uint256 tokenAmount, uint256 fee, uint256 price, uint256 glayzeAmount)
        internal
    {
        uint256 usdcPayment = price - fee;
        uint256 glayzePayment = 0;

        // User is using glayze to pay for the purchase
        if (glayzeAmount > 0) {
            if (glayzeAmount >= fee) {
                glayzePayment = fee;
            } else {
                glayzePayment = glayzeAmount;
                usdcPayment = price - fee - glayzePayment;
            }
        }

        // Pay with GLAYZE
        if (glayzePayment > 0) {
            require(GLAYZE.transferFrom(msg.sender, protocolFeeDestination, glayzePayment), "GlayzeTransferFailed");
        }

        // Pay User USDC
        require(USDC.transferFrom(protocolFeeDestination, msg.sender, usdcPayment), "USDCTransferFailed");

        _distributeCreatorEarnings(postId, fee);

        // Transfer tokens to contract
        require(transferFrom(msg.sender, address(this), postId, tokenAmount), "SellFailed");
    }

    function _distributeCreatorEarnings(uint256 postId, uint256 fee) internal {
        (uint256 realCreatorFee, uint256 contractCreatorFee, uint256 protocolFee) = getFeeSplit(postId, fee);
        require(protocolFee <= fee, "Fee calculation error");
        emit TradeFees(
            postId, fee - contractCreatorFee - realCreatorFee, contractCreatorFee, realCreatorFee, block.timestamp
        );
        if (contractCreatorFee > 0) {
            require(
                USDC.transferFrom(protocolFeeDestination, posts[postId].contractCreator, contractCreatorFee),
                "ContractCreatorTransferFailed"
            );
        }
        if (realCreatorFee > 0) {
            require(
                USDC.transferFrom(protocolFeeDestination, posts[postId].realCreator, realCreatorFee),
                "RealCreatorTransferFailed"
            );
        }
    }
}
