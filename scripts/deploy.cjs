const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "MATIC");

  const treasury = deployer.address; // update to multisig after deploy

  // 1. Deploy mSECCO token
  console.log("\n1. Deploying MSECCOToken...");
  const MSECCOToken = await ethers.getContractFactory("MSECCOToken");
  const msecco = await MSECCOToken.deploy(deployer.address);
  await msecco.waitForDeployment();
  console.log("   MSECCOToken:", await msecco.getAddress());

  // 2. Deploy AgentPassport
  console.log("2. Deploying AgentPassport...");
  const AgentPassport = await ethers.getContractFactory("AgentPassport");
  const passport = await AgentPassport.deploy(deployer.address);
  await passport.waitForDeployment();
  console.log("   AgentPassport:", await passport.getAddress());

  // 3. Deploy AiFinPayCore
  console.log("3. Deploying AiFinPayCore...");
  const AiFinPayCore = await ethers.getContractFactory("AiFinPayCore");
  const core = await AiFinPayCore.deploy(
    deployer.address,
    await msecco.getAddress(),
    await passport.getAddress(),
    treasury
  );
  await core.waitForDeployment();
  console.log("   AiFinPayCore:", await core.getAddress());

  // 4. Wire up permissions
  console.log("4. Wiring permissions...");
  await msecco.setCore(await core.getAddress());
  await passport.setCore(await core.getAddress());
  console.log("   Done.");

  console.log("\n=== DEPLOYMENT COMPLETE ===");
  console.log("MSECCOToken: ", await msecco.getAddress());
  console.log("AgentPassport:", await passport.getAddress());
  console.log("AiFinPayCore: ", await core.getAddress());
  console.log("Treasury:     ", treasury);
  console.log("\nVerify on Polygonscan:");
  console.log(`npx hardhat verify --network polygon ${await core.getAddress()} ${deployer.address} ${await msecco.getAddress()} ${await passport.getAddress()} ${treasury}`);
}

main().catch((e) => { console.error(e); process.exit(1); });
