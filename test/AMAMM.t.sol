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

contract AmAmmTest is Test {
    PoolId constant POOL_0 = PoolId.wrap(bytes32(0));

    address user0 = makeAddr("USER_0");
    address user1 = makeAddr("USER_1");
    address user2 = makeAddr("USER_2");

    uint128 internal constant K = 24; // 24 windows (hours)
    uint256 internal constant EPOCH_SIZE = 1 hours;
    uint256 internal constant MIN_BID_MULTIPLIER = 1.1e18; // 10%
    AMAMM amAmm;

    function setUp() public {
        amAmm = new AMAMM();
    }

    function _swapFeeToPayload(uint24 swapFee) internal pure returns (bytes7) {
        return bytes7(bytes3(swapFee));
    }

    //Test to check if lower bid can be promoted
    function test_bid() external {
        vm.prank(user0);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 1e18, K * 1e18, 0);

        assertEq(amAmm._getDeposit(POOL_0, 0), K * 1e18, "Bid Promoted to Top Bid");

        vm.prank(user1);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 10e18, K * 10e18, 0);

        assertEq(amAmm.getManager(POOL_0, 0).bidder, address(user1));

        vm.prank(user2);
        vm.expectRevert();
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 1e18, K * 1e18, 0);
    }

    //Test to check if lower bid can be promoted
    function test_withdrawFutureBid() external {
        vm.prank(user0);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 1e18, K * 1e18, 0);

        assertEq(amAmm._getDeposit(POOL_0, 0), K * 1e18, "Bid Promoted to Top Bid");

        vm.prank(user1);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 10e18, K * 10e18, 10); // Future Bid

        assertEq(amAmm.getManager(POOL_0, 10).bidder, address(user1)); //Confirm they are manager of future bid

        vm.prank(user1);
        vm.expectRevert();
        amAmm.withdrawBalance(POOL_0, K * 10e18);
    }

    // Test if lower bids can be refunded
    function test_bid_refund() external {
        vm.prank(user0);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 1e18, K * 1e18, 1);

        vm.prank(user1);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 10e18, K * 10e18, 1); // New Bid Winner

        assertEq(amAmm._getDeposit(POOL_0, 1), K * 10e18, "Bid Promoted to Top Bid");

        skip(10800); //Enter Epoch 3

        assertEq(amAmm._userBalance(user0), 1e18 * K, "Ensure User bid is still available to withdraw");

        vm.prank(user0); // user0 should have 1e18* k balance and should be able to withdraw
        amAmm.withdrawBalance(POOL_0, 1e18 * K);

        assertEq(amAmm._userBalance(user0), 0, "Zero Balance after withdrawing");
    }

    function test_bid_withdraw() external {
        vm.prank(user0);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 1e18, K * 1e18, 0);
        vm.prank(user0);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 2e18, K * 2e18, 0);

        vm.prank(user0);
        amAmm.withdrawBalance(POOL_0, K * 1e18);

        assertEq(amAmm._userBalance(user0), 0, "Zero Balance after withdrawing");
    }

    function _getEpoch(uint256 timestamp) internal pure returns (uint40) {
        return uint40(timestamp / EPOCH_SIZE);
    }
}
