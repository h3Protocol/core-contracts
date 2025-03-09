// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

contract H3rmesHelper {
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

    // New internal helper: call leverageFee(uint256, uint256)
    function leverageFee(uint256 sonic, uint256 numberOfDays) internal view returns (uint256 fee) {
        (bool success, bytes memory data) =
            h3rmesContract.staticcall(abi.encodeWithSignature("leverageFee(uint256,uint256)", sonic, numberOfDays));
        require(success && data.length >= 32, "leverageFee call failed");
        fee = abi.decode(data, (uint256));
    }

    // New internal helper: call SONICtoH3RMESLev(uint256, uint256)
    function SONICtoH3RMESLev(uint256 value, uint256 fee) internal view returns (uint256 result) {
        (bool success, bytes memory data) =
            h3rmesContract.staticcall(abi.encodeWithSignature("SONICtoH3RMESLev(uint256,uint256)", value, fee));
        require(success && data.length >= 32, "SONICtoH3RMESLev call failed");
        result = abi.decode(data, (uint256));
    }

    // Utility: replicate the getMidnightTimestamp function from H3rmes
    function getMidnightTimestamp(uint256 date) internal pure returns (uint256) {
        uint256 midnightTimestamp = date - (date % 86400);
        return midnightTimestamp + 1 days;
    }

    /**
     * @notice Simulate a leverageMint operation (using collateral as input).
     * @param collateral The amount of collateral (oSonic) provided.
     * @param debt The debt amount in sonic.
     * @param numberOfDays The borrowing period (must be less than 366 days).
     * @return loan The simulated Loan struct that would be recorded.
     */
    function simulateLeverageMint(uint256 collateral, uint256 debt, uint256 numberOfDays)
        external
        view
        returns (Loan memory loan)
    {
        require(numberOfDays < 366, "Max borrow/extension must be 365 days or less");

        // Compute the end date (simulate getMidnightTimestamp)
        uint256 endDate = getMidnightTimestamp((numberOfDays * 1 days) + block.timestamp);

        // Calculate the fee (combining the leverage fee and interest fee)
        uint256 sonicFee = leverageFee(debt, numberOfDays);
        // User gets debt minus fee
        uint256 userSonic = debt - sonicFee;
        // Calculate fee portions
        uint256 feeAddressAmount = (sonicFee * 3) / 10;
        uint256 userBorrow = (userSonic * 99) / 100;
        uint256 overCollateralizationAmount = (userSonic) / 100;
        uint256 subValue = feeAddressAmount + overCollateralizationAmount;
        uint256 totalFee = sonicFee + overCollateralizationAmount;

        // Simulate fee overage: if collateral > totalFee then feeOverage = collateral - totalFee.
        uint256 feeOverage = 0;
        if (collateral > totalFee) {
            feeOverage = collateral - totalFee;
        }
        // This require simulates: require(collateral - feeOverage == totalFee, "Insufficient sonic fee sent");
        require(collateral - feeOverage == totalFee, "Insufficient sonic fee sent");

        // Convert userSonic to H3rmes collateral via the conversion function
        uint256 userH3rmes = SONICtoH3RMESLev(userSonic, subValue);

        // Return the simulated Loan struct
        loan = Loan({collateral: userH3rmes, borrowed: userBorrow, endDate: endDate, numberOfDays: numberOfDays});
    }

    /**
     * @notice Simulate a leverageMintWithNative operation.
     * @param oSonicAmount The amount of oSonic obtained from the native deposit.
     * @param debt The debt amount in sonic.
     * @param numberOfDays The borrowing period (must be less than 366 days).
     * @return loan The simulated Loan struct that would be recorded.
     */
    function simulateLeverageMintWithNative(uint256 oSonicAmount, uint256 debt, uint256 numberOfDays)
        external
        view
        returns (Loan memory loan)
    {
        require(numberOfDays < 366, "Max borrow/extension must be 365 days or less");

        // In the native version, ltv is computed, but we assume no preexisting loan.
        // Compute the end date (simulate getMidnightTimestamp)
        uint256 endDate = getMidnightTimestamp((numberOfDays * 1 days) + block.timestamp);

        // Calculate the fee (combining the leverage fee and interest fee)
        uint256 sonicFee = leverageFee(debt, numberOfDays);
        uint256 userSonic = debt - sonicFee;
        uint256 feeAddressAmount = (sonicFee * 3) / 10;
        uint256 userBorrow = (userSonic * 99) / 100;
        uint256 overCollateralizationAmount = (userSonic) / 100;
        uint256 subValue = feeAddressAmount + overCollateralizationAmount;
        uint256 totalFee = sonicFee + overCollateralizationAmount;

        // In the native version, if oSonicAmount is greater than totalFee, feeOverage is sent back.
        uint256 feeOverage = 0;
        if (oSonicAmount > totalFee) {
            feeOverage = oSonicAmount - totalFee;
        }
        require(oSonicAmount - feeOverage == totalFee, "Insufficient sonic fee sent");

        uint256 userH3rmes = SONICtoH3RMESLev(userSonic, subValue);

        loan = Loan({collateral: userH3rmes, borrowed: userBorrow, endDate: endDate, numberOfDays: numberOfDays});
    }
}
