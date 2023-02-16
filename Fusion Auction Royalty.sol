// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FusionAuctionRoyalty is Ownable {
    using SafeMath for uint256;

    struct SaleItem {
        uint256 id; // start: 0
        address tokenAddress; // Contract address ERC-721 of tokenId
        uint256 tokenId; //
        address payable seller; 
        uint256 minPrice; // ex: 0.1 coin (18 decimals) => 0.1 * (10 ** 18)
        bytes32 status; // enum: Open, Completed, Cancelled
        uint256 bidAmountIncrease;
        uint256 highestBid;
        address highestBidder;
        uint256 auctionStart;
        uint256 auctionEnd;
        uint256 cryptoId;
        uint256 fee;
    }

    SaleItem[] public itemsForSale;

    struct Crypto {
        uint256 id;
        address cryptoAddress;
        string cryptoName;
        bool status;
    }

    Crypto[] public Cryptos;

    mapping (address => mapping (uint256 => uint256)) activeItemIds;
    mapping (address => bool) private _isExcludedFromFee;

    /// bytes4(keccak256("royaltyInfo(uint256,uint256)")) == 0x2a55205a
    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;

    /*
     * Default values that are used if not specified by the NFT seller.
     */
    uint32 public defaultBidAmountIncrease;
    address private _marketWalletAddress;

    constructor() {
        _marketWalletAddress = _msgSender();
        _isExcludedFromFee[_msgSender()] = true; // Exclude owner from fee
        defaultBidAmountIncrease = 100;

        itemsForSale.push(SaleItem(0, address(0), 0, payable(address(0)), 0, "Cancelled", 0, 0, address(0), 0, 0, 0, 0));
        Cryptos.push(Crypto(0, address(0), "BNB", true));
    }

    event itemAdded(uint256 marketId, uint256 tokenId, address tokenAddress, uint256 minPrice, uint256 cryptoId, uint256 fee);
    event itemCancelled(uint256 marketId, address seller);
    event itemUpdated(uint256 marketId, address seller, uint256 minPrice, uint256 auctionStart, uint256 auctionEnd, uint256 bidAmountIncrease);
    event itemBidMade(uint256 marketId, uint256 tokenId, address tokenAddress, address sender, uint256 amount);
    event itemCompleted(uint256 marketId, address highestBidder, uint256 highestBid);
    event cryptoAdded(uint256 cryptoId, address sender, address cryptoAddress, string cryptoName);
    event cryptoUpdated(uint256 cryptoId, address cryptoAddress, bool status);

    function setCryptoAddress(address cryptoAddress, string memory cryptoName) external onlyOwner {
        uint256 cryptoId = Cryptos.length;
        Cryptos.push(Crypto(cryptoId, cryptoAddress, cryptoName, true));
        emit cryptoAdded(cryptoId, _msgSender(), cryptoAddress, cryptoName);
    }

    function setCryptoStatus(uint256 cryptoId, bool status) external onlyOwner {
        Cryptos[cryptoId].status = status;
        emit cryptoUpdated(cryptoId, Cryptos[cryptoId].cryptoAddress, status);
    }

    function setMarketAddress(address account) external onlyOwner {
	    _marketWalletAddress = account;
    }

    modifier onlyItemOwner(address tokenAddress, uint256 tokenId) {
        IERC721 tokenContract = IERC721(tokenAddress);
        require(tokenContract.ownerOf(tokenId) == msg.sender, "CA010");
        _;
    }

    modifier validItemOwner(uint256 marketId) {
        require(msg.sender != itemsForSale[marketId].seller, "CA011");
        _;
    }

    modifier hasTransferApproval(address tokenAddress, uint256 tokenId) {
        IERC721 tokenContract = IERC721(tokenAddress);
        require(tokenContract.getApproved(tokenId) == address(this) || tokenContract.isApprovedForAll(msg.sender, address(this)), "CA012");
        _;
    }

    modifier itemExists(uint256 marketId) {
        require(marketId < itemsForSale.length && itemsForSale[marketId].id == marketId, "CA013");
        _;
    }

    modifier isForSale(uint256 marketId) {
        require(itemsForSale[marketId].status == "Open", "CA014");
        _;
    }

    modifier isExpirationTime(uint256 marketId) {
        require(itemsForSale[marketId].auctionStart < block.timestamp && itemsForSale[marketId].auctionEnd > block.timestamp, "CA015");
        _;
    }

    modifier isValidBidAmout(uint256 marketId, uint256 _amount) {
        uint256 highestBid = _getHighestBid(marketId);

        uint256 cryptoId = itemsForSale[marketId].cryptoId;
        address cryptoAddress = Cryptos[cryptoId].cryptoAddress;
        if (cryptoId == 0) {
            _amount = msg.value;
        } else {
            require(IERC20(cryptoAddress).balanceOf(msg.sender) >= _amount, "CA016");
            require(IERC20(cryptoAddress).allowance(msg.sender, address(this)) >= _amount, "CA017");
        }
        require(_amount > 0 && _amount >= highestBid, "CA018");
        _;
    }

    modifier validAuctionTime(uint256 auctionEnd) {
        require(auctionEnd > 0, "CA019");
        _;
    }

    modifier validCryptoId(uint256 cryptoId) {
        require(cryptoId < Cryptos.length, "CA021");
        Crypto storage crypto = Cryptos[cryptoId];
        require(crypto.status == true, "CA022");
        _;
    }

    function calculateTransFee(uint256 marketId, uint256 _amount) private view returns (uint256) {
        uint256 _marketFee = itemsForSale[marketId].fee;
        if (_marketFee == 0) {
            return 0;
        }
        return _amount * _marketFee / 1000;
    }

    function addItemToMarket(
        uint256 tokenId,
        address tokenAddress,
        uint256 minPrice,
        uint256 auctionStart,
        uint256 auctionEnd,
        uint256 bidAmountIncrease,
        uint256 cryptoId,
        uint256 fee
    ) external returns (uint256) {
        _beforeAddItem(tokenAddress, tokenId, auctionEnd, cryptoId);
        return _addItemToMarket(tokenId, tokenAddress, minPrice, auctionStart, auctionEnd, bidAmountIncrease, cryptoId, fee);
    }

    function _beforeAddItem(
        address tokenAddress,
        uint256 tokenId,
        uint256 auctionEnd,
        uint256 cryptoId)
        onlyItemOwner(tokenAddress, tokenId)
        hasTransferApproval(tokenAddress, tokenId)
        validAuctionTime(auctionEnd)
        validCryptoId(cryptoId) internal view returns (bool) {
        require(activeItemIds[tokenAddress][tokenId] == 0, "CA020");
        return true;
    }

    function _addItemToMarket(
        uint256 tokenId,
        address tokenAddress,
        uint256 minPrice,
        uint256 auctionStart,
        uint256 auctionEnd,
        uint256 bidAmountIncrease,
        uint256 cryptoId,
        uint256 fee
    ) internal returns (uint256) {
        IERC721(tokenAddress).transferFrom(msg.sender, address(this), tokenId);

        if (bidAmountIncrease == 0) {
            bidAmountIncrease = defaultBidAmountIncrease;
        }

        uint256 newItemId = itemsForSale.length;
        itemsForSale.push(SaleItem(
            newItemId,
            tokenAddress,
            tokenId,
            payable(msg.sender),
            minPrice,
            "Open",
            bidAmountIncrease,
            0,
            address(0),
            block.timestamp + auctionStart,
            block.timestamp + auctionStart + auctionEnd,
            cryptoId,
            fee
        ));
        activeItemIds[tokenAddress][tokenId] = newItemId;

        assert(itemsForSale[newItemId].id == newItemId);
        emit itemAdded(newItemId, tokenId, tokenAddress, minPrice, cryptoId, fee);
        return newItemId;
    }

    function _reversePreviousBidAndUpdateHighestBid(uint256 marketId, uint256 _amount, uint256 cryptoId) internal {
        address prevHighestBidder = itemsForSale[marketId].highestBidder;
        uint256 prevHighestBid = itemsForSale[marketId].highestBid;

        _updateHighestBid(marketId, _amount);

        if (prevHighestBidder != address(0)) {
            _payout(marketId, prevHighestBidder, prevHighestBid, cryptoId, false);
        }

        if (cryptoId != 0) {
            address cryptoAddress = Cryptos[cryptoId].cryptoAddress;
            IERC20(cryptoAddress).transferFrom(msg.sender, address(this), _amount);
        }
    }

    function _payout(
        uint256 marketId,
        address _recipient,
        uint256 _amount,
        uint256 cryptoId,
        bool withFee) internal returns (bool)
    {
        bool takeFee = true;
        address cryptoAddress = Cryptos[cryptoId].cryptoAddress;
        uint256 remainingAmount = _amount;
    
        if (!withFee || _isExcludedFromFee[_recipient]) {
            takeFee = false;
        }

        if (takeFee) {
            uint256 transferFee = calculateTransFee(marketId, _amount);
            if (transferFee != 0 && _marketWalletAddress != address(0)) {
                remainingAmount = remainingAmount.sub(transferFee);

                if (cryptoId == 0) {
                    payable(_marketWalletAddress).transfer(transferFee);
                } else {
                    IERC20(cryptoAddress).transfer(_marketWalletAddress, transferFee);
                }
            }

            SaleItem memory item = itemsForSale[marketId];

            (address receiver, uint256 royaltyAmount) = checkRoyalty(
                item.tokenAddress,
                item.tokenId,
                _amount
            );
            if (receiver != address(0) && royaltyAmount != 0) {
                remainingAmount = remainingAmount.sub(royaltyAmount);
                if (cryptoId == 0) {
                    payable(receiver).transfer(royaltyAmount);
                } else {
                    IERC20(cryptoAddress).transfer(receiver, royaltyAmount);
                }
            }
        }
        if (cryptoId == 0) {
            payable(_recipient).transfer(remainingAmount);
        } else {
            IERC20(cryptoAddress).transfer(_recipient, remainingAmount);
        }
        return true;
    }

    function checkRoyalty(
        address tokenAddress,
        uint256 _tokenId,
        uint256 _amount
    ) public view returns (address, uint256) {
        IERC2981 tokenContract = IERC2981(tokenAddress);
        bool supportInterface = tokenContract.supportsInterface(
            _INTERFACE_ID_ERC2981
        );
        if (supportInterface) {
            return tokenContract.royaltyInfo(_tokenId, _amount);
        }
        return (address(0), 0);
    }

    /******************************************************************
     * Internal functions that update bid parameters and reverse bids *
     * to ensure contract only holds the highest bid.                 *
     ******************************************************************/
    function _updateHighestBid(uint256 marketId, uint256 _amount) internal {
        itemsForSale[marketId].highestBidder = msg.sender;
        itemsForSale[marketId].highestBid = _amount;
    }

    function makeBid(uint256 marketId, uint256 _amount) payable external {
        uint256 cryptoId = itemsForSale[marketId].cryptoId;
        _beforeMakeBid(marketId, _amount, cryptoId);
        _makeBid(marketId, _amount);
    }

    function _beforeMakeBid(uint256 marketId, uint256 _amount, uint256 cryptoId) internal 
        itemExists(marketId)
        isForSale(marketId)
        isExpirationTime(marketId)
        validItemOwner(marketId)
        isValidBidAmout(marketId, _amount)
        validCryptoId(cryptoId) returns (bool) {
        return true;
    }

    /********************************************************************
     * Additionally, a buyer can pay the asking price to conclude a sale*
     * of an NFT.                                                      *
     ********************************************************************/
    function _makeBid(uint256 marketId, uint256 _amount) internal {
        uint256 minPrice = _getHighestBid(marketId);
        uint256 cryptoId = itemsForSale[marketId].cryptoId;
        if (cryptoId == 0) {
            _amount = msg.value;
            require(_amount >= minPrice, "CA005");
        } else {
            require(IERC20(Cryptos[cryptoId].cryptoAddress).balanceOf(msg.sender) >= _amount, "CA003");
            require(IERC20(Cryptos[cryptoId].cryptoAddress).allowance(msg.sender, address(this)) >= _amount, "CA004");
        }
        _reversePreviousBidAndUpdateHighestBid(marketId, _amount, cryptoId);
        emit itemBidMade(marketId, itemsForSale[marketId].tokenId, itemsForSale[marketId].tokenAddress, msg.sender, _amount);
    }

    function cancelItem(uint256 marketId) external
        itemExists(marketId)
        isForSale(marketId) {
        require(msg.sender == itemsForSale[marketId].seller, "CA001");
        require(itemsForSale[marketId].highestBidder == address(0), "CA002");

        itemsForSale[marketId].status = "Cancelled";
        activeItemIds[itemsForSale[marketId].tokenAddress][itemsForSale[marketId].tokenId] = 0;

        IERC721(itemsForSale[marketId].tokenAddress).transferFrom(address(this), itemsForSale[marketId].seller, itemsForSale[marketId].tokenId);

        emit itemCancelled(marketId, itemsForSale[marketId].seller);
    }

    function updateItemOnMarket(
        uint256 marketId,
        uint256 minPrice,
        uint256 auctionStart,
        uint256 auctionEnd,
        uint256 bidAmountIncrease) external
        itemExists(marketId)
        isForSale(marketId)
        validAuctionTime(auctionEnd) {
        require(msg.sender == itemsForSale[marketId].seller, "CA006");
        require(block.timestamp < itemsForSale[marketId].auctionStart, "CA007");

        itemsForSale[marketId].minPrice = minPrice;
        itemsForSale[marketId].auctionStart = block.timestamp + auctionStart;
        itemsForSale[marketId].auctionEnd = block.timestamp + auctionStart + auctionEnd;
        itemsForSale[marketId].bidAmountIncrease = bidAmountIncrease;

        emit itemUpdated(
            marketId,
            msg.sender,
            itemsForSale[marketId].minPrice,
            itemsForSale[marketId].auctionStart,
            itemsForSale[marketId].auctionEnd,
            itemsForSale[marketId].bidAmountIncrease
        );
    }

    function withdraw(uint256 marketId) external
        itemExists(marketId)
        isForSale(marketId) {
        require(msg.sender == itemsForSale[marketId].highestBidder || msg.sender == itemsForSale[marketId].seller, "CA008");
        require(block.timestamp > itemsForSale[marketId].auctionEnd, "CA009");

        itemsForSale[marketId].status = "Completed";
        activeItemIds[itemsForSale[marketId].tokenAddress][itemsForSale[marketId].tokenId] = 0;
        uint256 cryptoId = itemsForSale[marketId].cryptoId;

        _payout(marketId, itemsForSale[marketId].seller, itemsForSale[marketId].highestBid, cryptoId, true);
        IERC721(itemsForSale[marketId].tokenAddress).transferFrom(address(this), itemsForSale[marketId].highestBidder, itemsForSale[marketId].tokenId);

        emit itemCompleted(marketId, itemsForSale[marketId].highestBidder, itemsForSale[marketId].highestBid);
    }

    function excludeFromFee(address account) external onlyOwner {
        _isExcludedFromFee[account] = true;
    }

    function includeInFee(address account) external onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    function isExcludeFromFee(address account) public view returns (bool) {
        return _isExcludedFromFee[account] == true;
    }

    function _getHighestBid(uint256 marketId)
        internal
        view
        itemExists(marketId)
        returns (uint256)
    {
        SaleItem memory item = itemsForSale[marketId];
        if (item.highestBid == 0) {
            return item.minPrice;
        }
        return item.highestBid + item.bidAmountIncrease;
    }

    function getActiveItemId(address tokenAddress, uint256 tokenId) public view returns (uint256) {
        return activeItemIds[tokenAddress][tokenId];
    }
}


///
/// @dev Interface for the NFT Royalty Standard
///
interface IERC2981 is IERC721 {
    /// @notice Called with the sale price to determine how much royalty
    //          is owed and to whom.
    /// @param _tokenId - the NFT asset queried for royalty information
    /// @param _salePrice - the sale price of the NFT asset specified by _tokenId
    /// @return receiver - address of who should be sent the royalty payment
    /// @return royaltyAmount - the royalty payment amount for _salePrice
    function royaltyInfo(uint256 _tokenId, uint256 _salePrice)
        external
        view
        returns (address receiver, uint256 royaltyAmount);
}

/**
 * @title SafeMath
 * @dev Math operations with safety checks that revert on error
 * TODO: remove once open zeppelin update to solc 0.5.0
 */
library SafeMath {
    /**
     * @dev Multiplies two numbers, reverts on overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b);

        return c;
    }

    /**
     * @dev Subtracts two numbers, reverts on overflow (i.e. if subtrahend is greater than minuend).
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Adds two numbers, reverts on overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a);

        return c;
    }

    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }
}