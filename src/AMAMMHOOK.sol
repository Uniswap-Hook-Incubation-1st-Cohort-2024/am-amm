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
import {UniswapV4ERC20} from "v4-periphery/libraries/UniswapV4ERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {AMAMM} from "./AMAMM.sol";
import {LibMulticaller} from "../lib/multicaller/src/LibMulticaller.sol";

contract AMAMMHOOK is BaseHook, AMAMM {
    using SafeCast for uint256;
    using PoolIdLibrary for PoolKey;
    using LPFeeLibrary for uint24;
    using StateLibrary for IPoolManager;
    
    error MustUseDynamicFee();
    error LiquidityDoesntMeetMinimum();
    error LiquidityNotInWithdrwalQueue();

    struct PoolInfo {
        bool hasAccruedFees;
        address liquidityToken;
    }

    uint128 public constant TOTAL_BIPS = 10000;
    uint128 public constant WITHDRAWAL_FEE_RATIO = 100;
    mapping(PoolId => PoolInfo) public poolInfo;
    mapping(PoolId id => uint40) internal _lastChargedEpoch;
    mapping(PoolId id => mapping(address => mapping(int => uint40))) public withdrawalQueue;

    constructor(IPoolManager poolManager)
        BaseHook(poolManager)
    {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: true, // charge withdrawal fee
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
    ) external override returns (bytes4) {
        PoolId poolId = key.toId();

        string memory tokenSymbol = string(
            abi.encodePacked(
                "UniV4",
                "-",
                IERC20Metadata(Currency.unwrap(key.currency0)).symbol(),
                "-",
                IERC20Metadata(Currency.unwrap(key.currency1)).symbol(),
                "-",
                Strings.toString(uint256(key.fee))
            )
        );
        address poolToken = address(new UniswapV4ERC20(tokenSymbol, tokenSymbol));
        console.log("poolToken: ", poolToken);

        _setBidToken(poolToken);

        poolInfo[poolId] = PoolInfo({hasAccruedFees: false, liquidityToken: poolToken});

        // `.isDynamicFee()` function comes from using
        // the `SwapFeeLibrary` for `uint24`
        if (!key.fee.isDynamicFee()) revert MustUseDynamicFee();
        return this.beforeInitialize.selector;
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override poolManagerOnly returns (bytes4, BalanceDelta) {
        PoolId poolId = key.toId();

        address payer = abi.decode(hookData, (address));
        console.log("payer: ", payer);
        PoolInfo storage pool = poolInfo[poolId];

        int liquidity = params.liquidityDelta;
        console.log("liquidity: ");
        console.logInt(liquidity);

        UniswapV4ERC20(pool.liquidityToken).mint(payer, uint(liquidity));

        return (this.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function beforeRemoveLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4) {
        PoolId poolId = key.toId();
        PoolInfo storage pool = poolInfo[poolId];
        address payer = abi.decode(hookData, (address));
        console.log("payer: ", payer);

        uint40 currentEpoch = _getEpoch(poolId, block.timestamp);
        IAmAmm.Bid memory _bid = getLastManager(poolId, currentEpoch);
        uint128 rent = _bid.rent;

        int liquidity = params.liquidityDelta;
        console.log("liquidity: ");
        console.logInt(liquidity);
        uint40 withdrawLiquidityEpoch = withdrawalQueue[poolId][payer][liquidity];

        // delay withdrwal when there's manager
        console.log("rent: ", rent);
        console.log("withdrawLiquidityEpoch: ");
        console.log(withdrawLiquidityEpoch);
        if(rent > 0 && ( withdrawLiquidityEpoch == 0 || currentEpoch <= withdrawLiquidityEpoch )){
            revert LiquidityNotInWithdrwalQueue();
        }
        // burn LP token
        UniswapV4ERC20(pool.liquidityToken).burn(payer, uint(-liquidity));

        return (this.beforeRemoveLiquidity.selector);
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

        PoolId poolId = key.toId();
        uint40 currentEpoch = _getEpoch(poolId, block.timestamp);
        IAmAmm.Bid memory _bid = getLastManager(poolId, currentEpoch);
        uint24 fee = _getFee(_bid);
        address bidder = _bid.bidder;
        uint128 rent = _bid.rent;
        uint256 feeAmount = (uint128(swapAmount) * uint128(fee)) / TOTAL_BIPS;
        // manager takes fee
        console.log("feeAmount: ", feeAmount);
        poolManager.take(feeCurrency, bidder, feeAmount);
        // LP charge rent
        console.log("rent: ", rent);
        if(rent > 0) {
            uint40 last = _lastChargedEpoch[poolId];
            if(last == 0) {
                last = _lastUpdatedEpoch[poolId] - 1; // -1 to charge from the last epoch
            }
            if (currentEpoch - last <= K(poolId)) {
                rent = rent * uint128(currentEpoch - last);
            } else {
                rent = rent * uint128(K(poolId));
            }

            PoolInfo storage pool = poolInfo[poolId];
            UniswapV4ERC20(pool.liquidityToken).burn(address(this), uint(rent));
            _lastChargedEpoch[poolId] = currentEpoch;
        }
        return (IHooks.afterSwap.selector, feeAmount.toInt128());
    }

    function getPoolInfo(PoolId poolId) external view returns (PoolInfo memory) {
        return poolInfo[poolId];
    }

    function addToWithdrawalQueue(PoolId poolId, int liquidity) external {
        address msgSender = LibMulticaller.senderOrSigner();
        withdrawalQueue[poolId][msgSender][liquidity] = _getEpoch(poolId, block.timestamp);
    }

    /// -----------------------------------------------------------------------
    /// Internal helpers
    /// -----------------------------------------------------------------------

    function _getLastManager(PoolId poolid) internal returns (IAmAmm.Bid memory) {
        return getLastManager(poolid, _getEpoch(poolid, block.timestamp));
    }

    function _getFee(IAmAmm.Bid memory _bid) internal view returns (uint24) {
        return uint24(bytes3(_bid.payload));
    }

    function _setBidToken(address _bidToken) internal {
        bidToken = UniswapV4ERC20(_bidToken);
    }
}
