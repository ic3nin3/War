//chain goerli: 0xa0AD79D995DdeeB18a14eAef56A549A04e3Aa1Bd
//airnode: 0x6238772544f029ecaBfDED4300f13A3c4FE84E1D
//endpointIdUint256: 0xfb6d017bb87991b7495f563db3c8cf59ff87b09781947bb1e417006ad7f55a78
//xpub: xpub6CuDdF9zdWTRuGybJPuZUGnU4suZowMmgu15bjFZT2o6PUtk4Lo78KGJUGBobz3pPKRaN9sLxzj21CMe6StP3zUsd8tWEJPgZBesYBMY7Wo

pragma solidity ^0.8.9;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@api3/airnode-protocol/contracts/rrp/requesters/RrpRequesterV0.sol";

contract WAR is ERC20, Ownable, ReentrancyGuard, RrpRequesterV0 {
    using SafeMath for uint256;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;
    address public constant deadAddress = address(0xdead);

    bool private swapping;

    address public marketingWallet;
    address public devWallet;

    uint256 public maxTransactionAmount;
    uint256 public swapTokensAtAmount;
    uint256 public maxWallet;

    bool public limitsInEffect = true;
    bool public tradingActive = false;
    bool public swapEnabled = false;

    // Anti-bot and anti-whale mappings and variables
    mapping(address => uint256) private _holderLastTransferTimestamp; // to hold last Transfers temporarily during launch
    bool public transferDelayEnabled = true;

    uint256 public buyTotalFees;
    uint256 public buyMarketingFee;
    uint256 public buyLiquidityFee;
    uint256 public buyDevFee;

    uint256 public sellTotalFees;
    uint256 public sellMarketingFee;
    uint256 public sellLiquidityFee;
    uint256 public sellDevFee;

    uint256 public tokensForMarketing;
    uint256 public tokensForLiquidity;
    uint256 public tokensForDev;

    uint256 public totalPlays;
    uint256 public totalWins;
    uint256 public totalLosses;
    uint256 public totalBurnt;
    uint256 public totalWon;

    /******************/

    mapping(address => bytes32) public userId;
    mapping(bytes32 => address) public requestUser;
    mapping(bytes32 => uint256) public randomNumber;
    mapping(address => uint256) public betsize;
    mapping(address => uint256) public userHighscore;

    mapping(address => bool) public userPool;
    mapping(uint256 => address) public userIndex;
    mapping(address => address) public userToOpponent;
    mapping(address => address) public opponentToUser;
    mapping(address => uint256) public card;

    mapping(address => bytes32) public userReservedId;
    mapping(bytes32 => address) public requestReservedUser;
    mapping(bytes32 => uint256) public randomReservedNumber;
    mapping(address => uint256) public betReservedSize;

    mapping(address => bool) public userReservedPool;
    mapping(address => address) public userReservedToOpponent;
    mapping(address => address) public opponentReservedToUser;
    mapping(address => uint256) public cardReserved;

    mapping(address => uint256) public drawTime;

    uint256 public poolIndex;

    address public highscore;

    address public airnode;
    bytes32 public endpointIdUint256;
    address public sponsorWallet;

    // exlcude from fees and max transaction amount
    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) public _isExcludedMaxTransactionAmount;

    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping(address => bool) public automatedMarketMakerPairs;

    event UpdateUniswapV2Router(
        address indexed newAddress,
        address indexed oldAddress
    );

    event ExcludeFromFees(address indexed account, bool isExcluded);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event marketingWalletUpdated(
        address indexed newWallet,
        address indexed oldWallet
    );

    event devWalletUpdated(
        address indexed newWallet,
        address indexed oldWallet
    );

    event bet(address indexed from, uint256 amount);
    event win(
        address indexed from,
        uint256 myCard,
        uint256 theirCard,
        bool won,
        uint256 amount
    );

    event EnteredPool(address indexed player);
    event EnteredReservedPool(address indexed player, address opponent);

    event RequestedUint256(bytes32 indexed requestId);
    event ReceivedUint256(
        address indexed requestAddress,
        bytes32 indexed requestId,
        uint256 response
    );

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiquidity
    );

    event AutoNukeLP();

    event ManualNukeLP();

    constructor(address _airnodeRrp)
        ERC20("War", "WAR")
        RrpRequesterV0(_airnodeRrp)
    {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
            0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506
        );

        excludeFromMaxTransaction(address(_uniswapV2Router), true);
        uniswapV2Router = _uniswapV2Router;

        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
        excludeFromMaxTransaction(address(uniswapV2Pair), true);
        _setAutomatedMarketMakerPair(address(uniswapV2Pair), true);

        uint256 _buyMarketingFee;
        uint256 _buyLiquidityFee;
        uint256 _buyDevFee = 2;

        uint256 _sellMarketingFee;
        uint256 _sellLiquidityFee = 8;
        uint256 _sellDevFee;

        uint256 totalSupply = 1000000 * 1e18;

        maxTransactionAmount = (totalSupply * 5) / 1000; // 1% maxTransactionAmountTxn
        maxWallet = (totalSupply * 1) / 100; // 1% maxWallet
        swapTokensAtAmount = (totalSupply * 5) / 10000; // 0.05% swap wallet

        buyMarketingFee = _buyMarketingFee;
        buyLiquidityFee = _buyLiquidityFee;
        buyDevFee = _buyDevFee;
        buyTotalFees = buyMarketingFee + buyLiquidityFee + buyDevFee;

        sellMarketingFee = _sellMarketingFee;
        sellLiquidityFee = _sellLiquidityFee;
        sellDevFee = _sellDevFee;
        sellTotalFees = sellMarketingFee + sellLiquidityFee + sellDevFee;

        marketingWallet = address(0xFF079835E080b2E32Bf19d4C5705aB91F9d0A92c); // set as marketing wallet
        devWallet = address(0xFF079835E080b2E32Bf19d4C5705aB91F9d0A92c); // set as dev wallet

        // exclude from paying fees or having max transaction amount
        excludeFromFees(owner(), true);
        excludeFromFees(address(this), true);
        excludeFromFees(address(0xdead), true);

        excludeFromMaxTransaction(owner(), true);
        excludeFromMaxTransaction(address(this), true);
        excludeFromMaxTransaction(address(0xdead), true);

        /*
            _mint is an internal function in ERC20.sol that is only called here,
            and CANNOT be called ever again
        */
        _mint(msg.sender, totalSupply);
    }

    receive() external payable {}

    function setRequestParameters(
        address _airnode,
        bytes32 _endpointIdUint256,
        address _sponsorWallet
    ) external onlyOwner {
        airnode = _airnode;
        endpointIdUint256 = _endpointIdUint256;
        sponsorWallet = _sponsorWallet;
    }

    function makeRequestUint256(address userAddress) internal {
        bytes32 requestId = airnodeRrp.makeFullRequest(
            airnode,
            endpointIdUint256,
            address(this),
            sponsorWallet,
            address(this),
            this.fulfillUint256.selector,
            ""
        );
        userId[userAddress] = requestId;
        requestUser[requestId] = userAddress;
        emit RequestedUint256(requestId);
    }

    function fulfillUint256(bytes32 requestId, bytes calldata data)
        external
        onlyAirnodeRrp
    {
        require(requestUser[requestId] != address(0), "Request ID not known");
        uint256 qrngUint256 = abi.decode(data, (uint256));
        // Do what you want with `qrngUint256` here...
        randomNumber[requestId] = qrngUint256;

        emit ReceivedUint256(requestUser[requestId], requestId, qrngUint256);
    }

    function enterPool(uint256 _amount) public {
        require(!userPool[msg.sender] && !userReservedPool[msg.sender], "Can only enter one pool at a time");
        require(_amount > 0, "Must include a bet amount");
        userPool[msg.sender] = true;
        userIndex[poolIndex] = msg.sender;
        makeRequestUint256(msg.sender);
        betsize[msg.sender] = _amount;
        poolIndex++;

        _burn(msg.sender, _amount);
        emit bet(msg.sender, _amount);
        emit EnteredPool(msg.sender);
    }

    function leavePool(address user) internal {
        require(userPool[user], "Not in any pool");
        // Find the index of the user in userIndex and delete it
        uint256 userIndexToDelete;
        for (uint256 i = 0; i < poolIndex; i++) {
            if (userIndex[i] == user) {
                userIndexToDelete = i;
                delete userIndex[i];
                break;
            }
        }

        // Shift all the elements after the deleted index to the left by one position
        for (uint256 i = userIndexToDelete; i < poolIndex; i++) {
            userIndex[i] = userIndex[i + 1];
        }

        // Delete the last element of userIndex
        delete userIndex[poolIndex - 1];
        // Delete the user from userPool
        delete userPool[user];
        // Decrement the pool index
        poolIndex--;
    }

    function Draw() public nonReentrant {
        require(
            poolIndex >= 2 || opponentToUser[msg.sender] != address(0),
            "Pool is low. wait for more players to enter"
        );
        require(userId[msg.sender] != 0, "User has no unrevealed numbers.");
        require(
            (randomNumber[userId[msg.sender]] != uint256(0)),
            "Random number not ready, try again."
        );
        require(
            card[msg.sender] == 0,
            "Card has been assigned, reveal to view results"
        );

        bytes32 requestId = userId[msg.sender];
        uint256 secretnum = (randomNumber[requestId] % 12) + 1;
        uint256 opponent;
        if (opponentToUser[msg.sender] == address(0)) {
            opponent = (randomNumber[requestId] % (poolIndex - 1));
            if (userIndex[opponent] == msg.sender) {
                if (opponent >= (poolIndex - 1)) {
                    opponent--;
                } else {
                    opponent++;
                }
            }
            userToOpponent[msg.sender] = userIndex[opponent];
            opponentToUser[userIndex[opponent]] = msg.sender;
            userToOpponent[userIndex[opponent]] = msg.sender;
            opponentToUser[msg.sender] = userIndex[opponent];
        }

        card[msg.sender] = secretnum;
        drawTime[msg.sender] = block.timestamp;
        delete randomNumber[requestId];
        delete requestUser[requestId];
        if (userPool[msg.sender]) {
            delete userIndex[opponent];
            leavePool(msg.sender);
            leavePool(userToOpponent[msg.sender]);
        }
    }

    function Reveal() public nonReentrant {
        require(
            card[msg.sender] != 0,
            "Card has not been assigned, draw your card."
        );
        address opponent = userToOpponent[msg.sender];
        require(card[opponent] != 0, "Opponent has not drawn a card");
        uint256 myCard = card[msg.sender];
        uint256 theirCard = card[opponent];
        uint256 userBet = betsize[msg.sender];
        uint256 opponentBet = betsize[opponent];

        uint256 payoutWin;
        uint256 loseDelta;
        uint256 winDelta;
        if (userBet >= opponentBet) {
            payoutWin = userBet + opponentBet;
            loseDelta = userBet - opponentBet;
        } else {
            payoutWin = userBet + userBet;
            winDelta = userBet = opponentBet;
        }
        if (myCard > theirCard) {
            emit win(msg.sender, myCard, theirCard, true, payoutWin);
            _mint(msg.sender, payoutWin);
            _mint(opponent, winDelta);
        } else if (myCard == theirCard) {
            emit win(msg.sender, myCard, theirCard, false, userBet);
            _mint(msg.sender, userBet);
            _mint(opponent, opponentBet);
        } else {
            emit win(msg.sender, myCard, theirCard, false, loseDelta);
            _mint(msg.sender, loseDelta);
            _mint(opponent, (opponentBet + userBet) - loseDelta);
        }

        delete userToOpponent[msg.sender];
        delete opponentToUser[msg.sender];
        delete userToOpponent[opponent];
        delete opponentToUser[opponent];
        delete card[msg.sender];
        delete card[opponent];
        delete betsize[msg.sender];
        delete betsize[opponent];
        delete drawTime[msg.sender];
        delete drawTime[opponent];
    }

    function makeReservedRequestUint256(address userAddress) internal {
        bytes32 requestId = airnodeRrp.makeFullRequest(
            airnode,
            endpointIdUint256,
            address(this),
            sponsorWallet,
            address(this),
            this.fulfillUint256.selector,
            ""
        );
        userReservedId[userAddress] = requestId;
        requestReservedUser[requestId] = userAddress;
        emit RequestedUint256(requestId);
    }

    function enterReservedPool(address opponent, uint256 _amount) public {
        require(!userReservedPool[msg.sender] && !userPool[msg.sender], "Can only enter one pool at a time");
        require(_amount > 0, "Must include a bet amount");
        require(userReservedToOpponent[msg.sender] == address(0),"Can only open one challenge at a time");

        userReservedPool[msg.sender] = true;
        betReservedSize[msg.sender] = _amount;
        userReservedToOpponent[msg.sender] = opponent;
        opponentReservedToUser[opponent] = msg.sender;

        makeReservedRequestUint256(msg.sender);
        _burn(msg.sender, _amount);

        emit EnteredReservedPool(msg.sender, opponent);
        emit bet(msg.sender, _amount);
    }

    function leaveReservedPool() public {
        require(
            userReservedPool[msg.sender],
            "Must be in the reserved pool to leave"
        );
        bytes32 requestId = userReservedId[msg.sender];
        require(randomNumber[requestId] != 0,"Must wait for random number to generate to clean out variables");
        address opponent = userReservedToOpponent[msg.sender];
        require(!userReservedPool[opponent],"Cannot leave the pool after your opponent has entered");
        
        _mint(msg.sender,betReservedSize[msg.sender]);                        

        delete userReservedToOpponent[msg.sender];        
        delete opponentReservedToUser[opponent];
        delete userReservedPool[msg.sender];
        delete userReservedId[msg.sender];
        delete requestReservedUser[requestId];
    }

    function DrawReserved() public nonReentrant {
        require(
            userReservedId[msg.sender] != bytes32(0),
            "User has no unrevealed numbers."
        );
        require(
            (randomNumber[userReservedId[msg.sender]] != uint256(0)),
            "Random number not ready, try again."
        );
        require(
            cardReserved[msg.sender] == uint256(0),
            "Card has been assigned, reveal to view results"
        );
        require(
            userReservedToOpponent[userReservedToOpponent[msg.sender]] !=
                address(0),
            "Selected Player needs to enter the Reserved pool"
        );

        bytes32 requestId = userReservedId[msg.sender];
        uint256 secretnum = (randomNumber[requestId] % 12) + 1;

        cardReserved[msg.sender] = secretnum;

        delete randomNumber[requestId];
        delete requestUser[requestId];
        leaveReservedPool();
    }

    function RevealReserved() public nonReentrant {
        require(
            cardReserved[msg.sender] != 0,
            "Card has not been assigned, draw your card"
        );
        address opponent = userReservedToOpponent[msg.sender];
        require(cardReserved[opponent] != 0, "Opponent has not drawn a card");
        uint256 myCard = cardReserved[msg.sender];
        uint256 theirCard = cardReserved[opponent];

        uint256 userBet = betReservedSize[msg.sender];
        uint256 opponentBet = betReservedSize[opponent];
        uint256 payoutWin;
        uint256 delta;
        if (userBet >= opponentBet) {
            payoutWin = userBet + opponentBet;
            delta = userBet - opponentBet;
        } else {
            payoutWin = userBet + userBet;
        }
        if (myCard > theirCard) {
            emit win(msg.sender, myCard, theirCard, true, payoutWin);
            _mint(msg.sender, payoutWin);
            if (delta > 0) {
                _mint(opponent, delta);
            }
        } else if (myCard == theirCard) {
            emit win(msg.sender, myCard, theirCard, false, userBet);
            _mint(msg.sender, userBet);
            _mint(opponent, opponentBet);
        } else {
            emit win(msg.sender, myCard, theirCard, false, delta);
            _mint(msg.sender, delta);
            _mint(opponent, (opponentBet + userBet) - delta);
        }

        delete userReservedToOpponent[msg.sender];
        delete opponentReservedToUser[msg.sender];
        delete userReservedToOpponent[opponent];
        delete opponentReservedToUser[opponent];
        delete cardReserved[msg.sender];
        delete cardReserved[opponent];
        delete betReservedSize[msg.sender];
        delete betReservedSize[opponent];        
    }

    function ForceWin() public {
        if(card[msg.sender] ==0)
        {
            revert("Must have selected a card");
        }
        uint256 lastCallTime = drawTime[msg.sender]; 
        if (lastCallTime == 0 || block.timestamp >= lastCallTime + 1800) 
        {
            revert("Opponent has 30 minutes to draw a card");
        }
        address opponent = userToOpponent[msg.sender];
        if(card[opponent] !=0)
        {
            revert("Opponent has drawn a card");
        }
        uint256 totalBet = betsize[msg.sender] + betsize[opponent];

        _mint(msg.sender,totalBet);
        delete userToOpponent[msg.sender];
        delete opponentToUser[msg.sender];
        delete userToOpponent[opponent];
        delete opponentToUser[opponent];
        delete card[msg.sender];
        delete card[opponent];
        delete betsize[msg.sender];
        delete betsize[opponent];
        delete drawTime[msg.sender];
        delete drawTime[opponent];

    }

    function ForceReveal(address user, address opponent) public onlyOwner {}

    function ForceLeavePool() public {
        if(card[msg.sender] !=0)
        {
            revert("Cannot leave Pool after selecting a card");
        }
        if(userToOpponent[msg.sender] != address(0))
        {
            revert("Cannot leave Pool while you have an active opponent");
        }
        delete randomNumber[userId[msg.sender]];
        delete requestUser[userId[msg.sender]];
        delete betsize[msg.sender];
        delete userId[msg.sender];
        leavePool(msg.sender);
    }

    function setRouter(address router) public onlyOwner {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(router);

        excludeFromMaxTransaction(address(_uniswapV2Router), true);
        uniswapV2Router = _uniswapV2Router;

        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
        excludeFromMaxTransaction(address(uniswapV2Pair), true);
        _setAutomatedMarketMakerPair(address(uniswapV2Pair), true);
    }

    // once enabled, can never be turned off
    function enableTrading() external onlyOwner {
        tradingActive = true;
        swapEnabled = true;
    }

    // remove limits after token is stable
    function removeLimits() external onlyOwner returns (bool) {
        limitsInEffect = false;
        return true;
    }

    // disable Transfer delay - cannot be reenabled
    function disableTransferDelay() external onlyOwner returns (bool) {
        transferDelayEnabled = false;
        return true;
    }

    // change the minimum amount of tokens to sell from fees
    function updateSwapTokensAtAmount(uint256 newAmount)
        external
        onlyOwner
        returns (bool)
    {
        require(
            newAmount >= (totalSupply() * 1) / 100000,
            "Swap amount cannot be lower than 0.001% total supply."
        );
        require(
            newAmount <= (totalSupply() * 5) / 1000,
            "Swap amount cannot be higher than 0.5% total supply."
        );
        swapTokensAtAmount = newAmount;
        return true;
    }

    function updateMaxTxnAmount(uint256 newNum) external onlyOwner {
        require(
            newNum >= ((totalSupply() * 1) / 1000) / 1e18,
            "Cannot set maxTransactionAmount lower than 0.1%"
        );
        maxTransactionAmount = newNum * (10**18);
    }

    function updateMaxWalletAmount(uint256 newNum) external onlyOwner {
        require(
            newNum >= ((totalSupply() * 5) / 1000) / 1e18,
            "Cannot set maxWallet lower than 0.5%"
        );
        maxWallet = newNum * (10**18);
    }

    function excludeFromMaxTransaction(address updAds, bool isEx)
        public
        onlyOwner
    {
        _isExcludedMaxTransactionAmount[updAds] = isEx;
    }

    // only use to disable contract sales if absolutely necessary (emergency use only)
    function updateSwapEnabled(bool enabled) external onlyOwner {
        swapEnabled = enabled;
    }

    function updateBuyFees(
        uint256 _marketingFee,
        uint256 _liquidityFee,
        uint256 _devFee
    ) external onlyOwner {
        buyMarketingFee = _marketingFee;
        buyLiquidityFee = _liquidityFee;
        buyDevFee = _devFee;
        buyTotalFees = buyMarketingFee + buyLiquidityFee + buyDevFee;
        require(buyTotalFees <= 20, "Must keep fees at 20% or less");
    }

    function updateSellFees(
        uint256 _marketingFee,
        uint256 _liquidityFee,
        uint256 _devFee
    ) external onlyOwner {
        sellMarketingFee = _marketingFee;
        sellLiquidityFee = _liquidityFee;
        sellDevFee = _devFee;
        sellTotalFees = sellMarketingFee + sellLiquidityFee + sellDevFee;
        require(sellTotalFees <= 25, "Must keep fees at 25% or less");
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        _isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    function setAutomatedMarketMakerPair(address pair, bool value)
        public
        onlyOwner
    {
        require(
            pair != uniswapV2Pair,
            "The pair cannot be removed from automatedMarketMakerPairs"
        );

        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        automatedMarketMakerPairs[pair] = value;

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function updateMarketingWallet(address newMarketingWallet)
        external
        onlyOwner
    {
        emit marketingWalletUpdated(newMarketingWallet, marketingWallet);
        marketingWallet = newMarketingWallet;
    }

    function updateDevWallet(address newWallet) external onlyOwner {
        emit devWalletUpdated(newWallet, devWallet);
        devWallet = newWallet;
    }

    function isExcludedFromFees(address account) public view returns (bool) {
        return _isExcludedFromFees[account];
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        if (limitsInEffect) {
            if (
                from != owner() &&
                to != owner() &&
                to != address(0) &&
                to != address(0xdead) &&
                !swapping
            ) {
                if (!tradingActive) {
                    require(
                        _isExcludedFromFees[from] || _isExcludedFromFees[to],
                        "Trading is not active."
                    );
                }

                // at launch if the transfer delay is enabled, ensure the block timestamps for purchasers is set -- during launch.
                if (transferDelayEnabled) {
                    if (
                        to != owner() &&
                        to != address(uniswapV2Router) &&
                        to != address(uniswapV2Pair)
                    ) {
                        require(
                            _holderLastTransferTimestamp[tx.origin] <
                                block.number,
                            "_transfer:: Transfer Delay enabled.  Only one purchase per block allowed."
                        );
                        _holderLastTransferTimestamp[tx.origin] = block.number;
                    }
                }

                //when buy
                if (
                    automatedMarketMakerPairs[from] &&
                    !_isExcludedMaxTransactionAmount[to]
                ) {
                    require(
                        amount <= maxTransactionAmount,
                        "Buy transfer amount exceeds the maxTransactionAmount."
                    );
                    require(
                        amount + balanceOf(to) <= maxWallet,
                        "Max wallet exceeded"
                    );
                }
                //when sell
                else if (
                    automatedMarketMakerPairs[to] &&
                    !_isExcludedMaxTransactionAmount[from]
                ) {
                    require(
                        amount <= maxTransactionAmount,
                        "Sell transfer amount exceeds the maxTransactionAmount."
                    );
                } else if (!_isExcludedMaxTransactionAmount[to]) {
                    require(
                        amount + balanceOf(to) <= maxWallet,
                        "Max wallet exceeded"
                    );
                }
            }
        }

        uint256 contractTokenBalance = balanceOf(address(this));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if (
            canSwap &&
            swapEnabled &&
            !swapping &&
            !automatedMarketMakerPairs[from] &&
            !_isExcludedFromFees[from] &&
            !_isExcludedFromFees[to]
        ) {
            swapping = true;

            swapBack();

            swapping = false;
        }

        bool takeFee = !swapping;

        // if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        uint256 fees = 0;
        // only take fees on buys/sells, do not take on wallet transfers
        if (takeFee) {
            // on sell
            if (automatedMarketMakerPairs[to] && sellTotalFees > 0) {
                fees = amount.mul(sellTotalFees).div(100);
                tokensForLiquidity += (fees * sellLiquidityFee) / sellTotalFees;
                tokensForDev += (fees * sellDevFee) / sellTotalFees;
                tokensForMarketing += (fees * sellMarketingFee) / sellTotalFees;
            }
            // on buy
            else if (automatedMarketMakerPairs[from] && buyTotalFees > 0) {
                fees = amount.mul(buyTotalFees).div(100);
                tokensForLiquidity += (fees * buyLiquidityFee) / buyTotalFees;
                tokensForDev += (fees * buyDevFee) / buyTotalFees;
                tokensForMarketing += (fees * buyMarketingFee) / buyTotalFees;
            }

            if (fees > 0) {
                super._transfer(from, address(this), fees);
            }

            amount -= fees;
        }

        super._transfer(from, to, amount);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            marketingWallet,
            block.timestamp
        );
    }

    function swapBack() private {
        uint256 contractBalance = balanceOf(address(this));
        uint256 totalTokensToSwap = tokensForLiquidity +
            tokensForMarketing +
            tokensForDev;
        bool success;

        if (contractBalance == 0 || totalTokensToSwap == 0) {
            return;
        }

        if (contractBalance > swapTokensAtAmount * 20) {
            contractBalance = swapTokensAtAmount * 20;
        }

        // Halve the amount of liquidity tokens
        uint256 liquidityTokens = (contractBalance * tokensForLiquidity) /
            totalTokensToSwap /
            2;
        uint256 amountToSwapForETH = contractBalance.sub(liquidityTokens);

        uint256 initialETHBalance = address(this).balance;

        swapTokensForEth(amountToSwapForETH);

        uint256 ethBalance = address(this).balance.sub(initialETHBalance);

        uint256 ethForMarketing = ethBalance.mul(tokensForMarketing).div(
            totalTokensToSwap
        );
        uint256 ethForDev = ethBalance.mul(tokensForDev).div(totalTokensToSwap);

        uint256 ethForLiquidity = ethBalance - ethForMarketing - ethForDev;

        tokensForLiquidity = 0;
        tokensForMarketing = 0;
        tokensForDev = 0;

        (success, ) = address(devWallet).call{value: ethForDev}("");

        if (liquidityTokens > 0 && ethForLiquidity > 0) {
            addLiquidity(liquidityTokens, ethForLiquidity);
            emit SwapAndLiquify(
                amountToSwapForETH,
                ethForLiquidity,
                tokensForLiquidity
            );
        }

        (success, ) = address(marketingWallet).call{
            value: address(this).balance
        }("");
    }

    function payout() public onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function withdrawToken() public onlyOwner {
        this.approve(address(this), totalSupply());
        this.transferFrom(address(this), owner(), balanceOf(address(this)));
    }
}
