pragma solidity ^0.4.15;

/**
 * @title DirectCrowdsaleLib
 * @author Majoolr.io
 *
 * version 1.0.0
 * Copyright (c) 2017 Majoolr, LLC
 * The MIT License (MIT)
 * https://github.com/Majoolr/ethereum-libraries/blob/master/LICENSE
 *
 * The DirectCrowdsale Library provides functionality to create a initial coin offering
 * for a standard token sale with high supply where there is a direct ether to
 * token transfer.
 *
 * Majoolr provides smart contract services and security reviews for contract
 * deployments in addition to working on open source projects in the Ethereum
 * community. Our purpose is to test, document, and deploy reusable code onto the
 * blockchain and improve both security and usability. We also educate non-profits,
 * schools, and other community members about the application of blockchain
 * technology. For further information: majoolr.io
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

import "./BasicMathLib.sol";
import "./TokenLib.sol";
import "./CrowdsaleLib.sol";

library DirectCrowdsaleLib {
  using BasicMathLib for uint256;
  using CrowdsaleLib for CrowdsaleLib.CrowdsaleStorage;

  struct DirectCrowdsaleStorage {

  	CrowdsaleLib.CrowdsaleStorage base; // base storage from CrowdsaleLib

    uint256[] tokenPricePoints;    // price points at each price change interval in cents/token.

  	uint256 changeInterval;      // amount of time between changes in the price of the token
  	uint256 lastPriceChangeTime;  // time of the last change in token cost
  }

  event LogTokensBought(address indexed buyer, uint256 amount);
  event LogAddressCapExceeded(address indexed buyer, uint256 amount, string Msg);
  event LogErrorMsg(uint256 amount, string Msg);
  event LogTokenPriceChange(uint256 amount, string Msg);


  /// @dev Called by a crowdsale contract upon creation.
  /// @param self Stored crowdsale from crowdsale contract
  /// @param _owner Address of crowdsale owner
  /// @param _capAmountInCents Total to be raised in cents
  /// @param _startTime Timestamp of sale start time
  /// @param _endTime Timestamp of sale end time
  /// @param _tokenPricePoints Array of each price point during sale cents/token
  /// @param _fallbackExchangeRate Exchange rate of cents/ETH
  /// @param _changeInterval The number of seconds between each step
  /// @param _percentBurn Percentage of extra tokens to burn
  /// @param _token Token being sold
  function init(DirectCrowdsaleStorage storage self,
                address _owner,
                uint256 _capAmountInCents,
                uint256 _startTime,
                uint256 _endTime,
                uint256[] _tokenPricePoints,
                uint256 _fallbackExchangeRate,
                uint256 _changeInterval,
                uint8 _percentBurn,
                CrowdsaleToken _token)
  {
  	self.base.init(_owner,
                _tokenPricePoints[0],
                _fallbackExchangeRate,
                _capAmountInCents,
                _startTime,
                _endTime,
                _percentBurn,
                _token);

    require(_tokenPricePoints.length > 0);

    // if there is no increase or decrease in price, the time interval should also be zero
    if (_tokenPricePoints.length == 1) {
    	require(_changeInterval == 0);
    }
    self.tokenPricePoints = _tokenPricePoints;
  	self.changeInterval = _changeInterval;
  	self.lastPriceChangeTime = _startTime;
  }

  /// @dev Called when an address wants to purchase tokens
  /// @param self Stored crowdsale from crowdsale contract
  /// @param _amount amound of wei that the buyer is sending
  /// @return true on succesful purchase
  function receivePurchase(DirectCrowdsaleStorage storage self, uint256 _amount) returns (bool) {
    require(msg.sender != self.base.owner);
  	require(self.base.validPurchase());

    require((self.base.ownerBalance + _amount) <= self.base.capAmount);

  	// if the token price increase interval has passed, update the current day and change the token price
  	if ((self.changeInterval > 0) && (now >= (self.lastPriceChangeTime + self.changeInterval))) {
  		self.lastPriceChangeTime = self.lastPriceChangeTime + self.changeInterval;
      uint256 index = (now-self.base.startTime)/self.changeInterval;

      //prevents going out of bounds on the tokenPricePoints array
      if (self.tokenPricePoints.length <= index)
        index = self.tokenPricePoints.length - 1;

      self.base.changeTokenPrice(self.tokenPricePoints[index]);

      LogTokenPriceChange(self.base.tokensPerEth,"Token Price has changed!");
  	}

  	uint256 numTokens; //number of tokens that will be purchased
  	bool err;
    uint256 newBalance; //the new balance of the owner of the crowdsale
    uint256 weiTokens; //temp calc holder
    uint256 zeros; //for calculating token
    uint256 leftoverWei; //wei change for purchaser
    uint256 remainder; //temp calc holder

    // Find the number of tokens as a function in wei
    (err,weiTokens) = _amount.times(self.base.tokensPerEth);
    require(!err);

    if(self.base.tokenDecimals <= 18){
      zeros = 10**(18-uint256(self.base.tokenDecimals));
      numTokens = weiTokens/zeros;
      leftoverWei = weiTokens % zeros;
      self.base.leftoverWei[msg.sender] += leftoverWei;
    } else {
      zeros = 10**(uint256(self.base.tokenDecimals)-18);
      numTokens = weiTokens*zeros;
    }

    // can't overflow because it is under the cap
    self.base.hasContributed[msg.sender] += _amount - leftoverWei;

    require(numTokens <= self.base.token.balanceOf(this));

    // calculate the amout of ether in the owners balance
    (err,newBalance) = self.base.ownerBalance.plus(_amount-leftoverWei);
    require(!err);

    self.base.ownerBalance = newBalance;   // "deposit" the amount

    // can't overflow because it will be under the cap
	  self.base.withdrawTokensMap[msg.sender] += numTokens;

    //subtract tokens from owner's share
    (err,remainder) = self.base.withdrawTokensMap[self.base.owner].minus(numTokens);
    self.base.withdrawTokensMap[self.base.owner] = remainder;

	  LogTokensBought(msg.sender, numTokens);

    return true;
  }

  /*Functions "inherited" from CrowdsaleLib library*/

  function setTokenExchangeRate(DirectCrowdsaleStorage storage self, uint256 _exchangeRate) returns (bool) {
    return self.base.setTokenExchangeRate(_exchangeRate);
  }

  function setTokens(DirectCrowdsaleStorage storage self) returns (bool) {
    return self.base.setTokens();
  }

  function withdrawTokens(DirectCrowdsaleStorage storage self) returns (bool) {
    return self.base.withdrawTokens();
  }

  function withdrawLeftoverWei(DirectCrowdsaleStorage storage self) returns (bool) {
    return self.base.withdrawLeftoverWei();
  }

  function withdrawOwnerEth(DirectCrowdsaleStorage storage self) returns (bool) {
    return self.base.withdrawOwnerEth();
  }

  function crowdsaleActive(DirectCrowdsaleStorage storage self) constant returns (bool) {
    return self.base.crowdsaleActive();
  }

  function crowdsaleEnded(DirectCrowdsaleStorage storage self) constant returns (bool) {
    return self.base.crowdsaleEnded();
  }

  function validPurchase(DirectCrowdsaleStorage storage self) constant returns (bool) {
    return self.base.validPurchase();
  }
}
