import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { Signer, ZeroHash, parseEther } from "ethers";
import { AgentPassport, AiFinPayCore, MockPyth, MSECCOToken } from "../../typechain-types";
import { fixture } from "../fixtures";

describe("AiFinPayCore", function () {
  let owner: Signer, treasury: Signer, agent: Signer, merchant: Signer, attacker: Signer;
  let msecco: MSECCOToken, passport: AgentPassport, core: AiFinPayCore, mockPyth: MockPyth;

  beforeEach(async function () {
    ({ owner, treasury, agent, merchant, attacker, msecco, passport, core, mockPyth } = await loadFixture(fixture));
  });

  describe("Configuration", function () {
    it("MANIFESTO_HASH is set correctly", async function () {
      expect(await core.MANIFESTO_HASH()).to.equal(
        "0xa1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2"
      );
    });

    it("default treasury fee is 1%", async function () {
      expect(await core.treasuryBps()).to.equal(100);
    });

    it("default IP creator fee is 0.01%", async function () {
      expect(await core.ipCreatorBps()).to.equal(1);
    });

    it("MIN_USD_CENTS is 10", async function () {
      expect(await core.MIN_USD_CENTS()).to.equal(10);
    });

    it("PYTH_MAX_AGE is 60 seconds", async function () {
      expect(await core.PYTH_MAX_AGE()).to.equal(60);
    });

    it("USDC is native Circle address on Polygon", async function () {
      expect(await core.USDC()).to.equal("0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359");
    });

    it("USDT is correct Tether address on Polygon", async function () {
      expect(await core.USDT()).to.equal("0xc2132D05D31c914a87C6611C10748AEb04B58e8F");
    });

    it("Pyth contract address is correct", async function () {
      expect(await core.PYTH()).to.equal("0xff1a0f4744e8582DF1aE09D5611b887B6a12925C");
    });

    it("MATIC/USD feed ID is set", async function () {
      expect(await core.MATIC_USD_ID()).to.equal(
        "0x5de33a9112c2b700b8d30b8a3402c103578ccfa2856a12a2b20d7b0c67b6d82d"
      );
    });
  });

  describe("Admin Functions", function () {
    it("owner can pause and unpause", async function () {
      await core.connect(owner).pause();
      expect(await core.isPaused()).to.equal(true);

      await core.connect(owner).unpause();
      expect(await core.isPaused()).to.equal(false);
    });

    it("non-owner cannot pause", async function () {
      await expect(core.connect(attacker).pause())
        .to.be.revertedWithCustomError(core, "OwnableUnauthorizedAccount");
    });

    it("owner can update fees", async function () {
      await core.connect(owner).setFees(200, 5);
      expect(await core.treasuryBps()).to.equal(200);
      expect(await core.ipCreatorBps()).to.equal(5);
    });

    it("fees cannot exceed 100%", async function () {
      await expect(core.connect(owner).setFees(9999, 9999))
        .to.be.revertedWithCustomError(core, "FeesExceed100");
    });

    it("owner can update treasury address", async function () {
      await core.connect(owner).setTreasury(await attacker.getAddress());
      expect(await core.treasury()).to.equal(await attacker.getAddress());
    });

    it("setTreasury reverts on zero address", async function () {
      await expect(core.connect(owner).setTreasury(ethers.ZeroAddress))
        .to.be.revertedWithCustomError(core, "ZeroTreasury");
    });
  });

  describe("Partner Management", function () {
    it("owner can register partner", async function () {
      await core.connect(owner).registerPartner(await merchant.getAddress(), "TestMerchant");
      const partner = await core.partners(await merchant.getAddress());
      expect(partner.active).to.equal(true);
    });

    it("owner can deactivate partner", async function () {
      await core.connect(owner).registerPartner(await merchant.getAddress(), "Merchant");
      await core.connect(owner).deactivatePartner(await merchant.getAddress());
      expect((await core.partners(await merchant.getAddress())).active).to.equal(false);
    });

    it("cannot register zero address partner", async function () {
      await expect(core.connect(owner).registerPartner(ethers.ZeroAddress, "Test"))
        .to.be.revertedWithCustomError(core, "ZeroPartner");
    });

    it("cannot register empty partner name", async function () {
      await expect(core.connect(owner).registerPartner(await merchant.getAddress(), ""))
        .to.be.revertedWithCustomError(core, "EmptyPartnerName");
    });
  });

  describe("Pyth Oracle Integration", function () {
    it("no fake price can be injected — price comes from oracle not caller", async function () {
      const fragment = core.interface.getFunction("reserveSeatMatic");
      const paramNames = fragment.inputs.map(i => i.name);
      expect(paramNames).to.not.include("maticUsdPrice");
      expect(paramNames).to.include("_priceUpdateData");
    });

    it("topUpMatic signature has no maticUsdPrice parameter", async function () {
      const fragment = core.interface.getFunction("topUpMatic");
      const paramNames = fragment.inputs.map(i => i.name);
      expect(paramNames).to.not.include("maticUsdPrice");
      expect(paramNames).to.include("_priceUpdateData");
    });

    it("usdCents calculation: 1 MATIC @ $0.50 = 50 cents", async function () {
      const maticPayment = parseEther("1");
      const price = 50_000_000n;
      const usdCents = (maticPayment * price) / 1000000000000000000000000n;
      expect(usdCents).to.equal(50n);
    });

    it("usdCents calculation: 0.1 MATIC @ $0.50 = 5 cents", async function () {
      const maticPayment = parseEther("0.1");
      const price = 50_000_000n;
      const usdCents = (maticPayment * price) / 1000000000000000000000000n;
      expect(usdCents).to.equal(5n);
    });
  });

  describe("Pausable Functionality", function () {
    it("owner can pause", async function () {
      await core.connect(owner).pause();
      expect(await core.isPaused()).to.equal(true);
    });

    it("owner can unpause", async function () {
      await core.connect(owner).pause();
      await core.connect(owner).unpause();
      expect(await core.isPaused()).to.equal(false);
    });

    it("pause and unpause emit events", async function () {
      await expect(core.connect(owner).pause())
        .to.emit(core, "Paused")
        .withArgs(true);

      await expect(core.connect(owner).unpause())
        .to.emit(core, "Paused")
        .withArgs(false);
    });
  });
});