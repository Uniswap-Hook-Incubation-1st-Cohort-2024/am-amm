// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

import "./ERC20Mock.sol";
import {AMAMM} from "../../src/AmAmm.sol";

contract AmAmmMock is AMAMM {
    using CurrencyLibrary for Currency;

    ERC20Mock public immutable bidToken;
    ERC20Mock public immutable feeToken0;
    ERC20Mock public immutable feeToken1;

    mapping(PoolId id => bool) public enabled;
    mapping(PoolId id => uint24) public maxSwapFee;

    constructor(ERC20Mock _bidToken, ERC20Mock _feeToken0, ERC20Mock _feeToken1)
        AMAMM() // Passing the required parameter to the base constructor
    {
        bidToken = _bidToken;
        feeToken0 = _feeToken0;
        feeToken1 = _feeToken1;
    }

    function setEnabled(PoolId id, bool value) external {
        enabled[id] = value;
    }

    function setMaxSwapFee(PoolId id, uint24 value) external {
        maxSwapFee[id] = value;
    }

    function giveFeeToken0(PoolId id, uint256 amount) external {
        _updateEpochBids();
        // address manager = _topBids[id].manager;
        // feeToken0.mint(address(this), amount);
        // _accrueFees(manager, Currency.wrap(address(feeToken0)), amount);
    }

    function giveFeeToken1(PoolId id, uint256 amount) external {
        _updateEpochBids();
        // address manager = _topBids[id].manager;
        // feeToken1.mint(address(this), amount);
        // _accrueFees(manager, Currency.wrap(address(feeToken1)), amount);
    }
}
