// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../IAave.sol";

contract MockStrategy is IVaultYieldStrategy {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;
    address public vault;
    uint256 private _totalAssets;

    error NotVault();
    error InsufficientFunds();

    constructor(address _asset) {
        asset = IERC20(_asset);
    }

    function setVault(address _vault) external {
        vault = _vault;
    }

    function deposit(uint256 amount) external override returns (uint256) {
        if (msg.sender != vault) revert NotVault();
        asset.safeTransferFrom(msg.sender, address(this), amount);
        _totalAssets += amount;
        return amount;
    }

    function withdraw(uint256 amount) external override returns (uint256) {
        if (msg.sender != vault) revert NotVault();
        if (amount > _totalAssets) revert InsufficientFunds();
        _totalAssets -= amount;
        asset.safeTransfer(vault, amount);
        return amount;
    }

    function totalAssets() external view override returns (uint256) {
        return _totalAssets;
    }
}

