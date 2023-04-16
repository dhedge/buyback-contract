# buyback-contract
Buyback and burn contract for MTA token. Allows a holder of MTA on Ethereum (L1) to burn their tokens on L1 and claim their share of MTAy on Optimism (L2) without bridging the tokens first.

## How to run tests?

The codebase uses Foundry test suite and integration tests using forking mode. Setup Foundry by following the instructions in their [docs](https://book.getfoundry.sh/getting-started/installation). Make sure that you have set the relevant env variables.

Enter the following command in your terminal. By default, all tests will run.
```shell
$ forge t
```
