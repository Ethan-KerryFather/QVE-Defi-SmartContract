// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./tokens/QVEtoken.sol";
import "./tokens/stQVEtoken.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./util/Security.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract QVEstaking is Security {
    using Counters for Counters.Counter;
    using SafeMath for uint256;
    QVEtoken public qveToken;
    //stQVEtoken public stqveToken;
    uint24 private REWARD_PERIOD = 1 days;
    uint256 private MINIMAL_PERIOD = 90 days;

    Counters.Counter private totalStakeCount;   // 총 스테이킹 횟수
    Counters.Counter private totalSettlementCount;  // 정산 컨트랙트에서 정산된 횟수
    mapping(address => uint256) public stakePercentage; // 주소별 스테이킹 비율

    // [----- Warning Strings ------] //
    string constant private WARN_TRANSFER = "Transfer Error";
    string constant private WARN_MINT_TRANSFER ="Mint, Transfer Error";

    // [------ Events ------] // 
    event StakeEvent(address stakerAddress, uint256 stakeAmount);
    event UnStakeEvent(address stakerAddress, uint256 unstakeAmount);

    // [------Distribution------] //
    

    // [------ Variables, Mappings ------] //
    struct StakeDetail {       
        uint256 stakeNum;
        uint256 tokenAmount;                   // 스테이킹에 락된 물량
        // ether 단위로 관리                                                            
        uint256 startBlock;                    // 스테이킹 시작 시간                                                                           
        // Sum is 32 byte (word)
    }
    
    uint256 private totalStaked;
    // wei 단위로 관리

    
    struct StakeInfo{
        uint256 amount;
        uint256[] at;
    }
    mapping (address => StakeInfo) stakeInfo;   // 스테이킹 액수 관리 ( 총 )
    mapping (address => uint256 count) stakeCount; // 스테이킹 카운더 ( 사람 당 )

    // Settle balance
    mapping(uint256 => uint256) SettlementLog; // block.timestamp => amount
    uint256 private totalSettlement;
    

    constructor(QVEtoken _qveToken) {
        qveToken = _qveToken;
    }

    // [------ Getters ------] //
    function getTotalStaked() external view returns(uint256){
        return totalStaked;
    }

    function getTotalStakeNum() external view returns(uint256){
        return totalStakeCount.current();
    }

    function getPersonalStakeInfo(address sender) external view returns(StakeInfo memory){
        return stakeInfo[sender];
    }

    // [------ functions ------] //
    function stake(address staker, uint256 stakeAmount) external returns(bool){
        require(qveToken.balanceOf(staker)>= stakeAmount, "Warn : Insufficient QVE balance to stake");
        require(qveToken.via_transfer(address(this), staker, address(this), stakeAmount), "Warn : via transfer failed");
        
        _stakeAfter(staker, stakeAmount);

        emit StakeEvent(staker, stakeAmount);
        
        return true;
    }

    function unStake(address staker, uint256 unstakeAmount) external NoReEntrancy returns(bool){
        require(stakeInfo[staker].amount !=0, "Warn : 0 staked balance");
        require(stakeInfo[staker].amount >= unstakeAmount, "Warn : Insufficient staked balance");
        require(qveToken.transfer(staker, unstakeAmount), "Warn : Send QVE error");

        _unstakeAfter(unstakeAmount, staker);
        return true;
    }

    function receiveSettledEth(uint256 receivedAmount) external payable returns(bool){
        require(msg.value == receivedAmount, "Warn : received Amount , msg.value are different");

        totalSettlement = totalSettlement.add(receivedAmount);
        SettlementLog[block.timestamp] = receivedAmount;
        totalSettlementCount.increment();
        return true;
    }

    // [------ distribute profit to stakers ------] // 
    address[] public stakers;

    // 스테이킹 함수 내에서
  function _stakeAfter(address staker, uint256 stakeAmount) internal returns(bool){
    if (stakeInfo[staker].amount == 0) { // 이 조건은 처음 스테이킹하는 경우에만 true가 된당
        stakers.push(staker);
    }
    totalStaked = totalStaked.add(stakeAmount);
    stakeInfo[staker].amount = stakeInfo[staker].amount.add(stakeAmount);
    stakeInfo[staker].at.push(block.timestamp);
    stakeCount[staker] = stakeCount[staker].add(1);

    // Update stake percentage for all stakers
    for (uint256 i = 0; i < stakers.length; i++) {
        address currentStaker = stakers[i];
        stakePercentage[currentStaker] = stakeInfo[currentStaker].amount.mul(100).div(totalStaked);
    }

    totalStakeCount.increment();
    return true;
}

    // [------ Distribute ------] //
    mapping(address => uint256) public distributedEth;

    function claimDistribution() external payable returns(bool) {
    // 1. 컨트랙트에 이더리움 잔액이 있는지 확인
    require(address(this).balance > 0, "No ETH in the contract");

    uint256 totalDistributed = 0;

    // 2. 먼저 전체 분배할 이더리움의 총량을 계산
    uint256 totalDistributeAmount = address(this).balance.mul(9).div(10);

    // 3. 각 스테이커에게 분배할 이더리움 계산 및 전송
    for (uint256 i = 0; i < stakers.length; i++) {
        address staker = stakers[i];
        uint256 stakerShare = (stakeInfo[staker].amount.mul(totalDistributeAmount)).div(totalStaked);

        require(stakerShare <= address(this).balance - totalDistributed, "Not enough ETH in the contract");

        // 분배된 이더리움 기록
        distributedEth[staker] = distributedEth[staker].add(stakerShare);

        // 이더리움 전송
        payable(staker).transfer(1000000000000000);
        //payable(staker).transfer(stakerShare);

        totalDistributed = totalDistributed.add(stakerShare);
    }

    return true;
}




    // unstake 함수 내에서
    function _unstakeAfter(uint256 unstakeAmount, address unstaker) internal returns(bool) {
    totalStaked = totalStaked.sub(unstakeAmount);

    stakeInfo[unstaker].amount = stakeInfo[unstaker].amount.sub(unstakeAmount);
    stakeCount[unstaker] = stakeCount[unstaker].add(1);
    totalStakeCount.decrement();

    // 모든 토큰을 unstake한 경우 stakers 배열에서 제거
    if (stakeInfo[unstaker].amount == 0) {
        for (uint256 i = 0; i < stakers.length; i++) {
            if (stakers[i] == unstaker) {
                stakers[i] = stakers[stakers.length - 1];
                stakers.pop();
                break;
            }
        }
    }

    // Update stake percentage for all stakers
    for (uint256 i = 0; i < stakers.length; i++) {
        address currentStaker = stakers[i];
        stakePercentage[currentStaker] = stakeInfo[currentStaker].amount.mul(100).div(totalStaked);
    }

    return true;
}

    function getStakePercentage(address staker) external view returns (uint256) {
        return stakePercentage[staker];
    }
    function getTotalStakers() external view returns(uint256) {
    return stakers.length;
}

    // function claimStakeReward(uint256 stakeNum) internal NoReEntrancy returns(bool){
    //     uint256 timeFlowed = block.timestamp.sub(stakeVault[stakeNum].startBlock);
    //     return true;
    // }

}