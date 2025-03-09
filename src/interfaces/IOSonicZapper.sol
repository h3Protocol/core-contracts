// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title Interface for Zapper for Origin Sonic (OS) tokens
 * @author Origin Protocol Inc
 */
interface IOSonicZapper {
    event Zap(address indexed minter, address indexed asset, uint256 amount);

    /**
     * @dev Deposit native S currency and receive Origin Sonic (OS) tokens in return.
     * Will verify that the user is sent 1:1 for S.
     * @return Amount of Origin Sonic (OS) tokens sent to user
     */
    function deposit() external payable returns (uint256);

    /**
     * @dev Deposit S and receive Wrapped Origin Sonic (wOS) in return
     * @param minReceived min amount of Wrapped Origin Sonic (wOS) to receive
     * @return Amount of Wrapped Origin Sonic (wOS) tokens sent to user
     */
    function depositSForWrappedTokens(uint256 minReceived) external payable returns (uint256);

    /**
     * @dev Deposit Wrapped Sonic (wS) tokens and receive Wrapped Origin Sonic (wOS) tokens in return
     * @param wSAmount Amount of Wrapped Sonic (wS) to deposit
     * @param minReceived min amount of Wrapped Origin Sonic (wOS) token to receive
     * @return Amount of Wrapped Origin Sonic (wOS) tokens sent to user
     */
    function depositWSForWrappedTokens(uint256 wSAmount, uint256 minReceived) external returns (uint256);
}
