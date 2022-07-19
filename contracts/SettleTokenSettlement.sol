// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract SettleTokenSettlement is AccessControl 
{

    using SafeMath for uint256; //Actually this is no longer necessary after Solidity 0.8+ but it demonstrates understanding
    using SafeERC20 for IERC20; //SafeTransfer reverts execution on unsuccessful send so there is no chance of accidentally continuing

    event Release(uint32 settlement_id);
    event Refund(uint32 settlement_id);
    event Funded(uint32 settlement_id, IERC20 token, uint256 amount);
    event CreateSettlement(address receiver, address sender, address releaser, uint256 amount, IERC20 token, uint256 _expiry_block, bytes32 _expiry_action);

    /*
    *   Specify an ADMIN, and keccak256 it, so that it fits within a bytes32 datatype. This isn't a cryptographic technique
    *   per se. It simply standardizes the size of all roles to 32 bytes, no matter how large the name of them is.
    *   Very gas efficient, but slightly confusing to those who are not familiar with AccessControl.sol!
    */

    bytes32 public constant ADMIN = keccak256("ADMIN_ROLE");
    
    /*
    *   Specify refund and release types and standardize them into bytes32 hex arrays
    *   This is so we can easily parse them using bytes32 and have other standardized actions in the future maybe
    */
    
    bytes32 public constant REFUND = keccak256("refund");
    bytes32 public constant RELEASE = keccak256("release");

    /*
    *   I wanted to demonstrate some mitigating factors in this contract. So let's enable a flag that will specify the contract
    *   to be paused and unpaused at any time, just in case there was a vulnerability found in the future! Of course, only the contract
    *   owner should be able to do this! Hence, AccessControl.sol has been inherited, so that we can do this in the recommended way.
    */

    bool public emergency_pause = false;

    /*
    *   The percentage fee that the contract takes from the settlement. This must be immutable, to avoid the risk of a rug-pull midway
    *   through an settlement by the admin. It is set once in the constructor of this contract
    */

    uint8 public fee;

    /*
    *   Specify a fee receiver address who will receive the fee when the settlement release or settlement refund occurs
    */

    address public fee_receiver;

    /*
    *    To support multiple tokens types it is pertinent to create a struct, such that the token used in each settlement is specified.
    *    However, this is less gas-efficient than only supporting ETH. If we only supported ETH, we could use a bool mapping
    *    to specify which settlements have been released. However, supporting any token is a nice feature!
    */

    struct Settlement {
        bool released;          //Have the funds been released to the seller?
        bool funds_deposited;   //Have the funds be added to the contract?
        address receiver;       //Who sent the funds in the first place? (Used for friendly view function)
        address sender;         //Who was the sender
        address releaser;       //Who is the elected releaser - the person/address to release the funds (Can be another contract)
        uint256 amount;         //Amount of the token
        IERC20 token;           //Which token is being used in the settlement
        uint256 expiry_block;   //The block at which the settlement can be finalised manually
        bytes32 expiry_action;  //The action which is taken if the settlement expires keccak256("release") or keccak256("refund").
    }

    /*
    *   There needs to be an array of indexable Settlements, so we can modify their state easily.
    *   public keyword automagically creates a getter, so we can view the state of this variable
    *   easily by simply calling it using a web3 provider.
    */

    Settlement[] public settlements;

    /*
    *   The contract sets up the preconditions from which an admin can create one to many party->settlements
    *   On the time of contract instantiation, no settlements need to be created and no funds need to be added. 
    *   So theoretically, you can instantiate one or many settlement contracts instances on behalf of 3rd parties
    *   who might not necessarily want to deposit funds at the time of deployment.
    */

    constructor(address _fee_receiver, uint8 _fee)
    {
        /*
        *   For the purposes of simplicity, the fee structure is set to a whole integer between 0 and 100
        *   Should the necessity arrise for a floating point fee percentage, uint256 could be used to support up to
        *   18 decimal places.
        */

        require(_fee >= 0 && _fee <= 100, "Fee must be a whole number between 0 and 100%");

        /*
        *   Give the deployer of this contract ADMIN permissions so that, should a vulnerability be found, they
        *   are able to quickly pause the contract and stop any releasing of funds. Must invoke DEFAULT_ADMIN_ROLE first
        *   as per the specification of AccessControl
        */
        
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        grantRole("ADMIN", msg.sender); 

        /*
        *   Supply a fee receiver address who will receive the fee for the settlement release or settlement refund
        */

        fee_receiver = _fee_receiver;

        fee = _fee;

    }

    /*
    *   This function sets up an settlement between a sender, receiver and releaser. It is flexible on how these parties are represented.
    *   Actually, the receiver could even be the burn address, or the releaser could be either an address a multi-signatory smart-contract 
    *   The sky is the limit here and it is intentionally general.
    */
    function create_settlement (address _receiver, address _sender, address _releaser, uint256 _amount, IERC20 _token, uint256 _expiry_block, bytes32 _expiry_action) external
    {
        /*
        *   You shouldn't be able to create an settlement thate expires in the past.
        */
        require(_expiry_block > block.number || _expiry_block == 0, "Settle It: Settlement expiry block must be in the future, or never (0)");

        /*
        *   Settlements that expire must take specific action with the funds
        */

        require(_expiry_block == 0 || _expiry_action == RELEASE || _expiry_action == REFUND, "Settle It: Expired settlements must take specific action (refund or release) with the funds");

        /*
        *   You shouldn't be able to settlement 0 Tokens.
        */
        require(_amount > 0, "Settle It: Settlement amount must be greater than 0.");
        
        /*
        *   You shouldn't be able to settlement 0.000000000000000001 tokens and negate the contract's fee.
        *   This would require safe math is using compiler <0.8.0, but since we are using higher than that
        *   we have a simple life and can use basic mathematical operators.
        */
        
        require(_amount * fee / 100 > 0, "Settle It: Fee earned by the settlement contract must be material.");

        _create_settlement(_receiver, _sender, _releaser, _amount, _token, _expiry_block, _expiry_action);
    }

    function _create_settlement (address _receiver, address _sender, address _releaser, uint256 _amount, IERC20 _token, uint256 _expiry_block, bytes32 _expiry_action) internal
    {
        Settlement memory settlement = Settlement(false, false, _receiver, _sender, _releaser, _amount, _token, _expiry_block, _expiry_action); //Create the settlement object

        settlements.push(settlement); //Add the settlement to the array of settlements

        emit CreateSettlement(_receiver, _sender, _releaser, _amount, _token, _expiry_block, _expiry_action);
    }

    /*
    *   The top level release_settlement function runs all pertinent checks before calling an internal function
    *   which is responsible for the actual release of the settlement, this is a standard practice in Solidity.
    *   It is a separation of concerns between the checks, and the functionality.
    */

    function release_settlement(uint32 _settlement_id) external
    {
        Settlement storage _settlement = settlements[_settlement_id];

        require(_settlement.releaser == msg.sender, "Settle It: Caller is not the releaser of this settlement."); //Obviously only the releaser should be allowed to release settlements
        require(_settlement.funds_deposited == true, "Settle It: Settlement must be funded to be released.");    //The settlement must have had the funds deposited before it can be released
        require(_settlement.released == false, "Settle It: Settlement is already released."); //I like to avoid shorthand here for readability. On a compiler level, I believe it ends up the same
        require(emergency_pause == false, "Settle It: All settlements are currently paused.");

        _release_settlement(_settlement);

        emit Release(_settlement_id);
    }

    /*
    *   This is our internal _release_settlement function. It is internal, so that it can only be called by the contract
    *   not externally. In this case, the release_settlement function calls it once all checks are passed.
    */

    function _release_settlement(Settlement storage _settlement) internal 
    {
        //Set released to true - once true the release and refund functionn cannot be called again (this avoids reentrancy)
        _settlement.released = true; 

        //Safe transfer funds to receiver minus the fee
        _settlement.token.safeTransferFrom(address(this), _settlement.receiver, _settlement.amount - (fee * _settlement.amount / 100));

        //Send the remainder to a fee receiver wallet - that's the profit.
        _settlement.token.safeTransferFrom(address(this), fee_receiver, (fee * _settlement.amount / 100));

        //Set settlement amount to zero. We have already negated reentracy, so the fact that this happens after the send is not a problem
        _settlement.amount = 0; 
    }

    function fund_settlement(uint32 _settlement_id) external 
    {
        //Lets avoid multiple array lookups by saving the pertinent settlement in a local variable (Worth testing efficiency here!)
        Settlement storage _settlement = settlements[_settlement_id];

        //SafeTransfer will revert if this line fails
        _settlement.token.safeTransferFrom(msg.sender, address(this), _settlement.amount);

        //Now release and refund become possible
        _settlement.funds_deposited = true;

        emit Funded(_settlement_id, _settlement.token, _settlement.amount);
    }

    /*
    *   The top level refund_settlement function runs all pertinent checks before calling an internal function
    *   which is responsible for the actual refund of the settlement, this is a standard practice in Solidity.
    *   It is a separation of concerns between the checks, and the functionality.
    */

    function refund_settlement(uint32 _settlement_id) external
    {
        Settlement storage _settlement = settlements[_settlement_id];

        require(_settlement.releaser == msg.sender, "Settle It: Caller is not the releaser of this settlement."); //Obviously only the releaser should be allowed to refund settlements
        require(_settlement.funds_deposited == true, "Settle It: Settlement must be funded to be refunded.");    //The settlement must have had the funds deposited before it can be refunded
        require(_settlement.released == false, "Settle It: Settlement is already released."); //I like to avoid shorthand here for readability. On a compiler level, I believe it ends up the same
        require(emergency_pause == false, "Settle It: All settlements are currently paused.");

        _refund_settlement(_settlement);

        emit Refund(_settlement_id);
    }

    function _refund_settlement(Settlement storage _settlement) internal 
    {
        //Set released to true - once true the release and refund functionn cannot be called again (this avoids reentrancy)
        _settlement.released = true; 

        //Safe transfer funds to receiver minus fee
        _settlement.token.safeTransferFrom(address(this), _settlement.sender, _settlement.amount - (fee * _settlement.amount / 100));

        //Send the remainder to a fee receiver wallet - that's the profit.
        _settlement.token.safeTransferFrom(address(this), fee_receiver, (fee * _settlement.amount / 100));

        //Set settlement amount to zero. We have already negated reentracy, so the fact that this happens after the send is not a problem
        _settlement.amount = 0; 
        
    }

    /*
    * Let anyone trigger the action of an expired settlement. Be it the sender or receiver, if the settlement is expired, it should be able
    * to be refunded or released depending on its original configuration
    */

    function expire_settlement(uint32 _settlement_id) external
    {
        //Lets avoid multiple array lookups by saving the pertinent settlement in a local variable (Worth testing efficiency here!)
        Settlement storage _settlement = settlements[_settlement_id];

        require(block.number >= _settlement.expiry_block && _settlement.expiry_block != 0, "Settle It: This settlement has not yet expired.");

        //We can call the same external release function here if the action on expiry is to release the funds
        if(_settlement.expiry_action == RELEASE)
        {
            require(_settlement.funds_deposited == true, "Settle It: Settlement must be funded to be refunded.");    //The settlement must have had the funds deposited before it can be refunded
            require(_settlement.released == false, "Settle It: Settlement is already released."); //I like to avoid shorthand here for readability. On a compiler level, I believe it ends up the same
            require(emergency_pause == false, "Settle It: All settlements are currently paused.");
            _release_settlement(_settlement);
        }

        //We can call the same external refund function if the action on expiry is to refund the funds
        else if(_settlement.expiry_action == REFUND)
        {
            require(_settlement.funds_deposited == true, "Settle It: Settlement must be funded to be refunded.");    //The settlement must have had the funds deposited before it can be refunded
            require(_settlement.released == false, "Settle It: Settlement is already released."); //I like to avoid shorthand here for readability. On a compiler level, I believe it ends up the same
            require(emergency_pause == false, "Settle It: All settlements are currently paused.");
            _refund_settlement(_settlement);
        }
    }

    /*
    *   The external toggle pause function performs the permissions check before calling an internal toggle pause function
    */

    function toggle_pause () external
    {
        require(hasRole("ADMIN", msg.sender), "Settle It: Only the ADMIN may pause or unpause this contract.");
        _toggle_pause();
    }

    /*
    *   Simply pause the contract if it wasn't paused, and unpause it if it was already paused
    */

    function _toggle_pause () internal 
    {
        emergency_pause = !emergency_pause;
    }

    /*
    *   As of Solidity 0.8.0 we can directly return structs without having to use the experimental 
    *   encoding feature of "pragma experimental ABIEncoderV2;", so we can pull all the escrows
    *   down to our web3js front end and display them based on the connected wallet's involvement
    */

    function get_settlement (uint256 index) public view returns (Settlement memory)
    {
        return settlements[index];
    }

    function get_num_settlements() public view returns (uint256)
    {
        return settlements.length;
    }

}