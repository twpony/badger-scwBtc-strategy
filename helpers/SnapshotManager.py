from brownie import *
from tabulate import tabulate
from rich.console import Console
from helpers.multicall import Multicall

from helpers.utils import (
    val,
    approx,
    difference,
)

from helpers.snapshot.snap import Snap

from _setup.StrategyResolver import StrategyResolver

console = Console()


class SnapshotManager:
    def __init__(self, sett, strategy, key):
        self.key = key
        self.sett = sett
        self.strategy = strategy
        self.want = interface.IERC20Detailed(self.sett.token())
        self.resolver = self.init_resolver(self.strategy.getName())
        self.snaps = {}
        self.settSnaps = {}
        self.entities = {}

        assert self.want == self.strategy.want()

        # Common entities for all strategies
        # (key, address), add to self.entities[key] = entity
        self.addEntity("sett", self.sett.address)
        self.addEntity("strategy", self.strategy.address)
        self.addEntity("governance", self.strategy.governance())
        self.addEntity("treasury", self.sett.treasury())
        self.addEntity("strategist", self.strategy.strategist())

        # these statement seems useless
        destinations = self.resolver.get_strategy_destinations()
        for key, dest in destinations.items():
            self.addEntity(key, dest)

    def add_snap_calls(self, entities):
        calls = []
        calls = self.resolver.add_balances_snap(calls, entities)
        calls = self.resolver.add_sett_snap(calls)
        # calls = self.resolver.add_sett_permissions_snap(calls)
        calls = self.resolver.add_strategy_snap(calls, entities=entities)
        return calls

    def snap(self, trackedUsers=None):
        print("snap")
        snapBlock = chain.height
        entities = self.entities

        if trackedUsers:
            for key, user in trackedUsers.items():
                entities[key] = user

        calls = self.add_snap_calls(entities)
        multi = Multicall(calls)
        # multi.printCalls()

        data = multi()
        self.snaps[snapBlock] = Snap(
            data,
            snapBlock,
            [x[0] for x in entities.items()],
        )

        return self.snaps[snapBlock]

    def addEntity(self, key, entity):
        self.entities[key] = entity

    def init_resolver(self, name):
        print("init_resolver", name)
        return StrategyResolver(self)

    def settTend(self, trackuser, overrides, confirm=True):
        # user = overrides["from"].address
        user = trackuser
        trackedUsers = {"user": user}
        before = self.snap(trackedUsers)
        tx = self.strategy.tend(overrides)
        after = self.snap(trackedUsers)
        if confirm:
            self.resolver.confirm_tend(before, after, tx)

    def settHarvest(self, trackuser, overrides, confirm=True):
        # user = overrides["from"].address
        user = trackuser
        trackedUsers = {"user": user}
        before = self.snap(trackedUsers)
        tx = self.strategy.harvest(overrides)
        after = self.snap(trackedUsers)
        if confirm:
            self.resolver.confirm_harvest(before, after, tx)

    def settDeposit(self, amount, overrides, confirm=True):
        user = overrides["from"].address
        trackedUsers = {"user": user}
        before = self.snap(trackedUsers)
        self.sett.deposit(amount, overrides)
        after = self.snap(trackedUsers)

        if confirm:
            self.resolver.confirm_deposit(
                before, after, {"user": user, "amount": amount}
            )

    def settDepositAll(self, overrides, confirm=True):
        user = overrides["from"].address
        trackedUsers = {"user": user}
        userBalance = self.want.balanceOf(user)
        before = self.snap(trackedUsers)
        self.sett.depositAll(overrides)
        after = self.snap(trackedUsers)
        if confirm:
            self.resolver.confirm_deposit(
                before, after, {"user": user, "amount": userBalance}
            )

    # Add test
    def settEarn(self, trackuser, overrides, confirm=True):
        # user = overrides["from"].address
        user = trackuser
        trackedUsers = {"user": user}
        before = self.snap(trackedUsers)
        self.sett.earn(overrides)
        after = self.snap(trackedUsers)
        if confirm:
            self.resolver.confirm_earn(before, after, {"user": user})

    def settWithdraw(self, amount, overrides, confirm=True):
        user = overrides["from"].address
        trackedUsers = {"user": user}
        before = self.snap(trackedUsers)

        tx = self.sett.withdraw(amount, overrides)
        after = self.snap(trackedUsers)
        if confirm:
            self.resolver.confirm_withdraw(
                before, after, {"user": user, "amount": amount}, tx
            )

    def settWithdrawAll(self, overrides, confirm=True):
        user = overrides["from"].address
        trackedUsers = {"user": user}
        userBalance = self.sett.balanceOf(user)
        before = self.snap(trackedUsers)

        tx = self.sett.withdraw(userBalance, overrides)
        after = self.snap(trackedUsers)
        if confirm:
            self.resolver.confirm_withdraw(
                before, after, {"user": user, "amount": userBalance}, tx
            )
            # to test the predict of balanceOfPool
            # the test is valid when deposit all and withdraw all
            withdrawlFee = before.get("sett.withdrawalFee") * before.get("strategy.balanceOfPool") / 10_000
            # deposit 95%, so there is 5% in sett
            sett_reserve = before.balances("want", "sett")
            # withdraw all to user, to test the user want balance is correct or not
            assert approx(before.get("strategy.balanceOfPool") - withdrawlFee + sett_reserve, after.balances("want", "user"), 1)

    def settWithdrawMost(self, overrides, confirm=True):
        user = overrides["from"].address
        trackedUsers = {"user": user}
        # withdraw all will incur the slippage of treasury sett balance
        # here set 99% balance to test
        userBalance = 0.99 * self.sett.balanceOf(user)
        before = self.snap(trackedUsers)

        tx = self.sett.withdraw(userBalance, overrides)
        after = self.snap(trackedUsers)
        if confirm:
            self.resolver.confirm_withdraw(
                before, after, {"user": user, "amount": userBalance}, tx
            )

    # withdraw all will induce large slippage when the treasury sett balance is very small
    # so we set to test withdraw 98% balance here

    def format(self, key, value):
        if type(value) is int:
            if "stakingRewards.staked" or "stakingRewards.earned" in key:
                return val(value)
            # Ether-scaled balances
            # TODO: Handle based on token decimals
            if (
                "balance" in key
                or key == "sett.available"
                or key == "sett.getPricePerFullShare"
                or key == "sett.totalSupply"
            ):
                return val(value)
        return value

    def diff(self, a, b):
        if type(a) is int and type(b) is int:
            return b - a
        else:
            return "-"

    def printCompare(self, before: Snap, after: Snap):
        # self.printPermissions()
        table = []
        console.print(
            "[green]=== Compare: {} Sett {} -> {} ===[/green]".format(
                self.key, before.block, after.block
            )
        )

        for key, item in before.data.items():

            a = item
            b = after.get(key)

            # Don't add items that don't change
            if a != b:
                table.append(
                    [
                        key,
                        self.format(key, a),
                        self.format(key, b),
                        self.format(key, self.diff(a, b)),
                    ]
                )

        print(
            tabulate(
                table, headers=["metric", "before", "after", "diff"], tablefmt="grid"
            )
        )

    def printPermissions(self):
        # Accounts
        table = []
        console.print("[blue]=== Permissions: {} Sett ===[/blue]".format(self.key))

        table.append(["sett.keeper", self.sett.keeper()])
        table.append(["sett.governance", self.sett.governance()])
        table.append(["sett.strategist", self.sett.strategist()])

        table.append(["---------------", "--------------------"])

        table.append(["strategy.keeper", self.strategy.keeper()])
        table.append(["strategy.governance", self.strategy.governance()])
        table.append(["strategy.strategist", self.strategy.strategist()])
        table.append(["strategy.guardian", self.strategy.guardian()])

        table.append(["---------------", "--------------------"])
        print(tabulate(table, headers=["account", "value"]))

    def printBasics(self, snap: Snap):
        table = []
        console.print("[green]=== Status Report: {} Sett ===[green]".format(self.key))

        table.append(
            ["sett.getPricePerFullShare", snap.get("sett.getPricePerFullShare")]
        )
        table.append(["strategy.want", snap.balances("want", "strategy")])

        print(tabulate(table, headers=["metric", "value"]))

    def printTable(self, snap: Snap):
        # Numerical Data
        table = []
        console.print("[green]=== Status Report: {} Sett ===[green]".format(self.key))

        for key, item in snap.data.items():
            # Don't display 0 balances:
            if "balances" in key and item == 0:
                continue
            table.append([key, self.format(key, item)])

        table.append(["---------------", "--------------------"])
        print(tabulate(table, headers=["metric", "value"]))
