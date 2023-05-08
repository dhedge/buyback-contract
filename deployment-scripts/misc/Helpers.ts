import { HardhatRuntimeEnvironment } from "hardhat/types";
import { retryWithDelay } from "./utils";

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