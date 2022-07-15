pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract TestEscrowToken is ERC20PresetFixedSupply {

    uint256 public constant INITIAL_SUPPLY = 1000000 * (10 ** uint256(18)); // Initially Mint 1000000 tokens

    constructor () ERC20PresetFixedSupply("MyToken", "MT", INITIAL_SUPPLY, msg.sender) {

    }
}