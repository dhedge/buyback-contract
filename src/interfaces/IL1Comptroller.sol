// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

interface IL1Comptroller {
    event BuyBackFromL1Initiated(
        address indexed depositor, address indexed receiver, uint256 burnTokenAmount, uint256 totalAmountBurnt
    );
    event CrossChainGasLimitModified(uint256 newCrossChainGasLimit);
    event EmergencyWithdrawal(address indexed token, uint256 amount);
    event Initialized(uint8 version);
    event L2ComptrollerSet(address newL2Comptroller);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address account);
    event Unpaused(address account);

    function burntAmountOf(address depositor) external view returns (uint256 totalAmount);
    function buyBack(address receiver, uint256 burnTokenAmount) external;
    function crossDomainMessenger() external view returns (address);
    function emergencyWithdraw(address token, uint256 amount) external;
    function initialize(address _crossDomainMessenger, address _tokenToBurn, uint32 _crossChainCallGasLimit) external;
    function l2Comptroller() external view returns (address);
    function owner() external view returns (address);
    function pause() external;
    function paused() external view returns (bool);
    function renounceOwnership() external;
    function setCrossChainGasLimit(uint32 newCrossChainGasLimit) external;
    function setL2Comptroller(address newL2Comptroller) external;
    function tokenToBurn() external view returns (address);
    function transferOwnership(address newOwner) external;
    function unpause() external;
}
