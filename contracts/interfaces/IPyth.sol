// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPyth — Interface for Pyth Oracle (Polygon)
 * @notice Minimal interface for fetching MATIC/USD price from Pyth. Used in AiFinPay core for fee calculations. For mainnet deployment, use the official Pyth contract:
 */
interface IPyth {
    struct Price {
        int64  price;
        uint64 conf;
        int32  expo;
        uint   publishTime;
    }
    function getUpdateFee(bytes[] calldata updateData) external view returns (uint feeAmount);
    function updatePriceFeeds(bytes[] calldata updateData) external payable;
    function getPriceNoOlderThan(bytes32 id, uint age) external view returns (Price memory price);
}

