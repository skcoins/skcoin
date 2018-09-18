pragma solidity ^0.4.24;


contract Skcoin {
    using SafeMath for uint;

    /*=====================================
    =            CONSTANTS                =
    =====================================*/

    uint8 constant public                decimals = 18;//精度

    uint constant internal               tokenPriceInitial_ = 0.000653 ether;//SKY初始价
    uint constant internal               magnitude = 2 ** 64;//量级精度

    uint constant internal               icoHardCap = 250 ether;//ICO硬顶
    uint constant internal               addressICOLimit = 1   ether;//单个地址的ICO最大购买数量
    uint constant internal               icoMinBuyIn = 0.1 finney;//单个地址的ICO最小购买数量
    uint constant internal               icoMaxGasPrice = 50000000000 wei;//ICO的Gas单价

    uint constant internal               MULTIPLIER = 9615;//增量精度
    uint constant internal               MIN_ETH_BUYIN = 0.0001 ether;//最小Ether购买数量
    uint constant internal               MIN_TOKEN_SELL_AMOUNT = 0.0001 ether;//最小Token售卖数量
    uint constant internal               MIN_TOKEN_TRANSFER = 1e10;//最小Token转账数量
    uint constant internal               referrer_percentage = 30; //推荐奖励
    uint constant internal               user_percentage = 60; //用户占比

    uint public                          stakingRequirement = 100e18; // 持币数量大于stakingRequirement才能获取推荐费

    /*================================
     =          CONFIGURABLES         =
     ================================*/

    string public                        name = "Skcoin"; //名称
    string public                        symbol = "SKY";  //缩写
    uint   internal                      tokenSupply = 0; //供应量

    mapping(address => 
    mapping(address => uint))     public allowed;
    mapping(address => bool)      public administrators; //管理员列表

    bytes32 constant              public icoHashedPass = bytes32(0x5ddcde33b94b19bdef79dd9ea75be591942b9ec78286d64b44a356280fb6a262);

    address internal                     reserveAddress; //Ether储备金地址
    address internal                     platformAddress; //平台的收益地址
    address internal                     bankrollAddress;


    /*================================
     =            DATA               =
     ================================*/

    mapping(address => uint)    internal frontTokenBalanceLedger; // token bought total
    mapping(address => uint)    internal dividendTokenBalanceLedger_; //分红账本
    mapping(address => uint)    internal referralBalance_; //推荐账本
    mapping(address => int256)  internal payoutsTo_; //支付账本
    mapping(address => uint)    internal ICOBuyIn; //ICO认购记录账本

    mapping(uint8 => bool)      internal validDividendRates; //预设的分红比率
    mapping(address => bool)    internal userSelectedRate; //用户选择的分红比率
    mapping(address => uint8)   internal userDividendRate; //用户最终的分红比率
    mapping(address => uint256) internal holderIndex; // Mapping of holder addresses (index)

    address[]                   internal holders; //Token持有者数组

    uint    public                       tokensMintedDuringICO; //ICO发行的Token数量
    uint    public                       ethInvestedDuringICO; //ICO认购的Ether数量
    uint    public                       currentEthInvested; //最新的Ether认购数量
    uint    internal                     divTokenSupply = 0; //参与分红的Token数量
    uint    internal                     profitPerDivToken; //单个Token的分红利润
    uint256 internal                     dividendTotalToken; //本轮分红Token数量

    bool    public                       icoPhase = false; //是否是ICO阶段
    bool    public                       regularPhase = false;
    uint                                 icoOpenTime;//ICO开始时间

    /*=================================
    =            MODIFIERS            =
    =================================*/

    modifier onlyHolders() {
        require(myFrontEndTokens() > 0);
        _;
    }

    modifier dividendHolder() {
        require(myDividends(true) > 0);
        _;
    }

    modifier onlyAdministrator(){
        address _customerAddress = msg.sender;
        require(administrators[_customerAddress]);
        _;
    }

    /*==============================
    =            EVENTS            =
    ==============================*/

    /*
    * ETH购买Skc
    */
    event OnTokenPurchase(
        address indexed customerAddress, //地址
        uint incomingEthereum, //总的ETH，包含平台抽成
        uint tokensMinted, //购买Token数
        uint tokenPrice, //token价格
        uint8 divChoice, //股息率
        address referrer //推荐人
    );

    /*
    * Token兑换ETH
    */
    event OnTokenSell(
        address indexed customerAddress, //用户地址
        uint ethereumEarned, //最终兑换的ETH数
        uint tokensBurned, //兑换ETH时使用的Token数量
        uint tokenPrice, //token价格
        uint divRate //平均股息率
    );

    /*
    * 手动触发分成
    */
    event Divide(
        address indexed administrator, //管理员地址
        uint totalToken, // 待分成总的SKC数量
        uint holderNumber //当前SKC持有人数量
    );

    event RedeemGamePoints(
        uint256 id,
        address indexed from, //Token转出地址
        address indexed to, //Token转入地址
        uint tokens //token数量
    );

    /*
    * SKC分红
    */
    event SKCDivide(

    );

    /*
    * 用户选择的股息率
    */
    event UserDividendRate(
        address user,
        uint divRate
    );

    /*
    * 暂时未使用
    */
    event OnReinvestment(
        address indexed customerAddress,
        uint ethereumReinvested,
        uint tokensMinted
    );

    event OnWithdraw(
        address indexed customerAddress,
        uint ethereumWithdrawn
    );

    /*
    * Token转帐
    */
    event Transfer(
        address indexed from, //Token转出地址
        address indexed to, //Token转入地址
        uint tokens //token数量
    );

    /*
    * 将Token授权给其它地址
    */
    event Approval(
        address indexed tokenOwner, //Token的原来持有者
        address indexed spender, //被授权人，可以花费tokenOwner授权数量的Token
        uint tokens //授权的Token数量
    );

    event Allocation(
        uint toBankRoll,
        uint toReferrer,
        uint toTokenHolders,
        uint forTokens
    );

    event Referral(
        address referrer,
        uint amountReceived
    );

    /*=======================================
    =            PUBLIC FUNCTIONS           =
    =======================================*/
    constructor (address _platformAddress)
    public
    {
        platformAddress = _platformAddress;

        administrators[msg.sender] = true;

        validDividendRates[2] = true;
        validDividendRates[5] = true;
        validDividendRates[10] = true;
        validDividendRates[20] = true;
        validDividendRates[35] = true;
        validDividendRates[50] = true;
    }

    /** 获取常量的一些方法 */

    /**
     * 当前SKC的发行量\流通量
     */
    function totalSupply()
    public
    view
    returns (uint256)
    {
        return tokenSupply;
    }

    /**
     * 当前合约持有ETH数量
     */
    function totalEthereumBalance()
    public
    view
    returns (uint)
    {
        return address(this).balance;
    }

    /**
     * ICO阶段募集的ETH数量
     */
    function totalEthereumICOReceived()
    public
    view
    returns (uint)
    {
        return ethInvestedDuringICO;
    }

    /**
     * 调用者的SKC余额
     * Retrieve the frontend tokens owned by the caller
     */
    function myFrontEndTokens()
    public
    view
    returns (uint)
    {
        address _customerAddress = msg.sender;
        return balanceOf(_customerAddress);
    }

    /**
     * 获取目标地址的SKC余额
     */
    function balanceOf(address _customerAddress)
    view
    public
    returns (uint)
    {
        return frontTokenBalanceLedger[_customerAddress];
    }

    /*
    * 设置BankROll合约地址
    */
    function setBankrollAddress(address _bankrollAddress)
    public
    onlyAdministrator
    {
        bankrollAddress = _bankrollAddress;
    }

    /**
     * 修改BankRoll合约地址
     * wj 需要将旧地址的Token转到新地址？
     */
    function changeBankroll(address _newBankrollAddress)
    onlyAdministrator
    public
    {   
        bankrollAddress = _newBankrollAddress;
    }

    /**
    * 设置平台收益地址
    */
    function setPlatformAddress(address _platformAddress)
    public
    onlyAdministrator
    {
        platformAddress = _platformAddress;
        userSelectedRate[platformAddress] = true;
        userDividendRate[platformAddress] = 50;
    }

    /*
    * ETH直接购买游戏积分
    */
    function ethBuyGamePoints(uint256 _id, address _referredBy, uint8 divChoice)
    public
    payable
    returns (uint256)
    {
        // wj ICO phrase is enable?
        //require(regularPhase);
        address _customerAddress = msg.sender;
        uint256 frontendBalance = frontTokenBalanceLedger[msg.sender];
        if (userSelectedRate[_customerAddress] && divChoice == 0) {
            purchaseTokens(msg.value, _referredBy);
        } else {
            buyAndSetDivPercentage(_referredBy, divChoice);
        }
        uint256 difference = SafeMath.sub(frontTokenBalanceLedger[msg.sender], frontendBalance);

        bool isSuccess = bankrollAddress.call(bytes4(keccak256("tokenToPointBySkcContract(uint256, address, uint256)")),_id, msg.sender, difference);
        assert(!isSuccess);
        return difference;
    }

    /*
    * SKC兑换游戏积分
    */
    function redeemGamePoints(uint256 _id, address _caller, uint _amountOfTokens)
    public
    returns (bool)
    {
        // Only BankROll contract
        require(msg.sender == bankrollAddress);
        require(frontTokenBalanceLedger[_caller] >= _amountOfTokens);

        //require(regularPhase);

        // Calculate how many back-end dividend tokens to transfer.
        // This amount is proportional to the caller's average dividend rate multiplied by the proportion of tokens being transferred.
        uint _amountOfDivTokens = _amountOfTokens.mul(getUserAverageDividendRate(_caller)).div(magnitude);

        // Exchange tokens
        frontTokenBalanceLedger[_caller] = frontTokenBalanceLedger[_caller].sub(_amountOfTokens);
        frontTokenBalanceLedger[bankrollAddress] = frontTokenBalanceLedger[bankrollAddress].add(_amountOfTokens);
        dividendTokenBalanceLedger_[_caller] = dividendTokenBalanceLedger_[_caller].sub(_amountOfDivTokens);
        dividendTokenBalanceLedger_[bankrollAddress] = dividendTokenBalanceLedger_[bankrollAddress].add(_amountOfDivTokens);

        emit RedeemGamePoints(_id, _caller, bankrollAddress, _amountOfTokens);
        return true;
    }

    /*
    * 将当前累积的Token分给当前的持币用户
    */
    function divide()
    public
    onlyAdministrator
    {
        if(dividendTotalToken == 0) {
            return;
        }

        uint _dividendTotalToken = dividendTotalToken;
        uint allToken;
        for (uint i = 0; i < holders.length; i++) {
            address holder = holders[i];
            if(frontTokenBalanceLedger[holder] > 0) {
                uint reciveToken = dividendTotalToken.mul(dividendTokenBalanceLedger_[holder]).div(divTokenSupply);
                uint dividendToken = reciveToken.mul(dividendTokenBalanceLedger_[holder]).div(divTokenSupply);
                frontTokenBalanceLedger[holder] = frontTokenBalanceLedger[holder].add(reciveToken);
                dividendTokenBalanceLedger_[holder] = dividendTokenBalanceLedger_[holder].add(dividendToken);
                allToken += reciveToken;
            }
        }

        assert(allToken == dividendTotalToken);

        dividendTotalToken = 0;

        emit Divide(msg.sender, _dividendTotalToken, holders.length);
    }

    function addOrUpdateHolder(address _holderAddr) 
    internal
    {
        // Check and add holder to array
        if (holderIndex[_holderAddr] == 0) {
            holderIndex[_holderAddr] = holders.length++;
            holders[holderIndex[_holderAddr]] = _holderAddr;
        }
    }

    /**
     * ETH购买SKC，并设置选择的股息率
     * Same as buy, but explicitly sets your dividend percentage.   
     * If this has been called before, it will update your `default' dividend
     *   percentage for regular buy transactions going forward.
     */
    function buyAndSetDivPercentage(address _referredBy, uint8 _divChoice)
    public
    payable
    returns (uint)
    {
        require(icoPhase || regularPhase);

        if (icoPhase) {

            // Anti-bot measures - not perfect, but should help some.
            //bytes32 hashProvidedPass = keccak256(providedUnhashedPass);
            //require(hashProvidedPass == icoHashedPass);

            uint gasPrice = tx.gasprice;

            // Prevents ICO buyers from getting substantially burned if the ICO is reached
            //   before their transaction is processed.
            require(gasPrice <= icoMaxGasPrice && ethInvestedDuringICO <= icoHardCap);

        }

        // Dividend percentage should be a currently accepted value.
        require(validDividendRates[_divChoice]);

        // Set the dividend fee percentage denominator.
        userSelectedRate[msg.sender] = true;
        userDividendRate[msg.sender] = _divChoice;
        emit UserDividendRate(msg.sender, _divChoice);

        // Finally, purchase tokens.
        purchaseTokens(msg.value, _referredBy);
    }

    // All buys except for the above one require regular phase.
    /**
     * 使用上一次选择的股息率购买SKC
     */
    function buy(address _referredBy)
    public
    payable
    returns (uint)
    {
        require(regularPhase);
        address _customerAddress = msg.sender;
        require(userSelectedRate[_customerAddress]);
        purchaseTokens(msg.value, _referredBy);
    }

    /** 
     * ETH购买SKC后，将SKC转账给target账户
     */
    function buyAndTransfer(address _referredBy, address target)
    public
    payable
    {
        bytes memory empty;
        buyAndTransfer(_referredBy, target, empty, 20);
    }

    /** 
     * ETH购买SKC后，将SKC转账给target账户
     */
    function buyAndTransfer(address _referredBy, address target, bytes _data)
    public
    payable
    {
        buyAndTransfer(_referredBy, target, _data, 20);
    }

    /** 
     * ETH购买SKC后，将SKC转账给target账户
     */
    function buyAndTransfer(address _referredBy, address target, bytes _data, uint8 divChoice)
    public
    payable
    {
        require(regularPhase);
        address _customerAddress = msg.sender;
        uint256 frontendBalance = frontTokenBalanceLedger[msg.sender];
        if (userSelectedRate[_customerAddress] && divChoice == 0) {
            purchaseTokens(msg.value, _referredBy);
        } else {
            buyAndSetDivPercentage(_referredBy, divChoice);
        }
        uint256 difference = SafeMath.sub(frontTokenBalanceLedger[msg.sender], frontendBalance);
        transferTo(msg.sender, target, difference, _data);
    }

    // Fallback function only works during regular phase - part of anti-bot protection.
    function()
    payable
    public
    {
        /**
        / If the user has previously set a dividend rate, sending
        /   Ether directly to the contract simply purchases more at
        /   the most recent rate. If this is their first time, they
        /   are automatically placed into the 20% rate `bucket'.
        **/
        require(regularPhase);
        address _customerAddress = msg.sender;
        if (userSelectedRate[_customerAddress]) {
            purchaseTokens(msg.value, 0x0);
        } else {
            buyAndSetDivPercentage(0x0, 20);
        }
    }

    /**
     * 退出项目，所有SKC转为ETH
     */
    function exit()
    public
    {

        require(regularPhase);
        // Retrieve token balance for caller, then sell them all.
        address _customerAddress = msg.sender;
        uint _tokens = frontTokenBalanceLedger[_customerAddress];

        if (_tokens > 0) sell(_tokens);

        withdraw(_customerAddress);
    }

    /**
     * 暂时不支持
     */
    function withdraw(address _recipient)
    dividendHolder()
    public
    {
        require(regularPhase);
        // Setup data
        address _customerAddress = msg.sender;
        uint _dividends = myDividends(false);

        // update dividend tracker
        payoutsTo_[_customerAddress] += (int256) (_dividends * magnitude);

        // add ref. bonus
        _dividends += referralBalance_[_customerAddress];
        referralBalance_[_customerAddress] = 0;

        if (_recipient == address(0x0)) {
            _recipient = msg.sender;
        }
        _recipient.transfer(_dividends);

        // Fire logging event.
        emit OnWithdraw(_recipient, _dividends);
    }

    // Sells front-end tokens.
    // Logic concerning step-pricing of tokens pre/post-ICO is encapsulated in tokensToEthereum_.
    /**
     * 将Token卖成ETH
     */
    function sell(uint _amountOfTokens)
    onlyHolders()
    public
    {
        // No selling during the ICO. You don't get to flip that fast, sorry!
        require(!icoPhase);
        require(regularPhase);

        require(_amountOfTokens <= frontTokenBalanceLedger[msg.sender]);

        uint _frontEndTokensToBurn = _amountOfTokens;

        uint _sellPrice = sellPrice();

        // Calculate how many dividend tokens this action burns.
        // Computed as the caller's average dividend rate multiplied by the number of front-end tokens held.
        // As an additional guard, we ensure that the dividend rate is between 2 and 50 inclusive.
        uint userDivRate = getUserAverageDividendRate(msg.sender);
        require((2 * magnitude) <= userDivRate && (50 * magnitude) >= userDivRate);
        uint _divTokensToBurn = (_frontEndTokensToBurn.mul(userDivRate)).div(magnitude);

        // Calculate ethereum received before dividends
        uint _ethereum = tokensToEthereum_(_frontEndTokensToBurn);

        if (_ethereum > currentEthInvested) {
            // Well, congratulations, you've emptied the coffers.
            currentEthInvested = 0;
        } else {currentEthInvested = currentEthInvested - _ethereum;}

        // Calculate dividends generated from the sale.
        uint _dividends = (_ethereum.mul(getUserAverageDividendRate(msg.sender)).div(100)).div(magnitude);

        // Calculate Ethereum receivable net of dividends.
        uint _taxedEthereum = _ethereum.sub(_dividends);

        // Burn the sold tokens (both front-end and back-end variants).
        tokenSupply = tokenSupply.sub(_frontEndTokensToBurn);
        divTokenSupply = divTokenSupply.sub(_divTokensToBurn);

        // Subtract the token balances for the seller
        frontTokenBalanceLedger[msg.sender] = frontTokenBalanceLedger[msg.sender].sub(_frontEndTokensToBurn);
        dividendTokenBalanceLedger_[msg.sender] = dividendTokenBalanceLedger_[msg.sender].sub(_divTokensToBurn);

        // wj need to be confirmed
        // Update dividends tracker
        int256 _updatedPayouts = (int256) (profitPerDivToken * _divTokensToBurn + (_taxedEthereum * magnitude));
        payoutsTo_[msg.sender] -= _updatedPayouts;

        // Let's avoid breaking arithmetic where we can, eh?
        if (divTokenSupply > 0) {
            // Update the value of each remaining back-end dividend token.
            profitPerDivToken = profitPerDivToken.add((_dividends * magnitude) / divTokenSupply);
        }

        // Fire logging event.
        emit OnTokenSell(msg.sender, _taxedEthereum, _frontEndTokensToBurn, _sellPrice, userDivRate);
    }

    /**
     * Token的转账功能
     * Transfer tokens from the caller to a new holder.
     * No charge incurred for the transfer. We'd make a terrible bank.
     */
    function transfer(address _toAddress, uint _amountOfTokens)
    onlyHolders()
    public
    returns (bool)
    {
        require(_amountOfTokens >= MIN_TOKEN_TRANSFER
        && _amountOfTokens <= frontTokenBalanceLedger[msg.sender]);
        bytes memory empty;
        transferFromInternal(msg.sender, _toAddress, _amountOfTokens, empty);
        return true;

    }

    /**
     * ERC20的授权函数
     */
    function approve(address spender, uint tokens)
    public
    returns (bool)
    {
        address _customerAddress = msg.sender;
        allowed[_customerAddress][spender] = tokens;

        // Fire logging event.
        emit Approval(_customerAddress, spender, tokens);

        // Good old ERC20.
        return true;
    }

    /**
     * Transfer tokens from the caller to a new holder: the Used By Smart Contracts edition.
     * No charge incurred for the transfer. No seriously, we'd make a terrible bank.
     */
    function transferFrom(address _from, address _toAddress, uint _amountOfTokens)
    public
    returns (bool)
    {
        // Setup variables
        address _customerAddress = _from;
        bytes memory empty;
        // Make sure we own the tokens we're transferring, are ALLOWED to transfer that many tokens,
        // and are transferring at least one full token.
        require(_amountOfTokens >= MIN_TOKEN_TRANSFER
        && _amountOfTokens <= frontTokenBalanceLedger[_customerAddress]
        && _amountOfTokens <= allowed[_customerAddress][msg.sender]);

        transferFromInternal(_from, _toAddress, _amountOfTokens, empty);

        // Good old ERC20.
        return true;

    }

    function transferTo(address _from, address _to, uint _amountOfTokens, bytes _data)
    public
    {
        if (_from != msg.sender) {
            require(_amountOfTokens >= MIN_TOKEN_TRANSFER
            && _amountOfTokens <= frontTokenBalanceLedger[_from]
            && _amountOfTokens <= allowed[_from][msg.sender]);
        }
        else {
            require(_amountOfTokens >= MIN_TOKEN_TRANSFER
            && _amountOfTokens <= frontTokenBalanceLedger[_from]);
        }

        transferFromInternal(_from, _to, _amountOfTokens, _data);
    }

    // Anyone can start the regular phase 2 weeks after the ICO phase starts.
    // In case the devs die. Or something.
    /**
     * 手动结束ICO阶段，进入正常阶段
     */
    function publicStartRegularPhase()
    public
    {
        require(now > (icoOpenTime + 2 weeks) && icoOpenTime != 0);

        icoPhase = false;
        regularPhase = true;
    }

    /*----------  ADMINISTRATOR ONLY FUNCTIONS  ----------*/


    // Fire the starting gun and then duck for cover.
    /**
     * 开启ICO阶段
     */
    function startICOPhase()
    onlyAdministrator()
    public
    {
        // Prevent us from startaring the ICO phase again
        require(icoOpenTime == 0);
        icoPhase = true;
        icoOpenTime = now;
    }

    // Fire the ... ending gun?
    /**
     * 结束ICO阶段
     */
    function endICOPhase()
    onlyAdministrator()
    public
    {
        icoPhase = false;
    }

    function startRegularPhase()
    onlyAdministrator
    public
    {
        // disable ico phase in case if that was not disabled yet
        icoPhase = false;
        regularPhase = true;
    }

    // The death of a great man demands the birth of a great son.
    /**
     * 更新管理员状态
     */
    function setAdministrator(address _newAdmin, bool _status)
    onlyAdministrator()
    public
    {
        administrators[_newAdmin] = _status;
    }

    /** 
    * 设置能够获取推荐费的最小持币数量
    */
    function setStakingRequirement(uint _amountOfTokens)
    onlyAdministrator()
    public
    {
        // This plane only goes one way, lads. Never below the initial.
        require(_amountOfTokens >= 100e18);
        stakingRequirement = _amountOfTokens;
    }

    function setName(string _name)
    onlyAdministrator()
    public
    {
        name = _name;
    }

    function setSymbol(string _symbol)
    onlyAdministrator()
    public
    {
        symbol = _symbol;
    }

    /*----------  HELPERS AND CALCULATORS  ----------*/

    /**
     * 获取用户当前默认的股息率
     * Retrieves your currently selected dividend rate.
     */
    function getMyDividendRate()
    public
    view
    returns (uint8)
    {
        address _customerAddress = msg.sender;
        require(userSelectedRate[_customerAddress]);
        return userDividendRate[_customerAddress];
    }

    /**
     * 当前分成Token的总数量，类似于发行的总的股份数
     * Retreive the total dividend token supply
     */
    function getDividendTokenSupply()
    public
    view
    returns (uint)
    {
        return divTokenSupply;
    }

    /**
     * 获取用户的分成Token数
     * Retrieve the dividend tokens owned by the caller
     */
    function myDividendTokens()
    public
    view
    returns (uint)
    {
        address _customerAddress = msg.sender;
        return getDividendTokenBalanceOf(_customerAddress);
    }

    /**
     * 当前的推荐奖励
     */
    function myReferralDividends()
    public
    view
    returns (uint)
    {
        return myDividends(true) - myDividends(false);
    }

    /**
     * 获取当前的分成数量
     * 包含推荐的奖励
     */
    function myDividends(bool _includeReferralBonus)
    public
    view
    returns (uint)
    {
        address _customerAddress = msg.sender;
        return _includeReferralBonus ? dividendsOf(_customerAddress) + referralBalance_[_customerAddress] : dividendsOf(_customerAddress);
    }

    function theDividendsOf(bool _includeReferralBonus, address _customerAddress)
    public
    view
    returns (uint)
    {
        return _includeReferralBonus ? dividendsOf(_customerAddress) + referralBalance_[_customerAddress] : dividendsOf(_customerAddress);
    }



    function getDividendTokenBalanceOf(address _customerAddress)
    view
    public
    returns (uint)
    {
        return dividendTokenBalanceLedger_[_customerAddress];
    }

    function dividendsOf(address _customerAddress)
    view
    public
    returns (uint)
    {
        return (uint) ((int256)(profitPerDivToken * dividendTokenBalanceLedger_[_customerAddress]) - payoutsTo_[_customerAddress]) / magnitude;
    }

    // Get the sell price at the user's average dividend rate
    /**
     * 获取当前的售卖价格,以卖出0.001 ether计算
     */
    function sellPrice()
    public
    view
    returns (uint)
    {
        uint price;

        if (icoPhase || currentEthInvested < ethInvestedDuringICO) {
            price = tokenPriceInitial_;
        } else {

            // Calculate the tokens received for 100 finney.
            // Divide to find the average, to calculate the price.
            uint tokensReceivedForEth = ethereumToTokens_(0.001 ether);

            price = (1e18 * 0.001 ether) / tokensReceivedForEth;
        }

        // Factor in the user's average dividend rate
        uint theSellPrice = price.sub((price.mul(getUserAverageDividendRate(msg.sender)).div(100)).div(magnitude));

        return theSellPrice;
    }

    // Get the buy price at a particular dividend rate
    /**
     * 获取当前的购买价格
     */
    function buyPrice(uint dividendRate)
    public
    view
    returns (uint)
    {
        uint price;

        if (icoPhase || currentEthInvested < ethInvestedDuringICO) {
            price = tokenPriceInitial_;
        } else {

            // Calculate the tokens received for 100 finney.
            // Divide to find the average, to calculate the price.
            uint tokensReceivedForEth = ethereumToTokens_(0.001 ether);

            price = (1e18 * 0.001 ether) / tokensReceivedForEth;
        }

        // Factor in the user's selected dividend rate
        uint theBuyPrice = (price.mul(dividendRate).div(100)).add(price);

        return theBuyPrice;
    }

    /**
     * 计算当前用一定量的ether能够买到的SKC数量
     */
    function calculateTokensReceived(uint _ethereumToSpend)
    public
    view
    returns (uint)
    {
        uint _dividends = (_ethereumToSpend.mul(userDividendRate[msg.sender])).div(100);
        uint _taxedEthereum = _ethereumToSpend.sub(_dividends);
        uint _amountOfTokens = ethereumToTokens_(_taxedEthereum);
        return _amountOfTokens;
    }

    // When selling tokens, we need to calculate the user's current dividend rate.
    // This is different from their selected dividend rate.
    /**
     * 计算当前卖出一定量的SKC能够得到ether的数量
     */
    function calculateEthereumReceived(uint _tokensToSell)
    public
    view
    returns (uint)
    {
        require(_tokensToSell <= tokenSupply);
        uint _ethereum = tokensToEthereum_(_tokensToSell);
        uint userAverageDividendRate = getUserAverageDividendRate(msg.sender);
        uint _dividends = (_ethereum.mul(userAverageDividendRate).div(100)).div(magnitude);
        uint _taxedEthereum = _ethereum.sub(_dividends);
        return _taxedEthereum;
    }

    /*
     * 计算用户的平均股息率
     * Get's a user's average dividend rate - which is just their divTokenBalance / tokenBalance
     * We multiply by magnitude to avoid precision errors.
     */
    function getUserAverageDividendRate(address user) public view returns (uint) {
        return (magnitude * dividendTokenBalanceLedger_[user]).div(frontTokenBalanceLedger[user]);
    }

    function getMyAverageDividendRate() public view returns (uint) {
        return getUserAverageDividendRate(msg.sender);
    }

    /*==========================================
    =            INTERNAL FUNCTIONS            =
    ==========================================*/

    /* Purchase tokens with Ether.
       During ICO phase, dividends should go to the bankroll
       During normal operation:
         0.5% should go to the master dividend card
         0.5% should go to the matching dividend card
         25% of dividends should go to the referrer, if any is provided. */
    function purchaseTokens(uint _incomingEthereum, address _referredBy)
    internal
    returns (uint)
    {
        require(_incomingEthereum >= MIN_ETH_BUYIN || msg.sender == bankrollAddress, "Tried to buy below the min eth buyin threshold.");

        //uint toReferrer;
        //uint toTokenHolders;
        //uint toPlatform;
        //uint toPlatformToken;

        //uint dividendAmount;

        uint tokensBought;
        //uint dividendTokensBought;

        //uint remainingEth = _incomingEthereum;

        //uint fee;

        uint tokenPrice = buyPrice(userDividendRate[msg.sender]);

        uint8 dividendRate = userDividendRate[msg.sender];

        // 2% for platform is taken off before anything else
        //if (regularPhase) {
            //toPlatform = remainingEth.div(100).mul(2);
            //remainingEth = remainingEth.sub(toPlatform);
        //} else {
            // If ICO phase, all the dividends go to the platform
            //toPlatform = remainingEth.div(100).mul(dividendRate);
            //remainingEth = remainingEth.sub(toPlatform);
        //}

        
        //tokensBought = ethereumToTokens_(remainingEth);
        //tokenSupply = tokenSupply.add(tokensBought);
        
        // tokens should be dividended to the other user
        //if (regularPhase) {
            //dividendAmount = tokensBought.mul(dividendRate).div(100);
            //tokensBought = tokensBought.sub(dividendAmount);
        //}

        //the token user finnally bought
        //dividendTokensBought = tokensBought.mul(dividendRate);
        
        //currentEthInvested = currentEthInvested.add(remainingEth);

        // If ICO phase, all the dividends go to the platform
        //if (icoPhase) {
            //toReferrer = 0;
            //toTokenHolders = 0;

            /* ethInvestedDuringICO tracks how much Ether goes straight to tokens,
               not how much Ether we get total.
               this is so that our calculation using "investment" is accurate. */
            //ethInvestedDuringICO = ethInvestedDuringICO + remainingEth;
            //tokensMintedDuringICO = tokensMintedDuringICO + tokensBought;

            // Cannot purchase more than the hard cap during ICO.
            //require(ethInvestedDuringICO <= icoHardCap);
            // Contracts aren't allowed to participate in the ICO.
            //require(tx.origin == msg.sender);

            // Cannot purchase more then the limit per address during the ICO.
            //ICOBuyIn[msg.sender] += remainingEth;
            //require(ICOBuyIn[msg.sender] <= addressICOLimit);

            // Stop the ICO phase if we reach the hard cap
            //if (ethInvestedDuringICO == icoHardCap) {
                //icoPhase = false;
            //}

        //} else {
            // Not ICO phase, check for referrals

            // 30% goes to referrers, if set
            // toReferrer = (dividends * 30)/100
            //if (_referredBy != 0x0000000000000000000000000000000000000000 &&
            //_referredBy != msg.sender &&
            //frontTokenBalanceLedger[_referredBy] >= stakingRequirement)
            //{
                //toReferrer = (dividendAmount.mul(referrer_percentage)).div(100);
                //frontTokenBalanceLedger[_referredBy] = frontTokenBalanceLedger[_referredBy].add(toReferrer);
               // emit Referral(_referredBy, toReferrer);
            //}

            // wj read again!!

            // The rest of the dividends go to token holders
            //toTokenHolders = (dividendAmount.mul(user_percentage)).div(100);
            //toPlatformToken = (dividendAmount.sub(toReferrer)).sub(toTokenHolders);

            //dividendTotalToken = dividendTotalToken.add(toTokenHolders);

            // wj the really fee is = dividendTokensBought * (toTokenHolders * magnitude / (divTokenSupply))?
            //fee = toTokenHolders * magnitude;
            //fee = fee - (fee - (dividendTokensBought * (toTokenHolders * magnitude / (divTokenSupply))));

            // Finally, increase the divToken value
            //profitPerDivToken = profitPerDivToken.add((toTokenHolders.mul(magnitude)).div(divTokenSupply));
            //payoutsTo_[msg.sender] += (int256) (profitPerDivToken * dividendTokensBought);
        //}

        // Update the buyer's token amounts
        //frontTokenBalanceLedger[msg.sender] = frontTokenBalanceLedger[msg.sender].add(tokensBought);
        //dividendTokenBalanceLedger_[msg.sender] = dividendTokenBalanceLedger_[msg.sender].add(dividendTokensBought);

        //addOrUpdateHolder(msg.sender);

        // Transfer to platform
        //if (toPlatform != 0) {platformAddress.transfer(toPlatform);}
        //if (toPlatformToken != 0) {frontTokenBalanceLedger[platformAddress] = frontTokenBalanceLedger[platformAddress].add(toPlatformToken);}

        // checking
       // uint sum = toPlatform + remainingEth - _incomingEthereum;
       // assert(sum == 0);
       // sum = toPlatformToken + toReferrer + toTokenHolders - tokensBought;
       // assert(sum == 0);

        emit OnTokenPurchase(msg.sender, _incomingEthereum, tokensBought, tokenPrice, dividendRate, _referredBy);
    }

    // How many tokens one gets from a certain amount of ethereum.
    /**
     * 一定量的ether能换多少SKC，此方法未扣除平台抽成和股息率部分
     */
    function ethereumToTokens_(uint _ethereumAmount)
    public
    view
    returns (uint)
    {
        require(_ethereumAmount > MIN_ETH_BUYIN, "Tried to buy tokens with too little eth.");

        if (icoPhase) {
            return _ethereumAmount.div(tokenPriceInitial_) * 1e18;
        }

        /*
         *  i = investment, p = price, t = number of tokens
         *
         *  i_current = p_initial * t_current                   (for t_current <= t_initial)
         *  i_current = i_initial + (2/3)(t_current)^(3/2)      (for t_current >  t_initial)
         *
         *  t_current = i_current / p_initial                   (for i_current <= i_initial)
         *  t_current = t_initial + ((3/2)(i_current))^(2/3)    (for i_current >  i_initial)
         */

        // First, separate out the buy into two segments:
        //  1) the amount of eth going towards ico-price tokens
        //  2) the amount of eth going towards pyramid-price (variable) tokens
        uint ethTowardsICOPriceTokens = 0;
        uint ethTowardsVariablePriceTokens = 0;

        if (currentEthInvested >= ethInvestedDuringICO) {
            // Option One: All the ETH goes towards variable-price tokens
            ethTowardsVariablePriceTokens = _ethereumAmount;

        } else if (currentEthInvested < ethInvestedDuringICO && currentEthInvested + _ethereumAmount <= ethInvestedDuringICO) {
            // Option Two: All the ETH goes towards ICO-price tokens
            ethTowardsICOPriceTokens = _ethereumAmount;

        } else if (currentEthInvested < ethInvestedDuringICO && currentEthInvested + _ethereumAmount > ethInvestedDuringICO) {
            // Option Three: Some ETH goes towards ICO-price tokens, some goes towards variable-price tokens
            ethTowardsICOPriceTokens = ethInvestedDuringICO.sub(currentEthInvested);
            ethTowardsVariablePriceTokens = _ethereumAmount.sub(ethTowardsICOPriceTokens);
        } else {
            // Option Four: Should be impossible, and compiler should optimize it out of existence.
            revert();
        }

        // Sanity check:
        assert(ethTowardsICOPriceTokens + ethTowardsVariablePriceTokens == _ethereumAmount);

        // Separate out the number of tokens of each type this will buy:
        uint icoPriceTokens = 0;
        uint varPriceTokens = 0;

        // Now calculate each one per the above formulas.
        // Note: since tokens have 18 decimals of precision we multiply the result by 1e18.
        if (ethTowardsICOPriceTokens != 0) {
            icoPriceTokens = ethTowardsICOPriceTokens.mul(1e18).div(tokenPriceInitial_);
        }

        if (ethTowardsVariablePriceTokens != 0) {
            // Note: we can't use "currentEthInvested" for this calculation, we must use:
            //  currentEthInvested + ethTowardsICOPriceTokens
            // This is because a split-buy essentially needs to simulate two separate buys -
            // including the currentEthInvested update that comes BEFORE variable price tokens are bought!

            uint simulatedEthBeforeInvested = toPowerOfThreeHalves(tokenSupply.div(MULTIPLIER * 1e6)).mul(2).div(3) + ethTowardsICOPriceTokens;
            uint simulatedEthAfterInvested = simulatedEthBeforeInvested + ethTowardsVariablePriceTokens;

            /* We have the equations for total tokens above; note that this is for TOTAL.
               To get the number of tokens this purchase buys, use the simulatedEthInvestedBefore
               and the simulatedEthInvestedAfter and calculate the difference in tokens.
               This is how many we get. */

            uint tokensBefore = toPowerOfTwoThirds(simulatedEthBeforeInvested.mul(3).div(2)).mul(MULTIPLIER);
            uint tokensAfter = toPowerOfTwoThirds(simulatedEthAfterInvested.mul(3).div(2)).mul(MULTIPLIER);

            /* Note that we could use tokensBefore = tokenSupply + icoPriceTokens instead of dynamically calculating tokensBefore;
               either should work.

               Investment IS already multiplied by 1e18; however, because this is taken to a power of (2/3),
               we need to multiply the result by 1e6 to get back to the correct number of decimals. */

            varPriceTokens = (1e6) * tokensAfter.sub(tokensBefore);
        }

        uint totalTokensReceived = icoPriceTokens + varPriceTokens;

        assert(totalTokensReceived > 0);
        return totalTokensReceived;
    }

    // How much Ether we get from selling N tokens
    /**
     * 一定量的SKC能换多少Ether，此方法未扣除平台抽成和股息率部分
     */
    function tokensToEthereum_(uint _tokens)
    public
    view
    returns (uint)
    {
        require(_tokens >= MIN_TOKEN_SELL_AMOUNT, "Tried to sell too few tokens.");

        /*
         *  i = investment, p = price, t = number of tokens
         *
         *  i_current = p_initial * t_current                   (for t_current <= t_initial)
         *  i_current = i_initial + (2/3)(t_current)^(3/2)      (for t_current >  t_initial)
         *
         *  t_current = i_current / p_initial                   (for i_current <= i_initial)
         *  t_current = t_initial + ((3/2)(i_current))^(2/3)    (for i_current >  i_initial)
         */

        // First, separate out the sell into two segments:
        //  1) the amount of tokens selling at the ICO price.
        //  2) the amount of tokens selling at the variable (pyramid) price
        uint tokensToSellAtICOPrice = 0;
        uint tokensToSellAtVariablePrice = 0;

        if (tokenSupply <= tokensMintedDuringICO) {
            // Option One: All the tokens sell at the ICO price.
            tokensToSellAtICOPrice = _tokens;

        } else if (tokenSupply > tokensMintedDuringICO && tokenSupply - _tokens >= tokensMintedDuringICO) {
            // Option Two: All the tokens sell at the variable price.
            tokensToSellAtVariablePrice = _tokens;

        } else if (tokenSupply > tokensMintedDuringICO && tokenSupply - _tokens < tokensMintedDuringICO) {
            // Option Three: Some tokens sell at the ICO price, and some sell at the variable price.
            tokensToSellAtVariablePrice = tokenSupply.sub(tokensMintedDuringICO);
            tokensToSellAtICOPrice = _tokens.sub(tokensToSellAtVariablePrice);

        } else {
            // Option Four: Should be impossible, and the compiler should optimize it out of existence.
            revert();
        }

        // Sanity check:
        assert(tokensToSellAtVariablePrice + tokensToSellAtICOPrice == _tokens);

        // Track how much Ether we get from selling at each price function:
        uint ethFromICOPriceTokens;
        uint ethFromVarPriceTokens;

        // Now, actually calculate:

        if (tokensToSellAtICOPrice != 0) {

            /* Here, unlike the sister equation in ethereumToTokens, we DON'T need to multiply by 1e18, since
               we will be passed in an amount of tokens to sell that's already at the 18-decimal precision.
               We need to divide by 1e18 or we'll have too much Ether. */

            ethFromICOPriceTokens = tokensToSellAtICOPrice.mul(tokenPriceInitial_).div(1e18);
        }

        if (tokensToSellAtVariablePrice != 0) {

            /* Note: Unlike the sister function in ethereumToTokens, we don't have to calculate any "virtual" token count.
               This is because in sells, we sell the variable price tokens **first**, and then we sell the ICO-price tokens.
               Thus there isn't any weird stuff going on with the token supply.

               We have the equations for total investment above; note that this is for TOTAL.
               To get the eth received from this sell, we calculate the new total investment after this sell.
               Note that we divide by 1e6 here as the inverse of multiplying by 1e6 in ethereumToTokens. */

            uint investmentBefore = toPowerOfThreeHalves(tokenSupply.div(MULTIPLIER * 1e6)).mul(2).div(3);
            uint investmentAfter = toPowerOfThreeHalves((tokenSupply - tokensToSellAtVariablePrice).div(MULTIPLIER * 1e6)).mul(2).div(3);

            ethFromVarPriceTokens = investmentBefore.sub(investmentAfter);
        }

        uint totalEthReceived = ethFromVarPriceTokens + ethFromICOPriceTokens;

        assert(totalEthReceived > 0);
        return totalEthReceived;
    }

    function transferFromInternal(address _from, address _toAddress, uint _amountOfTokens, bytes _data)
    internal
    {
        // wj delete _data
        if(_data.length != 0) {
            return;
        }
        require(regularPhase);
        require(_toAddress != address(0x0));
        address _customerAddress = _from;
        uint _amountOfFrontEndTokens = _amountOfTokens;

        // Withdraw all outstanding dividends first (including those generated from referrals).
        if (theDividendsOf(true, _customerAddress) > 0) withdrawFrom(_customerAddress);

        // Calculate how many back-end dividend tokens to transfer.
        // This amount is proportional to the caller's average dividend rate multiplied by the proportion of tokens being transferred.
        uint _amountOfDivTokens = _amountOfFrontEndTokens.mul(getUserAverageDividendRate(_customerAddress)).div(magnitude);

        if (_customerAddress != msg.sender) {
            // Update the allowed balance.
            // Don't update this if we are transferring our own tokens (via transfer or buyAndTransfer)
            allowed[_customerAddress][msg.sender] -= _amountOfTokens;
        }

        // Exchange tokens
        frontTokenBalanceLedger[_customerAddress] = frontTokenBalanceLedger[_customerAddress].sub(_amountOfFrontEndTokens);
        frontTokenBalanceLedger[_toAddress] = frontTokenBalanceLedger[_toAddress].add(_amountOfFrontEndTokens);
        dividendTokenBalanceLedger_[_customerAddress] = dividendTokenBalanceLedger_[_customerAddress].sub(_amountOfDivTokens);
        dividendTokenBalanceLedger_[_toAddress] = dividendTokenBalanceLedger_[_toAddress].add(_amountOfDivTokens);

        // Update Token holders
        addOrUpdateHolder(_customerAddress);
        addOrUpdateHolder(_toAddress);

        // Recipient inherits dividend percentage if they have not already selected one.
        if (!userSelectedRate[_toAddress])
        {
            userSelectedRate[_toAddress] = true;
            userDividendRate[_toAddress] = userDividendRate[_customerAddress];
        }

        // Update dividend trackers
        payoutsTo_[_customerAddress] -= (int256) (profitPerDivToken * _amountOfDivTokens);
        payoutsTo_[_toAddress] += (int256) (profitPerDivToken * _amountOfDivTokens);

        // Fire logging event.
        emit Transfer(_customerAddress, _toAddress, _amountOfFrontEndTokens);
    }

    // Called from transferFrom. Always checks if _customerAddress has dividends.
    function withdrawFrom(address _customerAddress)
    internal
    {
        // Setup data
        uint _dividends = theDividendsOf(false, _customerAddress);

        // update dividend tracker
        payoutsTo_[_customerAddress] += (int256) (_dividends * magnitude);

        // add ref. bonus
        _dividends += referralBalance_[_customerAddress];
        referralBalance_[_customerAddress] = 0;

        _customerAddress.transfer(_dividends);

        // Fire logging event.
        emit OnWithdraw(_customerAddress, _dividends);
    }

    /*=======================
     =    RESET FUNCTIONS   =
     ======================*/

    function injectEther()
    public
    payable
    onlyAdministrator
    {

    }

    /*=======================
     =   MATHS FUNCTIONS    =
     ======================*/

    function toPowerOfThreeHalves(uint x) public pure returns (uint) {
        // m = 3, n = 2
        // sqrt(x^3)
        return sqrt(x ** 3);
    }

    function toPowerOfTwoThirds(uint x) public pure returns (uint) {
        // m = 2, n = 3
        // cbrt(x^2)
        return cbrt(x ** 2);
    }

    function sqrt(uint x) public pure returns (uint y) {
        uint z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    function cbrt(uint x) public pure returns (uint y) {
        uint z = (x + 1) / 3;
        y = x;
        while (z < y) {
            y = z;
            z = (x / (z * z) + 2 * z) / 3;
        }
    }
}

/*=======================
 =     INTERFACES       =
 ======================*/


library SafeMath {

    function mul(uint a, uint b) internal pure returns (uint) {
        if (a == 0) {
            return 0;
        }
        uint c = a * b;
        assert(c / a == b);
        return c;
    }

    function div(uint a, uint b) internal pure returns (uint) {
        uint c = a / b;
        return c;
    }

    function sub(uint a, uint b) internal pure returns (uint) {
        assert(b <= a);
        return a - b;
    }

    function add(uint a, uint b) internal pure returns (uint) {
        uint c = a + b;
        assert(c >= a);
        return c;
    }
}

/** Note
 * 1.平台获取的Token需要参与分成
 * 2.支持用户手动提取分成，统一分成时就没有
 */