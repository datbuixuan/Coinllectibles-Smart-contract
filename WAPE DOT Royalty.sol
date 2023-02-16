// contracts/FusionToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CoinllectiblesToken is ERC721Enumerable, IERC2981, Ownable {
    struct Item {
        string uri;
        address royaltyAddress;
        uint96 royaltyPercentage;
    }

    mapping (uint256 => Item) private Items;
    string private ContractURI;

    constructor (string memory name, string memory symbol) ERC721(name, symbol){ }

    event itemCreated(uint256 tokenId, string tokenUri, address owner, address royaltyAddress, uint96 royaltyPercentage);
    event itemsCreated(uint256[] tokenIds, string[] tokenUris, address owner, address royaltyAddress, uint96 royaltyPercentage);
   
   
    function createItem( string memory uri, address owner, address royaltyAddress, uint96 royaltyPercentage) public onlyOwner {
        uint256 newItemId = totalSupply();
        _safeMint(owner, newItemId);    

        Items[newItemId] = Item(
            uri,
            royaltyAddress,
            royaltyPercentage
        );

        emit itemCreated(newItemId, uri, owner, royaltyAddress, royaltyPercentage);
    }

    function createItems(string[] memory uris, address owner, address royaltyAddress, uint96 royaltyPercentage) public onlyOwner {
        require(uris.length > 0, "The token URIs is not valid");
        uint256[] memory newItems = new uint256[](uris.length);

        for (uint256 i = 0; i < uris.length; i++) {
            uint256 newItemId = totalSupply();
            _safeMint(owner, newItemId);

            Items[newItemId] = Item(
                uris[i],
                royaltyAddress,
                royaltyPercentage
            );

            newItems[i] = newItemId;
        }

        emit itemsCreated(newItems, uris, owner, royaltyAddress, royaltyPercentage);
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


    // view function
    function tokenURI(uint256 tokenId) public view override returns (string memory)
    {
        require(_exists(tokenId), "No token ID exists");
        return Items[tokenId].uri;
    }

    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view override returns (address receiver, uint256 royaltyAmount)
    {
        require(_exists(tokenId), "No token ID exists");
        Item memory _item = Items[tokenId];

        return (_item.royaltyAddress, (salePrice * _item.royaltyPercentage) / 1000);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC721Enumerable) returns (bool)
    {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }

    function contractURI() public view returns (string memory) {
        return ContractURI;
    }
}