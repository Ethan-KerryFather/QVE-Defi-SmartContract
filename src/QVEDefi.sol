// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./QVEtoken.sol";
import "./QVEnft.sol";

contract QVEDefi is Ownable{
    using SafeMath for uint;
    using Counters for Counters.Counter;
    Counters.Counter private stakeCount;

    QVEtoken public qvetoken;
    QVEnft public qvenft;

    struct ETHstakingChunk{
        // wei 단위
        uint256 balance;
        uint256 at;
    }

    struct QVEliquidityChunk{
        // ether 단위
        uint256 balance;
        uint256 at;
    }

    // 큐브 유동성 풀           ether단위로 관리
    QVEliquidityChunk public QVEliquidityPool;
    // 이더리움 스테이킹 풀       wei단위로 관리
    mapping (address => ETHstakingChunk) ETHstakingVault;

    constructor(QVEtoken _qveTokenAddress, QVEnft _qvenft) {
        qvetoken = _qveTokenAddress;
        qvenft = _qvenft;
        qvetoken.normal_transfer(msg.sender, address(this), qvetoken.totalSupply() / 2 );
        QVEliquidityPool.balance += qvetoken.balanceOf(address(this)) / 10 ** 18;
    }

    // 프론트에서 string으로 소수점까지 받은 다음에 컨트랙트 호출 할때는 wei단위로 바꾸어줘야함
    function receiveAsset(uint256 assetAmount) public payable returns(bool){
        {/*
        먼저 사용자가 이더리움을 전송하면
        require(msg.value == assetAmount * 10 ** 18, "Sent ether is not match with the specified amount");
        이더리움을 양을 체크하고
        address payable _to = _botAddress();
        _to.transfer(assetAmount * 10 ** 18);
        해당하는 양만큼 봇주소로 보냄
        */}
        
        stakeEth(assetAmount);
        return true;
    }

    function stakeEth(uint256 stakeAmount) internal returns(bool){
        qvenft.mintStakingGuarantee(msg.sender);
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
        // nft burn logic
        //require(QVEliquidityPool.balance >= stakeAmount, "QVE Liquidity pool don't have enough balance");
        require(_sendQVEFromLiquidity(msg.sender, ETHstakingVault[msg.sender].balance), "Burn QVE transfer error");
        return true;
    }

    function getStakeCount() external view returns(uint256){
        return stakeCount.current();
    } 

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

}