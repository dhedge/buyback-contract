import axios from "axios";
import { ethers } from "hardhat";
import { SafeService } from "@safe-global/safe-ethers-adapters";
import Safe, { EthersAdapter } from "@safe-global/protocol-kit";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { IProposeTxProperties, IUpgradeConfigProposeTx } from "./types";
import { retryWithDelay } from "./utils";
import { SafeTransactionDataPartial } from "@safe-global/safe-core-sdk-types";

let nonce: number;

export const nonceLog: {
    nonce: number;
    message: string;
}[] = [];

const getNonce = async (
    safeSdk: Safe,
    chainId: number,
    safeAddress: string,
    restartFromLastConfirmedNonce: boolean,
    useNonce: number | undefined
) => {
    if (useNonce !== undefined) {
        return useNonce;
    }
    const lastConfirmedNonce = await safeSdk.getNonce();
    if (restartFromLastConfirmedNonce) {
        console.log(
            "GetNonce: Starting from LAST CONFIRMED NONCE: ",
            lastConfirmedNonce
        );
        return lastConfirmedNonce;
    }

    const safeTxApi = `https://safe-client.gnosis.io/v1/chains/${chainId}/safes/${safeAddress}/transactions/queued`;
    const response = await axios.get(safeTxApi);
    const results = response.data.results.reverse();
    const last = results.find(
        (r: { type: string }) => r.type === "TRANSACTION"
    );
    if (!last) {
        console.log(
            "GetNonce: No Pending Nonce - Starting from LAST CONFIRMED NONCE: ",
            lastConfirmedNonce
        );
        return lastConfirmedNonce;
    }

    const nonce = last.transaction.executionInfo.nonce + 1;
    console.log("GetNonce: Starting from last PENDING nonce: ", nonce);
    return nonce;
};

export const proposeTx = async (
    to: string,
    data: string,
    message: string,
    config: IUpgradeConfigProposeTx,
    addresses: IProposeTxProperties
) => {
    if (!config.execute) {
        console.log("Will propose transaction:", message);
        return;
    }

    // Initialize the Safe SDK
    const provider = ethers.provider;
    const owner1 = provider.getSigner(0);
    const ethAdapter = new EthersAdapter({
        ethers: ethers,
        signerOrProvider: owner1,
    });
    const chainId: number = await ethAdapter.getChainId();

    if (!addresses.gnosisApi || !addresses.gnosisMultiSendAddress) {
        await owner1.sendTransaction({
            from: await owner1.getAddress(),
            to: to,
            data: data,
        });
        return;
    }

    const service = new SafeService(addresses.gnosisApi);

    const chainSafeAddress: string = addresses.protocolDaoAddress;

    const safeSdk = await Safe.create({
        ethAdapter,
        safeAddress: chainSafeAddress,
    });

    nonce = nonce
        ? nonce
        : await retryWithDelay(
              () =>
                  getNonce(
                      safeSdk,
                      chainId,
                      chainSafeAddress,
                      config.restartnonce,
                      config.useNonce
                  ),
              "Gnosis Get Nonce"
          );

    const safeTransactionData: SafeTransactionDataPartial = {
        to: to,
        data: data,
        value: "0",
        nonce: nonce,
    };

    const log = {
        nonce: nonce,
        message: message,
    };

    console.log("Proposing transaction: ", safeTransactionData);
    console.log(`Nonce Log`, log);
    nonceLog.push(log);

    nonce += 1;

    const safeTransaction = await safeSdk.createTransaction({ safeTransactionData });
    // off-chain sign
    const txHash = await safeSdk.getTransactionHash(safeTransaction);
    const signature = await safeSdk.signTransactionHash(txHash);
    // on-chain sign
    // const approveTxResponse = await safeSdk.approveTransactionHash(txHash)
    // console.log("approveTxResponse", approveTxResponse);
    console.log("safeTransaction: ", safeTransaction);

    await retryWithDelay(
        () =>
            service.proposeTx(
                chainSafeAddress,
                txHash,
                safeTransaction,
                signature
            ),
        "Gnosis safe"
    );
};

export const executeInSeries = <T>(
    providers: (() => Promise<T>)[]
): Promise<T[]> => {
    const ret: Promise<void> = Promise.resolve(undefined);
    const results: T[] = [];

    const reduced = providers.reduce((result, provider, index) => {
        const x = result.then(function () {
            return provider().then(function (val) {
                results[index] = val;
            });
        });
        return x;
    }, ret as Promise<void>);
    return reduced.then(() => results);
};

export const tryVerify = async (
    hre: HardhatRuntimeEnvironment,
    address: string,
    path: string,
    constructorArguments: unknown[],
  ) => {
    await retryWithDelay(
      async () => {
        try {
          await hre.run("verify:verify", {
            address: address,
            contract: path,
            constructorArguments: constructorArguments,
          });
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
        } catch (e: any) {
          if (e.message.toLowerCase().includes("constructor arguments exceeds max accepted")) {
            // This error may be to do with the compiler, "constructor arguments exceeds max accepted (10k chars) length"
            // Possibly because the contract should have been compiled in isolation before deploying ie "compile:one"
            console.warn(`Couldn't verify contract at ${address}. Error: ${e.message}, skipping verification`);
            return;
          }
          if (!e.message.toLowerCase().includes("already verified")) {
            throw e;
          }
        }
      },
      "Try Verify Failed: " + address,
      10,
    );
  };