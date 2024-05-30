// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import {BaseHook} from "v4-periphery/BaseHook.sol";
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
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

contract AMAMM is IAmAmm {
    constructor() public {}

    // TODO: set this value to the ePoch swap fee
    uint128 public constant SWAP_FEE_BIPS = 123; // 123/10000 = 1.23%
    uint128 public constant TOTAL_BIPS = 10000;

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
    mapping(address deposits => uint256) public _userDeposits;
    mapping(address refunds => uint256) public _userRefunds;

    /// -----------------------------------------------------------------------
    /// Getter actions
    /// -----------------------------------------------------------------------

    function getManager(PoolId id, uint40 epoch) public view returns (Bid memory) {
        return poolEpochManager[id][epoch];
    }

    /// -----------------------------------------------------------------------
    /// Bidder actions
    /// -----------------------------------------------------------------------
    /// @inheritdoc IAmAmm
    function bid(PoolId id, bytes7 payload, uint128 rent, uint128 deposit, uint40 _epoch) external virtual override {
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
            rent <= poolEpochManager[id][_epoch].rent.mulWad(MIN_BID_MULTIPLIER(id)) || deposit < rent * K(id)
                || deposit % rent != 0 || !_payloadIsValid(id, payload)
        ) {
            revert AmAmm__InvalidBid();
        }

        if (_getDeposit(id, _epoch) < deposit) {
            _userRefunds[poolEpochManager[id][_epoch].bidder] += _getDeposit(id, _epoch);
            poolEpochManager[id][_epoch] = Bid({bidder: msgSender, payload: payload, rent: rent});
            _userDeposits[msgSender] += deposit;
        }

        _updateEpochBids();
    }

    /// @inheritdoc IAmAmm
    function withdrawFromBid(PoolId id, uint40 _epoch, uint128 _amount) external virtual override {
        /// -----------------------------------------------------------------------
        /// Validation
        /// -----------------------------------------------------------------------

        address msgSender = LibMulticaller.senderOrSigner();

        if (
            !_amAmmEnabled(id) || poolEpochManager[id][_epoch].bidder != msgSender
                || _epoch <= _getEpoch(id, block.timestamp)
        ) {
            revert AmAmm__InvalidBid();
        }

        // ensure amount is a multiple of rent
        if (_amount % poolEpochManager[id][_epoch].rent != 0) {
            revert AmAmm__InvalidDepositAmount();
        }

        // require D_top / R_top >= K
        if ((_getDeposit(id, _epoch) - _amount) / poolEpochManager[id][_epoch].rent < K(id)) {
            revert AmAmm__BidLocked();
        }

        /// -----------------------------------------------------------------------
        /// State updates
        /// -----------------------------------------------------------------------
        poolEpochManager[id][_epoch].rent = uint128((_getDeposit(id, _epoch) - _amount) / K(id));
        _userDeposits[msgSender] -= _amount;

        _updateEpochBids();
    }

    /// @inheritdoc IAmAmm
    function claimRefund(PoolId id, uint40 _epoch) external virtual override returns (uint256 refund) {
        /// -----------------------------------------------------------------------
        /// Validation
        /// -----------------------------------------------------------------------

        address msgSender = LibMulticaller.senderOrSigner();

        if (!_amAmmEnabled(id) || _userRefunds[msgSender] == 0 || _epoch >= _getEpoch(id, block.timestamp)) {
            revert AmAmm__InvalidBid();
        }

        /// -----------------------------------------------------------------------
        /// State updates
        /// -----------------------------------------------------------------------

        uint256 refundAmount = _userRefunds[msgSender];
        _userDeposits[msgSender] -= refundAmount;
        _userRefunds[msgSender] = 0;

        _updateEpochBids();
        return refundAmount;
    }

    /// -----------------------------------------------------------------------
    /// Internal helpers
    /// -----------------------------------------------------------------------

    /// @dev Charges rent
    function _updateEpochBids() internal virtual {
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

    /// @notice returns current epoch.
    /// @param id pool id
    /// @param timestamp current timestamp
    function _getEpoch(PoolId id, uint256 timestamp) public view returns (uint40) {
        return uint40(timestamp / EPOCH_SIZE(id));
    }

    /// @notice returns current epoch.
    /// @param id pool id
    /// @param _epoch current epoch
    function _getDeposit(PoolId id, uint40 _epoch) public view returns (uint256) {
        return uint256(poolEpochManager[id][_epoch].rent * uint256(K(id)));
    }
}
