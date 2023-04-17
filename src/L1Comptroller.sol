// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {IERC20Burnable} from "./interfaces/IERC20Burnable.sol";
import {ICrossDomainMessenger} from "./interfaces/ICrossDomainMessenger.sol";

// TODO: Remove this line before deployment.
import "forge-std/console.sol";

/// @title L1 comptroller contract for token buy backs.
/// @notice Contract to burn a token and claim another one on L2.
/// @author dHEDGE
/// @dev This contract is only useful if paired with the L2 comptroller.
contract L1Comptroller is OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event L2ComptrollerSet(address newL2Comptroller);
    event CrossChainGasLimitModified(uint256 newCrossChainGasLimit);
    event EmergencyWithdrawal(address indexed token, uint256 amount);
    event TokensBurned(address indexed depositor, uint256 burnTokenAmount);
    event TokenClaimInitiated(
        address indexed depositor,
        address indexed receiver,
        uint256 burnTokenAmount
    );

    error ZeroAddress();
    error ZeroValue();
    error InvalidClaim();
    error L2ComptrollerNotSet();

    /// @notice Token to burn.
    /// @dev Should be a token which implements ERC20Burnable methods. MTA token does so in our case.
    IERC20Burnable public tokenToBurn;

    /// @notice The Optimism contract to interact with on L1 Ethereum for sending data using smart contracts.
    ICrossDomainMessenger public crossDomainMessenger;

    /// @notice Address of the L2 comptroller to be called to initiate a buyback claim.
    /// @dev Has to be set after deployment of both the contracts.
    address public L2Comptroller;

    /// @dev The gas limit to be used to call the Optimism Cross Domain Messenger contract.
    uint32 private crossChainCallGasLimit;

    /// @notice Stores cumulative amount of tokens burnt by an address.
    /// @dev We don't need to use order IDs as the difference of `totalAmount` (burnt) on L1
    ///      and `totalAmount` (claimed) on L2 gives us the amount of buy tokens tokens yet to be claimed.
    /// @dev The `totalAmount` for an address would/should NEVER decrease.
    mapping(address depositor => uint256 totalAmount) public burntAmountOf;

    /// @dev Modifier to check that L2Comptroller address has been set or not.
    modifier whenL2ComptrollerSet() {
        if (L2Comptroller == address(0)) revert L2ComptrollerNotSet();
        _;
    }

    /// @dev To prevent the implementation contract from being used, we invoke the _disableInitializers
    /// function in the constructor to automatically lock it when it is deployed.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        ICrossDomainMessenger _crossDomainMessenger,
        IERC20Burnable _tokenToBurn,
        uint32 _crossChainCallGasLimit
    ) external initializer {
        if (
            address(_tokenToBurn) == address(0) ||
            address(_crossDomainMessenger) == address(0)
        ) revert ZeroAddress();

        __Ownable_init();
        __Pausable_init();

        crossDomainMessenger = _crossDomainMessenger;
        tokenToBurn = _tokenToBurn;
        crossChainCallGasLimit = _crossChainCallGasLimit;
    }

    /// @notice Function to burn `amount` of tokens and create an order against it.
    /// @param amount Amount of `tokenToBurn` to be burnt and exchanged.
    function buyBackOnL2(
        uint256 amount
    ) external whenNotPaused whenL2ComptrollerSet {
        _burnAndUpdate(msg.sender, amount);
        _claimOnL2(msg.sender, msg.sender);
    }

    /// @notice Function to burn `amount` of tokens and claim against it on L2.
    /// @param amount Amount of `tokenToBurn` to be burnt and exchanged.
    /// @param receiver Address of the account which will receive the buy tokens.
    function buyBackOnL2AndTransfer(
        address receiver,
        uint256 amount
    ) external whenNotPaused whenL2ComptrollerSet {
        _burnAndUpdate(msg.sender, amount);
        _claimOnL2(msg.sender, receiver);
    }

    /// @notice Function to initiate a claim on L2 after burning of `tokenToBurn`.
    /// @dev Can be used to trigger a claim on L2 is cross chain call fails for some reason.
    ///      after calling `buyBackOnL2`.
    function claimOnL2() external whenNotPaused {
        _claimOnL2(msg.sender, msg.sender);
    }

    /// @notice Function to initiate a claim on L2 after burning of `tokenToBurn` and transfer the claimed
    ///         tokens to another address.
    /// @dev Can be used to trigger a claim on L2 is cross chain call fails for some reason.
    ///      after calling `buyBackOnL2`.
    function claimOnL2AndTransfer(address receiver) external whenNotPaused {
        _claimOnL2(msg.sender, receiver);
    }

    function _burnAndUpdate(
        address depositor,
        uint256 amount
    ) internal {
        // Burning the `amount` tokens held by the user without transferring them to
        // this contract first. This functionality is provided by the `ERC20Burnable` contract.
        tokenToBurn.burnFrom(depositor, amount);

        burntAmountOf[depositor] += amount;
    }

    // Question: Should a check of L2Comptroller address be made?
    function _claimOnL2(address depositor, address receiver) internal {
        uint256 totalAmount = burntAmountOf[msg.sender];

        // This check isn't necessary as this case is handled in the L2Comptroller anyway 
        // but we don't want the user calling this function when they never initiated a buy back.
        if(totalAmount == 0) revert InvalidClaim();

        // Send a cross chain message to `L2Comptroller` for releasing the buy tokens.
        crossDomainMessenger.sendMessage(
            L2Comptroller,
            abi.encodeWithSignature(
                "buyBackFromL1(address,address,uint)",
                depositor,
                receiver,
                totalAmount
            ),
            crossChainCallGasLimit
        );

        emit TokenClaimInitiated(depositor, receiver, totalAmount);
    }


    /////////////////////////////////////////////
    //             Owner Functions             //
    /////////////////////////////////////////////

    /// @notice Function to set the L2 comptroller address deployed on Optimism.
    /// @dev This function needs to be called after deployment of both the contracts.
    /// @param newL2Comptroller Address of the newly deployed L2 comptroller.
    // Question: Should this be allowed to be called only once?
    function setL2Comptroller(address newL2Comptroller) external onlyOwner {
        if (newL2Comptroller == address(0)) revert ZeroAddress();

        L2Comptroller = newL2Comptroller;

        emit L2ComptrollerSet(newL2Comptroller);
    }

    /// @notice Function to withdraw tokens in an emergency situation.
    /// @param token Address of the token to be withdrawn.
    /// @param amount Amount of the `token` to be removed.
    // Question: Rug pull protection?
    function emergencyWithdraw(
        address token,
        uint256 amount
    ) external onlyOwner {
        IERC20Upgradeable tokenToWithdraw = IERC20Upgradeable(token);

        // If the `amount` is max of uint256 then transfer all the available balance.
        if (amount == type(uint256).max) {
            amount = tokenToWithdraw.balanceOf(address(this));
        }

        // NOTE: If the balanceOf(address(this)) < `amount` < type(uint256).max then
        // the transfer will revert.
        tokenToWithdraw.safeTransfer(owner(), amount);

        emit EmergencyWithdrawal(token, amount);
    }

    /// @notice Function to set the cross chain calls gas limit.
    /// @dev Optimism allows, upto a certain limit, free execution gas units on L2.
    ///      This value is currently 1.92 million gas units.
    function setCrossChainGasLimit(
        uint32 newCrossChainGasLimit
    ) external onlyOwner {
        if (newCrossChainGasLimit == 0) revert ZeroValue();

        crossChainCallGasLimit = newCrossChainGasLimit;

        emit CrossChainGasLimitModified(newCrossChainGasLimit);
    }

    /// @notice Function to pause the critical functions in this contract.
    /// @dev This function won't make any state changes if already paused.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Function to unpause the critical functions in this contract.
    /// @dev This function won't make any state changes if already unpaused.
    function unpause() external onlyOwner {
        _unpause();
    }
}
