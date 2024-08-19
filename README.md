# MTA Buyback-Contract

Buyback and burn contract for the [mStable MTA token](https://etherscan.io/address/0xa3BeD4E1c75D00fa6f4E5E6922DB7261B5E9AcD2). Allows a holder of MTA on Ethereum (L1) to burn their tokens on L1 and claim their share of [MTy](https://app.dhedge.org/vault/0x0f6eae52ae1f94bc759ed72b201a2fdb14891485) on Optimism (L2) without bridging the tokens first. Users who have already bridged their tokens to Optimism can also interact with our contract on L2 to initiate buyback and burn.

## Motivation

dHEDGE recently [acquired](https://forum.mstable.org/t/mip-33-dhedge-acquisition-of-mstable/1017/5) mStable. As part of the acquisition, existing holders of the MTA token have two options:

- dHEDGE & mStable will offer a continuous floor price and set up a UI for redemption. The ability to cash out at the floor price will be available perpetually until it’s no longer relevant and mStable governance decides to sunset the redemption contract.
- If MTA trades above the floor price, and MTA holders are not redeeming, it would be capital inefficient to lock the full treasury in the redemption contract. Therefore in this scenario, a portion of the treasury can be used in safe yield with proven low risk yield sources and underlying. This will be fully transparent onchain with a private mStable Treasury Yield vault (MTy).

## The Architecture

### V1

The V1 contracts support the buyback and burn functionality for a single token pair and in our case, it's MTA and MTy. Technically, with small changes, it is possible to deploy the same contracts for any other token pairs as well. V1 only supports OP-stack chains (for L2Comptroller).

On a high level, there are two contracts involved in buyback and burn. One will be deployed on L1 Ethereum (the L1Comptroller contract) and the other one will be deployed on Optimism (the L2Comptroller contract). `L1Comptroller` is responsible for burning tokens when MTA holders interact with it and initiate issuance of MTy tokens on L2 using the Optimism bridge. This communication is only uni-directional i.e, the `L2Comptroller` contract never calls the `L1Comptroller`. Since there is no bi-directional communication, we made the contracts in such a way that failure of any calls to the `L2Comptroller` contract doesn't wreak havoc on the accounting being done in the `L1Comptroller` contract. So our main invariant is:

  *Users can only claim MTy token on L2 upto the amount claimable calculated on the basis of the amount of MTA token burnt on L1*

Let's understand this a bit more, for example a user burnt 100 MTA tokens for the first time using the `L1Comptroller`. Now the `L1Comptroller` makes a call to the `L2Comptroller` on Optimism stating the cumulative amount burnt by the user which in this case is 100 and an address to which the MTy tokens need to be transferred to. However, due to some reason let's assume the call to `L2Comptroller` failed. In such a case, the user should be able to claim the MTy tokens they are owed. We don't want a user to not be able to claim their rightful share of the MTy tokens under any circumstances.

To enable this, we use cumulative token burn amounts for each user (address). So whenever a user initiates a buyback and burn on L1, their total amount burnt till now (using `L1Comptroller`) is updated in a mapping in the `L1Comptroller` contract. This amount is then sent to the `L2Comptroller` to instruct it to release an appropriate amount of MTy token to the user specified address on L2. So if the call fails, the `L1Comptroller` can simply send the cumulative amount burnt again when the user calls the `buyBack` function. This cumulative amount is stored in the `L2Comptroller` after a successfull claim of MTy tokens. Hence, whenever a new buyback and burn is initiated, the `L2Comptroller` will subtract the cumulative amount it received from the `L1Comptroller` and it's own stored cumulative amount. This difference is the amount against which MTy can be claimed. Naturally, the cumulative burnt amount stored in the `L2Comptroller` should never be greater than the cumulative amount stored in `L1Comptroller`.

Why cumulative amounts and why not just send the amount burnt on L1 in one particular transaction? The answer is that if the call on L2 fails due to any reason, the L1 contract wouldn't know this and there would be no way of claiming the rightful share. We could have probably played with transaction ids but that would make claims difficult in case of failures. We concluded that this is the most intuitive way of communicating the burn amounts between L1 and L2. Also in case this whole bridge based buyback and burns fail, we have an option to fallback to issuing another token (wbMTA) on L1 and tell the users to manually bridge it or use some sort of merkle airdrop campaign.

For the users who have already bridged their MTA to Optimism, we allow for claiming MTy tokens using the `L2Comptroller`. What happens in this case is that the MTA tokens on L2 are sent to a burn multi-sig operated by dHEDGE and periodically bridged back to L1 and burned there manually.

### V2

The V2 contracts allow for multiple token buyback and burns. The high level messaging-via-bridges architecture remains the same but the accounting for buy and burn token amounts is done in a more generalized way. With V2, we have added support for Arb-stack chains.

With V2, one can burn any supported burn token and in exchange receive any supported buy token. Let's suppose the supported burn tokens are BR1 and BR2 and the supported buy tokens are BY1 and BY2. This mean's the following cases are possible:

- Burn BR1 and receive either BY1 or BY2 as per the request made by the user in case both BY1 and BY2 are non-zero and sufficient in balance.
- If a request was made to burn BR1 and receive BY1 but the balance of BY1 is zero, then the user can claim BY2 directly on L2.

For claims on L2, one has to provide the address of the L1 token burnt. Logically, one can't claim BY2 tokens on L2 if they have already exhausted their burn token amount for claiming BY1 tokens. This is enforced in the `L2Comptroller` contract.

Note that one can theoretically mention any buy token address when redeeming from L1 even if `L2Compotroller` doesn't support that token. This is because, the `L1Comptroller` has no way of knowing which tokens are supported on L2. However, if someone provides an unsupported token address, the `L2Comptroller` will still store the amount burnt and will allow for claiming any supported token on L2. This was a deliberate choice as setting the supported buy tokens on L1 would have costed us gas on mainnet. One can validate the supported buy tokens on L2 by checking the `L2Comptroller.buyTokenDetails` mapping.

The exchange/redemption prices for the buy tokens are set in the `L2Comptroller` contract. This design decision was made to keep the gas cost low as the alternative would have been to set the prices on L1 and then send the dollar amount claimable on L2. The alternative is a great choice in case the strategies underlying the supported buy tokens were to change chains frequently but in our case, we don't expect that to happen. Also it would have allowed for claiming a buy token for any and all burn token amounts (i.e, buy BY1 for combined amount of BR1 and BR2 burnt). This would have been a bit more complex and we deemed it unnecessary.

For anymore details, please read the contracts. They are sufficiently documented and if there still exists any issues, please let us know where and we can help you out in understanding this whole architecture.

## Deployments

The following are the addresses of the deployed V1 contracts on Ethereum and Optimism respectively.

| Contract Names | Addresses                                                                                                                             |
|----------------|---------------------------------------------------------------------------------------------------------------------------------------|
| L1Comptroller  | [0x06e54ADa21565c4F2Ebe2bc1E3C4BD04262A4616](https://etherscan.io/address/0x06e54ADa21565c4F2Ebe2bc1E3C4BD04262A4616)            |
| L2Comptroller  | [0x06e54ADa21565c4F2Ebe2bc1E3C4BD04262A4616](https://optimistic.etherscan.io/address/0x06e54ADa21565c4F2Ebe2bc1E3C4BD04262A4616) |

## How to run tests?

The codebase uses Foundry test suite and integration tests using forking mode. Setup Foundry by following the instructions in their [docs](https://book.getfoundry.sh/getting-started/installation). Make sure that you have set the relevant env variables. Also make sure that the block numbers that you pass in `.env` file are the same as the ones in `.env.sample` file.

Enter the following command in your terminal. By default, all tests will run.
```shell
$ forge t
```

To run specific tests (integration/fuzz), use the following commands:

For integration tests
```shell
$ npm run tests:integration
```

For fuzz tests
```shell
$ npm run tests:fuzz
```