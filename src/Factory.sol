// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { StrategyProxy } from "./StrategyProxy.sol";
import { Strategy } from "./Strategy.sol";

contract Factory {
    address public governor;
    address public keeper;
    uint256 public MANAGEMENT_FEE;
    mapping(address => mapping(address => bytes32)) public strategys;

    event CreateStrategy(address creator, bytes32 name, address strategyImplementation, address strategyProxy);
    event DeleteStrategy(address creator, address strategyProxy);
    event Trader(bytes32 indexed name, address indexed trader, bool inverseCopyTrade, uint16 copySizeBPS, address defaultCollateral);

    modifier onlyGov {
        require(msg.sender == governor, "Only governor");
        _;
    }

    constructor() {
        governor = msg.sender;
    }

    receive() payable external {}

    function setGovernor(address newGovernor) public onlyGov {
        governor = newGovernor;
    }

    function setKeeper(address newKeeper) public onlyGov {
        keeper = newKeeper;
    }

    function setManagementFee(uint256 newManagementFee) public onlyGov {
        MANAGEMENT_FEE = newManagementFee;
    }

    function withdrawETH(address recepient) public onlyGov {
        payable(recepient).transfer(address(this).balance);
    }

    function withdrawTokens(address recepient, address token, uint256 tokenAmount) public onlyGov {
        IERC20(token).transfer(recepient, tokenAmount);
    }

    function createStrategy(bytes32 name) public {
        Strategy strategyImplementation = new Strategy();
        StrategyProxy strategyProxy = new StrategyProxy();
        strategyImplementation.initialize();
        Strategy(payable(address(strategyProxy))).setParams(name, keeper, address(this), MANAGEMENT_FEE);
        // strategyProxy.transferOwnership(msg.sender);
        strategys[msg.sender][address(strategyProxy)] = name;
        emit CreateStrategy(msg.sender, name, address(strategyImplementation), address(strategyProxy));
    }

    function deleteStrategy(address strategyProxy) public {
        delete strategys[msg.sender][strategyProxy];
        emit DeleteStrategy(msg.sender, strategyProxy);
    }

    function fireStrategyEvent(address caller, bytes32 name, address trader, bool inverseCopyTrade, uint16 copySizeBPS, address defaultCollateral) public {
        require(strategys[caller][msg.sender] == name, "onlystrategyOwner call");
        emit Trader(name, trader, inverseCopyTrade, copySizeBPS, defaultCollateral);
   }
}