// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IERC20Extended is IERC20Upgradeable {
    function decimals() external view returns (uint8);
}
