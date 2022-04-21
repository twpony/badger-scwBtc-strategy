from brownie import *
from helpers.constants import MaxUint256


def test_are_you_trying(deployer, vault, strategy, want, governance):
    """
    Verifies that you set up the Strategy properly
    """
    # Setup
    startingBalance = want.balanceOf(deployer)

    depositAmount = startingBalance // 2
    assert startingBalance >= depositAmount
    assert startingBalance >= 0
    # End Setup

    # Deposit
    assert want.balanceOf(vault) == 0

    want.approve(vault, MaxUint256, {"from": deployer})
    vault.deposit(depositAmount, {"from": deployer})

    available = vault.available()
    assert available > 0

    vault.earn({"from": governance})

    # sleep more time, otherwise, harvest will be zero
    # harvest have inclued the accrued supply, accrued borrow, and the claimComp
    chain.sleep(10000*13)
    chain.mine(1000)

    ## TEST 1: Does the want get used in any way?
    assert want.balanceOf(vault) == depositAmount - available
    ## Did the strategy do something with the asset?
    assert want.balanceOf(strategy) < available

    ## TEST 2: Is the Harvest profitable?
    harvest = strategy.harvest({"from": governance})
    event = harvest.events["Harvested"]
    ## If it doesn't print, we don't want it
    assert event["amount"] > 0


