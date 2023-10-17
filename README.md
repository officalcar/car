# CAR
CAR contract address: `0x7BaCD1860a35864a0c394a9cF9bb949899345ead`

[View on arbiscan](https://arbiscan.io/address/0x7BaCD1860a35864a0c394a9cF9bb949899345ead)

CAR-ETH Sushi V2 Pool: `0xCb2C8210e7dAd0d8793dA18c7c3a548b51AC7E8a`

[View on arbiscan](https://arbiscan.io/address/0xCb2C8210e7dAd0d8793dA18c7c3a548b51AC7E8a)

## Mint
Contract address: `0xb4615f8eeBbCc9B17C268d3a358A6b56eE10A38D`

[View on arbiscan](https://arbiscan.io/address/0xb4615f8eeBbCc9B17C268d3a358A6b56eE10A38D)

### Function
#### Get the current coin price

The first value in the returned result set is the current latest currency price

```solidity
function bestPrice() external view returns (uint256, uint256, uint256);
```

#### Mint CAR Token

The fixed tolerance is 45000000000(1e18)

According to the current latest currency price, the actual amount of ETH that needs to be paid to buy N coins can be calculated using the formula of the arithmetic sequence
  - Usually, due to the price increase during the purchase period, some extra ETH is required to ensure the transaction is successful. The remaining ETH will be returned after the transaction is completed

```solidity
function mint(uint256 value) external payable;
```

| `Name`  |  `Type`   |            `Description`            |
| :-----: | :-------: | :---------------------------------: |
| `value` | `uint256` | `mint number, need to zoom in 1e18` |

## LP Earn
Contract address: `0x134B3AEa5b46b85a1F10c49474703493f52e027b`

[View on arbiscan](https://arbiscan.io/address/0x134B3AEa5b46b85a1F10c49474703493f52e027b)

### Function
#### Confirm invite
Bind your superior

```solidity
function confirmInvite(address account) external;
```

|  `Name`   |  `Type`   |    `Description`     |
| :-------: | :-------: | :------------------: |
| `account` | `address` | `senior recommender` |

#### Deposits

Deposits supports `CAR-ETH LP` and `ETH`

When deposits ETH, the item in the parameter must be `0x0000000000000000000000000000000000000000` address

```solidity
function deposits(address item, uint256 value, uint256 slippage) external payable;
```

|   `Name`   |  `Type`   |                     `Description`                      |
| :--------: | :-------: | :----------------------------------------------------: |
|   `item`   | `address` |                `deposits coin address`                 |
|  `value`   | `uint256` |                 `deposits coin value`                  |
| `slippage` | `uint256` | `swap slippage, Min 0.1, Max 100(need to zoom in 1e4)` |

#### Withdraw all LP

Withdraw all generated deposits income

```solidity
function withdrawAll() external;
```

#### Withdraw single LP

Withdraw a single generated deposits income

```solidity
function withdrawLP(uint256 serialNumber) external;
```

|     `Name`     |  `Type`   |      `Description`      |
| :------------: | :-------: | :---------------------: |
| `serialNumber` | `uint256` | `deposits order number` |

#### Withdraw sharing rewards

Extract the sharing rewards generated when the subordinates extract LP income

```solidity
function withdrawShareLP() external;
```
