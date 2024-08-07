// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {IERC20Burnable} from "../interfaces/IERC20Burnable.sol";
import {ICrossDomainMessenger} from "../interfaces/ICrossDomainMessenger.sol";

import {L2ComptrollerV2Base} from "./L2ComptrollerV2Base.sol";

/// @title L1 comptroller contract for token buy backs.
/// @notice Contract to burn a token and claim another one on L2.
/// @author dHEDGE
/// @dev This contract is only useful if paired with the L2 comptroller.
abstract contract L1ComptrollerV2Base is OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /////////////////////////////////////////////
    //                  Events                 //
    /////////////////////////////////////////////

    event BurnTokenAdded(address token);
    event BurnTokenRemoved(address token);
    event L2ComptrollerSet(address newL2Comptroller);
    event CrossChainGasLimitModified(uint256 newCrossChainGasLimit);
    event EmergencyWithdrawal(address indexed token, uint256 amount);
    event RedeemFromL1Initiated(
        address indexed depositor,
        address indexed tokenToBurn,
        address indexed receiver,
        uint256 burnTokenAmount,
        uint256 totalAmountBurnt
    );

    /////////////////////////////////////////////
    //                  Errors                 //
    /////////////////////////////////////////////

    error ZeroAddress();
    error ZeroValue();
    error L2ComptrollerNotSet();
    error NonRedeemableToken(address token);

    /////////////////////////////////////////////
    //                Variables                //
    /////////////////////////////////////////////

    /// @notice The address used to send tokens to be burnt in case the token is not natively burnable.
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /// @notice Address of the L2 comptroller to be called to initiate a buyback claim.
    /// @dev Has to be set after deployment of both the contracts.
    address public l2Comptroller;

    /// @notice Mapping of token to be burnt and its details.
    /// @dev Note that we are not enforcing that the `token` be a burnable token.
    ///      We can write different functions depending on the token type.
    mapping(address token => bool burnable) public tokensToBurn;

    /// @notice Stores cumulative amount of tokens burnt by an address.
    /// @dev We don't need to use order IDs as the difference of `totalAmount` (burnt) on L1
    ///      and `totalAmount` (claimed) on L2 gives us the amount of buy tokens tokens yet to be claimed.
    /// @dev The `totalAmount` for an address would/should NEVER decrease.
    mapping(address depositor => mapping(address tokenToBurn => uint256 totalAmount)) public burntAmountOf;

    /////////////////////////////////////////////
    //                Modifiers                //
    /////////////////////////////////////////////

    /// @dev Modifier to check that l2Comptroller address has been set or not.
    modifier whenL2ComptrollerSet() {
        if (l2Comptroller == address(0)) revert L2ComptrollerNotSet();
        _;
    }

    /////////////////////////////////////////////
    //                Functions                //
    /////////////////////////////////////////////

    /// @notice Function to burn `amount` of a `token` and claim against it on L2.
    /// @dev - If a transaction passes on L1 but fails on L2 then the user must claim their share on L2 directly.
    ///      - Note that this function can be called with any `tokenToBuy` passed and it's not validated here.
    ///        This is safe as long as the total burnt amount is updated in the L2 contract.
    ///        That way, the user can claim whatever supported token they want on the L2 side.
    /// @param tokenToBurn Address of the token to be burnt.
    /// @param tokenToBuy Address of the token to be claimed.
    /// @param burnTokenAmount Amount of `tokenToBurn` to be burnt.
    /// @param receiver Address of the account which will receive the claim.
    /// @param additionalData Data to be sent to the L2 comptroller and for the L1 -> L2 message (if any).
    function redeem(
        address tokenToBurn,
        address tokenToBuy,
        uint256 burnTokenAmount,
        address receiver,
        bytes memory additionalData
    ) public payable whenNotPaused whenL2ComptrollerSet {
        _burnToken(tokenToBurn, burnTokenAmount);

        uint256 totalBurntAmount = burntAmountOf[msg.sender][tokenToBurn] += burnTokenAmount;

        // Send a cross chain message to `l2Comptroller` for releasing the buy tokens.
        _sendMessage(
            abi.encodeCall(
                L2ComptrollerV2Base.redeemFromL1,
                (tokenToBurn, tokenToBuy, totalBurntAmount, msg.sender, receiver)
            ),
            additionalData
        );

        emit RedeemFromL1Initiated(msg.sender, tokenToBurn, receiver, burnTokenAmount, totalBurntAmount);
    }

    function _burnToken(address token, uint256 amount) internal {
        if (!tokensToBurn[token]) revert NonRedeemableToken(token);

        // Just send the token to the burn address directly.
        IERC20Upgradeable(token).safeTransferFrom(msg.sender, BURN_ADDRESS, amount);
    }

    function _sendMessage(bytes memory messageData, bytes memory additionalData) internal virtual {}

    /////////////////////////////////////////////
    //             Owner Functions             //
    /////////////////////////////////////////////

    /// @notice Function to add multiple burn tokens.
    /// @param burnTokens Array of tokens allowed to be burnt to be added.
    function addBurnTokens(address[] memory burnTokens) external onlyOwner {
        for (uint256 i; i < burnTokens.length; ++i) {
            addBurnToken(burnTokens[i]);
        }
    }

    /// @notice Function to add a burn token.
    /// @dev Returns if the token is already added.
    /// @param burnToken Token allowed to be burnt to be added.
    function addBurnToken(address burnToken) public onlyOwner {
        if (tokensToBurn[burnToken]) return;

        tokensToBurn[burnToken] = true;

        emit BurnTokenAdded(burnToken);
    }

    /// @notice Function to remove multiple burn tokens.
    /// @param burnTokens Array of tokens allowed to be burnt to be removed.
    function removeBurnTokens(address[] memory burnTokens) external onlyOwner {
        for (uint256 i; i < burnTokens.length; ++i) {
            removeBurnToken(burnTokens[i]);
        }
    }

    /// @notice Function to remove a burn token.
    /// @dev Returns if the token is already removed.
    /// @param burnToken Token allowed to be burnt to be removed.
    function removeBurnToken(address burnToken) public onlyOwner {
        if (!tokensToBurn[burnToken]) return;

        tokensToBurn[burnToken] = false;

        emit BurnTokenRemoved(burnToken);
    }

    /// @notice Function to set the L2 comptroller address deployed on Optimism.
    /// @dev This function needs to be called after deployment of both the contracts.
    /// @param newL2Comptroller Address of the newly deployed L2 comptroller.
    function setL2Comptroller(address newL2Comptroller) external onlyOwner {
        if (newL2Comptroller == address(0)) revert ZeroAddress();

        l2Comptroller = newL2Comptroller;

        emit L2ComptrollerSet(newL2Comptroller);
    }

    /// @notice Function to withdraw tokens in an emergency situation.
    /// @param token Address of the token to be withdrawn.
    /// @param amount Amount of the `token` to be removed.
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
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

    uint256[46] private __gap;
}
