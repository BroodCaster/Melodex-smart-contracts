const { ethers } = require("hardhat");

async function main() {
	console.log("Starting deployment and interaction script...");

	const [deployer] = await ethers.getSigners();
	console.log("Deployer address:", deployer.address);

	const DUTCH_AUCTION_ADDRESS = "0xf5E84369c29bEE054Ab3ac53CeA3E162C5352feB";
	const TOKEN_FACTORY_ADDRESS = "0x9b339A98212A026Ef48E028C8b8899a08DbE104c";
	const PAYMENT_TOKEN_ADDRESS = "0x004917Aeb11793cB2A0E65cfa733017bB755b0D0";

	// Step 1: Deploy payment token (MELS) - you'll need to replace this with your actual payment token
	console.log("\n--- Step 1: Connect to Payment Token ---");
	const MockERC20 = await ethers.getContractFactory(
		"contracts/ERC20.sol:MELSTestToken"
	);
	const paymentToken = MockERC20.attach(PAYMENT_TOKEN_ADDRESS);
	console.log("Connected to Payment Token at:", PAYMENT_TOKEN_ADDRESS);

	// Step 2: Deploy DutchAuction contract
	// console.log("\n--- Step 2: Deploy DutchAuction Contract ---");
	// const DutchAuction = await ethers.getContractFactory("DutchAuction");
	// const dutchAuction = await DutchAuction.deploy(await paymentToken.getAddress());
	// await dutchAuction.waitForDeployment();
	// console.log("DutchAuction deployed to:", await dutchAuction.getAddress());

	console.log("\n--- Step 2: Connect to DutchAuction Contract ---");
	const DutchAuction = await ethers.getContractFactory("DutchAuction");
	const dutchAuction = DutchAuction.attach(DUTCH_AUCTION_ADDRESS);
	console.log("Connected to DutchAuction at:", DUTCH_AUCTION_ADDRESS);

	// Step 3: Deploy TokenFactory contract
	// console.log("\n--- Step 3: Deploy TokenFactory Contract ---");
	// const TokenFactory = await ethers.getContractFactory("TokenFactory");
	// const tokenFactory = await TokenFactory.deploy();
	// await tokenFactory.waitForDeployment();
	// console.log("TokenFactory deployed to:", await tokenFactory.getAddress());

	console.log("\n--- Step 3: Connect to TokenFactory Contract ---");
	const TokenFactory = await ethers.getContractFactory("TokenFactory");
	const tokenFactory = TokenFactory.attach(TOKEN_FACTORY_ADDRESS);
	console.log("Connected to TokenFactory at:", TOKEN_FACTORY_ADDRESS);

	// Step 4: Create a new token using TokenFactory
	console.log("\n--- Step 4: Create Token via TokenFactory ---");
	const tokenName = "My Song Token";
	const tokenSymbol = "MST";

	const createTokenTx = await tokenFactory
		.connect(deployer)
		.createToken(tokenName, tokenSymbol);
	const receipt = await createTokenTx.wait();

	// Get the token address from the event
	const tokenCreatedEvent = receipt.logs.find((log) => {
		try {
			const parsed = tokenFactory.interface.parseLog(log);
			return parsed.name === "TokenCreated";
		} catch (e) {
			return false;
		}
	});

	const newTokenAddress =
		tokenFactory.interface.parseLog(tokenCreatedEvent).args.tokenAddress;
	console.log("New SongToken created at:", newTokenAddress);

	// Step 5: Get the SongToken contract instance
	console.log("\n--- Step 5: Setup SongToken Contract ---");
	const SongToken = await ethers.getContractFactory("SongToken");
	const songToken = SongToken.attach(newTokenAddress);

	// Step 6: Approve DutchAuction to spend tokens
	console.log("\n--- Step 6: Approve DutchAuction Contract ---");
	const approvalAmount = 10000; // Amount of tokens to approve for auction
	const approveTx = await songToken
		.connect(deployer)
		.approve(await dutchAuction.getAddress(), approvalAmount);
	await approveTx.wait();
	console.log(`Approved ${approvalAmount} tokens for DutchAuction contract`);

	// Verify allowance
	const allowance = await songToken.allowance(
		deployer.address,
		await dutchAuction.getAddress()
	);
	console.log("Allowance confirmed:", allowance.toString());

	// Step 7: Create an auction
	console.log("\n--- Step 7: Create Auction ---");
	const auctionParams = {
		initialPrice: ethers.parseEther("1"), // 1 MELS per token
		tokenAmount: 100, // Amount of tokens to auction
		duration: 45 * 60,
		tokenAddress: newTokenAddress,
	};

	const createAuctionTx = await dutchAuction
		.connect(deployer)
		.createAuction(
			auctionParams.initialPrice,
			auctionParams.tokenAmount,
			auctionParams.duration,
			auctionParams.tokenAddress
		);
	const auctionReceipt = await createAuctionTx.wait();

	// Get auction ID from event
	const auctionCreatedEvent = auctionReceipt.logs.find((log) => {
		try {
			const parsed = dutchAuction.interface.parseLog(log);
			return parsed.name === "AuctionCreated";
		} catch (e) {
			return false;
		}
	});

	const auctionId =
		dutchAuction.interface.parseLog(auctionCreatedEvent).args.auctionId;
	console.log("Auction created with ID:", auctionId.toString());

	// Step 8: Verify auction details
	console.log("\n--- Step 8: Verify Auction ---");
	const auction = await dutchAuction.getAuction(auctionId);
	console.log("Auction Details:");
	console.log("- Owner:", auction.auctionOwner);
	console.log(
		"- Initial Price:",
		ethers.formatEther(auction.initialPrice),
		"MELS"
	);
	console.log("- Token Amount:", auction.tokenAmount.toString());
	console.log("- Token Address:", auction.tokenAddress);
	console.log("- Duration (timestamp):", auction.duration.toString());
	console.log("- Sold:", auction.sold);
}

// Error handling
main()
	.then(() => process.exit(0))
	.catch((error) => {
		console.error("Error in script execution:", error);
		process.exit(1);
	});
