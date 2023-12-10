// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.2 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Crowdsale is ERC20, Ownable {
    uint public immutable crowdsale_deadline;
    uint public constant max_user_deposit = 0.1 ether;
    uint8 public constant dev_team_reward_percentage = 10;
    uint public constant token_exchange_rate = 10 ** 4;

    bool private completed; 

    modifier crowdsale_running() {
        require(block.timestamp <= crowdsale_deadline);
        _;
    }

    modifier acceptable_deposit() {
        require(msg.value > 0);
        require(balanceOf(msg.sender) / token_exchange_rate + msg.value <= max_user_deposit);
        _;
    }

    modifier is_able_to_complete() {
        require(block.timestamp > crowdsale_deadline);
        require(!completed);
        _;
    }
    
    constructor(address developers_team, string memory name, string memory symbol) 
        ERC20(name, symbol) 
        Ownable(developers_team) 
    {
        crowdsale_deadline = block.timestamp + 28 days;
    }

    function deposit() external payable crowdsale_running acceptable_deposit {
        _mint(msg.sender, msg.value * token_exchange_rate);
    }

    function complete_crowdsale() external is_able_to_complete {
        completed = true;
        _mint(owner(), totalSupply() * dev_team_reward_percentage * token_exchange_rate / 100);
    }

}
