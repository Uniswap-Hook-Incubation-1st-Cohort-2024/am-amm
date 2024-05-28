// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseHook} from "./forks/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IAmAmm} from "./interfaces/IAmAmm.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";

contract AMAMM is BaseHook, IAmAmm {
    constructor(IPoolManager poolManager) BaseHook(poolManager) {}

    /// -----------------------------------------------------------------------
    /// UNIV4 HOOK usage
    /// -----------------------------------------------------------------------

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true, // Override how swaps are done
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true, // Allow beforeSwap to return a custom delta
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------

    // using SafeCastLib for *;
    // using FixedPointMathLib for *;

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
    mapping(uint256 => mapping(uint40 => Bid)) public poolEpochManager;
    mapping(address manager => mapping(PoolId id => uint256)) internal _refunds;
    mapping(address manager => mapping(Currency currency => uint256)) internal _fees;
    mapping(uint256 => mapping(uint40 => mapping(address => Bid))) public poolEpochBids;

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
            bidder == address(0) || rent <= poolEpochManager[poolId][_epoch].mulWad(MIN_BID_MULTIPLIER(id))
                || deposit < rent * K(id) || deposit % rent != 0 || !_payloadIsValid(id, payload)
        ) {
            revert AmAmm__InvalidBid();
        }

        // Check if the bid already exists
        Bid existingBid = poolEpochBids[id][_epoch][bidder];
        Bid newBid = Bid({bidder: msgSender, payload: payload, rent: rent, deposit: deposit});

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
    function cancelBid(PoolId id, address bidder, uint40 _epoch) external virtual override returns (uint256 refund) {
        /// -----------------------------------------------------------------------
        /// Validation
        /// -----------------------------------------------------------------------

        address msgSender = LibMulticaller.senderOrSigner();

        if (
            !_amAmmEnabled(id) || poolEpochBids[id][epoch][bidder].deposit != 0
                || _epoch <= _getEpoch(id, block.timestamp)
        ) {
            revert AmAmm__InvalidBid();
        }

        /// -----------------------------------------------------------------------
        /// State updates
        /// -----------------------------------------------------------------------

        delete poolEpochBids[poolId][epoch][bidder];

        Bid topBid = getHighestDepositBid(id, _epoch);
        poolEpochManager[id][_epoch] = newBid;

        _updateEpochBids();
    }

    /// @inheritdoc IAmAmm
    function withdrawBid(PoolId id, address bidder, uint40 _epoch, uint256 _amount)
        external
        virtual
        override
        returns (uint256 refund)
    {
        /// -----------------------------------------------------------------------
        /// Validation
        /// -----------------------------------------------------------------------

        address msgSender = LibMulticaller.senderOrSigner();

        if (
            !_amAmmEnabled(id) || poolEpochBids[id][epoch][bidder].deposit != 0
                || _epoch <= _getEpoch(id, block.timestamp)
        ) {
            revert AmAmm__InvalidBid();
        }

        // ensure amount is a multiple of rent
        if (amount % topBid.rent != 0) {
            revert AmAmm__InvalidDepositAmount();
        }

        // require D_top / R_top >= K
        if ((topBid.deposit - amount) / topBid.rent < K(id)) {
            revert AmAmm__BidLocked();
        }

        /// -----------------------------------------------------------------------
        /// State updates
        /// -----------------------------------------------------------------------

        Bid newBid = Bid({bidder: msgSender, payload: payload, rent: rent, deposit: deposit});
        Bid existingBid = poolEpochBids[id][_epoch][bidder];

        existingBid.deposit = poolEpochBids[id][_epoch][bidder].deposit - amount;

        if (poolEpochManager[id][_epoch].bidder == bidder) {
            Bid topBid = getHighestDepositBid(id, _epoch);
            poolEpochManager[id][_epoch] = newBid;
        }

        _updateEpochBids();
    }

    /// -----------------------------------------------------------------------
    /// Internal helpers
    /// -----------------------------------------------------------------------

    /// @dev Charges rent
    function _updateEpochBids(PoolId id, uint40 _currentEpoch) internal virtual {
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

    /// @inheritdoc IAmAmm
    //This is expensive but will have to be done if we want to allow bidders to remove their bid
    function getHighestDepositBid(PoolId poolId, uint40 epoch) internal view returns (Bid memory) {
        uint128 highestDeposit = 0;
        Bid memory highestBid;
        bool hasBids = false;

        address[] memory bidders = poolEpochBidders[poolId][epoch];

        for (uint256 i = 0; i < bidders.length; i++) {
            Bid memory _bid = poolEpochBids[poolId][epoch][bidders[i]];
            if (_bid.deposit > highestDeposit) {
                highestDeposit = _bid.deposit;
                highestBid = _bid;
                hasBids = true;
            }
        }
        return highestBid;
    }

    /// @notice returns current epoch.
    /// @param id pool id
    /// @param timestamp current timestamp
    function _getEpoch(PoolId id, uint256 timestamp) internal view returns (uint40) {
        return uint40(timestamp / EPOCH_SIZE(id));
    }
}
