pragma solidity ^0.4.23;

import "./tokens/TRC20/TRC20Mintable.sol";
import "./tokens/TRC20/TRC20Detailed.sol";

contract YogiToken is TRC20Mintable, TRC20Detailed("Yogi", "DHT", 18) {
  constructor() public {
    uint256 ownersSupply = 8800000000 * 10 ** 18;
    mint(msg.sender, ownersSupply);
  }
}