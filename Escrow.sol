// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract Escrow {
    enum EscrowStatus {
        Launched,
        Ongoing,
        RequestRevised,
        Delivered,
        Dispute,
        Cancelled,
        Complete
    }

    struct EscrowDetail {
        EscrowStatus status;
        bytes32 title;
        address tokenAddress;
        uint256 deadline;
        address payable buyer;
        address payable seller;
        uint256 requestRevisedDeadline;
        uint256 amount;
        address escrowAddress;
        uint8 feePercent;
    }

    EscrowDetail escrowDetail;
    address payable public addressToPayFee;
    uint256 rejectCount = 0;
    address public tokenAddress;
    mapping(address => bool) public areTrustedHandlers;

    constructor(
        address payable _addressToPayFee,
        address _tokenAddress,
        uint256 _duration,
        uint256 amount,
        bytes32 title,
        address payable buyer,
        address payable seller,
        uint8 _feePercent,
        address[] memory _handlers
    ) {
        require(_duration == 0 || _duration >= 86400, '___INVALID_DURATION___'); // SHOULD BE MIN 1 DAY
        require(_feePercent > 0 || _feePercent < 100, '___INVALID_FEE_PERCENT___');
        uint256 duration = 915151608; //29 years default
        if (_duration >= 0) {
            duration = _duration;
        }
        addressToPayFee = _addressToPayFee;
        tokenAddress = _tokenAddress;
        areTrustedHandlers[msg.sender] = true;
        addTrustedHandlers(_handlers);
        escrowDetail = EscrowDetail(
            EscrowStatus.Launched,
            title,
            _tokenAddress,
            duration + block.timestamp,
            buyer,
            seller,
            0,
            amount,
            address(this),
            _feePercent
        ); // solhint-disable-line not-rely-on-time
    }

    fallback() external payable {
        require(uint8(escrowDetail.status) < 5, '___NOT_ELIGIBLE___');
        require(msg.value > 0, '___INVALID_AMOUNT___');
    }

    receive() external payable {
        require(uint8(escrowDetail.status) < 5, '___NOT_ELIGIBLE___');
        require(msg.value > 0, '___INVALID_AMOUNT___');
    }

    function getBalance() public view returns (uint256) {
        if (tokenAddress == address(0)) {
            return address(this).balance;
        }
        return IERC20(tokenAddress).balanceOf(address(this));
    }

    function addTrustedHandlers(address[] memory _handlers) public trusted {
        for (uint256 i = 0; i < _handlers.length; i++) {
            areTrustedHandlers[_handlers[i]] = true;
        }
    }

    function sendAndStatusUpdate(address payable toFund, EscrowStatus status) private {
        uint256 fee = (escrowDetail.amount * escrowDetail.feePercent) / 100; // %1
        if (tokenAddress == address(0)) {
            addressToPayFee.transfer(fee); // %1
            toFund.transfer(escrowDetail.amount - fee);
        } else {
            IERC20 token = IERC20(tokenAddress);
            token.transfer(addressToPayFee, fee); // %1
            token.transfer(toFund, escrowDetail.amount - fee);
        }
        escrowDetail.status = status;
    }

    function sellerLaunchedApprove() public onlySeller {
        require(getBalance() > 0, '___NO_FUNDS___');
        require(escrowDetail.status == EscrowStatus.Launched, '___NOT_IN_LAUNCHED_STATUS___');
        escrowDetail.status = EscrowStatus.Ongoing;
    }

    function sellerDeliver() external onlySeller {
        require(escrowDetail.status == EscrowStatus.Ongoing, '___NOT_IN_ONGOING_STATUS___');
        escrowDetail.status = EscrowStatus.Delivered;
    }

    function buyerConfirmDelivery() external onlyBuyer {
        require(escrowDetail.status == EscrowStatus.Delivered, '___NOT_IN_DELIVERED_STATUS___');
        sendAndStatusUpdate(escrowDetail.seller, EscrowStatus.Complete);
    }

    function buyerDeliverReject(uint256 _deliverRejectDuration) external onlyBuyer {
        require(escrowDetail.status == EscrowStatus.Delivered, '___NOT_IN_DELIVERED_STATUS___');
        require(_deliverRejectDuration >= 86400, '___REJECT_MIN_DAY___'); //1 day min
        rejectCount++;
        EscrowStatus state = EscrowStatus.RequestRevised;
        if (rejectCount > 1) {
            state = EscrowStatus.Dispute;
            escrowDetail.status = state;
        } else {
            escrowDetail.status = state;
            escrowDetail.requestRevisedDeadline = _deliverRejectDuration + block.timestamp;
        }
    }

    function sellerRejectDeliverReject() external onlySeller {
        require(escrowDetail.status == EscrowStatus.RequestRevised, '___NOT_IN_REJECT_DELIVERY_STATUS___');
        escrowDetail.status = EscrowStatus.Dispute;
    }

    function sellerApproveDeliverReject() external onlySeller {
        require(escrowDetail.status == EscrowStatus.RequestRevised, '___NOT_IN_REJECT_DELIVERY_STATUS___');
        escrowDetail.status = EscrowStatus.Ongoing;
        escrowDetail.deadline = escrowDetail.requestRevisedDeadline;
    }

    function cancel() external {
        require(uint8(escrowDetail.status) < 3, '___NOT_ELIGIBLE___');
        require(msg.sender == escrowDetail.buyer || msg.sender == escrowDetail.seller, '___INVALID_BUYER_SELLER___');

        if (
            msg.sender == escrowDetail.buyer &&
            (escrowDetail.status == EscrowStatus.Ongoing || escrowDetail.status == EscrowStatus.RequestRevised)
        ) {
            require(escrowDetail.deadline <= block.timestamp && block.timestamp >= escrowDetail.requestRevisedDeadline, '___NOT_EXPIRED___');
        }

        sendAndStatusUpdate(escrowDetail.buyer, EscrowStatus.Cancelled);
    }

    function fund(address payable toFund) external trusted {
        require(toFund == escrowDetail.buyer || toFund == escrowDetail.seller, '___INVALID_BUYER_SELLER___');
        require(EscrowStatus.Cancelled != escrowDetail.status, '___ALREADY_CANCELLED___');
        require(escrowDetail.status != EscrowStatus.Complete, '___NOT_IN_COMPLETE_STATUS___');
        sendAndStatusUpdate(toFund, EscrowStatus.Complete);
    }

    function getDetails() public view returns (EscrowDetail memory escrow) {
        return escrowDetail;
    }

    modifier onlyBuyer() {
        require(msg.sender == escrowDetail.buyer, '___ONLY_BUYER___');
        _;
    }

    modifier onlySeller() {
        require(msg.sender == escrowDetail.seller, '___ONLY_SELLER___');
        _;
    }

    modifier trusted() {
        require(areTrustedHandlers[msg.sender], '___NOT_TRUSTED___');
        _;
    }
}
