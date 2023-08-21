//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "./IERC20.sol";

interface ICAR is IERC20 {
    function _trade() external;

    function _mint(address account, uint256 value) external;
}
