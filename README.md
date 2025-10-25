# DecentralizedEscrow Smart Contract

A trustless peer-to-peer escrow system built on Stacks blockchain that enables secure transactions between buyers and sellers with built-in dispute resolution.

## Overview

DecentralizedEscrow provides a secure intermediary service for P2P transactions, holding funds until both parties fulfill their obligations. The contract includes dispute resolution mechanisms and platform fee collection.

## Features

- **Secure Fund Holding**: Funds are locked in the contract until release conditions are met
- **Multi-State Escrow**: Tracks escrow through pending, funded, completed, disputed, and cancelled states
- **Dispute Resolution**: Built-in arbitration system for resolving conflicts
- **Platform Fees**: Automatic fee collection (default 2.5%) on completed transactions
- **Transparency**: All escrow details and disputes are recorded on-chain
- **Cancellation Support**: Buyers can cancel unfunded escrows

## Contract States

- **Pending (0)**: Escrow created but not yet funded
- **Funded (1)**: Buyer has deposited funds into escrow
- **Completed (2)**: Funds released and transaction complete
- **Disputed (3)**: Dispute initiated, awaiting arbiter resolution
- **Cancelled (4)**: Escrow cancelled by buyer before funding

## Key Functions

### User Functions

#### `create-escrow`
```clarity
(create-escrow (seller principal) (amount uint) (description (string-ascii 256)))
```
Creates a new escrow agreement. Returns the escrow ID.

**Parameters:**
- `seller`: Principal address of the seller
- `amount`: Amount in microSTX to be held in escrow
- `description`: Description of the transaction (max 256 characters)

#### `fund-escrow`
```clarity
(fund-escrow (escrow-id uint))
```
Buyer funds the escrow, transferring STX to the contract.

#### `release-funds`
```clarity
(release-funds (escrow-id uint))
```
Buyer releases funds to seller after satisfactory completion. Platform fee is deducted automatically.

#### `initiate-dispute`
```clarity
(initiate-dispute (escrow-id uint) (reason (string-ascii 512)))
```
Either party can initiate a dispute with a reason. Only available for funded escrows.

#### `cancel-escrow`
```clarity
(cancel-escrow (escrow-id uint))
```
Buyer can cancel escrow before funding.

### Admin Functions

#### `resolve-dispute`
```clarity
(resolve-dispute (escrow-id uint) (winner principal))
```
Arbiter resolves disputes by designating the winner (buyer or seller). Funds are released to winner minus platform fee.

#### `set-arbiter`
```clarity
(set-arbiter (new-arbiter principal))
```
Contract owner can update the arbiter address.

#### `set-platform-fee`
```clarity
(set-platform-fee (new-fee uint))
```
Contract owner can update platform fee (in basis points, max 1000 = 10%).

### Read-Only Functions

- `get-escrow`: Retrieve escrow details by ID
- `get-dispute`: Retrieve dispute details by escrow ID
- `get-current-nonce`: Get the next escrow ID
- `get-arbiter`: Get current arbiter address
- `calculate-platform-fee`: Calculate fee for a given amount

## Usage Example

### Creating and Completing an Escrow

```clarity
;; 1. Buyer creates escrow for 1000 STX
(contract-call? .decentralized-escrow create-escrow 'ST1SELLER... u1000000000 "Website development services")
;; Returns: (ok u0) - escrow ID 0

;; 2. Buyer funds the escrow
(contract-call? .decentralized-escrow fund-escrow u0)
;; Transfers 1000 STX to contract

;; 3. Seller delivers service

;; 4. Buyer releases funds
(contract-call? .decentralized-escrow release-funds u0)
;; Transfers 975 STX to seller, 25 STX fee to platform (2.5%)
```

### Handling a Dispute

```clarity
;; 1. Seller initiates dispute
(contract-call? .decentralized-escrow initiate-dispute u0 "Buyer not responding after delivery")

;; 2. Arbiter reviews and resolves
(contract-call? .decentralized-escrow resolve-dispute u0 'ST1SELLER...)
;; Awards funds to seller
```

## Security Considerations

- Only buyers can create, fund, release, and cancel escrows
- Only designated arbiter can resolve disputes
- Funds cannot be withdrawn once funded until completion or dispute resolution
- Platform fees are capped at 10% maximum
- All state transitions are validated before execution

## Error Codes

- `u100`: Owner only operation
- `u101`: Escrow not found
- `u102`: Unauthorized action
- `u103`: Invalid state for operation
- `u104`: Insufficient funds
- `u105`: Escrow already exists

## Deployment

Deploy using Clarinet:

```bash
clarinet contract deploy decentralized-escrow
```

## Testing

Run the test suite:

```bash
clarinet test
```

## License

MIT License

## Contributing

Contributions are welcome! Please ensure all tests pass before submitting pull requests.
