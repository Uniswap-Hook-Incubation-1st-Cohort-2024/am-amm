// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";

import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {AMAMM} from "../../src/AMAMM.sol";
import {UniswapV4ERC20} from "v4-periphery/libraries/UniswapV4ERC20.sol";

contract AmAmmMock is AMAMM {
    using CurrencyLibrary for Currency;

    constructor(address _bidToken) {
        bidToken = UniswapV4ERC20(_bidToken);
    }

    /// @dev Transfers accrued fees from address(this)
    // function _transferFeeToken(Currency currency, address to, uint256 amount) internal {
    //     currency.transfer(to, amount);
    // }
}
