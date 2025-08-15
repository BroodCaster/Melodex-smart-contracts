require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
	solidity: {
		version: "0.8.22",
		settings: {
			optimizer: {
				enabled: true,
				runs: 200,
			},
		},
	},
	networks: {
		hardhat: {
			chainId: 31337,
		},
		localhost: {
			url: "http://127.0.0.1:8545",
			chainId: 31337,
		},
		polygon: {
			url: process.env.POLYGON_RPC_URL || "https://polygon-rpc.com/",
			accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
			chainId: 137,
			gasPrice: 35000000000, // 35 gwei
			timeout: 60000,
		},
		polygonAmoy: {
			url:
				process.env.POLYGON_AMOY_RPC_URL ||
				"https://rpc-amoy.polygon.technology/",
			accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
			chainId: 80002,
			gasPrice: 35000000000, // 35 gwei
			timeout: 60000,
		},
	},
	etherscan: {
		apiKey: {
			polygon: process.env.POLYGONSCAN_API_KEY,
			polygonMumbai: process.env.POLYGONSCAN_API_KEY,
			polygonAmoy: process.env.POLYGONSCAN_API_KEY,
		},
		customChains: [
			{
				network: "polygonAmoy",
				chainId: 80002,
				urls: {
					apiURL: "https://api-amoy.polygonscan.com/api",
					browserURL: "https://amoy.polygonscan.com",
				},
			},
		],
	},
};
