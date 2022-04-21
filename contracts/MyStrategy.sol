// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {BaseStrategy} from "@badger-finance/BaseStrategy.sol";

import "../interfaces/IComptroller.sol";
import "../interfaces/IUniswapV2Router02.sol";
import "../interfaces/IVToken.sol";
import "../interfaces/IERC20Extended.sol";
import "../interfaces/IVault.sol";

import "@openzeppelin-contracts-upgradeable/math/MathUpgradeable.sol";

contract MyStrategy is BaseStrategy {
    // constant SCREAM address
    address public constant comptroller = 0x260E596DAbE3AFc463e75B6CC05d8c46aCAcFB09; //Scream unitroller address
    address public constant iToken = 0x4565DC3Ef685E4775cdF920129111DdF43B9d882; //iToken address scWBtc
    address public constant screamToken = 0xe0654C8e6fd4D733349ac7E09f6f23DA256bF475; //claimComp Token address; SCREAM token
    address public constant wftmToken = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83; //wFtm Token address
    address[] public markets; //Scream Markets, here is just scWBtc

    // constant swap address using Spooky Swap
    address public constant unirouter = 0xF491e7B69E4244ad4002BC14e878a34207E38c29; //Spooky Swap address
    address[] public swapToWantRoute; //Scream -> WFtm -> WBtc, three address

    uint256 public minWant; // the minimum want balance to leverage or deleverage
    uint256 public minScreamWant; // the minimum scream balance to swap
    uint256 public collateralTarget; // borrow/supply, the collateralTarget to control the leverage ratio, scaled by 1e18
    uint256 public borrowDepth; // the number of leverage levels we will stake and borrow
    uint256 public debt; // debt from vault, deposit from vault will increas debt; withdraw from vault will decrease debt

    // comptorller distribution params
    // to restore varialbes to calculate the comp distribution
    struct DistributionParams {
        uint256 _lastSupplyBlock;
        uint256 _lastBorrowBlock;
        uint256 _sharesSupply;
        uint256 _sharesBorrow;
        uint256 _sharesAccrued;
    }

    // // for test; to record sett params
    // struct settParams {
    //     uint256 _withdrawalFee;
    //     uint256 _settTotalSupply;
    //     uint256 _settBalance;
    // }

    //Emitted when claimComp harvest
    event ClaimCompHarvested(address indexed token, uint256 amount, uint256 indexed blockNumber, uint256 timestamp);

    // event for test //
    // event TestBorrowIncrease(uint256 _amount, uint256 _supplys, uint256 _borrows, uint256 _desireBorrows);
    // event TestHarverstCurrentPosition(uint256 _testsupplys, uint256 _testborrows);
    // event TestHarverstAfterClaimcomp(
    //     uint256 _supplys,
    //     uint256 _borrows,
    //     uint256 _claimAsset,
    //     uint256 _screamAsset,
    //     uint256 _netAsset,
    //     uint256 debt
    // );
    // event TestHarvestClaimComp(uint256 ScreamTokenBefore, uint256 ScreamTokenAfter, uint256 wantBalanceBefore, uint256 AccruedInterestLeft);
    // event TestDepositDebtUpdate(uint256 debtUpdated, uint256 debtIncrease);
    // event TestDepositEnd(uint256 _testsupplys, uint256 _testborrows);
    // event TestIncreaseBorrowBegin(uint256 borrowToIncrease, uint256 stakeAmount, uint256 collateralFactorMantissa);
    // event TestIncreaseBorrowLeverageRound(uint256 borrowToIncrease, uint256 stakeAmount, uint256 borrowPositionChange, uint256 roundTime);
    // event TestLeverageBegin(uint256 wantbalance, uint256 tostakeamount, uint256 borrowbalancetoincrease);

    // event TestWithsomRelBorrowAfter(uint256 _tempWantBalance, uint256 _tempSupplys, uint256 _tempBorrows);
    // event TestWithsomRelBorrowAfterLast(uint256 _tempWantBalance, uint256 _tempSupplys, uint256 _tempBorrows);

    // event TestDeleverageBegin(uint256 _borrowPostionChange, uint256 _desirePostionChange, uint256 _currentSupplys, uint256 _currentBorrows);
    // event TestReleaseBorrowBegin(uint256 _DesiredReleaseBorrow, uint256 _collateralFactorMantissa);
    // event TestReleaseBorrowDeleverageRound(
    //     uint256 _DesiredReleaseBorrow,
    //     uint256 _currentSupply,
    //     uint256 _currentBorrow,
    //     uint256 _ReleaseBorrowAmount,
    //     uint256 _round
    // );

    // event TestWithdrawSomeLossCalculate(
    //     uint256 _amount,
    //     uint256 _amountActual,
    //     uint256 _loss,
    //     uint256 debt,
    //     uint256 _withdrawFee,
    //     uint256 _settTotalSupply,
    //     uint256 _settBalance
    // );
    // event TestWithdrawSomeStart(uint256 _amountToWithdraw, uint256 _wantBalance, uint256 _supplys, uint256 _borrows, uint256 _netposition);
    // event TestWithdrawSomeNetLessThanAmount(uint256 _positionChange, uint256 _supplys, uint256 _borrows);
    // event TestSwapComp(uint256 outputBal);
    // event TestWithdrawAll(uint256 _wantBal);
    // event TestWithdrawAll(uint256 _beforeWantBalance, uint256 _wantBal, uint256 _tempStraBalanceofBefore, uint256 _tempStraBalanceofAfter);
    // event TestReleaseBorrow(uint256 _supplys, uint256 _aftersupplys, uint256 _borrows, uint256 _afterborrows);

    /**
        @dev Initialize the Strategy with security settings as well as tokens
        @param _vault vault address, this strategy belongs to this vault
        @param _wantConfig want token address, the underlying token address  
    */
    function initialize(address _vault, address[1] memory _wantConfig) public initializer {
        __BaseStrategy_init(_vault);

        want = _wantConfig[0];

        borrowDepth = 5;

        minWant = uint256(uint256(10)**uint256((IERC20Extended(address(want))).decimals())).div(1e5);

        minScreamWant = uint256(uint256(10)**uint256((IERC20Extended(address(screamToken))).decimals())).div(1e5);

        collateralTarget = uint256(1e16).mul(uint256(68)); //0.68 ether

        // set allownance
        _setAllowances();

        // swap to want path
        swapToWantRoute = new address[](3);
        swapToWantRoute[0] = screamToken;
        swapToWantRoute[1] = wftmToken;
        swapToWantRoute[2] = want;

        // enter markets to stake and borrow in Scream
        markets.push(iToken);
        IComptroller(comptroller).enterMarkets(markets);
    }

    /**
        @dev Return the name of the strategy
        @return memory the name of the strategy
    */
    function getName() external pure override returns (string memory) {
        return "StrategyBadger-ScreamWBtc";
    }

    /**
        @dev Return a list of protected tokens
        @notice It's very important all tokens that are meant to be in the strategy to be marked as protected
        @notice this provides security guarantees to the depositors they can't be sweeped away
    */
    function getProtectedTokens() public view virtual override returns (address[] memory) {
        address[] memory protectedTokens = new address[](4);
        protectedTokens[0] = want;
        protectedTokens[1] = iToken;
        protectedTokens[2] = wftmToken;
        protectedTokens[3] = screamToken;
        return protectedTokens;
    }

    /**
        @dev deposit want token into this strategy, leverage to reach the collateralTarget
        @param _amount the amount of want token balance to deposit
     */
    function _deposit(uint256 _amount) internal override {
        if (_amount < minWant) {
            return;
        }
        // to record debt from vault
        debt = debt.add(_amount);

        // for test
        // emit TestDepositDebtUpdate(debt, _amount);

        // to calculate how much borrow balance to need
        uint256 _positionChange = borrowPositionNeedtoIncrease(_amount);

        // to increase the borrow balance, just to leverage
        _IncreaseBorrow(_positionChange, _amount);

        /** for test */
        // (uint256 _testsupplys, uint256 _testborrows) = getCurrentPosition();

        // emit TestDepositEnd(_testsupplys, _testborrows);
    }

    /**
        @dev withdraw all funds, this is used for migrations, most of the time for emergency reasons
        @notice deleverage all, and send all underlying tokes to vault
    */
    function _withdrawAll() internal override {
        (uint256 _supplys, uint256 _borrows) = getTimelyPosition();
        // uint256 _netposition = _supplys.sub(_borrows);

        // for test
        // uint256 _beforeWantBalance = IERC20Upgradeable(want).balanceOf(address(this));
        // uint256 _tempStraBalanceofBefore = balanceOfWant().add(balanceOfPool());

        _ReleaseBorrow(_borrows);

        swapComp();

        // for test
        // uint256 _wantBal = IERC20Upgradeable(want).balanceOf(address(this));
        // uint256 _tempStraBalanceofAfter = balanceOfWant().add(balanceOfPool());
        // emit TestWithdrawAll(_beforeWantBalance, _wantBal, _tempStraBalanceofBefore, _tempStraBalanceofAfter);

        uint256 _wantBal = IERC20Upgradeable(want).balanceOf(address(this));
        IERC20Upgradeable(want).safeTransfer(vault, _wantBal);

        // update debt from vault
        // debt = debt.sub(wantBal);
    }

    function swapComp() internal {
        uint256 outputBal = IERC20Upgradeable(screamToken).balanceOf(address(this));

        // // for test
        // emit TestSwapComp(outputBal);

        if (outputBal > minScreamWant) {
            IUniswapV2Router02(unirouter).swapExactTokensForTokens(outputBal, 0, swapToWantRoute, address(this), now);
        }
    }

    /**
        @dev withdraw `_amount` of want, so that it can be sent to the vault
        @param _amount amount of want to withdraw
        @return _amountActual acturally withdrawn amount of want 
    */
    function _withdrawSome(uint256 _amount) internal override returns (uint256) {
        uint256 _balance = IERC20Upgradeable(want).balanceOf(address(this));
        (uint256 _supplys, uint256 _borrows) = getTimelyPosition();
        uint256 _netposition = _supplys.add(_balance).sub(_borrows);

        // /** for test */
        // emit TestWithdrawSomeStart(_amount, _balance, _supplys, _borrows, _netposition);

        uint256 _amountActual = 0;
        uint256 _positionChange = 0;
        uint256 _tempBalance = 0;
        uint256 _tempSupplys = 0;
        uint256 _tempBorrows = 0;
        //  if netposition cannot cover withdrawal amount
        if (_netposition < _amount) {
            //  may test the rounding error, netposition is too small
            if (IERC20Upgradeable(iToken).balanceOf(address(this)) > 1) {
                // to calculate the borrow position change
                _positionChange = borrowPositionNeedtoReduce(_supplys.sub(_borrows));

                // /** for test */
                // emit TestWithdrawSomeNetLessThanAmount(_positionChange, _supplys, _borrows);

                _ReleaseBorrow(_positionChange);

                // for test
                // _tempBalance = IERC20Upgradeable(want).balanceOf(address(this));
                // (_tempSupplys, _tempBorrows) = getTimelyPosition();

                // // for test
                // emit TestWithsomRelBorrowAfter(_tempBalance, _tempSupplys, _tempBorrows);

                _amountActual = MathUpgradeable.min(_amount, IERC20Upgradeable(want).balanceOf(address(this)));
            }
        }
        // if netposition can cover withdrawal amount
        else {
            if (_balance < _amount) {
                // withdraw some asset
                _positionChange = borrowPositionNeedtoReduce(_amount.sub(_balance));

                _ReleaseBorrow(_positionChange);

                _amountActual = MathUpgradeable.min(_amount, IERC20Upgradeable(want).balanceOf(address(this)));
            }
            // want token balance is enough to cover withdrawal amount
            else {
                _amountActual = _amount;
            }
        }

        uint256 _loss = _amount.sub(_amountActual);

        // for test
        // settParams memory TestSettParams;
        // TestSettParams._withdrawalFee = IVault(vault).withdrawalFee();
        // TestSettParams._settTotalSupply = IVault(vault).totalSupply();
        // TestSettParams._settBalance = IVault(vault).balance();
        // emit TestWithdrawSomeLossCalculate(
        //     _amount,
        //     _amountActual,
        //     _loss,
        //     debt,
        //     TestSettParams._withdrawalFee,
        //     TestSettParams._settTotalSupply,
        //     TestSettParams._settBalance
        // );

        require(_loss.mul(MAX_BPS).div(_amount) <= withdrawalMaxDeviationThreshold, "Withdrawal Loss is too large!");

        // update debt from vault
        // debt = debt.sub(_amountActual);

        // Swap from scream token to want token
        // uint256 outputBal = IERC20Upgradeable(screamToken).balanceOf(address(this));
        // IUniswapV2Router02(unirouter).swapExactTokensForTokens(outputBal, 0, swapToWantRoute, address(this), now);
        swapComp();

        return _amountActual;
    }

    /**
        @dev increase borrow balance
        @param _amount the borrow balance need to leverage
        @param _stake the supply want token balance 
        @return notAll if the unwind times more than iteration 
    */
    function _IncreaseBorrow(uint256 _amount, uint256 _stake) internal returns (bool notAll) {
        uint256 i = 0;
        uint256 _tempPositionChange = 0;
        (, uint256 _collateralFactorMantissa, ) = IComptroller(comptroller).markets(address(iToken));

        /** for test */
        // emit TestIncreaseBorrowBegin(_amount, _stake, _collateralFactorMantissa);

        while (_amount > minWant) {
            _tempPositionChange = _Leverage(_amount, _stake, _collateralFactorMantissa);

            /** for test */
            // emit TestIncreaseBorrowLeverageRound(_amount, _stake, _tempPositionChange, i);

            _amount = _amount.sub(_tempPositionChange);

            // every borrowed token can be used to deposit again
            _stake = _tempPositionChange;
            i++;
            // stake the last time borrowed token balance
            if (_amount < minWant) {
                IVToken(iToken).mint(_stake);
            } else if (i >= borrowDepth) {
                IVToken(iToken).mint(_stake);
                notAll = true;
                break;
            }
        }
    }

    /**
        @dev release borrow balance
        @param _amount the borrow balance need to deleverage
        @return notAll if the unwind times more than iteration 
    */
    function _ReleaseBorrow(uint256 _amount) internal returns (bool notAll) {
        // if the position change is tiny, do nothing
        uint8 i = 0;
        uint256 _tempPositionChange = 0;
        (, uint256 _collateralFactorMantissa, ) = IComptroller(comptroller).markets(address(iToken));

        // for test
        // emit TestReleaseBorrowBegin(_amount, _collateralFactorMantissa);

        while (_amount > minWant) {
            (uint256 _tempSupply, uint256 _tempBorrow) = getCurrentPosition();
            _tempPositionChange = _Deleverage(_amount, _tempSupply, _tempBorrow, _collateralFactorMantissa);

            /** for test */
            // emit TestReleaseBorrowDeleverageRound(_amount, _tempSupply, _tempBorrow, _tempPositionChange, i);

            _amount = _amount.sub(_tempPositionChange);
            i++;
            if (i >= borrowDepth) {
                notAll = true;
                break;
            }
        }

        // redeem the underlying token
        // to adjust to the desired collateral ratio
        (uint256 _supplys, uint256 _borrows) = getTimelyPosition();
        uint256 _reservedSupply = 0;
        _reservedSupply = _borrows.mul(1e18).div(collateralTarget);
        if (_supplys > _reservedSupply) {
            uint256 _redeemable = _supplys.sub(_reservedSupply);
            IVToken(iToken).redeemUnderlying(_redeemable);
        }

        // for test
        // (uint256 _aftersupplys, uint256 _afterborrows) = getTimelyPosition();
        // emit TestReleaseBorrow(_supplys, _aftersupplys, _borrows, _afterborrows);
    }

    /**
        @dev
        @param _amount  the amount of borrowed balance to deleverage
        @param _stake the amount to supply
        @param _collateralRatio the present collateral Ration of this market in unitroller
        @return _positionChange the actual borrow position change in this delevrage action
     */
    function _Leverage(
        uint256 _amount,
        uint256 _stake,
        uint256 _collateralRatio
    ) internal returns (uint256 _positionChange) {
        uint256 _balance = IERC20Upgradeable(want).balanceOf(address(this));

        /** for test */
        // emit TestLeverageBegin(_balance, _stake, _amount);

        if (_balance < _stake) {
            _stake = _balance;
        }

        IVToken(iToken).mint(_stake);
        _positionChange = _stake.mul(_collateralRatio).div(1e18);
        // make sure position change does not exceed what we need
        if (_positionChange >= _amount) {
            _positionChange = _amount;
        }
        // to reduce the position slightly, prevent exceeding the limit
        _positionChange = _positionChange.sub(uint256(10));
        IVToken(iToken).borrow(_positionChange);
    }

    /**
        @dev
        @param _amount  the amount of borrowed balance to deleverage
        @param _supplys the present amount of supply balance
        @param _borrows the present amount of borrow balance
        @param _collateralRatio the present collateral Ration of this market in unitroller
        @return _positionChange the actual borrow position change in this delevrage action
     */
    function _Deleverage(
        uint256 _amount,
        uint256 _supplys,
        uint256 _borrows,
        uint256 _collateralRatio
    ) internal returns (uint256 _positionChange) {
        if (_borrows == 0) {
            return 0;
        }
        uint256 _desireSupplys = _borrows.mul(1e18).div(_collateralRatio);
        _positionChange = _supplys.sub(_desireSupplys);

        // position change shoulde be less than the overall borrows
        if (_positionChange >= _borrows) {
            _positionChange = _borrows;
        }
        // position change should be less then the postion change needed
        if (_positionChange >= _amount) {
            _positionChange = _amount;
        }

        // rounding error may exceed the limit
        _positionChange = _positionChange.sub(uint256(10));

        /** for test */
        // emit TestDeleverageBegin(_positionChange, _amount, _supplys, _borrows);

        IVToken(iToken).redeemUnderlying(_positionChange);
        IVToken(iToken).repayBorrow(_positionChange);
    }

    /**
        @dev Get the timely strategy balance of iToken
        @notice Have accrued interest
        @return _supplys the supply balance of this strategy
        @return _borrows the borrow balance of this strategy 
     */
    function getTimelyPosition() public returns (uint256 _supplys, uint256 _borrows) {
        // accrue interst, exchangeRate * accountTokens[ownver] / 1e18(truncate)
        _supplys = IVToken(iToken).balanceOfUnderlying(address(this));
        // have accrued interest in the above function
        // accountBorrows[account].principal * borrowIndex / accountBorrows[account].interestIndex
        _borrows = IVToken(iToken).borrowBalanceStored(address(this));
    }

    function getTimelySupplyPosition() public returns (uint256 _supplys) {
        _supplys = IVToken(iToken).balanceOfUnderlying(address(this));
    }

    function getTimelyBorrowPosition() public returns (uint256 _borrows) {
        // the function is often called after getTimelySupplyPosition()
        _borrows = IVToken(iToken).borrowBalanceStored(address(this));
    }

    /**
        @dev Get the current postion by stored variable
        @notice Donot accrue interest
        @return _supplys the supply balance of this strategy
        @return _borrows the borrow balance of this strategy 
     */
    function getCurrentPosition() public view returns (uint256 _supplys, uint256 _borrows) {
        (, uint256 _itokenBalance, uint256 _borrowBalance, uint256 _exchangeRate) = IVToken(iToken).getAccountSnapshot(address(this));

        _borrows = _borrowBalance;

        // to be the same with balanceOfUnderlying result
        _supplys = _itokenBalance.mul(_exchangeRate).div(1e18);
    }

    /**
        @dev When withdrawing, to calculate the borrow position needed to reduce
        @param _amount the want token amount to withdraw
        @return _position the borrow position needed to reduce when withdrawing
    */
    function borrowPositionNeedtoReduce(uint256 _amount) internal view returns (uint256 _position) {
        // This function is called after getTimelyPosition, have accrued interest
        // Just use the stored value
        (uint256 _supplys, uint256 _borrows) = getCurrentPosition();
        uint256 _netDeposits = _supplys.sub(_borrows);
        uint256 _desireDeposits = 0;

        // the most amount to deposit change is _netDeposits
        if (_amount > _netDeposits) {
            _amount = _netDeposits;
        }
        _desireDeposits = _netDeposits.sub(_amount);

        // to calculate the desired borrow
        // borrow = deposit*c/(1-c);   c = borrow/(borrow+deposit)
        uint256 _desireBorrows = _desireDeposits.mul(collateralTarget).div(uint256(1e18).sub(collateralTarget));

        // borrow position change
        _position = _borrows.sub(_desireBorrows);
    }

    /**
        @dev When depositing, to calculate the borrow position needed to increase
        @param _amount the want token amount to deposit
        @return _position the borrow position needed to increase when depositing
    */
    function borrowPositionNeedtoIncrease(uint256 _amount) internal returns (uint256 _position) {
        // This function is called after getTimelyPosition, have accrued interest
        // Just use the stored value
        (uint256 _supplys, uint256 _borrows) = getTimelyPosition();
        uint256 _netDeposits = _supplys.sub(_borrows);
        uint256 _desireDeposits = 0;

        _desireDeposits = _netDeposits.add(_amount);

        // to calculate the desired borrow
        // borrow = deposit*c/(1-c);   c = borrow/(borrow+deposit)
        uint256 _desireBorrows = _desireDeposits.mul(collateralTarget).div(uint256(1e18).sub(collateralTarget));

        // borrow position change
        // generally the desireBorrows is more than borrows
        // but if the supply accrued interest is less than the borrow accrued interest, and the deposit amount is very small
        // the desireBorrows will be less than the borrows. In this case, _position is set to be 0, and just mint the left token.
        if (_desireBorrows > _borrows) {
            _position = _desireBorrows.sub(_borrows);
        } else {
            _position = 0;
            IVToken(iToken).mint(_amount);
        }
    }

    /**
        @dev to set the strategy is tendable or not
        @notice here to tend is to deposit all extrat want token
    */
    function _isTendable() internal pure override returns (bool) {
        return true; // Change to true if the strategy should be tended
    }

    /**
        @dev harvest the SCREAM token, called by harvest() external function
        @notice core internal function to harvest
    */
    function _harvest() internal override returns (TokenAmount[] memory harvested) {
        //  for test
        // (uint256 _testsupplys, uint256 _testborrows) = getCurrentPosition();
        // emit TestHarverstCurrentPosition(_testsupplys, _testborrows);

        harvested = new TokenAmount[](1);

        if (IComptroller(comptroller).pendingComptrollerImplementation() == address(0)) {
            (uint256 _supplys, uint256 _borrows) = getTimelyPosition();
            uint256 _wantBalanceBeforeClaim = IERC20Upgradeable(screamToken).balanceOf(address(this));

            uint256 _wantBalanceBegin = IERC20Upgradeable(want).balanceOf(address(this));

            // Get the SCREAM Token Reward
            IComptroller(comptroller).claimComp(address(this), markets);
            uint256 outputBal = IERC20Upgradeable(screamToken).balanceOf(address(this));

            // // for test
            // uint256 testAccruedInterestLeft = IComptroller(comptroller).compAccrued(address(this));
            // emit TestHarvestClaimComp(_wantBalanceBeforeClaim, outputBal, testwantBalance, testAccruedInterestLeft);

            harvested[0] = TokenAmount(screamToken, outputBal);
            // Swap from scream token to want token
            if (outputBal > minScreamWant) {
                IUniswapV2Router02(unirouter).swapExactTokensForTokens(outputBal, 0, swapToWantRoute, address(this), now);
            }

            // to calculate the claim Gain
            uint256 _wantBalance = IERC20Upgradeable(want).balanceOf(address(this));

            uint256 _netAsset = _supplys.add(_wantBalance).sub(_borrows);

            // for test
            // emit TestHarverstAfterClaimcomp(_supplys, _borrows, _wantBalance, outputBal, _netAsset, debt);

            // Here just refer to claim Comp as harvest gain
            uint256 _claimGain = _wantBalance.sub(_wantBalanceBegin);

            // report the amount of want harvested to the sett and calculate the fee
            // If consider borrow and supply balance in iToken, the amout is higher than the whole estimated profit.
            // But borrow and supply balance is not leveraged and converted to underlying token, the whole estimated profict
            // is an estimate, not the real profit. There is no need to deleverage and leverage all tokens just to
            // get the real profit.
            emit ClaimCompHarvested(address(want), _claimGain, block.number, block.timestamp);
            _reportToVault(_claimGain);
        } else {
            // scream is not working, pause now
            _pause();
            _withdrawAll();
            _removeAllowances();
            harvested[0] = TokenAmount(screamToken, 0);
        }

        return harvested;
    }

    /**
        @dev Leverage any left want token
        @return tended  the leveraged want token balance
    */
    function _tend() internal override returns (TokenAmount[] memory tended) {
        // to deposit the left want token
        uint256 _balance = IERC20Upgradeable(want).balanceOf(address(this));
        tended = new TokenAmount[](1);

        if (_balance > minWant) {
            // There are some token left, go on leveraging
            uint256 _positionChange = borrowPositionNeedtoIncrease(_balance);
            _IncreaseBorrow(_positionChange, _balance);
            tended[0] = TokenAmount(want, _balance);
        } else {
            tended[0] = TokenAmount(want, 0);
        }

        return tended;
    }

    /**
        @dev This function makes a prediction on how much comp is accrued
        @return the available comp amount but not be accrued
        @notice estimate is not very exact, we use the past data to predict the future
     */
    function predictCompAccrued() public view returns (uint256) {
        uint256 _distributionPerBlockSupply;
        uint256 _distributionPerBlockBorrow;

        // Scream utilizes the same distribution rate for Supply and Borrow
        _distributionPerBlockSupply = IComptroller(comptroller).compSpeeds(iToken);
        _distributionPerBlockBorrow = _distributionPerBlockSupply;

        (uint256 _supplys, uint256 _borrows) = getCurrentPosition();

        uint256 _totalSupplyToken = IVToken(iToken).totalSupply();
        uint256 _totalBorrows = IVToken(iToken).totalBorrows();

        uint256 _totalSupply = _totalSupplyToken.mul(IVToken(iToken).exchangeRateStored()).div(1e18);

        // supply block distribution belongs to this strategy
        uint256 _blockShareSupply = 0;
        if (_totalSupply > 0) {
            _blockShareSupply = _supplys.mul(_distributionPerBlockSupply).div(_totalSupply);
        }

        // borrow block distribution belongs to this strategy
        uint256 _blockShareBorrow = 0;
        if (_totalBorrows > 0) {
            _blockShareBorrow = _borrows.mul(_distributionPerBlockBorrow).div(_totalBorrows);
        }

        // Distribution Calculation
        DistributionParams memory Dparams;
        Dparams._lastSupplyBlock = IComptroller(comptroller).compSupplyState(iToken).block;
        Dparams._lastBorrowBlock = IComptroller(comptroller).compBorrowState(iToken).block;
        Dparams._sharesSupply = _blockShareSupply * (getBlockNumber().sub(Dparams._lastSupplyBlock));
        Dparams._sharesBorrow = _blockShareBorrow * (getBlockNumber().sub(Dparams._lastBorrowBlock));

        // get the accrued distribution but not transfer
        Dparams._sharesAccrued = IComptroller(comptroller).compAccrued(address(this));

        return (Dparams._sharesSupply).add(Dparams._sharesBorrow).add(Dparams._sharesAccrued);
    }

    /**
        @dev to get the balance in pool
        @notice the unaccrued Comp needs to estimate
        @return _balanceInPool the balance in pool
    */
    function balanceOfPool() public view override returns (uint256 _balanceInPool) {
        (uint256 _supplys, uint256 _borrows) = getCurrentPosition();

        // the estimate claimable comp, but not transferred
        uint256 _compPredict = predictCompAccrued();

        uint256 _compBal = IERC20Upgradeable(screamToken).balanceOf(address(this));
        uint256 _claimableComp = _compBal.add(_compPredict);

        if (_claimableComp > 0) {
            // get the exchange value from comp to want
            uint256[] memory tempAmounts = IUniswapV2Router02(unirouter).getAmountsOut(_claimableComp, swapToWantRoute);
            _claimableComp = tempAmounts[tempAmounts.length - 1];

            _balanceInPool = _supplys.add(_claimableComp).sub(_borrows);
        } else {
            _balanceInPool = _supplys.sub(_borrows);
        }
    }

    /**
        @dev Return the balance of rewards that the strategy has accrued
        @notice Used for offChain APY and Harvest Health monitoring
    */
    function balanceOfRewards() public view override returns (TokenAmount[] memory rewards) {
        rewards = new TokenAmount[](1);
        rewards[0] = TokenAmount(screamToken, IERC20Upgradeable(screamToken).balanceOf(address(this)));
        return rewards;
    }

    /**
        @dev set min want token balance to deal with
        @param _minWant the amount of want token balance
    */
    function setMinWant(uint256 _minWant) external {
        _onlyAuthorizedActors();
        minWant = _minWant;
    }

    /**
        @dev set Collateral Target
        @param _collateralTarget the target ration, scaled by 1e18
        @notice require collateralTarget > 0 and < _collateralFactorMantissa (system collateral ratio)
    */
    function setCollateralTarget(uint256 _collateralTarget) external {
        _onlyAuthorizedActors();
        (, uint256 _collateralFactorMantissa, ) = IComptroller(comptroller).markets(address(iToken));
        // require collateralFactor > 0 and < collateralFactorMantissa
        require(_collateralFactorMantissa > _collateralTarget && _collateralTarget > 0);
        collateralTarget = _collateralTarget;
    }

    /**
        @dev set allowance
    */
    function _setAllowances() internal {
        IERC20Upgradeable(want).safeApprove(iToken, uint256(-1));
        IERC20Upgradeable(screamToken).safeApprove(unirouter, uint256(-1));
    }

    /**
        @dev remove allowance
    */
    function _removeAllowances() internal {
        IERC20Upgradeable(want).safeApprove(iToken, 0);
        IERC20Upgradeable(screamToken).safeApprove(unirouter, 0);
    }

    /**
        @dev pause the strategy from governance or keeper
    */
    function pauseStrategy() external {
        _onlyAuthorizedActors();

        _pause();
        _withdrawAll();
        _removeAllowances();
    }

    /**
        @dev unpause the strategy from governance or keeper
    */
    function unpauseStrategy() external {
        _onlyAuthorizedActors();

        _unpause();
        _setAllowances();
        uint256 _balance = IERC20Upgradeable(want).balanceOf(address(this));
        if (_balance > minWant) {
            // There are some token left, go on leveraging
            uint256 _positionChange = borrowPositionNeedtoIncrease(_balance);
            _IncreaseBorrow(_positionChange, _balance);
        }
    }

    /**
        @dev get the current block number, and return it
    */
    function getBlockNumber() public view returns (uint256) {
        return block.number;
    }
}
