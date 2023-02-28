pragma solidity 0.8.9;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@api3/airnode-protocol/contracts/rrp/requesters/RrpRequesterV0.sol";

contract Pop is ERC20, Ownable, ReentrancyGuard, RrpRequesterV0 {
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
    mapping(address => uint8[2]) public coord;
    mapping(address => uint256) public userHighscore;

    address public highscore;

    address public airnode;
    bytes32 public endpointIdUint256;
    address public sponsorWallet;

    uint8 gridSize = 7;

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
        uint256 config,
        uint8 x,
        uint8 y,
        bool won,
        uint256 amount
    );
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

    uint256[] gridMatrix;

    constructor(address _airnodeRrp)
        ERC20("Balloon", "POP")
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


        maxTransactionAmount = (totalSupply * 1) / 100; // 1% maxTransactionAmountTxn
        maxWallet = (totalSupply * 2) / 100; // 2% maxWallet
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

    function setGrid(uint256[] memory grid) public onlyOwner {
        gridMatrix = grid;
    }

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

    function POP(
        uint256 _amount,
        uint8 x,
        uint8 y
    ) public nonReentrant {
        require(gridSize > 3, "gridMatrix has no values");
        require(
            _amount <= totalSupply() / 100,
            "Can not flip more than 1% of the supply at a time"
        );
        require(_amount > 0, "Send at least 1 POP token");
        require((x < gridSize) && (x >= 0), "x value is out of bounds");
        require(((y < gridSize) && (y >= 0)), "y value is out of bounds");
        require(userId[msg.sender] == 0, "one bet at a time buddy!");
        _burn(msg.sender, _amount);
        totalBurnt += _amount;
        makeRequestUint256(msg.sender);
        coord[msg.sender] = [x, y];
        betsize[msg.sender] = ((_amount / computePayout(gridSize)) + _amount);
        emit bet(msg.sender, _amount);
    }

    function REVEAL() public nonReentrant {
        require(gridSize > 3, "gridMatrix has no values");
        require(userId[msg.sender] != 0, "User has no unrevealed numbers.");
        require(
            (randomNumber[userId[msg.sender]] != uint256(0)),
            "Random number not ready, try again."
        );
        bytes32 requestId = userId[msg.sender];
        uint256 secretnum = (randomNumber[requestId] % (((gridSize - 1) * (gridSize - 1))-1));

        uint8[2] memory xy = coord[msg.sender];
        uint8 x = xy[0];
        uint8 y = xy[1];
        bool check = checkMatch(secretnum, x, y);
        if (check) {
            userHighscore[msg.sender] = betsize[msg.sender];
            highscore = msg.sender;
            _mint(msg.sender, betsize[msg.sender]);
            ++totalWins;
            totalWon += betsize[msg.sender];
            emit win(msg.sender, secretnum, x, y, true, betsize[msg.sender]);
        } else {
            ++totalLosses;
            emit win(msg.sender, secretnum, x, y, false, betsize[msg.sender]);
        }
        ++totalPlays;
        delete randomNumber[requestId];
        delete requestUser[requestId];
        delete betsize[msg.sender];
        delete userId[msg.sender];
        delete coord[msg.sender];
    }

    function checkMatch(
        uint256 k,
        uint8 x,
        uint8 y
    ) public view returns (bool) {
        uint8[8] memory solution = generateSolutions(gridSize,k);
        uint256 end = solution.length;
        for (uint256 i = 0; i < end; i += 2) {
            if (solution[i] == x && solution[i + 1] == y) {
                return true;
            }
        }
        return false;
    }

    function generateSolutions(uint256 n, uint256 k)
        public
        pure
        returns (uint8[8] memory)
    {
        require(k < ((n - 1) * (n - 1)), "K is too large");
        require(k >= 0, "K is less than 0");
        uint8 i = uint8(k / (n - 1));
        uint8 j = uint8(k % (n - 1));
        uint8[8] memory temp = [i, j, i + 1, j, i, j + 1, i + 1, j + 1];
        return temp;
    }

    function computePayout(uint256 n) public pure returns (uint256) {
        uint256 safeOdds = (n - 1) * (n - 1);
        return SafeMath.div(4, safeOdds);
    }

    function dangerClearCache() public {
        delete randomNumber[userId[msg.sender]];
        delete requestUser[userId[msg.sender]];
        delete betsize[msg.sender];
        delete userId[msg.sender];
        delete coord[msg.sender];
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
