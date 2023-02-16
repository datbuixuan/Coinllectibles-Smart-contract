// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FusionCustodianWallet is Ownable {
    mapping (uint256 => mapping (address => mapping (uint256 => bool))) userTokenIds; // ERC721 (Fusion NFT, ....)
    mapping (uint256 => mapping (address => uint256)) userCryptoAmounts; // ERC20 (COTK, BUSD....)

    event TokenIdAdded(uint256 userId, address contractAddress, uint256 tokenId);
    event TokenIdWithdrawn(uint256 userId, address contractAddress, uint256 tokenId);
    event TokenIdTranferred(uint256 userId, address contractAddress, uint256 tokenId, uint256 receiverId);
    event TokenIdTranferredTo(uint256 userId, address contractAddress, uint256 tokenId, address receiverAddress);

    event AmountAdded(uint256 userId, address contractAddress, uint256 amount);
    event AmountWithdrawn(uint256 userId, address contractAddress, uint256 amount);
    event AmountTranferred(uint256 userId, address contractAddress, uint256 amount, uint256 receiverId);
    event AmountTranferredTo(uint256 userId, address contractAddress, uint256 amount, address receiverAddress);

    function addTokenId(uint256 userId, address contractAddress, uint256 tokenId) external onlyOwner {
        bool _tokenId = getTokenId(userId, contractAddress, tokenId);
        require(_tokenId == false, "TokenId already exists");

        IERC721 tokenContract = IERC721(contractAddress);
        require(tokenContract.isApprovedForAll(msg.sender, address(this)) || tokenContract.getApproved(tokenId) == address(this), "Item is not approved for this contract");
        IERC721(contractAddress).transferFrom(msg.sender, address(this), tokenId);
        userTokenIds[userId][contractAddress][tokenId] = true;

        emit TokenIdAdded(userId, contractAddress, tokenId);
    }

    function addCryptoAmount(uint256 userId, address contractAddress, uint256 amount) external payable onlyOwner {
        if (contractAddress == address(0)) {
            require(msg.value != 0);
            amount = msg.value;
        } else {
            require(amount != 0);
            IERC20 _contractAddress = IERC20(contractAddress);
            require(_contractAddress.balanceOf(msg.sender) >= amount, "Not enough balance");
            require(_contractAddress.allowance(msg.sender, address(this)) >= amount, "Not approved with amount");
            _contractAddress.transferFrom(msg.sender, address(this), amount);
        }
        userCryptoAmounts[userId][contractAddress] = userCryptoAmounts[userId][contractAddress] + amount;

        emit AmountAdded(userId, contractAddress, amount);
    }

    function transferTokenId(uint256 userId, address contractAddress, uint256 tokenId, uint256 receiverId) external onlyOwner {
        bool _tokenId = userTokenIds[userId][contractAddress][tokenId];
        require(_tokenId == true, "TokenId does not exist");

        userTokenIds[receiverId][contractAddress][tokenId] = true;
        userTokenIds[userId][contractAddress][tokenId] = false;

        emit TokenIdTranferred(userId, contractAddress, tokenId, receiverId);
    }

    function withdrawTokenId(uint256 userId, address contractAddress, uint256 tokenId) external onlyOwner {
        bool _tokenId = userTokenIds[userId][contractAddress][tokenId];
        require(_tokenId == true, "TokenId does not exist");

        IERC721(contractAddress).transferFrom(address(this), msg.sender, tokenId);
        userTokenIds[userId][contractAddress][tokenId] = false;
        
        emit TokenIdWithdrawn(userId, contractAddress, tokenId);
    }

    function transferTokenIdTo(uint256 userId, address contractAddress, uint256 tokenId, address receiverAddress) external onlyOwner {
        bool _tokenId = userTokenIds[userId][contractAddress][tokenId];
        require(_tokenId == true, "TokenId does not exist");

        IERC721(contractAddress).transferFrom(address(this), receiverAddress, tokenId);
        userTokenIds[userId][contractAddress][tokenId] = false;

        emit TokenIdTranferredTo(userId, contractAddress, tokenId, receiverAddress);
    }

    function _payout(address contractAddress, address receiverAddress, uint256 amount) internal {
        uint256 balance = 0;
        if (contractAddress == address(0)) {
            balance = address(this).balance;
            require(balance != 0 && amount <= balance, "Balance not enough");
            payable(receiverAddress).transfer(amount);
        } else {
            balance = IERC20(contractAddress).balanceOf(address(this));
            require(balance != 0 && amount <= balance, "Balance not enough");
            IERC20(contractAddress).transferFrom(address(this), receiverAddress, amount);
        }
    }

    function transferAmount(uint256 userId, address contractAddress, uint256 amount, uint256 receiverId) external onlyOwner {
        uint256 _amount = userCryptoAmounts[userId][contractAddress];
        require(_amount != 0 && amount != 0 && amount <= _amount, "Amount not enough");

        userCryptoAmounts[receiverId][contractAddress] = userCryptoAmounts[receiverId][contractAddress] + amount;
        userCryptoAmounts[userId][contractAddress] = _amount - amount;

        emit AmountTranferred(userId, contractAddress, amount, receiverId);
    }

    function withdrawAmount(uint256 userId, address contractAddress, uint256 amount) external onlyOwner {
        uint256 _amount = userCryptoAmounts[userId][contractAddress];
        require(_amount != 0 &&  amount != 0 && amount <= _amount, "Amount not enough");

        _payout(contractAddress, msg.sender, amount);
        userCryptoAmounts[userId][contractAddress] = _amount - amount;

        emit AmountWithdrawn(userId, contractAddress, amount);
    }

    function transferAmountTo(uint256 userId, address contractAddress, uint256 amount, address receiverAddress) external onlyOwner {
        uint256 _amount = userCryptoAmounts[userId][contractAddress];
        require(_amount != 0 &&  amount != 0 && amount <= _amount, "Amount not enough");

        _payout(contractAddress, receiverAddress, amount);
        userCryptoAmounts[userId][contractAddress] = _amount - amount;

        emit AmountTranferredTo(userId, contractAddress, amount, receiverAddress);
    }

    function getTokenId(uint256 userId, address contractAddress, uint256 tokenId) public view returns(bool) {
        return userTokenIds[userId][contractAddress][tokenId];
    }

    function getAmount(uint256 userId, address contractAddress) public view returns(uint256) {
        return userCryptoAmounts[userId][contractAddress];
    }
}