// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;


import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
// import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract StrategyProxy is UUPSUpgradeable  {
    constructor() initializer{
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override {

    }


}