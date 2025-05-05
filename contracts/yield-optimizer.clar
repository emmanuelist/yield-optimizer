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

;; Withdraw sBTC by burning shares
(define-public (withdraw (share-amount uint))
  (let ((sender tx-sender)
        (user-share-balance (default-to u0 (map-get? user-shares sender)))
        (withdrawal-amount (calculate-withdrawal-amount share-amount)))
    
    ;; Check if user has enough shares
    (asserts! (>= user-share-balance share-amount) ERR_INSUFFICIENT_BALANCE)
    
    ;; Update user shares
    (map-set user-shares sender (- user-share-balance share-amount))
    
    ;; Update total shares
    (var-set total-shares (- (var-get total-shares) share-amount))
    
    ;; Withdraw from protocols
    (try! (withdraw-from-protocols withdrawal-amount))
    
    ;; Update user deposits and total deposits
    (map-set user-deposits sender (- (default-to u0 (map-get? user-deposits sender)) withdrawal-amount))
    (var-set total-deposits (- (var-get total-deposits) withdrawal-amount))
    
    ;; Transfer sBTC back to user
    (as-contract
      (contract-call? 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token transfer
        withdrawal-amount
        tx-sender
        sender
        none)
    )
  )
)

;; Trigger rebalancing of funds across protocols
(define-public (rebalance)
  (let ((best-protocol (get-best-protocol)))
    ;; Check if there's enough time since last rebalance
    (asserts! (> (- block-height (var-get last-rebalance-block)) u100) ERR_REBALANCE_THRESHOLD_NOT_MET)
    
    ;; Update last rebalance block
    (var-set last-rebalance-block block-height)
    
    ;; Perform rebalancing logic
    (try! (perform-rebalance (get protocol best-protocol)))
    
    (ok true)
  )
)

;; Admin functions

;; Add a new yield protocol to the system
(define-public (add-protocol (protocol-name (string-ascii 64)) (protocol-address principal) (initial-yield uint))
  (let ((protocol-index (var-get protocol-count)))
    ;; Only contract owner can add protocols
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    
    ;; Add protocol to registry
    (map-set protocol-registry protocol-index protocol-name)
    (map-set protocol-addresses protocol-name protocol-address)
    (map-set protocol-yields protocol-name initial-yield)
    (map-set protocol-enabled protocol-name true)
    (map-set protocol-allocations protocol-name u0)
    
    ;; Increment protocol count
    (var-set protocol-count (+ protocol-index u1))
    
    (ok true)
  )
)

;; Update yield information for a specific protocol
(define-public (update-protocol-yield (protocol-name (string-ascii 64)) (new-yield uint))
  (begin
    ;; Only contract owner can update yields
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    
    ;; Check if protocol exists
    (asserts! (not (is-eq (default-to none (map-get? protocol-addresses protocol-name)) none)) ERR_PROTOCOL_NOT_FOUND)
    
    ;; Update protocol yield
    (map-set protocol-yields protocol-name new-yield)
    
    (ok true)
  )
)

;; Enable or disable a protocol
(define-public (toggle-protocol (protocol-name (string-ascii 64)) (enabled bool))
  (begin
    ;; Only contract owner can toggle protocols
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    
    ;; Check if protocol exists
    (asserts! (not (is-eq (default-to none (map-get? protocol-addresses protocol-name)) none)) ERR_PROTOCOL_NOT_FOUND)
    
    ;; Update protocol status
    (map-set protocol-enabled protocol-name enabled)
    
    (ok true)
  )
)

;; Transfer contract ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    ;; Only current owner can transfer ownership
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    
    ;; Update contract owner
    (var-set contract-owner new-owner)
    
    (ok true)
  )
)

;; Private helper functions

;; Allocate new deposits to the best performing protocol
(define-private (allocate-deposit (amount uint))
  (let ((best-protocol (get protocol (get-best-protocol))))
    (if (is-eq best-protocol "")
        (ok true) ;; No protocols available, keep in contract
        (let ((protocol-address (unwrap! (map-get? protocol-addresses best-protocol) ERR_PROTOCOL_NOT_FOUND)))
          ;; Increment allocation for best protocol
          (map-set protocol-allocations 
                  best-protocol 
                  (+ (default-to u0 (map-get? protocol-allocations best-protocol)) amount))
          
          ;; Call the external protocol contract to deposit
          (as-contract
            (try! (contract-call? protocol-address deposit
                    amount
                    (as-contract tx-sender)))
          )
          
          (ok true)
        )
    )
  )
)

;; Withdraw funds from protocols based on current allocations
(define-private (withdraw-from-protocols (amount uint))
  (fold withdraw-from-protocol 
        {remaining: amount, success: (ok true)} 
        (list 
          u0 u1 u2 u3 u4 ;; Support up to 5 protocols
        )
  )
)

;; Helper function to withdraw from a single protocol
(define-private (withdraw-from-protocol 
                  (protocol-index uint) 
                  (state {remaining: uint, success: (response bool uint)}))
  (let ((remaining (get remaining state))
        (current-result (get success state)))
    (if (or (<= remaining u0) (is-err current-result))
        ;; If no more funds needed or previous error, return current state
        state
        (let ((protocol-name (default-to "" (map-get? protocol-registry protocol-index))))
          (if (is-eq protocol-name "")
              ;; If no protocol at this index, continue to next
              state
              (let ((protocol-allocation (default-to u0 (map-get? protocol-allocations protocol-name)))
                    (protocol-address (unwrap! (map-get? protocol-addresses protocol-name) 
                                               (merge state {success: ERR_PROTOCOL_NOT_FOUND}))))
                (if (<= protocol-allocation u0)
                    ;; If no allocation in this protocol, continue to next
                    state
                    (let ((withdrawal-amount (min remaining protocol-allocation)))
                      ;; Call the protocol to withdraw funds
                      (let ((withdraw-result 
                              (as-contract
                                (contract-call? protocol-address withdraw
                                  withdrawal-amount
                                  (as-contract tx-sender))
                              )))
                        (if (is-ok withdraw-result)
                            ;; Update protocol allocation and continue
                            (begin
                              (map-set protocol-allocations 
                                      protocol-name 
                                      (- protocol-allocation withdrawal-amount))
                              {remaining: (- remaining withdrawal-amount), success: (ok true)}
                            )
                            ;; If withdrawal failed, propagate the error
                            {remaining: remaining, success: (err ERR_TRANSFER_FAILED)}
                        ))
                    ))
                )
              )
          )
        )
    )
)

;; Helper function to withdraw funds from lower-yielding protocols
(define-private (withdraw-from-lower-yield-protocols (best-protocol (string-ascii 64)) (best-yield uint))
  (fold withdraw-if-lower-yield
        (ok true)
        (list u0 u1 u2 u3 u4) ;; Support up to 5 protocols
  )
)

;; Helper function to withdraw from a protocol if its yield is lower than the best
(define-private (withdraw-if-lower-yield 
                  (protocol-index uint) 
                  (current-result (response bool uint)))
  (if (is-err current-result)
      current-result
      (let ((protocol-name (default-to "" (map-get? protocol-registry protocol-index))))
        (if (or (is-eq protocol-name "") (is-eq protocol-name best-protocol))
            current-result
            (let ((protocol-yield (default-to u0 (map-get? protocol-yields protocol-name)))
                  (protocol-allocation (default-to u0 (map-get? protocol-allocations protocol-name)))
                  (yield-difference (- best-yield protocol-yield)))
              
              ;; Only withdraw if yield difference exceeds the rebalance threshold
              ;; and there are funds allocated
              (if (or (< yield-difference (var-get rebalance-threshold)) (<= protocol-allocation u0))
                  current-result
                  (let ((protocol-address (unwrap! (map-get? protocol-addresses protocol-name) ERR_PROTOCOL_NOT_FOUND)))
                    ;; Withdraw all funds from this lower-yielding protocol
                    (let ((withdraw-result 
                            (as-contract
                              (contract-call? protocol-address withdraw
                                protocol-allocation
                                (as-contract tx-sender))
                            )))
                      (if (is-ok withdraw-result)
                          (begin
                            ;; Reset protocol allocation to zero
                            (map-set protocol-allocations protocol-name u0)
                            current-result
                          )
                          (err ERR_TRANSFER_FAILED)
                      )
                    )
                  )
              )
            )
        )
      )
  )
)

;; Rebalance funds across protocols to maximize yield
(define-private (perform-rebalance (best-protocol (string-ascii 64)))
  (begin
    ;; Implementation would withdraw from lower yielding protocols
    ;; and deposit into the best protocol
    ;; For hackathon purposes, we'll simulate this
    
    (ok true)
  )
)

;; Contract initialization

;; Initialize contract with default values
(map-set protocol-yields "default" u0)
(map-set protocol-enabled "default" false)