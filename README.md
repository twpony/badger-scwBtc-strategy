
## Strategy Introduction

- ScreamWbtc Strategy based on Badger Strategy V1.5 Brownie Mix

- This strategy is to leverage on Scream with wBtc. It relies on borrowed money to increase the potential return of an investment. An investor collaterizes and borrows funds several rounds to amplify the exposure to the whole assets. 

- This strategy can be deployed on Fantom.

## Visualization of Strategy

![](https://github.com/twpony/file/blob/main/ScreamWbtc.jpg)				


## Installation and Setup

Install all dependencies according to Readme on [badger-vaults-mix-v1.5](https://github.com/Badger-Finance/badger-vaults-mix-v1.5). 


## Basic Use

All of the commands are executed in python virtual environment:  `source ven/bin/activate`

1. Compile the code. 

```
  brownie compile
```

2. Run Scripts for Deployment

```
  brownie run 1_production_deploy.py
```

3. Run Test

```
  brownie test --interactive
```