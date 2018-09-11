pragma solidity ^0.4.23;

// SafeMath library
library SafeMath {

  /**
  * @dev Multiplies two numbers, throws on overflow.
  */
  function mul(uint a, uint b) internal pure returns (uint) {
    if (a == 0) {
      return 0;
    }
    uint c = a * b;
    assert(c / a == b);
    return c;
  }

  /**
  * @dev Integer division of two numbers, truncating the quotient.
  */
  function div(uint a, uint b) internal pure returns (uint) {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    uint c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return c;
  }

  /**
  * @dev Substracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
  */
  function sub(uint a, uint b) internal pure returns (uint) {
    assert(b <= a);
    return a - b;
  }

  /**
  * @dev Adds two numbers, throws on overflow.
  */
  function add(uint a, uint b) internal pure returns (uint) {
    uint c = a + b;
    assert(c >= a);
    return c;
  }
}

contract BankRoll {
  using SafeMath for uint;

  /*=================================
  =            MODIFIERS            =
  =================================*/

  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  modifier onlyAdministrator() {
    require(msg.sender == owner || admins[msg.sender]);
    _;
  }

  modifier onlyHolders() {
    require(points[msg.sender] > 0);
    _;
  }

  modifier onlySkcContract() {
    require(msg.sender == skcAddress);
    _;
  }

  modifier isNegative(address sender, uint256 amount) {
    require(points[sender] >= amount);
    _;
  }

  /*==============================
  =            EVENTS            =
  ==============================*/

  event redeemEvent(address indexed sender, uint256 indexed amount);
  event withdrawEvent(address indexed sender, uint256 indexed amount);
  event ledgerRecordEvent(uint256 _serialNumber, address _address, uint256 _oldPiont, uint256 _newPoint, string date);

  /*=====================================
  =            CONSTANTS                =
  =====================================*/

  address public owner;
  address public skcAddress;
  mapping (address => uint256) public points;
  mapping (address => bool) internal admins;
  address[] internal holders;
  address internal platform;
  uint256 public serialNumber;


  /*=======================================
  =            PUBLIC FUNCTIONS           =
  =======================================*/

  constructor (address _skcAddress)
  public
  {
    owner = msg.sender;
    skcAddress = _skcAddress;
  }

  //SKC换积分
  //说明: 前端利用metamask进行兑换
  function redeem(address _caller, uint256 _amount)
  public
  returns (bool)
  {
    //调用SKC合约判断当前用户是否足够的SKC,并且转入奖金池（合约持有）
    //TODO
    //判断成功后调用事件 链下更新积分
    emit redeemEvent(_caller,_amount);
    return true;
  }

  //积分换SKC
  //说明：后端管理员调用  原因：同步原因，无法实时判断当前用户有多少积分,不做加减，所以只能信任链下
  function withdraw(address _caller,uint256 _amount)
  public
  onlyAdministrator
  returns (bool)
  {
    //调用SKC合约将用户转入对应的SKC
    //TODO
    //bool isSuccess = skcAddress.call(bytes4(keccak256("transfer(address,uint256)")), msg.sender, _amount);
    //assert(!isSuccess);
    //判断转成功后调用事件，链下记录
    emit withdrawEvent(msg.sender, _amount);
    return true;
  }

  ///int256 --> uint256 is safe?
  //更新账本
  //说明:
  //1.后台调用,只能管理员进行调用
  //2.游戏平台会进行结算清算分红，按积分方式发放，自动或者手动进行兑换SKC。
  //3.只需要记录最终的用户积分明细。
  function updateLedger(uint256 _serialNumber, address[] _address, uint256[] _oldPionts, uint256[] _newPoints, string date)
  public
  onlyAdministrator
  {
    require(date);
    require(_address.length == _oldPionts.length);
    require(_oldPionts.length == _newPoints.length);
    serialNumber = _serialNumber;
    for (uint i = 0; i < _address.length; i++) {
      //用户游戏积分更新
      points[_address[i]] = _newPoints[i];
      //暂定每个监听，是否需要一起监听。
      emit ledgerRecordEvent(_serialNumber, _address[i], _oldPionts[i], _newPoints[i], date);
    }
  }

  function setAdministrator(address[] _administrators)
  public
  onlyOwner
  {
    for (uint i = 0; i < _administrators.length; i++) {
      admins[_administrators[i]] = true;
    }
  }

  function unsetAdministrator(address[] _administrators)
   public
   onlyOwner
   {
    for (uint i = 0; i < _administrators.length; i++) {
      admins[_administrators[i]] = false;
    }
  }

  function replaceAdministrator(address oldOwner, address newOwner)
  public
  onlyOwner
  {
    admins[oldOwner] = false;
    admins[newOwner] = true;
  }

  function replacePlatformAddress(address _platform)
  public
  onlyOwner
  {
    platform = _platform;
  }
}
