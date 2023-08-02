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
    stQVEtoken public stqveToken;
    uint24 private REWARD_PERIOD = 1 days;
    uint256 private MINIMAL_PERIOD = 90 days;

    Counters.Counter private StakeCount;

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

    mapping (address => uint256[]) ownedStake;
    mapping (uint256 => StakeDetail) stakeVault;

    constructor(QVEtoken _qveToken, stQVEtoken _stqveToken) {
        qveToken = _qveToken;
        stqveToken = _stqveToken;
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

        require(stqveToken.normal_mint(staker, stakeAmount.mul(1e18)), WARN_MINT_TRANSFER);
        StakeCount.increment();
        emit StakeEvent(staker, stakeAmount);
        
        return true;
    }

    function unStake(address staker, uint256 unstakeAmount) external NoReEntrancy returns(bool){
        require(stqveToken.normal_transfer(staker, address(this), unstakeAmount.mul(1e18)), WARN_TRANSFER);

        stqveToken.normal_burn(address(this), unstakeAmount.mul(1e18));
        emit UnStakeEvent(staker, unstakeAmount);
        return true;
    }

    // [------ Internal Functions ------] //
    // function claimStakeReward(uint256 stakeNum) internal NoReEntrancy returns(bool){
    //     uint256 timeFlowed = block.timestamp.sub(stakeVault[stakeNum].startBlock);
    //     return true;
    // }

}