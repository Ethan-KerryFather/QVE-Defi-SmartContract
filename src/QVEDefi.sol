// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./QVEtoken.sol";
import "./QVEnft.sol";

contract QVEDefi is Ownable{

    // [------ variables, struct -------] //
    using SafeMath for uint;
    using Counters for Counters.Counter;
    using Strings for *;
    Counters.Counter private stakeCount;

    QVEtoken public qvetoken;
    QVEnft public qvenft;

    struct ETHstakingChunk{                   // wei 단위
        uint256 balance;
        uint256 at;
    }

    struct QVEliquidityChunk{                 // ether 단위
        uint256 balance;
        uint256 at;
    }

    struct Stake {
        uint72 tokenAmount;                   // 스테이킹에 락된 물량                                                            
        uint24 lockingPeriodInBlocks;         // 보상을 지급할 임의의 시간                                   
        uint32 startBlock;                    // 스테이킹 시작 시간                                                                           
        uint128 expectedStakingRewardPoints;  // 정상적으로 언락했을때 받게될 보상
    }

    struct NFTFragment {
        uint256 tokenId;
        uint256 at;
    }

    struct NFTs {
        NFTFragment[] fragment;
    }

    // [------ QVE Liquidity pool / ETH staking pool ------] //
    // QVE : ether unit     // ETHVault : wei unit
    QVEliquidityChunk public QVEliquidityPool;
    mapping (address => ETHstakingChunk) ETHstakingVault;

    // [------ Stake Pool ------] //
    /// @notice Active stakes for each user
    mapping (address => Stake) public stakes;
    /// @notice "Reward points" each user earned (would be relative to totalRewardPoints to get the percentage)
    mapping (address => uint256) public rewardPointsEarned;
    /// @notice Total "reward points" all users earned
    uint256 public totalRewardPoints;
    /// @notice Block when Staking Program ends          
    uint256 immutable public stakingProgramEndsBlock;
    /// @notice Amount of Staking Bonus Fund (500 000 OIL), Oiler funds must be here, approved and ready to be transferredFrom
    uint256 immutable public stakingFundAmount;


    // [------ NFT vault ------ ] //
    mapping (address => NFTs) nftVault;

    constructor(QVEtoken _qveTokenAddress, QVEnft _qvenft) {
        qvetoken = _qveTokenAddress;
        qvenft = _qvenft;
        qvetoken.normal_transfer(msg.sender, address(this), qvetoken.totalSupply() / 2 );
        QVEliquidityPool.balance += qvetoken.balanceOf(address(this)) / 10 ** 18;
    }

    /*
        프론트에서 할일 
        일단 이더리움을 그냥 string으로 하던 숫자로 받던 상관은 없는데, 컨트렉트 호출 시에 wei단위로 보내줄 것
    */

    function receiveAsset(uint256 assetAmount) public payable returns(bool){
    /*
        먼저 사용자가 이더리움을 전송하면
        require(msg.value == assetAmount * 10 ** 18, "Sent ether is not match with the specified amount");
        이더리움을 양을 체크하고
        address payable _to = _botAddress();
        _to.transfer(assetAmount * 10 ** 18);
        해당하는 양만큼 봇주소로 보냄
    */
        stakeEth(assetAmount);
        string memory assetString = string(abi.encodePacked("This", " ", "nft", " ", "guarantees", " : ", assetAmount.toString()," ", "ETH"));
        qvenft.setMetadata("Staking Guarantee Card", assetString, "https://ipfs.io/ipfs/QmWEgQskBctQJUarEycv6cxPnM3Wr4aHz6rGoq2QmTvwUc?filename=QVEwarranty.png");
        return true;
    }

    function stakeEth(uint256 stakeAmount) internal returns(bool){
        _issueGuaranteeNFT(msg.sender);
        _addUserStakeVault(msg.sender, stakeAmount);
        stakeCount.increment();
        return true;
    }

    function shortenLockup(uint256 qveAmount) public returns(bool){
        require(qvenft.shortenLockup(qveAmount, address(this)), "shorten error");
        _addLiquidity(qveAmount);
        return true;
    }

    function burnStakingGuarantee() public returns(bool){
        
        require(_sendQVEFromLiquidity(msg.sender, ETHstakingVault[msg.sender].balance), "Burn QVE transfer error");
        return true;
    }

    
    function getStakeCount() external view returns(uint256){
        return stakeCount.current();
    } 

    // [------ internal Functions ------] //
    function _botAddress() internal pure returns(address payable) {
        return payable(address(uint160(0x1e721FF3c56EA3001B6Cf7268e2dAe8ddb10010A)));
    }

    function _sendQVEFromLiquidity(address _to, uint256 sendAmount) internal returns(bool){
        require(qvetoken.normal_transfer(address(this), _to, sendAmount * 10 ** 18), "QVE transfer error");
        QVEliquidityPool.balance -= sendAmount;
        QVEliquidityPool.at = block.timestamp;
        return true;
    }

    function _addUserStakeVault(address userAddress, uint256 stakeAmount) internal returns(bool){
        ETHstakingVault[userAddress].balance += stakeAmount * 10 ** 18;
        return true;
    }

    function _addLiquidity(uint256 amount) internal returns(bool){
        QVEliquidityPool.balance += amount;
        QVEliquidityPool.at = block.timestamp;
        return true;
    }

    function _subLiquidity(uint256 amount) internal returns(bool){
        QVEliquidityPool.balance -= amount;
        QVEliquidityPool.at = block.timestamp;
        return true;
    }

    function _issueGuaranteeNFT(address sender) internal returns(bool){
        uint256 item_id = qvenft.mintStakingGuarantee(sender);

        NFTFragment memory newFragment = NFTFragment({
            tokenId : item_id,
            at : block.timestamp
        });

        nftVault[sender].fragment.push(newFragment);
        return true;
    }

    function _getNFTbalance() external view returns(uint){
        return qvenft.balanceOf(msg.sender);
    }

}