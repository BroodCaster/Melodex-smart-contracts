/**
 * Upgrades the DutchAuction implementation behind an existing proxy.
 *
 * Usage:
 *   PROXY_ADDRESS=0x... \
 *     npx hardhat run scripts/upgrade.js --network polygon
 *
 * The new implementation contract name is taken from CONTRACT_NAME
 * (defaults to "DutchAuction"). The current owner of the proxy must
 * sign the transaction.
 */
const { ethers, upgrades, network } = require("hardhat");

async function main() {
	const proxyAddress = process.env.PROXY_ADDRESS;
	const contractName = process.env.CONTRACT_NAME || "DutchAuction";

	if (!proxyAddress) throw new Error("PROXY_ADDRESS env var is required");

	const [signer] = await ethers.getSigners();
	console.log(`Network:    ${network.name}`);
	console.log(`Signer:     ${signer.address}`);
	console.log(`Proxy:      ${proxyAddress}`);
	console.log(`New impl:   ${contractName}`);

	const NewImpl = await ethers.getContractFactory(contractName);

	console.log("\nUpgrading…");
	const upgraded = await upgrades.upgradeProxy(proxyAddress, NewImpl, {
		kind: "uups",
	});
	await upgraded.waitForDeployment();

	const newImplAddress = await upgrades.erc1967.getImplementationAddress(
		proxyAddress
	);
	console.log("\n--- Upgrade complete ---");
	console.log(`Proxy:             ${proxyAddress}`);
	console.log(`New implementation: ${newImplAddress}`);
}

main().catch((err) => {
	console.error(err);
	process.exitCode = 1;
});
