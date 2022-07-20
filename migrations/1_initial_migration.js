const Migrations = artifacts.require("Migrations");
const SettleTokenSettlement = artifacts.require("SettleTokenSettlement");
const TestEscrowToken = artifacts.require("TestEscrowToken");

module.exports = async function (deployer, network, accounts) {
  
  //console.log("Deploying initial migrations");
  //await deployer.deploy(Migrations);
  //console.log("Migrations Deployed");

  console.log("Deploying Token used to test the settlement system");

  await deployer.deploy(TestEscrowToken);

  let TestTokenInstance = await TestEscrowToken.deployed();

  console.log("Token deployed at " + TestTokenInstance.address + " ✔️");

  const SETTLE_FEE_PERCENTAGE = "1";
  const funder = accounts[0];
  const receiver = accounts[1];
  const releaser = accounts[2];
  const fee_receiver = accounts[3];

  console.log("Deploying Settlement contract:");
  console.log("Fee Receiver: " +  accounts[0]);
  console.log("Fee Percentage: " + SETTLE_FEE_PERCENTAGE);

  await deployer.deploy(SettleTokenSettlement, fee_receiver, SETTLE_FEE_PERCENTAGE);

  console.log("Settlement contract successfully deployed! ✔️");
  console.log("\n");

  let SettlementContractInstance = await SettleTokenSettlement.deployed();

  console.log("Creating a new settlement with no expiry, using the test token");
  console.log("SENDER: " + accounts[0]);
  console.log("RECEIVER: " + accounts[1]);
  console.log("RELEASER: " + accounts[2]);
  console.log("FEE RECEIVER: " + accounts[3]);
  console.log("\n");

  await SettlementContractInstance.create_settlement (receiver, funder, releaser, web3.utils.toWei("100"), TestTokenInstance.address, 0 /*Expires Never*/, 0 /*REFUND*/);
  
  console.log("Settlement successfully setup ✔️ \n");

  let TestTokenBalance = await TestTokenInstance.balanceOf(funder);
  console.log("Token balance of funding account " + funder + " is " + web3.utils.fromWei(TestTokenBalance) + " TEST");
  console.log("Approving settlement contract to access the pertinent amount of funds");

  await TestTokenInstance.approve(SettlementContractInstance.address, web3.utils.toWei("100"));
  console.log("Successfully approved! ✔️ \n");
  
  console.log("Now adding the funds to the settlement");
  await SettlementContractInstance.fund_settlement(0);
  console.log("Funds successsfully added! ✔️");

  TestTokenBalance = await TestTokenInstance.balanceOf(funder);
  console.log("Token balance of funding account " + funder + " after funding is " + web3.utils.fromWei(TestTokenBalance) + " TEST");

  TestTokenReceiverBalance = await TestTokenInstance.balanceOf(receiver);
  console.log("Token balance of receiving account " + receiver + " before releasing is " + web3.utils.fromWei(TestTokenReceiverBalance) + " TEST");

  console.log("Releasing the escrow...");
  await SettlementContractInstance.release_settlement(0, {from: releaser});
  console.log("Released ✔️");
  console.log("\n");

  TestTokenReceiverBalance = await TestTokenInstance.balanceOf(receiver);
  console.log("Balance of the receiver after the release is " + web3.utils.fromWei(TestTokenReceiverBalance) + " TEST");

  let TestTokenFeeReceiverBalance = await TestTokenInstance.balanceOf(fee_receiver);
  console.log("Balance of the fee receiver after the release is " + web3.utils.fromWei(TestTokenFeeReceiverBalance) + " TEST");

  let paused_status = await SettlementContractInstance.emergency_pause.call().then(data => {
    return data;
  });

  console.log("Contract paused: " + paused_status);

  let fee = await SettlementContractInstance.fee.call().then(data => {
   return data;
  });

  console.log("Contract fee: " + fee);

  let settlements = await SettlementContractInstance.get_num_settlements.call().then(data => {
    return data;
  });

  console.log("Number settlements: " + settlements);

  for(let i = 0; i < settlements.length; i++)
  {
    await SettlementContractInstance.get_settlement.call(i).then(data => {
      console.log("Printing raw settlement object data")
      console.log(data);
      console.log("\n");
    });
  }  

  console.log("Trying to Release the escrow for a second time");
  await SettlementContractInstance.release_settlement(0, {from: releaser});
  console.log("Released");

};
