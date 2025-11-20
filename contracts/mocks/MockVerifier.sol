// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../IAave.sol";

contract MockVerifier is ISelfVerifier {
    mapping(address => bool) private _status;

    function setVerified(address user, bool verified) external {
        _status[user] = verified;
    }

    function isVerified(address user) external view override returns (bool) {
        return _status[user];
    }

    function getNullifier(address) external pure override returns (bytes32) {
        return bytes32(0);
    }

    function verifySelfProof(bytes memory, bytes memory) external pure override {}
}

