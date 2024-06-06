// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";

import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {AMAMM} from "../../src/AMAMM.sol";

import "./ERC20Mock.sol";

contract AmAmmMock is AMAMM {
    using CurrencyLibrary for Currency;

    ERC20Mock public immutable feeToken0;
    ERC20Mock public immutable feeToken1;

    mapping(PoolId id => uint24) public maxSwapFee;

    constructor(ERC20Mock _bidToken, ERC20Mock _feeToken0, ERC20Mock _feeToken1) {
        bidToken = _bidToken;
        feeToken0 = _feeToken0;
        feeToken1 = _feeToken1;
    }

    function setMaxSwapFee(PoolId id, uint24 value) external {
        maxSwapFee[id] = value;
    }

    /// @dev Returns whether the am-AMM is enabled for a given pool
    function _amAmmEnabled(PoolId id) internal view override returns (bool) {
        return enabled[id];
    }

    /// @dev Validates a bid payload
    function _payloadIsValid(PoolId id, bytes7 payload) internal view override returns (bool) {
        // first 3 bytes of payload are the swap fee
        return uint24(bytes3(payload)) <= maxSwapFee[id];
    }

    /// @dev Burns bid tokens from address(this)
    function _burnBidToken(PoolId, uint256 amount) internal {
        bidToken.burn(amount);
    }

    /// @dev Transfers bid tokens from an address that's not address(this) to address(this)
    function _pullBidToken(PoolId, address from, uint256 amount) internal override {
        bidToken.transferFrom(from, address(this), amount);
    }

    /// @dev Transfers bid tokens from address(this) to an address that's not address(this)
    function _pushBidToken(PoolId, address to, uint256 amount) internal override {
        bidToken.transfer(to, amount);
    }

    /// @dev Transfers accrued fees from address(this)
    function _transferFeeToken(Currency currency, address to, uint256 amount) internal {
        currency.transfer(to, amount);
    }
}
