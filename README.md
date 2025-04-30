# Yield Optimizer - Smart Bitcoin Yield Optimizer

A sophisticated **yield optimization protocol** for Bitcoin assets on the [Stacks](https://stacks.co/) blockchain, designed to **automatically allocate funds** to the highest-yielding strategies while preserving **security, liquidity, and flexibility**.

## Overview

The **Yield Optimizer** dynamically allocates user deposits (denominated in sBTC) across multiple integrated yield protocols to maximize returns. It uses real-time yield data to perform intelligent **rebalancing**, supports **share-based tokenization** for deposits/withdrawals, and enables **modular protocol integration**.

Built on **Stacks**, this smart contract solution ensures the security and permanence of Bitcoin, while leveraging programmable logic for DeFi innovation.

## Features

- **Dynamic yield optimization** across registered protocols  
- **Automatic rebalancing** based on APY comparisons and block intervals  
- **Share-based accounting** to reflect user ownership and earnings  
- **Protocol registry** with enable/disable functionality  
- **Real-time yield updates** by contract owner  
- **Extensible design** with protocol-agnostic integrations  
- **Deposit/Withdraw** sBTC via secure Clarity contract calls  
- **Access control** and error handling for safe interactions  
- **Owner controls** for protocol management and ownership transfer  

## Contract Structure

### Constants

Predefined errors and configuration parameters (e.g., rebalance threshold, error codes).

### Global State

- `total-deposits`: Total sBTC deposited
- `total-shares`: Total shares issued
- `last-rebalance-block`: Block height at last rebalance
- `rebalance-threshold`: Minimum block interval for rebalancing
- `protocol-count`: Number of registered protocols

### Mappings

- `user-deposits`: Tracks sBTC deposited by users
- `user-shares`: Tracks shares issued to users
- `protocol-yields`: APYs (basis points) of protocols
- `protocol-allocations`: Allocation of funds per protocol
- `protocol-addresses`: Contract address of each protocol
- `protocol-enabled`: Toggleable status of protocols
- `protocol-registry`: Index-to-name mapping of protocols

## Functions

### Public Functions

#### User Interactions

- `deposit(amount)`: Deposit sBTC into optimizer (mint shares)
- `withdraw(share-amount)`: Withdraw sBTC by burning shares

#### Rebalancing

- `rebalance()`: Reallocate funds to the best yielding protocol

#### Admin Controls

- `add-protocol(name, address, yield)`: Register a new protocol
- `update-protocol-yield(name, yield)`: Manually update protocol APY
- `toggle-protocol(name, enabled)`: Enable/disable a protocol
- `transfer-ownership(new-owner)`: Transfer admin control

### Private Functions

- `allocate-deposit(amount)`: Allocate new deposits to highest-yielding protocol
- `withdraw-from-protocols(amount)`: Withdraw sBTC from protocols (mocked)
- `perform-rebalance(best-protocol)`: Shift funds between protocols (mocked)

### Read-Only Functions

- `get-user-balance(user)`: Get user's total deposited sBTC
- `get-user-shares(user)`: Get user's current share balance
- `get-protocol-allocation(name)`: Check sBTC allocated to a protocol
- `get-protocol-yield(name)`: View current APY of a protocol
- `get-total-deposits()`, `get-total-shares()`: Global metrics
- `get-share-value()`: Value of one share in sBTC (6-decimal precision)
- `calculate-shares-amount(amount)`: Convert deposit amount to shares
- `calculate-withdrawal-amount(shares)`: Convert shares back to sBTC
- `get-best-protocol()`: Determine protocol with highest yield

## Design Considerations

- **Security-First**: No hardcoded addresses, restricted admin functions.
- **Composable**: Protocols added modularly with names and addresses.
- **Scalable**: Supports up to 5 protocols and can easily be extended.
- **Precise Accounting**: Uses 6-decimal precision for accurate share-value mapping.
- **Transparent State**: All balances, shares, and allocations are queryable.

## Simulated Logic

- Protocol interactions (deposit/withdraw/rebalance) are mocked for demonstration.
- Replace simulated logic with real contract calls to integrate with actual protocols.

Example (future real usage):

```clojure
(contract-call? protocol-address deposit amount)
(contract-call? protocol-address withdraw amount)
```

## Access Control

Only the `contract-owner` (initially the deployer) can:

- Add new protocols
- Update yield rates
- Toggle protocol status
- Transfer ownership

## Dependencies

- **sBTC Token Contract**: Used for transfer operations
  Example: `'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token`

Update the token contract address to match your deployed environment.

## Deployment & Usage

1. **Deploy the contract** to the Stacks blockchain.
2. **Call `add-protocol`** to register protocols and assign APYs.
3. **Users call `deposit`** to earn yield and receive shares.
4. **Call `rebalance`** periodically to update fund allocations.
5. **Users call `withdraw`** to redeem shares for sBTC.

## Example Use

```clojure
;; Deposit 1000 sBTC
(define-public (deposit u1000))

;; Withdraw 500 shares
(define-public (withdraw u500))

;; Rebalance allocations
(define-public (rebalance))

;; Add a new protocol
(define-public (add-protocol "ProtocolA" 'ST3... 500)) ;; 5% APY
```

## Questions / Support

Have questions or ideas? Start a discussion or submit a PR.  
This project was created for hackathons and extensible for production-grade DeFi use.
