import { ethers } from "hardhat";
import { Signer } from "ethers";
import { AgentPassport, AiFinPayCore, MockPyth, MSECCOToken, B2BSplitter } from "../typechain-types";

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

export interface ProtocolWithSplitter extends ProtocolContracts {
  splitter: B2BSplitter;
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

async function deployProtocolWithSplitter(): Promise<ProtocolWithSplitter> {
  const base = await deployProtocol();

  const B2BSplitterFactory = await ethers.getContractFactory("B2BSplitter");
  const splitter = (await B2BSplitterFactory.deploy(
    await base.treasury.getAddress(),
    await base.treasury.getAddress()
  )) as unknown as B2BSplitter;

  return { ...base, splitter };
}

export const fixture = deployProtocol;
export const fixtureWithSplitter = deployProtocolWithSplitter;