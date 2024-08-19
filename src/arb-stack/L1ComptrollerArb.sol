// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {IInbox} from "../interfaces/IInbox.sol";

import {L1ComptrollerV2Base} from "../abstracts/L1ComptrollerV2Base.sol";
import {L2ComptrollerArb} from "./L2ComptrollerArb.sol";

/// @title L1 comptroller contract for token buy backs.
/// @notice Contract to burn a token and claim another one on L2.
/// @author dHEDGE
/// @dev This contract is only useful if paired with the L2 comptroller.
contract L1ComptrollerArb is L1ComptrollerV2Base {
    /////////////////////////////////////////////
    //                  Structs                //
    /////////////////////////////////////////////

    struct ArbAdditionalData {
        uint256 maxSubmissionCost;
        address excessFeeRefundAddress;
        address callValueRefundAddress;
        uint256 gasLimit;
        uint256 maxFeePerGas;
    }

    /////////////////////////////////////////////
    //                  Events                 //
    /////////////////////////////////////////////

    event RetryableTicketCreated(address indexed msgSender, uint256 ticketId);

    /////////////////////////////////////////////
    //                  State                  //
    /////////////////////////////////////////////

    /// @notice The Arbitrum contract to interact with on L1 Ethereum for sending data using smart contracts to L2.
    IInbox public inbox;

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
    ///        to the L2Comptroller contract.
    function initialize(address _owner, IInbox _inbox) external initializer {
        if (address(_inbox) == address(0)) revert ZeroAddress();

        __Ownable_init();
        __Pausable_init();

        inbox = _inbox;

        transferOwnership(_owner);
    }

    /// @dev Function to send a message to Arbitrum stack L2s (Arbitrum Inbox).
    /// @dev `additionalData` must be encoded as `ArbAdditionalData`.
    function _sendMessage(bytes memory messageData, bytes memory additionalData) internal override {
        ArbAdditionalData memory arbAdditionalData = abi.decode(additionalData, (ArbAdditionalData));

        uint256 ticketId = inbox.createRetryableTicket{value: msg.value}({
            to: l2Comptroller,
            l2CallValue: 0,
            maxSubmissionCost: arbAdditionalData.maxSubmissionCost,
            excessFeeRefundAddress: arbAdditionalData.excessFeeRefundAddress,
            callValueRefundAddress: arbAdditionalData.callValueRefundAddress,
            gasLimit: arbAdditionalData.gasLimit,
            maxFeePerGas: arbAdditionalData.maxFeePerGas,
            data: messageData
        });

        emit RetryableTicketCreated(msg.sender, ticketId);
    }
}
