// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

interface IL2Comptroller {
    event AssertionErrorDuringBuyBack(address indexed depositor, uint256 errorCode);
    event BuyTokenPriceUpdated(uint256 updatedBuyTokenPrice);
    event EmergencyWithdrawal(address indexed token, uint256 amount);
    event Initialized(uint8 version);
    event LowLevelErrorDuringBuyBack(address indexed depositor, bytes reason);
    event ModifiedMaxTokenPriceDrop(uint256 newMaxTokenPriceDrop);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address account);
    event RequireErrorDuringBuyBack(address indexed depositor, string reason);
    event TokensClaimed(
        address indexed depositor, address indexed receiver, uint256 burnTokenAmount, uint256 buyTokenAmount
    );
    event Unpaused(address account);
    event l1ComptrollerSet(address newL1Comptroller);

    function DENOMINATOR() external view returns (uint256);
    function _buyBack(address receiver, uint256 burnTokenAmount) external returns (uint256 buyTokenAmount);
    function burnMultiSig() external view returns (address);
    function buyBack(address receiver, uint256 burnTokenAmount) external returns (uint256 buyTokenAmount);
    function buyBackFromL1(address l1Depositor, address receiver, uint256 totalAmountBurntOnL1) external;
    function claim(address receiver, uint256 burnTokenAmount) external;
    function claimAll(address receiver) external;
    function claimedAmountOf(address depositor) external view returns (uint256 totalAmountClaimed);
    function convertToTokenToBurn(uint256 buyTokenAmount) external view returns (uint256 burnTokenAmount);
    function convertToTokenToBuy(uint256 burnTokenAmount) external view returns (uint256 buyTokenAmount);
    function crossDomainMessenger() external view returns (address);
    function emergencyWithdraw(address token, uint256 amount) external;
    function exchangePrice() external view returns (uint256);
    function getClaimableAmount(address depositor) external view returns (uint256 tokenToBuyClaimable);
    function initialize(
        address _crossDomainMessenger,
        address _tokenToBurn,
        address _tokenToBuy,
        address _burnMultiSig,
        uint256 _exchangePrice,
        uint256 _maxTokenPriceDrop
    ) external;
    function l1BurntAmountOf(address depositor) external view returns (uint256 totalAmountBurned);
    function l1Comptroller() external view returns (address);
    function lastTokenToBuyPrice() external view returns (uint256);
    function maxBurnAmountClaimable() external view returns (uint256 maxBurnTokenAmount);
    function maxTokenPriceDrop() external view returns (uint256);
    function modifyThreshold(uint256 newMaxTokenPriceDrop) external;
    function owner() external view returns (address);
    function pause() external;
    function paused() external view returns (bool);
    function renounceOwnership() external;
    function setL1Comptroller(address newL1Comptroller) external;
    function tokenToBurn() external view returns (address);
    function tokenToBuy() external view returns (address);
    function transferOwnership(address newOwner) external;
    function unpause() external;
}
