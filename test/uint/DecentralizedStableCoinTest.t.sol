// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract TestDecentralizedStableCoin is Test {
    DecentralizedStableCoin dsc;
    address owner;
    address recipient;

    constructor() {
        dsc = new DecentralizedStableCoin();
        owner = msg.sender;
        recipient = address(0x123); // Replace with a valid recipient address
    }

    function testInitialValues() public {
        string memory expectedName = "DecentralizedStableCoin";
        string memory expectedSymbol = "DSC";
        uint256 expectedOwnerBalance = 0;

        string memory actualName = dsc.name();
        string memory actualSymbol = dsc.symbol();
        uint256 actualOwnerBalance = dsc.balanceOf(owner);

        assertEq(actualName, expectedName);
        assertEq(actualSymbol, expectedSymbol);
        assertEq(actualOwnerBalance, expectedOwnerBalance);
    }

    function testMinting() public {
        uint256 mintAmount = 100;

        bool mintResult = dsc.mint(recipient, mintAmount);
        uint256 recipientBalance = dsc.balanceOf(recipient);

        assert(mintResult);
        assertEq(recipientBalance, mintAmount);
    }
}
