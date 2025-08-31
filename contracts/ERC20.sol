// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20{
    constructor()ERC20("MyToken","MTK") {
        
    }

    function mintToken(address _to, uint256 _amount)  public {
        _mint(_to, _amount*10**decimals());
    }
}





