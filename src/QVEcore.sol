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
import "./QVEswap.sol";

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
    string private constant WARNING_ESCROW = "Warning For QVE Escrow error";
    string private constant WARNING_VESTING = "Warning For QVE Vesting";

    // [------ Events ------] //
 


    // [------ Variables, Struct -------] //
    uint8 private constant ESCROWRATIO = 10;
    QVEtoken public qvetoken;
    QVEnft public qvenft;
    QVEescrow public qveEscrow;
    QVEvesting public qveVesting;
    QVEstaking public qveStaking;
    QVEswap public qveSwap;

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
        QVEstaking _qveStaking,
        QVEswap _qveSwap
        ) 
        {
            qvetoken = _qveTokenAddress;
            qvenft = _qvenft;
            qveEscrow = _qveEscrow;
            qveVesting = _qveVesting;
            qveStaking = _qveStaking;
            qveSwap = _qveSwap;

            qvetoken.normal_transfer(msg.sender, address(this), qvetoken.totalSupply() / 4 );
            QVEliquidityPool.balance += qvetoken.balanceOf(address(this)) / 10 ** 18;
    }

    function getEthBalance(address _address) external view returns(uint){
        return _address.balance;
    }
    // receive() external payable{
    //    
    // }

    // fallback() external payable{

    // }

    // 이더리움
    function receiveAsset(bool lockup) public payable returns(bool){
        string memory assetString = string(abi.encodePacked("Margin : ", msg.value.toString(),"WEI"));
        qvenft.setMetadata("Staking Guarantee Card", assetString, "https://ipfs.io/ipfs/QmWEgQskBctQJUarEycv6cxPnM3Wr4aHz6rGoq2QmTvwUc?filename=QVEwarranty.png");
        investmentEth(msg.value , lockup); // 원래 맨 위였음
        return true;
    }



    function investmentEth(uint256 stakeAmount, bool lockup) internal returns(bool){
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
        require(qvetoken.normal_mint(msg.sender, marginForNFT[tokenId].mul(1e18)), WARNING_TRANSFER);
        // 스테이킹        
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
        return payable(address(uint160(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2)));
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
            require(qveVesting.addVesting(qveEscrow.mintForLockup(msg.sender, stakeAmount.mul(1e18)), msg.sender), WARNING_VESTING);
        }
        return item_id;
    }


    // [------ QVE Staking ------] //
    function doQVEStake(uint qveStakeAmount) public NoReEntrancy returns(bool){
        require(_makeQVEescrowedAndVesting(msg.sender, qveStakeAmount.mul(1e18).mul(ESCROWRATIO).div(100)), "Error in Make QVE escrowed and Vesting");
        require(qveStaking.stake(msg.sender, qveStakeAmount.mul(100 - ESCROWRATIO).div(100)), "Error in QVE staking");
        return true;
    }

    // function doQVEunStake(uint qveUnstakingAmount) public NoReEntrancy returns(bool){
    //     return true;
    // }

    function _makeQVEescrowedAndVesting(address sender,uint256 QVEamount) internal returns(bool){
        require(qveEscrow.makeQVEescrow(sender, QVEamount.mul(1e18)), WARNING_ESCROW);
        require(qveVesting.addVesting(QVEamount.mul(1e18), sender), WARNING_VESTING);
        return true;
    }


    // [------ QVE Swap ------] // 
    function swapETHtoQVE(uint256 tokenAmount) external returns(bool){
        qveSwap.swapETHtoQVE(tokenAmount, msg.sender);
        return true;
    }

    function swapQVEtoETH(uint256 tokenAmount) external returns(bool){
        qveSwap.swapQVEtoETH(tokenAmount, msg.sender);
        return true;
    }


}