// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {ICrossDomainMessenger} from "../../interfaces/ICrossDomainMessenger.sol";
import {IPoolLogic} from "../../interfaces/IPoolLogic.sol";

import {L2ComptrollerV2Base} from "../../abstracts/L2ComptrollerV2Base.sol";

/// @title L2 comptroller contract for token buy backs or redemptions of one asset for another.
/// @notice This contract supports redemption claims raised from the L1 comptroller.
/// @dev This contract is specifically designed to work with dHEDGE pool tokens.
/// @author dHEDGE
contract L2ComptrollerOPV2 is L2ComptrollerV2Base {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice The Optimism contract to interact with for sending/verifying data to/from L1
    ///         using smart contracts.
    ICrossDomainMessenger public crossDomainMessenger;

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
    function initialize(address owner, ICrossDomainMessenger _crossDomainMessenger) external initializer {
        if (address(_crossDomainMessenger) == address(0)) revert ZeroAddress();

        // Initialize ownable contract.
        __Ownable_init();

        // Initialize Pausable contract.
        __Pausable_init();

        crossDomainMessenger = _crossDomainMessenger;

        // Transfer ownership to the owner.
        transferOwnership(owner);
    }

    function _preRedemptionChecks() internal view override {
        // The caller should be the cross domain messenger contract of Optimism
        // and the call should be initiated by our comptroller contract on L1.
        if (msg.sender != address(crossDomainMessenger) || crossDomainMessenger.xDomainMessageSender() != l1Comptroller)
            revert OnlyCrossChainAllowed();
    }
}
