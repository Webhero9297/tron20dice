pragma solidity ^0.4.23;

import "./YogiToken.sol";
import "./Ownable.sol";
 

/**
 * @title DharmaContract
 * @dev Dice game
 */
contract DharmaContract is Ownable {
  using SafeMath for uint256;

  bool public preventNewPlayers;

  uint8 constant public minRangeTotal = 1;    //  including
  uint8 constant public maxRangeTotal = 100;  //  including

  uint8 constant public minRangeUser = 8;     //  including
  uint8 constant public maxRangeUser = 99;    //  including

  uint8 constant public luckyHouseNumber = 88;
  uint256 constant public luckyHouseNumberMultiplier = 3;

  uint256 constant public minBet = 0x2FAF080;   // 50 * 10**6;
  uint256 constant public maxBet = 0xB2D05E00;  // 3000 * 10**6;


  uint256 public prizeAmountTotal;
  uint256 public tokenBonus = 0xC3663566A580000;  //88 * 10 ** 16;
  address public tokenAddress;

  uint256 constant private optimizedRateDivider = 10000;
  uint256[] public optimizedRates = [10652, 10769, 10888, 11011, 11136, 11264, 11395, 11529, 11666, 11807, 11951, 12098, 12250, 12405, 12564, 12727, 12894, 13066, 13243, 13424, 13611, 13802, 14000, 14202, 14411, 14626, 14848, 15076, 15312, 15555, 15806, 16065, 16333, 16610, 16896, 17192, 17500, 17818, 18148, 18490, 18846, 19215, 19600, 20000, 20416, 20851, 21304, 21777, 22272, 22790, 23333, 23902, 24500, 25128, 25789, 26486, 27222, 28000, 28823, 29696, 30625, 31612, 32666, 33793, 35000, 36296, 37692, 39200, 40833, 42608, 44545, 46666, 49000, 51578, 54444, 57647, 61250, 65333, 70000, 75384, 81666, 89090, 98000, 108888, 122500, 140000, 163333, 196000, 245000, 326666, 344344, 368888];

  uint256 public sessionCount;  //  used as sessionId
  mapping(address => uint256[]) private sessionIdsForAddress;
  mapping(uint256 => Session) private sessionForId;
  mapping(address => uint256) public prizeForAddress;

  //  Buddha Bonus Pool
  uint256 public bonusPoolTotal;                                                    //  amount of total funds amount for claim period
  uint256 public bonusPoolClaimPercent                                              = 3; //  3%
  uint256 public bonusPoolClaimIndividualAmount;                                    //  amount of payment for individual for claim period
  uint256 public bonusPoolClaimAvailablePeriod                                      = 28800; //  8 hours
  uint256 public bonusPoolCompoundPeriod                                            = 86400; //  24 hours
  uint256 public bonusPoolClaimPeriodStarted;                                       //  timestamp, when previous (pending) Claim Period Started
  uint256 public bonusPoolCompoundPeriodStarted;                                    //  timestamp, when previous (pending) Compound Period Started
  uint256 public bonusPoolClaimPeriodPlayersAmount;                                 //  amount of players, who played during previous (pending) Compound Period Started
  uint256 public bonusPoolCompoundPayoutPeriodsAmount = 1;                          //  amount of Compound - Payout periods. Compound + Payout = 1 period
  mapping(address => uint) public bonusPoolCompoundPayoutPeriodNumberForPlayer;     //  number of Compound - Payout period for player
  mapping(address => bool) public bonusPoolClaimPeriodPlayersClaimed;               //  keep track of users, whos has already claimed bonus

  struct Session {
    uint8 diceCount;            //  dice times. 3 - finished
    uint8[3] diceGuessNumbers;  //  guess numbers for dice rolls
    uint8[3] diceResults;       //  numbers for dice rolls
    uint256 id;                 //  session id
    address player;             //  player address
    uint256[3] diceBets;        //  bets for dice rolls
    uint256[3] dicePrizes;      //  prizes for dice rolls
    uint256[3] diceTimestamps;   //  dice rolled timestamps
  }

  event DiceRolled(address indexed _address, uint8 _guessNumber, uint8 _diceNumber, uint256 _prize, bool _luckyHouseNumberMultiplier);
  event SessionFinished(address _address);
  event ClaimBonusPool(bool _claimed, uint256 _amountClaimed);


  /**
   * PUBLIC
   */

  /**
   * @dev Fallback function should be used to keep contract's balance positive.
   */
  function() external payable { }

  /**
   * @dev Contract constructor.
   * @param _tokenAddress Address of token to be used in contract.
   */
  constructor(address _tokenAddress) public {
    updateToken(_tokenAddress, tokenBonus);
    bonusPoolCompoundPeriodStarted = now;
  }

  /**
   * @dev Updates token and bonus amount.
   * @param _tokenAddress Address of token to be used in contract.
   * @param _tokenBonus Amount of token to be sent at the end of the session.
   */
  function updateToken(address _tokenAddress, uint256 _tokenBonus) public onlyOwner {
    require(_tokenAddress != address(0), "wrong token address");
    require(_tokenBonus > 0, "bonus must be > 0");

    tokenAddress = _tokenAddress;
    tokenBonus = _tokenBonus;
  }

  function updatePreventNewPlayers(bool _prevent) public onlyOwner {
    preventNewPlayers = _prevent;
  }

  /**
   * @dev Updates time period for Buuddah Bonus Pool claiming.
   * @param _period Period for bonus claim.
   */
  function updateBonusPoolClaimAvailablePeriod(uint256 _period) public onlyOwner {
    require(_period > 0, "period must be > 0");

    bonusPoolClaimAvailablePeriod = _period;
  }

  /**
   * @dev Updates time period for Buuddah Bonus Pool compund.
   * @param _period Period for bonus compound.
   */
  function updateBonusPoolCompoundPeriod(uint256 _period) public onlyOwner {
    require(_period > 0, "period must be > 0");

    bonusPoolCompoundPeriod = _period;
  }

  /**
   * @dev Claiming for Buuddah Bonus Pool.
   */
  function claimBonusPool() public {
    if (bonusPoolClaimPeriodStarted > 0) {
      if (checkBonusPoolClaimPeriodRunning()) {
        //  transfer
        transferBonusPoolFunds();
      } else {
        //  stop claim & start compound
        startCompoundPeriod();
        //  event
        emit ClaimBonusPool(false, 0);
      }
    } else {
      if(checkBonusPoolCompoundPeriodRunning()) {
        //  compound still running
        emit ClaimBonusPool(false, 0);
      } else {
        //  stop compound & start claim
        stopCompoundPeriod();
        transferBonusPoolFunds();
      }
    }
  }

  /**
   * @dev User rolls.
   * @param _guessNumber Guess number provided by user.
   */
  function roll(uint8 _guessNumber) public payable {
    uint256[] memory sessionIds = sessionIdsForAddress[msg.sender];
    if (preventNewPlayers) {
      if((sessionIds.length == 0) || (sessionForId[sessionIds[sessionIds.length - 1]].diceCount == 3)) {
        revert("preventNewPlayers is active");
      }
    }

    require((msg.value >= minBet) && (msg.value <= maxBet), "wrong bet");
    require(_guessNumber >= minRangeUser && _guessNumber <= maxRangeUser, "not in user range");

    updateBonusPoolClaimAvailableStatus();

    uint256 prize;
    uint8 randNum = randomNumber(address(this).balance);
    if(randNum >= _guessNumber && randNum <= maxRangeUser) {
      //  won
      uint8 rateIdx = _guessNumber - minRangeUser;
      uint256 optimizedRate = optimizedRates[rateIdx];
      prize = msg.value.mul(optimizedRate).div(optimizedRateDivider);

      if(randNum == luckyHouseNumber) {
        prize = prize.mul(luckyHouseNumberMultiplier);
        emit DiceRolled(msg.sender, _guessNumber, randNum, prize, true);
      } else {
        emit DiceRolled(msg.sender, _guessNumber, randNum, prize, false);
      }

      prizeForAddress[msg.sender] = prizeForAddress[msg.sender].add(prize);
      prizeAmountTotal = prizeAmountTotal.add(prize);
    } else {
      //  lost
      if (bonusPoolClaimPeriodStarted == 0) {
        bonusPoolTotal = bonusPoolTotal.add(msg.value.mul(bonusPoolClaimPercent).div(100));
      }

      emit DiceRolled(msg.sender, _guessNumber, randNum, prize, false);
    }

    //  update current session
    if((sessionIds.length == 0) || (sessionForId[sessionIds[sessionIds.length - 1]].diceCount == 3)) {
      //  create new session
      Session memory session_new = Session(1, [_guessNumber, 0, 0], [randNum, 0, 0], sessionCount, msg.sender, [msg.value, 0, 0], [prize, 0, 0], [now, 0, 0]);
      sessionIdsForAddress[msg.sender].push(sessionCount);
      sessionForId[sessionCount] = session_new;

      sessionCount = sessionCount.add(1);

      if(bonusPoolClaimPeriodStarted == 0) {
        if(bonusPoolCompoundPayoutPeriodNumberForPlayer[msg.sender] != bonusPoolCompoundPayoutPeriodsAmount) {
          //  add player
          bonusPoolClaimPeriodPlayersClaimed[msg.sender] = false;
          bonusPoolClaimPeriodPlayersAmount = bonusPoolClaimPeriodPlayersAmount.add(1);
          bonusPoolCompoundPayoutPeriodNumberForPlayer[msg.sender] = bonusPoolCompoundPayoutPeriodsAmount;
        }
      }
    } else {
      //  running session
      Session storage session = sessionForId[sessionIds[sessionIds.length - 1]];
      session.diceGuessNumbers[session.diceCount] = _guessNumber;
      session.diceResults[session.diceCount] = randNum;
      session.diceBets[session.diceCount] = msg.value;
      session.dicePrizes[session.diceCount] = prize;
      session.diceTimestamps[session.diceCount] = now;
      session.diceCount += 1;

      if(session.diceCount == 3) {
        uint256 prizePlayer = prizeForAddress[msg.sender];
        if (prizePlayer > 0) {
          require(getBalance() >= prizePlayer, "not enough funds");

          delete prizeForAddress[msg.sender];
          prizeAmountTotal = prizeAmountTotal.sub(prizePlayer);
          address(msg.sender).transfer(prizePlayer);
        }

        TRC20Mintable(tokenAddress).mint(msg.sender, tokenBonus);
        emit SessionFinished(msg.sender);
      }
    }
  }

  /**
   * @dev Allows owner to withdraw commission.
   */
  function withdrawOwnerCommission() public onlyOwner {
    uint256 amount = getBalance().sub(prizeAmountTotal).sub(bonusPoolTotal);
    require(amount > 0, "amount == 0");

    msg.sender.transfer(amount);
  }

  /**
   * @dev Get contract's balance.
   * @return Balance for the contract.
   */
  function getBalance() public view returns(uint256) {
      return address(this).balance;
  }

  /**
   * @dev Gets information about session.
   * @param _id Session id to retrieve details.
   * @return Session parameters.
   */
  function sessionInfo(uint256 _id) public view returns(uint8, uint8[3] memory, uint8[3] memory, uint256, address, uint256[3] memory, uint256[3] memory, uint256[3] memory) {
      Session memory session = sessionForId[_id];
      return (session.diceCount, session.diceGuessNumbers, session.diceResults, session.id, session.player, session.diceBets, session.dicePrizes, session.diceTimestamps);
  }

  /**
   * @dev Gets session ids for provided address.
   * @param _address Address to get session ids.
   * @return Session ids for provided adress.
   */
  function sessionIds(address _address) public view returns(uint256[] memory) {
    return sessionIdsForAddress[_address];
  }

  /**
   * PRIVATE
   */

  /**
   * @dev Gererates and eturns preudo-random number.
   * @param _randHelper Random value for better randomness.
   * @return Preudo-random number. 1 - 100 including both edges.
   */
  function randomNumber(uint256 _randHelper) private view returns(uint8) {
    uint random = uint(keccak256(abi.encodePacked(now, msg.sender, _randHelper))) % maxRangeTotal;  //  0 - 99 including both
    return uint8(random + 1); //  should be 1 - 100 including both
  }

  /**
   * @dev Checks if payout period is still running.
   * @return If period is running.
   */
  function checkBonusPoolClaimPeriodRunning() public view returns (bool) {
    return bonusPoolClaimPeriodStarted.add(bonusPoolClaimAvailablePeriod) > now;
  }

  /**
   * @dev Checks if compound period is still running.
   * @return If period is running.
   */
  function checkBonusPoolCompoundPeriodRunning() public view returns (bool) {
    return bonusPoolCompoundPeriodStarted.add(bonusPoolCompoundPeriod) > now;
  }

  /**
   * @dev Transfers bonus amount to msg.sender.
   */
  function transferBonusPoolFunds() private {
    if(bonusPoolCompoundPayoutPeriodNumberForPlayer[msg.sender] == bonusPoolCompoundPayoutPeriodsAmount && bonusPoolClaimPeriodPlayersClaimed[msg.sender] == false) {
      uint256[] memory ids = sessionIdsForAddress[msg.sender];
      require((sessionForId[ids[ids.length - 1]].diceCount == 3), "session not finished");

      bonusPoolClaimPeriodPlayersClaimed[msg.sender] = true;
      bonusPoolTotal = bonusPoolTotal.sub(bonusPoolClaimIndividualAmount);
      msg.sender.transfer(bonusPoolClaimIndividualAmount);
      emit ClaimBonusPool(true, bonusPoolClaimIndividualAmount);
    } else {
      emit ClaimBonusPool(false, 0);
    }
  }

  /**
   * @dev Starts compound period and stops payout period.
   */
  function startCompoundPeriod() private {
    bonusPoolClaimPeriodStarted = 0;
    bonusPoolCompoundPeriodStarted = now;
    bonusPoolCompoundPayoutPeriodsAmount = bonusPoolCompoundPayoutPeriodsAmount.add(1);

    delete bonusPoolClaimIndividualAmount;
    delete bonusPoolClaimPeriodPlayersAmount;
    delete bonusPoolTotal;
  }

  /**
   * @dev Stops compound period and starts payout period.
   */
  function stopCompoundPeriod() private {
    bonusPoolClaimPeriodStarted = now;
    bonusPoolCompoundPeriodStarted = 0;
    bonusPoolClaimIndividualAmount = bonusPoolTotal.div(bonusPoolClaimPeriodPlayersAmount);
  }

  /**
   * @dev Updates BonusPoolClaimAvailable status.
   */
  function updateBonusPoolClaimAvailableStatus() private {
    if (bonusPoolClaimPeriodStarted > 0) {
      if(!checkBonusPoolClaimPeriodRunning()) {
        startCompoundPeriod();
      }
    } else {
      if(!checkBonusPoolCompoundPeriodRunning()) {
        stopCompoundPeriod();
      }
    }
  }
}
