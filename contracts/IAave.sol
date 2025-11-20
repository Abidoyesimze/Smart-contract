// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IAaveStrategy
 * @notice Interface for Aave V3 yield strategy
 */
interface IAaveStrategy {
    function deposit(uint256 amount) external returns (uint256);
    function withdraw(uint256 amount) external returns (uint256);
    function withdrawAll() external returns (uint256);
    function totalAssets() external view returns (uint256);
    function getCurrentAPY() external view returns (uint256);
    function setVault(address vault) external;
}

/**
 * @title ISelfVerifier
 * @notice Interface for Self Protocol verification
 */
interface ISelfVerifier {
    function isVerified(address user) external view returns (bool);
    function getNullifier(address user) external view returns (bytes32);
    function verifySelfProof(bytes memory proofPayload, bytes memory userContextData) external;
}

/**
 * @title IAttestifyVault
 * @notice Interface for main vault contract
 */
interface IAttestifyVault {
    function deposit(uint256 assets) external returns (uint256 shares);
    function withdraw(uint256 assets) external returns (uint256 shares);
    function withdrawAll() external;
    function balanceOf(address user) external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function getEarnings(address user) external view returns (uint256);
}

/**
 * @title IVaultYieldStrategy
 * @notice Minimal strategy interface consumed by the vault
 */
interface IVaultYieldStrategy {
    function deposit(uint256 amount) external returns (uint256);
    function withdraw(uint256 amount) external returns (uint256);
    function totalAssets() external view returns (uint256);
}