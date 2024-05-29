// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";

import {BaseHook} from "./forks/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IAmAmm} from "./interfaces/IAmAmm.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {LibMulticaller} from "../lib/multicaller/src/LibMulticaller.sol";
import {SafeCastLib} from "../lib/solady/src/utils/SafeCastLib.sol";
import {FixedPointMathLib} from "../lib/solady/src/utils/FixedPointMathLib.sol";

contract AMAMM is IAmAmm {
    constructor() public {}

    /// -----------------------------------------------------------------------
    /// UNIV4 HOOK usage
    /// -----------------------------------------------------------------------

    // function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
    //     return Hooks.Permissions({
    //         beforeInitialize: false,
    //         afterInitialize: false,
    //         beforeAddLiquidity: true, // Don't allow adding liquidity normally
    //         afterAddLiquidity: false,
    //         beforeRemoveLiquidity: false,
    //         afterRemoveLiquidity: false,
    //         beforeSwap: false,
    //         afterSwap: true, // Override how swaps are done
    //         beforeDonate: false,
    //         afterDonate: false,
    //         beforeSwapReturnDelta: false,
    //         afterSwapReturnDelta: true, // Allow afterSwap to return a custom delta
    //         afterAddLiquidityReturnDelta: false,
    //         afterRemoveLiquidityReturnDelta: false
    //     });
    // }

    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------

    using SafeCastLib for *;
    using FixedPointMathLib for *;

    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------

    function K(PoolId) internal view virtual returns (uint40) {
        return 24;
    }

    function EPOCH_SIZE(PoolId) internal view virtual returns (uint256) {
        return 1 hours;
    }

    function MIN_BID_MULTIPLIER(PoolId) internal view virtual returns (uint256) {
        return 1.1e18;
    }

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    mapping(PoolId id => uint40) internal _lastUpdatedEpoch;
    mapping(Currency currency => uint256) internal _totalFees;
    mapping(PoolId id => mapping(uint40 => Bid)) public poolEpochManager;
    mapping(address manager => mapping(PoolId id => uint256)) internal _refunds;
    mapping(address manager => mapping(Currency currency => uint256)) internal _fees;
    mapping(PoolId id => mapping(uint40 => mapping(address => Bid))) public poolEpochBids;

    /// -----------------------------------------------------------------------
    /// Getter actions
    /// -----------------------------------------------------------------------

    function getManager(PoolId id, uint40 epoch) public view returns (Bid memory) {
        return poolEpochManager[id][epoch];
    }

    function getBid(PoolId id, uint40 epoch, address bidder) public view returns (Bid memory) {
        return poolEpochBids[id][epoch][bidder];
    }
    /// -----------------------------------------------------------------------
    /// Bidder actions
    /// -----------------------------------------------------------------------

    /// @inheritdoc IAmAmm
    function bid(PoolId id, address bidder, bytes7 payload, uint128 rent, uint128 deposit, uint40 _epoch)
        external
        virtual
        override
    {
        /// -----------------------------------------------------------------------
        /// Validation
        /// -----------------------------------------------------------------------

        address msgSender = LibMulticaller.senderOrSigner();

        // ensure bid is valid
        // - manager can't be zero address
        // - bid needs to be greater than the next bid by >10%
        // - deposit needs to cover the rent for K hours
        // - deposit needs to be a multiple of rent
        // - payload needs to be valid
        if (
            bidder == address(0) || rent <= poolEpochManager[id][_epoch].rent.mulWad(MIN_BID_MULTIPLIER(id))
                || deposit < rent * K(id) || deposit % rent != 0 || !_payloadIsValid(id, payload)
        ) {
            revert AmAmm__InvalidBid();
        }

        // Check if the bid already exists
        Bid memory existingBid = poolEpochBids[id][_epoch][bidder];
        Bid memory newBid = Bid({bidder: msgSender, payload: payload, rent: rent, deposit: deposit});

        if (existingBid.bidder != address(0)) {
            // If the bid exists, update the deposit
            existingBid.deposit += deposit;
        } else {
            // If the bid does not exist, create a new one
            poolEpochBids[id][_epoch][bidder] = newBid;
        }

        //Update poolEpochManager if deposit is largest
        if (poolEpochManager[id][_epoch].deposit < deposit) {
            poolEpochManager[id][_epoch] = newBid;
        }

        _updateEpochBids();
    }

    /// @inheritdoc IAmAmm
    function cancelBid(PoolId id, uint40 _epoch) external virtual override {
        /// -----------------------------------------------------------------------
        /// Validation
        /// -----------------------------------------------------------------------

        address msgSender = LibMulticaller.senderOrSigner();

        if (
            !_amAmmEnabled(id) || poolEpochBids[id][_epoch][msgSender].deposit == 0
                || _epoch <= _getEpoch(id, block.timestamp)
        ) {
            revert AmAmm__InvalidBid();
        }

        /// -----------------------------------------------------------------------
        /// State updates
        /// -----------------------------------------------------------------------

        delete poolEpochBids[id][_epoch][msgSender];

        Bid memory topBid = getHighestDepositBid(id, _epoch);
        poolEpochManager[id][_epoch] = topBid;

        _updateEpochBids();
    }

    /// @inheritdoc IAmAmm
    function withdrawBid(PoolId id, uint40 _epoch, uint128 _amount) external virtual override {
        /// -----------------------------------------------------------------------
        /// Validation
        /// -----------------------------------------------------------------------

        address msgSender = LibMulticaller.senderOrSigner();

        if (
            !_amAmmEnabled(id) || poolEpochBids[id][_epoch][msgSender].deposit == 0
                || _epoch <= _getEpoch(id, block.timestamp)
        ) {
            revert AmAmm__InvalidBid();
        }

        // ensure amount is a multiple of rent
        if (_amount % poolEpochBids[id][_epoch][msgSender].rent != 0) {
            revert AmAmm__InvalidDepositAmount();
        }

        // require D_top / R_top >= K
        if (
            (poolEpochBids[id][_epoch][msgSender].deposit - _amount) / poolEpochBids[id][_epoch][msgSender].rent < K(id)
        ) {
            revert AmAmm__BidLocked();
        }

        /// -----------------------------------------------------------------------
        /// State updates
        /// -----------------------------------------------------------------------

        poolEpochBids[id][_epoch][msgSender].deposit -= _amount;

        if (poolEpochManager[id][_epoch].bidder == msgSender) {
            Bid memory topBid = getHighestDepositBid(id, _epoch);
            poolEpochManager[id][_epoch] = topBid;
        }

        _updateEpochBids();
    }

    /// -----------------------------------------------------------------------
    /// Internal helpers
    /// -----------------------------------------------------------------------

    /// @dev Charges rent
    function _updateEpochBids() internal virtual {
        //TODO
    }

    /// @inheritdoc IAmAmm
    function claimRefund(PoolId id, address recipient) external returns (uint256 refund) {
        //TODO
    }

    /// @inheritdoc IAmAmm
    function claimFees(Currency currency, address recipient) external returns (uint256 fees) {
        //TODO
    }

    /// @dev Validates a bid payload, e.g. ensure the swap fee is below a certain threshold
    function _payloadIsValid(PoolId id, bytes7 payload) internal view virtual returns (bool) {
        //TODO
        return true;
    }

    /// @dev Returns whether the am-AMM is enabled for a given pool
    function _amAmmEnabled(PoolId id) internal view virtual returns (bool) {
        //TODO
        return true;
    }

    /// @notice Returns the highest deposit bid for a given pool and epoch.
    /// @param id The identifier for the pool.
    /// @param _epoch The epoch for which to find the highest bid.
    /// @return highestBid The bid with the highest deposit.
    function getHighestDepositBid(PoolId id, uint40 _epoch) public view returns (Bid memory highestBid) {
        // highestBid = Bid({bidder: address(0), payload: 0, rent: 0, deposit: 0});

        // // Iterate through all bids for the given pool and epoch
        // for (uint256 i = 0; i < poolEpochBids[id][_epoch].length; i++) {
        //     Bid memory currentBid = poolEpochBids[id][_epoch][i];
        //     if (currentBid.deposit > highestBid.deposit) {
        //         highestBid = currentBid;
        //     }
        // }

        // return highestBid;
        //TODO FIX
    }

    /// @notice returns current epoch.
    /// @param id pool id
    /// @param timestamp current timestamp
    function _getEpoch(PoolId id, uint256 timestamp) internal view returns (uint40) {
        return uint40(timestamp / EPOCH_SIZE(id));
    }
}
