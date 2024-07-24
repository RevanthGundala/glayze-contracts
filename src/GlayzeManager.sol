// SPDX-License-Identifier: MIT
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

pragma solidity ^0.8.19;

error InvalidPoolKey();
error InvalidToken();
error InvalidAmount();
error InsufficientBalance();

contract GlayzeManager is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address public constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // TODO: base usdc
    uint256 public constant PROTOCOL_FEE = 10; // 3% of tx fess

    struct GlayzePool {
        uint128 liquidity;
        uint256 sqrtPriceX96;
        uint256 tokenBalance;
        uint256 usdcBalance;
        mapping(address => uint256) userLiquidity;
    }

    // The PoolKey is the address of the ERC20 token
    mapping(address token => GlayzePool pool) public pools;

    event PoolCreated(address indexed token, address indexed creator);
    event Bought(address indexed token, address indexed sender, uint256 usdcAmountIn, uint256 tokenAmountOut);
    event Sold(address indexed token, address indexed sender, uint256 tokenAmountIn, uint256 usdcAmountOut);

    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    function initializePool(address token, address creator) external {
        if (token == address(0) || IERC20(token).totalSupply() == 0) revert InvalidToken();
        pools[token] = GlayzePool({liquidity: 0, sqrtPriceX96: 0, tokenBalance: 0, usdcBalance: 0}); // TODO:
        emit PoolCreated(token, creator);
    }

    function buy(address token, uint256 usdcAmount) external returns (uint256 tokenAmount) {
        if (usdcAmount == 0) revert InvalidAmount();
        if (IERC20(token).balanceOf(msg.sender) < usdcAmount) revert InsufficientBalance();
        // TODO: calculate token amount
        IERC20(token).transferFrom(msg.sender, address(this), usdcAmount);
        pools[token].usdcBalance += usdcAmount;
        pools[token].tokenBalance += tokenAmount;
        emit Bought(token, msg.sender, usdcAmount, tokenAmount);
    }

    function sell(address token, uint256 tokenAmount) external returns (uint256 usdcAmount) {
        if (tokenAmount == 0) revert InvalidAmount();
        if (IERC20(token).balanceOf(msg.sender) < tokenAmount) revert InsufficientBalance();
        // TODO: calculate usdc amount
    }

    function _calculateAmountOut(address tokenIn, address tokenOut, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        // TODO: calculate amount out logic
    }

    // TODO: Off-chain figure out if a creator's tweet has been posted
    // If they have an account, send them money. Otherwise, deposit into escrow

    function getPool(address token) external view returns (GlayzePool memory) {
        return pools[token];
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
