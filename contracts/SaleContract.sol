// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SaleContract is ReentrancyGuard, Ownable {
    using SafeERC20 for ERC20;

    constructor () Ownable(msg.sender) { }

    struct Listing {
        address contractAddress;
        uint256 price;
        uint256 tokens;
        address seller;
        uint256 expiration;
    }

    mapping(uint256 => Listing) public listings;
    uint256 public listingCounter;
    address public COMMISSION_WALLET = 0xFCF8d2b098B3160654bbaDa1a8769483c71C288b;
    uint256 public constant COMMISSION_PERCENTAGE = 10;
    address public constant MELS_ADDRESS = 0x5FDAF637Aed59B2e6d384d9e84D8ac5cF03c6697;

    event ListingAdded(uint256 listingId, address indexed seller, address indexed contractAddress, uint256 price, uint256 tokens, uint256 expiration);
    event TokensPurchased(uint256 listingId, address indexed buyer, uint256 tokenAmount, uint256 price, bool withERC20);

    function addListing(uint256 price, address contractAddress, uint256 tokens, uint256 duration) external {
        require(price > 0, "Price must be greater than zero");
        require(tokens > 0, "Tokens must be greater than zero");
        require(duration > 0, "Duration must be greater than zero");
        require(contractAddress != address(0), "Invalid contract address");

        ERC20 token = ERC20(contractAddress);
        require(token.allowance(msg.sender, address(this)) >= tokens, "Token allowance too low");

        token.safeTransferFrom(msg.sender, address(this), tokens);

        listingCounter++;
        listings[listingCounter] = Listing({
            contractAddress: contractAddress,
            price: price,
            tokens: tokens,
            seller: msg.sender,
            expiration: block.timestamp + duration
        });

        emit ListingAdded(listingCounter, msg.sender, contractAddress, price, tokens, block.timestamp + duration);
    }

    function buyTokensWithERC20(
        uint256 listingId,
        uint256 tokenAmount,
        uint256 paymentAmount
    ) external nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.tokens > 0, "Listing does not exist");
        require(block.timestamp <= listing.expiration, "Listing has expired");
        require(listing.tokens >= tokenAmount, "Not enough tokens in listing");

        uint256 totalPrice = listing.price * tokenAmount;
        uint256 commission = (totalPrice * COMMISSION_PERCENTAGE) / 100;
        uint256 totalPaymentAmount = totalPrice + commission;
        require(paymentAmount == totalPaymentAmount, "Incorrect payment amount");

        ERC20 paymentERC20 = ERC20(MELS_ADDRESS);
        require(paymentERC20.allowance(msg.sender, address(this)) >= paymentAmount, "Payment token allowance too low");

        paymentERC20.safeTransferFrom(msg.sender, COMMISSION_WALLET, commission);
        paymentERC20.safeTransferFrom(msg.sender, listing.seller, totalPrice);

        listing.tokens -= tokenAmount;
        ERC20(listing.contractAddress).safeTransfer(msg.sender, tokenAmount);

        emit TokensPurchased(listingId, msg.sender, tokenAmount, totalPrice, true);
    }

    function withdrawTokensFromListing(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        require(msg.sender == listing.seller, "Only listing seller can withdraw");
        require(block.timestamp > listing.expiration, "Listing has not ended");
        require(listing.tokens > 0, "No tokens to withdraw");

        uint256 tokenAmountToWithdraw = listing.tokens;
        listing.tokens = 0;

        ERC20 token = ERC20(listing.contractAddress);
        token.safeTransfer(msg.sender, tokenAmountToWithdraw);
    }

    function setCommissionWallet(address newWallet) external onlyOwner {
        require(newWallet != address(0), "Invalid address");
        COMMISSION_WALLET = newWallet;
    }

}
