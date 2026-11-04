// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Conditionals} from "../src/Conditionals.sol";

/// @dev Local fixture only; it is not a production deployment contract.
contract TokenFactoryFixture {
    function deploy(bytes32 salt) external returns (Conditionals) {
        return new Conditionals{salt: salt}();
    }

    function move(Conditionals token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract LaunchFlowTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    TokenFactoryFixture private factory;
    Conditionals private token;
    address private launcher;
    address private distributor;
    address private poolManager;
    address private remainderRecipient;
    address private claimant;
    address private trader;

    function setUp() public {
        factory = new TokenFactoryFixture();
        launcher = makeAddr("launcher");
        distributor = makeAddr("distributor");
        poolManager = makeAddr("pool manager");
        remainderRecipient = makeAddr("remainder recipient");
        claimant = makeAddr("claimant");
        trader = makeAddr("trader");
        vm.prank(launcher, launcher);
        token = factory.deploy(bytes32(uint256(1)));
    }

    function test_Create2MintsWholeSupplyToImmediateFactory() public view {
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(factory),
                            bytes32(uint256(1)),
                            keccak256(type(Conditionals).creationCode)
                        )
                    )
                )
            )
        );
        assertEq(address(token), predicted);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(launcher), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertGt(address(token).code.length, 0);
        assertLe(address(token).code.length, 24_576);
    }

    function test_DuplicateCreate2DeploymentRevertsWithoutChangingSupply() public {
        vm.expectRevert();
        factory.deploy(bytes32(uint256(1)));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
    }

    /// @dev Tests the token side of settlement, not Uniswap liquidity math or swap execution.
    function test_DistributionClaimsAndTradingTransfersArriveWhole() public {
        uint256 swarmShare = SUPPLY / 10;
        uint256 poolShare = SUPPLY * 8 / 10;
        uint256 remainder = SUPPLY - swarmShare - poolShare;
        assertTrue(factory.move(token, distributor, swarmShare));
        assertTrue(factory.move(token, poolManager, poolShare));
        assertTrue(factory.move(token, remainderRecipient, remainder));
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), swarmShare);
        assertEq(token.balanceOf(poolManager), poolShare);
        assertEq(token.balanceOf(remainderRecipient), remainder);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, swarmShare));
        assertEq(token.balanceOf(claimant), swarmShare);
        assertEq(token.balanceOf(distributor), 0);

        uint256 bought = 100 ether;
        vm.prank(poolManager);
        assertTrue(token.transfer(trader, bought));
        assertEq(token.balanceOf(trader), bought);
        assertEq(token.balanceOf(poolManager), poolShare - bought);
        vm.prank(trader);
        assertTrue(token.transfer(poolManager, bought));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(poolManager), poolShare);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RuntimeHasNoForbiddenReachableOpcodes() public view {
        bytes memory runtime = address(token).code;
        bool reachable = true;
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode == 0x5b) reachable = true;
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            if (reachable) {
                assertTrue(opcode != 0xf4, "DELEGATECALL");
                assertTrue(opcode != 0xf2, "CALLCODE");
                assertTrue(opcode != 0xff, "SELFDESTRUCT");
            }
            if (
                opcode == 0x00 || opcode == 0x56 || opcode == 0xf3 || opcode == 0xfd || opcode == 0xfe || opcode == 0xff
            ) {
                reachable = false;
            }
        }
    }
}
