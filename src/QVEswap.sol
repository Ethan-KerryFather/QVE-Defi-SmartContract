// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./tokens/QVEtoken.sol";

contract QVEswap {

    // [------ Variables, Mappings ------] //
    QVEtoken public qveToken;
    address public owner;
    string constant private ETHtoQVE = "ETHtoQVE";
    string constant private QVEtoETH = "QVEtoETH";

    struct SwapLogChunk{
        bool QVEtoETH;
        bool ETHtoQVE;
        uint256 swapAmount;
    }
    // [------ Swap Logs ------] //
    mapping (address => SwapLogChunk[]) SwapLogs;
    

    // [------ Warnings ------] //
    string constant private WARNING_BALANCE_TOKEN = "Not Enough ERC20 Token";
    string constant private WARNING_BALANCE_ETHER = "Not Enough Ether";
    string constant private WARNING_SENTAMOUNT_MATCH = "Sent Ether doesn't match specified amount";

    // [------ Modifiers, Events ------] //
    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    event SwapQVEtoETH(uint256 QVEamount);
    event SwapETHtoQVE(uint256 ETHamount);

    constructor(QVEtoken _qveToken) {
        qveToken = _qveToken;
        owner = msg.sender;
    }


    // [------ Functions ------- //
    function depositEther() external payable onlyOwner {}

    function swapQVEtoETH(uint256 tokenAmount, address sender) external {
        require(tokenAmount <= qveToken.balanceOf(msg.sender), WARNING_BALANCE_TOKEN);
        uint256 etherAmount = address(this).balance;
        require(etherAmount >= tokenAmount, WARNING_BALANCE_ETHER);
        
        qveToken.transferFrom(msg.sender, address(this), tokenAmount);
        payable(msg.sender).transfer(tokenAmount);

        SwapLogChunk memory newSwapLog = SwapLogChunk({ETHtoQVE:false, QVEtoETH:true, swapAmount : tokenAmount});
        SwapLogs[sender].push(newSwapLog);


        emit SwapQVEtoETH(tokenAmount);
    }

    function swapETHtoQVE(uint256 ETHamount, address sender) external payable {
        require(msg.value == ETHamount, WARNING_SENTAMOUNT_MATCH);
        require(ETHamount <= qveToken.balanceOf(address(this)), WARNING_BALANCE_TOKEN);
        qveToken.transfer(msg.sender, ETHamount);

        SwapLogChunk memory newSwapLog = SwapLogChunk({ETHtoQVE:true, QVEtoETH:false, swapAmount : ETHamount});
        SwapLogs[sender].push(newSwapLog);
        emit SwapETHtoQVE(ETHamount);
    }
}
