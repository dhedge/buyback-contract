import { ethers } from "ethers";

// Deployment arguments for L2Comptroller contract.

export const config = {
    "L2CrossDomainMessenger": "0x4200000000000000000000000000000000000007",
    "MTA": "0x929B939f8524c3Be977af57A4A0aD3fb1E374b50",
    "MTy": "0x0f6eae52ae1f94bc759ed72b201a2fdb14891485", // mStable Treasury Yield (https://app.dhedge.org/vault/0x0f6eae52ae1f94bc759ed72b201a2fdb14891485)
    "OptimismMultisig": "0x352Fb838A3ae9b0ef2f0EBF24191AcAf4aB9EcEc", // Used for burning MTA on Optimism.
    "ExchangePrice": ethers.utils.parseUnits("318", 14), // $0.03
    "MaxTokenPriceDrop": 10, // 10:10000 => 0.1% max price drop acceptable
}