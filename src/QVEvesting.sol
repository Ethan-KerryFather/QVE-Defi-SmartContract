// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/TokenTimelock.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./tokens/QVEtoken.sol"; 

contract QVEvesting is Ownable{
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


    // [------ Events ------] //
    event TokenVesingReleased(uint256 indexed vesting, address indexed beneficiary, uint256 amount);
    event TokenVesingAdded(uint256 indexed vesting, address indexed beneficiary, uint256 amount);
    event TokenVesingRemoved(uint256 indexed vesting, address indexed beneficiary, uint256 amount);


    // [------ Variables ------] //    
    uint256 private tokensToVest = 0;
    

    // [------ Init ------] //
    constructor(QVEtoken _qveToken) {
        require(address(_qveToken) != address(0), "ERC20 Token address is address(0)");
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

    function addVesting(address _beneficiary, uint256 _releaseTime, uint256 _amount) public onlyOwner{
        require( _beneficiary != address(0), "QVE receiver is address(0)");
        tokensToVest = tokensToVest += _amount;
        vestings[VestingCounter.current()] = Vesting({
            beneficiary : _beneficiary,
            releaseTime : _releaseTime,
            amount : _amount,
            released : false
        });
        emit  TokenVesingReleased(VestingCounter.current(), _beneficiary, _amount);

        VestingCounter.increment();
    }

    function removeVesting(uint256 _vestingId) public onlyOwner{
        Vesting storage vesting = vestings[_vestingId];
        require(vesting.beneficiary != address(0), INVALID_BENEFICIARY);
        require(!vesting.released, VESTING_ALREADY_RELEASED);
        tokensToVest = tokensToVest.sub(vesting.amount);

        vesting.released = true;
        emit TokenVesingReleased(_vestingId, vesting.beneficiary, vesting.amount);
    }

    function release(uint256 _vestingId) public {
        Vesting storage vesting = vestings[_vestingId];
        require(vesting.beneficiary != address(0), INVALID_BENEFICIARY);
    }

    // [------ internal Functions -------] //

}