// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract Stacker is ERC721URIStorage{
        mapping (address => uint) public balances;

        uint public totalBalance;
        uint public deadline;
        uint public threshold;
        uint8 public completment_status; // 0: gathering in process, 1: gathering succeeded, 2: gathering failed 
        address payable private exampleExternalContractAddress;

        using Counters for Counters.Counter;
        Counters.Counter private tokenIds;

        uint public constant GOLD_STATUS_THRESHOLD = 1 ether;
        uint public constant SILVER_STATUS_THRESHOLD = 0.01 ether;
        uint public constant BRONZE_STATUS_THRESHOLD = 0.0001 ether;

        string private constant GOLD_NFT_URI = "gold";
        string private constant SILVER_NFT_URI = "silver";
        string private constant BRONZE_NFT_URI = "bronze";

        event Deposit(address indexed account, uint amount);
        event Withdraw(address indexed account, uint amount);
        event Completed(uint totalBalance);
        event NotCompleted(uint totalBalance);

        modifier notCompleted() {
            require(completment_status == 0);
            _;
        }

        modifier gatheringFailed() {
            require(completment_status == 2);
            _;
        }   

        modifier gatheringSucceded() {
            require(completment_status == 1);
            _;
        }   

        modifier gatheringFinished() {
            require(block.timestamp >= deadline);
            _;
        }

        modifier gatheringRunning() {
            require(block.timestamp < deadline);
            _;
        }

        modifier nonZeroValue() {
            require(msg.value > 0);
            _;
        }

        constructor(uint _deadline, uint _threshold, address payable _exampleExternalContractAddress) 
            ERC721("Stacker", "STACKER") 
        {
            deadline = _deadline;
            threshold = _threshold;
            exampleExternalContractAddress = _exampleExternalContractAddress;
        }

        function deposit() external payable gatheringRunning nonZeroValue {
            balances[msg.sender] += msg.value;
            totalBalance += msg.value;
            emit Deposit(msg.sender, msg.value);
        }

        function withdraw() external gatheringFailed {
            uint balance_amount = balances[msg.sender];
            require(balance_amount >= 0, "Staker: withdraw not allowed. balance amount is 0");

            balances[msg.sender] = 0;
            totalBalance -= balance_amount;

            payable(msg.sender).transfer(balance_amount);
            emit Withdraw(msg.sender, balance_amount);
        }

        function claimNFT() external gatheringSucceded {
            uint balance = balances[msg.sender];
            balances[msg.sender] = 0;
            if (balance < BRONZE_STATUS_THRESHOLD) {
                return;
            }
            tokenIds.increment();
            uint nft_id = tokenIds.current();

            if (balance >= GOLD_STATUS_THRESHOLD) {
                _safeMint(msg.sender, nft_id);
                _setTokenURI(nft_id, GOLD_NFT_URI);
            } else if (balance >= SILVER_STATUS_THRESHOLD) {
                _safeMint(msg.sender, nft_id);
                _setTokenURI(nft_id, SILVER_NFT_URI);
            } else {
                _safeMint(msg.sender, nft_id);
                _setTokenURI(nft_id, BRONZE_NFT_URI);
            }
        }

        function complete() external notCompleted gatheringFinished{
            if (totalBalance < threshold) {
                completment_status = 2;
                emit NotCompleted(totalBalance);
            } else {
                completment_status = 1;
                exampleExternalContractAddress.transfer(totalBalance);
                emit Completed(totalBalance);
            }
        }
}
