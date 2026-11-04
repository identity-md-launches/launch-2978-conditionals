// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Conditionals} from "../src/Conditionals.sol";

contract ConditionalsTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    Conditionals private token;
    address private holder;
    address private recipient;
    address private spender;
    address private outsider;

    function setUp() public {
        token = new Conditionals();
        holder = makeAddr("holder");
        recipient = makeAddr("recipient");
        spender = makeAddr("spender");
        outsider = makeAddr("outsider");
    }

    function test_MetadataAndInitialSupply() public view {
        assertEq(token.name(), "Conditionals");
        assertEq(token.symbol(), "COND");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_ConstructorEmitsExactlyOneMintToDeployer() public {
        vm.recordLogs();
        vm.prank(holder);
        Conditionals deployed = new Conditionals();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(deployed));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(holder))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
        assertEq(deployed.balanceOf(holder), SUPPLY);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_TransferReturnsTrueAndEmitsExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), holder, 123 ether);
        assertTrue(token.transfer(holder, 123 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY - 123 ether);
        assertEq(token.balanceOf(holder), 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferEntireSupply() public {
        assertTrue(token.transfer(holder, SUPPLY));
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountSucceedsAndEmits() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(holder, recipient, 0);
        vm.prank(holder);
        assertTrue(token.transfer(recipient, 0));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferDoesNotChangeBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferRejectsInsufficientBalanceWithoutChangingState() public {
        assertTrue(token.transfer(holder, 10));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 10, 11));
        vm.prank(holder);
        token.transfer(recipient, 11);
        assertEq(token.balanceOf(holder), 10);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferStillRequiresSufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 0, 1));
        vm.prank(holder);
        token.transfer(holder, 1);
        assertEq(token.balanceOf(holder), 0);
    }

    function test_TransferRejectsZeroRecipientEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApproveEmitsAndOnlyChangesCallersAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(holder, spender, 100);
        vm.prank(holder);
        assertTrue(token.approve(spender, 100));
        assertEq(token.allowance(holder, spender), 100);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.allowance(holder, outsider), 0);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApprovalCanBeReplacedAndRevoked() public {
        assertTrue(token.approve(spender, 100));
        assertTrue(token.approve(spender, 25));
        assertEq(token.allowance(address(this), spender), 25);
        assertTrue(token.approve(spender, 0));
        assertEq(token.allowance(address(this), spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), recipient, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_ApproveRejectsZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_TransferFromConsumesAllowanceAndEmitsTransfer() public {
        assertTrue(token.approve(spender, 100));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), recipient, 40);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 40));
        assertEq(token.balanceOf(address(this)), SUPPLY - 40);
        assertEq(token.balanceOf(recipient), 40);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(address(this), spender), 60);
        assertEq(token.totalSupply(), SUPPLY);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 60));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(recipient), 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), recipient, 1);
    }

    function test_InfiniteAllowanceIsNotDecreased() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, SUPPLY));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromRejectsInsufficientAllowanceAtomically() public {
        assertTrue(token.approve(spender, 10));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 10, 11));
        vm.prank(spender);
        token.transferFrom(address(this), recipient, 11);
        assertEq(token.allowance(address(this), spender), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_TransferFromRejectsUnapprovedSpender() public {
        assertTrue(token.approve(spender, 100));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, outsider, 0, 1));
        vm.prank(outsider);
        token.transferFrom(address(this), recipient, 1);
        assertEq(token.allowance(address(this), spender), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_TransferFromBalanceFailureRestoresAllowance() public {
        assertTrue(token.transfer(holder, 10));
        vm.prank(holder);
        assertTrue(token.approve(spender, 11));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 10, 11));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 11);
        assertEq(token.allowance(holder, spender), 11);
        assertEq(token.balanceOf(holder), 10);
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_TransferFromZeroRecipientRestoresAllowance() public {
        assertTrue(token.approve(spender, 10));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 10);
        assertEq(token.allowance(address(this), spender), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function test_ZeroTransferFromNeedsNoAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(holder, recipient, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 0));
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_ZeroTransferFromStillRejectsZeroAddresses() public {
        // Even a zero-value spend validates the allowance owner before attempting the transfer.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), recipient, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(holder, address(0), 0);
    }

    function test_SelfTransferFromConsumesAllowanceWithoutChangingBalance() public {
        assertTrue(token.approve(spender, 100));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 100));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_DeployerCannotSpendAnotherHoldersTokensWithoutApproval() public {
        assertTrue(token.transfer(holder, 100));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(holder, address(this), 1);
        assertEq(token.balanceOf(holder), 100);
        vm.prank(holder);
        assertTrue(token.transfer(recipient, 100));
        assertEq(token.balanceOf(recipient), 100);
    }

    function test_NoMintBurnOrAdministrativeEntryPoints() public {
        bytes[] memory calls = new bytes[](22);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", outsider, SUPPLY);
        calls[1] = abi.encodeWithSignature("mint(uint256)", SUPPLY);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("issue(uint256)", SUPPLY);
        calls[4] = abi.encodeWithSignature("setMinter(address)", outsider);
        calls[5] = abi.encodeWithSignature("initialize(address)", outsider);
        calls[6] = abi.encodeWithSignature("upgradeTo(address)", outsider);
        calls[7] = abi.encodeWithSignature("transferOwnership(address)", outsider);
        calls[8] = abi.encodeWithSignature("setOwner(address)", outsider);
        calls[9] = abi.encodeWithSignature("pause()");
        calls[10] = abi.encodeWithSignature("unpause()");
        calls[11] = abi.encodeWithSignature("blacklist(address)", holder);
        calls[12] = abi.encodeWithSignature("freeze(address)", holder);
        calls[13] = abi.encodeWithSignature("setBlacklist(address,bool)", holder, true);
        calls[14] = abi.encodeWithSignature("setBlocked(address,bool)", holder, true);
        calls[15] = abi.encodeWithSignature("lock(address)", holder);
        calls[16] = abi.encodeWithSignature("disableTransfers()");
        calls[17] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        calls[18] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[19] = abi.encodeWithSignature("burnFrom(address,uint256)", holder, 1);
        calls[20] = abi.encodeWithSignature("seize(address)", holder);
        calls[21] = abi.encodeWithSignature("_mint(address,uint256)", outsider, SUPPLY);

        assertTrue(token.transfer(holder, 100));
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded, "deployer reached an unexpected entry point");
            vm.prank(outsider);
            (bool outsiderSucceeded,) = address(token).call(calls[i]);
            assertFalse(outsiderSucceeded, "outsider reached an unexpected entry point");
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(holder), 100);
            assertEq(token.balanceOf(outsider), 0);
        }
        vm.prank(holder);
        assertTrue(token.transfer(recipient, 100));
        assertEq(token.balanceOf(recipient), 100);
    }

    function test_RejectsNativeEtherAndUnknownCalls() public {
        vm.deal(address(this), 1 ether);
        (bool acceptedEther,) = address(token).call{value: 1 ether}("");
        assertFalse(acceptedEther);
        (bool acceptedUnknown,) = address(token).call(hex"ffffffff");
        assertFalse(acceptedUnknown);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != address(this));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedTransferAccounting(uint256 approval, uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        approval = bound(approval, amount, type(uint256).max);
        assertTrue(token.approve(spender, approval));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, amount));
        assertEq(token.allowance(address(this), spender), approval == type(uint256).max ? approval : approval - amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_OverdrawnTransferReverts(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(recipient, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InsufficientAllowanceReverts(uint256 approval, uint256 amount) public {
        approval = bound(approval, 0, SUPPLY - 1);
        amount = bound(amount, approval + 1, SUPPLY);
        assertTrue(token.approve(spender, approval));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approval, amount)
        );
        vm.prank(spender);
        token.transferFrom(address(this), recipient, amount);
        assertEq(token.allowance(address(this), spender), approval);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
    }
}
