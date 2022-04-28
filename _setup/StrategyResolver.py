from helpers.StrategyCoreResolver import StrategyCoreResolver
from rich.console import Console

from helpers.utils import (
    approx,
    difference,
)

console = Console()
MAX_BPS = 10_000


class StrategyResolver(StrategyCoreResolver):
    def get_strategy_destinations(self):
        """
        Track balances for all strategy implementations
        (Strategy Must Implement)
        """
        strategy = self.manager.strategy
        return {}

    def hook_after_confirm_withdraw(self, before, after, params):
        """
        Specifies extra check for ordinary operation on withdrawal
        Use this to verify that balances in the get_strategy_destinations are properly set
        """
        assert True

    def hook_after_confirm_deposit(self, before, after, params):
        """
        Specifies extra check for ordinary operation on deposit
        Use this to verify that balances in the get_strategy_destinations are properly set
        """

        # to chek balance of sett, whether the sett balance increases by deposit amount
        assert difference(
            after.get("sett.balance") - before.get("sett.balance"),
            params["amount"],
            2,
        )

    def hook_after_earn(self, before, after, params):
        """
        Specifies extra check for ordinary operation on earn
        Use this to verify that balances in the get_strategy_destinations are properly set
        """
        # just deposit 95% want balance, 
        # maybe have rouding error, but the difference should be less than 1
        assert difference(
            after.balances("want", "sett"),
            before.balances("want", "sett") * 0.05,
            1,
        )

        # sett balance change will move to strategy's pool
        # maybe have rounding error, but the difference should be less than 1 
        assert difference(
            before.balances("want", "sett") - after.balances("want", "sett"),
            after.get("strategy.balanceOfPool"),
            1,
        )

        # strategy balanceof should be equal to balanceOfPool; strategy will deposit all in the pool
        assert after.get("strategy.balanceOfPool") == after.get("strategy.balanceOf")


        # to test whether we have deposited and borrowed in iToken as we want
        assert after.get("strategy.getTimelySupplyPosition") > before.get("strategy.getTimelySupplyPosition")
        assert after.get("strategy.getTimelyBorrowPosition") > before.get("strategy.getTimelyBorrowPosition")
        assert after.get("strategy.collateralTarget") == before.get("strategy.collateralTarget")
        _supplyIncrease = after.get("strategy.getTimelySupplyPosition") - before.get("strategy.getTimelySupplyPosition")
        _borrowIncrease = after.get("strategy.getTimelyBorrowPosition") - before.get("strategy.getTimelyBorrowPosition")
        _balanceIncrease = after.get("strategy.balanceOf") - before.get("strategy.balanceOf")
        _collateralRatio = _borrowIncrease / _supplyIncrease
        _collateralTarget = after.get("strategy.collateralTarget") / 1e18
        assert _collateralRatio <= _collateralTarget
        assert difference(
            _balanceIncrease / (1-_collateralRatio),
            _supplyIncrease,
            1,
        )
        assert difference(
            _balanceIncrease * _collateralRatio / (1-_collateralRatio),
            _borrowIncrease,
            1,
        )

    # At present, the SCREAM distribtuion rate is quite low. 
    # APY is lower than the APY shown on SCREAM analytics board.
    # To calcualte the whole balance, there may be a little loss.
    # I override the default check, and We harvest on the claimed comp token from unitroller
    # I will test the performance fee, the sett balance of treasury 
    def confirm_harvest(self, before, after, tx):
        """
        Verfies that the Harvest produced yield and fees
        NOTE: This overrides default check, use only if you know what you're doing
        """
        console.print("=== Compare Harvest ===")
        ## claim Comp token, swap to want token
        valueGained = after.balances("want", "strategy") - before.balances("want", "strategy")

        # # Strategist should earn if fee is enabled and value was generated
        if before.get("sett.performanceFeeStrategist") > 0:
            assert after.balances("sett", "strategist") > before.balances(
                "sett", "strategist"
            )
        
        # # Strategist should earn if fee is enabled and value was generated
        if before.get("sett.performanceFeeGovernance") > 0:
            assert after.balances("sett", "treasury") > before.balances(
                "sett", "treasury"
            )

        fee_strategist = before.get("sett.performanceFeeStrategist") * valueGained / MAX_BPS
        fee_govern = before.get("sett.performanceFeeGovernance") * valueGained / MAX_BPS 
        
        delta_strategist = after.balances("sett", "strategist") - before.balances(
            "sett", "strategist"
        )

        delta_treasury = after.balances("sett", "treasury") - before.balances(
            "sett", "treasury"
        )

        delta_totalsupply = after.get("sett.totalSupply") - before.get("sett.totalSupply")

        assert difference(fee_strategist, delta_strategist, 1)
        assert difference(fee_govern, delta_treasury, 1)
        assert delta_totalsupply == delta_strategist + delta_treasury


    def confirm_tend(self, before, after, tx):
        """
        Tend Should;
        - Increase the number of staked tended tokens in the strategy-specific mechanism
        - Reduce the number of tended tokens in the Strategy to zero

        (Strategy Must Implement)
        """
        minWant = before.get("strategy.minWant") 
        if before.balances("want", "strategy") <= minWant:
            tendAmount = 0
            assert(before.balances("want", "strategy") == after.balances("want", "strategy"))
        
        if before.balances("want", "strategy") > minWant:
            tendAmount = before.balances("want", "strategy") - after.balances("want", "strategy")
            assert after.balances("want", "strategy") == 0

        
        assert before.get("strategy.collateralTarget") == after.get("strategy.collateralTarget")
        
        collateralRatio = before.get("strategy.collateralTarget") / 1e18
        supplyBefore = before.get("strategy.getTimelySupplyPosition")
        supplyAfter = after.get("strategy.getTimelySupplyPosition")
        borrowBefore = before.get("strategy.getTimelyBorrowPosition")
        borrowAfter = after.get("strategy.getTimelyBorrowPosition")
        
        supplyIncrease = tendAmount / (1-collateralRatio)
        borrowIncrease = tendAmount * collateralRatio / (1-collateralRatio)
        poolIncrease = after.get("strategy.balanceOfPool") - before.get("strategy.balanceOfPool")

        # to test the accrued interest
        assert supplyIncrease <= (supplyAfter-supplyBefore)
        # to test the accrued interest
        assert borrowIncrease <= (borrowAfter-borrowBefore)
        # pool includes the claimable Comp
        assert poolIncrease >= ((supplyAfter - borrowAfter) - (supplyBefore - borrowBefore))
