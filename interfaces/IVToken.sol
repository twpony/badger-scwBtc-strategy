// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IVToken {
    function underlying() external returns (address);

    function totalBorrows() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function totalReserves() external view returns (uint256);

    function borrowIndex() external view returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function mint(uint256 mintAmount) external returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    function borrow(uint256 borrowAmount) external returns (uint256);

    function repayBorrow(uint256 repayAmount) external returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function balanceOfUnderlying(address owner) external returns (uint256);

    function borrowBalanceStored(address account)
        external
        view
        returns (uint256);

    function comptroller() external returns (address);

    function getAccountSnapshot(address account)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        );

    function accrualBlockNumber() external view returns (uint256);

    function reserveFactorMantissa() external view returns (uint256);
}
