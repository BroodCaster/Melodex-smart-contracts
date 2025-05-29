// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DutchAuction {

    struct Auction {
        uint256 initialPrice; // Initial price of the NFT
        uint16 tokenAmount; // Amount of the token to be auctioned
        uint256 duration; // Duration of the auction in seconds
        uint256 startTime; // Start time of the auction
        bool sold; // Indicates if the NFT has been sold
    }

    mapping(uint16 => Auction) public auctions; // Mapping of auction ID to Auction details
    uint16 public auctionCounter; // Counter for auction IDs
    address public owner;
    ERC20 public paymentToken;

    event AuctionCreated(uint16 indexed auctionId, uint256 initialPrice, uint16 tokenAmount, uint256 duration, uint256 startTime);
    event BidPlaced(uint16 indexed auctionId, address indexed bidder, uint256 amount, uint256 price);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address _paymentToken) {
        owner = msg.sender;
        paymentToken = ERC20(_paymentToken);
    }

    function bid(uint16 auctionId, uint256 amount) external {
        Auction storage auction = auctions[auctionId];
        require(block.timestamp >= auction.startTime, "Auction not started");
        require(block.timestamp <= auction.startTime + auction.duration, "Auction ended");
        require(!auction.sold, "Already sold");
        require(amount == auction.tokenAmount, "Incorrect token amount");

        // Calculate current price (linear decrease)
        uint256 elapsed = block.timestamp - auction.startTime;
        uint256 price = auction.initialPrice;
        if (elapsed < auction.duration) {
            uint256 discount = (auction.initialPrice * elapsed) / auction.duration;
            price = auction.initialPrice - discount;
        } else {
            price = 0;
        }

        auction.sold = true;
        require(paymentToken.transferFrom(msg.sender, owner, price), "Payment failed");

        emit BidPlaced(auctionId, msg.sender, amount, price);
    }

   
}