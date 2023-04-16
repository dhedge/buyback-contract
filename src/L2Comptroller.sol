// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Burnable} from "./interfaces/IERC20Burnable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {ICrossDomainMessenger} from "./interfaces/ICrossDomainMessenger.sol";
import {IPoolLogic} from "./interfaces/IPoolLogic.sol";

/// @title L2 comptroller contract for token buy backs.
/// @author dHEDGE
/// @dev This contract is only useful if paired with the L1 comptroller.
///      Users shouldn't interact with this contract directly.
contract L2Comptroller is OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event L1ComptrollerSet(address newL1Comptroller);
    event BuyTokenPriceUpdated(uint256 updatedBuyTokenPrice);
    event ModifiedMaxTokenPriceDrop(uint256 newMaxTokenPriceDrop);
    event EmergenWithdrawal(address indexed token, uint256 amount);
    event TokensBoughtOnL1(
        address indexed depositor,
        address indexed receiver,
        uint256 burnTokenAmount,
        uint256 buyTokenAmount
    );
    event TokensBoughtOnL2(
        address indexed depositor,
        address indexed receiver,
        uint256 burnTokenAmount,
        uint256 buyTokenAmount
    );

    error ZeroAddress();
    error InvalidValues();
    error ZeroTokenPrice();
    error OnlyCrossChainAllowed();
    error PriceDropExceedsLimit(
        uint256 minAcceptablePrice,
        uint256 actualPrice
    );
    error BuyTokenAlreadyClaimed(
        address l1Depositor,
        uint256 totalAmountClaimed
    );

    /// @notice Denominator for bps calculations.
    uint256 public constant DENOMINATOR = 10_000;

    /// @notice The Optimism contract to interact with for sending/verifying data to/from L1
    ///         using smart contracts.
    ICrossDomainMessenger public crossDomainMessenger;

    /// @notice Token to burn.
    /// @dev Should be a token which implements ERC20Burnable methods. MTA token does so in our case.
    IERC20Upgradeable public tokenToBurn;

    /// @notice Token to be redeemed for (token to buy).
    /// @dev In our case, this will be the dHEDGE pool token of the mStable treasury vault.
    IPoolLogic public tokenToBuy;

    /// @notice Address of the L1 comptroller which is allowed for cross chain buy-backs.
    /// @dev Has to be set after deployment of both the contracts.
    address public L1Comptroller;

    /// @notice Multi-sig wallet used to bridge tokens from L2 to L1 and burn them there.
    address public burnMultiSig;

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

    /// @notice Stores the amount of tokens bought back corresponding to the amount burnt on L1.
    /// @dev This allows us to revert transactions if a user is trying to claim `buyTokens` multiple
    ///      times via L1. Also allows us to recover in case cross-chain calls don't work.
    mapping(address depositor => uint256 totalAmount) public l1BurntAmountOf;

    /// @dev To prevent the implementation contract from being used, we invoke the _disableInitializers
    /// function in the constructor to automatically lock it when it is deployed.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        IERC20Upgradeable _tokenToBurn,
        IPoolLogic _tokenToBuy,
        address _burnMultiSig,
        uint256 _exchangePrice,
        uint256 _maxTokenPriceDrop
    ) external initializer {
        if (
            address(_tokenToBurn) == address(0) ||
            address(_tokenToBuy) == address(0) ||
            _burnMultiSig == address(0)
        ) revert ZeroAddress();

        if (
            _maxTokenPriceDrop > DENOMINATOR ||
            _exchangePrice == 0 ||
            _maxTokenPriceDrop == 0
        ) revert InvalidValues();

        // Initialize ownable contract.
        __Ownable_init();

        // Initialise Pausable contract.
        __Pausable_init();

        tokenToBurn = _tokenToBurn;
        tokenToBuy = _tokenToBuy;
        burnMultiSig = _burnMultiSig;
        exchangePrice = _exchangePrice;
        maxTokenPriceDrop = _maxTokenPriceDrop;

        uint256 tokenPrice = _tokenToBuy.tokenPrice();

        // If the token price is 0, revert the transaction as the pool isn't ready.
        if (lastTokenToBuyPrice == 0) revert ZeroTokenPrice();

        // Update the token price of the token to be bought.
        lastTokenToBuyPrice = tokenPrice;
    }

    /// @notice Function to exchange `tokenToBurn` for `tokenToBuy`.
    /// @param amount Amount of `tokenToBurn` to be burnt and exchanged.
    /// @return buyTokenAmount The amount of `tokenToBuy` bought.
    function buyBack(
        uint256 amount
    ) external whenNotPaused returns (uint256 buyTokenAmount) {
        // Transferring the `amount` of `tokenToBurn` to the burn multisig.
        tokenToBurn.safeTransferFrom(msg.sender, burnMultiSig, amount);

        buyTokenAmount = _buyBack(msg.sender, amount);

        emit TokensBoughtOnL2(msg.sender, msg.sender, amount, buyTokenAmount);
    }

    /// @notice Function to exchange `tokenToBurn` for `tokenToBuy`.
    /// @dev Added for the convenience of the end-users.
    /// @param receiver The receiver of the `tokenToBuy`.
    /// @param amount Amount of `tokenToBurn` to be burnt and exchanged.
    /// @return buyTokenAmount The amount of `tokenToBuy` bought.
    function buyBackAndTransfer(
        address receiver,
        uint256 amount
    ) external whenNotPaused returns (uint256 buyTokenAmount) {
        // Transferring the `amount` of `tokenToBurn` to the burn multisig.
        tokenToBurn.safeTransferFrom(msg.sender, burnMultiSig, amount);

        buyTokenAmount = _buyBack(receiver, amount);

        emit TokensBoughtOnL2(msg.sender, receiver, amount, buyTokenAmount);
    }

    function buyBackOnL1(
        address l1Depositor,
        address receiver,
        uint256 totalAmountBurntOnL1
    ) external whenNotPaused {
        // The caller should be the cross domain messenger contract of Optimism
        // and the call should be initiated by our comptroller contract on L1.
        if (
            msg.sender != address(crossDomainMessenger) ||
            crossDomainMessenger.xDomainMessageSender() != L1Comptroller
        ) revert OnlyCrossChainAllowed();

        uint256 totalAmountClaimed = l1BurntAmountOf[l1Depositor];

        // If the tokens have been claimed already then, revert the transaction.
        // This is necessary to be checked as the L1Comptroller doesn't know if the claims
        // have succeeded on L2 or not and hence can't revert the transaction on L1 itself.
        if (totalAmountClaimed == totalAmountBurntOnL1)
            revert BuyTokenAlreadyClaimed(l1Depositor, totalAmountBurntOnL1);

        // The cumulative token amount burnt and claimed against on L2 should never be less than
        // what's been burnt on L1. This indicates some serious issues exist.
        assert(totalAmountClaimed < totalAmountBurntOnL1);

        // The difference of both these variables tell us the actual tokens burnt in the latest transaction
        // on L1.
        uint256 burnTokenAmount = totalAmountBurntOnL1 - totalAmountClaimed;

        uint256 buyTokenAmount = _buyBack(receiver, burnTokenAmount);

        // Store the new total amount of tokens burnt on L1 and claimed against on L2.
        l1BurntAmountOf[l1Depositor] = totalAmountBurntOnL1;

        emit TokensBoughtOnL1(
            l1Depositor,
            receiver,
            burnTokenAmount,
            buyTokenAmount
        );
    }

    /// @notice Function to update the price of the `tokenToBuy`.
    /// @dev This function can be used to force update the buy token price to avoid price depeg.
    ///      This function only updates the price if the previous price was lesser than the current one.
    // QUESTION: Explore if this function is even required given the updates happen in the
    // `buyBackAndBurn` function.
    function updateBuyTokenPrice() external {
        uint256 tokenToBuyPrice = tokenToBuy.tokenPrice();

        if (tokenToBuyPrice > lastTokenToBuyPrice) {
            lastTokenToBuyPrice = tokenToBuyPrice;
        }
    }

    function _buyBack(
        address receiver,
        uint256 amount
    ) internal returns (uint256 buyTokenAmount) {
        uint256 tokenToBuyPrice = tokenToBuy.tokenPrice();

        uint256 minAcceptablePrice = lastTokenToBuyPrice -
            ((lastTokenToBuyPrice * maxTokenPriceDrop) / DENOMINATOR);

        // If there is a sudden price drop possibly due to a depeg event,
        // we need to revert the transaction.
        if (tokenToBuyPrice < minAcceptablePrice)
            revert PriceDropExceedsLimit(minAcceptablePrice, tokenToBuyPrice);

        // Calculating how many buy tokens should be transferred to the caller.
        buyTokenAmount = (amount * exchangePrice) / tokenToBuyPrice;

        // Transfer the tokens to the caller.
        IERC20Upgradeable(address(tokenToBuy)).safeTransfer(
            receiver,
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
    }

    /////////////////////////////////////////////
    //             Owner Functions             //
    /////////////////////////////////////////////

    function setL1Comptroller(address newL1Comptroller) external onlyOwner {
        if (newL1Comptroller == address(0)) revert ZeroAddress();

        L1Comptroller = newL1Comptroller;

        // Question: Do we really need to emit this? Ideally, this function should be used
        // only once.
        emit L1ComptrollerSet(newL1Comptroller);
    }

    /// @notice Function to modify the acceptable deviation from the last recorded price
    ///         of the `tokenToBuy`.
    /// @param newMaxTokenPriceDrop New value for deviation.
    function modifyThreshold(uint256 newMaxTokenPriceDrop) external onlyOwner {
        maxTokenPriceDrop = newMaxTokenPriceDrop;

        emit ModifiedMaxTokenPriceDrop(newMaxTokenPriceDrop);
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

        // If the balanceOf(address(this)) < `amount` < type(uint256).max then
        // the transfer will revert.
        tokenToWithdraw.safeTransfer(owner(), amount);

        emit EmergenWithdrawal(address(tokenToWithdraw), amount);
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
