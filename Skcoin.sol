pragma solidity ^0.4.23;


contract Skcoin {
  using SafeMath for uint;

  /*=====================================
  =            CONSTANTS                =
  =====================================*/

  uint8 constant public                decimals              = 18;//精度

  uint constant internal               tokenPriceInitial     = 0.000653 ether;//SKY初始价
  uint constant internal               magnitude             = 2**64;//量级精度

  uint constant internal               icoHardCap            = 250 ether;//ICO硬顶
  uint constant internal               icoMaxBuyIn           = 1   ether;//单个地址的ICO最大购买数量
  uint constant internal               icoMinBuyIn           = 0.1 finney;//单个地址的ICO最小购买数量
  uint constant internal               icoMaxGasPrice        = 50000000000 wei;//ICO的Gas单价

  uint constant internal               MULTIPLIER            = 9615;//增量精度
  uint constant internal               MIN_ETH_BUYIN         = 0.0001 ether;//最小Ether购买数量
  uint constant internal               MIN_TOKEN_SELL_AMOUNT = 0.0001 ether;//最小Token售卖数量
  uint constant internal               MIN_TOKEN_TRANSFER    = 1e10;//最小Token转账数量
  uint constant internal               REFERAL_REWARD        = 25; //推荐奖励


  /*================================
   =          CONFIGURABLES         =
   ================================*/

  string public                        name               = "Skcoin"; //名称
  string public                        symbol             = "SKY";    //缩写
  uint internal                        tokenSupply        = 0;        //供应量

  mapping(address => mapping (address => uint)) public allowed;
  mapping(address => bool) public      administrators; //管理员列表

  bytes32 constant public              icoHashedPass      = bytes32(0x5ddcde33b94b19bdef79dd9ea75be591942b9ec78286d64b44a356280fb6a262);

  address internal                     reserveAddress; //Ether储备金地址
  address internal                     platformAddress; //平台的收益地址


  /*================================
   =            DATA               =
   ================================*/

  mapping(address => uint)    internal dividendTokenLedger; //分红账本
  mapping(address => uint)    internal referralLedger; //推荐账本
  mapping(address => int256)  internal payoutsLedger; //支付账本
  mapping(address => uint)    internal icoBuyInLedger; //ICO认购记录账本

  mapping(uint8   => bool)    internal validDividendRates; //预设的分红比率
  mapping(address => bool)    internal userSelectedRate; //用户选择的分红比率
  mapping(address => uint8)   internal userDividendRate; //用户最终的分红比率

  uint public                          icoMintedTokens; //ICO发行的Token数量
  uint public                          icoInvestedEther; //ICO认购的Ether数量
  uint public                          currentEthInvested; //最新的Ether认购数量
  uint internal                        dividendTokenSupply = 0; //参与分红的Token数量
  uint internal                        dividendProfit; //单个Token的分红利润

  bool public                          icoPhase     = false; //是否是ICO阶段
  uint                                 icoStartTime;//ICO开始时间


}


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