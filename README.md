# Melodex Smart Contracts

Smart contracts for the Melodex auction platform. The headline contract is
**`DutchAuction`** (in `contracts/DutchAuctionSimple.sol`): an upgradeable,
UUPS-proxied Dutch auction that accepts bid payment in **any ERC20 token**.
Non-settlement tokens are swapped to the configured settlement token (e.g.
USDT) through a Uniswap V2 compatible router in the same transaction, so
the escrowed bid always matches the auction's USDT requirements.

---

## Repository layout

```
contracts/
  DutchAuctionSimple.sol      UUPS-upgradeable Dutch auction (multi-ERC20 payments)
  DutchAuctionProxy.sol       ERC1967 proxy wrapper used in front of the impl
  interfaces/
    IUniswapV2Router02.sol    Minimal V2 router interface (UniV2 / QuickSwap / Sushi)
  DutchAuction.sol            Legacy reference (commented out)
  ERC20.sol                   MELS test token
  SongToken.sol               Auctioned song token
  TokenFactory.sol            Creates new SongToken instances
  SaleContract.sol            Direct-sale alternative
scripts/
  deploy_upgradeable.js       Deploys the UUPS proxy + implementation
  upgrade.js                  Upgrades the implementation behind an existing proxy
  create_auction.js           Hardhat task to create a new auction
hardhat.config.js
package.json
```

## Architecture

### Upgradeable proxy (UUPS)

`DutchAuction` is a UUPS-upgradeable contract. State lives in the proxy
(`DutchAuctionProxy`, which wraps `ERC1967Proxy`); the implementation
contract is swap-replaceable by the proxy's owner via `_authorizeUpgrade`.
Storage layout is reserved with a `uint256[44] private __gap` so new state
variables can be added in future implementations without colliding with
existing slots.

The implementation contract is left uninitialized on its own — the
constructor calls `_disableInitializers()`. State is initialized through
the proxy via `initialize(paymentToken, swapRouter)`.

### Multi-ERC20 bidding via Uniswap V2

Every bid is denominated in `paymentToken` (set this to USDT on the target
chain). Bidders have two entry points:

- `bid(auctionId, amount, price)` — pay directly in `paymentToken`. Same
  ABI as the original contract.
- `bidWithToken(auctionId, amount, price, inputToken, maxInputAmount, path)` —
  pay in any ERC20. The contract pulls `maxInputAmount` of `inputToken`
  from the bidder, then calls `swapTokensForExactTokens` on the configured
  V2 router for _exactly_ the required `paymentToken` amount
  (`price * amount * 110 / 100`). Any unspent input is refunded in the
  same transaction.

`maxInputAmount` is the user's slippage cap. If the swap would need more
input than the cap, it reverts and the bidder loses nothing. Frontends
can call `quoteBidInputAmount(amount, price, path)` to compute the exact
input required from on-chain reserves, then apply their preferred
slippage tolerance on top.

### Why exact-output swaps?

Using `swapTokensForExactTokens` guarantees that the escrowed bid is
always _exactly_ the USDT amount the auction requires. There is no
rounding error, no need to re-verify a Uniswap quote on-chain, and no
risk of an under-funded bid being recorded. The trade-off is that the
caller must approve a slippage-padded `maxInputAmount` up front; the
contract refunds the unused portion automatically.

### Safety

- `SafeERC20` is used everywhere — USDT does not return a bool from
  `transfer` / `transferFrom`, so the original `require(token.transferFrom(...))`
  pattern was unsafe with USDT and similar tokens.
- All external entry points (`createAuction`, `bid`, `bidWithToken`,
  `finalizeAuction`) carry `nonReentrant`.
- Router allowance is set with `forceApprove(router, amount)` per-swap and
  reset to zero after each swap.

## Configuration

### Recommended addresses

Polygon mainnet:

- USDT (paymentToken): `0xc2132D05D31c914a87C6611C10748AEb04B58e8F`
- QuickSwap V2 router: `0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff`
- SushiSwap V2 router: `0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506`

Ethereum mainnet:

- USDT: `0xdAC17F958D2ee523a2206206994597C13D831ec7`
- Uniswap V2 router: `0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D`

The settlement token and router can both be reconfigured post-deployment
by the owner via `setPaymentToken` and `setSwapRouter`.

### Environment variables

Copy `.env.example` to `.env` and fill in:

- `PRIVATE_KEY` — deployer key
- `POLYGON_RPC_URL` / `POLYGON_AMOY_RPC_URL` — network RPC endpoints
- `POLYGONSCAN_API_KEY` — for contract verification
- `ADMIN_API_URL` — Melodex admin API used by `create_auction.js`

## Workflow

### Install

```bash
npm installs
```

### Compile

```bash
npx hardhat compile
```

Solidity is pinned to `0.8.24` (required by the OpenZeppelin 5.6+ headers
that the contracts depend on).

### Deploy proxy + implementation

```bash
PAYMENT_TOKEN=0xc2132D05D31c914a87C6611C10748AEb04B58e8F \
SWAP_ROUTER=0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff \
  npx hardhat run scripts/deploy_upgradeable.js --network polygon
```

The script prints both the proxy address (this is the address you
interact with — treat it as the new `DUTCH_AUCTION_ADDRESS`) and the
implementation address.

### Upgrade the implementation

```bash
PROXY_ADDRESS=0x... npx hardhat run scripts/upgrade.js --network polygon
```

The signer must be the proxy owner (the deployer by default). The plugin
runs OpenZeppelin's storage-layout safety checks before upgrading.

### Create an auction

```bash
npx hardhat createAuction <tokenAmount> <durationMinutes> --network polygon
```

Update `DUTCH_AUCTION_ADDRESS` inside `scripts/create_auction.js` to the
proxy address printed by the deploy script.

## Bidding examples

### Paying with USDT directly

```js
const auction = await ethers.getContractAt("DutchAuction", PROXY_ADDRESS);
const usdt = await ethers.getContractAt("IERC20", USDT);

const amount = 10n; // auctioned tokens to bid for
const price = ethers.parseUnits("1", 6); // 1 USDT per token (USDT has 6 decimals)
const totalPayment = (price * amount * 110n) / 100n;

await usdt.approve(PROXY_ADDRESS, totalPayment);
await auction.bid(auctionId, amount, price);
```

### Paying with any ERC20 (e.g. DOGE)

```js
const doge = await ethers.getContractAt("IERC20", DOGE);
const router = await ethers.getContractAt("IUniswapV2Router02", QUICKSWAP);

const amount = 10n;
const price = ethers.parseUnits("1", 6);

// 1) Quote how much DOGE is needed to fund the bid
const path = [DOGE, WMATIC, USDT]; // pick a liquid path
const [inputAmount, totalPayment] = await auction.quoteBidInputAmount(
	amount,
	price,
	path,
);

// 2) Pad for slippage (e.g. +1%)
const maxInputAmount = (inputAmount * 101n) / 100n;

// 3) Approve + bid
await doge.approve(PROXY_ADDRESS, maxInputAmount);
await auction.bidWithToken(
	auctionId,
	amount,
	price,
	DOGE,
	maxInputAmount,
	path,
);
```

Any DOGE not consumed by the swap is refunded automatically.

## Owner-only operations

- `setPaymentToken(address)` — change the settlement token. Existing
  in-flight auctions continue to be denominated in the old token only by
  way of escrowed balances, so coordinate changes carefully.
- `setSwapRouter(address)` — point bids at a different V2-compatible
  router. Useful for swapping out QuickSwap for SushiSwap, etc.
- `finalizeAuction(auctionId, winners, refunders)` — distribute
  auctioned tokens to winners, route settlement-token payment to the
  auction owner (minus the 10% fee that goes to the contract owner),
  and refund losing bidders.
- `upgradeToAndCall(newImpl, data)` — upgrade the implementation.

## Notes and limits

- The new proxy is a fresh deployment. The legacy `DutchAuction` at
  `0xE0ed341D2e4dF7ab9b0a2fFC5b70f9b86DBa3C86` is **not** a proxy and
  cannot be upgraded in place; migrate auctions over to the new proxy.
- Bid payments rely on the configured Uniswap V2 router. For tokens
  without a liquid V2 path to the settlement token, the bid will revert
  during the swap. A V3-router variant can be added in a future
  implementation without breaking storage.
- The 10% over-collateralization (`BID_OVERCOLLATERAL_BPS = 110`) is
  preserved from the original contract.

## Dependencies

- Solidity `0.8.24`
- `@openzeppelin/contracts` ^5.2.0
- `@openzeppelin/contracts-upgradeable` ^5.2.0
- `@openzeppelin/hardhat-upgrades` ^3.9.0
- `hardhat` ^2.22.18
