// SPDX-License-Identifier: MIT
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {ERC6909} from "@solmate/tokens/ERC6909.sol";

pragma solidity ^0.8.19;

contract GlayzeManager is ERC6909, Owned, ReentrancyGuard {
    ///////////////////
    // Errors
    ///////////////////
    error PostCreationFailed(uint256 postId);
    error BuyFailed(uint256 postId);
    error SellFailed(uint256 postId);
    error InsufficientUsdcBalance(uint256 postId);
    error InsufficientTokenBalance(uint256 postId);
    error InsufficientTokenSupply(uint256 postId);
    error InvalidPostId(uint256 postId);
    error ContractCreatorTransferFailed(uint256 postId);
    error RealCreatorTransferFailed(uint256 postId);
    error RealCreatorAlreadyExists(uint256 postId);

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

    ///////////////////
    // State variables
    ///////////////////
    IERC20 public immutable USDC;
    IERC20 public immutable GLAYZE;
    uint256 public totalValueDeposited;
    uint256 public postIdCounter;
    mapping(uint256 id => Post post) public posts;
    mapping(uint256 id => TokenInfo tokenInfo) public tokenInfo;
    mapping(uint256 id => uint256 remainingEarnings) public contractCreatorRemainingEarnings;

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
        uint256 usdcAmount,
        uint256 tokenAmountOut,
        uint256 newSupply,
        uint256 newPrice,
        uint256 timestamp
    );

    event TradeFees(
        uint256 postId,
        uint256 protocolFeeAfterSplit,
        uint256 contractCreatorFee,
        uint256 realCreatorFee,
        uint256 timestamp
    );

    ///////////////////
    // Modifiers
    ///////////////////
    modifier validPost(uint256 postId) {
        if (postId >= postIdCounter) revert InvalidPostId(postId);
        _;
    }

    constructor(address _usdc, address _glayze) Owned(msg.sender) {
        USDC = IERC20(_usdc);
        GLAYZE = IERC20(_glayze);
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

        // Emit event
        emit PostCreated(postId, msg.sender, name, symbol, postURI, block.timestamp);

        // Increment postIdCounter
        postIdCounter++;

        // Mint MAX_SUPPLY posts to the contract
        _mint(address(this), postId, MAX_SUPPLY);

        // Transfer USDC_CREATION_PAYMENT to contract
        bool success = USDC.transfer(address(this), USDC_CREATION_PAYMENT);
        if (!success) revert PostCreationFailed(postId);
    }

    function buyTokens(uint256 postId, uint256 tokenAmount) external nonReentrant validPost(postId) {
        uint256 supply = tokenInfo[postId].supply;
        // Get the price of the post
        uint256 price = _getBuyPrice(postId, tokenAmount);

        // Calculate the fee before distributing to creator
        uint256 fee = price * PROTOCOL_FEE / DECIMALS;

        // Distribute the fee to the creators
        uint256 feeAfterSplit = _distributeCreatorEarnings(postId, fee);

        // Update tokenInfo and totalValueDeposited
        tokenInfo[postId].supply = supply + tokenAmount;
        tokenInfo[postId].price += price;
        totalValueDeposited += price;

        // Emit event
        emit Trade(
            postId,
            msg.sender,
            true,
            feeAfterSplit,
            tokenAmount,
            supply + tokenAmount,
            tokenInfo[postId].price,
            block.timestamp
        );

        // // Transfer USDC to protocol fee destination
        // // Transfer Post shares to user
        bool usdcTransferSuccess = USDC.transfer(address(this), feeAfterSplit);
        bool tokenTransferSuccess = transferFrom(address(this), msg.sender, postId, tokenAmount);
        if (!tokenTransferSuccess || !usdcTransferSuccess) revert BuyFailed(postId);
    }

    function sellTokens(uint256 postId, uint256 tokenAmount) external nonReentrant validPost(postId) {
        // Check if the user has enough tokens to sell
        uint256 supply = tokenInfo[postId].supply;
        if (supply < tokenAmount) revert InsufficientTokenSupply(postId);

        // Get the price of the post
        uint256 price = _getSellPrice(postId, tokenAmount);

        // Calculate the protocol fee
        uint256 fee = price * PROTOCOL_FEE / DECIMALS;

        if (balanceOf[msg.sender][postId] < tokenAmount) revert InsufficientTokenBalance(postId);

        // Update tokenInfo and totalValueDeposited
        tokenInfo[postId].supply -= tokenAmount;
        tokenInfo[postId].price -= price;
        totalValueDeposited -= price;

        uint256 feeAfterSplit = _distributeCreatorEarnings(postId, fee);

        // Emit event
        emit Trade(
            postId,
            msg.sender,
            false,
            feeAfterSplit,
            tokenAmount,
            supply - tokenAmount,
            tokenInfo[postId].price,
            block.timestamp
        );

        bool tokenTransferSuccess = transfer(address(this), postId, tokenAmount);
        bool usdcTransferSuccess = USDC.transferFrom(address(this), msg.sender, price - feeAfterSplit);
        bool protocolTransferSuccess = USDC.transfer(address(this), feeAfterSplit);
        if (!tokenTransferSuccess || !usdcTransferSuccess || !protocolTransferSuccess) revert SellFailed(postId);
    }

    function setRealCreator(uint256 postId, address realCreator) external onlyOwner {
        if (posts[postId].realCreator != address(0)) revert RealCreatorAlreadyExists(postId);
        posts[postId].realCreator = realCreator;
    }

    function getBuyPriceAfterFees(uint256 postId, uint256 usdcAmount) external view returns (uint256) {
        uint256 price = _getBuyPrice(postId, usdcAmount);
        uint256 protocolFee = price * PROTOCOL_FEE / DECIMALS;
        return price + protocolFee;
    }

    function getSellPriceAfterFees(uint256 postId, uint256 postAmount) external view returns (uint256) {
        uint256 price = _getSellPrice(postId, postAmount);
        uint256 protocolFee = price * PROTOCOL_FEE / DECIMALS;
        return price - protocolFee;
    }

    function _getBuyPrice(uint256 postId, uint256 usdcAmount) internal view returns (uint256) {
        return _getPrice(tokenInfo[postId].supply, usdcAmount);
    }

    function _getSellPrice(uint256 postId, uint256 postAmount) internal view returns (uint256) {
        return _getPrice(tokenInfo[postId].supply - postAmount, postAmount);
    }

    function _getPrice(uint256 supply, uint256 amount) internal pure returns (uint256 price) {
        // Calculate sum of squares to get the price
        uint256 sum1 = supply == 0 ? 0 : ((supply - 1) * (supply) * (2 * (supply - 1) + 1)) / 6;
        uint256 sum2 = ((supply + amount - 1) * (supply + amount) * (2 * (supply + amount - 1) + 1)) / 6;
        uint256 summation = sum2 > sum1 ? sum2 - sum1 : 0;

        // Adjust for scaling factor
        price = summation * SCALING_FACTOR / DECIMALS;
    }

    function _distributeCreatorEarnings(uint256 postId, uint256 fee) internal returns (uint256 feeAfterSplit) {
        address realCreator = posts[postId].realCreator;
        bool contractCreatorHasEarnings = contractCreatorRemainingEarnings[postId] > 0;
        uint256 realCreatorFee = realCreator == address(0) ? 0 : fee * REAL_CREATOR_FEE_SHARE / DECIMALS;
        uint256 contractCreatorFee = contractCreatorHasEarnings ? fee * CONTRACT_CREATOR_FEE_SHARE / DECIMALS : 0;
        feeAfterSplit = fee - contractCreatorFee - realCreatorFee;
        emit TradeFees(postId, feeAfterSplit, contractCreatorFee, realCreatorFee, block.timestamp);
        if (contractCreatorHasEarnings) {
            bool contractCreatorSuccess =
                USDC.transferFrom(address(this), posts[postId].contractCreator, contractCreatorFee);
            if (!contractCreatorSuccess) revert ContractCreatorTransferFailed(postId);
        }
        bool realCreatorSuccess = USDC.transferFrom(address(this), realCreator, realCreatorFee);
        if (!realCreatorSuccess) revert RealCreatorTransferFailed(postId);
    }
}
