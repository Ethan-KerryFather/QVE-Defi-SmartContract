// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./tokens/QVEtoken.sol";

interface EscrowQVE{
    function makeQVEescrow(address, uint) external returns(bool);   // escrow QVE token
    function getEscrowedBalance_() external  view returns(uint);    // inquire User Escrowed QVE token in escrowed QVE vault
}

contract QVEescrow is ERC20, EscrowQVE {

    using Strings for *;
    QVEtoken qveToken;

    // [------ Variables, Constants, Mappings ------] //
    uint256 public supply;
    uint256 constant private LOCK_UP_DAYS = 180 days;

    struct escrowed{
        uint256 amount;
        uint256 at;
    }
    mapping (address => escrowed) public escrowedQVE;


    constructor(QVEtoken _qveToken) ERC20("esQVE", "esQVE") {
        supply = 0;
        qveToken = _qveToken;
        _mint(msg.sender, supply * 10 ** 18);
    }

    // [------ Token functions -------] //
    function normal_transfer(address from, address target, uint256 amount) public returns(bool){
        _transfer(from, target, amount);
        return true;
    }

    // [------ external functions ------] //
    function makeQVEescrow(address sender, uint256 QVEamount) external returns(bool){
        require(qveToken.normal_transfer(msg.sender, address(this), QVEamount), "qveToken transfer error");
        require(mintToEscrow(sender, QVEamount), "mint error");
        _inputEscrowVault(QVEamount);
        return true;
    }

    // [------ Getters ------] // 
    function getEscrowedBalance_() external view returns(uint256){
        return escrowedQVE[msg.sender].amount;
    }

    // [------ Internal functions -------] //
    function mintToEscrow(address receiver, uint256 amount) internal returns(bool){
        _mint(receiver, amount);
        return true;
    }

    function _inputEscrowVault(uint256 amount) internal{
        escrowedQVE[msg.sender].amount += amount;
        escrowedQVE[msg.sender].at = block.timestamp;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override  {
        super._beforeTokenTransfer(from, to, amount);
        if (from !=address(0)){
            //require(block.timestamp >= _mintTimes[tokenId] + lockupPeriod, );
            require(block.timestamp >= escrowedQVE[msg.sender].at + LOCK_UP_DAYS, string(abi.encodePacked(
                "token is still in lock period ", 
                Strings.toString( 
                    (escrowedQVE[msg.sender].at + LOCK_UP_DAYS - block.timestamp)/60/60/12), 
                "days left"
                )
            ));
        }
    }

}