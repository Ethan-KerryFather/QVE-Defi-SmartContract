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
    string private constant WARNING_ADDRESS = "Warning : You are trying to send asset to invalid Address";
    string private constant WARNING_TRANSFER = "Warning : Transfer failed";
    string private constant WARNING_VAULT = "Warning : Vault";
    string private constant WARNING_SHORTEN = "Warning : Lockup Shorten";
    string private constant WARNING_ESCROW = "Warning : QVE Escrow error";
    string private constant WARNING_VESTING = "Warning : QVE Vesting";
    string private constant WARNING_SENTAMOUNT = "Warning : Sent Eth Amount and Wanted Amount are different";
    string private constant WARNING_BALANCE = "Warning : You don't have suffient balance in your wallet";
    string private constant WARNING_NFTOWNER = "Warning : You are not NFT owner";

    // [------ Events ------] //
    event Received(address indexed sender, uint256 amount);

    receive() external payable{
        emit Received(msg.sender, msg.value);
    }


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
  
    mapping (address => NFTs) nftVault; // 주소 - {토큰id, mint시점}[]
    mapping (uint256 => uint256)  marginForNFT; // 토큰id - margin ETH 액수
    mapping (uint256 => address)  tokenIdForAddress; // 토큰id - 소유자 주소

    // [------ QVE Liquidity pool / ETH staking pool ------] //
    liquidityChunk public QVEliquidityPool;
    liquidityChunk public esQVEliquidityPool;



    // --- Put margin(ETH) ---- //
    struct marginDetail{
        uint256 marginAmount;
        uint256 at;
        uint256 tokenId;
    }

    struct userMarginData{
        marginDetail[] marginDetails;
        uint256[] holdNFT;
    }

    mapping (address => userMarginData) EthMarginVault;  // 주소 - {잔액, 시간, 토큰 id}[], NFTid[]

   
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

    }

    function getEthBalance(address _address) external view returns(uint){
        return _address.balance;
    }
   

    function receiveAsset(bool lockup, uint256 sendAmount) public payable returns(bool){
        // 조건검사
        require(msg.value == sendAmount, WARNING_SENTAMOUNT); // 보내려는 금액, 실제 보낸 금액 일치하는지 확인

        string memory assetString = string(abi.encodePacked("[Guaranteed Investment Margin]--:", msg.value.toString(),"WEI"));
        qvenft.setMetadata("Staking Guarantee Card", assetString, "https://ipfs.io/ipfs/QmQUumq8iYcA9X8uoafM2YU8LeyyMKzUN2HF5FGp6NpXEV?filename=Group%204584.jpg");
        
        investmentEth(msg.value, lockup); 
        // investmentEth 에는 쌩으로 다 들어가야 함

        return true;
    }

    function investmentEth(uint256 investAmount, bool lockup) internal returns(bool){
        uint256 tokenId = _issueGuaranteeNFT(msg.sender, investAmount,lockup);
        require(_addUserMarginVault(msg.sender, investAmount, tokenId), WARNING_VAULT);
        InputedMarginCount.increment();

        return true;
    }

    // [------ Shorten Lockup ------] //
    function shortenLockup(uint256 qveAmount, uint256 tokenId) external returns(bool){
        require(qvenft.shortenLockup(qveAmount, address(this), tokenId), WARNING_SHORTEN);
        _addLiquidity(qveAmount);
        return true;
    }


    // [------ Burn Investment Guarantee NFT ------ ] // 
    function burnInvestmentGuarantee(uint256 tokenId) public returns(bool){
        require(tokenIdForAddress[tokenId] == msg.sender, WARNING_NFTOWNER); // 함수 실행하는 사람이 실제 NFT소유자인지 확인

        qvenft.burnNFT(tokenId);
        require(qvetoken.normal_mint(msg.sender, marginForNFT[tokenId].mul(1e18)), WARNING_TRANSFER);
        // 1 eth : 1 qve
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

    function getEthMarginVault_() external view returns(userMarginData memory){
        return EthMarginVault[msg.sender];
    }

    function getmarginForNFT_(uint256 tokenId) external view returns(uint256){
        return marginForNFT[tokenId];
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
            marginVault.push(marginDetail({marginAmount : amount, at : block.timestamp, tokenId : tokenId}));
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
        tokenIdForAddress[item_id] = sender;

        if(lockup){
            require(qveVesting.addVesting(qveEscrow.mintForLockup(msg.sender, stakeAmount.mul(1e18)), msg.sender), WARNING_VESTING);
        }
        return item_id;
    }

    function _forwardFunds(address payable destination) external payable {
        require(msg.value > 0, "No funds sent");
        destination.transfer(msg.value);
    }


    // [------ QVE Staking ------] //
    function doQVEStake(uint256 qveStakeAmount) public NoReEntrancy returns(bool){
        //require(_makeQVEescrowedAndVesting(msg.sender, qveStakeAmount.mul(1e18).mul(ESCROWRATIO).div(100)), "Error in Make QVE escrowed and Vesting");
        //require(qveStaking.stake(msg.sender, qveStakeAmount.mul(100 - ESCROWRATIO).div(100)), "Error in QVE staking");
        require(qveStaking.stake(msg.sender, qveStakeAmount), "Error in QVE staking");
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
    function swapETHtoQVE_(uint256 tokenAmount) external payable returns(bool){
        qveSwap.swapETHtoQVE(tokenAmount, msg.sender);
        return true;
    }

    function swapQVEtoETH_(uint256 tokenAmount) external returns(bool){
        qveSwap.swapQVEtoETH(tokenAmount, msg.sender);
        return true;
    }
    

    // [------ Refund ------] // 
    function refundInvestment() external payable returns(bool){
        return true;
    }

    function _sendIntoContract(uint256 tokenId) external returns(bool){
        qvenft.safeTransferFrom(msg.sender, address(this), tokenId);
        return true;
    }
}