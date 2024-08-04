// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import {ICrossDomainMessenger} from "../interfaces/ICrossDomainMessenger.sol";
import {AddressAliasHelper} from "../libraries/AddressAliasHelper.sol";
import {L2ComptrollerV2Base} from "../abstracts/L2ComptrollerV2Base.sol";

/// @title L2 comptroller contract for token buy backs or redemptions of one asset for another.
/// @notice This contract supports redemption claims raised from the L1 comptroller.
/// @dev This contract is specifically designed to work with dHEDGE pool tokens.
/// @author dHEDGE
contract L2ComptrollerArb is L2ComptrollerV2Base {
    using AddressAliasHelper for address;

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
    function initialize(address owner) external initializer {
        // Initialize ownable contract.
        __Ownable_init();

        // Initialize Pausable contract.
        __Pausable_init();

        // Transfer ownership to the owner.
        transferOwnership(owner);
    }

    function _preRedemptionChecks() internal view override {
        // The caller should be our L1 comptroller contract.
        if(msg.sender.undoL1ToL2Alias() != l1Comptroller) revert OnlyCrossChainAllowed();
    }
}
