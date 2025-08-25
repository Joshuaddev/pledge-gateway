;; Pledge Gateway - Smart Conditional Payment System
;; A comprehensive platform for conditional payments based on verifiable conditions and oracles

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_PLEDGE_NOT_FOUND (err u404))
(define-constant ERR_INVALID_INPUT (err u400))
(define-constant ERR_INSUFFICIENT_FUNDS (err u402))
(define-constant ERR_CONDITION_NOT_MET (err u403))
(define-constant ERR_PLEDGE_EXPIRED (err u405))
(define-constant ERR_ALREADY_EXECUTED (err u406))
(define-constant ERR_ORACLE_FAILED (err u407))
(define-constant MIN_PLEDGE_AMOUNT u100)
(define-constant MAX_CONDITION_DURATION u52560) ;; ~1 year in blocks

;; Data structures
(define-map conditional-pledges
  { pledge-id: uint }
  {
    creator: principal,
    beneficiary: principal,
    amount: uint,
    condition-type: (string-ascii 30),
    condition-data: (buff 64),
    oracle-address: (optional principal),
    created-at: uint,
    deadline: uint,
    status: (string-ascii 20),
    is-executed: bool,
    execution-block: (optional uint)
  }
)

(define-map condition-validators
  { condition-type: (string-ascii 30) }
  {
    validator-address: principal,
    validation-fee: uint,
    is-active: bool,
    success-rate: uint,
    total-validations: uint
  }
)

(define-map pledge-conditions
  { pledge-id: uint }
  {
    condition-met: bool,
    verification-data: (buff 128),
    verified-at: (optional uint),
    verifier: (optional principal),
    confidence-score: uint
  }
)

(define-map escrow-balances
  { pledge-id: uint }
  {
    locked-amount: uint,
    penalty-amount: uint,
    refund-eligible: bool,
    last-updated: uint
  }
)

(define-map user-pledges
  { user: principal }
  {
    total-created: uint,
    total-received: uint,
    successful-pledges: uint,
    failed-pledges: uint,
    reputation-score: uint
  }
)

(define-map milestone-conditions
  { pledge-id: uint, milestone-id: uint }
  {
    description: (string-ascii 100),
    required-value: uint,
    current-value: uint,
    is-completed: bool,
    completion-block: (optional uint)
  }
)

;; Data variables
(define-data-var next-pledge-id uint u1)
(define-data-var total-pledges uint u0)
(define-data-var total-locked-funds uint u0)
(define-data-var total-executed-pledges uint u0)
(define-data-var platform-fee-bps uint u200) ;; 2% platform fee

;; Helper functions
(define-private (validate-string-input (input (string-ascii 30)))
  (> (len input) u0)
)

(define-private (validate-long-string-input (input (string-ascii 100)))
  (> (len input) u0)
)

(define-private (validate-pledge-id (pledge-id uint))
  (and (> pledge-id u0) (< pledge-id (var-get next-pledge-id)))
)

(define-private (is-pledge-expired (pledge-id uint))
  (let ((pledge (unwrap! (map-get? conditional-pledges { pledge-id: pledge-id }) true)))
    (> block-height (get deadline pledge))
  )
)

(define-private (calculate-platform-fee (amount uint))
  (/ (* amount (var-get platform-fee-bps)) u10000)
)

(define-private (is-condition-validator (condition-type (string-ascii 30)) (validator principal))
  (let ((validator-info (map-get? condition-validators { condition-type: condition-type })))
    (match validator-info
      some-validator (is-eq (get validator-address some-validator) validator)
      false
    )
  )
)

(define-private (update-user-stats (user principal) (is-creator bool) (is-successful bool) (amount uint))
  (let ((stats (default-to 
    { total-created: u0, total-received: u0, successful-pledges: u0, 
      failed-pledges: u0, reputation-score: u100 }
    (map-get? user-pledges { user: user }))))
    
    (map-set user-pledges
      { user: user }
      (if is-creator
        (merge stats {
          total-created: (+ (get total-created stats) u1),
          successful-pledges: (if is-successful (+ (get successful-pledges stats) u1) (get successful-pledges stats)),
          failed-pledges: (if (not is-successful) (+ (get failed-pledges stats) u1) (get failed-pledges stats)),
          reputation-score: (if is-successful (+ (get reputation-score stats) u5) (max-uint u0 (- (get reputation-score stats) u2)))
        })
        (merge stats {
          total-received: (+ (get total-received stats) amount),
          reputation-score: (+ (get reputation-score stats) u1)
        })
      )
    )
  )
)

;; Helper function for max
(define-private (max-uint (a uint) (b uint))
  (if (>= a b) a b)
)

;; Public functions
(define-public (register-condition-validator (condition-type (string-ascii 30)) 
                                           (validator-address principal)
                                           (validation-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (validate-string-input condition-type) ERR_INVALID_INPUT)
    (asserts! (> validation-fee u0) ERR_INVALID_INPUT)
    
    (map-set condition-validators
      { condition-type: condition-type }
      {
        validator-address: validator-address,
        validation-fee: validation-fee,
        is-active: true,
        success-rate: u100,
        total-validations: u0
      }
    )
    (ok true)
  )
)

(define-public (create-conditional-pledge (beneficiary principal)
                                         (amount uint)
                                         (condition-type (string-ascii 30))
                                         (condition-data (buff 64))
                                         (duration-blocks uint)
                                         (oracle-address (optional principal)))
  (let ((pledge-id (var-get next-pledge-id)))
    (asserts! (>= amount MIN_PLEDGE_AMOUNT) ERR_INSUFFICIENT_FUNDS)
    (asserts! (validate-string-input condition-type) ERR_INVALID_INPUT)
    (asserts! (and (> duration-blocks u0) (<= duration-blocks MAX_CONDITION_DURATION)) ERR_INVALID_INPUT)
    (asserts! (not (is-eq tx-sender beneficiary)) ERR_INVALID_INPUT)
    
    ;; Verify condition validator exists
    (let ((validator (map-get? condition-validators { condition-type: condition-type })))
      (asserts! (is-some validator) ERR_INVALID_INPUT)
      
      ;; Create pledge
      (map-set conditional-pledges
        { pledge-id: pledge-id }
        {
          creator: tx-sender,
          beneficiary: beneficiary,
          amount: amount,
          condition-type: condition-type,
          condition-data: condition-data,
          oracle-address: oracle-address,
          created-at: block-height,
          deadline: (+ block-height duration-blocks),
          status: "pending",
          is-executed: false,
          execution-block: none
        }
      )
      
      ;; Initialize escrow
      (map-set escrow-balances
        { pledge-id: pledge-id }
        {
          locked-amount: amount,
          penalty-amount: (calculate-platform-fee amount),
          refund-eligible: true,
          last-updated: block-height
        }
      )
      
      ;; Initialize condition state
      (map-set pledge-conditions
        { pledge-id: pledge-id }
        {
          condition-met: false,
          verification-data: 0x00,
          verified-at: none,
          verifier: none,
          confidence-score: u0
        }
      )
      
      ;; Update global stats
      (var-set next-pledge-id (+ pledge-id u1))
      (var-set total-pledges (+ (var-get total-pledges) u1))
      (var-set total-locked-funds (+ (var-get total-locked-funds) amount))
      
      ;; Update user stats
      (update-user-stats tx-sender true false amount)
      
      (ok pledge-id)
    )
  )
)

(define-public (verify-condition (pledge-id uint) 
                                (verification-data (buff 128))
                                (confidence-score uint))
  (let (
    (pledge (unwrap! (map-get? conditional-pledges { pledge-id: pledge-id }) ERR_PLEDGE_NOT_FOUND))
    (condition-state (unwrap! (map-get? pledge-conditions { pledge-id: pledge-id }) ERR_PLEDGE_NOT_FOUND))
  )
    (asserts! (validate-pledge-id pledge-id) ERR_PLEDGE_NOT_FOUND)
    (asserts! (is-condition-validator (get condition-type pledge) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (is-pledge-expired pledge-id)) ERR_PLEDGE_EXPIRED)
    (asserts! (not (get condition-met condition-state)) ERR_ALREADY_EXECUTED)
    (asserts! (<= confidence-score u100) ERR_INVALID_INPUT)
    
    ;; Update condition verification
    (map-set pledge-conditions
      { pledge-id: pledge-id }
      (merge condition-state {
        condition-met: (>= confidence-score u80), ;; 80% confidence threshold
        verification-data: verification-data,
        verified-at: (some block-height),
        verifier: (some tx-sender),
        confidence-score: confidence-score
      })
    )
    
    ;; Update validator stats
    (let ((validator (unwrap! (map-get? condition-validators { condition-type: (get condition-type pledge) }) ERR_INVALID_INPUT)))
      (map-set condition-validators
        { condition-type: (get condition-type pledge) }
        (merge validator { total-validations: (+ (get total-validations validator) u1) })
      )
    )
    
    (ok (>= confidence-score u80))
  )
)

(define-public (execute-pledge (pledge-id uint))
  (let (
    (pledge (unwrap! (map-get? conditional-pledges { pledge-id: pledge-id }) ERR_PLEDGE_NOT_FOUND))
    (condition-state (unwrap! (map-get? pledge-conditions { pledge-id: pledge-id }) ERR_PLEDGE_NOT_FOUND))
    (escrow (unwrap! (map-get? escrow-balances { pledge-id: pledge-id }) ERR_PLEDGE_NOT_FOUND))
  )
    (asserts! (validate-pledge-id pledge-id) ERR_PLEDGE_NOT_FOUND)
    (asserts! (not (get is-executed pledge)) ERR_ALREADY_EXECUTED)
    (asserts! (not (is-pledge-expired pledge-id)) ERR_PLEDGE_EXPIRED)
    (asserts! (get condition-met condition-state) ERR_CONDITION_NOT_MET)
    
    (let ((platform-fee (get penalty-amount escrow))
          (beneficiary-amount (- (get locked-amount escrow) platform-fee)))
      
      ;; Update pledge status
      (map-set conditional-pledges
        { pledge-id: pledge-id }
        (merge pledge {
          status: "executed",
          is-executed: true,
          execution-block: (some block-height)
        })
      )
      
      ;; Update escrow
      (map-set escrow-balances
        { pledge-id: pledge-id }
        (merge escrow {
          locked-amount: u0,
          refund-eligible: false,
          last-updated: block-height
        })
      )
      
      ;; Update global stats
      (var-set total-executed-pledges (+ (var-get total-executed-pledges) u1))
      (var-set total-locked-funds (- (var-get total-locked-funds) (get amount pledge)))
      
      ;; Update user stats
      (update-user-stats (get creator pledge) true true (get amount pledge))
      (update-user-stats (get beneficiary pledge) false true beneficiary-amount)
      
      (ok beneficiary-amount)
    )
  )
)

(define-public (refund-expired-pledge (pledge-id uint))
  (let (
    (pledge (unwrap! (map-get? conditional-pledges { pledge-id: pledge-id }) ERR_PLEDGE_NOT_FOUND))
    (condition-state (unwrap! (map-get? pledge-conditions { pledge-id: pledge-id }) ERR_PLEDGE_NOT_FOUND))
    (escrow (unwrap! (map-get? escrow-balances { pledge-id: pledge-id }) ERR_PLEDGE_NOT_FOUND))
  )
    (asserts! (validate-pledge-id pledge-id) ERR_PLEDGE_NOT_FOUND)
    (asserts! (not (get is-executed pledge)) ERR_ALREADY_EXECUTED)
    (asserts! (is-pledge-expired pledge-id) ERR_CONDITION_NOT_MET)
    (asserts! (not (get condition-met condition-state)) ERR_CONDITION_NOT_MET)
    (asserts! (get refund-eligible escrow) ERR_INVALID_INPUT)
    
    (let ((refund-amount (- (get locked-amount escrow) (get penalty-amount escrow))))
      
      ;; Update pledge status
      (map-set conditional-pledges
        { pledge-id: pledge-id }
        (merge pledge { status: "refunded" })
      )
      
      ;; Update escrow
      (map-set escrow-balances
        { pledge-id: pledge-id }
        (merge escrow {
          locked-amount: u0,
          refund-eligible: false,
          last-updated: block-height
        })
      )
      
      ;; Update global stats
      (var-set total-locked-funds (- (var-get total-locked-funds) (get amount pledge)))
      
      ;; Update user stats
      (update-user-stats (get creator pledge) true false (get amount pledge))
      
      (ok refund-amount)
    )
  )
)

(define-public (add-milestone (pledge-id uint)
                             (milestone-id uint)
                             (description (string-ascii 100))
                             (required-value uint))
  (let ((pledge (unwrap! (map-get? conditional-pledges { pledge-id: pledge-id }) ERR_PLEDGE_NOT_FOUND)))
    (asserts! (validate-pledge-id pledge-id) ERR_PLEDGE_NOT_FOUND)
    (asserts! (is-eq tx-sender (get creator pledge)) ERR_UNAUTHORIZED)
    (asserts! (validate-long-string-input description) ERR_INVALID_INPUT)
    (asserts! (> required-value u0) ERR_INVALID_INPUT)
    
    (map-set milestone-conditions
      { pledge-id: pledge-id, milestone-id: milestone-id }
      {
        description: description,
        required-value: required-value,
        current-value: u0,
        is-completed: false,
        completion-block: none
      }
    )
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-pledge (pledge-id uint))
  (map-get? conditional-pledges { pledge-id: pledge-id })
)

(define-read-only (get-condition-status (pledge-id uint))
  (map-get? pledge-conditions { pledge-id: pledge-id })
)

(define-read-only (get-escrow-balance (pledge-id uint))
  (map-get? escrow-balances { pledge-id: pledge-id })
)

(define-read-only (get-user-stats (user principal))
  (map-get? user-pledges { user: user })
)

(define-read-only (check-pledge-eligibility (pledge-id uint))
  (let (
    (pledge (map-get? conditional-pledges { pledge-id: pledge-id }))
    (condition-state (map-get? pledge-conditions { pledge-id: pledge-id }))
  )
    (match pledge
      some-pledge
        (match condition-state
          some-condition
            (ok {
              can-execute: (and (get condition-met some-condition) (not (get is-executed some-pledge))),
              can-refund: (and (is-pledge-expired pledge-id) (not (get condition-met some-condition))),
              is-expired: (is-pledge-expired pledge-id),
              condition-met: (get condition-met some-condition)
            })
          (err ERR_PLEDGE_NOT_FOUND)
        )
      (err ERR_PLEDGE_NOT_FOUND)
    )
  )
)

(define-read-only (get-platform-stats)
  (ok {
    total-pledges: (var-get total-pledges),
    total-locked-funds: (var-get total-locked-funds),
    total-executed-pledges: (var-get total-executed-pledges),
    platform-fee-rate: (var-get platform-fee-bps),
    next-pledge-id: (var-get next-pledge-id)
  })
)