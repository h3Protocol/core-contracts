# H3rmes Finance Protocol

![H3rmes Logo](https://placehold.co/600x200?text=H3rmes+Finance)

H3rmes Finance is a next-generation DeFi protocol built on Sonic that combines rising price-floor tokenomics with borrowing, lending, and staking mechanisms, all backed by oSonic.

## Protocol Overview

H3rmes introduces an innovative financial ecosystem with several interconnected components:

- **H3RMES Token**: Core asset with mathematically-enforced rising price backed by oSonic
- **XH3RMES Token**: Governance and staking token with vesting mechanisms
- **Borrowing System**: Collateralized loans using H3RMES as backing
- **Liquidity Incentives**: Rewards for providing liquidity via XH3RMES emissions
- **Advanced Trading**: Leverage trading and flash-close position functionality

## Contract Addresses

All protocol contracts are deployed using our deterministic CREATE3 deployer, ensuring consistent addresses across all deployments:

| Contract | Description | CREATE3 Address |
|----------|-------------|----------------|
| H3rmesContractDeployer | Deterministic deployment system | `0xc966583B2310FfcA55D46F3dD0b88c12c151e434` |
| H3rmes | Core token with bonding curve | `0x8a4e3A3E7a6613A4C9F559c9d24021ec1a7c442c` |
| H3rmesHelper | Utility contract for price calculations | `0xf87847cb67677a7227f7338c420646f968ff542e` |
| XH3rmes | Governance and staking token | `0x52ED2dCa89E74165B4380FEe5402e4cA59250A8E` |
| H3rmesExchange | H3RMES ⟷ XH3RMES conversion | `0xdFf5f458B38C5c94b7434B436eA023930E35d4AC` |
| XH3rmesRewardPool | LP staking rewards distribution | `0xd87f3AF8A3A69e55cD2A149235D579e0382CdA49` | NativePositionManager | Enables Sonic Interactions | `0x6746665dB6115e58860ec52dC3110FD734d3dbFB` |

## Core Mechanisms

### Price Floor Tokenomics

H3RMES implements a mathematically guaranteed rising price floor through several key mechanisms:

1. **Bonding Curve**: Every buy/sell transaction occurs along a deterministic curve
2. **Backing Pool**: All purchases add to the oSonic backing pool
3. **Safety Check**: Transactions that would lower the token price are rejected
4. **Dead Shares**: Initial 1 token permanently locked in contract

Price calculations follow these formulas:
