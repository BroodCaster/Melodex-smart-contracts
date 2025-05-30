// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DutchAuction is ReentrancyGuard, Ownable {

    constructor () Ownable(msg.sender) { }
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
        uint256 startTime; // Start time of the auction
        bool sold; // Indicates if the FT has been sold
        Bid[] bids; // Array of bids placed in the auction
    }

    

    mapping(uint16 => Auction) public auctions; // Mapping of auction ID to Auction details
    uint16 public auctionCounter; // Counter for auction IDs
    ERC20 constant public paymentToken = ERC20(0x5FDAF637Aed59B2e6d384d9e84D8ac5cF03c6697); // Address of the payment token (MELS)

    event AuctionCreated(uint16 indexed auctionId, uint256 initialPrice, uint16 tokenAmount, uint256 duration, uint256 startTime);
    event BidPlaced(uint16 indexed auctionId, address indexed bidder, uint256 amount, uint256 price);
    event AuctionFinalized(uint16 indexed auctionId, address indexed winner, uint256 amount, uint256 price);

    function createAuction(
        uint256 initialPrice,
        uint16 tokenAmount,
        uint256 duration,
        uint256 startTime,
        address tokenAddress
    ) external {
        require(initialPrice > 0, "Initial price must be greater than zero");
        require(tokenAmount > 0, "Token amount must be greater than zero");
        require(duration > 0, "Duration must be greater than zero");
        require(startTime >= block.timestamp, "Start time must be in the future");
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
            duration: duration,
            startTime: block.timestamp+startTime,
            sold: false,
            bids: new Bid[](0)
        });

        emit AuctionCreated(auctionCounter, initialPrice, tokenAmount, duration, startTime);
    }

    function bid(uint16 auctionId, uint256 amount, uint256 price) external {
        Auction storage auction = auctions[auctionId];
        require(block.timestamp >= auction.startTime, "Auction not started");
        require(block.timestamp <= auction.startTime + auction.duration, "Auction ended");
        require(!auction.sold, "Already sold");
        require(price >= auction.initialPrice, "Bid price too low");
        require(paymentToken.allowance(msg.sender, address(this)) >= price*amount, "Insufficient allowance");
        require(paymentToken.transferFrom(msg.sender, address(this), price*amount), "Payment failed");
        require(amount <= auction.tokenAmount, "Bid amount exceeds available tokens");
        require(amount > 0, "Bid amount must be greater than zero");

        // Store the bid in the array
        auction.bids.push(Bid({
            bidder: msg.sender,
            amount: amount,
            price: price
        }));
        
        auction.sold = true;

        emit BidPlaced(auctionId, msg.sender, amount, price);
    }

    function finalizeAuction(uint16 auctionId) external onlyOwner {
        Auction storage auction = auctions[auctionId];
        require(block.timestamp > auction.startTime + auction.duration, "Auction not ended");
        require(auction.sold, "Auction not sold");

        Bid[] storage bids = auction.bids;
        uint256 n = bids.length;
        for (uint256 i = 0; i < n; i++) {
            for (uint256 j = 0; j < n - 1 - i; j++) {
                if (bids[j].price < bids[j + 1].price) {
                    Bid memory temp = bids[j];
                    bids[j] = bids[j + 1];
                    bids[j + 1] = temp;
                }
            }
        }

        Bid[] memory winners = new Bid[](auction.bids.length);
        uint256 totalAmount = 0;
        uint256 winnerCount = 0;
        for (uint256 i = 0; i < bids.length; i++) {
            if (totalAmount + bids[i].amount <= auction.tokenAmount) {
            winners[winnerCount] = bids[i];
            totalAmount += bids[i].amount;
            winnerCount++;
            } else {
            break;
            }
        }

        // Refund losing bidders
        for (uint256 i = winnerCount; i < bids.length; i++) {
            uint256 refund = bids[i].price * bids[i].amount;
            require(paymentToken.transfer(bids[i].bidder, refund), "Refund to losing bidder failed");
        }

        uint256 minPrice = type(uint256).max;
        for (uint256 i = 0; i < winnerCount; i++) {
            if (winners[i].price < minPrice) {
                minPrice = winners[i].price;
            }
        }

        // Refund the difference between bid price and minPrice to winners who bid above minPrice
        for (uint256 i = 0; i < winnerCount; i++) {
            if (winners[i].price > minPrice) {
            uint256 refund = (winners[i].price - minPrice) * winners[i].amount;
            require(paymentToken.transfer(winners[i].bidder, refund), "Refund failed");
            }
            winners[i].price = minPrice;
        }

        ERC20 token = ERC20(auction.tokenAddress);

        for (uint256 i = 0; i < winnerCount; i++) {
            require(token.transfer(winners[i].bidder, winners[i].amount), "Token transfer failed");
        }

        for (uint256 i = 0; i < winnerCount; i++) {
            require(paymentToken.transfer(auction.auctionOwner, auction.tokenAmount*minPrice), "Token transfer failed");
        }

        emit AuctionFinalized(auctionId, winners[0].bidder, totalAmount, minPrice);
        // Clean up the auction
        delete auctions[auctionId];
    }

   function getAuction(uint16 auctionId) external view returns (Auction memory) {
        return auctions[auctionId];
    }

    function getBidCount(uint16 auctionId) external view returns (uint256) {
        return auctions[auctionId].bids.length;
    }

    function getBid(uint16 auctionId, uint256 index) external view returns (Bid memory) {
        require(index < auctions[auctionId].bids.length, "Index out of bounds");
        return auctions[auctionId].bids[index];
    }
}