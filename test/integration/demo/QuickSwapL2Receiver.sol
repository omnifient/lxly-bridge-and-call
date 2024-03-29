// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract QuickSwapL2Receiver {
    using SafeERC20 for IERC20;

    function approveAndQuickSwap(address quickswapRouter, bytes memory data) external payable {
        uint256 amt = 1000 * 10 ** 6;
        IERC20(0xA8CE8aee21bC2A48a5EF670afCc9274C7bbbC035).safeTransferFrom(msg.sender, address(this), amt);

        // approve bridge wrapped usdc to be used by quickswap router
        // NOTE: hardcoding these values because the args are all encoded
        // since this does a dynamic invocation to QuickSwap's router
        // for production, a receiver contract should take explicit parameters
        IERC20(0xA8CE8aee21bC2A48a5EF670afCc9274C7bbbC035).approve(quickswapRouter, amt);

        // do the swap
        (bool success,) = quickswapRouter.call(data);
        require(success);

        // above dynamic call is equivalent to:
        // ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
        //     .ExactInputSingleParams(
        //         0xA8CE8aee21bC2A48a5EF670afCc9274C7bbbC035,
        //         0xa2036f0538221a77A3937F1379699f44945018d0,
        //         0x2B5AD5c4795c026514f8317c7a215E218DcCD6cF,
        //         block.timestamp + 86400,
        //         1000 * 10 ** 6,
        //         0,
        //         0
        //     );
        // ISwapRouter(targetContract).exactInputSingle(params);
    }
}

// interface ISwapRouter {
//     struct ExactInputSingleParams {
//         address tokenIn;
//         address tokenOut;
//         address recipient;
//         uint256 deadline;
//         uint256 amountIn;
//         uint256 amountOutMinimum;
//         uint160 limitSqrtPrice;
//     }

//     function exactInputSingle(
//         ExactInputSingleParams calldata params
//     ) external payable returns (uint256 amountOut);
// }
