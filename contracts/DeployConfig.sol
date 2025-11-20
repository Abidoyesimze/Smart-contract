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
            // TODO: Get from Aave Address Book or official docs
            aavePoolAddressesProvider: address(0), // MUST UPDATE BEFORE DEPLOYMENT
            selfHubV2: 0x1a7E0033C45F2663BEc7A49eC1d2E4eB2C7acF81
        });
    }
    
    /* ========== CELO ALFAJORES TESTNET ========== */
    
    function getCeloAlfajores() internal pure returns (CeloAddresses memory) {
        return CeloAddresses({
            cUSD: 0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1, // Alfajores cUSD
            aavePoolAddressesProvider: address(0), // MUST UPDATE
            selfHubV2: 0x18E05EAc6f31D03Fb188fDc8e72ff354AB24Eab6
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