// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import './SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract Escrow {
    using SafeMath for uint256;
    uint256 duration = 915151608; //29 years default
    uint8 feePercent = 1; //default 1
    uint256 deliverRejectDuration = 86400;

    enum EscrowStatus {
        Launched,
        Ongoing,
        Delivered,
        RequestRevised,
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
        if (_duration > 0) {
            duration = _duration;
        }
        addressToPayFee = _addressToPayFee;
        tokenAddress = _tokenAddress;
        feePercent = _feePercent;
        areTrustedHandlers[msg.sender] = true;
        addTrustedHandlers(_handlers);
        escrowDetail = EscrowDetail(
            EscrowStatus.Launched,
            title,
            _tokenAddress,
            duration.add(block.timestamp),
            buyer,
            seller,
            0,
            amount,
            address(this)
        ); // solhint-disable-line not-rely-on-time
    }

    fallback() external payable {
        escrowDetail.amount = msg.value;
    }

    receive() external payable {}

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
        uint256 fee = escrowDetail.amount.mul(feePercent).div(100); // %1
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

    function sellerLaunchedApprove() public payable onlySeller {
        require(getBalance() > 0, '___NO_FUNDS___');
        require(escrowDetail.status == EscrowStatus.Launched, '___NOT_IN_LAUNCHED_STATUS___');
        escrowDetail.status = EscrowStatus.Ongoing;
    }

    function sellerDeliver() external onlySeller {
        require(escrowDetail.status == EscrowStatus.Ongoing, '___NOT_IN_ONGOING_STATUS___');
        escrowDetail.status = EscrowStatus.Delivered;
    }

    function buyerConfirmDelivery() external payable onlyBuyer {
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
            deliverRejectDuration = _deliverRejectDuration;
            escrowDetail.requestRevisedDeadline = deliverRejectDuration.add(block.timestamp);
        }
    }

    function sellerRejectDeliverReject() external onlySeller {
        require(escrowDetail.status == EscrowStatus.RequestRevised, '___NOT_IN_REJECT_DELIVERY_STATUS___');
        escrowDetail.status = EscrowStatus.Dispute;
    }

    function sellerApproveDeliverReject() external onlySeller {
        require(escrowDetail.status == EscrowStatus.RequestRevised, '___NOT_IN_REJECT_DELIVERY_STATUS___');
        require(escrowDetail.deadline >= block.timestamp, '___EXPIRED___');
        escrowDetail.status = EscrowStatus.Ongoing;
        escrowDetail.deadline = escrowDetail.requestRevisedDeadline;
    }

    function cancel() external {
        require(uint8(escrowDetail.status) < 4, '___NOT_ELIGIBLE___');
        require(msg.sender == escrowDetail.buyer || msg.sender == escrowDetail.seller, '___INVALID_BUYER_SELLER___');

        if (
            msg.sender == escrowDetail.buyer &&
            (escrowDetail.status == EscrowStatus.Ongoing || escrowDetail.status == EscrowStatus.RequestRevised || escrowDetail.status == EscrowStatus.Delivered)
        ) {
            require(escrowDetail.deadline <= block.timestamp, '___NOT_EXPIRED___');
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
