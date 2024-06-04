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

contract AMAMMHOOKTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    // using CurrencyLibrary for Currency;

    PoolId constant POOL_0 = PoolId.wrap(bytes32(0));

    AMAMMHOOK hook;
    AmAmmMock amAmm;

    address user0 = makeAddr("USER_0");
    address user1 = makeAddr("USER_1");
    address user2 = makeAddr("USER_2");

    uint128 internal constant K = 24; // 24 windows (hours)
    uint256 internal constant EPOCH_SIZE = 1 hours;
    uint256 internal constant MIN_BID_MULTIPLIER = 1.1e18; // 10%
    function setUp() public {
        // Deploy AMAMM

        amAmm = new AmAmmMock(new ERC20Mock(), new ERC20Mock(), new ERC20Mock());
        amAmm.bidToken().approve(address(amAmm), type(uint256).max);
        amAmm.setEnabled(POOL_0, true);

        amAmm.setMaxSwapFee(POOL_0, 0.1e6);

        // Deploy v4-core
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployMintAndApprove2Currencies();

        address hookAddress = address(
            uint160(
                Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.AFTER_SWAP_FLAG |
                Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG |
                Hooks.BEFORE_SWAP_FLAG
            )
        );
        deployCodeTo("AMAMMHOOK.sol", abi.encode(manager, address(amAmm), amAmm.bidToken()), hookAddress);
        hook = AMAMMHOOK(hookAddress);

        // key = PoolKey(currency0, currency1, 3000, 60, limitOrder);
        (key, ) = initPoolAndAddLiquidity(
            currency0,
            currency1,
            hook,
            LPFeeLibrary.DYNAMIC_FEE_FLAG, // Set the `DYNAMIC_FEE_FLAG` in place of specifying a fixed fee,
            SQRT_PRICE_1_1,
            ZERO_BYTES
        );
    }

    function test_swap_exactInput_zeroForOne_withNoFee() public {
        // amAmm.bidToken().mint(address(user0), K * 100e18);
        // amAmm.bidToken().mint(address(user1), K * 100e18);
        // amAmm.bidToken().mint(address(user2), K * 100e18);

        uint256 balanceBefore0 = currency0.balanceOf(address(this));
        console.log("balanceBefore0: ", balanceBefore0);
        uint256 balanceBefore1 = currency1.balanceOf(address(this));
        console.log("balanceBefore1: ", balanceBefore1);
        // uint256 rentBefore = amAmm.bidToken().balanceOf(address(this));
        // console.log("rentBefore: ", rentBefore);

        uint256 amountToSwap = 1000;
        swap(key, true, -int256(amountToSwap), ZERO_BYTES);

        // input is 1000 for output of 998 with this much liquidity available
        // plus a fee of 1.23% on unspecified (output) => (998*123)/10000 = 12
        // assertEq(
        //     currency0.balanceOf(address(this)),
        //     balanceBefore0 - amountToSwap,
        //     "amount 0"
        // );
        // assertEq(
        //     currency1.balanceOf(address(this)),
        //     balanceBefore1 + (998 - 12),
        //     "amount 1"
        // );

        // input is 1000 for output of 999 with this much liquidity available
        // plus a fee of 0
        // It proves that the swap fee has been changed
        assertEq(
            currency0.balanceOf(address(this)),
            balanceBefore0 - amountToSwap,
            "amount 0"
        );
        assertEq(
            currency1.balanceOf(address(this)),
            balanceBefore1 + 999,
            "amount 1"
        );
        // assertEq(
        //     currency1.balanceOf(address(this)),
        //     balanceBefore1 + 999,
        //     "amount 1"
        // );
    }

    function test_swap_exactInput_zeroForOne_withFee() public {
        amAmm.bidToken().mint(address(user0), K * 100e18);
        amAmm.bidToken().mint(address(user1), K * 100e18);
        amAmm.bidToken().mint(address(user2), K * 100e18);

        vm.startPrank(user0);
        amAmm.bidToken().approve(address(amAmm), K * 100e18);
        amAmm.bidToken().approve(address(hook), K * 100e18);
        amAmm.bid(POOL_0, _swapFeeToPayload(123), 1e18, 1);
        vm.stopPrank();

        assertEq(amAmm._getDeposit(POOL_0, 1), K * 1e18, "Bid Promoted to Top Bid");

        skip(10800); //Enter Epoch 3

        uint256 balanceBefore0 = currency0.balanceOf(address(this));
        console.log("balanceBefore0: ", balanceBefore0);
        uint256 balanceBefore1 = currency1.balanceOf(address(this));
        console.log("balanceBefore1: ", balanceBefore1);
        uint256 rentBefore = amAmm.bidToken().balanceOf(address(amAmm));
        console.log("rentBefore: ", rentBefore);

        uint256 amountToSwap = 1000;
        swap(key, true, -int256(amountToSwap), ZERO_BYTES);

        // input is 1000 for output of 998 with this much liquidity available
        // plus a fee of 1.23% on unspecified (output) => (998*123)/10000 = 12
        assertEq(
            currency0.balanceOf(address(this)),
            balanceBefore0 - amountToSwap,
            "amount 0"
        );
        assertEq(
            currency1.balanceOf(address(this)),
            balanceBefore1 + (998 - 12),
            "amount 1"
        );
        assertEq(
            amAmm.bidToken().balanceOf(address(amAmm)),
            rentBefore - 1e18,
            "amount 2"
        );
    }

    function _swapFeeToPayload(uint24 swapFee) internal pure returns (bytes7) {
        return bytes7(bytes3(swapFee));
    }
}
