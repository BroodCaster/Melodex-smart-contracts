// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DutchAuction is ReentrancyGuard, Ownable {
    // ERC20 public paymentToken = ERC20(0x5FDAF637Aed59B2e6d384d9e84D8ac5cF03c6697); // Address of the payment token (MELS)
    ERC20 public paymentToken;
    constructor (address paymentTokenAddress) Ownable(msg.sender) { paymentToken = ERC20(paymentTokenAddress); }
    struct Bid {
        address bidder; // Address of the bidder
        uint256 amount; // Amount of the bid
        uint256 price; // Price at which the bid was placed
    }
    struct Auction {
        address auctionOwner; // Address of the auction owner
        uint256 initialPrice;
        uint16 tokenAmount; // Amount of the token to be auctioned
        address tokenAddress; // Address of the token being auctioned
        uint256 duration; // Duration of the auction in seconds
        bool sold; // Indicates if the FT has been sold
    }

    

    mapping(uint16 => Auction) public auctions; // Mapping of auction ID to Auction details
    mapping(uint16 => Bid[]) public bids; // Mapping of auction ID to array of bids
    uint16 public auctionCounter; // Counter for auction IDs
    

    event AuctionCreated(uint16 indexed auctionId, uint256 initialPrice, uint16 tokenAmount, uint256 duration);
    event BidPlaced(uint16 indexed auctionId, address indexed bidder, uint256 amount, uint256 price);
    event AuctionFinalized(uint16 indexed auctionId, address indexed winner, uint256 amount, uint256 price);

    function createAuction(
        uint256 initialPrice,
        uint16 tokenAmount,
        uint256 duration,
        address tokenAddress
    ) external {
        require(initialPrice > 0, "Initial price must be greater than zero");
        require(tokenAmount > 0, "Token amount must be greater than zero");
        require(duration > 0, "Duration must be greater than zero");
        require(tokenAddress != address(0), "Invalid token address");

        ERC20 token = ERC20(tokenAddress);

        require(token.allowance(msg.sender, address(this)) >= tokenAmount, "Token allowance too low");
        require(token.transferFrom(msg.sender, address(this), tokenAmount), "Token transfer failed");

        
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

    function bid(uint16 auctionId, uint256 amount, uint256 price) external {
        Auction storage auction = auctions[auctionId];
        require(auction.auctionOwner != address(0), "Auction does not exist");
        require(block.timestamp <= auction.duration, "Auction ended");
        require(!auction.sold, "Already sold");
        require(price >= auction.initialPrice, "Bid price too low");
        require(amount <= auction.tokenAmount, "Bid amount exceeds available tokens");
        require(amount > 0, "Bid amount must be greater than zero");
        require(paymentToken.allowance(msg.sender, address(this)) >= price * amount, "Insufficient allowance");
        require(paymentToken.transferFrom(msg.sender, address(this), price * amount), "Payment failed");

        bids[auctionId].push(Bid({
            bidder: msg.sender,
            amount: amount,
            price: price
        }));

        emit BidPlaced(auctionId, msg.sender, amount, price);
    }

    function finalizeAuction(
        uint16 auctionId,
        Bid[] calldata winners,
        Bid[] calldata refunders
    ) external onlyOwner {
        Auction storage auction = auctions[auctionId];
        require(block.timestamp > auction.duration, "Auction not ended");
        require(auction.sold, "Auction not sold");

        // Transfer tokens to winners
        ERC20 token = ERC20(auction.tokenAddress);
        for (uint256 i = 0; i < winners.length; i++) {
            require(token.transfer(winners[i].bidder, winners[i].amount), "Token transfer to winner failed");
        }

        // Transfer payment to auction owner
        uint256 totalPayment;
        for (uint256 i = 0; i < winners.length; i++) {
            totalPayment += winners[i].amount * winners[i].price;
        }
        require(paymentToken.transfer(auction.auctionOwner, totalPayment), "Payment to auction owner failed");

        // Refund non-winning bidders
        for (uint256 i = 0; i < refunders.length; i++) {
            require(paymentToken.transfer(refunders[i].bidder, refunders[i].amount * refunders[i].price), "Refund to bidder failed");
        }

        // Clean up the auction
        delete auctions[auctionId];
    }

    function getAuction(uint16 auctionId) external view returns (Auction memory) {
        return auctions[auctionId];
    }


    function getBid(uint16 auctionId, uint256 index) external view returns (Bid memory) {
        require(index < bids[auctionId].length, "Index out of bounds");
        return bids[auctionId][index];
    }
}