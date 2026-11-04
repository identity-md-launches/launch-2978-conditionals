// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Conditionals (COND)
/// @notice Fixed-supply ERC-20 with 18 decimals and no administrative powers.
contract Conditionals is ERC20 {
    /// @notice One billion COND, expressed in the token's smallest unit.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev The immediate deployer receives the entire supply, including when it is a factory.
    constructor() ERC20("Conditionals", "COND") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
