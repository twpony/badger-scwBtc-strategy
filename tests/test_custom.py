import brownie
from brownie import *
from helpers.constants import MaxUint256
from helpers.SnapshotManager import SnapshotManager
from helpers.time import days

"""
  TODO: Put your tests here to prove the strat is good!
  See test_harvest_flow, for the basic tests
  See test_strategy_permissions, for tests at the permissions level
"""


def test_deposit_all_withdraw_all(vault, strategy, want, randomUser, deployer):

    initial_balance = want.balanceOf(deployer)

    settKeeper = accounts.at(vault.keeper(), force=True)

    snap = SnapshotManager(vault, strategy, "StrategySnapshot")

    # Deposit
    assert want.balanceOf(deployer) > 0

    depositAmount = int(want.balanceOf(deployer))
    assert depositAmount > 0

    want.approve(vault.address, MaxUint256, {"from": deployer})

    snap.settDeposit(depositAmount, {"from": deployer})

    # Earn
    with brownie.reverts("onlyAuthorizedActors"):
        vault.earn({"from": randomUser})

    snap.settEarn(deployer.address, {"from": settKeeper})

    # Test no harvests
    chain.sleep(days(2))
    chain.mine()

    snap.settWithdrawAll({"from": deployer})

    ending_Balance = want.balanceOf(deployer)

    print("Initial Balance")
    print(initial_balance)
    print("Ending Balance")
    print(ending_Balance)





