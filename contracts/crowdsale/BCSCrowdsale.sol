pragma solidity ^0.4.10;

import '../token/ITokenPool.sol';
import '../token/ReturnTokenAgent.sol';
import '../common/Manageable.sol';
import '../common/SafeMath.sol';
import './IInvestRestrictions.sol';
import './ICrowdsaleFormula.sol';

/**@dev Crowdsale base contract, used for PRE-TGE and TGE stages
* Token holder should also be the owner of this contract */
contract BCSCrowdsale is ICrowdsaleFormula, Manageable, SafeMath {

    enum State {Unknown, BeforeStart, Active, FinishedSuccess, FinishedFailure}
    
    ITokenPool public tokenPool;
    IInvestRestrictions public restrictions; //restrictions on investment
    address public beneficiary; //address of contract to collect ether
    uint256 public startTime; //unit timestamp of start time
    uint256 public endTime; //unix timestamp of end date
    uint256 public minimumGoalInWei; //TODO or in tokens
    uint256 public tokensForOneEther; //how many tokens can you buy for 1 ether   
    uint256 realAmountForOneEther; //how many tokens can you buy for 1 ether * 10**decimals   
    uint256 bonusPct;   //additional percent of tokens    
    bool public withdrew; //true if beneficiary already withdrew

    uint256 public weiCollected;
    uint256 public tokensSold;

    bool public failure; //true if some error occurred during crowdsale

    mapping (address => uint256) public investedFrom; //how many wei specific address invested
    mapping (address => uint256) public tokensSoldTo; //how many tokens sold to specific addreess
    mapping (address => uint256) public overpays;     //overpays for send value excesses

    // A new investment was made
    event Invested(address investor, uint weiAmount, uint tokenAmount);
    // Refund was processed for a contributor
    event Refund(address investor, uint weiAmount);
    // Overpay refund was processed for a contributor
    event OverpayRefund(address investor, uint weiAmount);

    /**@dev Crowdsale constructor, can specify startTime as 0 to start crowdsale immediately 
    _tokensForOneEther - doesn't depend on token decimals   */ 
    function BCSCrowdsale(        
        ITokenPool _tokenPool,
        IInvestRestrictions _restrictions,
        address _beneficiary, 
        uint256 _startTime, 
        uint256 _durationInHours, 
        uint256 _goalInWei,
        uint256 _tokensForOneEther,
        uint256 _bonusPct) 
    {
        require(_beneficiary != 0x0);
        require(address(_tokenPool) != 0x0);
        require(_durationInHours > 0);
        require(_tokensForOneEther > 0); 
        
        tokenPool = _tokenPool;
        beneficiary = _beneficiary;
        restrictions = _restrictions;
        
        if (_startTime == 0) {
            startTime = now;
        } else {
            startTime = _startTime;
        }
        endTime = (_durationInHours * 1 hours) + startTime;
        //endTime = (_durationInHours * 1 minutes) + startTime;
        
        tokensForOneEther = _tokensForOneEther;
        minimumGoalInWei = _goalInWei;
        bonusPct = _bonusPct;

        weiCollected = 0;
        tokensSold = 0;
        failure = false;
        withdrew = false;

        realAmountForOneEther = tokenPool.token().getRealTokenAmount(tokensForOneEther);
    }

    function() payable {
        invest();
    }

    function invest() payable {
        require(canInvest(msg.sender, msg.value));
        
        uint256 excess;
        uint256 weiPaid = msg.value;
        uint256 tokensToBuy;
        (tokensToBuy, excess) = howManyTokensForEther(weiPaid);

        require(tokensToBuy <= tokensLeft() && tokensToBuy > 0);

        if (excess > 0) {
            overpays[msg.sender] = safeAdd(overpays[msg.sender], excess);
            weiPaid = safeSub(weiPaid, excess);
        }
        
        investedFrom[msg.sender] = safeAdd(investedFrom[msg.sender], weiPaid);      
        tokensSoldTo[msg.sender] = safeAdd(tokensSoldTo[msg.sender], tokensToBuy);
        
        tokensSold = safeAdd(tokensSold, tokensToBuy);
        weiCollected = safeAdd(weiCollected, weiPaid);

        if(address(restrictions) != 0x0) {
            restrictions.investHappened(msg.sender, msg.value);
        }
        
        require(tokenPool.token().transferFrom(tokenPool, msg.sender, tokensToBuy));

        Invested(msg.sender, weiPaid, tokensToBuy);
    }

    /**@dev Returns true if it is possible to invest */
    function canInvest(address investor, uint256 amount) constant returns(bool) {
        return getState() == State.Active &&
                    (address(restrictions) == 0x0 || 
                    restrictions.canInvest(investor, amount, tokensLeft()));
    }

    /**@dev ICrowdsaleFormula override */
    function howManyTokensForEther(uint256 weiAmount) constant returns(uint256 tokens, uint256 excess) {        
        uint256 bpct = getCurrentBonusPct();        
        uint256 maxTokens = (tokensLeft() * 100) / (100 + bpct);

        tokens = weiAmount * realAmountForOneEther / 1 ether;
        if (tokens > maxTokens) {
            tokens = maxTokens;
        }

        excess = weiAmount - tokens * 1 ether / realAmountForOneEther;

        tokens = (tokens * 100 + tokens * bpct) / 100;
    }

    /**@dev Returns current bonus percent [0-100] */
    function getCurrentBonusPct() constant returns (uint256) {
        return bonusPct;
    }
    
    /**@dev Returns how many tokens left for sale */
    function tokensLeft() constant returns(uint256) {        
        return tokenPool.getTokenAmount();
    }

    // function forbiddenTokens(address investor) constant returns(uint256) {
    //     return address(restrictions) == 0x0 ? 0 : restrictions.forbiddenTokens(investor);
    // }

    /**@dev Returns funds that should be sent to beneficiary */
    function amountToBeneficiary() constant returns (uint256) {
        return weiCollected;
    } 

    /**@dev Returns crowdsale current state */
    function getState() constant returns (State) {
        if (failure) {
            return State.FinishedFailure;
        }
        
        if (now < startTime) {
            return State.BeforeStart;
        } else if (now < endTime && tokensLeft() > 0) {
            return State.Active;
        } else if (weiCollected >= minimumGoalInWei || tokensLeft() <= 0) {
            return State.FinishedSuccess;
        } else {
            return State.FinishedFailure;
        }
    }

    /**@dev Allows investors to withdraw funds and overpays in case of crowdsale failure */
    function refund() {
        require(getState() == State.FinishedFailure);

        uint amount = investedFrom[msg.sender];        

        if (amount > 0) {
            investedFrom[msg.sender] = 0;
            weiCollected = safeSub(weiCollected, amount);            
            msg.sender.transfer(amount);
            
            Refund(msg.sender, amount);            
        }
    }    

    /**@dev Allows investor to withdraw overpay */
    function withdrawOverpay() {
        uint amount = overpays[msg.sender];
        overpays[msg.sender] = 0;        

        if (amount > 0) {
            if (msg.sender.send(amount)) {
                OverpayRefund(msg.sender, amount);
            } else {
                overpays[msg.sender] = amount; //restore funds in case of failed send
            }
        }
    }

    /**@dev Transfers all collected funds to beneficiary*/
    function transferToBeneficiary() {
        require(getState() == State.FinishedSuccess && !withdrew);
        
        withdrew = true;
        uint256 amount = amountToBeneficiary();

        beneficiary.transfer(amount);
        Refund(beneficiary, amount);
    }

    /**@dev Makes crowdsale failed/ok, for emergency reasons */
    function makeFailed(bool state) managerOnly {
        failure = state;
    }

    /**@dev Sets new beneficiary */
    function changeBeneficiary(address newBeneficiary) managerOnly {
        beneficiary = newBeneficiary;
    }

    /***********************************************************************************************
    * temp dev methods 
    ***********************************************************************************************/
    // function changeEndTime(uint256 newTime) {
    //     endTime = newTime;
    // }
}