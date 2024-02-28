// SPDX-License-Identifier: MIT OR Apache-2.0

pragma solidity ^0.8.0;

import {IL2StandardToken} from "./interfaces/IL2StandardToken.sol";
import {IEthToken} from "./interfaces/IEthToken.sol";
import {MSG_VALUE_SYSTEM_CONTRACT, DEPLOYER_SYSTEM_CONTRACT, BOOTLOADER_FORMAL_ADDRESS} from "./Constants.sol";

/**
 * @author Matter Labs
 * @notice Native ETH contract.
 * @dev It does NOT provide interfaces for personal interaction with tokens like `transfer`, `approve`, and `transferFrom`.
 * Instead, this contract is used by `MsgValueSimulator` and `ContractDeployer` system contracts
 * to perform the balance changes while simulating the `msg.value` Ethereum behavior.
 */
contract L2EthToken is IL2StandardToken, IEthToken {
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @notice The balances of the users.
    mapping(address => uint256) public override balanceOf;

    /// @notice The total amount of tokens that have been minted.
    uint256 public totalSupply;

    /// @notice The address of the L2EthBridge
    address public override l2Bridge;

    /// @notice There is no "ETH" token contract on L1, but we use "0" as the formal address
    /// for it.
    address public constant override l1Address = address(0);

    // TODO: We need to come up with a safe way to initialize this contract.
    // Currently it is fine, because it is assumed that operator will initiate it first.
    // But it is critical thing to change before mainntet!
    function initialization(address _l2Bridge) external {
        require(l2Bridge == address(0));
        require(_l2Bridge != address(0));
        l2Bridge = _l2Bridge;
    }

    modifier onlyBridge() {
        require(msg.sender == l2Bridge);
        _;
    }

    /// @notice Transfer tokens from one address to another.
    /// @param _from The address to transfer the ETH from.
    /// @param _to The address to transfer the ETH to.
    /// @param _amount The amount of ETH in wei being transferred.
    /// @dev This function can be called only by trusted system contracts.
    /// @dev This function also emits "Transfer" event, which might be removed
    /// later on.
    function transferFromTo(address _from, address _to, uint256 _amount) external override {
        require(
            msg.sender == MSG_VALUE_SYSTEM_CONTRACT ||
                msg.sender == address(DEPLOYER_SYSTEM_CONTRACT) ||
                msg.sender == BOOTLOADER_FORMAL_ADDRESS
        );

        // We rely on SameMath to revert if the user does not have enough balance.
        balanceOf[_from] -= _amount;
        balanceOf[_to] += _amount;

        emit Transfer(_from, _to, _amount);
    }

    /// @notice Increase the total supply of tokens and balance of the receiver.
    /// @dev This method is only callable by the L2 ETH bridge.
    /// @param _account The address which to mint the funds to.
    /// @param _amount The amount of ETH in wei to be minted.
    function bridgeMint(address _account, uint256 _amount) external override onlyBridge {
        totalSupply += _amount;
        balanceOf[_account] += _amount;
        emit Transfer(address(0), _account, _amount);
        emit BridgeMint(_account, _amount);
    }

    /// @notice Decrease the total supply of tokens and balance of the account.
    /// @dev This method is only callable by the L2 ETH bridge.
    /// @param _account The address which to mint the funds to.
    /// @param _amount The amount of ETH in wei to be minted.
    function bridgeBurn(address _account, uint256 _amount) external override onlyBridge {
        totalSupply -= _amount;
        balanceOf[_account] -= _amount;
        emit Transfer(_account, address(0), _amount);
        emit BridgeBurn(_account, _amount);
    }

    /// @dev This method has not been stabilized and might be
    /// removed later on.
    function name() external pure returns (string memory) {
        return "Ether";
    }

    /// @dev This method has not been stabilized and might be
    /// removed later on.
    function symbol() external pure returns (string memory) {
        return "ETH";
    }

    /// @dev This method has not been stabilized and might be
    /// removed later on.
    function decimals() external pure returns (uint8) {
        return 18;
    }
}
