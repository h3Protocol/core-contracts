// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IWrappedNative} from "./interfaces/IWrappedNative.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {H3rmes} from "./H3rmes.sol";

contract NativePositionManager is ReentrancyGuard, Owned {
    ERC20 public oSonic;
    ISwapRouter public swapRouter;

    H3rmes public h3rmes;

    IWrappedNative public wrappedSonic;
    uint16 public constant BASIS = 10_000;

    struct NativePositionManagerConfig {
        address h3rmes;
        address swapRouter;
        address wrappedSonic;
        address oSonic;
        uint16 minSlippage;
    }

    NativePositionManagerConfig public config;

    constructor(NativePositionManagerConfig memory _config, address _operator) Owned(_operator) {
        config = _config;
        h3rmes = H3rmes(_config.h3rmes);
        swapRouter = ISwapRouter(_config.swapRouter);
        oSonic = ERC20(_config.oSonic);
        wrappedSonic = IWrappedNative(_config.wrappedSonic);
    }

    function borrowNative(uint256 sonic, uint16 numberOfDays, uint256 maxAmountIn) public {
        uint256 oSonicReceived = h3rmes.borrowFor(msg.sender, sonic, numberOfDays, maxAmountIn);
        uint256 sonicReceived = oSonicUnwrap(oSonicReceived);
        sendSonic(msg.sender, sonicReceived);
    }

    function borrowMoreNative(uint256 sonic, uint256 maxAmountIn) public {
        uint256 oSonicReceived = h3rmes.borrowMoreFor(msg.sender, sonic, maxAmountIn);
        uint256 sonicReceived = oSonicUnwrap(oSonicReceived);
        sendSonic(msg.sender, sonicReceived);
    }

    function oSonicUnwrap(uint256 _amount) internal returns (uint256 amountSonic) {
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(oSonic),
            tokenOut: address(wrappedSonic),
            recipient: address(this),
            deadline: block.timestamp + 60,
            amountIn: _amount,
            amountOutMinimum: Math.mulDiv(_amount, 95, 100), // TODO: configurable slippage
            limitSqrtPrice: 0
        });

        amountSonic = swapRouter.exactInputSingle(swapParams);

        // Unwrap wrappedSonic to Sonic
        wrappedSonic.withdraw(amountSonic);
    }

    function sendSonic(address to, uint256 amount) internal {
        (bool success,) = to.call{value: amount}("");
        require(success, "Failed to send Sonic");
    }
}
