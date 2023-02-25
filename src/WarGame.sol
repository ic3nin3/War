// 0x06A9e7BAD35a8aC2F04Bdc2858039a96F6A8bC30
pragma solidity ^0.8.9;
import "@api3/airnode-protocol/contracts/rrp/requesters/RrpRequesterV0.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface WarToken {
    function gameMint(address _to, uint256 _amount) external;

    function gameBurn(address _to, uint256 _amount) external;
}

contract WARGAME is Ownable, ReentrancyGuard, RrpRequesterV0 {
    using SafeMath for uint256;

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

    mapping(address => bool) public inGame;

    mapping(address => uint256) public drawTime;

    uint256 public poolIndex;

    address public highscore;

    address public airnode;
    bytes32 public endpointIdUint256;
    address public sponsorWallet;    

    uint256 public qfee = 50000000000000;

    WarToken warToken;

    event bet(address indexed from, uint256 amount);
    event win(
        address indexed from,
        uint256 myCard,
        uint256 theirCard,
        bool won,
        uint256 amount
    );

    event EnteredPool(address indexed player);

    event RequestedUint256(bytes32 indexed requestId);
    event ReceivedUint256(
        address indexed requestAddress,
        bytes32 indexed requestId,
        uint256 response
    );

    constructor(address _airnodeRrp, address _warTokenAddress)
        RrpRequesterV0(_airnodeRrp)
    {
        warToken = WarToken(_warTokenAddress);
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

    function enterPool(uint256 _amount) 
    payable 
    public {
        require(
            !inGame[msg.sender],
            "Can only enter one pool at a time"
        );
        require(_amount > 0, "Must include a bet amount");
        require(msg.value >= qfee, "Must small gas fee for the random number generator");
        //address payable sendAddress = payable(sponsorWallet);
        
        ++poolIndex;        
        
        payable(sponsorWallet).transfer(qfee);
        userPool[msg.sender] = true;
        inGame[msg.sender] = true;
        userIndex[poolIndex] = msg.sender;
        makeRequestUint256(msg.sender);
        betsize[msg.sender] = _amount;        

        warToken.gameBurn(msg.sender, _amount);
        emit bet(msg.sender, _amount);
        emit EnteredPool(msg.sender);
    }

    function leavePool(address user) internal {
        require(userPool[user], "Not in any pool");
        // Find the index of the user in userIndex and delete it
        uint256 userIndexToDelete;
        for (uint256 i = 1; i <= poolIndex; i++) {
            if (userIndex[i] == user) {
                userIndexToDelete = i;
                delete userIndex[i];
                break;
            }
        }

        // Shift all the elements after the deleted index to the left by one position
        for (uint256 i = userIndexToDelete; i <= poolIndex; i++) {
            userIndex[i] = userIndex[i + 1];
        }

        // Delete the last element of userIndex
        delete userIndex[poolIndex];
        // Delete the user from userPool
        delete userPool[user];
        // Decrement the pool index
        --poolIndex;
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
            opponent = (randomNumber[requestId] % (poolIndex));
            if (userIndex[opponent] == msg.sender) {
                if (opponent > (poolIndex)) {
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
            if (userPool[userToOpponent[msg.sender]]) {
                leavePool(userToOpponent[msg.sender]);
            }
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
            warToken.gameMint(msg.sender, payoutWin);
            warToken.gameMint(opponent, winDelta);
        } else if (myCard == theirCard) {
            emit win(msg.sender, myCard, theirCard, false, userBet);
            warToken.gameMint(msg.sender, userBet);
            warToken.gameMint(opponent, opponentBet);
        } else {
            emit win(msg.sender, myCard, theirCard, false, loseDelta);
            warToken.gameMint(msg.sender, loseDelta);
            warToken.gameMint(opponent, (opponentBet + userBet) - loseDelta);
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
        delete inGame[msg.sender];
        delete inGame[opponent];
    }

    function ForceWin() public {
        if (card[msg.sender] == 0) {
            revert("Must have selected a card");
        }
        uint256 lastCallTime = drawTime[msg.sender];
        if (lastCallTime == 0 || block.timestamp < lastCallTime + 1800) {
            revert("Opponent has 30 minutes to draw a card");
        }
        address opponent = userToOpponent[msg.sender];
        if (card[opponent] != 0) {
            revert("Opponent has drawn a card");
        }
        uint256 totalBet = betsize[msg.sender] + betsize[opponent];

        warToken.gameMint(msg.sender, totalBet);
        delete userPool[opponent];
        delete userPool[msg.sender];
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
        if (card[msg.sender] != 0 || userToOpponent[msg.sender] != address(0)) {
            revert("Cannot leave Pool after selecting a card unless opponent wasnt assigned");
        }
        if(userToOpponent[msg.sender] == address(0) && card[msg.sender] == 0 ){
            warToken.gameMint(msg.sender,betsize[msg.sender]);
        }     
        delete randomNumber[userId[msg.sender]];
        delete requestUser[userId[msg.sender]];
        delete betsize[msg.sender];
        delete userId[msg.sender];
        delete inGame[msg.sender];
        leavePool(msg.sender);
    }

    function fixZeroIndex() 
    public
    onlyOwner {                
        uint256 userIndexToDelete;
        if(userIndex[0] != address(0))
        {
            userIndexToDelete = 0;
        }

        // Shift all the elements after the deleted index to the left by one position
        for (uint256 i = 1; i <= poolIndex+1; i++) {
            if(userIndex[i+1] == address(0))
            {
                poolIndex = i;
                break;
            }
            userIndex[i] = userIndex[i - 1];
            
        }

        // Delete the last element of userIndex
        delete userIndex[userIndexToDelete];        

    }
}
