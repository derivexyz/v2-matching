pragma solidity ^0.8.27;

import {AccessControlUpgradeable} from "openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20Upgradeable, Initializable} from "openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";


contract FxToken is Initializable, ERC20Upgradeable, AccessControlUpgradeable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER");
    bytes32 public constant BLOCK_MANAGER_ROLE = keccak256("BLOCK_MANAGER");
    // keccak256(abi.encode(uint256(keccak256("FxToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FxTokenStorageLocation = 0xfb8997de7bd810675586dece12917931ae29ba246c9d4d120b17fca6e2b68f00;


    /// @custom:storage-location erc7201:FxToken
    struct FxTokenStorage {
        uint8 decimals;
        mapping(address user => bool blocked) isBlocked;
    }

    function _getStorage() internal pure returns (FxTokenStorage storage s) {
        bytes32 position = FxTokenStorageLocation;
        assembly {
            s.slot := position
        }
    }

    ///////////
    // Setup //
    ///////////

    constructor() {
        _disableInitializers();
    }

    function initialize(string memory _name, string memory _symbol, uint _decimals) external initializer {
        __ERC20_init_unchained(_name, _symbol);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        FxTokenStorage storage s = _getStorage();
        s.decimals = uint8(_decimals);
    }

    ////////////////
    // Block List //
    ////////////////

    function setBlocked(address user, bool blocked) public onlyRole(BLOCK_MANAGER_ROLE) {
        require(user != address(0), "FxToken: cannot block zero address");
        FxTokenStorage storage s = _getStorage();
        s.isBlocked[user] = blocked;
        emit Blocked(user, blocked);
    }

    function isBlocked(address user) public view returns (bool) {
        return _getStorage().isBlocked[user];
    }

    ///////////////
    // Mint/Burn //
    ///////////////

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        FxTokenStorage storage s = _getStorage();
        require(!s.isBlocked[msg.sender], "FxToken: minter is blocked");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public onlyRole(MINTER_ROLE) {
        FxTokenStorage storage s = _getStorage();
        require(!s.isBlocked[msg.sender], "FxToken: minter is blocked");

        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        // Skip the _update call to avoid checking blocked status
        super._update(from, address(0), amount);
    }

    /////////////////////
    // ERC20 Overrides //
    /////////////////////

    function _update(address from, address to, uint256 value) internal override {
        FxTokenStorage storage s = _getStorage();
        require(!s.isBlocked[from], "FxToken: sender is blocked");
        require(!s.isBlocked[to], "FxToken: recipient is blocked");
        super._update(from, to, value);
    }

    function _spendAllowance(address owner, address spender, uint256 value) internal override {
        FxTokenStorage storage s = _getStorage();
        require(!s.isBlocked[spender], "FxToken: spender is blocked");
        super._spendAllowance(owner, spender, value);
    }

    function decimals() public view virtual override returns (uint8) {
        return _getStorage().decimals;
    }

    ////////////
    // Events //
    ////////////

    event Blocked(address indexed user, bool blocked);
}
