// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IGmxRouter} from "./interfaces/IGmxRouter.sol";
import {IGmxVault} from "./interfaces/IGmxVault.sol";
import {IGmxPositionRouter} from "./interfaces/IGmxPositionRouter.sol";
import {IWETH} from "./interfaces/IWETH.sol";

contract GMXAdapter is ReentrancyGuard{

    struct AccountState {
    address account;
    address collateralToken;
    address indexToken; // 160
    bool isLong; // 8
    uint8 collateralDecimals;
    bytes32[20] reserved;
    }
     struct OpenPositionContext {
    // parameters
    uint256 amountIn;
    uint256 sizeUsd;
    uint256 priceUsd;
    bool isMarket;
    // calculated
    uint256 fee;
    uint256 amountOut;
    uint256 gmxOrderIndex;
    uint256 executionFee;
}

struct ClosePositionContext {
    uint256 collateralUsd;
    uint256 sizeUsd;
    uint256 priceUsd;
    bool isMarket;
    uint256 gmxOrderIndex;
    uint256 executionFee;
}


struct ExchangeConfigs {
    address vault;
    address positionRouter;
    address orderBook;
    address router;
    bytes32 referralCode;
    // ========================
    uint32 marketOrderTimeoutSeconds;
    uint32 limitOrderTimeoutSeconds;
    uint32 initialMarginRate;
    uint32 maintenanceMarginRate;
    bytes32[20] reserved;
}

    address internal _WETH;

    uint256 internal constant GMX_DECIMAL_MULTIPLIER = 1e12; // 30 - 18

    address internal _factory;

    bytes32 internal _gmxPositionKey;

    ExchangeConfigs internal _exchangeConfigs;

    AccountState internal _account;


    event Withdraw(
        address collateralAddress,
        address account,
        uint256 balance
    );


    event OpenPosition(address collateralToken, address indexToken, bool isLong, OpenPositionContext context);
    event ClosePosition(address collateralToken, address indexToken, bool isLong, ClosePositionContext context);

    constructor(address weth) {
        _WETH = weth;
    }

    receive() external payable {}

    modifier onlyTraderOrFactory() {
        require(msg.sender == _account.account || msg.sender == _factory, "OnlyTraderOrFactory");
        _;
    }

    modifier onlyFactory() {
        require(msg.sender == _factory, "onlyFactory");
        _;
    }

    function setConfigs(
        address account,
        address collateralToken,
        address assetToken,
        bool isLong,
        ExchangeConfigs memory exchangeConfig
    ) public {
        _factory = msg.sender;
        _gmxPositionKey = keccak256(abi.encodePacked(address(this), collateralToken, assetToken, isLong));

        _account.account = account;
        _account.collateralToken = collateralToken;
        _account.indexToken = assetToken;
        _account.isLong = isLong;
        _account.collateralDecimals = ERC20(collateralToken).decimals();

        _exchangeConfigs = exchangeConfig;
    }

    function getPositionKey() external view returns(bytes32){
        return _gmxPositionKey;
    }

    function _tryApprovePlugins() internal {
        IGmxRouter(_exchangeConfigs.router).approvePlugin(_exchangeConfigs.orderBook);
        IGmxRouter(_exchangeConfigs.router).approvePlugin(_exchangeConfigs.positionRouter);
    }

    function openPosition(
        address swapInToken,
        uint256 swapInAmount, // tokenIn.decimals
        uint256 minSwapOut, // collateral.decimals
        uint256 sizeUsd, // 1e18
        uint96 priceUsd, // 1e18
        uint96 tpPriceUsd,
        uint96 slPriceUsd,
        uint8 flags // MARKET, TRIGGER
    ) external payable onlyTraderOrFactory nonReentrant {

        _tryApprovePlugins();
        bytes32 orderKey;
        orderKey = _openPosition(
            swapInToken,
            swapInAmount, // tokenIn.decimals
            minSwapOut, // collateral.decimals
            sizeUsd, // 1e18
            priceUsd, // 1e18
            flags // MARKET, TRIGGER
        );
    }

    function _openPosition(
        address swapInToken,
        uint256 swapInAmount, // tokenIn.decimals
        uint256 minSwapOut, // collateral.decimals
        uint256 sizeUsd, // 1e18
        uint96 priceUsd, // 1e18
        uint8 flags // MARKET, TRIGGER
    ) internal returns(bytes32 orderKey){

        _tryApprovePlugins();

        OpenPositionContext memory context = OpenPositionContext({
            sizeUsd: sizeUsd * GMX_DECIMAL_MULTIPLIER,
            priceUsd: priceUsd * GMX_DECIMAL_MULTIPLIER,
            isMarket: true,
            fee: 0,
            amountIn: 0,
            amountOut: 0,
            gmxOrderIndex: 0,
            executionFee: msg.value
        });
        if (swapInToken == _WETH) {
            IWETH(_WETH).deposit{ value: swapInAmount }();
            context.executionFee = msg.value - swapInAmount;
        }
        if (swapInToken != _account.collateralToken) {
            context.amountOut = swap(
                _exchangeConfigs,
                swapInToken,
                _account.collateralToken,
                swapInAmount,
                minSwapOut
            );
        } else {
            context.amountOut = swapInAmount;
        }
        context.amountIn = context.amountOut;
        IERC20(_account.collateralToken).approve(_exchangeConfigs.router, context.amountIn);

        return _openPosition(context);
    }

    /// @notice Place a closing request on GMX.
    function closePosition(
        uint256 collateralUsd, // collateral.decimals
        uint256 sizeUsd, // 1e18
        uint96 priceUsd, // 1e18
        uint96 tpPriceUsd, // 1e18
        uint96 slPriceUsd, // 1e18
        uint8 flags // MARKET, TRIGGER
    ) external payable onlyTraderOrFactory nonReentrant {

        _closePosition(
                collateralUsd, // collateral.decimals
                sizeUsd, // 1e18
                priceUsd, // 1e18
                flags // MARKET, TRIGGER
            );
    }

    /// @notice Place a closing request on GMX.
    function _closePosition(
        uint256 collateralUsd, // collateral.decimals
        uint256 sizeUsd, // 1e18
        uint96 priceUsd, // 1e18
        uint8 flags // MARKET, TRIGGER
    ) internal returns (bytes32 orderKey)  {

        ClosePositionContext memory context = ClosePositionContext({
            collateralUsd: collateralUsd * 1e24,
            sizeUsd: sizeUsd * 1e12,
            priceUsd: priceUsd * 1e30,
            isMarket: true,
            gmxOrderIndex: 0,
            executionFee: 0
        });
        return _closePosition(context);
    }

    function withdraw() external nonReentrant {

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            if (_account.collateralToken == _WETH) {
                IWETH(_WETH).deposit{ value: ethBalance }();
            } else {
            //   (payable(_account.account).call{value: ethBalance}("");
        }

        uint256 balance = IERC20(_account.collateralToken).balanceOf(address(this));
        //ToDo - should we check if margin is safe?
        if (balance > 0) {
            _transferToUser(balance);
                emit Withdraw(
                _account.collateralToken,
                _account.account,
                balance
            );
        }
        }
        // clean tpsl orders
}

    function _transferToUser(uint256 amount) internal {
        if (_account.collateralToken == _WETH) {
            IWETH(_WETH).withdraw(amount);
            payable(_account.account).call{value:amount}("");
        } else {
            IERC20(_account.collateralToken).transfer(_account.account, amount);
        }
    }


 

    function _getGmxPosition() internal view returns (IGmxVault.Position memory) {
        return IGmxVault(_exchangeConfigs.vault).positions(_gmxPositionKey);
    }

    function _openPosition(OpenPositionContext memory context) internal returns(bytes32 orderKey){
        IGmxVault.Position memory position = _getGmxPosition();
    
        address[] memory path = new address[](1);
        path[0] = _account.collateralToken;
        if (context.isMarket) {
            context.executionFee = 215000000000000;
            IGmxPositionRouter(_exchangeConfigs.positionRouter).createIncreasePosition{ value: context.executionFee }(
                path,
                _account.indexToken,
                context.amountIn,
                0,
                context.sizeUsd,
                _account.isLong,
                _account.isLong ? type(uint256).max : 0,
                context.executionFee,
                _exchangeConfigs.referralCode,
                address(0)
            );
       }
        emit OpenPosition(_account.collateralToken, _account.indexToken, _account.isLong, context);
    }

    function _closePosition(ClosePositionContext memory context) internal returns(bytes32 orderKey){
        IGmxVault.Position memory position = _getGmxPosition();

        address[] memory path = new address[](1);
        path[0] = _account.collateralToken;
        if (context.isMarket) {
            context.executionFee = getPrExecutionFee();
            context.priceUsd = _account.isLong ? 0 : type(uint256).max;
            IGmxPositionRouter(_exchangeConfigs.positionRouter).createDecreasePosition{ value: context.executionFee }(
                path, // no swap for collateral
                _account.indexToken,
                context.collateralUsd,
                context.sizeUsd,
                _account.isLong, // no swap for collateral
                address(this),
                context.priceUsd,
                0,
                context.executionFee,
                false,
                address(0)
            );
        } 
        emit ClosePosition(_account.collateralToken, _account.indexToken, _account.isLong, context);
    }

    function getPrExecutionFee() internal view returns (uint256) {
        return IGmxPositionRouter(_exchangeConfigs.positionRouter).minExecutionFee();
    }


     function getOraclePrice(
        ExchangeConfigs storage exchangeConfigs,
        address token,
        bool useMaxPrice
    ) internal view returns (uint256 price) {
        // open long = max
        // open short = min
        // close long = min
        // close short = max
        price = useMaxPrice //isOpen == isLong
            ? IGmxVault(exchangeConfigs.vault).getMaxPrice(token)
            : IGmxVault(exchangeConfigs.vault).getMinPrice(token);
        require(price != 0, "ZeroOraclePrice");
    }

    function swap(
        ExchangeConfigs memory exchangeConfigs,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut
    ) internal returns (uint256 amountOut) {
        IERC20(tokenIn).transfer(exchangeConfigs.vault, amountIn);
        amountOut = IGmxVault(exchangeConfigs.vault).swap(tokenIn, tokenOut, address(this));
        require(amountOut >= minOut, "AmountOutNotReached");
    }
}