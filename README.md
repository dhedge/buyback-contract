# MTA Buyback-Contract
Buyback and burn contract for the [mStable MTA token](0xa3BeD4E1c75D00fa6f4E5E6922DB7261B5E9AcD2). Allows a holder of MTA on Ethereum (L1) to burn their tokens on L1 and claim their share of [MTy](0x0f6eae52ae1f94bc759ed72b201a2fdb14891485) on Optimism (L2) without bridging the tokens first. Users who have already bridged their tokens to Optimism can also interact with our contract on L2 to initiate buyback and burn.

## Motivation
---
dHEDGE recently [acquired](https://forum.mstable.org/t/mip-33-dhedge-acquisition-of-mstable/1017/5) mStable. As part of the acquisition, existing holders of the MTA token have two options:

- dHEDGE & mStable will offer a continuous floor price and set up a UI for redemption. The ability to cash out at the floor price will be available perpetually until it’s no longer relevant and mStable governance decides to sunset the redemption contract.
- If MTA trades above the floor price, and MTA holders are not redeeming, it would be capital inefficient to lock the full treasury in the redemption contract. Therefore in this scenario, a portion of the treasury can be used in safe yield with proven low risk yield sources and underlying. This will be fully transparent onchain with a private mStable Treasury Yield vault (MTy).

## The Architecture
---

On a high level, there are two contracts involved in buyback and burn. One will be deployed on L1 Ethereum (the L1Comptroller contract) and the other one will be deployed on Optimism (the L2Comptroller contract). `L1Comptroller` is responsible for burning tokens when MTA holders interact with it and initiate issuance of MTy tokens on L2 using the Optimism bridge. This communication is only uni-directional i.e, the `L2Comptroller` contract never calls the `L1Comptroller`. Since there is no bi-directional communication, we made the contracts in such a way that failure of any calls to the `L2Comptroller` contract doesn't wreak havoc on the accounting being done in the `L1Comptroller` contract. So our main invariant is:

  *Users can only claim MTy token on L2 upto the amount claimable calculated on the basis of the amount of MTA token burnt on L1*

Let's understand this a bit more, for example a user burnt 100 MTA tokens for the first time using the `L1Comptroller`. Now the `L1Comptroller` makes a call to the `L2Comptroller` on Optimism stating the cumulative amount burnt by the user which in this case is 100 and an address to which the MTy tokens need to be transferred to. However, due to some reason let's assume the call to `L2Comptroller` failed. In such a case, the user should be able to claim the MTy tokens they are owed. We don't want a user to not be able to claim their rightful share of the MTy tokens under any circumstances.

To enable this, we use cumulative token burn amounts for each user (address). So whenever a user initiates a buyback and burn on L1, their total amount burnt till now (using `L1Comptroller`) is updated in a mapping in the `L1Comptroller` contract. This amount is then sent to the `L2Comptroller` to instruct it to release an appropriate amount of MTy token to the user specified address on L2. So if the call fails, the `L1Comptroller` can simply send the cumulative amount burnt again when the user calls the `buyBack` function. This cumulative amount is stored in the `L2Comptroller` after a successfull claim of MTy tokens. Hence, whenever a new buyback and burn is initiated, the `L2Comptroller` will subtract the cumulative amount it received from the `L1Comptroller` and it's own stored cumulative amount. This difference is the amount against which MTy can be claimed. Naturally, the cumulative burnt amount stored in the `L2Comptroller` should never be greater than the cumulative amount stored in `L1Comptroller`.

Why cumulative amounts and why not just send the amount burnt on L1 in one particular transaction? The answer is that if the call on L2 fails due to any reason, the L1 contract wouldn't know this and there would be no way of claiming the rightful share. We could have probably played with transaction ids but that would make claims difficult in case of failures. We concluded that this is the most intuitive way of communicating the burn amounts between L1 and L2. Also in case this whole bridge based buyback and burns fail, we have an option to fallback to issuing another token (wbMTA) on L1 and tell the users to manually bridge it or use some sort of merkle airdrop campaign.

For the users who have already bridged their MTA to Optimism, we allow for claiming MTy tokens using the `L2Comptroller`. What happens in this case is that the MTA tokens on L2 are sent to a burn multi-sig operated by dHEDGE and periodically bridged back to L1 and burned there manually.

For anymore details, please read the contracts. They are sufficiently documented and if there still exists any issues, please let us know where and we can help you out in understanding this whole architecture.

## How to run tests?
---

The codebase uses Foundry test suite and integration tests using forking mode. Setup Foundry by following the instructions in their [docs](https://book.getfoundry.sh/getting-started/installation). Make sure that you have set the relevant env variables.

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