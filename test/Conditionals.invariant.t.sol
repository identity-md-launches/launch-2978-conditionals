// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
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
        _approve(owner, spender, amount);
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

    /// @dev Approve enough first so this reaches the balance check, after allowance consumption.
    function overdraw(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = expectedBalance[owner] + 1;
        _approve(owner, spender, amount);
        _expectRejected(
            spender,
            abi.encodeCall(token.transferFrom, (owner, to, amount)),
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, owner, expectedBalance[owner], amount
            )
        );
    }

    /// @dev Hit revocation, dust, the current balance, and both sides of the unlimited sentinel.
    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 kind) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256[5] memory amounts = [uint256(0), 1, expectedBalance[owner], type(uint256).max - 1, type(uint256).max];
        _approve(owner, spender, amounts[kind % amounts.length]);
    }

    function transferAll(uint256 fromSeed, uint256 toSeed) external {
        address from = _fundedActor(fromSeed);
        address to = actors[toSeed % actors.length];
        uint256 amount = expectedBalance[from];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    /// @dev Always spends a positive amount, with either an exactly exhausted or unlimited approval.
    function approveAndSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount, bool unlimited)
        external
    {
        address owner = _fundedActor(ownerSeed);
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 1, expectedBalance[owner]);
        _approve(owner, spender, unlimited ? type(uint256).max : amount);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (!unlimited) expectedAllowance[owner][spender] = 0;
    }

    function overdrawDirect(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = expectedBalance[from] + 1;
        _expectRejected(
            from,
            abi.encodeCall(token.transfer, (to, amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, expectedBalance[from], amount)
        );
    }

    /// @dev The owner can afford the spend; only the spender's authorization is insufficient.
    function overspendAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 approval) external {
        address owner = _fundedActor(ownerSeed);
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        approval = bound(approval, 0, expectedBalance[owner] - 1);
        _approve(owner, spender, approval);
        _expectRejected(
            spender,
            abi.encodeCall(token.transferFrom, (owner, to, approval + 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approval, approval + 1)
        );
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[owner]);
        bytes memory reason = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        if (delegated) {
            uint256 allowed = expectedAllowance[owner][spender];
            amount = amount < allowed ? amount : allowed;
            _expectRejected(spender, abi.encodeCall(token.transferFrom, (owner, address(0), amount)), reason);
        } else {
            _expectRejected(owner, abi.encodeCall(token.transfer, (address(0), amount)), reason);
        }
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        _expectRejected(
            owner,
            abi.encodeCall(token.approve, (address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _expectRejected(address caller, bytes memory data, bytes memory reason) private {
        vm.prank(caller);
        (bool succeeded, bytes memory returned) = address(token).call(data);
        assertFalse(succeeded, "invalid call succeeded");
        assertEq(returned, reason, "unexpected failure reason");
        // No ghost updates: the invariant checks that the entire ledger stayed unchanged.
    }

    function _fundedActor(uint256 seed) private view returns (address) {
        uint256 start = seed % actors.length;
        for (uint256 i; i < actors.length; ++i) {
            address actor = actors[(start + i) % actors.length];
            if (expectedBalance[actor] > 0) return actor;
        }
        revert("the model lost the fixed supply");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
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

        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.overdraw.selector;
        selectors[4] = TokenHandler.approveBoundary.selector;
        selectors[5] = TokenHandler.transferAll.selector;
        selectors[6] = TokenHandler.approveAndSpend.selector;
        selectors[7] = TokenHandler.overdrawDirect.selector;
        selectors[8] = TokenHandler.overspendAllowance.selector;
        selectors[9] = TokenHandler.rejectZeroRecipient.selector;
        selectors[10] = TokenHandler.rejectZeroSpender.selector;
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
            assertEq(token.allowance(actor, address(0)), 0);
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actor, actors[j]), handler.expectedAllowance(actor, actors[j]));
            }
        }
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    /// @dev Every holder must still be able to move its full balance after any generated sequence.
    function afterInvariant() public {
        for (uint256 i = 1; i < actors.length; ++i) {
            handler.transfer(i, 0, handler.expectedBalance(actors[i]));
            assertEq(token.balanceOf(actors[i]), 0);
        }
        assertEq(token.balanceOf(actors[0]), SUPPLY);
        invariant_SupplyBalancesAndAllowancesMatchModel();
    }
}
