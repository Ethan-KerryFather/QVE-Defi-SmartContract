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
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract QVEcore is Security, Ownable, IERC721Receiver {
    using SafeMath for uint256;
    using Counters for Counters.Counter;
    using Strings for *;

    Counters.Counter private InputedMarginCount;
    Counters.Counter private strategyCount;

    uint256 constant private SETTLE_PERIOD = 7 days;

    // [------ Events ------] //
    event Received(address indexed sender, uint256 amount);
    event NFTDeposited(address indexed sender, uint256 tokenId);
    event NFTWithdrawn(address indexed receiver, uint256 tokenId);

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    // [------ Variables, Struct -------] //
    uint8 private constant ESCROWRATIO = 10;
    QVEtoken public qvetoken;
    QVEnft public qvenft;
    QVEstaking public qveStaking;
    QVEswap public qveSwap;

    struct ETHstakingChunk {
        uint256 balance;
        uint256 at;
    }

    struct liquidityChunk {
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

    mapping(address => NFTs) nftVault;
    mapping(uint256 => uint256) marginForNFT;
    mapping(uint256 => address) tokenIdForAddress;

    struct ContractNFTFragment {
        uint256 amount;
        uint256 at;
    }

    mapping(uint256 => mapping(address => ContractNFTFragment)) ContractOwnedNFTs;

    // [------ QVE Liquidity pool / ETH staking pool ------] //
    liquidityChunk public QVEliquidityPool;

    // [------ Strategies ------] //
    struct StrategyData {
        address payable botAddress;
        uint256 initialBalance;
        uint256 currentBalance;
    }

    mapping(uint256 => StrategyData) public strategies;
    
    mapping (uint256 => uint256) public tokenIdToStrategyId; // nfttokenId - strategyId

    function setStrategy(uint256 strategyId, address payable botAddress) external onlyOwner {
        require(botAddress != address(0), "Warn : Invalid bot address");
        strategies[strategyId] = StrategyData(botAddress, 0, 0);
    }

    function updateStrategyBalance(uint256 strategyId, uint256 newBalance) external onlyOwner {
        require(strategies[strategyId].botAddress != address(0), "Warn : Strategy does not exist");
        if (strategies[strategyId].initialBalance == 0) {
            strategies[strategyId].initialBalance = newBalance;
        }
        strategies[strategyId].currentBalance = newBalance;
    }

    function getStrategyProfitPercentage(uint256 strategyId) public view returns (uint256) {
        StrategyData memory strategy = strategies[strategyId];
        if (strategy.initialBalance == 0) return 0;
        return (strategy.currentBalance * 100) / strategy.initialBalance;
    }

    function sendToBotAddress_(uint256 strategy, uint256 sendAmount) internal returns(bool) {
        require(strategies[strategy].botAddress != address(0), "Warn : Invalid bot address");
        require(address(this).balance >= sendAmount, "Warn : Insufficient balance in contract");
        strategies[strategy].botAddress.transfer(sendAmount);
        return true;
    }

    // [------ individual strategy ------] // 
    struct IndividualInvestment {
        uint256 investedAmount; // 투자한 금액
        uint256 strategyInitialBalance; // 투자 시점의 전략 잔액
        uint256 at; // 투자 시점
    }

    mapping(address => IndividualInvestment[]) public individualInvestments;

    function getIndividualProfit(address investor, uint256 investmentIndex, uint256 strategyId) public view returns (uint256) {
        IndividualInvestment memory investment = individualInvestments[investor][investmentIndex];
        uint256 currentStrategyBalance = strategies[strategyId].currentBalance;
        uint256 profit = currentStrategyBalance - investment.strategyInitialBalance;
        return (investment.investedAmount * profit) / investment.strategyInitialBalance;
    }


    // [------ Put margin(ETH) ------] //
    struct marginDetail {
        uint256 marginAmount;
        uint256 at;
        uint256 tokenId;
    }

    struct userMarginData {
        marginDetail[] marginDetails;
        uint256[] holdNFT;
    }

    mapping(address => userMarginData) EthMarginVault;

    constructor(
        QVEtoken _qveTokenAddress,
        QVEnft _qvenft,
        QVEstaking _qveStaking,
        QVEswap _qveSwap
    ) {
        qvetoken = _qveTokenAddress;
        qvenft = _qvenft;
        qveStaking = _qveStaking;
        qveSwap = _qveSwap;
    }

    function getEthBalance(address _address) external view returns(uint) {
        return _address.balance;
    }

    function receiveAsset(bool lockup, uint256 sendAmount, uint256 strategyId) public payable returns(bool) {
        require(msg.value == sendAmount, "Warn : Mismatched sent amount");

        // Update strategy balance
        if (strategies[strategyId].initialBalance == 0) {
            strategies[strategyId].initialBalance = msg.value;
        }
        strategies[strategyId].currentBalance += msg.value;


        // 개별 투자 기록 업데이트
        IndividualInvestment memory newInvestment = IndividualInvestment({
        investedAmount: msg.value,
        strategyInitialBalance: strategies[strategyId].currentBalance,
        at: block.timestamp
        });

        individualInvestments[msg.sender].push(newInvestment);

        // Send ETH to strategy address
        sendToBotAddress_(strategyId, msg.value);

        string memory assetString = string(abi.encodePacked("[Guaranteed Investment Margin]--:", msg.value.toString(), "WEI"));
        qvenft.setMetadata("Staking Guarantee Card", assetString, "https://ipfs.io/ipfs/QmQUumq8iYcA9X8uoafM2YU8LeyyMKzUN2HF5FGp6NpXEV?filename=Group%204584.jpg");

        investmentEth(msg.value, lockup, strategyId);

        

        return true;
    }

    function investmentEth(uint256 investAmount, bool lockup, uint256 strategyId) internal returns(bool) {
        uint256 tokenId = _issueGuaranteeNFT(msg.sender, investAmount, lockup);
        tokenIdToStrategyId[tokenId] = strategyId;

        require(_addUserMarginVault(msg.sender, investAmount, tokenId), "Warn : Vault update failed");
        InputedMarginCount.increment();

        return true;
    }

    function shortenLockup(uint256 qveAmount, uint256 tokenId) external returns(bool) {
        require(qvenft.shortenLockup(qveAmount, address(this), tokenId), "Warn : Lockup shorten failed");
        _addLiquidity(qveAmount);
        return true;
    }

    function burnInvestmentGuarantee(uint256 tokenId) public returns(bool) {
        require(tokenIdForAddress[tokenId] == msg.sender, "Warn : You are not the NFT owner");
        require(qvenft.ownerOf(tokenId) == msg.sender, "Warn : You are not the NFT owner");
        qvenft.burnNFT(tokenId);
        require(qvetoken.normal_mint(msg.sender, marginForNFT[tokenId].mul(1e18)), "Warn : Transfer failed");

        // Remove individual investment record
        _removeIndividualInvestmentRecord(msg.sender, tokenId);

        _removeMarginData(tokenId, msg.sender);
        return true;
    }

    function _removeIndividualInvestmentRecord(address investor, uint256 tokenId) internal {
        IndividualInvestment[] storage investments = individualInvestments[investor];
        uint256 indexToRemove = 0;
        bool found = false;

        for (uint256 i = 0; i < investments.length; i++) {
            if (investments[i].investedAmount == marginForNFT[tokenId]) {
                indexToRemove = i;
                found = true;
                break;
            }
        }

        if (found) {
        investments[indexToRemove] = investments[investments.length - 1];
        investments.pop();
        }
    }

    // [------ Getters ------ ] //
    function getInputedMarginCount() external view returns(uint256) {
        return InputedMarginCount.current();
    }

    function getNFTbalance_() external view returns(uint) {
        return qvenft.balanceOf(msg.sender);
    }

    function getNfts_() external view returns(NFTFragment[] memory) {
        return nftVault[msg.sender].fragment;
    }

    function getQVELiquidityAmount_() external view returns(uint) {
        return QVEliquidityPool.balance;
    }

    function getEthMarginVault_() external view returns(userMarginData memory) {
        return EthMarginVault[msg.sender];
    }

    function getmarginForNFT_(uint256 tokenId) public view returns(uint256) {
        return marginForNFT[tokenId];
    }

    function getstrategyAddress(uint256 strategy) public view returns(address) {
        return strategies[strategy].botAddress;
    }

    // [------ internal Functions ------] //
    function _botAddress() internal pure returns(address payable) {
        return payable(address(uint160(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2)));
    }

    function _sendQVEFromLiquidity(address _to, uint256 sendAmount) internal returns(bool) {
        require(qvetoken.normal_transfer(address(this), _to, sendAmount.mul(1e18)), "Warn : Transfer failed");
        QVEliquidityPool.balance -= sendAmount;
        QVEliquidityPool.at = block.timestamp;

        return true;
    }

    function _addUserMarginVault(address userAddress, uint amount, uint256 tokenId) internal returns(bool) {
        marginDetail[] storage marginVault = EthMarginVault[userAddress].marginDetails;
        marginVault.push(marginDetail({marginAmount : amount, at : block.timestamp, tokenId : tokenId}));
        EthMarginVault[userAddress].holdNFT.push(tokenId);
        marginForNFT[tokenId] = amount;
        return true;
    }

    function _addLiquidity(uint256 amount) internal returns(bool) {
        QVEliquidityPool.balance += amount;
        QVEliquidityPool.at = block.timestamp;
        return true;
    }

    function _subLiquidity(uint256 amount) internal returns(bool) {
        QVEliquidityPool.balance -= amount;
        QVEliquidityPool.at = block.timestamp;
        return true;
    }

    function _issueGuaranteeNFT(address sender, uint256 stakeAmount, bool lockup) internal NoReEntrancy returns(uint256) {
        uint256 item_id = qvenft.mintStakingGuarantee(sender, lockup);
        nftVault[sender].fragment.push(NFTFragment(item_id, block.timestamp));
        _addUserMarginVault(msg.sender, stakeAmount, item_id);
        tokenIdForAddress[item_id] = sender;
        return item_id;
    }



    function _removeMarginData(uint256 tokenId, address userAddress) internal {
        // Update EthMarginVault
        uint256 indexToRemove = 0;
        bool found = false;
        for (uint256 i = 0; i < EthMarginVault[userAddress].marginDetails.length; i++) {
            if (EthMarginVault[userAddress].marginDetails[i].tokenId == tokenId) {
                indexToRemove = i;
                found = true;
                break;
            }
        }
        if (found) {
            EthMarginVault[userAddress].marginDetails[indexToRemove] = EthMarginVault[userAddress].marginDetails[EthMarginVault[userAddress].marginDetails.length - 1];
            EthMarginVault[userAddress].marginDetails.pop();
        }

        // Update nftVault
        for (uint256 i = 0; i < nftVault[userAddress].fragment.length; i++) {
            if (nftVault[userAddress].fragment[i].tokenId == tokenId) {
                nftVault[userAddress].fragment[i] = nftVault[userAddress].fragment[nftVault[userAddress].fragment.length - 1];
                nftVault[userAddress].fragment.pop();
                break;
            }
        }

        // Update marginForNFT and tokenIdForAddress
        delete marginForNFT[tokenId];
        delete tokenIdForAddress[tokenId];
    }

    // [------ QVE Staking ------] //
    function doQVEStake(uint256 qveStakeAmount) public NoReEntrancy returns(bool) {
        require(qveStaking.stake(msg.sender, qveStakeAmount), "Warn : QVE staking failed");
        return true;
    }

    // [------ QVE Swap ------] //
    function swapETHtoQVE_(uint256 tokenAmount) external payable returns(bool) {
        qveSwap.swapETHtoQVE{value: msg.value}(tokenAmount, msg.sender);
        return true;
    }

    function swapQVEtoETH_(uint256 tokenAmount) external returns(bool) {
        qveSwap.swapQVEtoETH(tokenAmount, msg.sender);
        return true;
    }

    // [------ Refund Strategies------] //

    function onERC721Received(address, address nftOwner, uint256 tokenId, bytes calldata) external override returns (bytes4) {
        ContractOwnedNFTs[tokenId][nftOwner] = ContractNFTFragment({amount: marginForNFT[tokenId], at: block.timestamp});
        return this.onERC721Received.selector;
    }


    function withdrawInvestmentAndProfit(uint256 tokenId) external returns(bool) {
        // 1. NFT의 소유자 확인
        require(tokenIdForAddress[tokenId] == msg.sender, "Warn : You are not the NFT owner");
        require(qvenft.ownerOf(tokenId) == msg.sender, "Warn : You are not the NFT owner");

        // 2. 해당 tokenId에 대한 strategyId 가져오기
        uint256 strategyId = tokenIdToStrategyId[tokenId];

        // 3. 투자자의 원금 및 수익금 계산
        uint256 investedAmount = marginForNFT[tokenId];
        uint256 profit = getIndividualProfit(msg.sender, tokenId, strategyId); 

        // 4. 봇에게서 사용자에게 원금 및 수익금 전송
        // 이 부분이 골때림 어카지
        

        // 5. 전략의 현재 잔액 업데이트
        strategies[strategyId].currentBalance -= (investedAmount + profit);

        // 6. 투자자의 기록 업데이트
        _removeIndividualInvestmentRecord(msg.sender, tokenId);

        return true;
    }   

    function sendNftToContract(uint256 tokenId) external view returns(bool){
         // 1. NFT의 소유자 확인
        require(tokenIdForAddress[tokenId] == msg.sender, "Warn : You are not the NFT owner");
        require(qvenft.ownerOf(tokenId) == msg.sender, "Warn : You are not the NFT owner");

        // 2. 해당 tokenId에 대한 strategyId 가져오기
        uint256 strategyId = tokenIdToStrategyId[tokenId];

        // 3. 투자자의 원금 및 수익금 계산
        uint256 investedAmount = marginForNFT[tokenId];
        uint256 profit = getIndividualProfit(msg.sender, tokenId, strategyId); 
        return true;
    }

    function sendBotToContract(uint256 sendAmount, uint256 strategyId) external payable returns(bool){
        require(msg.value == sendAmount, "Warn : Send amount is different with msg.value");
        require(msg.sender == getstrategyAddress(strategyId), "Warn : Send trying address is not the strategy Address");
        return true;
    }


}

  

    // [------ 개발되어있지만 사용이 확정되지 않은 기능들 ------] //

    // function _makeQVEescrowedAndVesting(address sender,uint256 QVEamount) internal returns(bool){
    //     require(qveEscrow.makeQVEescrow(sender, QVEamount.mul(1e18)), WARNING_ESCROW);
    //     require(qveVesting.addVesting(QVEamount.mul(1e18), sender), WARNING_VESTING);
    //     return true;
    // }

