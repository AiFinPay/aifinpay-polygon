// @ts-ignore
import { ethers } from "hardhat";
import { Signer } from "ethers";
import { AgentPassport, AiFinPayCore, MockPyth, MSECCOToken } from "../typechain-types";

export interface ProtocolContracts {
  owner: Signer;
  treasury: Signer;
  agent: Signer;
  merchant: Signer;
  ipCreator: Signer;
  attacker: Signer;
  msecco: MSECCOToken;
  passport: AgentPassport;
  core: AiFinPayCore;
  mockPyth: MockPyth;
}

async function deployProtocol(): Promise<ProtocolContracts> {
  const [owner, treasury, agent, merchant, ipCreator, attacker] = await ethers.getSigners();

  const MockPythFactory = await ethers.getContractFactory("MockPyth");
  const mockPyth = (await MockPythFactory.deploy()) as unknown as MockPyth;

  const MSECCOTokenFactory = await ethers.getContractFactory("MSECCOToken");
  const AgentPassportFactory = await ethers.getContractFactory("AgentPassport");
  const AiFinPayCoreFactory = await ethers.getContractFactory("AiFinPayCore");

  const msecco = (await MSECCOTokenFactory.deploy(await owner.getAddress())) as unknown as MSECCOToken;
  const passport = (await AgentPassportFactory.deploy(await owner.getAddress())) as unknown as AgentPassport;
  const core = (await AiFinPayCoreFactory.deploy(
    await owner.getAddress(),
    await msecco.getAddress(),
    await passport.getAddress(),
    await treasury.getAddress()
  )) as unknown as AiFinPayCore;

  await msecco.setCore(await core.getAddress());
  await passport.setCore(await core.getAddress());

  return { owner, treasury, agent, merchant, ipCreator, attacker, msecco, passport, core, mockPyth };
}

export const fixture = deployProtocol;