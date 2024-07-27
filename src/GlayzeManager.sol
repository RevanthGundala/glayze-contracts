// SPDX-License-Identifier: MIT
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {ERC6909} from "@solmate/tokens/ERC6909.sol";
import {console2} from "forge-std/console2.sol";

pragma solidity ^0.8.19;

// V1 Has USDC and GLAYZE sent to EOA
// Tokens remain in contract
// Creators always get paid in usdc (cannot pay for glayze for their share, so lower their fee share)

contract GlayzeManager is ERC6909, Owned, ReentrancyGuard {
    ///////////////////
    // Errors
    ///////////////////
    error InsufficientTokenBalance(uint256 postId, address user, uint256 balance);
    error InsufficientTokenSupply(uint256 postId, uint256 supply);
    error InvalidPostId(uint256 postId);
    error RealCreatorAlreadyExists(uint256 postId, address creator);
    error UserAlreadyReferred(address user);
    error TokenAmountZero(uint256 postId);

    ///////////////////
    // Constants
    ///////////////////
    uint256 public constant DECIMALS = 1e6;
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e6; // 1 billion
    uint256 public constant SCALING_FACTOR = 3000; // Adjusted for 6 decimals
    uint256 public constant USDC_CREATION_PAYMENT = 1000000; // 1 USDC
    uint256 public constant PROTOCOL_FEE = 25000; // 2.5%
    uint256 public constant REAL_CREATOR_FEE = 5000; // 0.5%
    uint256 public constant CONTRACT_CREATOR_FEE = 100; // 0.01%
    // TODO: calclate glayze token value
    uint256 public constant GLAYZE_REFERRAL_AMOUNT = 100000000000000000; // 100 GLAYZE

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

    modifier tokenAmountNotZero(uint256 postId, uint256 tokenAmount) {
        if (tokenAmount == 0) revert TokenAmountZero(postId);
        _;
    }

    constructor(address _usdc, address _glayze) Owned(msg.sender) {
        USDC = IERC20(_usdc);
        GLAYZE = IERC20(_glayze);
        protocolFeeDestination = msg.sender;
        super.setOperator(address(this), true);
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

        // Increment postIdCounter
        postIdCounter++;

        // Emit event
        emit PostCreated(postId, msg.sender, name, symbol, postURI, block.timestamp);

        // Mint MAX_SUPPLY posts to the contract
        _mint(address(this), postId, MAX_SUPPLY);

        // Transfer USDC_CREATION_PAYMENT to Protocol
        require(USDC.transferFrom(msg.sender, protocolFeeDestination, USDC_CREATION_PAYMENT), "InsufficientUsdcBalance");
    }

    function buyTokens(uint256 postId, uint256 tokenAmount, uint256 glayzeAmount)
        external
        nonReentrant
        validPost(postId)
        tokenAmountNotZero(postId, tokenAmount)
    {
        (uint256 buyPrice, uint256 newSupply, uint256 newPrice) = _updateBuyState(postId, tokenAmount);

        // Emit event
        emit Trade(postId, msg.sender, true, glayzeAmount, buyPrice, tokenAmount, newSupply, newPrice, block.timestamp);

        // Distribute the fee to the creators
        _handleBuy(postId, tokenAmount, buyPrice, glayzeAmount);
    }

    function sellTokens(uint256 postId, uint256 tokenAmount, uint256 glayzeAmount)
        external
        nonReentrant
        validPost(postId)
        tokenAmountNotZero(postId, tokenAmount)
    {
        (uint256 sellPrice, uint256 newSupply, uint256 newPrice) = _updateSellState(postId, tokenAmount);

        // Emit event
        emit Trade(
            postId, msg.sender, false, glayzeAmount, sellPrice, tokenAmount, newSupply, newPrice, block.timestamp
        );

        _handleSell(postId, tokenAmount, sellPrice, glayzeAmount);
    }

    function setRealCreator(uint256 postId, address realCreator) external onlyOwner validPost(postId) {
        if (posts[postId].realCreator != address(0)) revert RealCreatorAlreadyExists(postId, realCreator);
        posts[postId].realCreator = realCreator;
        emit RealCreatorSet(postId, realCreator, block.timestamp);
    }

    function refer(address user, address referrer) external onlyOwner {
        if (usersReferred[user]) revert UserAlreadyReferred(user);
        usersReferred[user] = true;
        emit Refer(user, referrer, block.timestamp);
        require(
            GLAYZE.transferFrom(protocolFeeDestination, user, GLAYZE_REFERRAL_AMOUNT)
                && GLAYZE.transferFrom(protocolFeeDestination, referrer, GLAYZE_REFERRAL_AMOUNT),
            "TransferFailed"
        );
    }

    function getBuyPriceAfterFees(uint256 postId, uint256 tokenAmount)
        public
        view
        validPost(postId)
        returns (uint256)
    {
        uint256 price = getBuyPrice(postId, tokenAmount);
        return price + getTotalFees(postId, price);
    }

    function getSellPriceAfterFees(uint256 postId, uint256 tokenAmount)
        public
        view
        validPost(postId)
        returns (uint256)
    {
        uint256 price = getSellPrice(postId, tokenAmount);
        return price - getTotalFees(postId, price);
    }

    function getBuyPrice(uint256 postId, uint256 tokenAmount) public view validPost(postId) returns (uint256) {
        return getPrice(tokenInfo[postId].supply, tokenAmount);
    }

    function getSellPrice(uint256 postId, uint256 tokenAmount) public view validPost(postId) returns (uint256) {
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

    function getFeeSplit(uint256 postId, uint256 price)
        public
        view
        validPost(postId)
        returns (uint256, uint256, uint256)
    {
        uint256 contractCreatorFee =
            contractCreatorRemainingEarnings[postId] > 0 ? price * CONTRACT_CREATOR_FEE / DECIMALS : 0;
        return (price * PROTOCOL_FEE / DECIMALS, contractCreatorFee, price * REAL_CREATOR_FEE / DECIMALS);
    }

    function getTotalFees(uint256 postId, uint256 price) public view validPost(postId) returns (uint256) {
        uint256 contractCreatorFee =
            contractCreatorRemainingEarnings[postId] > 0 ? price * CONTRACT_CREATOR_FEE / DECIMALS : 0;
        return ((price * PROTOCOL_FEE / DECIMALS) + contractCreatorFee + (price * REAL_CREATOR_FEE / DECIMALS));
    }

    function _updateBuyState(uint256 postId, uint256 tokenAmount)
        internal
        returns (uint256 price, uint256 newSupply, uint256 newPrice)
    {
        // Store supply in local variable for reads
        uint256 supply = tokenInfo[postId].supply;

        // Get the price of the post
        price = getBuyPrice(postId, tokenAmount);

        // Calculate new supply and price
        newSupply = supply + tokenAmount;
        newPrice = tokenInfo[postId].price + price;

        // Update tokenInfo and totalValueDeposited
        tokenInfo[postId].supply = newSupply;
        tokenInfo[postId].price = newPrice;
        totalValueDeposited += price;
        return (price, newSupply, newPrice);
    }

    function _updateSellState(uint256 postId, uint256 tokenAmount)
        internal
        returns (uint256 sellPrice, uint256 newSupply, uint256 newPrice)
    {
        // Check if the supply is enough to sell
        uint256 supply = tokenInfo[postId].supply;

        // Ensure atleast the amount of tokens to sell is available
        if (supply < tokenAmount) revert InsufficientTokenSupply(postId, supply);

        // Get the price of the post
        sellPrice = getSellPrice(postId, tokenAmount);

        // Check if the user has enough tokens to sell
        if (balanceOf[msg.sender][postId] < tokenAmount) {
            revert InsufficientTokenBalance(postId, msg.sender, balanceOf[msg.sender][postId]);
        }

        // Update tokenInfo and totalValueDeposited
        newSupply = supply - tokenAmount;
        newPrice = tokenInfo[postId].price - sellPrice;

        tokenInfo[postId].supply = newSupply;
        tokenInfo[postId].price = newPrice;
        totalValueDeposited -= sellPrice;

        return (sellPrice, newSupply, newPrice);
    }

    function _handleBuy(uint256 postId, uint256 tokenAmount, uint256 buyPrice, uint256 glayzeAmount) internal {
        (uint256 protocolFee, uint256 contractCreatorFee, uint256 realCreatorFee) = getFeeSplit(postId, buyPrice);
        uint256 protocolFeesPaidInGlayze = 0;
        uint256 protocolFeesPaidInUsdc = protocolFee;
        // User is using glayze to pay for the purchase
        if (glayzeAmount > 0) {
            if (glayzeAmount >= protocolFee) {
                protocolFeesPaidInGlayze = protocolFee;
                protocolFeesPaidInUsdc = 0;
            } else {
                protocolFeesPaidInGlayze = glayzeAmount;
                protocolFeesPaidInUsdc = protocolFee - glayzeAmount;
            }
        }

        // Pay protocol fees with GLAYZE
        if (protocolFeesPaidInGlayze > 0) {
            require(
                GLAYZE.transferFrom(msg.sender, protocolFeeDestination, protocolFeesPaidInGlayze),
                "GlayzeTransferFailed"
            );
        }

        // Make user pay remaining amount in USDC
        if (protocolFeesPaidInUsdc > 0) {
            require(USDC.transferFrom(msg.sender, protocolFeeDestination, protocolFeesPaidInUsdc), "USDCTransferFailed");
        }

        // Transfer price to contract
        require(USDC.transferFrom(msg.sender, address(this), buyPrice), "USDCTransferFailed");

        // Distribute creator earnings based on total usdcAmount
        _distributeCreatorEarnings(postId, realCreatorFee, contractCreatorFee, protocolFee);

        // Transfer tokens to user
        // console2.log("Contract supply: ", balanceOf[address(this)][postId]);
        // console2.log("User supply: ", balanceOf[msg.sender][postId]);
        // require(transferFrom(address(this), msg.sender, postId, tokenAmount), "BuyFailed");
        _transfer(address(this), msg.sender, postId, tokenAmount);
    }

    function _handleSell(uint256 postId, uint256 tokenAmount, uint256 sellPrice, uint256 glayzeAmount) internal {
        (uint256 protocolFee, uint256 contractCreatorFee, uint256 realCreatorFee) = getFeeSplit(postId, sellPrice);
        uint256 protocolFeesPaidInGlayze = 0;
        uint256 protocolFeesPaidInUsdc = protocolFee;

        // User is using glayze to pay for the purchase
        if (glayzeAmount > 0) {
            if (glayzeAmount >= protocolFee) {
                protocolFeesPaidInGlayze = protocolFee;
                protocolFeesPaidInUsdc = 0;
            } else {
                protocolFeesPaidInGlayze = glayzeAmount;
                protocolFeesPaidInUsdc = protocolFee - glayzeAmount;
            }
        }

        // Pay with GLAYZE
        if (protocolFeesPaidInGlayze > 0) {
            require(
                GLAYZE.transferFrom(msg.sender, protocolFeeDestination, protocolFeesPaidInGlayze),
                "GlayzeTransferFailed"
            );
        }

        // Pay
        if (protocolFeesPaidInUsdc > 0) {
            require(USDC.transferFrom(msg.sender, protocolFeeDestination, protocolFeesPaidInUsdc), "USDCTransferFailed");
        }

        // Transfer price to sender
        require(USDC.transfer(msg.sender, sellPrice), "USDCTransferFailed");

        _distributeCreatorEarnings(postId, realCreatorFee, contractCreatorFee, protocolFee);

        // Transfer tokens to contract
        require(transferFrom(msg.sender, address(this), postId, tokenAmount), "SellFailed");
    }

    function _distributeCreatorEarnings(
        uint256 postId,
        uint256 realCreatorFee,
        uint256 contractCreatorFee,
        uint256 protocolFee
    ) internal {
        emit TradeFees(postId, protocolFee, contractCreatorFee, realCreatorFee, block.timestamp);
        if (contractCreatorFee > 0) {
            require(
                USDC.transferFrom(msg.sender, posts[postId].contractCreator, contractCreatorFee),
                "ContractCreatorTransferFailed"
            );
        }
        // If the real creator hasn't signed up yet, use the contract owner as the real creator
        address realCreator =
            posts[postId].realCreator == address(0) ? protocolFeeDestination : posts[postId].realCreator;
        require(USDC.transferFrom(msg.sender, realCreator, realCreatorFee), "RealCreatorTransferFailed");
    }

    function _transfer(address from, address to, uint256 postId, uint256 amount) internal {
        balanceOf[from][postId] -= amount;
        balanceOf[to][postId] += amount;
    }
}
