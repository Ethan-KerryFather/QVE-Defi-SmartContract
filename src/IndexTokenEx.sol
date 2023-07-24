// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract IndexToken1 is ERC20Burnable, Ownable {
    uint256 public supply;

    // [------ Init -------] //
    constructor() ERC20("Index1", "Index1") {
        supply = 1000000000;
        _mint(msg.sender, supply * 10 ** 18);
    }

    // [------ functions -------] //
    function normal_transfer(address from, address target, uint256 amount) public returns(bool){
        _transfer(from, target, amount);
        return true;
    }
}

contract IndexToken2 is ERC20Burnable, Ownable {
    uint256 public supply;

    // [------ Init -------] //
    constructor() ERC20("Index2", "Index2") {
        supply = 1000000000;
        _mint(msg.sender, supply * 10 ** 18);
    }

    // [------ functions -------] //
    function normal_transfer(address from, address target, uint256 amount) public returns(bool){
        _transfer(from, target, amount);
        return true;
    }
}
contract IndexToken3 is ERC20Burnable, Ownable {
    uint256 public supply;

    // [------ Init -------] //
    constructor() ERC20("Index3", "Index3") {
        supply = 1000000000;
        _mint(msg.sender, supply * 10 ** 18);
    }

    // [------ functions -------] //
    function normal_transfer(address from, address target, uint256 amount) public returns(bool){
        _transfer(from, target, amount);
        return true;
    }
}