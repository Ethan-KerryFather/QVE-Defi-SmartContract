/*
  
 ██████  ██████   ██████  ██   ██ ██████   ██████   ██████  ██   ██    ██████  ███████ ██    ██
██      ██    ██ ██    ██ ██  ██  ██   ██ ██    ██ ██    ██ ██  ██     ██   ██ ██      ██    ██
██      ██    ██ ██    ██ █████   ██████  ██    ██ ██    ██ █████      ██   ██ █████   ██    ██
██      ██    ██ ██    ██ ██  ██  ██   ██ ██    ██ ██    ██ ██  ██     ██   ██ ██       ██  ██
 ██████  ██████   ██████  ██   ██ ██████   ██████   ██████  ██   ██ ██ ██████  ███████   ████

Find any smart contract, and build your project faster: https://www.cookbook.dev
Twitter: https://twitter.com/cookbook_dev
Discord: https://discord.gg/WzsfPcfHrk

Find this contract on Cookbook: https://www.cookbook.dev/contracts/GMX-Reader/?utm=code
*/

//SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IPancakeFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}