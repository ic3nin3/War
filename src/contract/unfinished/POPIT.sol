//chain goerli: 0xa0AD79D995DdeeB18a14eAef56A549A04e3Aa1Bd
//airnode: 0x6238772544f029ecaBfDED4300f13A3c4FE84E1D
//endpointIdUint256: 0xfb6d017bb87991b7495f563db3c8cf59ff87b09781947bb1e417006ad7f55a78
//xpub: xpub6CuDdF9zdWTRuGybJPuZUGnU4suZowMmgu15bjFZT2o6PUtk4Lo78KGJUGBobz3pPKRaN9sLxzj21CMe6StP3zUsd8tWEJPgZBesYBMY7Wo
pragma solidity 0.8.9;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@api3/airnode-protocol/contracts/rrp/requesters/RrpRequesterV0.sol";

contract PopIt is Ownable, ReentrancyGuard, RrpRequesterV0 {
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
        address indexed from,
        bytes32 indexed requestId,
        uint256 response
    );

    uint256[] gridMatrix;

    constructor(address _airnodeRrp) RrpRequesterV0(_airnodeRrp) {
        totalPlays = 0;
        totalWins = 0;
        totalLosses = 0;
        totalBurnt = 0;
        totalWon = 0;
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
        require(gridSize > 4, "gridSize is too small");
        require(_amount > 0, "Send at least 1 POP token");
        require((x < gridSize) && (x >= 0), "x value is out of bounds");
        require(((y < gridSize) && (y >= 0)), "y value is out of bounds");
        require(userId[msg.sender] == 0, "one bet at a time buddy!");
        totalBurnt += _amount;
        makeRequestUint256(msg.sender);
        coord[msg.sender] = [x, y];
        betsize[msg.sender] = ((_amount / computePayout(gridSize)) + _amount);
        emit bet(msg.sender, _amount);
    }

    function REVEAL() public nonReentrant {
        require(gridSize > 4, "gridSize is too small");
        require(userId[msg.sender] != 0, "User has no unrevealed numbers.");
        require(
            (randomNumber[userId[msg.sender]] != uint256(0)),
            "Random number not ready, try again."
        );
        bytes32 requestId = userId[msg.sender];
        uint256 secretnum = (randomNumber[requestId] %
            ((gridSize - 1) * (gridSize - 1)));

        //uint256 rand = randomNumber[userId[msg.sender]];
        //secretnum = uint256(keccak256(abi.encode(rand))) % 36;

        uint8[2] memory xy = coord[msg.sender];
        uint8 x = xy[0];
        uint8 y = xy[1];
        bool check = checkMatch(secretnum, x, y);
        if (check) {
            userHighscore[msg.sender] = betsize[msg.sender];
            highscore = msg.sender;
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

    function setGrid(uint8 n) public onlyOwner {
        gridSize = n;
    }

    function checkMatch(
        uint256 k,
        uint8 x,
        uint8 y
    ) public view returns (bool) {
        uint8[8] memory solution = generateSolutions(gridSize, k);
        uint256 end = solution.length;
        for (uint256 i = 0; i < end; i += 2) {
            if (solution[i] == x && solution[i + 1] == y) {
                return true;
            }
        }
        return false;
    }

    function generateSolutionsOld(uint256 n, uint256 k)
        public
        pure
        returns (uint8[] memory)
    {
        require(k < ((n - 1) * (n - 1)), "K is too large");
        require(k >= 0, "K is less than 0");

        uint8[] memory temp = new uint8[](8);

        uint8 i = uint8(k / (n - 1));
        uint8 j = uint8(k % (n - 1));

        if (i >= n - 1 || j >= n - 1) {
            return new uint8[](0);
        }

        uint256 pointIndex = 0;
        for (uint8 x = i; x < i + 2; x++) {
            for (uint8 y = j; y < j + 2; y++) {
                temp[pointIndex] = x;
                pointIndex++;
                temp[pointIndex] = y;
                pointIndex++;
            }
        }
        return temp;
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
}
