// SPDX-License-Identifier:  Unlicense
pragma solidity ^0.8.17;

interface ISuShiV2Factory {
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
}
