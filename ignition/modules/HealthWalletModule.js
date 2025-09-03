const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("HealthWalletModule", (m) => {
  // Get the admin address parameter (passed via CLI)
  const adminAddress = m.getParameter("adminAddress");

  // Deploy HealthWallet contract with the admin address
  const healthWallet = m.contract("HealthWallet", [adminAddress]);

  return { healthWallet };
});
