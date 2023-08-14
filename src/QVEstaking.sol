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

    Counters.Counter private totalStakeCount;
    Counters.Counter private totalSettlementCount;

    // [----- Warning Strings ------] //
    string constant private WARN_TRANSFER = "Transfer Error";
    string constant private WARN_MINT_TRANSFER ="Mint, Transfer Error";

    // [------ Events ------] // 
    event StakeEvent(address stakerAddress, uint256 stakeAmount);
    event UnStakeEvent(address stakerAddress, uint256 unstakeAmount);


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

    // mapping (address => uint256[]) ownedStake;
    // mapping (uint256 => StakeDetail) stakeVault;

    struct StakeInfo{
        uint256 amount;
        uint256[] at;
    }
    mapping (address => StakeInfo) stakeInfo;
    mapping (address => uint256 count) stakeCount;

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

    // [------ Internal Functions ------] //
    function _unstakeAfter(uint256 unstakeAmount, address unstaker) internal returns(bool){
        totalStaked = totalStaked.sub(unstakeAmount);

        stakeInfo[unstaker].amount = stakeInfo[unstaker].amount.sub(unstakeAmount);
        stakeCount[unstaker] = stakeCount[unstaker].add(1);
        totalStakeCount.decrement();

        return true;
    }

    function _stakeAfter(address staker, uint256 stakeAmount) internal returns(bool){
        totalStaked = totalStaked.add(stakeAmount);
        stakeInfo[staker].amount = stakeInfo[staker].amount.add(stakeAmount);
        stakeInfo[staker].at.push(block.timestamp);
        stakeCount[staker] = stakeCount[staker].add(1);
        totalStakeCount.increment();
        // stakeVault[StakeCount.current()] = StakeDetail({ tokenAmount : stakeAmount , startBlock : block.timestamp, stakeNum : StakeCount.current() });
        // ownedStake[staker].push( StakeCount.current());
        return true;
    }

    // function claimStakeReward(uint256 stakeNum) internal NoReEntrancy returns(bool){
    //     uint256 timeFlowed = block.timestamp.sub(stakeVault[stakeNum].startBlock);
    //     return true;
    // }

}