require("@nomicfoundation/hardhat-toolbox");

require("dotenv/config");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {

  sourcify:{
    enabled: true
  },

  solidity: {
    compilers: [
      {
        version: "0.8.28",
        settings: {
          optimizer: { enabled: true, runs: 200 },
        },
      },
    ],
  },
  networks: {
    polygonAmoy: {
      url: process.env.RPC_URL,
      accounts: [process.env.Privatekey],
    },
  },
  etherscan: {
    apiKey: {
      polygonAmoy: process.env.ETHERSCAN_API_KEY, // use the key from .env
    },
    customChains: [
      {
        network: "polygonAmoy",
        chainId: 80002,
        urls: {
          apiURL: "https://www.oklink.com/api/explorer/v1/contract/verify/async/api/polygonAmoy",
      browserURL: "https://www.oklink.com/amoy",
        },
      },
    ],
  },
};
