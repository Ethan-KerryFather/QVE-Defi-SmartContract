// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./QVEstaking.sol";
import "./QVEcore.sol";

contract ProtocolFee{
    using SafeMath for uint256;
    using Counters for Counters.Counter;
    
    QVEstaking qveStaking;
    QVEcore qveCore;
    Counters.Counter public totalSettle;
    uint256 distributePeriod = 7 days;


    constructor(QVEstaking _qveStaking, QVEcore _qveCore) {
        qveStaking = _qveStaking;
        qveCore = _qveCore;
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
    // bot -> contract 
    function SettleFromStrategy_(uint256 amount, address sender, address payable strategy) external payable returns(bool){
        require(msg.sender == qveCore.getstrategyAddress_(strategy), "Warn : invalid strategy Address");
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

   function _unstakeAfter(uint256 sentAmount) internal returns(bool){
       
   }



}