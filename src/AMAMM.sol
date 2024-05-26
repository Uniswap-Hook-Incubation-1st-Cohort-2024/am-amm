// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseHook} from "./forks/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

contract AMAMM is BaseHook {

    constructor(IPoolManager poolManager) BaseHook(poolManager) {}

    function getHookPermissions()
        public
        pure
        override
        returns (HookPermission[] memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true, // Update swap fee
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: true, // Redistribute swap fee
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

}