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
(define-data-var last-rebalance-block uint stacks-block-height)
(define-data-var rebalance-threshold uint u100) ;; 1% in basis points
(define-data-var protocol-count uint u0)

;; Temporary variables used for checking best protocol 
(define-data-var best-protocol-name (string-ascii 64) "")
(define-data-var best-protocol-yield uint u0)

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

;; Find the best protocol by checking each protocol in the registry
(define-private (find-best-protocol)
  (begin
    ;; Initialize with empty values
    (var-set best-protocol-name "")
    (var-set best-protocol-yield u0)
    
    ;; Check each protocol and update the best one
    (check-protocol-index u0)
    (check-protocol-index u1)
    (check-protocol-index u2)
    (check-protocol-index u3)
    (check-protocol-index u4)
    
    ;; Return the result
    {best-name: (var-get best-protocol-name), best-yield: (var-get best-protocol-yield)}
  )
)

;; Helper function to check a protocol at given index and update the best if better
(define-private (check-protocol-index (protocol-index uint))
  (let ((protocol-name (default-to "" (map-get? protocol-registry protocol-index))))
    (if (not (is-eq protocol-name ""))
        (let ((protocol-yield (default-to u0 (map-get? protocol-yields protocol-name)))
              (protocol-active (default-to false (map-get? protocol-enabled protocol-name)))
              (current-best-yield (var-get best-protocol-yield)))
          
          (if (and protocol-active (> protocol-yield current-best-yield))
              (begin
                ;; Update the best protocol
                (var-set best-protocol-name protocol-name)
                (var-set best-protocol-yield protocol-yield)
                true)
              false))
        false)
  )
)

;; Find the protocol with the highest current yield
(define-public (get-best-protocol)
  (let ((best-protocol (find-best-protocol)))
    ;; Store best protocol info for use in contracts
    (var-set best-protocol-name (get best-name best-protocol))
    (var-set best-protocol-yield (get best-yield best-protocol))
    
    (ok (get best-name best-protocol))
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
  (begin
    ;; Check if there's enough time since last rebalance
    (asserts! (> (- stacks-block-height (var-get last-rebalance-block)) u100) ERR_REBALANCE_THRESHOLD_NOT_MET)
    
    ;; Update last rebalance block
    (var-set last-rebalance-block stacks-block-height)
    
    ;; Get the best protocol first
    (try! (get-best-protocol))
    
    ;; Perform rebalancing logic using the stored best protocol
    (try! (perform-rebalance (var-get best-protocol-name)))
    
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
  (begin
    ;; First get the best protocol
    (try! (get-best-protocol))
    
    (let ((best-protocol (var-get best-protocol-name)))
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
  )

;; Additional temporary variables for withdraw operations
(define-data-var remaining-amount uint u0)
(define-data-var withdrawal-result (response bool uint) (ok true))
(define-data-var rebalance-result (response bool uint) (ok true))

;; Withdraw funds from protocols based on current allocations
(define-private (withdraw-from-protocols (amount uint))
  (begin
    (var-set remaining-amount amount)
    (var-set withdrawal-result (ok true))
    
    ;; Try to withdraw from each protocol until the amount is satisfied
    (map try-withdraw-from-protocol (list u0 u1 u2 u3 u4))
    
    (var-get withdrawal-result)
  )
)

(define-private (try-withdraw-from-protocol (protocol-index uint))
  (let ((remaining (var-get remaining-amount))
        (current-result (var-get withdrawal-result)))
    (if (or (<= remaining u0) (is-err current-result))
        false  ;; Skip if already done or error occurred
        (let ((protocol-name (default-to "" (map-get? protocol-registry protocol-index))))
          (if (is-eq protocol-name "")
              false  ;; No protocol at this index
              (let ((protocol-allocation (default-to u0 (map-get? protocol-allocations protocol-name)))
                    (protocol-address-opt (map-get? protocol-addresses protocol-name)))
                (if (or (<= protocol-allocation u0) (is-none protocol-address-opt))
                    false  ;; No allocation or no address
                    (let ((protocol-address (unwrap! protocol-address-opt 
                                             (begin
                                               (var-set withdrawal-result ERR_PROTOCOL_NOT_FOUND)
                                               false))))
                      (let ((withdrawal-amount (if (< remaining protocol-allocation) 
                                                  remaining 
                                                  protocol-allocation)))
                        ;; Call the protocol to withdraw funds
                        (let ((withdraw-result 
                                (as-contract
                                  (contract-call? protocol-address withdraw
                                    withdrawal-amount
                                    (as-contract tx-sender))
                                )))
                          (if (is-ok withdraw-result)
                              (begin
                                ;; Update protocol allocation
                                (map-set protocol-allocations 
                                        protocol-name 
                                        (- protocol-allocation withdrawal-amount))
                                (var-set remaining-amount (- remaining withdrawal-amount))
                                true)
                              (begin
                                ;; Set error
                                (var-set withdrawal-result ERR_TRANSFER_FAILED)
                                false))
                        ))))
              ))
          )
        )
    )
  )

;; Helper function to withdraw funds from lower-yielding protocols
(define-private (withdraw-from-lower-yield-protocols (best-protocol (string-ascii 64)) (best-yield uint))
  (begin
    (var-set rebalance-result (ok true))
    
    ;; Check each protocol and withdraw from lower-yielding ones
    (map withdraw-if-lower-yield-protocol (list u0 u1 u2 u3 u4))
    
    (var-get rebalance-result)
  )
)

;; Helper function to withdraw from a protocol if its yield is lower than the best
(define-private (withdraw-if-lower-yield-protocol (protocol-index uint))
  (let ((current-result (var-get rebalance-result)))
    (if (is-err current-result)
        false  ;; Skip if there's already an error
        (let ((protocol-name (default-to "" (map-get? protocol-registry protocol-index))))
          (if (or (is-eq protocol-name "") (is-eq protocol-name (var-get best-protocol-name)))
              false  ;; Skip if no protocol at this index or it's the best protocol
              (let ((protocol-yield (default-to u0 (map-get? protocol-yields protocol-name)))
                    (protocol-allocation (default-to u0 (map-get? protocol-allocations protocol-name)))
                    (yield-difference (- best-yield protocol-yield)))
                
                ;; Only withdraw if yield difference exceeds the rebalance threshold
                ;; and there are funds allocated
                (if (or (< yield-difference (var-get rebalance-threshold)) (<= protocol-allocation u0))
                    false  ;; Skip if threshold not met or no allocation
                    (let ((protocol-address-opt (map-get? protocol-addresses protocol-name)))
                      (if (is-none protocol-address-opt)
                          (begin
                            (var-set rebalance-result ERR_PROTOCOL_NOT_FOUND)
                            false)
                          (let ((protocol-address (unwrap-panic protocol-address-opt)))
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
                                    true)
                                  (begin
                                    (var-set rebalance-result (err ERR_TRANSFER_FAILED))
                                    false))
                            ))))
                )
              ))
          )
        )
    )
  )

;; Rebalance funds across protocols to maximize yield
(define-private (perform-rebalance (best-protocol (string-ascii 64)))
  (begin
    ;; Only proceed if we have a valid protocol
    (if (is-eq best-protocol "")
        (ok true)
        (let ((best-protocol-address (unwrap! (map-get? protocol-addresses best-protocol) ERR_PROTOCOL_NOT_FOUND))
              (best-protocol-yield (default-to u0 (map-get? protocol-yields best-protocol))))
          
          ;; Step 1: Calculate total assets to rebalance
          (let ((total-to-rebalance (var-get total-deposits))
                (current-best-allocation (default-to u0 (map-get? protocol-allocations best-protocol))))
            
            ;; Step 2: Withdraw from lower-yielding protocols
            (try! (withdraw-from-lower-yield-protocols best-protocol best-protocol-yield))
            
            ;; Step 3: Deposit all available funds into best protocol
            (let ((available-balance 
                    (as-contract
                      (contract-call? 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token get-balance 
                        (as-contract tx-sender))
                    )))
              
              (if (> available-balance u0)
                  (as-contract
                    (begin
                      ;; Deposit to best protocol
                      (try! (contract-call? best-protocol-address deposit
                              available-balance
                              (as-contract tx-sender)))
                      
                      ;; Update allocation for best protocol
                      (map-set protocol-allocations 
                              best-protocol 
                              (+ current-best-allocation available-balance))
                      
                      (ok true)
                    )
                  )
                  (ok true) ;; No funds to rebalance
              )
            )
          )
        )
    )
  )
)

;; Contract initialization

;; Initialize contract with default values
(map-set protocol-yields "default" u0)
(map-set protocol-enabled "default" false)