# Numa protocol

## Numa protocol V2

### contracts/lending/*
### contracts/NumaProtocol/*
### contracts/nuAssets/*

## Foundry testing

- Use lite foundry config for faster build: $Env:FOUNDRY_PROFILE = 'lite'
- define URLARBI = Arbitrum rpc  in .env file (tests are running on arbitrum fork)

### vault testing

```shell
forge test --match-contract VaultTest -vv 
```


### vault buy/sell fees testing

```shell
forge test --match-contract VaultBuySellFeeTest -vv 
```


### printer testing

```shell
forge test --match-contract PrinterTest -vv 
```


### lending testing

```shell
forge test --match-contract LendingTest -vv 
```


### vault migrations testing

```shell
forge test --match-contract VaultTest -vv 
```
