// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SelfUtils} from "@selfxyz/contracts/contracts/libraries/SelfUtils.sol";

/**
 * @title DeployConfig
 * @notice Centralized configuration for deployment
 * @dev All addresses and parameters in one place
 */
library DeployConfig {
    
    /* ========== CELO MAINNET ADDRESSES ========== */
    
    struct CeloAddresses {
        address cUSD;
        address aavePoolAddressesProvider;
        address selfHubV2;
    }
    
    function getCeloMainnet() internal pure returns (CeloAddresses memory) {
        return CeloAddresses({
            cUSD: 0x765DE816845861e75A25fCA122bb6898B8B1282a,
            aavePoolAddressesProvider: 0x9F7Cf9417D5251C59fE94fB9147feEe1aAd9Cea5,
            selfHubV2: 0xe57F4773bd9c9d8b6Cd70431117d353298B9f5BF
        });
    }
    
    /* ========== CELO ALFAJORES TESTNET ========== */
    
    function getCeloAlfajores() internal pure returns (CeloAddresses memory) {
        return CeloAddresses({
            cUSD: 0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1, // Alfajores cUSD
            aavePoolAddressesProvider: address(0), // MUST UPDATE
            selfHubV2: 0x18E05eAC6F31d03fb188FDc8e72FF354aB24EaB6
        });
    }
    
    /* ========== SELF PROTOCOL CONFIG ========== */
    
    struct VerificationConfig {
        uint256 minimumAge;
        string[] forbiddenCountries;
        bool ofacEnabled;
    }
    
    function getDefaultVerificationConfig() 
        internal 
        pure 
        returns (SelfUtils.UnformattedVerificationConfigV2 memory) 
    {
        string[] memory forbidden = new string[](0);
        
        return SelfUtils.UnformattedVerificationConfigV2({
            olderThan: 18,
            forbiddenCountries: forbidden,
            ofacEnabled: false
        });
    }
    
    function getStrictVerificationConfig() 
        internal 
        pure 
        returns (SelfUtils.UnformattedVerificationConfigV2 memory) 
    {
        string[] memory forbidden = new string[](2);
        forbidden[0] = "US"; // Example
        forbidden[1] = "KP"; // North Korea
        
        return SelfUtils.UnformattedVerificationConfigV2({
            olderThan: 21,
            forbiddenCountries: forbidden,
            ofacEnabled: true
        });
    }
    
    /* ========== VAULT PARAMETERS ========== */
    
    struct VaultLimits {
        uint256 maxUserDeposit;
        uint256 maxTotalDeposit;
    }
    
    // Phase 1: Conservative launch
    function getPhase1Limits() internal pure returns (VaultLimits memory) {
        return VaultLimits({
            maxUserDeposit: 1_000 * 1e18,      // $1,000 per user
            maxTotalDeposit: 10_000 * 1e18     // $10,000 total
        });
    }
    
    // Phase 2: After 2 weeks of testing
    function getPhase2Limits() internal pure returns (VaultLimits memory) {
        return VaultLimits({
            maxUserDeposit: 10_000 * 1e18,     // $10,000 per user
            maxTotalDeposit: 100_000 * 1e18    // $100,000 total
        });
    }
    
    // Phase 3: After audit + 1 month
    function getPhase3Limits() internal pure returns (VaultLimits memory) {
        return VaultLimits({
            maxUserDeposit: 100_000 * 1e18,    // $100,000 per user
            maxTotalDeposit: 10_000_000 * 1e18 // $10M total
        });
    }
    
    /* ========== SELF PROTOCOL SCOPE ========== */
    
    function getScopeSeed() internal pure returns (string memory) {
        return "attestify-v1"; // Max 31 bytes
    }
}