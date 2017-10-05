var Web3 = require("web3");
var web3 = new Web3(new Web3.providers.HttpProvider("http://localhost:8545"));

var Controller = artifacts.require("BCSBonusController");
var Token = artifacts.require("BCSPromoToken");
var Product = artifacts.require("TokenProduct");
var Vendor = artifacts.require("TokenVendor");
var Airdrop = artifacts.require("AirdropCampaign");

var token, product, controller, vendor;

contract("Compare gas prices", function(accounts) {

    var owner = accounts[0];

    it("Airdrop", async function () {
              
        vendor = await Vendor.new("BONUS", accounts[1], 1, 10, 100, 10, 100);
        token = await Token.new("BCS BONUS TOKEN", "", 0);
        // await token.setManager(vendor.address, true);
        // await vendor.setToken(token.address);        
        // await vendor.quickCreatePromo("S1", 7);
        // var sale1 = Product.at(await vendor.products.call(0));
        
        // var oldBalance = await web3.eth.getBalance(owner);
        // await sale1.buy("CC", false , 0, {value:0});
        // var newBalance = await web3.eth.getBalance(owner);
        // var cost2 = oldBalance.minus(newBalance).toNumber();
      
        // console.log(cost2 / 1000000000000000000);
        // console.log(sale1.buy.estimateGas);        

        //create airdrop
        var air = await Airdrop.new(token.address, "PROMO", 100, 1, 3, 10, 2, 50, true);
        await token.setMinter(air.address, true);        
        var user1 = accounts[1];
        var user2 = accounts[2];
        var user3 = accounts[3];

        //check gas costs
        var rr = await air.buy.estimateGas({from:owner});
        console.log(rr);      

        //buy then check again
        var oldBalance2 = await web3.eth.getBalance(user1);
        await air.buy({from:user1});
        var newBalance2 = await web3.eth.getBalance(user1);        
        var cost = oldBalance2.minus(newBalance2).toNumber();        
        console.log(cost / 1000000000000000000);

        var rr2 = await air.buy.estimateGas({from:user2});
        console.log(rr2);
        await air.buy({from:user2});

        var rr3 = await air.buy.estimateGas({from:user3});
        console.log(rr3);
        
    })

    // it("Creation of token vendor. Controller and standalone transactions.", async function() {
    //     var b1 = await web3.eth.getBalance(owner);

    //     controller = await Controller.new(accounts[1]);        
    //     await controller.createTokenAndVendor();

    //     var b2 = await web3.eth.getBalance(owner);
    //     var cost1 = b1.minus(b2).toNumber();
    //     console.log(cost1);

    //     var b3 = await web3.eth.getBalance(owner);
        
    //     vendor = await Vendor.new("BONUS", accounts[1], 1, 10, 100, 10, 100);
    //     token = await Token.new("BCS BONUS TOKEN", "", 0);
    //     await token.setManager(vendor.address, true);
    //     await vendor.setToken(token.address);
        
        
    //     var b4 = await web3.eth.getBalance(owner);
    //     var cost2 = b3.minus(b4).toNumber();
    //     console.log(cost2);

    //     assert.equal(cost1, cost2, "!");
    // })

    // it("Creation of token product. TokenVendor method and contract deploy.", async function() {        

    //     var b1 = await web3.eth.getBalance(owner);          
    //     await vendor.createProduct("P1", 10000, true, 2000, false, 0, 0);        
    //     var b2 = await web3.eth.getBalance(owner);
    //     var cost1 = b1.minus(b2).toNumber();
    //     console.log(cost1);
                
    //     var b3 = await web3.eth.getBalance(owner);        
    //     product = await Product.new(token.address, 0, "T1", 2000, 0, 0, 1, 10, 100, 10, 100);                
    //     var b4 = await web3.eth.getBalance(owner);
    //     var cost2 = b3.minus(b4).toNumber();
    //     console.log(cost2);

    //     assert.equal(cost1, cost2, "!");
    // })
})