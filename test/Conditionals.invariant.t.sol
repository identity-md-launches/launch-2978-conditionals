// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Conditionals} from "../src/Conditionals.sol";

/// @dev A closed set of actors lets the invariant account for every token and every approval.
contract TokenHandler is Test {
    Conditionals private immutable token;
    address[4] private actors;

    mapping(address account => uint256 balance) public expectedBalance;
    mapping(address owner => mapping(address spender => uint256 amount)) public expectedAllowance;

    constructor(Conditionals token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        for (uint256 i; i < actors.length; ++i) {
            expectedBalance[actors[i]] = token.balanceOf(actors[i]);
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = expectedAllowance[from][spender];
        uint256 available = expectedBalance[from];
        amount = bound(amount, 0, allowed < available ? allowed : available);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        if (allowed != type(uint256).max) expectedAllowance[from][spender] -= amount;
    }

    /// @dev Failed delegated calls must preserve both balances and approvals throughout a sequence.
    function overdraw(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = expectedBalance[owner] + 1;
        vm.prank(spender);
        (bool succeeded,) = address(token).call(abi.encodeCall(token.transferFrom, (owner, to, amount)));
        assertFalse(succeeded, "overdraw succeeded");
    }
}

contract ConditionalsInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    Conditionals private token;
    TokenHandler private handler;
    address[4] private actors;

    function setUp() public {
        token = new Conditionals();
        actors = [makeAddr("actor 0"), makeAddr("actor 1"), makeAddr("actor 2"), makeAddr("actor 3")];
        assertTrue(token.transfer(actors[0], SUPPLY));
        handler = new TokenHandler(token, actors);

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.overdraw.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyBalancesAndAllowancesMatchModel() public view {
        assertEq(token.totalSupply(), SUPPLY);
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            address actor = actors[i];
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            sum += balance;
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actor, actors[j]), handler.expectedAllowance(actor, actors[j]));
            }
        }
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }
}
