;; DecentralizedEscrow - Trustless P2P Payment Escrow
;; A secure escrow system for peer-to-peer transactions with dispute resolution

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-state (err u103))
(define-constant err-insufficient-funds (err u104))
(define-constant err-already-exists (err u105))

;; Escrow states
(define-constant state-pending u0)
(define-constant state-funded u1)
(define-constant state-completed u2)
(define-constant state-disputed u3)
(define-constant state-cancelled u4)

;; Data Variables
(define-data-var escrow-nonce uint u0)
(define-data-var arbiter principal contract-owner)
(define-data-var platform-fee-percentage uint u250) ;; 2.5% (basis points)

;; Data Maps
(define-map escrows
  { escrow-id: uint }
  {
    buyer: principal,
    seller: principal,
    amount: uint,
    state: uint,
    description: (string-ascii 256),
    created-at: uint,
    funded-at: (optional uint),
    completed-at: (optional uint)
  }
)

(define-map disputes
  { escrow-id: uint }
  {
    initiated-by: principal,
    reason: (string-ascii 512),
    initiated-at: uint,
    resolved: bool,
    winner: (optional principal)
  }
)

;; Read-only functions
(define-read-only (get-escrow (escrow-id uint))
  (map-get? escrows { escrow-id: escrow-id })
)

(define-read-only (get-dispute (escrow-id uint))
  (map-get? disputes { escrow-id: escrow-id })
)

(define-read-only (get-current-nonce)
  (ok (var-get escrow-nonce))
)

(define-read-only (get-arbiter)
  (ok (var-get arbiter))
)

(define-read-only (calculate-platform-fee (amount uint))
  (ok (/ (* amount (var-get platform-fee-percentage)) u10000))
)

;; Public functions
(define-public (create-escrow (seller principal) (amount uint) (description (string-ascii 256)))
  (let
    (
      (escrow-id (var-get escrow-nonce))
    )
    (asserts! (> amount u0) err-insufficient-funds)
    (asserts! (not (is-eq tx-sender seller)) err-unauthorized)
    
    (map-set escrows
      { escrow-id: escrow-id }
      {
        buyer: tx-sender,
        seller: seller,
        amount: amount,
        state: state-pending,
        description: description,
        created-at: stacks-block-height,
        funded-at: none,
        completed-at: none
      }
    )
    
    (var-set escrow-nonce (+ escrow-id u1))
    (ok escrow-id)
  )
)

(define-public (fund-escrow (escrow-id uint))
  (let
    (
      (escrow (unwrap! (map-get? escrows { escrow-id: escrow-id }) err-not-found))
      (amount (get amount escrow))
    )
    (asserts! (is-eq tx-sender (get buyer escrow)) err-unauthorized)
    (asserts! (is-eq (get state escrow) state-pending) err-invalid-state)
    
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    (map-set escrows
      { escrow-id: escrow-id }
      (merge escrow {
        state: state-funded,
        funded-at: (some stacks-block-height)
      })
    )
    
    (ok true)
  )
)

(define-public (release-funds (escrow-id uint))
  (let
    (
      (escrow (unwrap! (map-get? escrows { escrow-id: escrow-id }) err-not-found))
      (amount (get amount escrow))
      (fee (unwrap-panic (calculate-platform-fee amount)))
      (seller-amount (- amount fee))
    )
    (asserts! (is-eq tx-sender (get buyer escrow)) err-unauthorized)
    (asserts! (is-eq (get state escrow) state-funded) err-invalid-state)
    
    (try! (as-contract (stx-transfer? seller-amount tx-sender (get seller escrow))))
    (try! (as-contract (stx-transfer? fee tx-sender contract-owner)))
    
    (map-set escrows
      { escrow-id: escrow-id }
      (merge escrow {
        state: state-completed,
        completed-at: (some stacks-block-height)
      })
    )
    
    (ok true)
  )
)

(define-public (initiate-dispute (escrow-id uint) (reason (string-ascii 512)))
  (let
    (
      (escrow (unwrap! (map-get? escrows { escrow-id: escrow-id }) err-not-found))
    )
    (asserts! 
      (or 
        (is-eq tx-sender (get buyer escrow))
        (is-eq tx-sender (get seller escrow))
      )
      err-unauthorized
    )
    (asserts! (is-eq (get state escrow) state-funded) err-invalid-state)
    
    (map-set disputes
      { escrow-id: escrow-id }
      {
        initiated-by: tx-sender,
        reason: reason,
        initiated-at: stacks-block-height,
        resolved: false,
        winner: none
      }
    )
    
    (map-set escrows
      { escrow-id: escrow-id }
      (merge escrow { state: state-disputed })
    )
    
    (ok true)
  )
)

(define-public (resolve-dispute (escrow-id uint) (winner principal))
  (let
    (
      (escrow (unwrap! (map-get? escrows { escrow-id: escrow-id }) err-not-found))
      (dispute (unwrap! (map-get? disputes { escrow-id: escrow-id }) err-not-found))
      (amount (get amount escrow))
      (fee (unwrap-panic (calculate-platform-fee amount)))
      (winner-amount (- amount fee))
    )
    (asserts! (is-eq tx-sender (var-get arbiter)) err-unauthorized)
    (asserts! (is-eq (get state escrow) state-disputed) err-invalid-state)
    (asserts! (not (get resolved dispute)) err-invalid-state)
    (asserts! 
      (or 
        (is-eq winner (get buyer escrow))
        (is-eq winner (get seller escrow))
      )
      err-unauthorized
    )
    
    (try! (as-contract (stx-transfer? winner-amount tx-sender winner)))
    (try! (as-contract (stx-transfer? fee tx-sender contract-owner)))
    
    (map-set disputes
      { escrow-id: escrow-id }
      (merge dispute {
        resolved: true,
        winner: (some winner)
      })
    )
    
    (map-set escrows
      { escrow-id: escrow-id }
      (merge escrow {
        state: state-completed,
        completed-at: (some stacks-block-height)
      })
    )
    
    (ok true)
  )
)

(define-public (cancel-escrow (escrow-id uint))
  (let
    (
      (escrow (unwrap! (map-get? escrows { escrow-id: escrow-id }) err-not-found))
    )
    (asserts! (is-eq tx-sender (get buyer escrow)) err-unauthorized)
    (asserts! (is-eq (get state escrow) state-pending) err-invalid-state)
    
    (map-set escrows
      { escrow-id: escrow-id }
      (merge escrow { state: state-cancelled })
    )
    
    (ok true)
  )
)

;; Admin functions
(define-public (set-arbiter (new-arbiter principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set arbiter new-arbiter)
    (ok true)
  )
)

(define-public (set-platform-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-fee u1000) err-invalid-state) ;; Max 10%
    (var-set platform-fee-percentage new-fee)
    (ok true)
  )
)