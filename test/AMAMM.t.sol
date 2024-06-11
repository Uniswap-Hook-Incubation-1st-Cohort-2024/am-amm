// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";

import "./mocks/ERC20Mock.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";
import {AMAMM} from "../src/AMAMM.sol";
import {AmAmmMock} from "./mocks/AmAmmMock.sol";

contract AmAmmTest is Test {
    PoolId constant POOL_0 = PoolId.wrap(bytes32(0));

    address user0 = makeAddr("USER_0");
    address user1 = makeAddr("USER_1");
    address user2 = makeAddr("USER_2");

    uint128 internal constant K = 24; // 24 windows (hours)
    uint256 internal constant EPOCH_SIZE = 1 hours;
    uint256 internal constant MIN_BID_MULTIPLIER = 1.1e18; // 10%
    AmAmmMock amAmm;

    function setUp() public {
        amAmm = new AmAmmMock(address(new ERC20Mock()));
        amAmm.bidToken().approve(address(amAmm), type(uint256).max);
        amAmm.setEnabled(POOL_0, true);

        amAmm.setMaxSwapFee(POOL_0, 0.1e6);
    }

    function _swapFeeToPayload(uint24 swapFee) internal pure returns (bytes7) {
        return bytes7(bytes3(swapFee));
    }

    //Test get_epoch
    function test_get_epoch() external {
        assertEq(
            amAmm._getEpoch(POOL_0, block.timestamp),
            uint40(block.timestamp / amAmm.EPOCH_SIZE(POOL_0)),
            "Get Epoch returns Correct Epoch"
        );
    }

    //Test to check if you can bid on current epoch
    function test_bid_current_epoch() external {
        vm.prank(user0);
        vm.expectRevert();
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 1e18, 0);
    }

    //Test to check if lower bid can be promoted
    function test_bid() external {
        amAmm.bidToken().mint(address(user0), K * 100e18);
        amAmm.bidToken().mint(address(user1), K * 100e18);
        amAmm.bidToken().mint(address(user2), K * 100e18);

        vm.startPrank(user0);
        amAmm.bidToken().approve(address(amAmm), K * 100e18);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 1e18, 1);
        vm.stopPrank();

        assertEq(amAmm._getDeposit(POOL_0, 1), K * 1e18, "Bid Promoted to Top Bid");

        vm.startPrank(user1);
        amAmm.bidToken().approve(address(amAmm), type(uint256).max);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 10e18, 1);
        vm.stopPrank();

        assertEq(amAmm.getLastManager(POOL_0, 1).bidder, address(user1));

        vm.startPrank(user2);
        amAmm.bidToken().approve(address(amAmm), type(uint256).max);
        vm.expectRevert();
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 1e18, 1);
        vm.stopPrank();
    }

    //Test for Future Bid
    function test_futureBid() external {
        amAmm.bidToken().mint(address(user0), K * 100e18);

        vm.startPrank(user0);
        amAmm.bidToken().approve(address(amAmm), K * 1e18);
        vm.expectRevert();
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 1e18, 25);
        vm.stopPrank();
    }

    //Test to check if lower bid can be promoted
    function test_withdrawFutureBid() external {
        amAmm.bidToken().mint(address(user0), K * 100e18);
        amAmm.bidToken().mint(address(user1), K * 100e18);
        amAmm.bidToken().mint(address(user2), K * 100e18);

        vm.startPrank(user0);
        amAmm.bidToken().approve(address(amAmm), K * 1e18);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 1e18, 1);
        vm.stopPrank();

        assertEq(amAmm._getDeposit(POOL_0, 1), K * 1e18, "Bid Promoted to Top Bid");

        vm.startPrank(user1);
        amAmm.bidToken().approve(address(amAmm), 2e18 * K);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 2e18, 10); // Future Bid
        vm.stopPrank();

        assertEq(amAmm.getLastManager(POOL_0, 10).bidder, address(user1)); //Confirm they are manager of future bid

        vm.startPrank(user1);
        vm.expectRevert();
        amAmm.withdrawBalance(POOL_0, K * 10e18);
        vm.stopPrank();
    }

    // Test if lower bids can be refunded
    function test_bid_full_refund() external {
        amAmm.bidToken().mint(address(user0), K * 100e18);
        amAmm.bidToken().mint(address(user1), K * 100e18);

        vm.startPrank(user0);
        amAmm.bidToken().approve(address(amAmm), 1e18 * K);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 1e18, 1);
        vm.stopPrank();

        vm.startPrank(user1);
        amAmm.bidToken().approve(address(amAmm), 10e18 * K);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 10e18, 1); // New Bid Winner
        vm.stopPrank();

        assertEq(amAmm._getDeposit(POOL_0, 1), K * 10e18, "Bid Promoted to Top Bid");

        skip(10800); //Enter Epoch 3

        assertEq(amAmm._userBalance(user0), 1e18 * K, "Ensure User bid is still available to withdraw");

        vm.prank(user0); // user0 should have 1e18 * k balance and should be able to withdraw
        amAmm.withdrawBalance(POOL_0, 1e18 * K);

        assertEq(amAmm._userBalance(user0), 0, "Zero Balance after withdrawing");
    }

    // Test if lower bids can be refunded
    function test_bid_multiple_full_refunds() external {
        amAmm.bidToken().mint(address(user0), K * 100e18);
        amAmm.bidToken().mint(address(user1), K * 100e18);
        amAmm.bidToken().mint(address(user2), K * 100e18);

        vm.startPrank(user0);
        amAmm.bidToken().approve(address(amAmm), 9e18 * K);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 9e18, 1);
        vm.stopPrank();

        vm.startPrank(user1);
        amAmm.bidToken().approve(address(amAmm), 10e18 * K);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 10e18, 1); // New Bid Winner
        vm.stopPrank();

        vm.startPrank(user2);
        amAmm.bidToken().approve(address(amAmm), 12e18 * K);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 12e18, 1); // New Bid Winner
        vm.stopPrank();

        vm.startPrank(user0);
        amAmm.bidToken().approve(address(amAmm), 15e18 * K);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 15e18, 1); // New Bid Winner
        vm.stopPrank();

        assertEq(amAmm._getDeposit(POOL_0, 1), K * 15e18, "Bid Promoted to Top Bid");

        skip(10800); //Enter Epoch 3

        assertEq(amAmm._userBalance(user0), 0, "Ensure User bid is not available to withdraw");
    }

    // Test if userFunds can be resued without pulling
    function test_bid_reuse_userBalance() external {
        amAmm.bidToken().mint(address(user0), K * 100e18);
        amAmm.bidToken().mint(address(user1), K * 100e18);

        vm.startPrank(user0);
        amAmm.bidToken().approve(address(amAmm), 1e18 * K);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 1e18, 1);
        vm.stopPrank();

        vm.startPrank(user1);
        amAmm.bidToken().approve(address(amAmm), 10e18 * K);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 10e18, 1); // New Bid Winner
        vm.stopPrank();

        skip(92000); //Enter Epoch 25

        assertEq(amAmm._getEpoch(POOL_0, block.timestamp), 25, "Enter Epoch 25");

        assertEq(amAmm._userBalance(user0), 1e18 * K, "User should be refunded because they lost bid");

        vm.startPrank(user0);
        amAmm.bidToken().approve(address(amAmm), 1e18 * K);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 1e18, 26); // Bid with reused balance
        vm.stopPrank();

        assertEq(amAmm.getLastManager(POOL_0, 26).bidder, user0, "Ensure user0 is winning bidder with reused balance");
    }

    // Test if lower bids can be refunded
    function test_bid_partial_refund() external {
        amAmm.bidToken().mint(address(user0), K * 100e18);
        amAmm.bidToken().mint(address(user1), K * 100e18);

        vm.startPrank(user0);
        amAmm.bidToken().approve(address(amAmm), 1e18 * K);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 1e18, 1);
        vm.stopPrank();

        vm.startPrank(user1);
        amAmm.bidToken().approve(address(amAmm), 10e18 * K);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 10e18, 12); // New Bid Winner midway between user0's bid so need to refund half
        vm.stopPrank();

        assertEq(amAmm._getDeposit(POOL_0, 12), K * 10e18, "Bid Promoted to Top Bid");

        skip(43200); //Enter Epoch 3

        uint256 remainingAmount = (1e18 * K) - (1e18 * 11);
        assertEq(amAmm._userBalance(user0), remainingAmount, "Ensure User bid is still available to withdraw");

        vm.prank(user0); // user0 should have (1e18 * K) - (1e18 * 11) balance and should be able to withdraw
        amAmm.withdrawBalance(POOL_0, uint128(remainingAmount));

        assertEq(amAmm._userBalance(user0), 0, "Zero Balance after withdrawing");
    }

    // Test case where lastUpdatedEpochManager is > than the target Epoch (this bid should not fill)
    function test_failed_bid_with_withdraw() external {
        amAmm.bidToken().mint(address(user0), K * 100e18);
        amAmm.bidToken().mint(address(user1), K * 100e18);

        vm.startPrank(user0);
        amAmm.bidToken().approve(address(amAmm), 1e18 * K);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 1e18, 1);
        vm.stopPrank();

        skip(92000); //Enter Epoch 25

        assertEq(amAmm._getEpoch(POOL_0, block.timestamp), 25, "Enter Epoch 25");

        vm.startPrank(user1);
        amAmm.bidToken().approve(address(amAmm), 10e18 * K);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 10e18, 30);
        vm.stopPrank();

        assertEq(amAmm._userBalance(user0), 0, "Zero Balance after bidding first time");

        vm.startPrank(user0);
        amAmm.bidToken().approve(address(amAmm), 3e18 * K);
        vm.expectRevert();
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 3e18, 29); // New Bid should not be filled
        vm.stopPrank();

        assertEq(amAmm._getDeposit(POOL_0, 29), 0, "Should be no bid on epoch 29");
        assertEq(amAmm._userBalance(user0), 0, "0 Balance after submitting failed bid");
    }

    // Test withdraw
    function test_bid_withdraw() external {
        amAmm.bidToken().mint(address(user0), K * 100e18);
        amAmm.bidToken().mint(address(user1), K * 100e18);

        vm.startPrank(user0);
        amAmm.bidToken().approve(address(amAmm), 1e18 * K);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 1e18, 1);

        vm.stopPrank();

        vm.startPrank(user0);
        amAmm.bidToken().approve(address(amAmm), 2e18 * K);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 2e18, 1);
        vm.stopPrank();

        vm.prank(user0);
        amAmm.withdrawBalance(POOL_0, K * 1e18);

        assertEq(amAmm._userBalance(user0), 0, "Zero Balance after withdrawing");
    }

    function _getEpoch(uint256 timestamp) internal pure returns (uint40) {
        return uint40(timestamp / EPOCH_SIZE);
    }
}
