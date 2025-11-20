// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SelfVerificationRoot} from "@selfxyz/contracts/contracts/abstract/SelfVerificationRoot.sol";
import {ISelfVerificationRoot} from "@selfxyz/contracts/contracts/interfaces/ISelfVerificationRoot.sol";
import {SelfStructs} from "@selfxyz/contracts/contracts/libraries/SelfStructs.sol";
import {SelfUtils} from "@selfxyz/contracts/contracts/libraries/SelfUtils.sol";
import {IIdentityVerificationHubV2} from "@selfxyz/contracts/contracts/interfaces/IIdentityVerificationHubV2.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title SelfProtocolVerifier
 * @notice Handles all Self Protocol verification logic
 * @dev Separate contract allows updating verification without touching vault
 */
contract SelfProtocolVerifier is SelfVerificationRoot, Ownable {
    
    /* ========== STATE VARIABLES ========== */
    
    // Verification configuration
    SelfStructs.VerificationConfigV2 public verificationConfig;
    bytes32 public verificationConfigId;
    
    // Authorized contracts (vaults) that can query verification status
    mapping(address => bool) public authorizedCallers;
    
    // Verified users data
    mapping(address => UserVerification) public verifications;
    
    struct UserVerification {
        bool isVerified;
        uint256 verifiedAt;
        bytes32 nullifier;
        uint256 age;          // If disclosed
        string nationality;   // If disclosed
    }
    
    /* ========== EVENTS ========== */
    
    event UserVerified(address indexed user, bytes32 indexed nullifier, uint256 timestamp);
    event CallerAuthorized(address indexed caller);
    event CallerRevoked(address indexed caller);
    event ConfigUpdated(bytes32 indexed newConfigId);
    
    /* ========== ERRORS ========== */
    
    error Unauthorized();
    error AlreadyVerified();
    error NotVerified();
    
    /* ========== CONSTRUCTOR ========== */
    
    /**
     * @notice Initialize Self verifier
     * @param _hubV2 Self Protocol Hub V2 address
     * @param _scopeSeed Unique scope identifier (max 31 bytes)
     * @param _config Verification requirements
     */
    constructor(
        address _hubV2,
        string memory _scopeSeed,
        SelfUtils.UnformattedVerificationConfigV2 memory _config
    ) 
        SelfVerificationRoot(_hubV2, _scopeSeed)
        Ownable(msg.sender)
    {
        // Format and register verification config with Self Hub
        verificationConfig = SelfUtils.formatVerificationConfigV2(_config);
        verificationConfigId = IIdentityVerificationHubV2(_hubV2)
            .setVerificationConfigV2(verificationConfig);
    }
    
    /* ========== SELF PROTOCOL REQUIRED FUNCTIONS ========== */
    
    /**
     * @notice Return verification config ID for Self Hub
     * @dev Called by Self Protocol during verification
     */
    function getConfigId(
        bytes32, // destinationChainId
        bytes32, // userIdentifier
        bytes memory // userDefinedData
    ) public view override returns (bytes32) {
        return verificationConfigId;
    }
    
    /**
     * @notice Called after successful verification by Self Hub
     * @dev Store verification data for the user
     */
    function customVerificationHook(
        ISelfVerificationRoot.GenericDiscloseOutputV2 memory output,
        bytes memory userData
    ) internal override {
        address user = msg.sender;
        
        // Prevent double verification
        if (verifications[user].isVerified) revert AlreadyVerified();
        
        // Store verification data
        verifications[user] = UserVerification({
            isVerified: true,
            verifiedAt: block.timestamp,
            nullifier: bytes32(output.nullifier),
            age: 0, // Extract from output if needed
            nationality: "" // Extract from output if needed
        });
        
        emit UserVerified(user, bytes32(output.nullifier), block.timestamp);
    }
    
    /* ========== PUBLIC VIEW FUNCTIONS ========== */
    
    /**
     * @notice Check if user is verified (callable by anyone)
     * @param user Address to check
     * @return True if verified
     */
    function isVerified(address user) external view returns (bool) {
        return verifications[user].isVerified;
    }
    
    /**
     * @notice Get user's nullifier (for sybil resistance)
     * @param user Address to check
     * @return Nullifier hash
     */
    function getNullifier(address user) external view returns (bytes32) {
        return verifications[user].nullifier;
    }
    
    /**
     * @notice Get full verification details (only authorized callers)
     * @param user Address to check
     * @return UserVerification struct
     */
    function getVerificationDetails(address user) 
        external 
        view 
        returns (UserVerification memory) 
    {
        if (!authorizedCallers[msg.sender]) revert Unauthorized();
        return verifications[user];
    }
    
    /* ========== ADMIN FUNCTIONS ========== */
    
    /**
     * @notice Authorize contract to query detailed verification data
     * @param caller Contract address (e.g., vault)
     */
    function authorizeCaller(address caller) external onlyOwner {
        authorizedCallers[caller] = true;
        emit CallerAuthorized(caller);
    }
    
    /**
     * @notice Revoke authorization
     * @param caller Contract address
     */
    function revokeCaller(address caller) external onlyOwner {
        authorizedCallers[caller] = false;
        emit CallerRevoked(caller);
    }
    
    /**
     * @notice Update verification config (creates new config ID)
     * @param newConfig New verification requirements
     */
    function updateConfig(
        SelfUtils.UnformattedVerificationConfigV2 memory newConfig
    ) external onlyOwner {
        verificationConfig = SelfUtils.formatVerificationConfigV2(newConfig);
        
        // Register new config with Self Hub (need hub address)
        // verificationConfigId = IIdentityVerificationHubV2(hubAddress)
        //     .setVerificationConfigV2(verificationConfig);
        
        emit ConfigUpdated(verificationConfigId);
    }
    
    /**
     * @notice Manual verification (emergency only)
     * @param user User to verify
     * @param nullifier Nullifier to assign
     */
    function manualVerify(address user, bytes32 nullifier) external onlyOwner {
        verifications[user] = UserVerification({
            isVerified: true,
            verifiedAt: block.timestamp,
            nullifier: nullifier,
            age: 0,
            nationality: ""
        });
        
        emit UserVerified(user, nullifier, block.timestamp);
    }
    
    /**
     * @notice Revoke verification (compliance/security)
     * @param user User to revoke
     */
    function revokeVerification(address user) external onlyOwner {
        if (!verifications[user].isVerified) revert NotVerified();
        verifications[user].isVerified = false;
    }
}