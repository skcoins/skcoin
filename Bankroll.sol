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

  modifier onlyFggContract() {
    require(msg.sender == fggAddress);
    _;
  }

  modifier isZero(int256[] _amount) {
    uint256 positive = 0;
    uint256 negative = 0;
    for (uint i = 0; i < _amount.length; i++) {
      if (_amount[i] > 0) {
        positive = SafeMath.add(positive, uint256(_amount[i]));
      } else {
        negative = SafeMath.add(negative, uint256(_amount[i]));
      }
    }
    require(positive == negative);
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
  event playGame(address sender, uint id, int256 amount);

  /*=====================================
  =            CONSTANTS                =
  =====================================*/

  address public owner;
  address public fggAddress;
  uint256 public totalSupply;
  mapping (address => uint256) public points;
  mapping (address => bool) internal admins;
  address[] internal holders;
  address internal platform;
  uint256 public serialNumber;

  /*=======================================
  =            PUBLIC FUNCTIONS           =
  =======================================*/

  constructor (address _fggAddress) public {
    owner = msg.sender;
    fggAddress = _fggAddress;
  }

  function redeem(address _caller, uint256 _amount) public onlyFggContract returns (bool){
    points[_caller] = SafeMath.add(points[_caller], _amount);
    totalSupply = SafeMath.add(totalSupply, _amount);
    emit redeemEvent(_caller,_amount);
    return true;
  }

  function withdrawAll() public onlyHolders {
    withdraw(points[msg.sender]);
  }

  ///"this" is safe
  function withdraw(uint256 _amount) public returns (bool){
    require(points[msg.sender] >= _amount);
    points[msg.sender] = SafeMath.sub(points[msg.sender], _amount);
    totalSupply = SafeMath.sub(totalSupply, _amount);
    bool isSuccess = fggAddress.call(bytes4(keccak256("transfer(address,uint256)")), msg.sender, _amount);
    assert(!isSuccess);
    emit withdrawEvent(msg.sender, _amount);
    return true;
  }

  ///int256 --> uint256 is safe?
  function updateLedger(address[] _address, int256[] _amount, uint id, uint256 _serialNumber)
  public
  onlyAdministrator
  isZero(_amount)
  {
    require(_address.length == _amount.length);
    for (uint i = 0; i < _address.length; i++) {
      uint256 oldPoints = points[_address[i]];
      if (_amount[i] > 0) {
        points[_address[i]] = SafeMath.add(oldPoints, uint256(_amount[i]));
      } else {
        assert(oldPoints < uint256(_amount[i]));
        points[_address[i]] = SafeMath.sub(oldPoints, uint256(_amount[i]));
      }
      emit playGame(_address[i], id, _amount[i]);
    }
    serialNumber = _serialNumber;
    /// calculate the sum of
  }

  function setAdministrator(address[] _administrators) public onlyOwner {
    for (uint i = 0; i < _administrators.length; i++) {
      admins[_administrators[i]] = true;
    }
  }

  function unsetAdministrator(address[] _administrators) public onlyOwner {
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
