// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../util/Security.sol";

contract QVEtoken is ERC20Burnable, Ownable, Security {
    uint256 public initialSupply;

    // [------ Init -------] //
    constructor() ERC20("QVE", "QVE") {
        initialSupply = 1000000000;
        _mint(msg.sender, initialSupply * 10 ** 18);
    }

    // [------ Event ------] //
    event TransferEvent(address from, address to, uint256 amount);
    event BurnEvent(address from, uint256 amount);

    // [------ functions -------] //
    function normal_transfer(address from, address target, uint256 amount) NoReEntrancy public returns(bool){
        _transfer(from, target, amount);

        emit TransferEvent(from, target, amount);
        return true;
    }

    function normal_burn(address from, uint256 amount) public returns(bool){
        super._burn(from, amount);

        emit BurnEvent(from, amount);
        return true;
    }

    function normal_mint(address account, uint256 amount) public NoReEntrancy returns(bool){
        _mint(account, amount);
        return true;
    }
}
