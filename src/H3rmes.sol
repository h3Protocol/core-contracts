//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IOSonicZapper} from "./interfaces/IOSonicZapper.sol";
import {H3rmesExchange} from "./H3rmesExchange.sol";

contract H3rmes is ERC20Burnable, AccessControl, ReentrancyGuard {
    using SafeERC20 for ERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant EXCHANGE_ROLE = keccak256("EXCHANGE_ROLE");
    bytes32 public constant POSITION_MANAGER_ROLE = keccak256("POSITION_MANAGER_ROLE");

    address public FEE_ADDRESS;

    ERC20 public oSonic;
    IOSonicZapper public oSonicZapper;
    H3rmesExchange public h3rmesExchange;

    uint256 private constant MIN = 1000;

    uint256 public sell_fee = 975;
    uint256 public buy_fee = 975;
    uint256 public buy_fee_leverage = 10;
    uint256 private constant FEE_BASE_1000 = 1000;

    uint256 private constant FEES_BUY = 125;
    uint256 private constant FEES_SELL = 125;

    uint8 public fee_fraction = 50;
    uint256 public maxLTV = 20000; // 20x, 1000 = 1x = FEE_BASE_1000

    bool public start = false;

    uint128 private constant SONICinWEI = 1 * 10 ** 18;

    uint256 private totalBorrowed = 0;
    uint256 private totalCollateral = 0;

    uint128 public constant maxSupply = 10e28;
    uint256 public totalMinted;
    uint256 public lastPrice = 0;

    struct Loan {
        uint256 collateral; // shares of token staked
        uint256 borrowed; // user reward per token paid
        uint256 endDate;
        uint256 numberOfDays;
    }

    mapping(address => Loan) public Loans;

    mapping(uint256 => uint256) public BorrowedByDate;
    mapping(uint256 => uint256) public CollateralByDate;
    uint256 public lastLiquidationDate;

    event Price(uint256 time, uint256 price, uint256 volumeInSonic);
    event MaxUpdated(uint256 max);
    event SellFeeUpdated(uint256 sellFee);
    event FeeAddressUpdated(address _address);
    event BuyFeeUpdated(uint256 buyFee);
    event LeverageFeeUpdated(uint256 leverageFee);
    event Started(bool started);
    event Liquidate(uint256 time, uint256 amount);
    event LoanDataUpdate(
        uint256 collateralByDate, uint256 borrowedByDate, uint256 totalBorrowed, uint256 totalCollateral
    );
    event SendSonic(address to, uint256 amount);

    constructor(address _operator, address _oSonic, address _oSonicZapper, address _feeAddress) ERC20("H3rmes", "H3") {
        _setupRole(DEFAULT_ADMIN_ROLE, _operator);
        _setupRole(OPERATOR_ROLE, _operator);
        lastLiquidationDate = getMidnightTimestamp(uint256(block.timestamp));
        oSonic = ERC20(_oSonic);
        oSonicZapper = IOSonicZapper(_oSonicZapper);
        FEE_ADDRESS = _feeAddress;
    }

    function setStart(uint256 _initialValue) public onlyRole(OPERATOR_ROLE) {
        require(FEE_ADDRESS != address(0x0), "Must set fee address");
        require(!start, "Trading already initialized");
        oSonic.safeTransferFrom(msg.sender, address(this), _initialValue);
        uint256 teamMint = _initialValue * MIN;
        require(teamMint >= 1 ether);
        mint(msg.sender, teamMint);

        _transfer(msg.sender, 0x000000000000000000000000000000000000dEaD, 1 ether);
        start = true;
        emit Started(true);
    }

    function setExchange(address _address) external onlyRole(OPERATOR_ROLE) {
        if (address(h3rmesExchange) != address(0x0)) {
            revokeRole(EXCHANGE_ROLE, address(h3rmesExchange));
        }
        h3rmesExchange = H3rmesExchange(_address);
        _setupRole(EXCHANGE_ROLE, _address);
    }

    function mint(address to, uint256 value) private {
        require(to != address(0x0), "Can't mint to to 0x0 address");
        totalMinted = totalMinted + value;
        require(totalMinted <= maxSupply, "NO MORE H3RMES");

        _mint(to, value);
    }

    function setFeeAddress(address _address) external onlyRole(OPERATOR_ROLE) {
        require(_address != address(0x0), "Can't set fee address to 0x0 address");
        FEE_ADDRESS = _address;
        emit FeeAddressUpdated(_address);
    }

    function setBuyFee(uint256 amount) external onlyRole(OPERATOR_ROLE) {
        require(amount <= 992, "buy fee must be greater than FEES_BUY");
        require(amount >= 975, "buy fee must be less than 2.5%");
        buy_fee = amount;
        emit BuyFeeUpdated(amount);
    }

    function setBuyFeeLeverage(uint256 amount) external onlyRole(OPERATOR_ROLE) {
        require(amount <= 25, "leverage buy fee must be less 2.5%");
        require(amount >= 0, "leverage buy fee must be greater than 0%");
        buy_fee_leverage = amount;
        emit LeverageFeeUpdated(amount);
    }

    function setSellFee(uint256 amount) external onlyRole(OPERATOR_ROLE) {
        require(amount <= 992, "sell fee must be greater than FEES_SELL");
        require(amount >= 975, "sell fee must be less than 2.5%");
        sell_fee = amount;
        emit SellFeeUpdated(amount);
    }

    function setMaxLTV(uint256 amount) external onlyRole(OPERATOR_ROLE) {
        maxLTV = amount;
    }

    function _buy(address receiver, uint256 value) internal {
        liquidate();
        require(start, "Trading must be initialized");

        require(receiver != address(0x0), "Reciever cannot be 0x0 address");

        // Mint H3rmes to sender
        // AUDIT: to user round down
        uint256 h3rmes = SONICtoH3RMES(value);

        mint(receiver, (h3rmes * getBuyFee()) / FEE_BASE_1000);

        // Team fee
        uint256 feeAddressAmount = value / FEES_BUY;
        require(feeAddressAmount > MIN, "must trade over min");
        sendSonic(FEE_ADDRESS, feeAddressAmount);

        safetyCheck(value);
    }

    function buy(address receiver, uint256 value) external nonReentrant {
        require(value != 0, "Must send more than 0");
        oSonic.safeTransferFrom(msg.sender, address(this), value);
        _buy(receiver, value);
    }

    function buyWithNative(address receiver) external payable nonReentrant {
        require(msg.value != 0, "Must send more than 0");
        uint256 oSonicAmmount = oSonicZapper.deposit{value: msg.value}();
        _buy(receiver, oSonicAmmount);
    }

    function sell(uint256 h3rmes) external nonReentrant {
        liquidate();

        // Total Eth to be sent
        // AUDIT: to user round down
        uint256 sonic = H3RMEStoSONIC(h3rmes);

        // Burn of JAY
        uint256 feeAddressAmount = sonic / FEES_SELL;
        _burn(msg.sender, h3rmes);

        // Payment to sender
        sendSonic(msg.sender, (sonic * sell_fee) / FEE_BASE_1000);

        // Team fee

        require(feeAddressAmount > MIN, "must trade over min");
        sendSonic(FEE_ADDRESS, feeAddressAmount);

        safetyCheck(sonic);
    }

    // Calculation may be off if liqudation is due to occur
    function getBuyAmount(uint256 amount) public view returns (uint256) {
        uint256 h3rmes = SONICtoH3RMESNoTrade(amount);
        return ((h3rmes * getBuyFee()) / FEE_BASE_1000);
    }

    function leverageFee(uint256 sonic, uint256 numberOfDays) public view returns (uint256) {
        uint256 mintFee = (sonic * buy_fee_leverage) / FEE_BASE_1000;

        uint256 interest = getInterestFee(sonic, numberOfDays);

        return (mintFee + interest);
    }

    function leverageMint(uint256 collateral, uint256 debt, uint256 numberOfDays) public nonReentrant {
        require(start, "Trading must be initialized");
        require(numberOfDays < 366, "Max borrow/extension must be 365 days or less");

        Loan memory userLoan = Loans[msg.sender];
        if (userLoan.borrowed != 0) {
            if (isLoanExpired(msg.sender)) {
                delete Loans[msg.sender];
            }
            require(Loans[msg.sender].borrowed == 0, "Use account with no loans");
        }
        liquidate();

        oSonic.safeTransferFrom(msg.sender, address(this), collateral);

        uint256 endDate = getMidnightTimestamp(uint256((numberOfDays * 1 days) + block.timestamp));

        uint256 sonicFee = leverageFee(debt, numberOfDays);

        uint256 userSonic = debt - sonicFee;

        uint256 feeAddressAmount = (sonicFee * fee_fraction) / 100;
        uint256 userBorrow = (userSonic * 99) / 100;
        uint256 overCollateralizationAmount = (userSonic) / 100;
        uint256 subValue = feeAddressAmount + overCollateralizationAmount;
        uint256 totalFee = (sonicFee + overCollateralizationAmount);
        uint256 ltv = getLTV(totalFee, debt);
        require(ltv <= maxLTV);
        uint256 feeOverage;
        if (collateral > totalFee) {
            feeOverage = collateral - totalFee;
            sendSonic(msg.sender, feeOverage);
        }
        require(collateral - feeOverage == totalFee, "Insufficient sonic fee sent");

        // AUDIT: to user round down
        uint256 userH3rmes = SONICtoH3RMESLev(userSonic, subValue);
        mint(address(this), userH3rmes);

        require(feeAddressAmount > MIN, "Fees must be higher than min.");
        sendSonic(FEE_ADDRESS, feeAddressAmount);

        addLoansByDate(userBorrow, userH3rmes, endDate);
        Loans[msg.sender] =
            Loan({collateral: userH3rmes, borrowed: userBorrow, endDate: endDate, numberOfDays: numberOfDays});

        safetyCheck(debt);
    }
    function leverageMintWithNative(uint256 debt, uint256 numberOfDays) external payable nonReentrant {
        require(start, "Trading must be initialized");
        require(numberOfDays < 366, "Max borrow/extension must be 365 days or less");
        Loan memory userLoan = Loans[msg.sender];
        if (userLoan.borrowed != 0) {
            if (isLoanExpired(msg.sender)) {
                delete Loans[msg.sender];
            }
            require(Loans[msg.sender].borrowed == 0, "Use account with no loans");
        }
        liquidate();

        uint256 oSonicAmount = oSonicZapper.deposit{value: msg.value}();
        uint256 endDate = getMidnightTimestamp(uint256((numberOfDays * 1 days) + block.timestamp));

        uint256 sonicFee = leverageFee(debt, numberOfDays);
        uint256 userSonic = debt - sonicFee;
        uint256 feeAddressAmount = (sonicFee * fee_fraction) / 100;
        uint256 userBorrow = (userSonic * 99) / 100;
        uint256 overCollateralizationAmount = (userSonic) / 100;
        uint256 subValue = feeAddressAmount + overCollateralizationAmount;
        uint256 totalFee = (sonicFee + overCollateralizationAmount);
        uint256 ltv = getLTV(totalFee, debt);
        require(ltv <= maxLTV);
        uint256 feeOverage;
        if (oSonicAmount > totalFee) {
            feeOverage = oSonicAmount - totalFee;
            sendSonic(msg.sender, feeOverage);
        }
        require(oSonicAmount - feeOverage == totalFee, "Insufficient sonic fee sent");

        // AUDIT: to user round down
        uint256 userH3rmes = SONICtoH3RMESLev(userSonic, subValue);
        mint(address(this), userH3rmes);

        require(feeAddressAmount > MIN, "Fees must be higher than min.");
        sendSonic(FEE_ADDRESS, feeAddressAmount);

        addLoansByDate(userBorrow, userH3rmes, endDate);
        Loans[msg.sender] =
            Loan({collateral: userH3rmes, borrowed: userBorrow, endDate: endDate, numberOfDays: numberOfDays});

        safetyCheck(debt);
    }

    function getLTV(uint256 collateral, uint256 debt) public pure returns (uint256 ltv) {
        ltv = Math.mulDiv(debt, 1000, collateral);
    }

    function getInterestFee(uint256 amount, uint256 numberOfDays) public pure returns (uint256) {
        uint256 interest = Math.mulDiv(0.039e18, numberOfDays, 365) + 0.001e18;
        return Math.mulDiv(amount, interest, 1e18);
    }

    function borrow(uint256 sonic, uint256 numberOfDays, uint256 maxAmountIn) public nonReentrant returns (uint256) {
        return _borrow(msg.sender, sonic, numberOfDays, maxAmountIn);
    }

    function borrowMore(uint256 sonic, uint256 maxAmountIn) public nonReentrant returns (uint256) {
        return _borrowMore(msg.sender, sonic, maxAmountIn);
    }

    function borrowFor(address borrower, uint256 sonic, uint256 numberOfDays, uint256 maxAmountIn)
        external
        nonReentrant
        onlyRole(POSITION_MANAGER_ROLE)
        returns (uint256)
    {
        return _borrow(borrower, sonic, numberOfDays, maxAmountIn);
    }

    function borrowMoreFor(address borrower, uint256 sonic, uint256 maxAmountIn)
        external
        nonReentrant
        onlyRole(POSITION_MANAGER_ROLE)
        returns (uint256)
    {
        return _borrowMore(borrower, sonic, maxAmountIn);
    }

    function _borrow(address borrower, uint256 sonic, uint256 numberOfDays, uint256 maxAmountIn)
        internal
        returns (uint256)
    {
        require(numberOfDays < 366, "Max borrow/extension must be 365 days or less");
        require(sonic != 0, "Must borrow more than 0");
        if (isLoanExpired(borrower)) {
            delete Loans[borrower];
        }
        require(Loans[borrower].borrowed == 0, "Use borrowMore to borrow more");
        liquidate();
        uint256 endDate = getMidnightTimestamp(uint256((numberOfDays * 1 days) + block.timestamp));

        uint256 sonicFee = getInterestFee(sonic, numberOfDays);

        uint256 feeAddressFee = (sonicFee * fee_fraction) / 100;

        //AUDIT: h3rmes required from user round up?
        uint256 userH3rmes = SONICtoH3RMESNoTradeCeil(sonic);
        require(userH3rmes <= maxAmountIn, "Amount exceeds max");
        uint256 newUserBorrow = (sonic * 99) / 100;

        Loans[borrower] =
            Loan({collateral: userH3rmes, borrowed: newUserBorrow, endDate: endDate, numberOfDays: numberOfDays});

        _transfer(borrower, address(this), userH3rmes);
        require(feeAddressFee > MIN, "Fees must be higher than min.");

        sendSonic(borrower, newUserBorrow - sonicFee);
        sendSonic(FEE_ADDRESS, feeAddressFee);

        addLoansByDate(newUserBorrow, userH3rmes, endDate);

        safetyCheck(sonicFee);
        return newUserBorrow - sonicFee;
    }

    function _borrowMore(address borrower, uint256 sonic, uint256 maxAmountIn) internal returns (uint256) {
        require(!isLoanExpired(borrower), "Loan expired use borrow");
        require(sonic != 0, "Must borrow more than 0");
        liquidate();
        uint256 userBorrowed = Loans[borrower].borrowed;
        uint256 userCollateral = Loans[borrower].collateral;
        uint256 userEndDate = Loans[borrower].endDate;

        uint256 newBorrowLength = uint256((userEndDate - getMidnightTimestamp(uint256(block.timestamp))) / 1 days);

        uint256 sonicFee = getInterestFee(sonic, newBorrowLength);

        //AUDIT: h3rmes required from user round up?
        uint256 userH3rmes = SONICtoH3RMESNoTradeCeil(sonic);
        uint256 userBorrowedInH3rmes = SONICtoH3RMESNoTrade(userBorrowed);
        uint256 userExcessInH3rmes = ((userCollateral) * 99) / 100 - userBorrowedInH3rmes;

        uint256 requireCollateralFromUser = userH3rmes;
        if (userExcessInH3rmes >= userH3rmes) {
            requireCollateralFromUser = 0;
        } else {
            requireCollateralFromUser = requireCollateralFromUser - userExcessInH3rmes;
        }

        uint256 feeAddressFee = (sonicFee * fee_fraction) / 100;

        uint256 newUserBorrow = (sonic * 99) / 100;

        uint256 newUserBorrowTotal = userBorrowed + newUserBorrow;
        uint256 newUserCollateralTotal = userCollateral + requireCollateralFromUser;

        Loans[borrower] = Loan({
            collateral: newUserCollateralTotal,
            borrowed: newUserBorrowTotal,
            endDate: userEndDate,
            numberOfDays: newBorrowLength
        });

        if (requireCollateralFromUser != 0) {
            require(userH3rmes <= maxAmountIn, "Amount exceeds max");
            _transfer(borrower, address(this), requireCollateralFromUser);
        }

        require(feeAddressFee > MIN, "Fees must be higher than min.");
        sendSonic(FEE_ADDRESS, feeAddressFee);
        sendSonic(borrower, newUserBorrow - sonicFee);

        addLoansByDate(newUserBorrow, requireCollateralFromUser, userEndDate);

        safetyCheck(sonicFee);
        return newUserBorrow - sonicFee;
    }

    function removeCollateral(uint256 amount) public nonReentrant {
        require(!isLoanExpired(msg.sender), "Your loan has been liquidated, no collateral to remove");
        liquidate();
        uint256 collateral = Loans[msg.sender].collateral;
        // AUDIT: to user round down
        require(
            Loans[msg.sender].borrowed <= (H3RMEStoSONIC(collateral - amount) * 99) / 100,
            "Require 99% collateralization rate"
        );
        Loans[msg.sender].collateral = Loans[msg.sender].collateral - amount;
        _transfer(address(this), msg.sender, amount);
        subLoansByDate(0, amount, Loans[msg.sender].endDate);

        safetyCheck(0);
    }

    function repay(uint256 debt) public nonReentrant {
        uint256 borrowed = Loans[msg.sender].borrowed;
        require(borrowed > debt, "Must repay less than borrowed amount");
        require(debt != 0, "Must repay something");

        require(!isLoanExpired(msg.sender), "Your loan has been liquidated, cannot repay");
        oSonic.safeTransferFrom(msg.sender, address(this), debt);
        uint256 newBorrow = borrowed - debt;
        Loans[msg.sender].borrowed = newBorrow;
        subLoansByDate(debt, 0, Loans[msg.sender].endDate);

        safetyCheck(0);
    }

    function repayWithNative(uint256 debt) public payable nonReentrant {
        uint256 borrowed = Loans[msg.sender].borrowed;
        require(borrowed > debt, "Must repay less than borrowed amount");
        require(debt != 0, "Must repay something");

        require(!isLoanExpired(msg.sender), "Your loan has been liquidated, cannot repay");
        uint256 oSonicAmount = oSonicZapper.deposit{value: msg.value}();
        require(oSonicAmount >= debt, "Must send enough to repay");
        uint256 newBorrow = borrowed - debt;
        Loans[msg.sender].borrowed = newBorrow;
        subLoansByDate(debt, 0, Loans[msg.sender].endDate);

        safetyCheck(0);
    }

    function closePosition() public nonReentrant {
        uint256 borrowed = Loans[msg.sender].borrowed;
        uint256 collateral = Loans[msg.sender].collateral;
        require(!isLoanExpired(msg.sender), "Your loan has been liquidated, no collateral to remove");
        oSonic.safeTransferFrom(msg.sender, address(this), borrowed);
        _transfer(address(this), msg.sender, collateral);
        subLoansByDate(borrowed, collateral, Loans[msg.sender].endDate);

        delete Loans[msg.sender];
        safetyCheck(0);
    }

    function flashClosePosition() public nonReentrant {
        require(!isLoanExpired(msg.sender), "Your loan has been liquidated, no collateral to remove");
        liquidate();
        uint256 borrowed = Loans[msg.sender].borrowed;

        uint256 collateral = Loans[msg.sender].collateral;

        // AUDIT: from user round up
        uint256 collateralInSonic = H3RMEStoSONIC(collateral);
        _burn(address(this), collateral);

        uint256 collateralInSonicAfterFee = (collateralInSonic * 99) / 100;

        uint256 fee = collateralInSonic / 100;
        require(collateralInSonicAfterFee >= borrowed, "You do not have enough collateral to close position");

        uint256 toUser = collateralInSonicAfterFee - borrowed;
        uint256 feeAddressFee = (fee * fee_fraction) / 100;

        sendSonic(msg.sender, toUser);

        require(feeAddressFee > MIN, "Fees must be higher than min.");
        sendSonic(FEE_ADDRESS, feeAddressFee);
        subLoansByDate(borrowed, collateral, Loans[msg.sender].endDate);

        delete Loans[msg.sender];
        safetyCheck(borrowed);
    }

    function extendLoan(uint256 numberOfDays) public nonReentrant returns (uint256) {
        uint256 oldEndDate = Loans[msg.sender].endDate;
        uint256 borrowed = Loans[msg.sender].borrowed;
        uint256 collateral = Loans[msg.sender].collateral;
        uint256 _numberOfDays = Loans[msg.sender].numberOfDays;

        uint256 newEndDate = oldEndDate + (numberOfDays * 1 days);

        uint256 loanFee = getInterestFee(borrowed, numberOfDays);
        require(!isLoanExpired(msg.sender), "Your loan has been liquidated, no collateral to remove");
        uint256 feeAddressFee = (loanFee * fee_fraction) / 100;
        require(feeAddressFee > MIN, "Fees must be higher than min.");
        oSonic.safeTransferFrom(msg.sender, address(this), loanFee);
        sendSonic(FEE_ADDRESS, feeAddressFee);
        subLoansByDate(borrowed, collateral, oldEndDate);
        addLoansByDate(borrowed, collateral, newEndDate);
        Loans[msg.sender].endDate = newEndDate;
        Loans[msg.sender].numberOfDays = numberOfDays + _numberOfDays;
        require((newEndDate - block.timestamp) / 1 days < 366, "Loan must be under 365 days");

        safetyCheck(loanFee);
        return loanFee;
    }

    function extendLoanWithNative(uint256 numberOfDays) public payable nonReentrant returns (uint256) {
        uint256 oldEndDate = Loans[msg.sender].endDate;
        uint256 borrowed = Loans[msg.sender].borrowed;
        uint256 collateral = Loans[msg.sender].collateral;
        uint256 _numberOfDays = Loans[msg.sender].numberOfDays;

        uint256 newEndDate = oldEndDate + (numberOfDays * 1 days);

        uint256 loanFee = getInterestFee(borrowed, numberOfDays);
        require(!isLoanExpired(msg.sender), "Your loan has been liquidated, no collateral to remove");
        uint256 feeAddressFee = (loanFee * fee_fraction) / 100;
        require(feeAddressFee > MIN, "Fees must be higher than min.");
        uint256 oSonicAmount = oSonicZapper.deposit{value: msg.value}();
        require(oSonicAmount >= loanFee, "Must send enough to repay");
        sendSonic(FEE_ADDRESS, feeAddressFee);
        subLoansByDate(borrowed, collateral, oldEndDate);
        addLoansByDate(borrowed, collateral, newEndDate);
        Loans[msg.sender].endDate = newEndDate;
        Loans[msg.sender].numberOfDays = numberOfDays + _numberOfDays;
        require((newEndDate - block.timestamp) / 1 days < 366, "Loan must be under 365 days");

        safetyCheck(loanFee);
        safetyCheck(loanFee);
        return loanFee;
    }

    function liquidate() public {
        uint256 borrowed;
        uint256 collateral;

        while (lastLiquidationDate < block.timestamp) {
            collateral = collateral + CollateralByDate[lastLiquidationDate];
            borrowed = borrowed + BorrowedByDate[lastLiquidationDate];
            lastLiquidationDate = lastLiquidationDate + 1 days;
        }
        if (collateral != 0) {
            totalCollateral = totalCollateral - collateral;
            _burn(address(this), collateral);
        }
        if (borrowed != 0) {
            totalBorrowed = totalBorrowed - borrowed;
            emit Liquidate(lastLiquidationDate - 1 days, borrowed);
        }
    }

    function addLoansByDate(uint256 borrowed, uint256 collateral, uint256 date) private {
        CollateralByDate[date] = CollateralByDate[date] + collateral;
        BorrowedByDate[date] = BorrowedByDate[date] + borrowed;
        totalBorrowed = totalBorrowed + borrowed;
        totalCollateral = totalCollateral + collateral;
        emit LoanDataUpdate(CollateralByDate[date], BorrowedByDate[date], totalBorrowed, totalCollateral);
    }

    function subLoansByDate(uint256 borrowed, uint256 collateral, uint256 date) private {
        CollateralByDate[date] = CollateralByDate[date] - collateral;
        BorrowedByDate[date] = BorrowedByDate[date] - borrowed;
        totalBorrowed = totalBorrowed - borrowed;
        totalCollateral = totalCollateral - collateral;
        emit LoanDataUpdate(CollateralByDate[date], BorrowedByDate[date], totalBorrowed, totalCollateral);
    }

    // utility fxns
    function getMidnightTimestamp(uint256 date) public pure returns (uint256) {
        uint256 midnightTimestamp = date - (date % 86400); // Subtracting the remainder when divided by the number of seconds in a day (86400)
        return midnightTimestamp + 1 days;
    }

    function getLoansExpiringByDate(uint256 date) public view returns (uint256, uint256) {
        return (BorrowedByDate[getMidnightTimestamp(date)], CollateralByDate[getMidnightTimestamp(date)]);
    }

    function getLoanByAddress(address _address) public view returns (uint256, uint256, uint256) {
        if (Loans[_address].endDate >= block.timestamp) {
            return (Loans[_address].collateral, Loans[_address].borrowed, Loans[_address].endDate);
        } else {
            return (0, 0, 0);
        }
    }

    function isLoanExpired(address _address) public view returns (bool) {
        return Loans[_address].endDate < block.timestamp;
    }

    function getBuyFee() public view returns (uint256) {
        return buy_fee;
    }

    // Buy H3rmes

    function getTotalBorrowed() public view returns (uint256) {
        return totalBorrowed;
    }

    function getTotalCollateral() public view returns (uint256) {
        return totalCollateral;
    }

    function getOSonicBalance() public view returns (uint256) {
        return oSonic.balanceOf(address(this));
    }

    function getBacking() public view returns (uint256) {
        return getOSonicBalance() + getTotalBorrowed();
    }

    function safetyCheck(uint256 sonic) private {
        uint256 newPrice = (getBacking() * 1 ether) / totalSupply();
        uint256 _totalColateral = balanceOf(address(this));
        require(
            _totalColateral >= totalCollateral,
            "The h3rmes balance of the contract must be greater than or equal to the collateral"
        );
        require(lastPrice <= newPrice, "The price of h3rmes cannot decrease");
        lastPrice = newPrice;
        emit Price(uint256(block.timestamp), newPrice, sonic);
    }

    function H3RMEStoSONIC(uint256 value) public view returns (uint256) {
        return Math.mulDiv(value, getBacking(), totalSupply());
    }

    function SONICtoH3RMES(uint256 value) public view returns (uint256) {
        return Math.mulDiv(value, totalSupply(), getBacking() - value);
    }

    function SONICtoH3RMESLev(uint256 value, uint256 fee) public view returns (uint256) {
        uint256 backing = getBacking() - fee;
        return (value * totalSupply() + (backing - 1)) / backing;
    }

    function SONICtoH3RMESNoTradeCeil(uint256 value) public view returns (uint256) {
        uint256 backing = getBacking();
        return (value * totalSupply() + (backing - 1)) / backing;
    }

    function SONICtoH3RMESNoTrade(uint256 value) public view returns (uint256) {
        uint256 backing = getBacking();
        return Math.mulDiv(value, totalSupply(), backing);
    }

    function sendSonic(address _address, uint256 _value) internal {
        oSonic.safeTransfer(_address, _value);
        emit SendSonic(_address, _value);
    }

    //utils
    function getBuyH3rmes(uint256 amount) external view returns (uint256) {
        return (amount * (totalSupply()) * (buy_fee)) / (getBacking()) / (FEE_BASE_1000);
    }

    function credit(address to, uint256 value) external onlyRole(EXCHANGE_ROLE) {
        _mint(to, value);
    }

    function debit(address account, uint256 amount) external onlyRole(EXCHANGE_ROLE) {
        _burn(account, amount);
    }

    function addPositionManagerContract(address _address) external onlyRole(OPERATOR_ROLE) {
        _setupRole(POSITION_MANAGER_ROLE, _address);
    }
}
