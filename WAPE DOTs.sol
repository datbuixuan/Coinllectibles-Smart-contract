// contracts/Coinllectibles.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CoinllectiblesToken is ERC721Enumerable, Ownable {
    constructor (string memory name, string memory symbol) ERC721(name, symbol){}

    mapping (uint256 => string) private Items;
    string private ContractURI;
    
    event itemCreated(uint256 tokenId, string tokenUri, address owner);
    event itemsCreated(uint256[] tokenIds, string[] tokenUris, address owner);

    function createItem(string memory tokenUri, address owner) public onlyOwner{
        uint256 newItemId = totalSupply();
        _safeMint(owner, newItemId);

        Items[newItemId] = tokenUri;
        
        emit itemCreated(newItemId, tokenUri, owner);
    }
    
    function createItems(string[] memory tokenUris, address owner) public onlyOwner{
        require(tokenUris.length > 0, "The token URIs is not valid");
        
        uint256[] memory newItems =  new uint[](tokenUris.length);
      
        for(uint256 i = 0; i < tokenUris.length; i++){
            uint256 newItemId = totalSupply();
            _safeMint(owner, newItemId);
    
            Items[newItemId] = tokenUris[i];
            
            newItems[i] = newItemId;
        }
       
        emit itemsCreated(newItems, tokenUris, owner);
    }  
    
    function setApprovalForItems(address to, uint256[] memory tokenIds) public{
        require(tokenIds.length > 0, "The input data is incorrect");
        
        for(uint256 i = 0; i < tokenIds.length; i++){
            require(_isApprovedOrOwner(msg.sender, tokenIds[i]), "You are not owner of item");

            _approve(to, tokenIds[i]);
        }
    }

    function transfers(address[] memory froms, address[] memory tos, uint256[] memory tokenIds) public{
        require(froms.length == tos.length, "The input data is incorrect");
        require(tokenIds.length == tos.length, "The input data is incorrect");

        for(uint256 i = 0; i < froms.length; i++){
            require(_isApprovedOrOwner(msg.sender, tokenIds[i]), "You are not owner of item");

            _transfer(froms[i], tos[i], tokenIds[i]);
        }
    }

    function setContractURI(string memory contractUri) public onlyOwner{
        ContractURI = contractUri;
    }

    

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "No token ID exists");

       return Items[tokenId];
    }

    function contractURI() public view returns (string memory) {
        return ContractURI;
    }
}