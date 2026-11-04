// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Conditionals} from "../src/Conditionals.sol";

/// @dev Complements the basic ERC-20 suite with boundaries and properties over several calls.
/// forge-config: default.fuzz.runs = 1000
contract ConditionalsPropertiesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    Conditionals private token;
    address private holder;
    address private recipient;
    address private spender;
    address private otherSpender;

    function setUp() public {
        token = new Conditionals();
        holder = makeAddr("property holder");
        recipient = makeAddr("property recipient");
        spender = makeAddr("property spender");
        otherSpender = makeAddr("other property spender");
    }

    function test_DirectRoundTripAtZeroOneWeiAndFullSupply() public {
        uint256[4] memory amounts = [uint256(0), 1, SUPPLY - 1, SUPPLY];
        for (uint256 i; i < amounts.length; ++i) {
            _directRoundTrip(amounts[i]);
        }
    }

    function test_MaximumAmountCannotOverflowDirectOrDelegatedBalances() public {
        uint256 amount = type(uint256).max;
        bytes memory reason =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount);
        vm.expectRevert(reason);
        token.transfer(recipient, amount);

        assertTrue(token.approve(spender, amount));
        vm.expectRevert(reason);
        vm.prank(spender);
        token.transferFrom(address(this), recipient, amount);

        assertEq(token.allowance(address(this), spender), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumMinusOneAllowanceIsFinite() public {
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_UnlimitedApprovalCanBeReducedThenRevoked() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 1));

        assertTrue(token.approve(spender, 2));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 2));
        assertEq(token.allowance(address(this), spender), 0);
        _expectNoAllowance(address(this), spender, recipient);

        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, 0));
        _expectNoAllowance(address(this), spender, recipient);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(recipient), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_OwnerTransferFromRequiresExplicitSelfApproval() public {
        assertTrue(token.transfer(holder, 1));
        _expectNoAllowance(holder, holder, recipient);
        vm.prank(holder);
        assertTrue(token.approve(holder, 1));
        vm.prank(holder);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, holder), 0);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 1);
    }

    function test_DelegatedSelfTransferStillNeedsBalanceAndRestoresAllowance() public {
        assertTrue(token.transfer(holder, 10));
        vm.prank(holder);
        assertTrue(token.approve(spender, 11));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 10, 11));
        vm.prank(spender);
        token.transferFrom(holder, holder, 11);
        assertEq(token.allowance(holder, spender), 11);
        assertEq(token.balanceOf(holder), 10);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApprovalsDoNotFollowTokensToANewHolder() public {
        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.transfer(holder, SUPPLY));
        _expectNoAllowance(holder, spender, recipient);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_ApprovalBeforeFundingSurvivesFailedSpend() public {
        vm.prank(holder);
        assertTrue(token.approve(spender, 3));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.allowance(holder, spender), 3);

        assertTrue(token.transfer(holder, 3));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 3));
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
    }

    function test_ZeroSpenderApprovalRejectsAllBoundaryAmounts() public {
        assertTrue(token.approve(spender, 9));
        uint256[4] memory amounts = [uint256(0), 1, SUPPLY, type(uint256).max];
        for (uint256 i; i < amounts.length; ++i) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            token.approve(address(0), amounts[i]);
            assertEq(token.allowance(address(this), address(0)), 0);
            assertEq(token.allowance(address(this), spender), 9);
        }
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ZeroDelegatedTransfersPreserveFiniteAndInfiniteApproval() public {
        uint256[2] memory approvals = [uint256(7), type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            vm.prank(holder);
            assertTrue(token.approve(spender, approvals[i]));
            vm.expectEmit(true, true, false, true, address(token));
            emit IERC20.Transfer(holder, recipient, 0);
            vm.prank(spender);
            assertTrue(token.transferFrom(holder, recipient, 0));
            assertEq(token.allowance(holder, spender), approvals[i]);
            assertEq(token.balanceOf(holder), 0);
            assertEq(token.balanceOf(recipient), 0);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DirectRoundTripRestoresBalances(uint256 amount) public {
        _directRoundTrip(bound(amount, 0, SUPPLY));
    }

    function testFuzz_SplitTransfersEqualOneTransfer(uint256 amount, uint256 first) public {
        amount = bound(amount, 0, SUPPLY);
        first = bound(first, 0, amount);
        Conditionals lumpSumToken = new Conditionals();

        assertTrue(token.transfer(holder, first));
        assertTrue(token.transfer(holder, amount - first));
        assertTrue(lumpSumToken.transfer(holder, amount));

        assertEq(token.balanceOf(holder), lumpSumToken.balanceOf(holder));
        assertEq(token.balanceOf(holder), amount);
        assertEq(token.balanceOf(address(this)), lumpSumToken.balanceOf(address(this)));
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(lumpSumToken.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedRoundTripConsumesBothApprovals(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.approve(spender, amount));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), holder, amount));
        assertEq(token.balanceOf(holder), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);

        vm.prank(holder);
        assertTrue(token.approve(spender, amount));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RepeatedSpendsCannotExceedCumulativeApproval(uint256 approval, uint256 first) public {
        approval = bound(approval, 1, SUPPLY);
        first = bound(first, 0, approval);
        assertTrue(token.approve(spender, approval));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), holder, first));
        assertEq(token.allowance(address(this), spender), approval - first);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, approval - first));
        _expectNoAllowance(address(this), spender, recipient);

        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(holder), first);
        assertEq(token.balanceOf(recipient), approval - first);
        assertEq(token.balanceOf(address(this)), SUPPLY - approval);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_BalanceFailurePreservesApproval(
        uint256 balance,
        uint256 amount,
        bool unlimited,
        bool selfTransfer
    ) public {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, balance + 1, type(uint256).max);
        uint256 approval = unlimited ? type(uint256).max : amount;
        assertTrue(token.transfer(holder, balance));
        vm.prank(holder);
        assertTrue(token.approve(spender, approval));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, balance, amount));
        vm.prank(spender);
        token.transferFrom(holder, selfTransfer ? holder : recipient, amount);
        assertEq(token.allowance(holder, spender), approval);
        assertEq(token.balanceOf(holder), balance);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InvalidRecipientPreservesApproval(uint256 amount, bool unlimited) public {
        amount = bound(amount, 0, SUPPLY);
        uint256 approval = unlimited ? type(uint256).max : amount;
        assertTrue(token.approve(spender, approval));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);

        assertEq(token.allowance(address(this), spender), approval);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_AllowanceChangesAreIsolatedByOwnerAndSpender(uint256 approval, uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        approval = bound(approval, amount, type(uint256).max);
        assertTrue(token.approve(spender, approval));
        assertTrue(token.approve(otherSpender, 11));
        vm.prank(holder);
        assertTrue(token.approve(spender, 13));
        vm.prank(holder);
        assertTrue(token.approve(otherSpender, 17));

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), holder, amount));
        assertEq(token.allowance(address(this), spender), approval == type(uint256).max ? approval : approval - amount);
        assertEq(token.allowance(address(this), otherSpender), 11);
        assertEq(token.allowance(holder, spender), 13);
        assertEq(token.allowance(holder, otherSpender), 17);
        assertEq(token.allowance(spender, address(this)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(holder), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _directRoundTrip(uint256 amount) private {
        assertTrue(token.transfer(holder, amount));
        assertEq(token.balanceOf(holder), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        vm.prank(holder);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _expectNoAllowance(address owner, address caller, address to) private {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, caller, 0, 1));
        vm.prank(caller);
        token.transferFrom(owner, to, 1);
    }
}
