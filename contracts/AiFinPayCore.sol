// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./MSECCOToken.sol";
import "./AgentPassport.sol";

// ── Pyth Interface (Pull Oracle) ───────────────────────────────────────────────
interface IPyth {
    struct Price {
        int64  price;
        uint64 conf;
        int32  expo;
        uint   publishTime;
    }
    function getUpdateFee(bytes[] calldata updateData) external view returns (uint feeAmount);
    function updatePriceFeeds(bytes[] calldata updateData) external payable;
    function getPriceNoOlderThan(bytes32 id, uint age) external view returns (Price memory price);
}

/// @title AiFinPayCore v1.1 — Polygon mainnet (Pyth Pull Oracle + security hardening)
/// @notice Handles seat reservation, mSECCO minting, B2B payments, partner registry
contract AiFinPayCore is Ownable, ReentrancyGuard {

    // ── Pyth Oracle ────────────────────────────────────────────────────────────
    IPyth   public constant PYTH          = IPyth(0xff1a0f4744e8582DF1aE09D5611b887B6a12925C);
    bytes32 public constant MATIC_USD_ID  = 0x5de33a9112c2b700b8d30b8a3402c103578ccfa2856a12a2b20d7b0c67b6d82d;
    uint    public constant PYTH_MAX_AGE  = 60; // max 60 seconds old

    // ── Constants ──────────────────────────────────────────────────────────────
    uint256 public constant USD_CENTS_PER_MSECCO = 1;
    uint256 public constant MIN_USD_CENTS        = 1;   // ~$0.001 minimum
    uint256 public constant BPS_DENOMINATOR      = 10_000;

    bytes32 public constant MANIFESTO_HASH =
        0xd4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5;

    // ── Stablecoins (Polygon mainnet — native only, no bridged USDC.e) ────────
    address public constant USDC = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359; // Native Circle USDC
    address public constant USDT = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F; // Tether USDT

    // ── Configurable Fees ──────────────────────────────────────────────────────
    uint256 public treasuryBps  = 100; // 1.00% → treasury
    uint256 public ipCreatorBps = 1;   // 0.01% → IP creator

    // ── State ──────────────────────────────────────────────────────────────────
    MSECCOToken   public msecco;
    AgentPassport public passport;
    address       public treasury;
    bool          public isPaused;

    struct Seat {
        uint256 usdCentsPaid;
        uint256 mseccoBalance;
        uint8   assetType;   // 0=MATIC, 1=USDC, 2=USDT
        uint256 createdAt;
    }

    struct Partner {
        bool    active;
        string  name;
        uint256 registeredAt;
    }

    mapping(address => Seat)    public seats;
    mapping(address => Partner) public partners;
    uint256 public totalSeats;
    uint256 public totalUsdCents;

    // ── Events ─────────────────────────────────────────────────────────────────
    event SeatReserved(address indexed agent, uint256 usdCents, uint256 mseccoMinted, uint8 assetType);
    event TopUp(address indexed agent, uint256 usdCents, uint256 mseccoMinted);
    event PassportMinted(address indexed agent, address ipCreator);
    event B2BPayment(address indexed agent, address indexed merchant, uint256 amount, string orderId);
    event PartnerRegistered(address indexed partner, string name);
    event FeesUpdated(uint256 treasuryBps, uint256 ipCreatorBps);
    event Paused(bool status);

    // ── Modifiers ──────────────────────────────────────────────────────────────
    modifier notPaused() {
        require(!isPaused, "Protocol is paused");
        _;
    }

    modifier hasSeat() {
        require(seats[msg.sender].createdAt != 0, "No seat found");
        _;
    }

    constructor(
        address initialOwner,
        address _msecco,
        address _passport,
        address _treasury
    ) {
        _transferOwnership(initialOwner);
        msecco   = MSECCOToken(_msecco);
        passport = AgentPassport(_passport);
        treasury = _treasury;
    }

    // ── Reserve Seat (MATIC + Pyth Pull Oracle) ────────────────────────────────
    /// @notice Reserve a seat by paying in MATIC.
    /// @dev Caller must fetch fresh priceUpdateData from Pyth Hermes API and include
    ///      the Pyth update fee in msg.value on top of the payment amount.
    ///      msg.value = maticPayment + pythUpdateFee
    /// @param agreementHash  Must equal MANIFESTO_HASH
    /// @param priceUpdateData  Fresh price update bytes from Pyth Hermes API
    function reserveSeatMatic(
        bytes32 agreementHash,
        bytes[] calldata priceUpdateData
    ) external payable notPaused nonReentrant {
        require(agreementHash == MANIFESTO_HASH, "Invalid agreement hash");
        require(msg.value > 0, "Must send MATIC");

        // 1. Calculate and deduct Pyth update fee
        uint pythFee = PYTH.getUpdateFee(priceUpdateData);
        require(msg.value > pythFee, "Insufficient MATIC for fee");
        uint256 maticPayment = msg.value - pythFee;

        // 2. Push price update on-chain
        PYTH.updatePriceFeeds{value: pythFee}(priceUpdateData);

        // 3. Get trusted MATIC/USD price (max 60s old)
        IPyth.Price memory p = PYTH.getPriceNoOlderThan(MATIC_USD_ID, PYTH_MAX_AGE);
        require(p.price > 0, "Invalid Pyth price");
        require(p.expo == -8, "Unexpected price exponent");

        // 4. Calculate USD cents from payment
        // price.price has 8 decimals (expo = -8), maticPayment is in wei (18 decimals)
        // usdCents = maticPayment * price / 10^(18 + 8 - 2)
        //          = maticPayment * price / 10^24
        uint256 usdCents = (maticPayment * uint256(uint64(p.price))) / 1e24;
        require(usdCents >= MIN_USD_CENTS, "Below minimum");

        // 5. Create/update seat and mint mSECCO
        _createOrUpdateSeat(msg.sender, usdCents, 0);

        // 6. Forward payment (not the pyth fee) to treasury
        (bool sent,) = treasury.call{value: maticPayment}("");
        require(sent, "MATIC transfer failed");

        emit SeatReserved(msg.sender, usdCents, usdCents, 0);
    }

    // ── Reserve Seat (USDC/USDT — stablecoin, no oracle needed) ──────────────
    /// @notice Reserve a seat by paying in USDC or USDT.
    function reserveSeatStable(
        bytes32 agreementHash,
        address token,
        uint256 amount
    ) external notPaused nonReentrant {
        require(agreementHash == MANIFESTO_HASH, "Invalid agreement hash");
        require(token == USDC || token == USDT, "Unsupported token");

        uint256 usdCents = amount / 100; // 6 decimals → cents
        require(usdCents >= MIN_USD_CENTS, "Below minimum");

        IERC20(token).transferFrom(msg.sender, treasury, amount);
        _createOrUpdateSeat(msg.sender, usdCents, token == USDC ? 1 : 2);

        emit SeatReserved(msg.sender, usdCents, usdCents, token == USDC ? 1 : 2);
    }

    // ── Top Up (MATIC + Pyth Pull Oracle) ─────────────────────────────────────
    /// @param priceUpdateData  Fresh price update bytes from Pyth Hermes API
    function topUpMatic(
        bytes[] calldata priceUpdateData
    ) external payable notPaused nonReentrant hasSeat {
        uint pythFee = PYTH.getUpdateFee(priceUpdateData);
        require(msg.value > pythFee, "Insufficient MATIC for fee");
        uint256 maticPayment = msg.value - pythFee;

        PYTH.updatePriceFeeds{value: pythFee}(priceUpdateData);

        IPyth.Price memory p = PYTH.getPriceNoOlderThan(MATIC_USD_ID, PYTH_MAX_AGE);
        require(p.price > 0, "Invalid Pyth price");
        require(p.expo == -8, "Unexpected price exponent");

        uint256 usdCents = (maticPayment * uint256(uint64(p.price))) / 1e24;
        require(usdCents >= MIN_USD_CENTS, "Below minimum");

        seats[msg.sender].usdCentsPaid  += usdCents;
        seats[msg.sender].mseccoBalance += usdCents;
        totalUsdCents += usdCents;
        msecco.mint(msg.sender, usdCents);

        (bool sent,) = treasury.call{value: maticPayment}("");
        require(sent, "MATIC transfer failed");

        emit TopUp(msg.sender, usdCents, usdCents);
    }

    // ── Top Up (Stablecoin) ────────────────────────────────────────────────────
    function topUpStable(address token, uint256 amount) external notPaused nonReentrant hasSeat {
        require(token == USDC || token == USDT, "Unsupported token");
        uint256 usdCents = amount / 100;
        require(usdCents >= MIN_USD_CENTS, "Below minimum");

        IERC20(token).transferFrom(msg.sender, treasury, amount);
        seats[msg.sender].usdCentsPaid  += usdCents;
        seats[msg.sender].mseccoBalance += usdCents;
        totalUsdCents += usdCents;
        msecco.mint(msg.sender, usdCents);

        emit TopUp(msg.sender, usdCents, usdCents);
    }

    // ── Mint Passport ──────────────────────────────────────────────────────────
    function mintPassport(
        address ipCreator,
        bytes32 ipMetadata,
        uint64  dailyLimit
    ) external notPaused {
        passport.mintPassport(msg.sender, ipCreator, ipMetadata, dailyLimit);
        emit PassportMinted(msg.sender, ipCreator);
    }

    // ── Partner Registry ───────────────────────────────────────────────────────
    function registerPartner(address partner, string calldata name) external onlyOwner {
        partners[partner] = Partner({ active: true, name: name, registeredAt: block.timestamp });
        emit PartnerRegistered(partner, name);
    }

    function deactivatePartner(address partner) external onlyOwner {
        partners[partner].active = false;
    }

    // ── B2B Pay ────────────────────────────────────────────────────────────────
    /// @notice Atomic split: 98.99% merchant / 1% treasury / 0.01% IP creator
    function b2bPay(
        address payable merchant,
        string calldata orderId
    ) external payable notPaused nonReentrant {
        require(msg.value > 0, "Must send MATIC");
        require(partners[merchant].active, "Partner not active");
        require(passport.isVerifiedB2B(msg.sender), "Agent not Verified_B2B");

        uint256 treasuryAmount  = (msg.value * treasuryBps) / BPS_DENOMINATOR;
        uint256 ipCreatorAmount = (msg.value * ipCreatorBps) / BPS_DENOMINATOR;
        uint256 merchantAmount  = msg.value - treasuryAmount - ipCreatorAmount;

        require(treasuryAmount > 0, "Protocol fee failed");

        address ipCreator = passport.getPassport(msg.sender).ipCreator;

        (bool s1,) = merchant.call{value: merchantAmount}("");
        require(s1, "Merchant transfer failed");

        (bool s2,) = treasury.call{value: treasuryAmount}("");
        require(s2, "Treasury transfer failed");

        if (ipCreatorAmount > 0 && ipCreator != address(0)) {
            (bool s3,) = payable(ipCreator).call{value: ipCreatorAmount}("");
            require(s3, "IP creator transfer failed");
        }

        emit B2BPayment(msg.sender, merchant, msg.value, orderId);
    }

    // ── Admin ──────────────────────────────────────────────────────────────────
    function pause() external onlyOwner {
        isPaused = true;
        emit Paused(true);
    }

    function unpause() external onlyOwner {
        isPaused = false;
        emit Paused(false);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Zero address");
        treasury = _treasury;
    }

    function setFees(uint256 _treasuryBps, uint256 _ipCreatorBps) external onlyOwner {
        require(_treasuryBps + _ipCreatorBps < BPS_DENOMINATOR, "Fees exceed 100%");
        treasuryBps  = _treasuryBps;
        ipCreatorBps = _ipCreatorBps;
        emit FeesUpdated(_treasuryBps, _ipCreatorBps);
    }

    function verifyAgentB2B(address agent) external onlyOwner {
        passport.setStatus(agent, 2); // STATUS_VERIFIED_B2B = 2
    }

    // ── Internal ───────────────────────────────────────────────────────────────
    function _createOrUpdateSeat(address agent, uint256 usdCents, uint8 assetType) internal {
        if (seats[agent].createdAt == 0) {
            seats[agent] = Seat({
                usdCentsPaid:  usdCents,
                mseccoBalance: usdCents,
                assetType:     assetType,
                createdAt:     block.timestamp
            });
            totalSeats++;
        } else {
            seats[agent].usdCentsPaid  += usdCents;
            seats[agent].mseccoBalance += usdCents;
        }
        totalUsdCents += usdCents;
        msecco.mint(agent, usdCents);
    }
}
