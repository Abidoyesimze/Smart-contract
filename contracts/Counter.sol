// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract Counter {
    uint256 public x;

    event Increment(uint256 by);

    function inc() external {
        incBy(1);
    }

    function incBy(uint256 by) public {
        x += by;
        emit Increment(by);
    }
}

