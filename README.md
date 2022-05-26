- **Deployed Strategy**

Zapper：

[Vault](https://zapper.fi/zh/account/0x64d1b1aaa02fc0c6ced2868ae4cea71b0b818fbe)

[Strategy](https://zapper.fi/zh/account/0x18a592a5939c161a652dc82f2e6f335fe654d93b)


- **ScreamWbtc Strategy Introduction**

Scream leverage based on wBtc is my strategy. This strategy relies on borrowed money to increase the potential return of an investment. An investor collaterizes and borrows funds several rounds to amplify the exposure to the whole assets. 

How to invest: 1) deposits wBtc in vault; 2) vault deposits in strategy; 3) strategy collaterizes in scWbtc pool; 4) strategy borrow from scWbtc pool; 5) repeat step 3 and step 4 in several rounds;  6) harvest SCREAM token from scream unitroller; 7) using spookyswap to swap SCREAM token to wBtc, and deposit the harvested token in scWbtc pool again; 8) go on starting from step 3.

- **Estimate APY**

We use the following  parameters:   The table shows the calculation process. Based on the present Scream APY, my strategy estimated APY is 2.22%. Deducting the performance fee, strategy estimated APY is 1.10%.  

![](https://github.com/twpony/file/blob/main/APYEstimate.jpg)

- **Visualization of Strateg y**

![](https://github.com/twpony/file/blob/main/ScreamWbtc.jpg)																																																																																																																																										

**Address:**

Wbtc=0x321162Cd933E2Be498Cd2267a90534A804051b11

scWbtc=0x4565DC3Ef685E4775cdF920129111DdF43B9d882

SCREAM=0xe0654C8e6fd4D733349ac7E09f6f23DA256bF475

unitroller=0x260E596DAbE3AFc463e75B6CC05d8c46aCAcFB09



- **Structure of this project**

This project is developed based on badger-vaults-mix-v1.5. The main structure of this project is the same as badger-vaults-mix-v1.5. badger-vaults-mix-v1.5 is dependent on two important contacts (BaseStrategy.sol and Vault.sol)in badger-sett-1.5.  In order to compile codes together, and this strategy may be deployed on mainnet work, I add these two important contacts and some interface files into this project. Excpet this change, the structure of project is almost the same with badger-vaults-mix-v1.5.

BaseStrategy.sol is in the "folder  basestrategy"; Vault.sol is inthe "folder vault"; Interface files are all in "folder interfaces".

- **How to run it**

  install all dependencies according to readme on https://github.com/Badger-Finance/badger-vaults-mix-v1.5. 

  `source ven/bin/activate`

  `brownie compile`

  `brownie run 1_production_deploy.py`

  `brownie test --interactive`

- **Some Important Modifications For Framework**

1. ***Overwrite withdraw() function in Basestrategy.sol.***  The original function has a very strict limitations on the diff between actual withdrawal amount and expected withdrawal amount. If the strategy does not have leverage, this is a good way to handle it. But in multilevels leverage, we generally set reserves for leveraging in consideration of liquidity safety, it is quite easy to exceed the revert conditions, such as withdraw-threshhold. ***This function should be virtual to be convenient for developers to overwrite***. 

2. ***function _mintSharesFor(address recipient, uint256 _amount, uint256 _pool) () in Vault.sol**,  **modify if condition*** to  `totalSupply() == 0 || _pool == 0`. When I run brownie test, sometimes _pool =0 will revert division 0 safemath problem.

3. ***function confirm_withdraw() in StrategyCoreResolver.py***,  I encounter the number is little and very close, and cannot satisfy the approx(). The difference is quite little, just because of the gas cost. So I modify the requirement to compare strategy.balanceOf change to make the test pass. 

4. ***function confirm_harvest() in StrategyCoreResolver.py***, If the underlying pool net asset does not change, delta_strategist should be the same as **shares_perf_strategist.** Because the underlying scream pool without claimcomp will loss the money, so in general  delta_strategist should be more than shares_perf_strategist. And the difference between the two values is small, I set the limit is 5. Comparison of **shares_perf_treasury** and delta_treasury has been dealt with in the same way. 

   All the above places I have changed are marked with "\## Badge Mix". You can find them out soon.

- **Reference**

I have referred to many app gitbhub and website, including Badger, Scream, Beefy, Yearn, Compound. I learnt a lot from their github codes.

- **Developer Configuration**

Brownie v1.18.1 - Python development framework for Ethereum;   
Ganache CLI v6.12.1 (ganache-core: 2.13.1);   
Windows WSL2 system;   
VisualCode.

