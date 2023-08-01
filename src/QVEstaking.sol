// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./tokens/QVEtoken.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./util/Security.sol";

contract QVEstaking is Security {
    using SafeMath for uint256;
    QVEtoken public qveToken;
    uint24 private REWARD_PERIOD = 1 days;
    using Counters for Counters.Counter;

    Counters.Counter private StakeCount;

    // [----- Warning Strings ------] //
    string constant private WARN_TRANSFER = "Transfer Error";


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

    mapping (address => uint256[]) ownedStake;
    mapping (uint256 => StakeDetail) stakeVault;

    constructor(QVEtoken _qveToken) {
        qveToken = _qveToken;
    }

    // [------ Getters ------] //
    function getTotalStaked() external view returns(uint256){
        return totalStaked;
    }

    function getTotalStakeNum() external view returns(uint256){
        return StakeCount.current();
    }

    // [------ functions ------] //
    function stake(address staker, uint256 stakeAmount) external NoReEntrancy returns(bool){
        require(qveToken.normal_transfer(staker, address(this), stakeAmount.mul(1e18)), WARN_TRANSFER);
        
        totalStaked = totalStaked.add(stakeAmount.mul(1e18));
        stakeVault[StakeCount.current()] = StakeDetail({ tokenAmount : stakeAmount , startBlock : block.timestamp, stakeNum : StakeCount.current() });
        ownedStake[staker].push( StakeCount.current());

        StakeCount.increment();

        emit StakeEvent(staker, stakeAmount);
        
        return true;
    }

    function unStake(address staker, uint256 unstakeAmount) external NoReEntrancy returns(bool){

        emit UnStakeEvent(staker, unstakeAmount);
        return true;
    }

    // [------ Internal Functions ------] //
    function claimStakeReward(uint256 stakeNum) internal NoReEntrancy returns(bool){
        uint256 timeFlowed = block.timestamp.sub(stakeVault[stakeNum].startBlock);
        return true;
    }

}