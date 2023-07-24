// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ERC20 토큰 인터페이스를 가져옵니다.
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./QVEtoken.sol";


contract NFTescrow is Ownable{

    // [------ Variables, Addresses ------] //
    QVEtoken public qveToken;
    address private escrowCloser;
    uint256 public escrowOpentime;
    
    struct Raise{
        uint256 raisedAmount;
        uint256 at;
    }

    // [------ Mappings ------] //
    mapping (address => Raise ) public Raises;

    constructor( QVEtoken _qveToken ) {
        // 입력받은 토큰, 수혜자 주소, 해제 시간을 저장합니다.
        qveToken = _qveToken;
        escrowCloser = msg.sender;
        escrowOpentime = block.timestamp;
    }

    function closeEscrow() external onlyOwner returns(bool){

        return true;
    }

    // function release() public {
    //     // 현재 시간이 해제 시간보다 이전이라면 잠금 해제를 거부합니다.
    //     require(block.timestamp >= releaseTime, "Current time is before release time");

    //     // 잠금 해제할 토큰의 수를 가져옵니다.
    //     uint256 amount = token.balanceOf(address(this));
    //     require(amount > 0, "No tokens to release");

    //     // 토큰을 수혜자에게 전송합니다.
    //     token.transfer(beneficiary, amount);
    // }
}
