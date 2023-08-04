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
import "./util/Security.sol";
import "./QVEvesting.sol";
import "./QVEstaking.sol";
// interface DefiQVE{
//     function receiveAsset(uint256 assetAmount) external  payable returns(bool);     // User send ETH to QVE Defi
//     function shortenLockup(uint256 qveAmount) external returns(bool);               // Shorten Lockup using QVEtoken
//     function getStakeCount_() external view returns(uint256);                       // get Stake Count
//     function getNFTbalance_() external view returns(uint);                          // get NFT balance, if you want to want to inquire individual nft vault, USE [---nftVault---]
// }

contract QVEcore is Security, Ownable{

    using SafeMath for uint256;
    using Counters for Counters.Counter;
    using Strings for *;
    Counters.Counter private InputedMarginCount;


    // [------ Warning Strings ------] //
    string private constant WARNING_ADDRESS = "Warning For Address(0)";
    string private constant WARNING_TRANSFER = "Warning For Transfer";
    string private constant WARNING_VAULT = "Warning For Vault";
    string private constant WARNING_SHORTEN = "Warning For Lockup Shorten";


    // [------ Events ------] //
 


    // [------ Variables, Struct -------] //
    uint8 private constant ESCROWRATIO = 10;
    QVEtoken public qvetoken;
    QVEnft public qvenft;
    QVEescrow public qveEscrow;
    QVEvesting public qveVesting;
    QVEstaking public qveStaking;

    struct ETHstakingChunk{                   // wei 단위
        uint256 balance;
        uint256 at;
    }

    struct liquidityChunk{                 // ether 단위
        uint256 balance;
        uint256 at;
    }


    // [------ NFT vault ------ ] //
    struct NFTFragment {
        uint256 tokenId;
        uint256 at;
    }

    struct NFTs {
        NFTFragment[] fragment;
    }
  
    mapping (address => NFTs) nftVault;


    // [------ QVE Liquidity pool / ETH staking pool ------] //
    // QVE : ether unit     // ETHVault : wei unit
    liquidityChunk public QVEliquidityPool;
    liquidityChunk public esQVEliquidityPool;

    mapping (uint256 => uint256) private marginForNFT;


    // --- Put margin(ETH) ---- //
    struct marginDetail{
        uint256 marginAmount;
        uint256 at;
        uint256 random;
    }

    struct userMarginData{
        marginDetail[] marginDetails;
        uint256[] holdNFT;
    }

    mapping (address => userMarginData) EthMarginVault;

   
    constructor(
        QVEtoken _qveTokenAddress, 
        QVEnft _qvenft, 
        QVEescrow _qveEscrow, 
        QVEvesting _qveVesting,
        QVEstaking _qveStaking
        ) 
        {
            qvetoken = _qveTokenAddress;
            qvenft = _qvenft;
            qveEscrow = _qveEscrow;
            qveVesting = _qveVesting;
            qveStaking = _qveStaking;

            qvetoken.normal_transfer(msg.sender, address(this), qvetoken.totalSupply() / 4 );
            QVEliquidityPool.balance += qvetoken.balanceOf(address(this)) / 10 ** 18;
    }

    /*
        프론트에서 할일 
        일단 이더리움을 그냥 string으로 하던 숫자로 받던 상관은 없는데, 컨트렉트 호출 시에 wei단위로 보내줄 것
    */
    function receiveAsset(uint256 assetAmount, bool lockup) external payable returns(bool){
    /*
        먼저 사용자가 이더리움을 전송하면
        require(msg.value == assetAmount * 10 ** 18, "Sent ether is not match with the specified amount");
        이더리움을 양을 체크하고
        address payable _to = _botAddress();
        _to.transfer(assetAmount * 10 ** 18);
        해당하는 양만큼 봇주소로 보냄
    */
        stakeEth(assetAmount, lockup);
        string memory assetString = string(abi.encodePacked("Margin : ", assetAmount.toString(),"ETH"));
        qvenft.setMetadata("Staking Guarantee Card", assetString, "https://ipfs.io/ipfs/QmWEgQskBctQJUarEycv6cxPnM3Wr4aHz6rGoq2QmTvwUc?filename=QVEwarranty.png");
        return true;
    }

    function stakeEth(uint256 stakeAmount, bool lockup) internal returns(bool){
        uint256 tokenId = _issueGuaranteeNFT(msg.sender, stakeAmount,lockup);
        console.log(tokenId);
        require(_addUserMarginVault(msg.sender, stakeAmount, tokenId), WARNING_VAULT);
        InputedMarginCount.increment();

        return true;
    }

    // [------ Shorten Lockup ------] //
    function shortenLockup(uint256 qveAmount, uint256 tokenId) external returns(bool){
        require(qvenft.shortenLockup(qveAmount, address(this), tokenId), WARNING_SHORTEN);
        _addLiquidity(qveAmount);
        return true;
    }


    // [------ Burn staking Guarantee NFT ------ ] // 
    function burnStakingGuarantee(uint256 tokenId) public returns(bool){
        qvenft.burnNFT(tokenId);
        require(_sendQVEFromLiquidity(msg.sender, marginForNFT[tokenId]), WARNING_TRANSFER);
        require(_escrowQVE(marginForNFT[tokenId].mul(ESCROWRATIO).div(100).mul(1e18)));
        return true;
    }


    // [------ Getters ------ ] //
    function getInputedMarginCount() external view returns(uint256){
        return InputedMarginCount.current();
    } 

    function getNFTbalance_() external view returns(uint){
        return qvenft.balanceOf(msg.sender);
    }

    function getNfts_() external view returns(NFTFragment[] memory){
        return nftVault[msg.sender].fragment;
    }

    function getQVELiquidityAmount_() external view returns(uint){
        return QVEliquidityPool.balance;
    }

    // [------ internal Functions ------] //
    function _botAddress() internal pure returns(address payable) {
        return payable(address(uint160(0x1e721FF3c56EA3001B6Cf7268e2dAe8ddb10010A)));
    }

    function _sendQVEFromLiquidity(address _to, uint256 sendAmount) public returns(bool){
        require(qvetoken.normal_transfer(address(this), _to, sendAmount.mul(1e18)), WARNING_TRANSFER);
        QVEliquidityPool.balance -= sendAmount;
        QVEliquidityPool.at = block.timestamp;

        return true;
    }

    function _addUserMarginVault(address userAddress, uint amount, uint256 tokenId) internal returns(bool){
            marginDetail[] storage marginVault = EthMarginVault[userAddress].marginDetails;
            marginVault.push(marginDetail(amount, block.timestamp, tokenId));
            EthMarginVault[userAddress].holdNFT.push(tokenId);
            marginForNFT[tokenId] = amount;
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

    function _issueGuaranteeNFT(address sender, uint256 stakeAmount, bool lockup) internal NoReEntrancy returns(uint256){
        uint256 item_id = qvenft.mintStakingGuarantee(sender, lockup);
        nftVault[sender].fragment.push(NFTFragment(item_id, block.timestamp));
        _addUserMarginVault(msg.sender, stakeAmount, item_id);

        if(lockup){
            require(qveEscrow.mintToEscrow(msg.sender, stakeAmount * 100 * 1e18), "MintToEscrow error");
            qveVesting.addVesting(stakeAmount * 100, msg.sender);
        }
        return item_id;
    }

    function _escrowQVE(uint256 QVEamount) internal NoReEntrancy returns(bool){
        qveEscrow.makeQVEescrow(msg.sender, QVEamount);
        return true;
    }

    // [------ QVE Staking ------] //
    function doQVEStake(uint qveStakeAmount) public NoReEntrancy returns(bool){
        require(makeQVEescrowedAndVesting(msg.sender, qveStakeAmount.mul(1e18).mul(ESCROWRATIO).div(100)), "Error in Make QVE escrowed and Vesting");
        require(qveStaking.stake(msg.sender, qveStakeAmount.mul(100 - ESCROWRATIO).div(100)), "Error in QVE staking");
        return true;
    }

    // function doQVEunStake(uint qveUnstakingAmount) public NoReEntrancy returns(bool){
    //     return true;
    // }

    function makeQVEescrowedAndVesting(address escrower, uint256 QVEamount) internal returns(bool){
        qveEscrow.makeQVEescrow(escrower, QVEamount);
        qveVesting.addVesting(QVEamount, escrower);
        return true;
    }

}