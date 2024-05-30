// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {ICrossDomainMessenger} from "./interfaces/ICrossDomainMessenger.sol";
import {IPoolLogic} from "./interfaces/IPoolLogic.sol";

/// @title L2 comptroller contract for token buy backs.
/// @notice This contract supports buyback claims raised from the L1 comptroller.
/// @author dHEDGE
contract L2Comptroller is OwnableUpgradeable, PausableUpgradeable {
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

    /////////////////////////////////////////////
    //                Events                   //
    /////////////////////////////////////////////

    event l1ComptrollerSet(address newL1Comptroller);
    event BuyTokenPriceUpdated(uint256 updatedBuyTokenPrice);
    event ModifiedMaxTokenPriceDrop(uint256 newMaxTokenPriceDrop);
    event EmergencyWithdrawal(address indexed token, uint256 amount);
    event RequireErrorDuringBuyBack(address indexed depositor, string reason);
    event AssertionErrorDuringBuyBack(
        address indexed depositor,
        uint256 errorCode
    );
    event LowLevelErrorDuringBuyBack(address indexed depositor, bytes reason);
    event TokensClaimed(
        address indexed depositor,
        address indexed receiver,
        uint256 burnTokenAmount,
        uint256 buyTokenAmount
    );

    /////////////////////////////////////////////
    //                 Errors                  //
    /////////////////////////////////////////////

    error ZeroAddress();
    error InvalidValues();
    error ZeroTokenPrice();
    error OnlyCrossChainAllowed();
    error ExternalCallerNotAllowed();
    error PriceDropExceedsLimit(
        uint256 minAcceptablePrice,
        uint256 actualPrice
    );
    error ExceedingClaimableAmount(
        address depositor,
        uint256 maxClaimableAmount,
        uint256 claimAmount
    );
    error DecreasingBurntAmount(
        address depositor,
        uint256 prevBurntAmount,
        uint256 givenBurntAmount
    );

    /////////////////////////////////////////////
    //                Variables                //
    /////////////////////////////////////////////

    /// @notice Denominator for bps calculations.
    uint256 public constant DENOMINATOR = 10_000;

    /// @notice The Optimism contract to interact with for sending/verifying data to/from L1
    ///         using smart contracts.
    ICrossDomainMessenger public crossDomainMessenger;

    /// @notice Address of the L1 comptroller which is allowed for cross chain buy-backs.
    /// @dev Has to be set after deployment of both the contracts.
    address public l1Comptroller;

    /// @notice Multi-sig wallet used to bridge tokens from L2 to L1 and burn them there.
    address public burnMultiSig;

    /// @notice Stores the exchange price of a `tokenToBurn` in $ terms.
    mapping(address tokenToBurn => uint256 exchangePrice) public exchangePrices;

    /// @notice Stores the last price of a `tokenToBuy` and the max price drop allowed.
    mapping(IPoolLogic tokenToBuy => BuyTokenDetails buyTokenDetails)
        public buyTokenDetails;

    /// @notice Stores the amount of `tokenToBurn` burnt on L1 and claimed on L2.
    /// @dev This allows us to revert transactions if a user is trying to claim `buyTokens` multiple
    ///      times via L1. Also allows us to recover in case cross-chain calls don't work.
    mapping(address depositor => mapping(address tokenToBurn => BurnAndClaimDetails burnAndClaimDetails))
        public burnAndClaimDetails;

    /////////////////////////////////////////////
    //                Functions                //
    /////////////////////////////////////////////

    /// @dev To prevent the implementation contract from being used, we invoke the _disableInitializers
    /// function in the constructor to automatically lock it when it is deployed.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice The initialization function for this contract.
    /// @param _crossDomainMessenger The cross domain messenger contract on L2.
    /// @param _burnMultiSig The multi-sig address used to bridge `_tokenToBurn` to L1 and burn there.
    function initialize(
        ICrossDomainMessenger _crossDomainMessenger,
        address _burnMultiSig
    ) external initializer {
        if (
            _burnMultiSig == address(0) ||
            address(_crossDomainMessenger) == address(0)
        ) revert ZeroAddress();

        // Initialize ownable contract.
        __Ownable_init();

        // Initialize Pausable contract.
        __Pausable_init();

        crossDomainMessenger = _crossDomainMessenger;
        burnMultiSig = _burnMultiSig;
    }

    /// @notice Function which allows buy back from L1 without bridging tokens.
    /// @dev This function can only be called by Optimism's CrossDomainMessenger contract on L2 and the call should have originated
    ///      from the l1Comptroller contract on L1.
    /// @param tokenBurned Address of the token burnt on L1.
    /// @param tokenToBuy Address of the token to be bought.
    /// @param l1Depositor The address which burned `totalAmountBurntOnL1` of `tokenToBurn` on L1.
    /// @param receiver Address of the receiver of the `tokenToBuy`.
    /// @param totalAmountBurntOnL1 Cumulative sum of tokens burnt on L1 by `l1Depositor`.
    function buyBackFromL1(
        address tokenBurned,
        address tokenToBuy,
        uint256 totalAmountBurntOnL1,
        address l1Depositor,
        address receiver
    ) external whenNotPaused {
        // The caller should be the cross domain messenger contract of Optimism
        // and the call should be initiated by our comptroller contract on L1.
        if (
            msg.sender != address(crossDomainMessenger) ||
            crossDomainMessenger.xDomainMessageSender() != l1Comptroller
        ) revert OnlyCrossChainAllowed();

        // `totalAmountClaimed` is of the `tokenToBurn` denomination.
        uint256 totalAmountClaimed = burnAndClaimDetails[l1Depositor][
            tokenBurned
        ].totalAmountClaimed;

        // The difference of both these variables tell us the claimable token amount in `tokenToBurn`
        // denomination.
        uint256 burnTokenAmount = totalAmountBurntOnL1 - totalAmountClaimed;

        if (burnTokenAmount == 0) {
            revert ExceedingClaimableAmount(l1Depositor, 0, 0);
        }

        uint256 prevBurntAmount = burnAndClaimDetails[l1Depositor][tokenBurned]
            .totalAmountBurned;

        // This check prevents replay attacks due to the Optimism bridge architecture which allows for failed transactions to
        // be replayed. For more info, check: https://github.com/dhedge/buyback-contract/issues/11
        if (totalAmountBurntOnL1 < prevBurntAmount) {
            revert DecreasingBurntAmount(
                l1Depositor,
                prevBurntAmount,
                totalAmountBurntOnL1
            );
        }

        // Store the new total amount of tokens burnt on L1 and claimed against on L2.
        burnAndClaimDetails[l1Depositor][tokenBurned]
            .totalAmountBurned = totalAmountBurntOnL1;

        // The reason we are using try-catch block is that we want to store the `totalAmountBurntOnL1`
        // regardless of the failure of the `_buyBack` function. This allows for the depositor
        // to claim their share on L2 later.
        try this._buyBack(receiver, burnTokenAmount) returns (
            uint256 buyTokenAmount
        ) {
            // Updating the amount claimed against the tokens burnt by the `l1Depositor`.
            burnAndClaimDetails[l1Depositor][tokenBurned]
                .totalAmountClaimed += burnTokenAmount;

            emit TokensClaimed(
                l1Depositor,
                receiver,
                burnTokenAmount,
                buyTokenAmount
            );
        } catch Error(string memory reason) {
            // This is executed in case revert was called and a reason string was provided.
            emit RequireErrorDuringBuyBack(l1Depositor, reason);
        } catch Panic(uint256 errorCode) {
            // This is executed in case of a panic, i.e. a serious error like division by zero
            // or overflow. The error code can be used to determine the kind of error.
            emit AssertionErrorDuringBuyBack(l1Depositor, errorCode);
        } catch (bytes memory reason) {
            // This is executed in case revert() was used.
            emit LowLevelErrorDuringBuyBack(l1Depositor, reason);
        }

        // The cumulative token amount burnt and claimed against on L2 should never be less than
        // what's been burnt on L1. This indicates some serious issues.
        assert(totalAmountClaimed <= totalAmountBurntOnL1);
    }

    /// @notice Function to claim all the claimable `tokenToBuy` tokens of a depositor.
    /// @dev A depositor is an address which has burnt tokens on L1 (using l1Comptroller).
    function claimAll(
        address tokenBurned,
        IPoolLogic tokenToBuy,
        address receiver
    ) external {
        // The difference between burnt amount and previously claimed amount gives us
        // the claimable amount in `tokenToBurn` denomination.
        claim(
            tokenBurned,
            tokenToBuy,
            burnAndClaimDetails[msg.sender][tokenBurned].totalAmountBurned -
                burnAndClaimDetails[msg.sender][tokenBurned].totalAmountClaimed,
            receiver
        );
    }

    /// @notice Function to claim any `amount` of `tokenToBuy` on L2.
    /// @param receiver Receiver of the `tokenToBuy` claim.
    /// @param burnTokenAmount Amount of `tokenToBurn` to claim against.
    /// @dev Use `convertToTokenToBurn` to get the proper `amount`.
    function claim(
        address tokenBurned,
        IPoolLogic tokenToBuy,
        uint256 burnTokenAmount,
        address receiver
    ) public whenNotPaused {
        // `totalAmountClaimed` is of the `tokenToBurn` denomination.
        uint256 totalAmountClaimed = burnAndClaimDetails[msg.sender][
            tokenBurned
        ].totalAmountClaimed;
        uint256 totalAmountBurntOnL1 = burnAndClaimDetails[msg.sender][
            tokenBurned
        ].totalAmountBurned;

        // The difference of both these variables tells us the remaining claimable token amount in `tokenToBurn`
        // denomination.
        uint256 remainingBurnTokenAmount = totalAmountBurntOnL1 -
            totalAmountClaimed;

        // Will revert in case there are no tokens remaining to be claimed by the user or the amount they
        // asked for exceeds their claimable amount.
        if (
            burnTokenAmount > remainingBurnTokenAmount ||
            remainingBurnTokenAmount == 0
        )
            revert ExceedingClaimableAmount(
                msg.sender,
                remainingBurnTokenAmount,
                burnTokenAmount
            );

        // Updating the amount claimed against the tokens burnt by the `msg.sender` on L1.
        burnAndClaimDetails[msg.sender][tokenBurned]
            .totalAmountClaimed += burnTokenAmount;

        uint256 buyTokenAmount = this._buyBack(
            tokenToBuy,
            burnTokenAmount,
            receiver
        );

        // The cumulative token amount burnt and claimed against on L2 should never be less than
        // what's been burnt on L1. This indicates some serious issues.
        assert(totalAmountClaimed <= totalAmountBurntOnL1);

        emit TokensClaimed(
            msg.sender,
            receiver,
            burnTokenAmount,
            buyTokenAmount
        );
    }

    /// @dev Although this is marked as an external function, it is meant to be only called by this contract.
    ///      The naming convention is deliberately unfollowed to semantically enforce the meaning.
    // solhint-disable-next-line private-vars-leading-underscore
    function _buyBack(
        address tokenBurned,
        IPoolLogic tokenToBuy,
        uint256 burnTokenAmount,
        address receiver
    ) external returns (uint256 buyTokenAmount) {
        if (msg.sender != address(this)) revert ExternalCallerNotAllowed();

        uint256 lastTokenToBuyPrice = buyTokenDetails[tokenToBuy]
            .lastTokenToBuyPrice;
        uint256 exchangePrice = exchangePrices[tokenBurned];
        uint256 tokenToBuyPrice = tokenToBuy.tokenPrice();
        uint256 minAcceptablePrice = lastTokenToBuyPrice -
            ((lastTokenToBuyPrice *
                buyTokenDetails[tokenToBuy].maxTokenPriceDrop) / DENOMINATOR);

        // If there is a sudden price drop possibly due to a depeg event,
        // we need to revert the transaction.
        if (tokenToBuyPrice < minAcceptablePrice)
            revert PriceDropExceedsLimit(minAcceptablePrice, tokenToBuyPrice);

        // Calculating how many buy tokens should be transferred to the caller.
        buyTokenAmount = (burnTokenAmount * exchangePrice) / tokenToBuyPrice;

        // Transfer the tokens to the caller.
        // We are deliberately not checking if this contract has enough tokens as
        // this would have the desired impact in case of low buy token balance anyway.
        IERC20Upgradeable(address(tokenToBuy)).safeTransfer(
            receiver,
            buyTokenAmount
        );

        // Updating the buy token price for future checks.
        if (lastTokenToBuyPrice < tokenToBuyPrice) {
            lastTokenToBuyPrice = tokenToBuyPrice;

            emit BuyTokenPriceUpdated(tokenToBuyPrice);
        }
    }

    /// @notice Function to get the amount of `tokenToBurn` that should be burned to
    ///         receive `amount` of `tokenToBuy`.
    /// @param tokenToBuy `tokenToBuy` token address.
    /// @param buyTokenAmount `tokenToBuy` amount to be converted.
    /// @return burnTokenAmount Amount converted to `tokenToBurn`.
    // TODO: Move to L1Comptroller
    function convertToTokenToBurn(
        address tokenToBurn,
        address tokenToBuy,
        uint256 buyTokenAmount
    ) public view returns (uint256 burnTokenAmount) {
        burnTokenAmount =
            (buyTokenAmount * tokenToBuy.tokenPrice()) /
            exchangePrices[tokenToBurn];
    }

    /// @notice Function to get the amount of `tokenToBuy` that can be claimed by burning `amount`
    ///         of `tokenToBurn`.
    /// @param burnTokenAmount `tokenToBurn` amount to be converted.
    /// @return buyTokenAmount Amount converted to `tokenToBuy`.
    // Move to L1Comptroller
    function convertToTokenToBuy(
        uint256 burnTokenAmount
    ) public view returns (uint256 buyTokenAmount) {
        buyTokenAmount =
            (burnTokenAmount * exchangePrice) /
            tokenToBuy.tokenPrice();
    }

    /// @notice Function to get the amount of `tokenToBuy` claimable by a depositor.
    /// @dev A depositor is an address which has burnt tokens on L1 (using l1Comptroller).
    /// @param depositor Address of the account which burnt tokens on L1.
    /// @return tokenToBuyClaimable The amount claimable by `depositor` in `tokenToBuy` denomination.
    // TODO: Check if this can be moved to L1Comptroller
    function getClaimableAmount(
        address depositor
    ) public view returns (uint256 tokenToBuyClaimable) {
        return
            convertToTokenToBuy(
                l1BurntAmountOf[depositor] - claimedAmountOf[depositor]
            );
    }

    /// @notice Function to get the max amount of `tokenToBurn` that can be burned and claimable
    ///         for `tokenToBuy`.
    /// @dev This function allows us to make assumptions about the success of the claim function.
    /// @dev This contract is expected to be containing a limited amount of `tokenToBuy` to begin with
    ///      and thus, we provide this function to calculate how much amount of `tokenToBurn` can be
    ///      claimable immediately.
    /// @return maxBurnTokenAmount Maximum `tokenToBurn` amount that can be burned.
    function maxBurnAmountClaimable()
        public
        view
        returns (uint256 maxBurnTokenAmount)
    {
        maxBurnTokenAmount = convertToTokenToBurn(
            tokenToBuy.balanceOf(address(this))
        );
    }

    /////////////////////////////////////////////
    //             Owner Functions             //
    /////////////////////////////////////////////

    /// @notice Function to set the L1 comptroller address of the comptroller deployed on Ethereum.
    /// @dev This function needs to be called after deployment of both the contracts.
    /// @param newL1Comptroller Address of the newly deployed L2 comptroller.
    function setL1Comptroller(address newL1Comptroller) external onlyOwner {
        if (newL1Comptroller == address(0)) revert ZeroAddress();

        l1Comptroller = newL1Comptroller;

        emit l1ComptrollerSet(newL1Comptroller);
    }

    /// @notice Function to modify the acceptable deviation from the last recorded price
    ///         of the `tokenToBuy`.
    /// @param newMaxTokenPriceDrop New value for deviation.
    function modifyThreshold(
        address tokenToBuy,
        uint256 newMaxTokenPriceDrop
    ) external onlyOwner {
        buyTokenDetails[tokenToBuy].maxTokenPriceDrop = newMaxTokenPriceDrop;

        emit ModifiedMaxTokenPriceDrop(newMaxTokenPriceDrop);
    }

    /// @notice Function to withdraw tokens in an emergency situation.
    /// @param token Address of the token to be withdrawn.
    /// @param amount Amount of the `token` to be removed.
    function emergencyWithdraw(
        address token,
        uint256 amount
    ) external onlyOwner {
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
}
