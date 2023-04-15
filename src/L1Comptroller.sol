// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {IERC20Burnable} from "./interfaces/IERC20Burnable.sol";
import {ICrossDomainMessenger} from "./interfaces/ICrossDomainMessenger.sol";

/// @title L1 comptroller contract for token buy backs.
/// @notice Contract to burn a token and claim another one on L2.
/// @author dHEDGE
/// @dev This contract is only useful if paired with the L2 comptroller.
contract L1Comptroller is OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event TokensBurned(
        address indexed depositor,
        uint256 burnTokenAmount
    );
    event L2ComptrollerSet(address newL2Comptroller);

    error ZeroAddress();
    error L2ComptrollerNotSet();

    /// @notice Token to burn.
    /// @dev Should be a token which implements ERC20Burnable methods. MTA token does so in our case.
    IERC20Burnable public tokenToBurn;

    /// @notice The Optimism contract to interact with on L1 Ethereum for sending data using smart contracts.
    ICrossDomainMessenger public crossDomainMessenger;

    /// @notice Address of the L2 comptroller to be called to initiate a buyback claim.
    /// @dev Has to be set after deployment of both the contracts.
    address public L2Comptroller;

    /// @notice Stores cumulative amount of tokens burnt by an address.
    /// @dev We don't need to use order IDs as the difference of `totalAmount` (burnt) on L1
    ///      and `totalAmount` (claimed) on L2 gives us the amount of buy tokens tokens yet to be claimed.
    /// @dev The `totalAmount` for an address would/should NEVER decrease.
    mapping(address depositor => uint256 totalAmount) public burntAmountOf;

    /// @dev To prevent the implementation contract from being used, we invoke the _disableInitializers
    /// function in the constructor to automatically lock it when it is deployed.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(ICrossDomainMessenger _crossDomainMessenger, IERC20Burnable _tokenToBurn) external initializer {
        if (address(_tokenToBurn) == address(0)) revert ZeroAddress();

        __Ownable_init();
        __Pausable_init();

        crossDomainMessenger = _crossDomainMessenger;
        tokenToBurn = _tokenToBurn;
    }

    /// @notice Function to burn `amount` of tokens and create an order against it.
    /// @param amount Amount of `tokenToBurn` to be burnt and exchanged.
    function buyBackOnL2(
        uint256 amount
    ) external whenNotPaused {
        if (L2Comptroller == address(0)) revert L2ComptrollerNotSet();

        // Burning the `amount` tokens held by the user without transferring them to
        // this contract first. This functionality is provided by the `ERC20Burnable` contract.
        // TODO: Explore if any low level calls are required to verify nothing failed silently.
        tokenToBurn.burnFrom(msg.sender, amount);

        burntAmountOf[msg.sender] += amount;

        // TODO: Perform a cross contract call to the L2Comptroller to give buy token to
        // the caller.

        emit TokensBurned(msg.sender, amount);
    }

    /////////////////////////////////////////////
    //             Owner Functions             //
    /////////////////////////////////////////////

    // Question: Should this be allowed to be called only once?
    function setL2Comptroler(address newL2Comptroller) external onlyOwner {
        if(newL2Comptroller == address(0)) revert ZeroAddress();

        L2Comptroller = newL2Comptroller;
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
    }

    /// @notice Function to pause the critical functions in this contract.
    /// @dev This function won't make any state changes if already paused.
    function pause() external onlyOwner {
        if (!paused()) _pause();
    }

    /// @notice Function to unpause the critical functions in this contract.
    /// @dev This function won't make any state changes if already unpaused.
    function unpause() external onlyOwner {
        if (paused()) _unpause();
    }
}
