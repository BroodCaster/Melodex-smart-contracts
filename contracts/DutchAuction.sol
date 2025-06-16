// SPDX-License-Identifier: NONE
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
    }

    

    mapping(uint16 => Auction) public auctions; // Mapping of auction ID to Auction details
    mapping(uint16 => Bid[]) public bids; // Mapping of auction ID to array of bids
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
            sold: false
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

        bids[auctionId].push(Bid({
            bidder: msg.sender,
            amount: amount,
            price: price
        }));
        
        auction.sold = true;

        emit BidPlaced(auctionId, msg.sender, amount, price);
    }

    // function finalizeAuction(uint16 auctionId) external onlyOwner {
    //     Auction storage auction = auctions[auctionId];
    //     require(block.timestamp > auction.startTime + auction.duration, "Auction not ended");
    //     require(auction.sold, "Auction not sold");

    //     uint256 bidCount = auction.bids.length;
    //     Bid[] memory bidsOffChain = new Bid[](bidCount);
    //     for (uint256 i = 0; i < bidCount; i++) {
    //         bidsOffChain[i] = auction.bids[i];
    //     }

    //     // Sort bids by price descending (bubble sort, inefficient for large data, okay for small arrays)
    //     for (uint256 i = 0; i < bidCount; i++) {
    //         for (uint256 j = 0; j < bidCount - 1 - i; j++) {
    //             if (bidsOffChain[j].price < bidsOffChain[j + 1].price) {
    //                 Bid memory temp = bidsOffChain[j];
    //                 bidsOffChain[j] = bidsOffChain[j + 1];
    //                 bidsOffChain[j + 1] = temp;
    //             }
    //         }
    //     }

    //     Bid[] storage winners = new Bid[](bidCount);
    //     uint256 totalAmount = 0;
    //     uint256 winnerCount = 0;
    //     for (uint256 i = 0; i < bidCount; i++) {
    //         if (totalAmount + bidsOffChain[i].amount <= auction.tokenAmount) {
    //             winners[winnerCount] = bidsOffChain[i];
    //             totalAmount += bidsOffChain[i].amount;
    //             winnerCount++;
    //         } else {
    //             break;
    //         }
    //     }

    //     // Refund losing bidders
    //     for (uint256 i = winnerCount; i < bidCount; i++) {
    //         uint256 refund = bidsOffChain[i].price * bidsOffChain[i].amount;
    //         require(paymentToken.transfer(bidsOffChain[i].bidder, refund), "Refund to losing bidder failed");
    //     }

    //     // Determine the minimum winning price
    //     uint256 minPrice = type(uint256).max;
    //     for (uint256 i = 0; i < winnerCount; i++) {
    //         if (winners[i].price < minPrice) {
    //             minPrice = winners[i].price;
    //         }
    //     }

    //     // Refund overpayment to winners
    //     for (uint256 i = 0; i < winnerCount; i++) {
    //         if (winners[i].price > minPrice) {
    //             uint256 refund = (winners[i].price - minPrice) * winners[i].amount;
    //             require(paymentToken.transfer(winners[i].bidder, refund), "Refund failed");
    //         }
    //         winners[i].price = minPrice;
    //     }

    //     // Transfer tokens to winners
    //     ERC20 token = ERC20(auction.tokenAddress);
    //     for (uint256 i = 0; i < winnerCount; i++) {
    //         require(token.transfer(winners[i].bidder, winners[i].amount), "Token transfer failed");
    //     }

    //     // Transfer collected payment to auction owner
    //     require(paymentToken.transfer(auction.auctionOwner, minPrice * totalAmount), "Owner payment failed");

    //     emit AuctionFinalized(auctionId, winners[0].bidder, totalAmount, minPrice);

    //     // Clean up the auction
    //     delete auctions[auctionId];
    // }

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