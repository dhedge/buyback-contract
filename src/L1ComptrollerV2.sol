// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {IERC20Burnable} from "./interfaces/IERC20Burnable.sol";
import {ICrossDomainMessenger} from "./interfaces/ICrossDomainMessenger.sol";

import {L2ComptrollerV2} from "./L2ComptrollerV2.sol";

/// @title L1 comptroller contract for token buy backs.
/// @notice Contract to burn a token and claim another one on L2.
/// @author dHEDGE
/// @dev This contract is only useful if paired with the L2 comptroller.
contract L1ComptrollerV2 is OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /////////////////////////////////////////////
    //                  Structs                //
    /////////////////////////////////////////////

    struct BurnTokenDetails {
        bool isTokenToBurn;
        bool isIERC20Burnable;
    }

    struct BurnTokenSettings {
        address tokenToBurn;
        bool isERC20Burnable;
    }

    /////////////////////////////////////////////
    //                  Events                 //
    /////////////////////////////////////////////

    event L2ComptrollerSet(address newL2Comptroller);
    event CrossChainGasLimitModified(uint256 newCrossChainGasLimit);
    event EmergencyWithdrawal(address indexed token, uint256 amount);
    event BuyBackFromL1Initiated(
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
    error NotBuybackToken(address token);
    error TokenCannotBeBought(address token);

    /////////////////////////////////////////////
    //                Variables                //
    /////////////////////////////////////////////

    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /// @notice The Optimism contract to interact with on L1 Ethereum for sending data using smart contracts.
    ICrossDomainMessenger public crossDomainMessenger;

    /// @notice Address of the L2 comptroller to be called to initiate a buyback claim.
    /// @dev Has to be set after deployment of both the contracts.
    address public l2Comptroller;

    /// @dev The gas limit to be used to call the Optimism Cross Domain Messenger contract.
    uint32 public crossChainCallGasLimit;

    /// @notice Mapping of token to be burnt and its details.
    /// @dev Note that we are not enforcing that the `token` be a burnable token.
    ///      We can write different functions depending on the token type.
    mapping(address token => BurnTokenDetails burnTokenDetails) public tokensToBurn;

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

    /// @dev To prevent the implementation contract from being used, we invoke the _disableInitializers
    /// function in the constructor to automatically lock it when it is deployed.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Function to initialize this contract.
    /// @param _crossDomainMessenger The cross domain messenger contract on L1.
    /// @param _crossChainCallGasLimit The gas limit to be passed for a cross chain call
    ///        to the L2Comptroller contract.
    function initialize(
        address owner,
        ICrossDomainMessenger _crossDomainMessenger,
        uint32 _crossChainCallGasLimit
    ) external initializer {
        if (address(_crossDomainMessenger) == address(0)) revert ZeroAddress();

        __Ownable_init();
        __Pausable_init();

        crossDomainMessenger = _crossDomainMessenger;
        crossChainCallGasLimit = _crossChainCallGasLimit;

        transferOwnership(owner);
    }

    /// @notice Function to burn `amount` of a `token` and claim against it on L2.
    /// @dev - If a transaction passes on L1 but fails on L2 then the user must claim their share on L2 directly.
    ///      - Note that this function can be called with any `tokenToBuy` passed and it's not validated here.
    ///        This is safe as long as the total burnt amount is updated in the L2 contract.
    ///        That way, the user can claim whatever supported token they want on the L2 side.
    /// @param tokenToBuy Address of the token to be claimed.
    /// @param tokenToBurn Address of the token to be burnt.
    /// @param receiver Address of the account which will receive the claim.
    /// @param burnTokenAmount Amount of `tokenToBurn` to be burnt.
    function buyBack(
        address tokenToBurn,
        address tokenToBuy,
        uint256 burnTokenAmount,
        address receiver
    ) external whenNotPaused whenL2ComptrollerSet {
        _burnToken(tokenToBurn, burnTokenAmount);

        uint256 totalBurntAmount = burntAmountOf[msg.sender][tokenToBurn] += burnTokenAmount;

        // Send a cross chain message to `l2Comptroller` for releasing the buy tokens.
        crossDomainMessenger.sendMessage(
            l2Comptroller,
            abi.encodeCall(
                L2ComptrollerV2.buyBackFromL1,
                (tokenToBurn, tokenToBuy, totalBurntAmount, msg.sender, receiver)
            ),
            crossChainCallGasLimit
        );

        emit BuyBackFromL1Initiated(msg.sender, tokenToBurn, receiver, burnTokenAmount, totalBurntAmount);
    }

    function _burnToken(address token, uint256 amount) private {
        if (tokensToBurn[token].isTokenToBurn == false) revert NotBuybackToken(token);

        if (tokensToBurn[token].isIERC20Burnable) {
            IERC20Burnable(token).burnFrom(msg.sender, amount);
        } else {
            // If it's not a natively burnable token then transfer it to the burn address.
            IERC20Upgradeable(token).safeTransferFrom(msg.sender, BURN_ADDRESS, amount);
        }
    }

    /////////////////////////////////////////////
    //             Owner Functions             //
    /////////////////////////////////////////////

    /// @notice Function to add multiple burn tokens.
    /// @param burnTokenSettings Array of BurnTokenSettings to be added.
    function addBurnTokens(BurnTokenSettings[] memory burnTokenSettings) external onlyOwner {
        for (uint256 i; i < burnTokenSettings.length; ++i) {
            addBurnTokens(burnTokenSettings[i]);
        }
    }

    /// @notice Function to add a burn token.
    /// @param burnTokenSettings BurnTokenSettings to be added. This struct includes the token address and the IERC20Burnable support flag.
    function addBurnTokens(BurnTokenSettings memory burnTokenSettings) public onlyOwner {
        if (burnTokenSettings.tokenToBurn == address(0)) revert ZeroAddress();

        tokensToBurn[burnTokenSettings.tokenToBurn] = BurnTokenDetails({
            isTokenToBurn: true,
            isIERC20Burnable: burnTokenSettings.isERC20Burnable
        });
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

    /// @notice Function to set the cross chain calls gas limit.
    /// @dev Optimism allows, upto a certain limit, free execution gas units on L2.
    ///      This value is currently 1.92 million gas units. This might not be enough for us.
    ///      Hence this function for modifying the gas limit.
    /// @param newCrossChainGasLimit The new gas amount to be sent to the l2Comptroller for cross chain calls.
    function setCrossChainGasLimit(uint32 newCrossChainGasLimit) external onlyOwner {
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
