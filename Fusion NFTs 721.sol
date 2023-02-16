// contracts/FusionToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FusionToken is ERC721, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    constructor (string memory name, string memory symbol) ERC721("Fusion NFTs", "FNFT"){}

    struct Item {
        uint256 id;
        address creator;
        string uri;
    }

    mapping (uint256 => Item) public Items;
    
    event itemCreated(uint256 tokenId, string tokenUri, address owner);
    event itemsCreated(uint256[] tokenIds, string[] tokenUris, address owner);

    function createItem(string memory tokenUri, address owner) public onlyOwner returns (uint256){
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        _safeMint(owner, newItemId);

        Items[newItemId] = Item(newItemId, owner, tokenUri);
        
        emit itemCreated(newItemId, tokenUri, owner);

        return newItemId;
    }
    
    
     function createItems(string[] memory tokenUris, address owner) public onlyOwner returns (uint[] memory){
        require(tokenUris.length > 0, 'The token uris is not valid');
        
        uint256[] memory newItems =  new uint[](tokenUris.length);
      
        for(uint256 i = 0; i < tokenUris.length; i++){
             _tokenIds.increment();
            uint256 newItemId = _tokenIds.current();
            _safeMint(owner, newItemId);
    
            Items[newItemId] = Item(newItemId, owner, tokenUris[i]);
            
            newItems[i] = newItemId;
        }
       
        emit itemsCreated(newItems, tokenUris, owner);
        return newItems;
    }
    
    

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

       return Items[tokenId].uri;
    }
}