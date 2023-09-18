// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Eric Igbinosun
 * @notice This contract is the core of the DSC system. it handles all the logic of the system
 *
 * The system is designed to be as minimal as possible and have the tokens maintain a 1 token == $1 peg
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 *
 */

contract DSCEngine is ReentrancyGuard {
    // Errors
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAndPriceFeedLengthMismatch();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TranferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();

    // State variables
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e18;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // this mean you have to be 200% overcolateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    // This is the priceFeed mapping
    mapping(address token => address priceFeed) s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDSCMinted) private s_DSCMinted;
    address[] private s_collateraTokens;

    DecentralizedStableCoin private immutable i_dsc;

    // Events
    event CollateralDeposited(address indexed user, address indexedtoken, uint256 indexed amount);

    // Modifiers
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    //Functions
    constructor(address[] memory tokenAddress, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddress.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAndPriceFeedLengthMismatch();
        }
        // loop through all the tokens
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_priceFeeds[tokenAddress[i]] = priceFeedAddresses[i];
            s_collateraTokens.push(tokenAddress[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    //External Functions
    function depositCollateralAndMintDSC() external {}

    /**
     * @param tokenCollateralAddress The address of the collateral token
     * @param amountCollateral The amount of collateral
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant //to prevent reentrancy
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool seccuess = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!seccuess) {
            revert DSCEngine__TranferFailed();
        }
    }

    function redeemCollateralForDSC() external {}

    function redeemCollateral() external {}

    /*
     * @notice follows CEI 
     * @param amountDSCToMint the amount of DSC to mint
     * @notice they must have more collateral value the minimum  
     */

    function mintDSC(uint256 amountDSCToMint) external moreThanZero(amountDSCToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDSCToMint;
        // if they minted too much ($150 DSC, $100 ETH)
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    // Private & Internal View Function

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateraValue(user);
    }

    //if a user goes below 1 then they can be liquidated

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        //return (collateralValueInUsd / totalDscMinted);
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    //Public and external view function

    function getAccountCollateraValue(address user) public view returns (uint256 totalCollateraValueInUsd) {
        // loop through all the tokens, get the amount they have deposited
        for (uint256 i = 0; i < s_collateraTokens.length; i++) {
            address token = s_collateraTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateraValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateraValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}
