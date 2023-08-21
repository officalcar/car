require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.17",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  defaultNetwork: "arbitrumOne",
  networks: {
    arbitrumOne: {
      url: "https://arb1.arbitrum.io/rpc",
      accounts: []
    }
  }
};