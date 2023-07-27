// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./tokens/QVEtoken.sol";
import "./QVEescrow.sol";
import "./QVEnft.sol";

// interface DefiQVE{
//     function receiveAsset(uint256 assetAmount) external  payable returns(bool);     // User send ETH to QVE Defi
//     function shortenLockup(uint256 qveAmount) external returns(bool);               // Shorten Lockup using QVEtoken
//     function getStakeCount_() external view returns(uint256);                       // get Stake Count
//     function getNFTbalance_() external view returns(uint);                          // get NFT balance, if you want to want to inquire individual nft vault, USE [---nftVault---]
// }

contract QVEDefi is Ownable {

    using SafeMath for uint;
    using Counters for Counters.Counter;
    using Strings for *;
    Counters.Counter private stakeCount;


    // [------ variables, struct -------] //
    uint8 private constant ESCROWRATIO = 40;
    QVEtoken public qvetoken;
    QVEnft public qvenft;
    QVEescrow public qveEscrow;

    struct ETHstakingChunk{                   // wei 단위
        uint256 balance;
        uint256 at;
    }

    struct liquidityChunk{                 // ether 단위
        uint256 balance;
        uint256 at;
    }

    struct QVEStake {
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
    liquidityChunk public QVEliquidityPool;
    liquidityChunk public esQVEliquidityPool;

    mapping (address => ETHstakingChunk) public ETHstakingVault;

    // --- new ---- //
    struct marginDetail{
        uint256 marginAmount;
        uint256 at;
        uint256 random;
    }

    struct marginData{
        marginDetail[] marginDetails;
        uint256 Counter;
    }
    mapping (address => marginData) public EthMarginVault;

    // [------ about QVE Stake ------] //
    mapping (address => QVEStake) public QVEstakes;
    mapping (address => uint256) public rewardPointsEarned;
    uint256 public totalRewardPoints;
    uint256 immutable public stakingProgramEndsBlock;
    uint256 immutable public stakingFundAmount;


    // [------ NFT vault ------ ] //
    mapping (address => NFTs) nftVault;

    constructor(QVEtoken _qveTokenAddress, QVEnft _qvenft, QVEescrow _qveEscrow) {
        qvetoken = _qveTokenAddress;
        qvenft = _qvenft;
        qveEscrow = _qveEscrow;
        qvetoken.normal_transfer(msg.sender, address(this), qvetoken.totalSupply() / 4 );
        QVEliquidityPool.balance += qvetoken.balanceOf(address(this)) / 10 ** 18;
    }

    /*
        프론트에서 할일 
        일단 이더리움을 그냥 string으로 하던 숫자로 받던 상관은 없는데, 컨트렉트 호출 시에 wei단위로 보내줄 것
    */

    function receiveAsset(uint256 assetAmount) external payable returns(bool){
    /*
        먼저 사용자가 이더리움을 전송하면
        require(msg.value == assetAmount * 10 ** 18, "Sent ether is not match with the specified amount");
        이더리움을 양을 체크하고
        address payable _to = _botAddress();
        _to.transfer(assetAmount * 10 ** 18);
        해당하는 양만큼 봇주소로 보냄
    */
        stakeEth(assetAmount);
        string memory assetString = string(abi.encodePacked("Margin : ", assetAmount.toString(),"ETH"));
        qvenft.setMetadata("Staking Guarantee Card", assetString, "https://ipfs.io/ipfs/QmWEgQskBctQJUarEycv6cxPnM3Wr4aHz6rGoq2QmTvwUc?filename=QVEwarranty.png");
        return true;
    }

    function stakeEth(uint256 stakeAmount) internal returns(bool){
        _issueGuaranteeNFT(msg.sender);
        _addUserStakeVault(msg.sender, stakeAmount);
        _addUserMarginVault(msg.sender, stakeAmount);
        stakeCount.increment();
        return true;
    }

    // [------ Shorten Lockup ------] //
    function shortenLockup(uint256 qveAmount, uint256 tokenId) external returns(bool){
        require(qvenft.shortenLockup(qveAmount, address(this), tokenId), "shorten error");
        _addLiquidity(qveAmount);
        return true;
    }

    // [------ Burn staking Guarantee NFT ------ ] // 
    function burnStakingGuarantee(uint256 tokenId) public returns(bool){
        qvenft.burnNFT(tokenId);
        require(_sendQVEFromLiquidity(msg.sender, ETHstakingVault[msg.sender].balance / 10 ** 18), "Burn QVE transfer error");
        require(_escrowQVE(ETHstakingVault[msg.sender].balance * 10));
        return true;
    }


    // [------ Getters ------ ] //
    function getStakeCount_() external view returns(uint256){
        return stakeCount.current();
    } 

    function getNFTbalance_() external view returns(uint){
        return qvenft.balanceOf(msg.sender);
    }

    function getNfts_() external view returns(NFTFragment[] memory){
        return nftVault[msg.sender].fragment;
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

    // --- new --- //
    function _addUserMarginVault(address userAddress, uint amount) internal returns(bool){
            marginDetail[] storage marginVault = EthMarginVault[userAddress].marginDetails;
            marginVault.push(marginDetail(amount, block.timestamp, 1));
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
        uint256 item_id = qvenft.mintStakingGuarantee(sender, false);

        NFTFragment memory newFragment = NFTFragment({
            tokenId : item_id,
            at : block.timestamp
        });

        nftVault[sender].fragment.push(newFragment);
        return true;
    }

    function _escrowQVE(uint256 QVEamount) internal returns(bool){
        qveEscrow.makeQVEescrow(msg.sender, QVEamount);
        return true;
    }

   

   
}