// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title AttestifyVault
 * @notice Main vault contract for yield generation with identity verification
 * @dev Upgradeable vault using UUPS pattern, integrates with separate strategy contracts
 * 
 * Architecture:
 * - Vault: Holds user funds, manages shares
 * - Strategy: Deploys funds to yield sources (Aave)
 * - Verifier: Handles identity verification (Self Protocol)
 */
contract AttestifyVault is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES (DO NOT REORDER) ========== */
    
    // Core contracts
    IERC20 public asset;                    // cUSD token
    address public strategy;                // Aave strategy contract
    address public verifier;                // Self verifier contract
    
    // Vault accounting
    uint256 public totalShares;
    mapping(address => uint256) public shares;
    
    // User data
    mapping(address => UserData) public userData;
    
    struct UserData {
        uint256 totalDeposited;
        uint256 totalWithdrawn;
        uint256 lastActionTime;
    }
    
    // Configuration
    uint256 public constant MIN_DEPOSIT = 1e18;        // 1 cUSD
    uint256 public maxUserDeposit;                      // Per user limit
    uint256 public maxTotalDeposit;                     // Total TVL limit
    uint256 public constant RESERVE_RATIO = 10;         // 10% kept in vault
    
    // Admin
    address public treasury;
    address public rebalancer;                          // Can be AI agent
    uint256 public lastRebalance;
    
    // Stats
    uint256 public totalDeposited;
    uint256 public totalWithdrawn;
    
    /* ========== EVENTS ========== */
    
    event Deposited(address indexed user, uint256 assets, uint256 shares);
    event Withdrawn(address indexed user, uint256 assets, uint256 shares);
    event Rebalanced(uint256 strategyBalance, uint256 reserveBalance, uint256 timestamp);
    event StrategyUpdated(address indexed oldStrategy, address indexed newStrategy);
    event VerifierUpdated(address indexed oldVerifier, address indexed newVerifier);
    event LimitsUpdated(uint256 maxUser, uint256 maxTotal);
    
    /* ========== ERRORS ========== */
    
    error NotVerified();
    error InvalidAmount();
    error ExceedsUserLimit();
    error ExceedsTVLLimit();
    error InsufficientShares();
    error InsufficientBalance();
    error ZeroAddress();
    
    /* ========== CONSTRUCTOR ========== */
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /* ========== INITIALIZER ========== */
    
    /**
     * @notice Initialize vault (called once after proxy deployment)
     * @param _asset Underlying asset (cUSD)
     * @param _strategy Aave strategy contract
     * @param _verifier Self verifier contract
     * @param _maxUserDeposit Max deposit per user
     * @param _maxTotalDeposit Max total TVL
     */
    function initialize(
        address _asset,
        address _strategy,
        address _verifier,
        uint256 _maxUserDeposit,
        uint256 _maxTotalDeposit
    ) external initializer {
        if (_asset == address(0) || _strategy == address(0) || _verifier == address(0)) {
            revert ZeroAddress();
        }
        
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        
        asset = IERC20(_asset);
        strategy = _strategy;
        verifier = _verifier;
        maxUserDeposit = _maxUserDeposit;
        maxTotalDeposit = _maxTotalDeposit;
        treasury = msg.sender;
        rebalancer = msg.sender;
    }
    
    /* ========== UPGRADE AUTHORIZATION ========== */
    
    function _authorizeUpgrade(address newImplementation) 
        internal 
        override 
        onlyOwner 
    {}
    
    function version() external pure returns (string memory) {
        return "1.0.0";
    }
    
    /* ========== MODIFIERS ========== */
    
    modifier onlyVerified() {
        // Call verifier contract to check
        (bool success, bytes memory data) = verifier.staticcall(
            abi.encodeWithSignature("isVerified(address)", msg.sender)
        );
        
        if (!success || !abi.decode(data, (bool))) {
            revert NotVerified();
        }
        _;
    }
    
    /* ========== DEPOSIT FUNCTIONS ========== */
    
    /**
     * @notice Deposit cUSD to earn yield
     * @param assets Amount of cUSD to deposit
     * @return sharesIssued Shares minted to user
     */
    function deposit(uint256 assets) 
        external 
        nonReentrant 
        whenNotPaused 
        onlyVerified 
        returns (uint256 sharesIssued)
    {
        // Validation
        if (assets < MIN_DEPOSIT) revert InvalidAmount();
        if (assets > maxUserDeposit) revert ExceedsUserLimit();
        if (totalAssets() + assets > maxTotalDeposit) revert ExceedsTVLLimit();
        
        // Calculate shares
        sharesIssued = _convertToShares(assets);
        
        // Update state
        shares[msg.sender] += sharesIssued;
        totalShares += sharesIssued;
        userData[msg.sender].totalDeposited += assets;
        userData[msg.sender].lastActionTime = block.timestamp;
        totalDeposited += assets;
        
        // Transfer assets from user
        asset.safeTransferFrom(msg.sender, address(this), assets);
        
        // Deploy to strategy (keeping reserve)
        _deployToStrategy(assets);
        
        emit Deposited(msg.sender, assets, sharesIssued);
    }
    
    /**
     * @notice Internal function to deploy assets to strategy
     */
    function _deployToStrategy(uint256 amount) internal {
        uint256 reserveAmount = (amount * RESERVE_RATIO) / 100;
        uint256 deployAmount = amount - reserveAmount;
        
        if (deployAmount > 0) {
            // Approve strategy
            asset.forceApprove(strategy, deployAmount);
            
            // Call strategy deposit
            (bool success,) = strategy.call(
                abi.encodeWithSignature("deposit(uint256)", deployAmount)
            );
            require(success, "Strategy deposit failed");
        }
    }
    
    /* ========== WITHDRAW FUNCTIONS ========== */
    
    /**
     * @notice Withdraw cUSD (principal + yield)
     * @param assets Amount to withdraw
     * @return sharesBurned Shares burned
     */
    function withdraw(uint256 assets) 
        external 
        nonReentrant 
        returns (uint256 sharesBurned)
    {
        // Calculate shares to burn
        sharesBurned = _convertToShares(assets);
        if (shares[msg.sender] < sharesBurned) revert InsufficientShares();
        
        // Update state
        shares[msg.sender] -= sharesBurned;
        totalShares -= sharesBurned;
        userData[msg.sender].totalWithdrawn += assets;
        userData[msg.sender].lastActionTime = block.timestamp;
        totalWithdrawn += assets;
        
        // Check reserve
        uint256 reserveBalance = asset.balanceOf(address(this));
        
        // Withdraw from strategy if needed
        if (reserveBalance < assets) {
            uint256 shortfall = assets - reserveBalance;
            _withdrawFromStrategy(shortfall);
        }
        
        // Transfer to user
        asset.safeTransfer(msg.sender, assets);
        
        emit Withdrawn(msg.sender, assets, sharesBurned);
    }
    
    /**
     * @notice Withdraw all user's balance
     */
    function withdrawAll() external {
        uint256 userAssets = balanceOf(msg.sender);
        this.withdraw(userAssets);
    }
    
    /**
     * @notice Internal function to withdraw from strategy
     */
    function _withdrawFromStrategy(uint256 amount) internal {
        (bool success, bytes memory data) = strategy.call(
            abi.encodeWithSignature("withdraw(uint256)", amount)
        );
        require(success, "Strategy withdraw failed");
        
        uint256 received = abi.decode(data, (uint256));
        if (received < amount) revert InsufficientBalance();
    }
    
    /* ========== VIEW FUNCTIONS ========== */
    
    /**
     * @notice Get total assets under management
     * @return Total cUSD (reserve + strategy)
     */
    function totalAssets() public view returns (uint256) {
        uint256 reserveBalance = asset.balanceOf(address(this));
        
        // Get strategy balance
        (bool success, bytes memory data) = strategy.staticcall(
            abi.encodeWithSignature("totalAssets()")
        );
        
        uint256 strategyBalance = success ? abi.decode(data, (uint256)) : 0;
        
        return reserveBalance + strategyBalance;
    }
    
    /**
     * @notice Get user's balance in assets
     * @param user User address
     * @return Balance in cUSD
     */
    function balanceOf(address user) public view returns (uint256) {
        return _convertToAssets(shares[user]);
    }
    
    /**
     * @notice Get user's earnings
     * @param user User address
     * @return Total earnings
     */
    function getEarnings(address user) external view returns (uint256) {
        uint256 currentBalance = balanceOf(user);
        uint256 deposited = userData[user].totalDeposited;
        uint256 withdrawn = userData[user].totalWithdrawn;
        
        if (currentBalance + withdrawn > deposited) {
            return (currentBalance + withdrawn) - deposited;
        }
        return 0;
    }
    
    /**
     * @notice Convert assets to shares
     */
    function _convertToShares(uint256 assets) internal view returns (uint256) {
        uint256 _totalAssets = totalAssets();
        if (totalShares == 0 || _totalAssets == 0) return assets;
        return (assets * totalShares) / _totalAssets;
    }
    
    /**
     * @notice Convert shares to assets
     */
    function _convertToAssets(uint256 _shares) internal view returns (uint256) {
        if (totalShares == 0) return 0;
        return (_shares * totalAssets()) / totalShares;
    }
    
    /* ========== REBALANCE ========== */
    
    /**
     * @notice Rebalance between strategy and reserve
     */
    function rebalance() external {
        require(msg.sender == owner() || msg.sender == rebalancer, "Unauthorized");
        
        uint256 _totalAssets = totalAssets();
        uint256 targetReserve = (_totalAssets * RESERVE_RATIO) / 100;
        uint256 currentReserve = asset.balanceOf(address(this));
        
        if (currentReserve < targetReserve) {
            // Need more in reserve
            uint256 needed = targetReserve - currentReserve;
            _withdrawFromStrategy(needed);
        } else if (currentReserve > targetReserve * 2) {
            // Too much in reserve
            uint256 excess = currentReserve - targetReserve;
            _deployToStrategy(excess);
        }
        
        lastRebalance = block.timestamp;
        
        // Get updated balances
        (bool success, bytes memory data) = strategy.staticcall(
            abi.encodeWithSignature("totalAssets()")
        );
        uint256 strategyBalance = success ? abi.decode(data, (uint256)) : 0;
        
        emit Rebalanced(strategyBalance, asset.balanceOf(address(this)), block.timestamp);
    }
    
    /* ========== ADMIN FUNCTIONS ========== */
    
    function setStrategy(address _strategy) external onlyOwner {
        if (_strategy == address(0)) revert ZeroAddress();
        address old = strategy;
        strategy = _strategy;
        emit StrategyUpdated(old, _strategy);
    }
    
    function setVerifier(address _verifier) external onlyOwner {
        if (_verifier == address(0)) revert ZeroAddress();
        address old = verifier;
        verifier = _verifier;
        emit VerifierUpdated(old, _verifier);
    }
    
    function setLimits(uint256 _maxUser, uint256 _maxTotal) external onlyOwner {
        maxUserDeposit = _maxUser;
        maxTotalDeposit = _maxTotal;
        emit LimitsUpdated(_maxUser, _maxTotal);
    }
    
    function setRebalancer(address _rebalancer) external onlyOwner {
        if (_rebalancer == address(0)) revert ZeroAddress();
        rebalancer = _rebalancer;
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        require(paused(), "Must be paused");
        IERC20(token).safeTransfer(owner(), amount);
    }
    
    /* ========== STORAGE GAP ========== */
    uint256[50] private __gap;
}