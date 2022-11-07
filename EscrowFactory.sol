// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import './Escrow.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract EscrowFactory {
    uint8 feePercent = 1;
    uint256 public counter;
    address[] escrows;
    address[] processedTrustedHandlers;
    mapping(address => address[]) public myEscrows;
    mapping(address => bool) public areTrustedHandlers;
    mapping(address => bool) public areTokenTrusted;
    address feeAddress = address(this);
    event Created(address);

    constructor(address _backup, address[] memory trustedTokens) {
        processedTrustedHandlers.push(msg.sender);
        areTrustedHandlers[msg.sender] = true;
        processedTrustedHandlers.push(_backup);
        areTrustedHandlers[_backup] = true;
        areTokenTrusted[address(0)] = true; // for native currencies
        switchActiveTrustedTokens(trustedTokens, true);
    }

    function createEscrow(
        address payable seller,
        address tokenAddress,
        uint256 amount,
        bytes32 title,
        uint256 _standartDuration
    ) external payable returns (address) {
        require(msg.sender != seller, '___INVALID_SAME___');
        require(seller != address(0), '___NON_EXIST_ADDRESS___');
        require(areTokenTrusted[tokenAddress], '___NOT_TRUSTED___');

        IERC20 token = IERC20(tokenAddress);

        if (tokenAddress != address(0)) {
            require(token.balanceOf(msg.sender) >= amount, '___TOKEN_UNAVAILABLE___');
        } else {
            require(msg.value == amount, '___DIFFER_AMOUNT_VAL___');
        }

        Escrow escrow = new Escrow(
            payable(feeAddress),
            tokenAddress,
            _standartDuration,
            amount,
            title,
            payable(msg.sender),
            seller,
            feePercent,
            getTrustedHandlers()
        );

        if (tokenAddress == address(0)) {
            payable(address(escrow)).transfer(msg.value);
        } else {
            token.transferFrom(msg.sender, address(escrow), amount);
        }

        escrows.push(address(escrow));
        myEscrows[msg.sender].push(address(escrow));
        myEscrows[seller].push(address(escrow));
        emit Created(address(escrow));
        return address(escrow);
    }

    function getTrustedHandlers() public view returns (address[] memory) {
        address[] memory trustedHandlers = new address[](processedTrustedHandlers.length);
        uint j = 0;
        for (uint i = 0; i < processedTrustedHandlers.length; i++) {
            if (areTrustedHandlers[processedTrustedHandlers[i]]) {
                trustedHandlers[j] = processedTrustedHandlers[i];
                j++;
            }
        }
        return trustedHandlers;
    }

    function withdraw(address payable to, address tokenAddress, uint256 amount) external payable trusted {   
        if (tokenAddress == address(0)) {
            to.transfer(amount);
        } else {
            IERC20(tokenAddress).transfer(to, amount);
        }
    }

    function switchActiveTrustedHandlers(address[] memory _handlers, bool approve) public trusted {
        for (uint256 i = 0; i < _handlers.length; i++) {
            processedTrustedHandlers.push(_handlers[i]);
            areTrustedHandlers[_handlers[i]] = approve;
        }
    }

    function switchActiveTrustedTokens(address[] memory _tokens, bool approve) public trusted {
        for (uint256 i = 0; i < _tokens.length; i++) {
            areTokenTrusted[_tokens[i]] = approve;
        }
    }

    function checkTrusted(address _addr) public view trusted returns (bool) {
        return areTrustedHandlers[_addr];
    }

    function checkTrustedToken(address _token) public view trusted returns (bool) {
        return areTokenTrusted[_token];
    }

    function getFee() public view trusted returns (uint8) {
        return feePercent;
    }

    function updateFeePercent(uint8 _feePercent) external trusted {
        require(_feePercent > 0 || _feePercent < 100, '___INVALID_FEE_PERCENT___');
        feePercent = _feePercent;
    }

    function updateFeeAddress(address _feeAddress) external trusted {
        feeAddress = _feeAddress;
    }

    fallback() external payable {}
    receive() external payable {}

    function balanceOf(address tokenAddress) public view returns (uint256) {
        if (tokenAddress == address(0)) {
            return address(this).balance;
        }
        return IERC20(tokenAddress).balanceOf(address(this));
    }

    function getMyEscrows() public view returns (address[] memory escrowAddresses) {
        return myEscrows[msg.sender];
    }

    // recent to oldest
    function getEscrowDetailsPaging(uint256 offset) external view trusted returns (address[] memory escrowAddresses, uint256 total) {
        uint256 limit = 10;
        if (limit > escrows.length - offset) {
            limit = escrows.length - offset;
        }

        address[] memory values = new address[](limit);
        for (uint256 i = 0; i < limit; i++) {
            values[i] = escrows[escrows.length - 1 - offset - i];
        }
        return (values, escrows.length);
    }

    modifier trusted() {
        require(areTrustedHandlers[msg.sender], '___NOT_TRUSTED___');
        _;
    }
}
