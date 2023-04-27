import { BigNumber, BigNumberish } from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";

export type Address = string;

interface IDhedgeInternal {
    // Dhedge
    protocolDaoAddress: Address;
    protocolTreasuryAddress: Address;
    proxyAdminAddress: Address;
    implementationStorageAddress: Address;
}

export type IProposeTxProperties = IDhedgeInternal & {
    // Gnosis safe multicall/send address
    // https://github.com/gnosis/safe-deployments
    gnosisMultiSendAddress?: string;
    gnosisApi?: string;
};

export interface IUpgradeConfigProposeTx {
    execute: boolean;
    restartnonce: boolean;
    useNonce: number;
}

export type IUpgradeConfig = IUpgradeConfigProposeTx & {
    oldTag: string;
    newTag: string;
};
