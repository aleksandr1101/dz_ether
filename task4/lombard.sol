// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.2 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract lombard is Ownable {

    uint public immutable payments_period;
    uint public immutable inverted_interest_rate;
    uint public immutable collateral_percentage;

    mapping (address => address) private token_price_addr;

    address[] public tokens_for_loan;
    address[] public tokens_for_stake;

    mapping (address => mapping (address => uint)) public loaning_dates;
    mapping (address => mapping (address => uint)) public staking_dates;

    mapping (address => mapping (address => uint)) public loaning_balances;
    mapping (address => mapping (address => uint)) public staking_balances;

    event TokenStaked(address indexed to, address token, uint amount);
    event TokenLoaned(address indexed to, address token, uint amount);
    event TokenWithdrawed(address indexed to, address token, uint amount);
    event TokenReturned(address indexed to, address token, uint amount);


    function tokenUsedForLoan(address token) public view returns(bool) {
        for (uint i = 0; i < tokens_for_loan.length; i++) {
            if (token == tokens_for_loan[i]) {
                return true;
            }
        }
        return false;
    }

    function tokenUsedForStake(address token) public view returns(bool) {
        for (uint i = 0; i < tokens_for_stake.length; i++) {
            if (token == tokens_for_stake[i]) {
                return true;
            }
        }
        return false;
    }

    function getTokenPrice(address token_addr) private view returns(uint) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(token_price_addr[token_addr]);
        (, int256 answer, , , ) = priceFeed.latestRoundData();
        return uint(answer);
    }

    constructor(
        uint _payments_period, 
        uint _inverted_interest_rate, 
        uint _collateral_percentage
    ) 
        Ownable(msg.sender) 
    {
        payments_period = _payments_period;
        inverted_interest_rate = _inverted_interest_rate;
        collateral_percentage = _collateral_percentage;
    }

    function add_token_for_loans(address token) external onlyOwner() {
        require(!tokenUsedForLoan(token), "Token already used for loans");
        tokens_for_loan.push(token);
    }

    function add_token_for_stake(address token) external onlyOwner() {
        require(!tokenUsedForStake(token), "Token already used for loans");
        tokens_for_stake.push(token);
    }


    function stake(address token_addr, uint amount) external {
        recalculateStakedTokenBalance(token_addr);(token_addr);
        
        IERC20 token = IERC20(token_addr);
        require(token.allowance(msg.sender, address(this)) >= amount);
        safeTransferFrom(token, msg.sender, address(this), amount);
        
        staking_balances[msg.sender][token_addr] += amount;
        staking_dates[msg.sender][token_addr] = block.timestamp;

        emit TokenStaked(msg.sender, token_addr, amount);
    }

    function depositLoanedToken(address token_addr, uint amount) external {
        recalculateLoanedTokenBalance(token_addr);

        IERC20 token = IERC20(token_addr);
        require(token.allowance(msg.sender, address(this)) >= amount);
        safeTransferFrom(token, msg.sender, address(this), amount);

        uint balance = loaning_balances[msg.sender][token_addr];
        loaning_balances[msg.sender][token_addr] -= balance >= amount ? amount : balance;
        loaning_dates[msg.sender][token_addr] = block.timestamp;

        emit TokenReturned(msg.sender, token_addr, amount);
    }

    modifier zeroDebt() {
        uint debt = 0;
        for (uint i = 0; i < tokens_for_loan.length; i++) {
            debt += loaning_balances[msg.sender][tokens_for_loan[i]];
        }
        require(debt == 0, "Withdraw is not allowed, you have a debt");
        _;
    }

    function getLoanedTokenBalance(address token_addr) public view returns(uint) {
        uint amount = loaning_balances[msg.sender][token_addr];
        if (amount == 0) {
            return 0;
        }
        uint payments_passed = (block.timestamp - loaning_dates[msg.sender][token_addr]) / payments_period;
        for (uint i = 0; i < payments_passed; i++) {
            amount += amount / inverted_interest_rate;
        }
        return amount;
    }

    function recalculateLoanedTokenBalance(address token_addr) private returns(uint) {
        loaning_dates[msg.sender][token_addr] = block.timestamp;
        return loaning_balances[msg.sender][token_addr] = getLoanedTokenBalance(token_addr);
    }
    

    function getStakedTokenBalance(address token_addr) public view returns(uint) {
        uint amount = staking_balances[msg.sender][token_addr];
        if (amount == 0) {
            return 0;
        }
        uint payments_passed = (block.timestamp - staking_dates[msg.sender][token_addr]) / payments_period;
        for (uint i = 0; i < payments_passed; i++) {
            amount += amount / inverted_interest_rate;
        }
        return amount;
    }

    function recalculateStakedTokenBalance(address token_addr) private returns(uint){
        staking_dates[msg.sender][token_addr] = block.timestamp;
        return staking_balances[msg.sender][token_addr] = getStakedTokenBalance(token_addr);
    }

    function withdraw(address token_addr, uint amount) external zeroDebt {
        recalculateStakedTokenBalance(token_addr);

        IERC20 token = IERC20(token_addr);
        require(token.balanceOf(address(this)) >= amount);
        require(staking_balances[msg.sender][token_addr] >= amount);

        staking_balances[msg.sender][token_addr] -= amount;
        staking_dates[msg.sender][token_addr] = block.timestamp;

        safeTokenTransfer(token, msg.sender, amount);

        emit TokenWithdrawed(msg.sender, token_addr, amount);
    }

    function calculateTotalStaked() private returns(uint) {
        uint cnt = 0;
        for (uint i = 0; i < tokens_for_stake.length; i++) {
            uint token_amount = recalculateStakedTokenBalance(tokens_for_stake[i]);
            cnt += token_amount * getTokenPrice(tokens_for_stake[i]);
        }
        return cnt;
    }

    function calculateTotalLoaned() private returns(uint) {
        uint cnt = 0;
        for (uint i = 0; i < tokens_for_loan.length; i++) {
            uint token_amount = recalculateLoanedTokenBalance(tokens_for_loan[i]);
            cnt += token_amount * getTokenPrice(tokens_for_loan[i]);
        }
        return cnt;
    }

    function calculateMaxTokenAmountForLoan(address token_addr) public returns(uint) {
        uint token_price = getTokenPrice(token_addr);
        uint total_staked = calculateTotalStaked() * collateral_percentage / 100;
        uint total_loaned = calculateTotalLoaned();

        uint can_loan = total_staked > total_loaned ? total_staked : 0;
        return can_loan / token_price;
    }

    function loanToken(address token_addr, uint amount) external {
        require(calculateMaxTokenAmountForLoan(token_addr) >= amount);

        IERC20 token = IERC20(token_addr);
        require(token.balanceOf(address(this)) >= amount);

        staking_balances[msg.sender][token_addr] += amount;
        staking_dates[msg.sender][token_addr] = block.timestamp;

        safeTokenTransfer(token, msg.sender, amount);

        emit TokenLoaned(msg.sender, token_addr, amount);
    }

    function safeTokenTransfer(IERC20 token, address to, uint amount) private {
        bool sent = token.transfer(to, amount);
        require(sent, "Token transfer failed");
    }

    function safeTransferFrom(IERC20 token, address sender, address recipient, uint amount) private {
        bool sent = token.transferFrom(sender, recipient, amount);
        require(sent, "Token transfer failed");
    }
    
}
