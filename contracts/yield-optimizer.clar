;; Title: Yield Optimizer- Smart Bitcoin Yield Optimizer
;; 
;; Summary: 
;; A sophisticated yield optimization protocol for Bitcoin assets on Stacks, automatically 
;; allocating funds to the highest-yielding protocols while maintaining security and liquidity.
;;
;; Description:
;; Yield Optimizer intelligently manages Bitcoin assets across multiple lending protocols to maximize
;; returns. The system employs dynamic rebalancing strategies based on real-time yield data,
;; deposits/withdrawals through share-based tokenization, and protocol-agnostic integrations.
;; Built on Stacks for Bitcoin's security with the flexibility of smart contracts.
;;

;; Constants

(define-constant ERR_UNAUTHORIZED (err u1000))
(define-constant ERR_INSUFFICIENT_BALANCE (err u1001))
(define-constant ERR_TRANSFER_FAILED (err u1002))
(define-constant ERR_INVALID_AMOUNT (err u1003))
(define-constant ERR_PROTOCOL_NOT_FOUND (err u1004))
(define-constant ERR_REBALANCE_THRESHOLD_NOT_MET (err u1005))

;; Storage

;; Contract ownership
(define-data-var contract-owner principal tx-sender)

;; Global state variables
(define-data-var total-deposits uint u0)
(define-data-var total-shares uint u0)
(define-data-var last-rebalance-block uint block-height)
(define-data-var rebalance-threshold uint u100) ;; 1% in basis points
(define-data-var protocol-count uint u0)

;; User and protocol data maps
(define-map user-deposits principal uint)
(define-map user-shares principal uint)
(define-map protocol-allocations (string-ascii 64) uint)
(define-map protocol-yields (string-ascii 64) uint) ;; APY in basis points
(define-map protocol-addresses (string-ascii 64) principal)
(define-map protocol-enabled (string-ascii 64) bool)
(define-map protocol-registry uint (string-ascii 64))

;; Read-only functions

;; User balance and share queries
(define-read-only (get-user-balance (user principal))
  (default-to u0 (map-get? user-deposits user))
)

(define-read-only (get-user-shares (user principal))
  (default-to u0 (map-get? user-shares user))
)

;; Protocol information queries
(define-read-only (get-protocol-allocation (protocol-name (string-ascii 64)))
  (default-to u0 (map-get? protocol-allocations protocol-name))
)

(define-read-only (get-protocol-yield (protocol-name (string-ascii 64)))
  (default-to u0 (map-get? protocol-yields protocol-name))
)

;; Global state queries
(define-read-only (get-total-deposits)
  (var-get total-deposits)
)

(define-read-only (get-total-shares)
  (var-get total-shares)
)

;; Calculate the current value of one share (with 6 decimal precision)
(define-read-only (get-share-value)
  (let ((total-shares-value (var-get total-shares))
        (total-deposits-value (var-get total-deposits)))
    (if (is-eq total-shares-value u0)
        u1000000 ;; Initial share price: 1.0 with 6 decimal places
        (/ (* total-deposits-value u1000000) total-shares-value)) ;; 6 decimal places for precision
  )
)

;; Convert between deposit amounts and share quantities
(define-read-only (calculate-shares-amount (deposit-amount uint))
  (let ((share-price (get-share-value)))
    (if (is-eq share-price u0)
        deposit-amount
        (/ (* deposit-amount u1000000) share-price))
  )
)

(define-read-only (calculate-withdrawal-amount (share-amount uint))
  (let ((share-price (get-share-value)))
    (/ (* share-amount share-price) u1000000)
  )
)

;; Find the protocol with the highest current yield
(define-read-only (get-best-protocol)
  (fold check-protocol-yield 
        {protocol: "", yield: u0} 
        (list 
          u0 u1 u2 u3 u4 ;; Support up to 5 protocols
        )
  )
)

(define-private (check-protocol-yield (protocol-index uint) (current-best {protocol: (string-ascii 64), yield: uint}))
  (let ((protocol-name (default-to "" (map-get? protocol-registry protocol-index)))
        (protocol-yield (default-to u0 (map-get? protocol-yields protocol-name)))
        (protocol-active (default-to false (map-get? protocol-enabled protocol-name))))
    (if (and (not (is-eq protocol-name "")) protocol-active (> protocol-yield (get yield current-best)))
        {protocol: protocol-name, yield: protocol-yield}
        current-best)
  )
)

;; Public functions

;; Deposit sBTC into the yield optimizer
(define-public (deposit (amount uint))
  (let ((sender tx-sender)
        (current-deposit (default-to u0 (map-get? user-deposits sender)))
        (share-amount (calculate-shares-amount amount)))
    
    ;; Check for valid amount
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    
    ;; Transfer sBTC from sender to contract
    (asserts! (is-ok (contract-call? 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token transfer
      amount
      sender
      (as-contract tx-sender)
      none)) ERR_TRANSFER_FAILED)
    
    ;; Update user deposits
    (map-set user-deposits sender (+ current-deposit amount))
    
    ;; Update user shares
    (map-set user-shares sender (+ (default-to u0 (map-get? user-shares sender)) share-amount))
    
    ;; Update total deposits and shares
    (var-set total-deposits (+ (var-get total-deposits) amount))
    (var-set total-shares (+ (var-get total-shares) share-amount))
    
    ;; Allocate deposits to protocols
    (try! (allocate-deposit amount))
    
    (ok share-amount)
  )
)