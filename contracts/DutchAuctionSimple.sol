// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
// OZ 5.5+ ships ReentrancyGuard with namespaced storage — proxy-safe without an initializer.
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";

/// @title DutchAuction (upgradeable, multi-ERC20 payments)
/// @notice Dutch auction where bids are accounted in `paymentToken` (e.g. USDT),
///         but bidders may pay in *any* ERC20 token routed through a Uniswap V2
///         compatible router. The contract swaps the bidder's input token into
///         `paymentToken` so the escrowed bid always equals the required
///         USDT amount.
///
/// @dev Upgradeable via the UUPS pattern. Deploy through `DutchAuctionProxy`
///      (ERC1967Proxy). The implementation is owned by the deployer; only the
///      owner can authorize upgrades or change the router / payment token.
contract DutchAuction is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuard,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    /// @notice Settlement token. All bids are denominated and escrowed in this token (e.g. USDT).
    IERC20 public paymentToken;

    /// @notice Uniswap V2 compatible router used to convert arbitrary ERC20s -> paymentToken.
    IUniswapV2Router02 public swapRouter;

    struct Bid {
        address bidder;
        uint256 amount; // amount of auctioned tokens the bidder wants
        uint256 price; // price-per-token, denominated in `paymentToken`
    }

    struct Auction {
        address auctionOwner;
        uint256 initialPrice;
        uint16 tokenAmount;
        address tokenAddress;
        uint256 duration; // absolute deadline timestamp (kept name for compatibility)
        bool sold;
    }

    mapping(uint16 => Auction) public auctions;
    mapping(uint16 => Bid[]) public bids;
    uint16 public auctionCounter;

    uint8 public constant FEE_PERCENTAGE = 10;
    /// @notice Multiplier on bid value to over-collateralize (110 == 110%).
    uint16 public constant BID_OVERCOLLATERAL_BPS = 110;
    /// @notice Default swap deadline relative to block.timestamp.
    uint256 public constant SWAP_DEADLINE = 30 minutes;

    /// @dev Storage gap for future variables without breaking the layout.
    uint256[44] private __gap;

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event AuctionCreated(uint16 indexed auctionId, uint256 initialPrice, uint16 tokenAmount, uint256 duration);
    event BidPlaced(uint16 indexed auctionId, address indexed bidder, uint256 amount, uint256 price);
    event BidPaidWithSwap(
        uint16 indexed auctionId,
        address indexed bidder,
        address indexed inputToken,
        uint256 inputAmountSpent,
        uint256 paymentAmountOut
    );
    event AuctionFinalized(uint16 indexed auctionId, address indexed winner, uint256 amount, uint256 price);
    event PaymentTokenUpdated(address indexed token);
    event SwapRouterUpdated(address indexed router);

    // ---------------------------------------------------------------------
    // Initializer
    // ---------------------------------------------------------------------

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the proxy. Call exactly once via the proxy.
    /// @param paymentTokenAddress USDT (or any ERC20 chosen as settlement token).
    /// @param swapRouterAddress Uniswap V2 compatible router (QuickSwap / SushiSwap / UniV2).
    function initialize(address paymentTokenAddress, address swapRouterAddress) external initializer {
        require(paymentTokenAddress != address(0), "Invalid payment token");
        __Ownable_init(msg.sender);
        // UUPSUpgradeable in OZ 5.x is stateless — no initializer needed.

        paymentToken = IERC20(paymentTokenAddress);
        swapRouter = IUniswapV2Router02(swapRouterAddress);
    }

    /// @dev Only owner may upgrade.
    function _authorizeUpgrade(address) internal override onlyOwner {}

    // ---------------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------------

    function setPaymentToken(address token) external onlyOwner {
        require(token != address(0), "Invalid token");
        paymentToken = IERC20(token);
        emit PaymentTokenUpdated(token);
    }

    function setSwapRouter(address router) external onlyOwner {
        swapRouter = IUniswapV2Router02(router);
        emit SwapRouterUpdated(router);
    }

    // ---------------------------------------------------------------------
    // Auction lifecycle
    // ---------------------------------------------------------------------

    function createAuction(
        uint256 initialPrice,
        uint16 tokenAmount,
        uint256 duration,
        address tokenAddress
    ) external nonReentrant {
        require(initialPrice > 0, "Initial price must be greater than zero");
        require(tokenAmount > 0, "Token amount must be greater than zero");
        require(duration > 0, "Duration must be greater than zero");
        require(tokenAddress != address(0), "Invalid token address");

        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), tokenAmount);

        auctionCounter++;
        auctions[auctionCounter] = Auction({
            auctionOwner: msg.sender,
            initialPrice: initialPrice,
            tokenAmount: tokenAmount,
            tokenAddress: tokenAddress,
            duration: block.timestamp + duration,
            sold: false
        });

        emit AuctionCreated(auctionCounter, initialPrice, tokenAmount, duration);
    }

    /// @notice Place a bid paying directly in `paymentToken` (e.g. USDT). Same
    ///         calling convention as the original contract.
    function bid(uint16 auctionId, uint256 amount, uint256 price) external nonReentrant {
        uint256 totalPayment = _validateAndCalcPayment(auctionId, amount, price);

        paymentToken.safeTransferFrom(msg.sender, address(this), totalPayment);

        _recordBid(auctionId, amount, price);
    }

    /// @notice Place a bid paying in *any* ERC20. The contract swaps the
    ///         bidder's input token into `paymentToken` via Uniswap V2 so the
    ///         escrowed bid equals the required USDT amount exactly.
    ///
    /// @dev    The caller must approve `maxInputAmount` of `inputToken` to
    ///         this contract beforehand. Any input tokens the swap does not
    ///         consume are refunded in the same transaction.
    ///
    /// @param auctionId      Target auction.
    /// @param amount         Number of auctioned tokens to bid for.
    /// @param price          Per-token bid price (in paymentToken units).
    /// @param inputToken     Token the bidder wants to pay with (e.g. DOGE).
    /// @param maxInputAmount Maximum input the bidder is willing to spend (slippage cap).
    /// @param path           Uniswap V2 swap path: [inputToken, ..., paymentToken].
    function bidWithToken(
        uint16 auctionId,
        uint256 amount,
        uint256 price,
        address inputToken,
        uint256 maxInputAmount,
        address[] calldata path
    ) external nonReentrant {
        require(address(swapRouter) != address(0), "Swap router not set");
        require(inputToken != address(0), "Invalid input token");
        require(maxInputAmount > 0, "maxInputAmount must be > 0");
        require(path.length >= 2, "Path too short");
        require(path[0] == inputToken, "Path must start with inputToken");
        require(path[path.length - 1] == address(paymentToken), "Path must end with paymentToken");

        uint256 totalPayment = _validateAndCalcPayment(auctionId, amount, price);

        IERC20 input = IERC20(inputToken);

        // Pull the slippage-capped max from the user.
        input.safeTransferFrom(msg.sender, address(this), maxInputAmount);

        // Approve the router for this swap only. forceApprove handles USDT-style
        // non-zero-allowance tokens correctly.
        input.forceApprove(address(swapRouter), maxInputAmount);

        // Exact-out swap: we want exactly `totalPayment` of paymentToken.
        uint256[] memory amounts = swapRouter.swapTokensForExactTokens(
            totalPayment,
            maxInputAmount,
            path,
            address(this),
            block.timestamp + SWAP_DEADLINE
        );

        uint256 inputSpent = amounts[0];

        // Reset router allowance to 0 (defense in depth).
        input.forceApprove(address(swapRouter), 0);

        // Refund any unspent input back to the bidder.
        if (inputSpent < maxInputAmount) {
            input.safeTransfer(msg.sender, maxInputAmount - inputSpent);
        }

        _recordBid(auctionId, amount, price);
        emit BidPaidWithSwap(auctionId, msg.sender, inputToken, inputSpent, totalPayment);
    }

    /// @notice Off-chain helper: how much `inputToken` does the bidder need to
    ///         fund a given bid (after the 110% over-collateralization)?
    function quoteBidInputAmount(
        uint256 amount,
        uint256 price,
        address[] calldata path
    ) external view returns (uint256 inputAmount, uint256 totalPayment) {
        require(address(swapRouter) != address(0), "Swap router not set");
        require(path.length >= 2, "Path too short");
        require(path[path.length - 1] == address(paymentToken), "Path must end with paymentToken");

        totalPayment = (price * amount * BID_OVERCOLLATERAL_BPS) / 100;
        uint256[] memory amounts = swapRouter.getAmountsIn(totalPayment, path);
        inputAmount = amounts[0];
    }

    function finalizeAuction(
        uint16 auctionId,
        Bid[] calldata winners,
        Bid[] calldata refunders
    ) external onlyOwner nonReentrant {
        Auction storage auction = auctions[auctionId];
        require(block.timestamp > auction.duration, "Auction not ended");
        require(!auction.sold, "Auction not sold");

        auction.sold = true;

        // Transfer auctioned tokens to winners.
        IERC20 token = IERC20(auction.tokenAddress);
        for (uint256 i = 0; i < winners.length; i++) {
            token.safeTransfer(winners[i].bidder, winners[i].amount);
        }

        // Split payment + fees.
        uint256 totalPayment;
        for (uint256 i = 0; i < winners.length; i++) {
            totalPayment += winners[i].price;
        }
        uint256 fee = (totalPayment * FEE_PERCENTAGE) / 100;
        uint256 ownerAmount = totalPayment - fee;

        paymentToken.safeTransfer(auction.auctionOwner, ownerAmount);
        paymentToken.safeTransfer(owner(), fee);

        // Refund losing bidders.
        for (uint256 i = 0; i < refunders.length; i++) {
            paymentToken.safeTransfer(refunders[i].bidder, refunders[i].price);
        }
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function getAuction(uint16 auctionId) external view returns (Auction memory) {
        return auctions[auctionId];
    }

    function getBid(uint16 auctionId, uint256 index) external view returns (Bid memory) {
        require(index < bids[auctionId].length, "Index out of bounds");
        return bids[auctionId][index];
    }

    function getBidCount(uint16 auctionId) external view returns (uint256) {
        return bids[auctionId].length;
    }

    // ---------------------------------------------------------------------
    // Internal
    // ---------------------------------------------------------------------

    function _validateAndCalcPayment(uint16 auctionId, uint256 amount, uint256 price)
        internal
        view
        returns (uint256 totalPayment)
    {
        Auction storage auction = auctions[auctionId];
        require(block.timestamp <= auction.duration, "Auction ended");
        require(!auction.sold, "Already sold");
        require(price >= auction.initialPrice, "Bid price too low");
        require(amount > 0, "Bid amount must be greater than zero");
        require(amount <= auction.tokenAmount, "Bid amount exceeds available tokens");

        totalPayment = (price * amount * BID_OVERCOLLATERAL_BPS) / 100;
    }

    function _recordBid(uint16 auctionId, uint256 amount, uint256 price) internal {
        bids[auctionId].push(Bid({bidder: msg.sender, amount: amount, price: price}));
        emit BidPlaced(auctionId, msg.sender, amount, price);
    }
}
