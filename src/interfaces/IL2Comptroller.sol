// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

interface Interface {
    event AssertErrorDuringBuyBack(address indexed depositor, bytes reason);
    event BuyTokenPriceUpdated(uint256 updatedBuyTokenPrice);
    event EmergencyWithdrawal(address indexed token, uint256 amount);
    event Initialized(uint8 version);
    event L1ComptrollerSet(address newL1Comptroller);
    event ModifiedMaxTokenPriceDrop(uint256 newMaxTokenPriceDrop);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address account);
    event RequireErrorDuringBuyBack(address indexed depositor, string reason);
    event TokensBoughtOnL1(
        address indexed depositor, address indexed receiver, uint256 burnTokenAmount, uint256 buyTokenAmount
    );
    event TokensBoughtOnL2(
        address indexed depositor, address indexed receiver, uint256 burnTokenAmount, uint256 buyTokenAmount
    );
    event Unpaused(address account);

    function DENOMINATOR() external view returns (uint256);
    function L1Comptroller() external view returns (address);
    function _buyBack(address receiver, uint256 amount) external returns (uint256 buyTokenAmount);
    function burnMultiSig() external view returns (address);
    function buyBack(address receiver, uint256 amount) external returns (uint256 buyTokenAmount);
    function buyBackFromL1(address l1Depositor, address receiver, uint256 totalAmountBurntOnL1) external;
    function claim(address receiver, uint256 amount) external;
    function claimAll(address receiver) external;
    function claimedAmountOf(address depositor) external view returns (uint256 totalAmountClaimed);
    function convertToTokenToBurn(uint256 amount) external view returns (uint256 burnTokenAmount);
    function convertToTokenToBuy(uint256 amount) external view returns (uint256 buyTokenAmount);
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
