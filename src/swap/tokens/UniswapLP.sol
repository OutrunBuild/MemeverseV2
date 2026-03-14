// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import {Owned} from "solmate/auth/Owned.sol";

import {IMemeverseUniswapHook, PoolId} from "../interfaces/IMemeverseUniswapHook.sol";

/// @notice LP Token For MemeverseUniswapHook
contract UniswapLP is Owned {
    string public name;
    string public symbol;
    uint8 public immutable decimals;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    uint256 internal immutable INITIAL_CHAIN_ID;
    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;
    mapping(address => uint256) public nonces;

    PoolId public immutable poolId;
    address public immutable memeverseUniswapHook;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        PoolId _poolId,
        address _memeverseUniswapHook
    ) Owned(msg.sender) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        poolId = _poolId;
        memeverseUniswapHook = _memeverseUniswapHook;

        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
    }

    /// @notice Executes approve.
    /// @dev See the implementation for behavior details.
    /// @param spender The spender value.
    /// @param amount The amount value.
    /// @return bool The bool value.
    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    /// @notice Executes transfer.
    /// @dev See the implementation for behavior details.
    /// @param to The to value.
    /// @param amount The amount value.
    /// @return bool The bool value.
    function transfer(address to, uint256 amount) public returns (bool) {
        _beforeTokenTransfer(msg.sender, to);

        balanceOf[msg.sender] -= amount;

        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    /// @notice Executes transfer from.
    /// @dev See the implementation for behavior details.
    /// @param from The from value.
    /// @param to The to value.
    /// @param amount The amount value.
    /// @return bool The bool value.
    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        _beforeTokenTransfer(from, to);

        uint256 allowed = allowance[from][msg.sender];

        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        balanceOf[from] -= amount;

        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }

    /// @notice Executes mint.
    /// @dev See the implementation for behavior details.
    /// @param account The account value.
    /// @param amount The amount value.
    function mint(address account, uint256 amount) external onlyOwner {
        _mint(account, amount);
    }

    /// @notice Executes burn.
    /// @dev See the implementation for behavior details.
    /// @param account The account value.
    /// @param amount The amount value.
    function burn(address account, uint256 amount) external onlyOwner {
        _burn(account, amount);
    }

    /// @notice Executes permit.
    /// @dev See the implementation for behavior details.
    /// @param owner The owner value.
    /// @param spender The spender value.
    /// @param value The value value.
    /// @param deadline The deadline value.
    /// @param v The v value.
    /// @param r The r value.
    /// @param s The s value.
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
    {
        require(deadline >= block.timestamp, "PERMIT_DEADLINE_EXPIRED");

        unchecked {
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                                ),
                                owner,
                                spender,
                                value,
                                nonces[owner]++,
                                deadline
                            )
                        )
                    )
                ),
                v,
                r,
                s
            );

            require(recoveredAddress != address(0) && recoveredAddress == owner, "INVALID_SIGNER");

            allowance[recoveredAddress][spender] = value;
        }

        emit Approval(owner, spender, value);
    }

    /// @notice Returns domain separator.
    /// @dev See the implementation for behavior details.
    /// @return bytes32 The bytes32 value.
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : computeDomainSeparator();
    }

    function computeDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;

        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        balanceOf[from] -= amount;

        unchecked {
            totalSupply -= amount;
        }

        emit Transfer(from, address(0), amount);
    }

    function _beforeTokenTransfer(address from, address to) internal {
        if (from != address(0)) IMemeverseUniswapHook(memeverseUniswapHook).updateUserSnapshot(poolId, from);
        if (to != address(0)) IMemeverseUniswapHook(memeverseUniswapHook).updateUserSnapshot(poolId, to);
    }

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
}
