// SPDX-License-Identifier: MIT
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

pragma solidity ^0.8.19;

contract Aura is ERC20 {
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e6; // 1 billion

    constructor() ERC20("Aura", "AURA") {
        _mint(msg.sender, MAX_SUPPLY);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
