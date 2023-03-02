// test: 0xcC9De99b32750a0550380cb8495588ca2f48d533
// previous: 0x20c375C04e22E600A2BD4Bb9c4499483942Fa7C7
// latest: 0x20F173DF4580e900E39b0Dc442e0c54e7E133066
pragma solidity ^0.8.9;
import "@api3/airnode-protocol/contracts/rrp/requesters/RrpRequesterV0.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface WarToken {
    function gameMint(address _to, uint256 _amount) external;

    function gameBurn(address _to, uint256 _amount) external;
}

contract AERIAL is Ownable, ReentrancyGuard, RrpRequesterV0 {
    using SafeMath for uint256;

    uint256 public totalPlays;

    /******************/

    mapping(address => bytes32) public userId;
    mapping(bytes32 => address) public requestUser;
    mapping(bytes32 => uint256) public randomNumber;
    mapping(address => uint256) public betsize;
    mapping(address => uint8[2]) public coord;
    // mapping(address => uint256) public userHighscore;    

    mapping(address => bool) public inGame;    
    mapping(bytes32 => bool) public expectingRequestWithIdToBeFulfilled;

    uint256 public poolIndex;

    uint256 public highscore;
    address public highscoreHolder;

    address public airnode;
    bytes32 public endpointIdUint256;
    address public sponsorWallet;

    uint256 public gridSize;
    uint256 public qfee = 100000000000000;  

    uint256 public  totalWins;     
    uint256 public totalWon;     

    uint256 totalLosses;
    uint256 totalLost;

    WarToken warToken;

    event bet(address indexed from, uint256 amount);
    event win(
        address indexed from,
        uint256 config,
        uint256 x,
        uint256 y,
        bool won,
        uint256 Amount        
    );

    event EnteredPool(address indexed player);

    event RequestedUint256(bytes32 indexed requestId);
    event ReceivedUint256(
        address indexed requestAddress,
        bytes32 indexed requestId,
        uint256 response
    );

    bool gameActive;

    address botContract;

    constructor(address _airnodeRrp, address _warTokenAddress)
        RrpRequesterV0(_airnodeRrp)
    {
        warToken = WarToken(_warTokenAddress);
    }

    modifier onlyOwnerBot() {
        require(
            (msg.sender ==owner()) || (msg.sender == botContract),
            "Only Owner or Bot"
        );
        _;
    }

    function setBot(address _botContract) public onlyOwner {
        botContract = _botContract;
    }

    function setQfee(uint256 _qfee) public onlyOwner {
        require(_qfee <= 200000000000000, "Dont set fee too high");
        require(_qfee >= 50000000000000, "Dont set fee too low");
        qfee = _qfee;
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

    /// @notice Called by the Airnode through the AirnodeRrp contract to
    /// fulfill the request
    /// @param requestId Request ID
    /// @param data ABI-encoded response
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

    function setGrid(uint8 n) public onlyOwner {
        gridSize = n;
    }

    function Fire(
        uint256 _amount,
        uint8 x,
        uint8 y
    ) public nonReentrant {
        require(gridSize > 3, "GridSize needs to be greate then 3");        
        require(_amount > 0, "Send at least 1 POP token");
        require((x < gridSize) && (x >= 0), "x value is out of bounds");
        require(((y < gridSize) && (y >= 0)), "y value is out of bounds");
        require(userId[msg.sender] == 0, "one bet at a time buddy!");
        payable(sponsorWallet).transfer(qfee);
        warToken.gameBurn(msg.sender, _amount);        
        makeRequestUint256(msg.sender);
        coord[msg.sender] = [x, y];
        betsize[msg.sender] = ((_amount / computePayout(gridSize)) + _amount);
        emit bet(msg.sender, _amount);
    }

    function Reveal() public nonReentrant {
        require(gridSize > 3, "gridMatrix has no values");
        require(userId[msg.sender] != 0, "User has no unrevealed numbers.");
        require(
            (randomNumber[userId[msg.sender]] != uint256(0)),
            "Random number not ready, try again."
        );
        bytes32 requestId = userId[msg.sender];
        uint256 secretnum = (randomNumber[requestId] % (((gridSize - 1) * (gridSize - 1))-1));
        uint256 userBet = betsize[msg.sender];
        uint256 winAmount = computePayout(gridSize);

        uint8[2] memory xy = coord[msg.sender];
        uint8 x = xy[0];
        uint8 y = xy[1];
        bool check = checkMatch(secretnum, x, y);

        if (check) {            
            warToken.gameMint(msg.sender, winAmount);  
            ++totalWins;
            totalWon += winAmount;
            emit win(msg.sender, secretnum, x, y, true, winAmount);
        } else {
            ++totalLosses;
            totalLost += userBet;
            emit win(msg.sender, secretnum, x, y, false, userBet);
        }
        ++totalPlays;
        delete randomNumber[requestId];
        delete requestUser[requestId];
        delete betsize[msg.sender];
        delete userId[msg.sender];
        delete coord[msg.sender];
        delete inGame[msg.sender];       
    }
    
    function ChangeStatus(bool _newStatus) public onlyOwnerBot {
        gameActive = _newStatus;
    }

    function leaveGame()
    public
    {           
        if (!inGame[msg.sender])
        {
            revert("Not in a game");
        }
        bytes32 requestId = userId[msg.sender];   
        delete requestUser[requestId];
        delete randomNumber[requestId];        
        delete userId[msg.sender];        
        delete betsize[msg.sender];
        delete inGame[msg.sender];
    }

    function checkMatch(
        uint256 k,
        uint8 x,
        uint8 y
    ) public view
    returns (bool) {
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

}

