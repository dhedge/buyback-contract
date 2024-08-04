// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {ICrossDomainMessenger} from "../../interfaces/ICrossDomainMessenger.sol";

import {L1ComptrollerV2Base} from "../../abstracts/L1ComptrollerV2Base.sol";
import {L2ComptrollerOPV2} from "./L2ComptrollerOPV2.sol";

/// @title L1 comptroller contract for token buy backs.
/// @notice Contract to burn a token and claim another one on L2.
/// @author dHEDGE
/// @dev This contract is only useful if paired with the L2 comptroller.
contract L1ComptrollerOPV2 is L1ComptrollerV2Base {
    /// @notice The Optimism contract to interact with on L1 Ethereum for sending data using smart contracts.
    ICrossDomainMessenger public crossDomainMessenger;

    /// @dev The gas limit to be used to call the Optimism Cross Domain Messenger contract.
    uint32 public crossChainCallGasLimit;

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
    /// @param _owner The owner of the contract.
    /// @param _crossDomainMessenger The cross domain messenger contract on L1.
    /// @param _crossChainCallGasLimit The gas limit to be passed for a cross chain call
    ///        to the L2Comptroller contract.
    function initialize(
        address _owner,
        ICrossDomainMessenger _crossDomainMessenger,
        uint32 _crossChainCallGasLimit
    ) external initializer {
        if (address(_crossDomainMessenger) == address(0)) revert ZeroAddress();

        __Ownable_init();
        __Pausable_init();

        crossDomainMessenger = _crossDomainMessenger;
        crossChainCallGasLimit = _crossChainCallGasLimit;

        transferOwnership(_owner);
    }

    /// @notice Wrapper function for redemption.
    /// @dev Check `L1ComptrollerOPV2Base.redeem` for implementation details.
    function redeem(
        address tokenToBurn,
        address tokenToBuy,
        uint256 burnTokenAmount,
        address receiver
    ) external {
        super.redeem(tokenToBurn, tokenToBuy, burnTokenAmount, receiver, "");
    }

    /// @dev For Op-Stack chains, we need to use `crossDomainMessenger` for sending messages from L1 to L2.
    function _sendMessage(bytes memory messageData, bytes memory) internal override {
        crossDomainMessenger.sendMessage(l2Comptroller, messageData, crossChainCallGasLimit);
    }


    /////////////////////////////////////////////
    //          Owner Functions                //
    /////////////////////////////////////////////

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
}
