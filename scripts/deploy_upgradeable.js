/**
 * Deploys the upgradeable DutchAuction (UUPS).
 *
 * Usage:
 *   PAYMENT_TOKEN=0x... SWAP_ROUTER=0x... \
 *     npx hardhat run scripts/deploy_upgradeable.js --network polygon
 *
 * Common router addresses:
 *   - QuickSwap (Polygon mainnet): 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff
 *   - SushiSwap (Polygon mainnet): 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506
 *   - Uniswap V2 (Ethereum):       0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
 *
 * USDT addresses:
 *   - Polygon mainnet: 0xc2132D05D31c914a87C6611C10748AEb04B58e8F
 *   - Ethereum mainnet: 0xdAC17F958D2ee523a2206206994597C13D831ec7
 */
const { ethers, upgrades, network } = require("hardhat");

async function main() {
	const paymentToken = process.env.PAYMENT_TOKEN;
	const swapRouter = process.env.SWAP_ROUTER;

	if (!paymentToken) throw new Error("PAYMENT_TOKEN env var is required");
	if (!swapRouter) throw new Error("SWAP_ROUTER env var is required");

	const [deployer] = await ethers.getSigners();
	console.log(`Network:        ${network.name}`);
	console.log(`Deployer:       ${deployer.address}`);
	console.log(`Payment token:  ${paymentToken}`);
	console.log(`Swap router:    ${swapRouter}`);

	const DutchAuction = await ethers.getContractFactory("DutchAuction");

	console.log("\nDeploying proxy + implementation via OpenZeppelin upgrades…");
	const proxy = await upgrades.deployProxy(
		DutchAuction,
		[paymentToken, swapRouter],
		{ kind: "uups", initializer: "initialize" }
	);
	await proxy.waitForDeployment();

	const proxyAddress = await proxy.getAddress();
	const implAddress = await upgrades.erc1967.getImplementationAddress(
		proxyAddress
	);

	console.log("\n--- Deployment complete ---");
	console.log(`Proxy (use this as DutchAuction address): ${proxyAddress}`);
	console.log(`Implementation:                           ${implAddress}`);
	console.log(`Owner:                                    ${deployer.address}`);
}

main().catch((err) => {
	console.error(err);
	process.exitCode = 1;
});
