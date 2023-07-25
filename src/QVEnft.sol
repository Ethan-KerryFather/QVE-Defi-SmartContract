// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./tokens/QVEtoken.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";



contract QVEnft is ERC721Burnable{

    using Counters for Counters.Counter;
    using Strings for uint;
    Counters.Counter private _tokenIds;

    // [------Contracts , Address , Variables------] //
    QVEtoken private qveToken;
    address private qveDefiAddress;
    uint256 private lockupPeriod;

    // [------NFTmetadata------] //
    string private _name;
    string private _description;
    string private _imageUri;

    // [------Mappings------] //
    


    struct NftDetail {
        uint256 mintTime;
        uint256 lockupTime;
    }

    mapping(uint256 => NftDetail) public nftDetails;
    mapping(address => uint256[]) public ownedTokens;


    // [------Initializers------] //
    constructor(QVEtoken _qveToken) ERC721("QVE_staking", "QVE_GUARANTEE") {
        qveToken = _qveToken;
        lockupPeriod = 180 days;
    }

    // [------Set Metadata------] // 
    function setMetadata(string memory name_, string memory description_, string memory imageUri_) external returns(bool){
        _name = name_;
        _description = description_;
        _imageUri = imageUri_;
        return true;
    }
    // }


    // [------Mint NFT------] // 
    function mintStakingGuarantee(address staker, bool lockup) external returns(uint256){
        uint256 itemId = _tokenIds.current();
        _safeMint(staker, itemId, "");

        if(lockup){
            nftDetails[itemId] = NftDetail({
            mintTime: block.timestamp,
            lockupTime: 180 days
            });   
        }else{
            nftDetails[itemId] = NftDetail({
            mintTime: block.timestamp,
            lockupTime: 0 days
            });      
        }
        
        ownedTokens[staker].push(itemId);
        _tokenIds.increment();

        return ownedTokens[staker].length;
    }


    // [------Make Lockup Short------] // 
    function shortenLockup(uint256 QVEamount, address _qveDefiAddress, uint256 tokenId) external returns(bool){
        _setQVEdefi(_qveDefiAddress);
        require(qveToken.normal_transfer(msg.sender, qveDefiAddress, QVEamount), "qveToken transfer error"); 
        _setLockup(QVEamount, tokenId);
        return true;   
    }

    // [------Internal functions------] // 

    // function _baseURI() internal pure override returns (string memory) {
    //     return "https://ipfs.io/ipfs/QmWtmTFs2Uqb736jWQ1WHq8fV4NCX3Wuz1zrKPz9jj8tZt?filename=QVE.json";
    // }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId, batchSize = 1);
        if (from !=address(0)){
            require(block.timestamp >= nftDetails[tokenId].mintTime + nftDetails[tokenId].lockupTime, string(abi.encodePacked("token is still in lock period", Strings.toString(lockupPeriod))));
        }
    }

    function _setQVEdefi(address _qveDefiAddress) internal returns(bool){
        require(_qveDefiAddress != address(0), "_setQVEdefi error");
        qveDefiAddress = _qveDefiAddress;
        return true;
    }

    function _setLockup(uint256 QVEamount, uint256 tokenId) internal returns(bool){
        lockupPeriod = QVEamount == 0 ? 180 days : QVEamount == 100 ? 130 days : QVEamount == 200 ? 100 days : QVEamount == 1000 ? 0 days : 180 days;
        nftDetails[tokenId].lockupTime = lockupPeriod;
        return true;
    }  

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireMinted(tokenId);

        return string(abi.encodePacked(
            'data:application/json,{"name":"', _name, '", "description":"', _description, '", "image":"', _imageUri, '"}'
        ));
    }

    function burnNFT(uint256 tokenId) external returns(bool){
        _burn(tokenId);
        return true;
    }

   

    // [------ test functions ------] //
  

}

