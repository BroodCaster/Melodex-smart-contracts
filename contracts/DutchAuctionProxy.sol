// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title DutchAuctionProxy
/// @notice Minimal ERC1967 proxy in front of the upgradeable `DutchAuction`
///         implementation. Pair this with the UUPS-enabled implementation
///         (see DutchAuctionSimple.sol).
///
/// @dev Constructor arguments:
///      - `logic`: address of the deployed DutchAuction implementation.
///      - `data`:  encoded `initialize(paymentToken, swapRouter)` call so the
///                 proxy is initialized atomically with deployment.
///
/// Example (ethers v6):
///   const initData = Impl.interface.encodeFunctionData(
///     "initialize", [usdt, quickswapRouter]
///   );
///   const proxy = await DutchAuctionProxy.deploy(implAddr, initData);
///
/// After deployment, attach the implementation ABI to the proxy address to
/// interact with it: `Impl.attach(await proxy.getAddress())`.
contract DutchAuctionProxy is ERC1967Proxy {
    constructor(address logic, bytes memory data) ERC1967Proxy(logic, data) {}
}
