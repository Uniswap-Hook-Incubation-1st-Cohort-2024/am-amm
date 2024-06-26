// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import {PoolId} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";

interface IAmAmm {
    error AmAmm__BidLocked();
    error AmAmm__InvalidBid();
    error AmAmm__BidOutOfBounds();
    error AmAmm__NotEnabled();
    error AmAmm__Unauthorized();
    error AmAmm__InvalidDepositAmount();

    event SubmitBid(
        PoolId indexed id, address indexed manager, uint40 indexed epoch, bytes7 payload, uint128 rent, uint128 deposit
    );
    event DepositIntoTopBid(PoolId indexed id, address indexed manager, uint128 amount);
    event WithdrawFromTopBid(PoolId indexed id, address indexed manager, address indexed recipient, uint128 amount);
    event DepositIntoNextBid(PoolId indexed id, address indexed manager, uint128 amount);
    event WithdrawFromNextBid(PoolId indexed id, address indexed manager, address indexed recipient, uint128 amount);
    event CancelNextBid(PoolId indexed id, address indexed manager, address indexed recipient, uint256 refund);
    event SetBidPayload(PoolId indexed id, address indexed manager, bytes7 payload, bool topBid);

    struct Bid {
        address bidder;
        bytes7 payload; // payload specifying what parames the manager wants, e.g. swap fee
        uint128 rent; // rent per hour
    }

    /// @notice Places a bid to become the manager of a pool
    /// @param id The pool id
    /// @param payload The payload specifying what parameters the manager wants, e.g. swap fee
    /// @param rent The rent per epoch
    function bid(PoolId id, bytes7 payload, uint128 rent, uint40 _epoch) external;

    /// @notice Withdraws from the deposit of the top bid. Only callable by topBids[id].manager. Reverts if D_top / R_top < K.
    /// @param id The pool id
    /// @param _amount The amount to withdraw, must be a multiple of rent and leave D_top / R_top >= K
    function withdrawBalance(PoolId id, uint128 _amount) external returns (uint128);

    /// @notice Return bid from the last manager
    /// @param id The pool id
    /// @param targetEpoch The epoch to target
    function getLastManager(PoolId id, uint40 targetEpoch) external returns (Bid memory);

    /// @notice Return current epoch.
    /// @param id The pool id
    /// @param timestamp The current timestamp
    function _getEpoch(PoolId id, uint256 timestamp) external returns (uint40);
}
