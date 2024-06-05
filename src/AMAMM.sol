// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import {BaseHook} from "v4-periphery/BaseHook.sol";
import {Test, console} from "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
import "../test/mocks/ERC20Mock.sol";

contract AMAMM is IAmAmm {
    constructor() public {}

    // Modifier to check if the sender is the owner
    modifier isAmAmm(PoolId id) {
        require(_amAmmEnabled(id), "This Pool is not AMAMM enabled");
        _;
    }

    // TODO: set this value to the ePoch swap fee
    uint128 public constant SWAP_FEE_BIPS = 123; // 123/10000 = 1.23%
    uint128 public constant TOTAL_BIPS = 10000;

    ERC20Mock public immutable bidToken;

    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------

    using SafeCastLib for *;
    using FixedPointMathLib for *;

    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------

    function K(PoolId) public view virtual returns (uint40) {
        return 24;
    }

    function EPOCH_SIZE(PoolId) public view virtual returns (uint256) {
        return 1 hours;
    }

    function MIN_BID_MULTIPLIER(PoolId) public view virtual returns (uint256) {
        return 1.1e18;
    }

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    mapping(PoolId id => bool) public enabled;
    mapping(PoolId id => address) internal _bidToken;
    mapping(PoolId id => uint40) internal _lastUpdatedEpoch;
    mapping(address deposits => uint256) public _userBalance;
    mapping(PoolId id => mapping(uint40 => Bid)) public poolEpochManager;

    /// -----------------------------------------------------------------------
    /// Getter actions
    /// -----------------------------------------------------------------------

    function getLastManager(PoolId id, uint40 targetEpoch) public view returns (Bid memory) {
        if (_lastUpdatedEpoch[id] > targetEpoch) {
            if (_lastUpdatedEpoch[id] - targetEpoch <= K(id)) return poolEpochManager[id][_lastUpdatedEpoch[id]];
            else return poolEpochManager[id][targetEpoch];
        } else {
            if (targetEpoch - _lastUpdatedEpoch[id] <= K(id)) {
                return poolEpochManager[id][_lastUpdatedEpoch[id]];
            } else {
                return poolEpochManager[id][targetEpoch];
            }
        }
    }

    /// -----------------------------------------------------------------------
    /// Bidder actions
    /// -----------------------------------------------------------------------
    /// @inheritdoc IAmAmm
    function bid(PoolId id, bytes7 payload, uint128 rent, uint40 _epoch) external virtual override isAmAmm(id) {
        /// -----------------------------------------------------------------------
        /// Validation
        /// -----------------------------------------------------------------------

        address msgSender = LibMulticaller.senderOrSigner();
        if (_epoch > _getEpoch(id, block.timestamp) + K(id)) {
            revert AmAmm__BidOutOfBounds();
        }

        depositToken(id, msgSender, rent);
        Bid memory prevWinner = getLastManager(id, _epoch);

        if (
            _epoch <= _getEpoch(id, block.timestamp) || rent <= prevWinner.rent.mulWad(MIN_BID_MULTIPLIER(id))
                || !_payloadIsValid(id, payload)
        ) {
            revert AmAmm__InvalidBid();
        }

        if (prevWinner.rent != 0) {
            if (prevWinner.rent < rent) {
                //Userp Top Bidder and only allow bidder to own N epochs instead of K epochs (N < K)
                _userBalance[prevWinner.bidder] += _getRefund(id, _lastUpdatedEpoch[id], _epoch); //Refund losing bidder
                poolEpochManager[id][_epoch] = Bid({bidder: msgSender, payload: payload, rent: rent});

                _userBalance[msgSender] -= _getDeposit(id, _epoch);
            }
        } else {
            poolEpochManager[id][_epoch] = Bid({bidder: msgSender, payload: payload, rent: rent});

            _userBalance[msgSender] -= _getDeposit(id, _epoch);
        }
        _updateLastUpdatedEpoch(id, _epoch);
    }

    function depositToken(PoolId id, address depositor, uint128 rent) internal {
        uint128 amount = uint128(rent * K(id));

        if (_userBalance[depositor] >= amount) {
            uint128 remainderAmount = uint128(_userBalance[depositor] - amount);
            _pullBidToken(id, depositor, remainderAmount);
            _userBalance[depositor] += remainderAmount;
        } else {
            _pullBidToken(id, depositor, amount);
            _userBalance[depositor] += amount;
        }
    }

    /// @inheritdoc IAmAmm
    function withdrawBalance(PoolId id, uint128 _amount) external virtual override isAmAmm(id) returns (uint128) {
        address msgSender = LibMulticaller.senderOrSigner();

        if (_userBalance[msgSender] < _amount) {
            revert AmAmm__InvalidBid();
        }

        _userBalance[msgSender] -= _amount;
        _pushBidToken(id, msgSender, _amount);

        return _amount;
    }

    /// -----------------------------------------------------------------------
    /// Internal helpers
    /// -----------------------------------------------------------------------

    /// @notice returns current epoch.
    /// @param id pool id
    /// @param _epoch current epoch
    function _getDeposit(PoolId id, uint40 _epoch) public view returns (uint256) {
        return uint256(poolEpochManager[id][_epoch].rent * uint256(K(id)));
    }

    /// @notice returns current epoch.
    /// @param id pool id
    /// @param timestamp current timestamp
    function _getEpoch(PoolId id, uint256 timestamp) public view returns (uint40) {
        return uint40(timestamp / EPOCH_SIZE(id));
    }

    function _getRefund(PoolId id, uint40 _epoch, uint40 _targetEpoch) internal view returns (uint256) {
        return poolEpochManager[id][_epoch].rent * (_epoch + K(id) - _targetEpoch);
    }

    function _updateLastUpdatedEpoch(PoolId id, uint40 _epoch) internal returns (uint40) {
        return _lastUpdatedEpoch[id] = _epoch;
    }

    function _findUpperManager(PoolId id, uint40 _epoch) internal view returns (uint40) {
        for (uint40 e = _epoch; e <= _epoch + K(id); e++) {
            if (poolEpochManager[id][e].rent > 0) {
                return e;
            }
        }
        return 0;
    }

    /// @dev Transfers bid tokens from an address that's not address(this) to address(this)
    function _pullBidToken(PoolId, address from, uint256 amount) internal virtual {
        bidToken.transferFrom(from, address(this), amount);
    }

    /// @dev Transfers bid tokens from address(this) to an address that's not address(this)
    function _pushBidToken(PoolId, address to, uint256 amount) internal virtual {
        bidToken.transfer(to, amount);
    }

    /// @dev Validates a bid payload, e.g. ensure the swap fee is below a certain threshold
    function _payloadIsValid(PoolId id, bytes7 payload) internal view virtual returns (bool) {
        //TODO
        return false;
    }

    /// @dev Returns whether the am-AMM is enabled for a given pool
    function _amAmmEnabled(PoolId id) internal view virtual returns (bool) {
        return enabled[id];
    }

    function setEnabled(PoolId id, bool value) external {
        enabled[id] = value;
    }
}
