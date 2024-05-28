// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import "./mocks/AmAmmMock.sol";
import "./mocks/ERC20Mock.sol";
import {AMAMM} from "../../src/AmAmm.sol";

contract AmAmmTest is Test {
    PoolId constant POOL_0 = PoolId.wrap(bytes32(0));

    uint128 internal constant K = 24; // 24 windows (hours)
    uint256 internal constant EPOCH_SIZE = 1 hours;
    uint256 internal constant MIN_BID_MULTIPLIER = 1.1e18; // 10%

    AmAmmMock amAmm;

    function setUp() external {
        // amAmm = new AmAmmMock(new ERC20Mock(), new ERC20Mock(), new ERC20Mock());
        // amAmm.bidToken().approve(address(amAmm), type(uint256).max);
        // amAmm.setEnabled(POOL_0, true);
        // amAmm.setMaxSwapFee(POOL_0, 0.1e6);
    }

    function _swapFeeToPayload(uint24 swapFee) internal pure returns (bytes7) {
        return bytes7(bytes3(swapFee));
    }

    function test_stateTransition_AC() external {
        // mint bid tokens
        // amAmm.bidToken().mint(address(this), K * 1e18);

        // // make bid
        // amAmm.bid({
        //     id: POOL_0,
        //     manager: address(this),
        //     payload: _swapFeeToPayload(0.01e6),
        //     rent: 1e18,
        //     deposit: K * 1e18
        // });

        // // verify state
        // IAmAmm.Bid memory bid = amAmm.getNextBid(POOL_0);
        // assertEq(amAmm.bidToken().balanceOf(address(this)), 0, "didn't take bid tokens");
        // assertEq(amAmm.bidToken().balanceOf(address(amAmm)), K * 1e18, "didn't give bid tokens");
        // assertEq(bid.manager, address(this), "manager incorrect");
        // assertEq(bid.payload, _swapFeeToPayload(0.01e6), "swapFee incorrect");
        // assertEq(bid.rent, 1e18, "rent incorrect");
        // assertEq(bid.deposit, K * 1e18, "deposit incorrect");
        // assertEq(bid.epoch, _getEpoch(vm.getBlockTimestamp()), "epoch incorrect");
    }

    function _getEpoch(uint256 timestamp) internal pure returns (uint40) {
        return uint40(timestamp / EPOCH_SIZE);
    }
}
