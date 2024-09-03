// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {ICrossDomainMessenger} from "../interfaces/ICrossDomainMessenger.sol";
import {IPoolLogic} from "../interfaces/IPoolLogic.sol";

/// @title L2 comptroller contract for token buy backs or redemptions of one asset for another.
/// @notice This contract supports redemption claims raised from the L1 comptroller.
/// @dev This contract is specifically designed to work with dHEDGE pool tokens.
/// @author dHEDGE
abstract contract L2ComptrollerV2Base is OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /////////////////////////////////////////////
    //                Structs                  //
    /////////////////////////////////////////////

    struct BurnAndClaimDetails {
        uint256 totalAmountBurned;
        uint256 totalAmountClaimed;
    }

    struct BuyTokenDetails {
        uint256 lastTokenToBuyPrice;
        uint256 maxTokenPriceDrop;
    }

    struct BurnTokenSettings {
        address tokenToBurn;
        uint256 exchangePrice;
    }

    struct BuyTokenSettings {
        IPoolLogic tokenToBuy;
        uint256 maxTokenPriceDrop;
    }

    /////////////////////////////////////////////
    //                Events                   //
    /////////////////////////////////////////////

    event L1ComptrollerSet(address newL1Comptroller);
    event BuyTokenPriceUpdated(IPoolLogic buyToken, uint256 updatedBuyTokenPrice);
    event ModifiedMaxTokenPriceDrop(IPoolLogic buyToken, uint256 newMaxTokenPriceDrop);
    event EmergencyWithdrawal(address indexed token, uint256 amount);
    event RequireErrorDuringRedemption(address indexed depositor, string reason);
    event AssertionErrorDuringRedemption(address indexed depositor, uint256 errorCode);
    event LowLevelErrorDuringRedemption(address indexed depositor, bytes reason);
    event TokensClaimed(
        address indexed depositor,
        address indexed receiver,
        address tokenBurned,
        IPoolLogic tokenBought,
        uint256 burnTokenAmount,
        uint256 buyTokenAmount
    );

    /////////////////////////////////////////////
    //                 Errors                  //
    /////////////////////////////////////////////

    error ZeroAddress();
    error InvalidValues();
    error OnlyCrossChainAllowed();
    error ExternalCallerNotAllowed();
    error ZeroTokenPrice(IPoolLogic tokenToBuy);
    error PriceDropExceedsLimit(IPoolLogic buyToken, uint256 minAcceptablePrice, uint256 actualPrice);
    error ExceedingClaimableAmount(
        address depositor,
        address receiver,
        address tokenBurned,
        uint256 maxClaimableAmount,
        uint256 claimAmount
    );
    error DecreasingBurntAmount(
        address depositor,
        address receiver,
        address tokenBurned,
        uint256 prevBurntAmount,
        uint256 givenBurntAmount
    );

    /////////////////////////////////////////////
    //                Variables                //
    /////////////////////////////////////////////

    /// @notice Denominator for bps calculations.
    uint256 public constant DENOMINATOR = 10_000;

    /// @notice Address of the L1 comptroller which is allowed for cross chain buy-backs.
    /// @dev Has to be set after deployment of both the contracts.
    address public l1Comptroller;

    /// @notice Stores the exchange price of a `tokenToBurn` in $ terms.
    mapping(address tokenToBurn => uint256 exchangePrice) public exchangePrices;

    /// @notice Stores the last price of a `tokenToBuy` and the max price drop allowed.
    mapping(IPoolLogic tokenToBuy => BuyTokenDetails buyTokenDetails) public buyTokenDetails;

    /// @notice Stores the amount of `tokenToBurn` burnt on L1 and claimed on L2.
    /// @dev This allows us to revert transactions if a user is trying to claim `buyTokens` multiple
    ///      times via L1. Also allows us to recover in case cross-chain calls don't work.
    mapping(address depositor => mapping(address receiver => mapping(address tokenToBurn => BurnAndClaimDetails burnAndClaimDetails)))
        public burnAndClaimDetails;

    /////////////////////////////////////////////
    //                Functions                //
    /////////////////////////////////////////////

    /// @notice Function which allows buy back/redemption from L1 without bridging tokens.
    /// @dev This function can only be called by Optimism's CrossDomainMessenger contract on L2 and the call should have originated
    ///      from the l1Comptroller contract on L1.
    /// @param tokenBurned Address of the token burnt on L1.
    /// @param tokenToBuy Address of the token to be bought.
    /// @param totalAmountBurntOnL1 Cumulative sum of tokens burnt on L1 by `l1Depositor`.
    /// @param l1Depositor The address which burned `totalAmountBurntOnL1` of `tokenToBurn` on L1.
    /// @param receiver Address of the receiver of the `tokenToBuy`.
    function redeemFromL1(
        address tokenBurned,
        address tokenToBuy,
        uint256 totalAmountBurntOnL1,
        address l1Depositor,
        address receiver
    ) external whenNotPaused {
        _preRedemptionChecks();

        // `totalAmountClaimed` is of the `tokenToBurn` denomination.
        uint256 totalAmountClaimed = burnAndClaimDetails[l1Depositor][receiver][tokenBurned].totalAmountClaimed;

        // The difference of both these variables tell us the claimable token amount in `tokenToBurn`
        // denomination.
        uint256 burnTokenAmount = totalAmountBurntOnL1 - totalAmountClaimed;

        if (burnTokenAmount == 0) {
            revert ExceedingClaimableAmount(l1Depositor, receiver, tokenBurned, 0, 0);
        }

        uint256 prevBurntAmount = burnAndClaimDetails[l1Depositor][receiver][tokenBurned].totalAmountBurned;

        // This check prevents replay attacks due to the Optimism bridge architecture which allows for failed transactions to
        // be replayed. For more info, check: https://github.com/dhedge/buyback-contract/issues/11
        if (totalAmountBurntOnL1 < prevBurntAmount) {
            revert DecreasingBurntAmount(l1Depositor, receiver, tokenBurned, prevBurntAmount, totalAmountBurntOnL1);
        }

        // Store the new total amount of tokens burnt on L1 and claimed against on L2.
        burnAndClaimDetails[l1Depositor][receiver][tokenBurned].totalAmountBurned = totalAmountBurntOnL1;

        // The reason we are using try-catch block is that we want to store the `totalAmountBurntOnL1`
        // regardless of the failure of the `_redeem` function. This allows for the depositor
        // to claim their share on L2 later.
        try this._redeem(tokenBurned, IPoolLogic(tokenToBuy), burnTokenAmount, receiver) returns (
            uint256 buyTokenAmount
        ) {
            // Updating the amount claimed against the tokens burnt by the `l1Depositor`.
            burnAndClaimDetails[l1Depositor][receiver][tokenBurned].totalAmountClaimed += burnTokenAmount;

            emit TokensClaimed(
                l1Depositor,
                receiver,
                tokenBurned,
                IPoolLogic(tokenToBuy),
                burnTokenAmount,
                buyTokenAmount
            );
        } catch Error(string memory reason) {
            // This is executed in case revert was called and a reason string was provided.
            emit RequireErrorDuringRedemption(l1Depositor, reason);
        } catch Panic(uint256 errorCode) {
            // This is executed in case of a panic, i.e. a serious error like division by zero
            // or overflow. The error code can be used to determine the kind of error.
            emit AssertionErrorDuringRedemption(l1Depositor, errorCode);
        } catch (bytes memory reason) {
            // This is executed in case revert() was used.
            emit LowLevelErrorDuringRedemption(l1Depositor, reason);
        }

        // The cumulative token amount burnt and claimed against on L2 should never be less than
        // what's been burnt on L1. This indicates some serious issues.
        assert(totalAmountClaimed <= totalAmountBurntOnL1);
    }

    /// @notice Function to claim all the claimable `tokenToBuy` tokens of a depositor.
    /// @param tokenBurned Address of the token burnt on L1.
    /// @param tokenToBuy Address of the token to be bought.
    /// @param l1Depositor Address of the account which burnt tokens on L1.
    /// @dev A depositor is an address which has burnt tokens on L1 (using l1Comptroller).
    function claimAll(address tokenBurned, IPoolLogic tokenToBuy, address l1Depositor) external {
        // The difference between burnt amount and previously claimed amount gives us
        // the claimable amount in `tokenToBurn` denomination.
        claim(
            tokenBurned,
            tokenToBuy,
            burnAndClaimDetails[l1Depositor][msg.sender][tokenBurned].totalAmountBurned -
                burnAndClaimDetails[l1Depositor][msg.sender][tokenBurned].totalAmountClaimed,
            l1Depositor
        );
    }

    /// @notice Function to claim any `amount` of `tokenToBuy` on L2.
    /// @param tokenBurned Address of the token burnt on L1.
    /// @param tokenToBuy Address of the token to be bought.
    /// @param burnTokenAmount Amount of `tokenToBurn` to claim against.
    /// @param l1Depositor Address of the account which burnt tokens on L1.
    /// @dev Note that the `l1Depositor` should have passed the `msg.sender` address as receiver while burning on L1.
    /// @dev Use `convertToTokenToBurn` to get the proper `amount`.
    function claim(
        address tokenBurned,
        IPoolLogic tokenToBuy,
        uint256 burnTokenAmount,
        address l1Depositor
    ) public whenNotPaused {
        // `totalAmountClaimed` is of the `tokenToBurn` denomination.
        uint256 totalAmountClaimed = burnAndClaimDetails[l1Depositor][msg.sender][tokenBurned].totalAmountClaimed;
        uint256 totalAmountBurntOnL1 = burnAndClaimDetails[l1Depositor][msg.sender][tokenBurned].totalAmountBurned;

        // The difference of both these variables tells us the remaining claimable token amount in `tokenToBurn`
        // denomination.
        uint256 remainingBurnTokenAmount = totalAmountBurntOnL1 - totalAmountClaimed;

        // Will revert in case there are no tokens remaining to be claimed by the user or the amount they
        // asked for exceeds their claimable amount.
        if (burnTokenAmount > remainingBurnTokenAmount || remainingBurnTokenAmount == 0)
            revert ExceedingClaimableAmount(
                l1Depositor,
                msg.sender,
                tokenBurned,
                remainingBurnTokenAmount,
                burnTokenAmount
            );

        // Updating the amount claimed against the tokens burnt by the `msg.sender` on L1.
        burnAndClaimDetails[l1Depositor][msg.sender][tokenBurned].totalAmountClaimed += burnTokenAmount;

        uint256 buyTokenAmount = this._redeem(tokenBurned, tokenToBuy, burnTokenAmount, msg.sender);

        // The cumulative token amount burnt and claimed against on L2 should never be less than
        // what's been burnt on L1. This indicates some serious issues.
        assert(totalAmountClaimed <= totalAmountBurntOnL1);

        emit TokensClaimed(l1Depositor, msg.sender, tokenBurned, tokenToBuy, burnTokenAmount, buyTokenAmount);
    }

    /// @dev Although this is marked as an external function, it is meant to be only called by this contract.
    ///      The naming convention is ignored to semantically enforce the meaning.
    // solhint-disable-next-line private-vars-leading-underscore
    function _redeem(
        address tokenBurned,
        IPoolLogic tokenToBuy,
        uint256 burnTokenAmount,
        address receiver
    ) external returns (uint256 buyTokenAmount) {
        if (msg.sender != address(this)) revert ExternalCallerNotAllowed();

        // The following can be true if the token is not added to the buy list.
        if (buyTokenDetails[tokenToBuy].lastTokenToBuyPrice == 0) revert ZeroTokenPrice(tokenToBuy);

        uint256 lastTokenToBuyPrice = buyTokenDetails[tokenToBuy].lastTokenToBuyPrice;
        uint256 exchangePrice = exchangePrices[tokenBurned];
        uint256 tokenToBuyPrice = tokenToBuy.tokenPrice();
        uint256 minAcceptablePrice = lastTokenToBuyPrice -
            ((lastTokenToBuyPrice * buyTokenDetails[tokenToBuy].maxTokenPriceDrop) / DENOMINATOR);

        // If there is a sudden price drop possibly due to a depeg event,
        // we need to revert the transaction.
        if (tokenToBuyPrice < minAcceptablePrice)
            revert PriceDropExceedsLimit(tokenToBuy, minAcceptablePrice, tokenToBuyPrice);

        // Calculating how many buy tokens should be transferred to the caller.
        buyTokenAmount = (burnTokenAmount * exchangePrice) / tokenToBuyPrice;

        // Transfer the tokens to the caller.
        // We are deliberately not checking if this contract has enough tokens as
        // this would have the desired impact in case of low buy token balance anyway.
        IERC20Upgradeable(address(tokenToBuy)).safeTransfer(receiver, buyTokenAmount);

        // Updating the buy token price for future checks.
        if (lastTokenToBuyPrice < tokenToBuyPrice) {
            lastTokenToBuyPrice = tokenToBuyPrice;

            emit BuyTokenPriceUpdated(tokenToBuy, tokenToBuyPrice);
        }
    }

    /// @notice Function to get the amount of `tokenToBurn` that should be burned to
    ///         receive `amount` of `tokenToBuy`.
    /// @param tokenToBurn Address of the token burned on L1.
    /// @param tokenToBuy `tokenToBuy` token address.
    /// @param buyTokenAmount `tokenToBuy` amount to be converted.
    /// @return burnTokenAmount Amount converted to `tokenToBurn`.
    function convertToTokenToBurn(
        address tokenToBurn,
        IPoolLogic tokenToBuy,
        uint256 buyTokenAmount
    ) public view returns (uint256 burnTokenAmount) {
        burnTokenAmount = (buyTokenAmount * tokenToBuy.tokenPrice()) / exchangePrices[tokenToBurn];
    }

    /// @notice Function to get the amount of `tokenToBuy` that can be claimed by burning `amount`
    ///         of `tokenToBurn`.
    /// @param burnTokenAmount `tokenToBurn` amount to be converted.
    /// @return buyTokenAmount Amount converted to `tokenToBuy`.
    function convertToTokenToBuy(
        address tokenToBurn,
        IPoolLogic tokenToBuy,
        uint256 burnTokenAmount
    ) public view returns (uint256 buyTokenAmount) {
        buyTokenAmount = (burnTokenAmount * exchangePrices[tokenToBurn]) / tokenToBuy.tokenPrice();
    }

    /// @notice Function to get the amount of `tokenToBuy` claimable by a depositor.
    /// @dev A depositor is an address which has burnt tokens on L1 (using l1Comptroller).
    /// @param tokenBurned Address of the token burnt on L1.
    /// @param tokenToBuy `tokenToBuy` token address.
    /// @param depositor Address of the account which burnt tokens on L1.
    /// @param receiver Address of the receiver of the `tokenToBuy`.
    /// @return tokenToBuyClaimable The amount claimable by `depositor` in `tokenToBuy` denomination.
    function getClaimableAmount(
        address tokenBurned,
        IPoolLogic tokenToBuy,
        address depositor,
        address receiver
    ) public view returns (uint256 tokenToBuyClaimable) {
        return
            convertToTokenToBuy(
                tokenBurned,
                tokenToBuy,
                burnAndClaimDetails[depositor][receiver][tokenBurned].totalAmountBurned -
                    burnAndClaimDetails[depositor][receiver][tokenBurned].totalAmountClaimed
            );
    }

    /// @notice Function to get the max amount of `tokenToBurn` that can be burned and claimable
    ///         for `tokenToBuy`.
    /// @dev This function allows us to make assumptions about the success of the claim function.
    /// @dev This contract is expected to be containing a limited amount of `tokenToBuy` to begin with
    ///      and thus, we provide this function to calculate how much amount of `tokenToBurn` can be
    ///      claimable immediately.
    /// @param tokenToBurn Address of the token burned on L1.
    /// @param tokenToBuy `tokenToBuy` token address.
    /// @return maxBurnTokenAmount Maximum `tokenToBurn` amount that can be burned.
    function maxBurnAmountClaimable(
        address tokenToBurn,
        IPoolLogic tokenToBuy
    ) public view returns (uint256 maxBurnTokenAmount) {
        return convertToTokenToBurn(tokenToBurn, tokenToBuy, tokenToBuy.balanceOf(address(this)));
    }

    /// @dev Function to be called before the redemption process.
    /// @dev Can be used to determine if a redemption call is valid or not (caller must be L1Comptroller and so on).
    /// @dev Should revert if the redemption call is invalid.
    function _preRedemptionChecks() internal view virtual {}

    /////////////////////////////////////////////
    //             Owner Functions             //
    /////////////////////////////////////////////

    /// @notice Function to set the exchange prices for multiple `tokenToBurn` tokens.
    /// @param burnTokenSettings Array of `BurnTokenSettings` struct.
    function setExchangePrices(BurnTokenSettings[] memory burnTokenSettings) external onlyOwner {
        for (uint256 i; i < burnTokenSettings.length; ++i) {
            setExchangePrices(burnTokenSettings[i]);
        }
    }

    /// @notice Function to add multiple `tokenToBuy` tokens.
    /// @param buyTokenSettings The array of `BuyTokenSettings` struct.
    function addBuyTokens(BuyTokenSettings[] memory buyTokenSettings) external onlyOwner {
        for (uint256 i; i < buyTokenSettings.length; ++i) {
            addBuyToken(buyTokenSettings[i]);
        }
    }

    /// @notice Function to remove multiple `tokenToBuy` tokens.
    /// @param tokensToBuy Array of `IPoolLogic` type tokens.
    function removeBuyTokens(IPoolLogic[] memory tokensToBuy) external onlyOwner {
        for (uint256 i; i < tokensToBuy.length; ++i) {
            removeBuyToken(tokensToBuy[i]);
        }
    }

    /// @notice Function to set the exchange price for a `tokenToBurn` token.
    /// @param burnTokenSetting `BurnTokenSettings` struct.
    function setExchangePrices(BurnTokenSettings memory burnTokenSetting) public onlyOwner {
        exchangePrices[burnTokenSetting.tokenToBurn] = burnTokenSetting.exchangePrice;
    }

    /// @notice Function to add a `tokenToBuy` token.
    /// @param buyTokenSetting `BuyTokenSettings` struct which contains the token address and max price drop.
    function addBuyToken(BuyTokenSettings memory buyTokenSetting) public onlyOwner {
        uint256 tokenPrice = buyTokenSetting.tokenToBuy.tokenPrice();

        if (tokenPrice == 0) revert ZeroTokenPrice(buyTokenSetting.tokenToBuy);

        buyTokenDetails[buyTokenSetting.tokenToBuy] = BuyTokenDetails({
            lastTokenToBuyPrice: tokenPrice,
            maxTokenPriceDrop: buyTokenSetting.maxTokenPriceDrop
        });
    }

    /// @notice Function to remove a `tokenToBuy` token.
    /// @param tokenToBuy Address of the token to be removed.
    function removeBuyToken(IPoolLogic tokenToBuy) public onlyOwner {
        delete buyTokenDetails[tokenToBuy];
    }

    /// @notice Function to set the L1 comptroller address of the comptroller deployed on Ethereum.
    /// @dev This function needs to be called after deployment of both the contracts.
    /// @param newL1Comptroller Address of the newly deployed L2 comptroller.
    function setL1Comptroller(address newL1Comptroller) external onlyOwner {
        if (newL1Comptroller == address(0)) revert ZeroAddress();

        l1Comptroller = newL1Comptroller;

        emit L1ComptrollerSet(newL1Comptroller);
    }

    /// @notice Function to modify the acceptable deviation from the last recorded price
    ///         of the `tokenToBuy`.
    /// @param tokenToBuy Address of the token to be modified.
    /// @param newMaxTokenPriceDrop New value for deviation.
    function modifyThreshold(IPoolLogic tokenToBuy, uint256 newMaxTokenPriceDrop) external onlyOwner {
        buyTokenDetails[tokenToBuy].maxTokenPriceDrop = newMaxTokenPriceDrop;

        emit ModifiedMaxTokenPriceDrop(tokenToBuy, newMaxTokenPriceDrop);
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

        // If the balanceOf(address(this)) < `amount` < type(uint256).max then
        // the transfer will revert.
        tokenToWithdraw.safeTransfer(owner(), amount);

        emit EmergencyWithdrawal(token, amount);
    }

    /// @notice Function to pause the critical functions in this contract.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Function to unpause the critical functions in this contract.
    function unpause() external onlyOwner {
        _unpause();
    }

    uint256[45] private __gap;
}
