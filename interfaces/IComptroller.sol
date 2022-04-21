// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

//** Comptroller Interface */
interface IComptroller {
    struct CompMarketState {
        uint224 index;
        uint32 block;
    }

    /// @notice The COMP market borrow state for each market
    function compBorrowState(address) external view returns (CompMarketState memory);

    /// @notice The COMP market supply state for each market
    function compSupplyState(address) external view returns (CompMarketState memory);

    function claimComp(address holder, address[] calldata _iTokens) external;

    function claimComp(address holder) external;

    function enterMarkets(address[] memory _iTokens) external;

    function pendingComptrollerImplementation() external view returns (address implementation);

    function markets(address)
        external
        view
        returns (
            bool,
            uint256,
            bool
        );

    /// @notice The portion of compRate that each market currently receives
    function compSpeeds(address) external view returns (uint256);

    /// The COMP accrued but not yet transferred to each user
    function compAccrued(address) external view returns (uint256);
}
