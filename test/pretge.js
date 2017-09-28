//
//
// Pretge process - create restrictions and pool and lock tokens
//
//

var Web3 = require("web3");
var web3 = new Web3(new Web3.providers.HttpProvider("http://localhost:8545"));
var utils = new (require("./timeutils.js"))(web3);

var Token = artifacts.require("BCSToken");
var token;

var Crowdsale = artifacts.require("BCSCrowdsale");
var sale;

var Pool = artifacts.require("TokenPool");
var pool;

var Restrictions = artifacts.require("ParticipantInvestRestrictions");
var restrictions;

var OneEther = web3.toWei(1, "ether");
var DurationHours = 1;
var TokenCap = 1000;
var TokensForOneEther = 100;

var owner;
var beneficiary;
var investor1;
var investor2;
var investor3;

//returns real tokens amount considering token decimals
async function _RT(_tokens) {
    return new Promise(async (resolve, reject) =>{
        return resolve((await token.getRealTokenAmount.call(_tokens)).toNumber());
    })
}

//returns given address specifeid token's real balance
async function _TB(_holder) {
    return new Promise(async (resolve, reject) =>{
        return resolve((await token.balanceOf.call(_holder)).toNumber());
    })
}

function Prepare(accounts, _beneficiary) {
    return new Promise(async (resolve, reject) => {
        
        owner = accounts[0];
        beneficiary = _beneficiary;
        investor1 = accounts[2];
        investor2 = accounts[3];
        investor3 = accounts[4];

        token = await Token.new(TokenCap, 18);        
        restrictions = await Restrictions.new(OneEther, 3);        
        pool = await Pool.new(token.address);                
        
        return resolve(true);
    })
}

contract("BCSCrowdsale. Lock token transfer for everybody", function(accounts) {
    it("create and lock transfer", async function() {
        await Prepare(accounts, accounts[1]);

        await token.setLockedState(true);
        sale = await Crowdsale.new(pool.address, 0, beneficiary, 0, DurationHours, 0, TokensForOneEther, 0);
        
        totalTokens = (await token.totalSupply.call()).toNumber();        
        await restrictions.setManager(sale.address, true);
        await restrictions.setFormula(sale.address);
        
        assert.isTrue(await token.transferLocked.call(), "Locked state should be locked");
        assert.isFalse(await token.canTransfer.call(owner), "Owner shouldn't be able to transfer tokens");
    })

    it("try to transfer tokens to pool, should fail", async function() {
        try {
            await token.transfer(pool.address, totalTokens);
        } catch (e) {
            return true;
        }
        assert.isTrue(false, "Transfer should fail");
    })

    it("allow transfer for owner and transfer to pool", async function() {
        await token.allowTransferFor(owner, true);
        assert.isTrue(await token.transferLocked.call(), "Locked state should be locked");
        assert.isTrue(await token.canTransfer.call(owner), "Owner should be able to transfer tokens");                

        await token.transfer(pool.address, totalTokens);
        await pool.setTrustee(sale.address, true);
        assert.equal(await _TB(pool.address), await totalTokens, "Token pool should have all tokens");
    })

    it("try to invest, should fail", async function() {
        try {
            await sale.invest({from: investor1, value: OneEther});
        } catch (e) {
            return true;
        }
        assert.isTrue(false, "Investment should fail");
    })

    it("unlock transfer for pool and invest again", async function() {
        await token.allowTransferFor(pool.address, true);
        assert.isTrue(await token.canTransfer.call(pool.address), "Pool should be able to transfer tokens");

        await sale.invest({from: investor1, value: OneEther});
        assert.equal(await _TB(investor1), await _RT(100), "Investor1 should get 100 tokens");

        await sale.invest({from: investor2, value: OneEther*2});
        assert.equal(await _TB(investor2), await _RT(200), "Investor2 should get 200 tokens");
    })
})
