// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseHook} from "./forks/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IAmAmm} from "./interfaces/IAmAmm.sol";

contract AMAMM is BaseHook {
    constructor(IPoolManager poolManager) BaseHook(poolManager) {}

    /// -----------------------------------------------------------------------
    /// UNIV4 HOOK usage
    /// -----------------------------------------------------------------------

    function getHookPermissions() public pure override returns (HookPermission[] memory) {
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
    mapping(uint256 => mapping(uint40 => Bid)) public poolEpochManager;
    mapping(address manager => mapping(PoolId id => uint256)) internal _refunds;
    mapping(address manager => mapping(Currency currency => uint256)) internal _fees;
    mapping(uint256 => mapping(uint40 => mapping(address => Bid))) public poolEpochBids;

    /// -----------------------------------------------------------------------
    /// Bidder actions
    /// -----------------------------------------------------------------------

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
    function cancelBid(PoolId id, address recipient, uint40 _epoch)
        external
        virtual
        override
        returns (uint256 refund)
    {
        /// -----------------------------------------------------------------------
        /// Validation
        /// -----------------------------------------------------------------------

        address msgSender = LibMulticaller.senderOrSigner();

        if (!_amAmmEnabled(id)) {
            revert AmAmm__NotEnabled();
        }

        /// -----------------------------------------------------------------------
        /// State updates
        /// -----------------------------------------------------------------------

        delete poolEpochBids[poolId][epoch][bidder];

        Bid topBid = getHighestDepositBid(id, _epoch);
        poolEpochManager[id][_epoch] = newBid;

        _updateEpochBids();
    }

    /// -----------------------------------------------------------------------
    /// Internal helpers
    /// -----------------------------------------------------------------------

    /// @dev Charges rent
    function _updateEpochBids(PoolId id, uint40 _currentEpoch) internal virtual {
        // Find and track the number of epochs passed since last time function was called
        uint40 epochsPassed = 10; //dummy number

        //Charge rent from current Manager
        uint256 rentOwed = epochsPassed * poolEpochManager[id].rent;

        poolEpochManager[id].deposit -= rentOwed.toUint128();
    }

    //This is expensive but will have to be done if we want to allow bidders to remove their bid
    function getHighestDepositBid(PoolId poolId, uint40 epoch) internal view returns (Bid memory) {
        uint128 highestDeposit = 0;
        Bid memory highestBid;

        mapping(address => Bid) bids = poolEpochBids[poolId][epoch];
        for (uint256 i = 0; i < address(this).balance; i++) {
            Bid bid = bids[i];
            if (bid.deposit > highestDeposit) {
                highestDeposit = bid.deposit;
                highestBid = bid;
            }
        }

        return highestBid;
    }
}
