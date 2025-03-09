// SPDX-Identifier: MIT
pragma solidity ^0.8.0;

interface IWrappedNative {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
    function balanceOf(address _owner) external view returns (uint256);
    function transfer(address _to, uint256 _value) external returns (bool);
    function approve(address _spender, uint256 _value) external returns (bool);
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool);
}
