// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract NFTTicketing is ERC721, Ownable {
    using Counters for Counters.Counter;
    
    Counters.Counter private _tokenIdCounter;
    
    struct Event {
        string name;
        uint256 price;
        uint256 totalSupply;
        uint256 soldTickets;
        uint256 eventDate;
        bool isActive;
    }
    
    struct Ticket {
        uint256 eventId;
        bool isUsed;
        uint256 purchaseTime;
    }
    
    mapping(uint256 => Event) public events;
    mapping(uint256 => Ticket) public tickets;
    mapping(uint256 => bool) public eventExists;
    
    uint256 public eventCounter;
    
    event EventCreated(uint256 indexed eventId, string name, uint256 price, uint256 totalSupply, uint256 eventDate);
    event TicketPurchased(uint256 indexed tokenId, uint256 indexed eventId, address indexed buyer);
    event TicketUsed(uint256 indexed tokenId, uint256 indexed eventId);
    event EventToggled(uint256 indexed eventId, bool isActive);
    
    constructor() ERC721("EventTicket", "ETKT") Ownable(msg.sender) {}
    
    // 1. Create Event - Only owner can create events
    function createEvent(
        string memory _name,
        uint256 _price,
        uint256 _totalSupply,
        uint256 _eventDate
    ) external onlyOwner {
        require(_eventDate > block.timestamp, "Event date must be in the future");
        require(_totalSupply > 0, "Total supply must be greater than 0");
        
        eventCounter++;
        events[eventCounter] = Event({
            name: _name,
            price: _price,
            totalSupply: _totalSupply,
            soldTickets: 0,
            eventDate: _eventDate,
            isActive: true
        });
        
        eventExists[eventCounter] = true;
        
        emit EventCreated(eventCounter, _name, _price, _totalSupply, _eventDate);
    }
    
    // 2. Purchase Ticket - Users can buy tickets for events
    function purchaseTicket(uint256 _eventId) external payable {
        require(eventExists[_eventId], "Event does not exist");
        require(events[_eventId].isActive, "Event is not active");
        require(events[_eventId].soldTickets < events[_eventId].totalSupply, "Event sold out");
        require(msg.value >= events[_eventId].price, "Insufficient payment");
        require(block.timestamp < events[_eventId].eventDate, "Event has already occurred");
        
        _tokenIdCounter.increment();
        uint256 tokenId = _tokenIdCounter.current();
        
        _safeMint(msg.sender, tokenId);
        
        tickets[tokenId] = Ticket({
            eventId: _eventId,
            isUsed: false,
            purchaseTime: block.timestamp
        });
        
        events[_eventId].soldTickets++;
        
        // Refund excess payment
        if (msg.value > events[_eventId].price) {
            payable(msg.sender).transfer(msg.value - events[_eventId].price);
        }
        
        emit TicketPurchased(tokenId, _eventId, msg.sender);
    }
    
    // 3. Use Ticket - Mark ticket as used (for venue entry)
    function useTicket(uint256 _tokenId) external onlyOwner {
        require(_ownerOf(_tokenId) != address(0), "Ticket does not exist");
        require(!tickets[_tokenId].isUsed, "Ticket already used");
        
        uint256 eventId = tickets[_tokenId].eventId;
        require(block.timestamp >= events[eventId].eventDate - 1 hours, "Too early to use ticket");
        require(block.timestamp <= events[eventId].eventDate + 6 hours, "Ticket expired");
        
        tickets[_tokenId].isUsed = true;
        
        emit TicketUsed(_tokenId, eventId);
    }
    
    // 4. Toggle Event Status - Owner can activate/deactivate events
    function toggleEventStatus(uint256 _eventId) external onlyOwner {
        require(eventExists[_eventId], "Event does not exist");
        
        events[_eventId].isActive = !events[_eventId].isActive;
        
        emit EventToggled(_eventId, events[_eventId].isActive);
    }
    
    // 5. Withdraw Funds - Owner can withdraw collected funds
    function withdrawFunds() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");
        
        payable(owner()).transfer(balance);
    }
    
    // Additional view functions for better functionality
    function getEvent(uint256 _eventId) external view returns (Event memory) {
        require(eventExists[_eventId], "Event does not exist");
        return events[_eventId];
    }
    
    function getTicket(uint256 _tokenId) external view returns (Ticket memory) {
        require(_ownerOf(_tokenId) != address(0), "Ticket does not exist");
        return tickets[_tokenId];
    }
    
    function getTicketsByOwner(address _owner) external view returns (uint256[] memory) {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);
        uint256 currentIndex = 0;
        
        for (uint256 i = 1; i <= _tokenIdCounter.current(); i++) {
            if (_ownerOf(i) != address(0) && ownerOf(i) == _owner) {
                tokenIds[currentIndex] = i;
                currentIndex++;
            }
        }
        
        return tokenIds;
    }
    
    // Override transfer functions to add restrictions
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        address from = _ownerOf(tokenId);
        
        // Prevent transfer if ticket is used (skip check for minting)
        if (from != address(0)) {
            require(!tickets[tokenId].isUsed, "Cannot transfer used ticket");
        }
        
        return super._update(to, tokenId, auth);
    }
}
