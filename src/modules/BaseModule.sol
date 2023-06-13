import "../interfaces/IMatchingModule.sol";
import {Matching} from  "../Matching.sol";

abstract contract BaseModule is IMatchingModule {
  Matching public immutable matching;

  mapping(address owner => mapping (uint nonce => bool used)) public usedNonces;

  constructor (Matching _matching) {
    matching = _matching;
  }


  function _transferAccounts(VerifiedOrder[] memory orders) internal returns (uint[] memory accountIds, address[] memory owners) {
    accountIds = new uint[](orders.length);
    owners = new address[](orders.length);
    for (uint i = 0; i < orders.length; ++i) {
      matching.accounts().transferFrom(address(this), address(matching), orders[i].accountId);
    }
  }

  function _checkAndInvalidateNonce(address owner, uint nonce) internal {
    require(!usedNonces[owner][nonce], "nonce already used");
    usedNonces[owner][nonce] = true;
  }

  modifier onlyMatching() {
    require(msg.sender == address(matching), "only matching");
    _;
  }
}