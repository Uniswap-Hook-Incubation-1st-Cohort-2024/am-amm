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

    function test_bid() external {
        vm.prank(user0);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 1e18, K * 1e18, 0);

        assertEq(amAmm.getManager(POOL_0, 0).deposit, K * 1e18, "Bid Promoted to Top Bid");

        vm.prank(user1);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 10e18, K * 10e18, 0);

        assertEq(amAmm.getManager(POOL_0, 0).bidder, address(user1));

        vm.prank(user2);
        vm.expectRevert();
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 1e18, K * 1e18, 0);
    }

    function test_bid_refund() external {
        vm.prank(user0);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 1e18, K * 1e18, 0);
        vm.prank(user0);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 1e18, K * 1e18, 1);

        assertEq(amAmm.getManager(POOL_0, 0).deposit, K * 1e18, "Bid Promoted to Top Bid");

        vm.prank(user1);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 10e18, K * 10e18, 1);

        assertEq(amAmm.getManager(POOL_0, 1).bidder, address(user1));

        console.log(amAmm._getEpoch(POOL_0, block.timestamp), block.timestamp);
        skip(10800); //Enter Epoch 3

        console.log(amAmm._getEpoch(POOL_0, block.timestamp), block.timestamp);

        assertEq(amAmm._getEpoch(POOL_0, block.timestamp), 3, "Entered Epoch 3");

        vm.prank(user0);
        amAmm.claimRefund(POOL_0, 1);

        vm.prank(user1);
        vm.expectRevert();
        amAmm.claimRefund(POOL_0, 1);
    }

    function test_bid_withdraw() external {
        vm.prank(user0);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 1e18, K * 1e18, 0);
        vm.prank(user0);
        amAmm.bid(POOL_0, _swapFeeToPayload(0.01e6), 1e18, K * 2e18, 1);

        vm.prank(user0);
        amAmm.withdrawFromBid(POOL_0, 1, 1e18);

        assertEq(amAmm.getManager(POOL_0, 1).deposit, (K * 2e18) - 1e18);
    }

    function _getEpoch(uint256 timestamp) internal pure returns (uint40) {
        return uint40(timestamp / EPOCH_SIZE);
    }
}
