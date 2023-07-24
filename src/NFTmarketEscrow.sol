// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ERC20 토큰 인터페이스를 가져옵니다.
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Escrow {
    // 잠금을 해제할 수 있는 주소를 저장합니다.
    address public beneficiary;
    // 잠금을 해제할 수 있는 시간을 저장합니다.
    uint256 public releaseTime;
    // 잠금에 사용되는 토큰을 저장합니다.
    IERC20 public token;

    constructor(
        IERC20 _token,
        address _beneficiary,
        uint256 _releaseTime
    ) {
        // 입력받은 토큰, 수혜자 주소, 해제 시간을 저장합니다.
        token = _token;
        beneficiary = _beneficiary;
        releaseTime = _releaseTime;
    }

    function release() public {
        // 현재 시간이 해제 시간보다 이전이라면 잠금 해제를 거부합니다.
        require(block.timestamp >= releaseTime, "Current time is before release time");

        // 잠금 해제할 토큰의 수를 가져옵니다.
        uint256 amount = token.balanceOf(address(this));
        require(amount > 0, "No tokens to release");

        // 토큰을 수혜자에게 전송합니다.
        token.transfer(beneficiary, amount);
    }
}
