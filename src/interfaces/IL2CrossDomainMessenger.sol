// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

/* Interface Imports */
import { ICrossDomainMessenger } from "./ICrossDomainMessenger.sol";

/**
 * @title IL2CrossDomainMessenger
 * @dev Imported from https://github.com/ethereum-optimism/optimism/blob/131ae0a197e1ee419b9d0a5a904e46002d27a505/packages/contracts/contracts/L2/messaging/IL2CrossDomainMessenger.sol#L10
 */
interface IL2CrossDomainMessenger is ICrossDomainMessenger {
    /********************
     * Public Functions *
     ********************/

    function messageNonce() external returns(uint256);
    
    /**
     * Relays a cross domain message to a contract.
     * @param _target Target contract address.
     * @param _sender Message sender address.
     * @param _message Message to send to the target.
     * @param _messageNonce Nonce for the provided message.
     */
    function relayMessage(
        address _target,
        address _sender,
        bytes memory _message,
        uint256 _messageNonce
    ) external;
}