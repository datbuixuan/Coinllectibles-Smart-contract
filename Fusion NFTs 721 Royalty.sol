// contracts/FusionToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FusionTokenRoyalty is ERC721, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    /// bytes4(keccak256("royaltyInfo(uint256,uint256)")) == 0x2a55205a
    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;

    struct Item {
        uint256 id;
        address creator;
        string uri;
        address royaltyAddress;
        uint96 royaltyPercentage;
    }

    constructor() ERC721("Dev", "Dev") {}

    mapping(uint256 => Item) public Items;

    event itemCreated(uint256 tokenId, string tokenUri, address owner, address royaltyAddress, uint96 royaltyPercentage);
    event itemsCreated(uint256[] tokenIds, string[] tokenUris, address owner, address royaltyAddress, uint96 royaltyPercentage);

    function contractURI() public view returns (string memory) {
        return "https://staging.coinllectibles.art/test.txt";
    }

    function createItem(
        string memory uri,
        address creator,
        address royaltyAddress,
        uint96 royaltyPercentage
    ) public onlyOwner returns (uint256) {
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        _safeMint(creator, newItemId);
        Items[newItemId] = Item(
            newItemId,
            creator,
            uri,
            royaltyAddress,
            royaltyPercentage
        );

        emit itemCreated(newItemId, uri, creator,royaltyAddress, royaltyPercentage);

        return newItemId;
    }

    function createItems(
        string[] memory tokenUris,
        address owner,
        address royaltyAddress,
        uint96 royaltyPercentage
    ) public onlyOwner returns (uint256[] memory) {
        require(tokenUris.length > 0, "The token uris is not valid");

        uint256[] memory newItems = new uint256[](tokenUris.length);

        for (uint256 i = 0; i < tokenUris.length; i++) {
            _tokenIds.increment();
            uint256 newItemId = _tokenIds.current();
            _safeMint(owner, newItemId);

            Items[newItemId] = Item(
                newItemId,
                owner,
                tokenUris[i],
                royaltyAddress,
                royaltyPercentage
            );

            newItems[i] = newItemId;
        }

        emit itemsCreated(newItems, tokenUris, owner, royaltyAddress, royaltyPercentage);
        return newItems;
    }

    function tokenURI(uint256 _tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(
            _exists(_tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        return Items[_tokenId].uri;
    }

    function royaltyInfo(uint256 _tokenId, uint256 _salePrice)
        external
        view
        returns (address receiver, uint256 royaltyAmount)
    {
        if (_exists(_tokenId)) {
            Item memory _item = Items[_tokenId];
            return (
                _item.royaltyAddress,
                (_salePrice * _item.royaltyPercentage) / 1000
            );
        } else {
            return (address(0), 0);
        }
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721)
        returns (bool)
    {
        if (interfaceId == _INTERFACE_ID_ERC2981) {
            return true;
        }
        return super.supportsInterface(interfaceId);
    }
}