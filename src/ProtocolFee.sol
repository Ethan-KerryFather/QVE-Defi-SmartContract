// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./QVEstaking.sol";

contract ProtocolFee{
    using SafeMath for uint256;
    using Counters for Counters.Counter;
    
    QVEstaking qveStaking;
    Counters.Counter public totalSettle;
    uint256 distributePeriod = 7 days;


    constructor(QVEstaking _qveStaking) {
        qveStaking = _qveStaking;
    }

    // [------ Warns ------] //
    string constant private WARN_RECEIVE = "Warn : Settle From Strategy wallet";

    // [------ Events ------] //
    event meanlessTransfer(address sender, uint256 amount);

    // [------ Fallback, Receive ------]] //
    // 데이터 없이 이더를 그냥 돈 보내려고 하면 돌려줌
    fallback() external payable {
        payable(msg.sender).transfer(msg.value);
        emit meanlessTransfer(msg.sender, msg.value);
    }
    
    receive() external payable {
        payable(msg.sender).transfer(msg.value);
        emit meanlessTransfer(msg.sender, msg.value);

    }

    // [------ Balances ------] // 
    uint256 private totalBalance;

    struct Strategies{
        uint256 amount; // 쌓인 금액
        uint256 at; // 마지막으로 정산받은 timestamp
    }

    mapping (address => Strategies) StrategiesBalance;


    // [------ Settle ------] //
    function SettleFromStrategy_(uint256 amount, address sender) external payable returns(bool){
        require(amount == msg.value, WARN_RECEIVE);

        _SettleAfter(msg.value, sender);

        return true;
    }

    // [------ Distribute ------] //
    function SendToUnstakeAccount() internal returns(bool){
        qveStaking.receiveSettledEth{value: totalBalance}(totalBalance);
        return true;
    }
    
   // [------ Internal ------] // 
   function _SettleAfter(uint256 receiveAmount, address sender) internal returns(bool){
        StrategiesBalance[sender].amount = StrategiesBalance[sender].amount.add(receiveAmount);
        totalSettle.increment();
        totalBalance = totalBalance.add(receiveAmount);
        return true;
   }



}