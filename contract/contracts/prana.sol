// SPDX-License-Identifier: ISC

pragma solidity ^0.6.0;

import "../../node_modules/@openzeppelin/contracts/utils/Counters.sol";
import "../../node_modules/@openzeppelin/contracts/token/ERC721/ERC721.sol";


//prana main contract.


contract prana is ERC721 {

    using Counters for Counters.Counter;

    //to automate tokenId generation
    Counters.Counter private _tokenIdTracker;

    //AccessControl and Ownable can be added instead of owner if time permits
    constructor() ERC721("PranaBooks", "PBT") public {
        owner = msg.sender;
    }

    //address of the contract deployer
    address owner;

    //address of the helper contract
    address pranaHelperAddress;

    //Modifier for onlyOwner functions
    //this could be figured out with AccessControl if there's enough time
    modifier onlyOwner {
       require(msg.sender == owner, 'You are not the contract owner to call this function!');
       _;
    }

    // A nonce to ensure unique id for each new token.
    //deprecated in favor of _tokenIdTracker
    // uint256 public nonce;  // might need more work

    // struct to store book details. For each new title.
    // bytes32(encryptedBookDataHash) - the actual content of the book
    // bytes32(unencryptedBookDetailsCID) - cid to pull book cover and other details to show the world
    // This is where the linkage of the contract with storage mechanisms happen
    // address(publisherAddress) -  address of the content creator/publisher
    // uint256(bookPrice) - price of the book that the creator asks for direct purchase
    // uint256(transactionCut) - cut of further transactions on copies
    // that the creator lay claim to. Stored as a percentage.
    struct BookInfo{
        string encryptedBookDataHash;
        string unencryptedBookDetailsCID;
        address publisherAddress;
        uint256 bookPrice;
        uint256 transactionCut;
        uint256 bookSales;
    }

    // mapping for all books
    // ISBN is the key, its corresponding details is the value
    mapping(uint256 => BookInfo) internal booksInfo;

    // struct for token details and transactions
    // uint256(isbn) binds the token to the book it points to
    // uint256(copyNumber) to count which copy of the book the token is
    // so that people can brag about owning the 1st copy, 100th copy etc,
    // add sell them at a premium
    // uint256(resalePrice) is the price that tokenOwner asks to sell the token
    // bool(isUpForResale) is to advertise that the token is for sale
    // uint(rentingPrice) is the price for renting that the tokenOwner sets
    // bool (isUpForRenting) is to advertise that the token is for renting
    // address(rentee) so that the tokenOwner doesn't change and the token comes back after a while
    struct TokenDetails{
        uint256 isbn;
        uint256 copyNumber;
        // resale aspects
        uint256 resalePrice;
        bool isUpForResale;
        //Renting aspects (gonna be hard to properly figure out renting)
        uint256 rentingPrice;
        bool isUpForRenting;
        address rentee;
        uint256 rentedAtBlock;
    }


    // tokenId to TokenDetails mapping
    mapping (uint256 => TokenDetails) internal tokenData;

    // account balances, for everyone involved.
    mapping (address => uint256) internal accountBalance;


    //Event to emit when a new book is published with its ISBN and publisher address
    event BookPublished(address indexed publisher, uint256 indexed isbn, uint256 indexed price);

    //Event to emit when a tokenOwner puts out a token for sale
    event TokenForSale(uint256 indexed resalePrice, uint256 indexed isbn, uint256 indexed tokenId);

    //Event to emit when the tokenOwner puts out a token for renting
    event TokenForRenting(uint256 indexed rentingPrice, uint256 indexed isbn, uint256 indexed tokenId);

    //Event to emit when a token is rented
    event TokenRented(uint256 indexed isbn, uint256 indexed tokenId, address indexed rentee);

    // function to pass in the adddresses of each of the contract
    // so that they may refer to each other. Crude version
    function setPranaHelperAddress(address _pranaHelperAddress) public onlyOwner{
        pranaHelperAddress = _pranaHelperAddress;
    }

    // overriding _beforeTokenTransfer()
    // this ensure good behavior whenever a token transfer happens with money involved.
    // various actors get their cut before ownership is transfered
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override {
        if(from != address(0) && to != address(0)){
            _updateAccountBalances(tokenId);
        }
     }

    // an internal function to update the balances for each monetary transaction
    // not sure if msg.value works well with internal functions
    function _updateAccountBalances(uint256 tokenId) internal {

        // transactinCut for the author/publisher gets debited
        accountBalance[booksInfo[tokenData[tokenId].isbn].publisherAddress] += booksInfo[tokenData[tokenId].isbn].transactionCut*(msg.value/100);

        //the remaining money goes to the token owner
        accountBalance[ownerOf(tokenId)] += msg.value - (booksInfo[tokenData[tokenId].isbn].transactionCut*(msg.value/100));

    }

    //function to add book details into the chain i.e. publish the book
    function publishBook(
        string memory _encryptedBookDataHash, //TOCHECK: bytes32 vs bytes memory
        uint256 _isbn,
        uint256 _price,
        string memory _unencryptedBookDetailsCID,
        uint256 _transactionCut)
        public {
        require(booksInfo[_isbn].publisherAddress==address(0), "This book has already been published!");
        require(_transactionCut > 0 && _transactionCut < 80, "Your cut can't be more than 80% of the total");
        booksInfo[_isbn].encryptedBookDataHash = _encryptedBookDataHash;
        booksInfo[_isbn].publisherAddress = msg.sender;
        booksInfo[_isbn].bookPrice = _price;
        booksInfo[_isbn].unencryptedBookDetailsCID = _unencryptedBookDetailsCID;
        booksInfo[_isbn].transactionCut = _transactionCut;
        booksInfo[_isbn].bookSales = 0;

        //event that serves as an advertisement
        emit BookPublished(msg.sender, _isbn, _price);

    }

    //function to purchase books directly from the publisher.
    //New tokens will be minted here.
    //Could be assigned to Minter_Role in AccessControl and redirected from the helper contract
    function directPurchase(uint256 _isbn) public payable returns (bool) {
        //to revert back if the buyer doesn't have the price set by the author.
        require(booksInfo[_isbn].publisherAddress != address(0),"ISBN does not exist !");
        require(msg.value >= booksInfo[_isbn].bookPrice,"Insufficient funds ! Please pay the price as set by the author.");
        //a new tokenId is generated, and a new token is minted with that ID.
        uint256 tokenId = _tokenIdTracker.current();
        _safeMint(msg.sender, tokenId);
        _tokenIdTracker.increment();
        //once a token's succesfully minted, update the various details.
        booksInfo[_isbn].bookSales++;

        tokenData[tokenId].isbn = _isbn;
        tokenData[tokenId].copyNumber = booksInfo[_isbn].bookSales;
        tokenData[tokenId].isUpForResale = false;
        tokenData[tokenId].isUpForRenting = false;
        tokenData[tokenId].rentee = address(0);
        tokenData[tokenId].rentedAtBlock = 0;

        // the money goes to the plubisher's accountBalance.
        accountBalance[booksInfo[_isbn].publisherAddress] += msg.value;
        return true;
    }

    // function to put a token for sale
    // a user can update the resalePrice by just putting it up for sale again (may not be needed)
    function putTokenForSale(uint256 salePrice, uint256 tokenId) public {
        require(msg.sender == ownerOf(tokenId), "You are not this token's owner");
        require(tokenData[tokenId].isUpForRenting == false,
        "Can't put a token for sale while it's put for renting");
        tokenData[tokenId].resalePrice = salePrice;
        tokenData[tokenId].isUpForResale = true;

        // The helper contract gets approved for token transfer when someone's ready to buy
        approve(pranaHelperAddress, tokenId);
        // event that serves as advertisement for all
        emit TokenForSale(salePrice, tokenData[tokenId].isbn, tokenId);
    }

    // To buy a token that's been put for sale.
    // function will always be called by pranaHelper as the approved address for tokenId
    function buyToken(uint256 tokenId, address _tokenRecipient) public payable {
        require(tokenData[tokenId].isUpForResale == true,
        "This token hasn't been put for sale by the token owner");

        require(msg.value >= tokenData[tokenId].resalePrice,
        "Your price is too low for this token");


        safeTransferFrom(ownerOf(tokenId), _tokenRecipient, tokenId);

        // TODO:
        // _updateAccountBalances(tokenId) should go into transferFrom()
        // and safeTransferFrom() functions after mutability error resolution

        //  This went into _beforeTokenTransfer()
        // _updateAccountBalances(tokenId);

        tokenData[tokenId].isUpForResale = false;
        tokenData[tokenId].isUpForRenting = false;

    }

    // function to put a copy for renting, ownership doesn't change.
    function putForRent(uint256 _newPrice, uint256 tokenId) public{
        require(msg.sender == ownerOf(tokenId), "You are not this token's owner");
        require(tokenData[tokenId].isUpForResale == false,
        "Can't put a copy up for renting if it's already on sale!");
        if(tokenData[tokenId].rentee != address(0)){
                // the copy is rented for a two-week period, which is 100800 blocks.
                // assuming the block time is 12 seconds on average
                require(block.number > tokenData[tokenId].rentedAtBlock + 100800,
                "The renting period is not over yet to put it for renting again");
            }
        tokenData[tokenId].rentingPrice = _newPrice;
        tokenData[tokenId].isUpForRenting = true;
        tokenData[tokenId].rentee = address(0);//No one's rented it as of now
        emit TokenForRenting(_newPrice, tokenData[tokenId].isbn, tokenId);
    }

    //function to actually rent a copy for content consumption
    function rentToken(uint256 tokenId) public payable {
        require(tokenData[tokenId].isUpForRenting == true,
        "This copy hasn't been put for renting by the owner");
        require(tokenData[tokenId].rentee == address(0),
        "This copy has been rented by someone already");
        require(msg.value >= tokenData[tokenId].rentingPrice,
        "Your price isn't sufficient to rent this copy");

        tokenData[tokenId].rentee = msg.sender;
        tokenData[tokenId].rentedAtBlock = block.number;

        _updateAccountBalances(tokenId);

        emit TokenRented(tokenData[tokenId].isbn, tokenId, msg.sender);

    }

    //function to actually consume the content  you've bought/rented
    function consumeContent(uint256 tokenId) public view returns(string memory){
        require(ownerOf(tokenId) == msg.sender || tokenData[tokenId].rentee == msg.sender,
        "You are not authorized to view this copy!");
        if(ownerOf(tokenId) == msg.sender){
            require(tokenData[tokenId].isUpForRenting == false,
            "You have put your copy for renting, please take it down to view the content");
            if(tokenData[tokenId].rentee != address(0)){
                // the copy is rented for a two-week period, which is 100800 blocks.
                // assuming the block time is 12 seconds on average
                require(block.number > tokenData[tokenId].rentedAtBlock + 100800,
                "The renting period is not over yet for you to consume the content");
            }
        }
        else if(tokenData[tokenId].rentee == msg.sender){
            require(block.number <= tokenData[tokenId].rentedAtBlock + 100800,
            "Your rental period has expired");
        }
        return booksInfo[tokenData[tokenId].isbn].encryptedBookDataHash;
    }

    // function to get the balances stored in contract back into the respective owners' account
    // this is to mainly to reduce the number of transactions and transaction cost associated with it.
    // WARNING: Extensive testing required before this can be finalized!
    function withdrawBalance() public payable{
        require(accountBalance[msg.sender] > 0, "You don't have any balance to withdraw");
        (msg.sender).transfer(accountBalance[msg.sender]);
        accountBalance[msg.sender] = 0;
    }

    //function to view balance
    function viewBalance() public view returns(uint256){
        return accountBalance[msg.sender];
    }

    //function to get book details with the tokenId
    //returns CID of coverpic+bookname
    function viewTokenBookDetails(uint256 _tokenId) public view returns (string memory) {
        require(booksInfo[tokenData[_tokenId].isbn].publisherAddress!=address(0), "This book is not on the platform");
        return booksInfo[tokenData[_tokenId].isbn].unencryptedBookDetailsCID;
    }
}
