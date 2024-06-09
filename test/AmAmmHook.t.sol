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
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {AmAmmMock} from "./mocks/AmAmmMock.sol";
import "./mocks/ERC20Mock.sol";
import {UniswapV4ERC20} from "v4-periphery/libraries/UniswapV4ERC20.sol";

contract AMAMMHOOKTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    // using CurrencyLibrary for Currency;

    PoolId constant POOL_0 = PoolId.wrap(bytes32(0));
    PoolId POOL_1;

    AMAMMHOOK hook;
    address hookAddress;

    address user0 = makeAddr("USER_0");
    address user1 = makeAddr("USER_1");
    address user2 = makeAddr("USER_2");

    uint128 internal constant K = 24; // 24 windows (hours)
    uint256 internal constant EPOCH_SIZE = 1 hours;

    function setUp() public {
        // Deploy hook

        // Deploy v4-core
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployMintAndApprove2Currencies();

        hookAddress = address(
            uint160(
                Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
                    | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG
            )
        );
        deployCodeTo("AMAMMHOOK.sol", abi.encode(manager), hookAddress);
        hook = AMAMMHOOK(hookAddress);

        // key = PoolKey(currency0, currency1, 3000, 60, limitOrder);
        (key,) = initPool(
            currency0,
            currency1,
            hook,
            LPFeeLibrary.DYNAMIC_FEE_FLAG, // Set the `DYNAMIC_FEE_FLAG` in place of specifying a fixed fee,
            SQRT_PRICE_1_1,
            ZERO_BYTES
        );

        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, abi.encode(address(this)), false, false);
        console.log("modifyLiquidityRouter: ", address(modifyLiquidityRouter));

        POOL_1 = key.toId();
        hook.setEnabled(POOL_1, true);
        hook.setMaxSwapFee(POOL_1, 0.1e6);
    }

    function test_swap_exactInput_zeroForOne_withNoFee() public {
        hook.bidToken().approve(hookAddress, K * 100e18);

        currency0.transfer(address(user0), 10e18);
        currency0.transfer(address(user1), 10e18);

        uint256 balanceBefore0User0 = currency0.balanceOf(address(user0));
        uint256 balanceBefore1User0 = currency1.balanceOf(address(user0));

        uint256 balanceBefore0User1 = currency0.balanceOf(address(user1));
        uint256 balanceBefore1User1 = currency1.balanceOf(address(user1));

        console.log("balanceBefore user0: ", balanceBefore0User0, balanceBefore1User0);
        console.log("balanceBefore user1: ", balanceBefore0User1, balanceBefore1User1);

        uint256 amountToSwap = 1000;

        uint128 rent = 1;
        vm.prank(user0);
        hook.bid(POOL_1, _swapFeeToPayload(123), rent, 1);

        vm.prank(user1);
        hook.bid(POOL_1, _swapFeeToPayload(123), rent + 1, 1); //Winning bid

        vm.prank(user0);
        swap(key, true, -int256(amountToSwap), ZERO_BYTES);

        assertEq(
            currency0.balanceOf(address(user0)),
            balanceBefore0User0 - amountToSwap,
            "amount 0 with  swap Fee. Because they are not the Winner"
        );
        assertEq(
            currency1.balanceOf(address(user0)),
            balanceBefore1User0 + 999,
            "amount 1 with  swap fee. Because they are not the Winner"
        );

        vm.prank(user1);
        swap(key, true, -int256(amountToSwap), ZERO_BYTES);

        assertEq(
            currency0.balanceOf(address(user1)),
            balanceBefore0User0 - amountToSwap,
            "amount 0 with no swap Fee since they are the winner"
        );
        assertEq(
            currency1.balanceOf(address(user1)),
            balanceBefore1User0 + 999,
            "amount 1 with no swap fee since they are the winner"
        );
    }

    function test_swap_exactInput_zeroForOne_withFee_asWinner() public {
        hook.bidToken().approve(hookAddress, K * 100e18);

        uint256 balanceBefore0 = currency0.balanceOf(address(this));
        uint256 balanceBefore1 = currency1.balanceOf(address(this));

        console.log("balanceBefore0: ", balanceBefore0);
        console.log("balanceBefore1: ", balanceBefore1);
        console.log("test address: ", address(this));

        UniswapV4ERC20 bidToken = UniswapV4ERC20(hook.getPoolInfo(POOL_1).liquidityToken);
        uint256 lpTokenBefore = bidToken.balanceOf(hookAddress);

        console.log("LP Token before: ", lpTokenBefore);

        uint128 rent = 1;
        hook.bid(POOL_1, _swapFeeToPayload(123), rent, 1);

        uint256 lpTokenAfter = bidToken.balanceOf(hookAddress);

        console.log("LP Token After: ", lpTokenAfter);

        assertEq(lpTokenBefore + uint256(rent * K), lpTokenAfter, "LP token is token after bid");
        assertEq(hook._getDeposit(POOL_1, 1), K * rent, "Bid Promoted to Top Bid");

        skip(10800); //Enter Epoch 3

        uint256 amountToSwap = 1000;
        swap(key, true, -int256(amountToSwap), ZERO_BYTES);

        // input is 1000 for output of 998 with this much liquidity available
        // plus a fee of 1.23% on unspecified (output) => (998*123)/10000 = 12
        assertEq(currency0.balanceOf(address(this)), balanceBefore0 - amountToSwap, "amount 0");
        assertEq(
            currency1.balanceOf(address(this)),
            // balanceBefore1 + (998 - 12),
            // TODO: Create a new case that winner and current swapper not the same user
            balanceBefore1 + 998, // since the fee got sent to the winner which is the current user
            "amount 1"
        );
        lpTokenAfter = bidToken.balanceOf(hookAddress);
        console.log("LP Token After swap: ", lpTokenAfter);
        assertEq(
            lpTokenBefore + uint256(rent * K) - uint256(rent * 3), // 3 epochs of rent paid
            lpTokenAfter,
            "LP token is paid after swap"
        );
    }

    function test_swap_exactInput_zeroForOne_withFee() public {
        hook.bidToken().approve(hookAddress, K * 100e18);

        uint256 balanceBefore0 = currency0.balanceOf(address(this));
        uint256 balanceBefore1 = currency1.balanceOf(address(this));

        console.log("balanceBefore0: ", balanceBefore0);
        console.log("balanceBefore1: ", balanceBefore1);
        console.log("test address: ", address(this));

        UniswapV4ERC20 bidToken = UniswapV4ERC20(hook.getPoolInfo(POOL_1).liquidityToken);
        uint256 lpTokenBefore = bidToken.balanceOf(hookAddress);

        console.log("LP Token before: ", lpTokenBefore);

        uint128 rent = 1;
        hook.bid(POOL_1, _swapFeeToPayload(123), rent, 1);

        uint256 lpTokenAfter = bidToken.balanceOf(hookAddress);

        console.log("LP Token After: ", lpTokenAfter);

        assertEq(lpTokenBefore + uint256(rent * K), lpTokenAfter, "LP token is token after bid");
        assertEq(hook._getDeposit(POOL_1, 1), K * rent, "Bid Promoted to Top Bid");

        skip(10800); //Enter Epoch 3

        uint256 amountToSwap = 1000;
        swap(key, true, -int256(amountToSwap), ZERO_BYTES);

        // input is 1000 for output of 998 with this much liquidity available
        // plus a fee of 1.23% on unspecified (output) => (998*123)/10000 = 12
        assertEq(currency0.balanceOf(address(this)), balanceBefore0 - amountToSwap, "amount 0");
        assertEq(
            currency1.balanceOf(address(this)),
            // balanceBefore1 + (998 - 12),
            // TODO: Create a new case that winner and current swapper not the same user
            balanceBefore1 + 998, // since the fee got sent to the winner which is the current user
            "amount 1"
        );
        lpTokenAfter = bidToken.balanceOf(hookAddress);
        console.log("LP Token After swap: ", lpTokenAfter);
        assertEq(
            lpTokenBefore + uint256(rent * K) - uint256(rent * 3), // 3 epochs of rent paid
            lpTokenAfter,
            "LP token is paid after swap"
        );
    }

    function test_lp_token_supply_with_swap() public {
        hook.bidToken().approve(hookAddress, K * 100e18);

        uint256 balanceBefore0 = currency0.balanceOf(address(this));
        uint256 balanceBefore1 = currency1.balanceOf(address(this));

        UniswapV4ERC20 bidToken = UniswapV4ERC20(hook.getPoolInfo(POOL_1).liquidityToken);

        uint256 bidTokenSupplyBefore = bidToken.totalSupply();
        console.log("bidTokenSupplyBefore", bidTokenSupplyBefore);

        uint256 lpTokenBefore = bidToken.balanceOf(hookAddress);

        uint128 rent = 1;
        hook.bid(POOL_1, _swapFeeToPayload(123), rent, 1);

        uint256 lpTokenAfter = bidToken.balanceOf(hookAddress);

        skip(10800); //Enter Epoch 3

        uint256 amountToSwap = 1000;
        swap(key, true, -int256(amountToSwap), ZERO_BYTES);

        uint256 bidTokenSupplyAfter = bidToken.totalSupply();
        assertEq(
            bidTokenSupplyAfter,
            bidTokenSupplyBefore - 3,
            "LP token supply should reduce by the number of epochs passed"
        );

        skip(43200); //Enter Epoch 12
        uint128 epochsPassed = hook._getEpoch(POOL_1, block.timestamp);

        swap(key, true, -int256(amountToSwap), ZERO_BYTES);

        bidTokenSupplyAfter = bidToken.totalSupply();
        assertEq(
            bidTokenSupplyAfter,
            bidTokenSupplyBefore - epochsPassed,
            "LP token supply should reduce by the number of epochs passed"
        );
    }

    function test_lp_token_supply_with_changing_liquidity() public {
        hook.bidToken().approve(hookAddress, K * 100e18);

        uint256 balanceBefore0 = currency0.balanceOf(address(this));
        uint256 balanceBefore1 = currency1.balanceOf(address(this));

        UniswapV4ERC20 bidToken = UniswapV4ERC20(hook.getPoolInfo(POOL_1).liquidityToken);

        uint256 bidTokenSupplyBefore = bidToken.totalSupply();
        console.log("bidTokenSupplyBefore", bidTokenSupplyBefore);

        uint256 lpTokenBefore = bidToken.balanceOf(hookAddress);

        uint128 rent = 1;
        hook.bid(POOL_1, _swapFeeToPayload(123), rent, 1);

        uint256 lpTokenAfter = bidToken.balanceOf(hookAddress);

        skip(10800); //Enter Epoch 3

        uint256 amountToSwap = 1000;
        //swap(key, true, -int256(amountToSwap), ZERO_BYTES);

        uint256 bidTokenSupplyAfter = bidToken.totalSupply();
        console.log("bidTokenSupplyAfter", bidTokenSupplyAfter);
        assertEq(bidTokenSupplyAfter, bidTokenSupplyBefore, "LP token supply should remain the same");
    }

    /// -----------------------------------------------------------------------
    /// Helpers
    /// -----------------------------------------------------------------------

    function _swapFeeToPayload(uint24 swapFee) internal pure returns (bytes7) {
        return bytes7(bytes3(swapFee));
    }
}
