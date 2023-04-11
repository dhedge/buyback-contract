// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IPoolLogic} from "./interfaces/IPoolLogic.sol";
import {IERC20Burnable} from "./interfaces/IERC20Burnable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";

/// @title MTA Buyback contract.
/// @author dHEDGE.
/// @notice mStable token (MTA) buyback and burn contract.
contract MTABuyBack is OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    error ZeroAddress();
    error PriceDropExceedsLimit(
        uint256 minAcceptablePrice,
        uint256 actualPrice
    );

    event TokensBoughtAndBurned(
        uint256 burnTokenAmount,
        uint256 buyTokenAmount
    );
    event BuyTokenPriceUpdated(uint256 updatedBuyTokenPrice);
    event ModifiedMaxTokenPriceDrop(uint256 newMaxTokenPriceDrop);

    /// @notice Denominator for bps calculations.
    uint256 public constant DENOMINATOR = 10_000;

    /// @notice Token to burn.
    /// @dev Should be a token which implements ERC20Burnable methods. MTA token does so in our case.
    IERC20Burnable public tokenToBurn;

    /// @notice Token to be redeemed for (token to buy).
    /// @dev In our case, this will be the dHEDGE pool token of the mStable treasury vault.
    IPoolLogic public tokenToBuy;

    /// @notice The exchange price for buyback.
    /// @dev Expecting 18 decimals for more precision.
    uint256 public exchangePrice;

    // TODO: Explore if setting a minimum price in the constructor makes sense.
    // Probably by querying the pool price in the constructor and setting the return value
    // as the `lastTokenToBuyPrice`.
    /// @notice The token price of `tokenToBuy` last time it was updated.
    /// @dev The updates happen every time tokens are burned.
    uint256 public lastTokenToBuyPrice;

    /// @notice The acceptable price drop percentage of the `tokenToBuy`.
    uint256 public maxTokenPriceDrop;

    /// @dev To prevent the implementation contract from being used, we invoke the _disableInitializers 
    /// function in the constructor to automatically lock it when it is deployed.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        IERC20Burnable _tokenToBurn,
        IPoolLogic _tokenToBuy,
        uint256 _exchangePrice,
        uint256 _maxTokenPriceDrop
    ) external initializer {
        if (
            address(_tokenToBurn) == address(0) ||
            address(_tokenToBuy) == address(0)
        ) revert ZeroAddress();

        __Ownable_init();
        __Pausable_init();

        // TODO: Explore requirement of checks for other two parameters.

        tokenToBurn = _tokenToBurn;
        tokenToBuy = _tokenToBuy;
        exchangePrice = _exchangePrice;
        maxTokenPriceDrop = _maxTokenPriceDrop;

        // Update the token price of the token to be bought.
        lastTokenToBuyPrice = _tokenToBuy.tokenPrice();
    }

    /// @notice Function to exchange `tokenToBurn` for `tokenToBuy`.
    /// @param amount Amount of `tokenToBurn` to be burnt and exchanged.
    /// @return buyTokenAmount The amount of `tokenToBuy` bought.
    function buyBackAndBurn(
        uint256 amount
    ) external whenNotPaused returns (uint256 buyTokenAmount) {
        uint256 tokenToBuyPrice = tokenToBuy.tokenPrice();

        uint256 minAcceptablePrice = lastTokenToBuyPrice -
            ((lastTokenToBuyPrice * maxTokenPriceDrop) / DENOMINATOR);

        // If there is a sudden price drop possibly due to a depeg event,
        // we need to revert the transaction.
        if (tokenToBuyPrice < minAcceptablePrice)
            revert PriceDropExceedsLimit(minAcceptablePrice, tokenToBuyPrice);

        // Burning the `amount` tokens held by the user without transferring them to
        // this contract first. This functionality is provided by the `ERC20Burnable` contract.
        // TODO: Explore if any low level calls are required to verify nothing failed silently.
        tokenToBurn.burnFrom(msg.sender, amount);

        // Calculating how many buy tokens should be transferred to the caller.
        buyTokenAmount = (amount * exchangePrice) / tokenToBuyPrice;

        // Transfer the tokens to the caller.
        IERC20Upgradeable(address(tokenToBuy)).safeTransfer(
            msg.sender,
            buyTokenAmount
        );

        // Updating the buy token price for future checks.
        // TODO: Explore if an update should take place if there is a price deviation within
        // a pre-defined threshold.
        if (lastTokenToBuyPrice < tokenToBuyPrice) {
            lastTokenToBuyPrice = tokenToBuyPrice;

            // TODO: Explore if this event emission is required or not.
            emit BuyTokenPriceUpdated(tokenToBuyPrice);
        }

        emit TokensBoughtAndBurned(amount, buyTokenAmount);
    }

    /// @notice Function to update the price of the `tokenToBuy`.
    /// @dev This function can be used to force update the buy token price to avoid price depeg.
    ///      This function only updates the price if the previous price was lesser than the current one.
    // TODO: Explore if this function is even required given the updates happen in the
    // `buyBackAndBurn` function.
    function updateBuyTokenPrice() external {
        uint256 tokenToBuyPrice = tokenToBuy.tokenPrice();

        if (tokenToBuyPrice > lastTokenToBuyPrice) {
            lastTokenToBuyPrice = tokenToBuyPrice;
        }
    }

    /////////////////////////////////////////////
    //             Owner Functions             //
    /////////////////////////////////////////////

    function modifyThreshold(uint256 newMaxTokenPriceDrop) external onlyOwner {
        maxTokenPriceDrop = newMaxTokenPriceDrop;
    }

    /// @notice Function to withdraw tokens in an emergency situation.
    /// @param token Address of the token to be withdrawn.
    /// @param amount Amount of the `token` to be removed.
    // TODO: Rug pull protection?
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
