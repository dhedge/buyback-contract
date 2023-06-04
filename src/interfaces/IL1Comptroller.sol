// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

interface Interface {
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

    function L2Comptroller() external view returns (address);
    function burntAmountOf(address depositor) external view returns (uint256 totalAmount);
    function buyBackOnL2(address receiver, uint256 amount) external;
    function crossDomainMessenger() external view returns (address);
    function emergencyWithdraw(address token, uint256 amount) external;
    function initialize(address _crossDomainMessenger, address _tokenToBurn, uint32 _crossChainCallGasLimit) external;
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
