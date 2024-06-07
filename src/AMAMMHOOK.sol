// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// import {BaseHook} from "v4-periphery/BaseHook.sol";
import {BaseHook} from "./forks/BaseHook.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {IAmAmm} from "./interfaces/IAmAmm.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {console} from "forge-std/console.sol";

contract AMAMMHOOK is BaseHook {
    using SafeCast for uint256;
    using PoolIdLibrary for PoolKey;
    using LPFeeLibrary for uint24;
    
    IAmAmm public immutable AMAMM = IAmAmm(AMAMM);
    Currency public immutable bidToken;

    error MustUseDynamicFee();

    uint128 public constant TOTAL_BIPS = 10000;

    constructor(IPoolManager poolManager, address _AMAMM, Currency _bidToken)
        BaseHook(poolManager)
    {
        AMAMM = IAmAmm(_AMAMM);
        bidToken = _bidToken;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true, // Override how swaps are done
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: true, // Allow afterSwap to return a custom delta
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function beforeInitialize(
        address,
        PoolKey calldata key,
        uint160,
        bytes calldata
    ) external pure override returns (bytes4) {
        // `.isDynamicFee()` function comes from using
        // the `SwapFeeLibrary` for `uint24`
        if (!key.fee.isDynamicFee()) revert MustUseDynamicFee();
        return this.beforeInitialize.selector;
    }


    function beforeSwap(address sender, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata)
        external
        override
        poolManagerOnly
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        IAmAmm.Bid memory _bid = _getLastManager(key.toId());
        uint24 fee = _getFee(_bid);
        console.log("fee: ", fee);
        poolManager.updateDynamicLPFee(key, fee);

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(
        address, /* sender **/
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata /* hookData **/
    ) external override poolManagerOnly returns (bytes4, int128) {
        // fee will be in the unspecified token of the swap
        bool specifiedTokenIs0 = (params.amountSpecified < 0 == params.zeroForOne);
        (Currency feeCurrency, int128 swapAmount) =
            (specifiedTokenIs0) ? (key.currency1, delta.amount1()) : (key.currency0, delta.amount0());
        // if fee is on output, get the absolute output amount
        if (swapAmount < 0) swapAmount = -swapAmount;

        IAmAmm.Bid memory _bid = _getLastManager(key.toId());
        uint24 fee = _getFee(_bid);
        address bidder = _bid.bidder;
        uint128 rent = _bid.rent;

        uint256 feeAmount = (uint128(swapAmount) * uint128(fee)) / TOTAL_BIPS;
        // manager takes fee
        console.log("feeAmount: ", feeAmount);
        poolManager.take(feeCurrency, bidder, feeAmount);
        // LP charge rent
        console.log("rent: ", rent);
        poolManager.take(bidToken, address(AMAMM), rent);

        return (IHooks.afterSwap.selector, feeAmount.toInt128());
    }

    function _getLastManager(PoolId poolid) internal returns (IAmAmm.Bid memory) {
        return AMAMM.getLastManager(poolid, AMAMM._getEpoch(poolid, block.timestamp));
    }

    function _getFee(IAmAmm.Bid memory _bid) internal view returns (uint24) {
        return uint24(bytes3(_bid.payload));
    }
}
