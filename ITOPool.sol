pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ITOPool is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    uint256 public tokenPrice;
    ERC20 public rewardToken;
    uint256 public decimals;
    uint256 public startTimestamp;
    uint256 public finishTimestamp;
    uint256 public startClaimTimestamp;
    uint256 public minEthPayment;
    uint256 public maxEthPayment;
    uint256 public maxDistributedTokenAmount;
    uint256 public tokensForDistribution;
    uint256 public distributedTokens;

    mapping(address => uint256) public tokenDebt;
    mapping(address => uint256) public payedAmount;

    event UpdatedSettings(string name, uint256 _newFinishTimestamp);
    
    event TokensDebt(
        address holder,
        uint256 ethAmount,
        uint256 tokenAmount
    );
    
    event TokensWithdrawn(address holder, uint256 amount);

    constructor(
        uint256 _tokenPrice,
        ERC20 _rewardToken,
        uint256 _startTimestamp,
        uint256 _finishTimestamp,
        uint256 _startClaimTimestamp,
        uint256 _minEthPayment,
        uint256 _maxEthPayment,
        uint256 _maxDistributedTokenAmount
    ) public {
        tokenPrice = _tokenPrice;
        rewardToken = _rewardToken;
        decimals = rewardToken.decimals();

        require(
            _startTimestamp < _finishTimestamp,
            "Start timestamp must be less than finish timestamp"
        );
        require(
            _finishTimestamp > now,
            "Finish timestamp must be more than current block"
        );
        startTimestamp = _startTimestamp;
        finishTimestamp = _finishTimestamp;
        startClaimTimestamp = _startClaimTimestamp;
        minEthPayment = _minEthPayment;
        maxEthPayment = _maxEthPayment;
        maxDistributedTokenAmount = _maxDistributedTokenAmount;
    }

    function pay() payable external nonReentrant{
        require(msg.value >= minEthPayment, "Less then min amount");
        require(msg.value <= maxEthPayment, "More then max amount");
        require(now >= startTimestamp, "Not started");
        require(now < finishTimestamp, "Ended");
        require(tokensForDistribution < maxDistributedTokenAmount, "Filled");

        uint256 tokenAmount = getTokenAmount(msg.value);
        //Need to sell the rest and return rest ETH
        if(tokensForDistribution.add(tokenAmount) > maxDistributedTokenAmount)
        {
            tokenAmount = maxDistributedTokenAmount.sub(tokensForDistribution);
            uint256 resturnETH = msg.value.sub(getETHAmount(tokenAmount));
            msg.sender.transfer(resturnETH);
        }
        tokensForDistribution = tokensForDistribution.add(tokenAmount);
        tokenDebt[msg.sender] = tokenDebt[msg.sender].add(tokenAmount);

        emit TokensDebt(msg.sender, msg.value, tokenAmount);
    }

    function getTokenAmount(uint256 ethAmount)
        internal
        view
        returns (uint256)
    {
        return ethAmount.div(tokenPrice).mul(10**decimals);
    }

    function getETHAmount(uint256 tokenAmount)
        internal
        view
        returns (uint256)
    {
        return tokenAmount.mul(tokenPrice).div(10**decimals);
    }

    /// @dev Allows to claim tokens for the specific user.
    /// @param _user Token receiver.
    function claimFor(address _user) external {
        proccessClaim(_user);
    }

    /// @dev Allows to claim tokens for themselves.
    function claim() external {
        proccessClaim(msg.sender);
    }

    /// @dev Proccess the claim.
    /// @param _receiver Token receiver.
    function proccessClaim(
        address _receiver
    ) internal nonReentrant{
        require(now > startClaimTimestamp, "Distribution not started");
        uint256 _amount = tokenDebt[_receiver];
        if (_amount > 0) {
            rewardToken.safeTransfer(_receiver, _amount);
            tokenDebt[_receiver] = 0;

            distributedTokens = distributedTokens.add(_amount);
            payedAmount[_receiver] = payedAmount[_receiver].add(_amount);
            emit TokensWithdrawn(_receiver,_amount);
        }
    }

    
    function withdrawETH() external onlyOwner returns(bool success) {
        msg.sender.transfer(address(this).balance);
        return true;
    }

     function withdrawNotSoldTokens() external onlyOwner returns(bool success) {
        require(now > finishTimestamp, "Withdraw allowed after stop accept ETH");
        uint256 balance = rewardToken.balanceOf(address(this));
        rewardToken.safeTransfer(msg.sender, balance.add(distributedTokens).sub(tokensForDistribution));
        return true;
    }

    function setFinishTimestamp(uint256 _newFinishTimestamp) external onlyOwner {
        require(
                startTimestamp < _newFinishTimestamp,
                "Start timestamp must be less than finish timestamp"
            );
        require(
                _newFinishTimestamp > now,
                "Finish timestamp must be more than current block"
            );
        finishTimestamp = _newFinishTimestamp;
        emit UpdatedSettings("finishTimestamp", finishTimestamp);
    }

    function setStartClaimTimestamp(uint256 _newStartClaimTimestamp) external onlyOwner {
        startClaimTimestamp = _newStartClaimTimestamp;
        emit UpdatedSettings("startClaimTimestamp", startClaimTimestamp);
    }

    function setMaxDistributedTokenAmount(uint256 _newMaxDistributedTokenAmount) external onlyOwner {
        require(
            _newMaxDistributedTokenAmount > maxDistributedTokenAmount,
            "New MaxDistributedTokenAmount must be more then current"
        );
        maxDistributedTokenAmount = _newMaxDistributedTokenAmount;
        emit UpdatedSettings("maxDistributedTokenAmount", maxDistributedTokenAmount);
    }
}
