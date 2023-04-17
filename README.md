# buyback-contract
Buyback and burn contract for MTA token. Allows a holder of MTA on Ethereum (L1) to burn their tokens on L1 and claim their share of MTAy on Optimism (L2) without bridging the tokens first.

## Tests

The naming convention we follow for writing tests are detailed below:
- File name represents the contract being tested specifically. For example, the test contract file name `L1Comptroller.t.sol` represents the L1Comptroller contract's tests.
- Contract names represent the exact function to be tested. For example, a contract named `BuyBackOnL2` represents tests for the function `buyBackOnL2` in the `L1Comptroller.sol` as per our previous example.
- The test names start with 'test' followed by the function name being tested, followed by the test case description in capitalized camel case. For example, if you want to write the test for `buyBackOnL2` to check whether the `L1Comptroller` is burning tokens correctly you would write it as `test_buyBackOnL2_ShouldBurnTokensCorrectly`. Notice the camel case of the test description.
- If ever in doubt, refer the Foundry [docs](https://book.getfoundry.sh/tutorials/best-practices#tests).

### How to run tests?

The codebase uses Foundry test suite and integration tests using forking mode. Setup Foundry by following the instructions in their [docs](https://book.getfoundry.sh/getting-started/installation). Make sure that you have set the relevant env variables.

Enter the following command in your terminal. By default, all tests will run.
```shell
$ forge t
```
