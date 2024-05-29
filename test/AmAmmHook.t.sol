// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Deployers} from "v4-core-test/utils/Deployers.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {console} from "forge-std/console.sol";
import {AMAMMHOOK} from "../src/AMAMMHOOK.sol";

contract AMAMMTest is Test, Deployers {
    // using CurrencyLibrary for Currency;

    AMAMMHOOK hook;

    function setUp() public {
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployMintAndApprove2Currencies();

        address hookAddress = address(uint160(Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG));
        deployCodeTo("AMAMM.sol", abi.encode(manager), hookAddress);
        hook = AMAMMHOOK(hookAddress);

        // key = PoolKey(currency0, currency1, 3000, 60, limitOrder);
        (key,) = initPoolAndAddLiquidity(currency0, currency1, hook, 100, SQRT_PRICE_1_1, ZERO_BYTES);
    }

    function test_swap_exactInput_zeroForOne() public {
        uint256 balanceBefore0 = currency0.balanceOf(address(this));
        console.log("balanceBefore0: ", balanceBefore0);
        uint256 balanceBefore1 = currency1.balanceOf(address(this));
        console.log("balanceBefore1: ", balanceBefore1);

        uint256 amountToSwap = 1000;
        swap(key, true, -int256(amountToSwap), ZERO_BYTES);

        // input is 1000 for output of 998 with this much liquidity available
        // plus a fee of 1.23% on unspecified (output) => (998*123)/10000 = 12
        assertEq(currency0.balanceOf(address(this)), balanceBefore0 - amountToSwap, "amount 0");
        assertEq(currency1.balanceOf(address(this)), balanceBefore1 + (998 - 12), "amount 1");
    }
}
