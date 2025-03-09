// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

contract H3rmesHelperV1 {
    address public immutable h3rmesContract;

    constructor(address _h3rmesContract) {
        require(_h3rmesContract != address(0), "Invalid contract address");
        h3rmesContract = _h3rmesContract;
    }

    // Helper struct identical to the one in H3rmes
    struct Loan {
        uint256 collateral; // shares of token staked (userH3rmes)
        uint256 borrowed; // user borrow amount (userBorrow)
        uint256 endDate;
        uint256 numberOfDays;
    }

    struct MarketState {
        uint256 totalSupply;
        uint256 backing;
    }

    // Existing helper functions
    function getBacking() internal view returns (uint256) {
        (bool success, bytes memory data) = h3rmesContract.staticcall(abi.encodeWithSignature("getBacking()"));
        require(success && data.length >= 32, "getBacking call failed");
        return abi.decode(data, (uint256));
    }

    function getTotalSupply() internal view returns (uint256) {
        (bool success, bytes memory data) = h3rmesContract.staticcall(abi.encodeWithSignature("totalSupply()"));
        require(success && data.length >= 32, "totalSupply call failed");
        return abi.decode(data, (uint256));
    }

    function getInterestFee(uint256 amount, uint256 numberOfDays) internal view returns (uint256) {
        (bool success, bytes memory data) =
            h3rmesContract.staticcall(abi.encodeWithSignature("getInterestFee(uint256,uint256)", amount, numberOfDays));
        require(success && data.length >= 32, "getInterestFee call failed");
        return abi.decode(data, (uint256));
    }

    function H3RMEStoSONICNoTradeCeil(uint256 hermes) external view returns (uint256) {
        uint256 backing = getBacking();
        uint256 supply = getTotalSupply();
        return (((hermes - 1) * backing) / supply) + 1;
    }

    function H3RMEStoSONICNoTradeCeilMinusInterestFee(uint256 hermes, uint256 numberOfDays)
        external
        view
        returns (uint256)
    {
        uint256 backing = getBacking();
        uint256 supply = getTotalSupply();
        uint256 sonic = (((hermes - 1) * backing) / supply) + 1;
        uint256 interestFee = getInterestFee(sonic, numberOfDays);
        return sonic - interestFee;
    }

    function shouldBorrowMore(address _address) external view returns (bool) {
        (bool successLoan, bytes memory loanData) =
            h3rmesContract.staticcall(abi.encodeWithSignature("getLoanByAddress(address)", _address));
        (uint256 collateral, uint256 borrowed, uint256 endDate) = abi.decode(loanData, (uint256, uint256, uint256));
        if (borrowed == 0) {
            return false;
        }
        (bool successExpired, bytes memory expiredData) =
            h3rmesContract.staticcall(abi.encodeWithSignature("isLoanExpired(address)", _address));
        bool expired = abi.decode(expiredData, (bool));
        return !expired;
    }

    function getMarketState() external view returns (MarketState memory marketState) {
        marketState = MarketState({totalSupply: getTotalSupply(), backing: getBacking()});
    }
}
