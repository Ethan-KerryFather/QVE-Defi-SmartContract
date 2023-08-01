// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/TokenTimelock.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./tokens/QVEtoken.sol"; 
import "./util/Security.sol";

contract QVEvesting is Ownable, Security{
    using SafeMath for uint256;
    using Counters for Counters.Counter;
    Counters.Counter private VestingCounter;
    QVEtoken qveToken;

    // [------ Warn messages ------] //
    string private constant INSUFFICIENT_BALANCE = "Insufficient balance";
    string private constant INVALID_VESTING_ID = "Invalid vesting id";
    string private constant VESTING_ALREADY_RELEASED = "Vesting already released";
    string private constant INVALID_BENEFICIARY = "Invalid beneficiary address";
    string private constant NOT_VESTED = "Tokens have not vested yet";

    // [------ Vesting ------] //
    struct Vesting{
        uint256 releaseTime;
        uint256 amount;
        address beneficiary;
        bool released;
    }

    mapping(uint256 => Vesting) public vestings;
    mapping(address => uint256[]) public ownedVestings;


    // [------ Events ------] //
    event TokenVestingReleased(uint256 indexed vesting, address indexed beneficiary, uint256 amount);
    event TokenVestingAdded(uint256 indexed vesting, address indexed beneficiary, uint256 amount);
    event TokenVestingRemoved(uint256 indexed vesting, address indexed beneficiary, uint256 amount);


    // [------ Variables ------] //    
    uint256 private tokensToVest = 0;
    

    // [------ Modifiers ------] //
    modifier HaveVesting(address sender){
        require(ownedVestings[sender].length > 0, NOT_VESTED);
        _;
    }

    // [------ Init ------] //
    constructor(QVEtoken _qveToken) {
        require(address(_qveToken) != address(0), INVALID_BENEFICIARY);
        qveToken = _qveToken;
    }
    function token() public view returns(ERC20){
        return qveToken;
    }

    // [------ external, public Functions ------] // 
    function getBeneficiary(uint256 _vestingId) external view returns(address){
        return vestings[_vestingId].beneficiary;
    }

    function getReleaseTime(uint256 _vestingId) external view returns(uint256){
        return vestings[_vestingId].releaseTime;
    }

    function getVestingAmount(uint256 _vestingId) external  view returns(uint256){
        return vestings[_vestingId].amount;
    }

    function addVesting(address _beneficiary, uint256 _releaseTime, uint256 _amount, address sender) public onlyOwner NoReEntrancy{
        require( _beneficiary != address(0), INVALID_BENEFICIARY);
        tokensToVest = tokensToVest.add(_amount);

        vestings[VestingCounter.current()] = Vesting({
            beneficiary : _beneficiary,
            releaseTime : _releaseTime,
            amount : _amount,
            released : false
        });

        ownedVestings[sender].push(VestingCounter.current());

        emit  TokenVestingReleased(VestingCounter.current(), _beneficiary, _amount);

        VestingCounter.increment();
    }



    function releaseAll(uint256 _vestingId, address sender) public NoReEntrancy{

        Vesting storage vesting = vestings[_vestingId];
        require(vesting.beneficiary != address(0x0), INVALID_VESTING_ID);
        require(!vesting.released , VESTING_ALREADY_RELEASED);
        require(block.timestamp >= vesting.releaseTime, NOT_VESTED);
        require(qveToken.balanceOf(address(this)) >= vesting.amount, INSUFFICIENT_BALANCE);
        
        tokensToVest = tokensToVest.sub(vesting.amount);

        qveToken.normal_transfer(address(this), vesting.beneficiary, vesting.amount);
        // 새롭게 민팅해서 추가분 주기 (claimForQVE)
        removeVesting(_vestingId, sender, true);

        emit TokenVestingReleased(_vestingId, vesting.beneficiary, vesting.amount);
    }

    // function retrieveExcessTokens(uint256 _amount) public onlyOwner {
    //     require(_amount <= qveToken.balanceOf(address(this)).sub(tokensToVest), INSUFFICIENT_BALANCE);
    //     qveToken.normal_transfer(address(this), owner(), _amount);
    // }

    function claimForQVE() public {
        
    }

    // [------ internal Functions -------] //
    function getVestingId(address sender) internal view HaveVesting(sender) returns(uint256[] memory){
        return ownedVestings[sender];
    }

    function removeVesting(uint _vestingId, address sender, bool isReleased) internal HaveVesting(sender) onlyOwner returns(bool){
        uint256[] storage vestingIds = ownedVestings[sender];
        
        Vesting storage vesting = vestings[_vestingId];
        require(vesting.beneficiary != address(0), INVALID_BENEFICIARY);
        require(!vesting.released, VESTING_ALREADY_RELEASED);

        tokensToVest = tokensToVest.sub(vesting.amount);
        
        for(uint i = 0; i < vestingIds.length ; i++){
            if( vestingIds[i] == _vestingId ){
                vestingIds[i] = vestingIds[vestingIds.length-1];
                vestingIds.pop();
                vesting.released = isReleased;
                break;
            }
        }

        emit TokenVestingRemoved(_vestingId, vesting.beneficiary, vesting.amount);
        return true;
    }
   

}