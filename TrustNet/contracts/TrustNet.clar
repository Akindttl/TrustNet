;; TrustNet: Decentralized Reputation System
;; A system for users to build and maintain reputation through attestations

;; Define the data structures
(define-map user-reputation
  { user: principal }
  { 
    score: uint,
    positive-attestations: uint,
    negative-attestations: uint,
    last-updated: uint
  }
)

;; Define the attestation records
(define-map attestations
  { from: principal, to: principal }
  {
    value: int,           ;; Can be positive or negative
    timestamp: uint,
    comment: (string-utf8 256)
  }
)

;; Store categories for attestations
(define-map categories
  { category-id: uint }
  { name: (string-utf8 64) }
)

;; Map users to categories they've received attestations in
(define-map user-categories
  { user: principal, category-id: uint }
  { count: uint }
)

;; Counter for category IDs
(define-data-var next-category-id uint u1)

;; Constants
(define-constant ATTESTATION_COOLDOWN u86400) ;; 24 hours in seconds
(define-constant MIN_SCORE u0)
(define-constant MAX_SCORE u100)
(define-constant CONTRACT_OWNER tx-sender)

;; Error codes
(define-constant ERR_UNAUTHORIZED u401)
(define-constant ERR_NOT_FOUND u404)
(define-constant ERR_COOLDOWN_ACTIVE u429)
(define-constant ERR_SELF_ATTESTATION u403)

;; Initialize a user's reputation if not already registered
(define-public (initialize-reputation)
  (let ((user tx-sender))
    (if (is-some (map-get? user-reputation { user: user }))
      (ok true) ;; Already initialized
      (begin
        (map-set user-reputation
          { user: user }
          {
            score: u50,  ;; Start with neutral score
            positive-attestations: u0,
            negative-attestations: u0,
            last-updated: (unwrap-panic (get-block-info? time u0))
          }
        )
        (ok true)
      )
    )
  )
)

;; Add a new attestation category
(define-public (add-category (name (string-utf8 64)))
  (let ((category-id (var-get next-category-id)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) (err ERR_UNAUTHORIZED))
    (map-set categories
      { category-id: category-id }
      { name: name }
    )
    (var-set next-category-id (+ category-id u1))
    (ok category-id)
  )
)

;; Make an attestation about another user
(define-public (make-attestation (to principal) (value int) (category-id uint) (comment (string-utf8 256)))
  (let (
    (from tx-sender)
    (current-time (unwrap-panic (get-block-info? time u0)))
    (previous-attestation (map-get? attestations { from: from, to: to }))
  )
    ;; Check conditions
    (asserts! (not (is-eq from to)) (err ERR_SELF_ATTESTATION))
    (asserts! (is-some (map-get? categories { category-id: category-id })) (err ERR_NOT_FOUND))
    
    ;; Check if cooldown is active
    (if (is-some previous-attestation)
      (let ((last-timestamp (get timestamp (unwrap-panic previous-attestation))))
        (asserts! (> current-time (+ last-timestamp ATTESTATION_COOLDOWN)) (err ERR_COOLDOWN_ACTIVE))
      )
      true
    )
        
    ;; Initialize target's reputation if needed
    (if (is-none (map-get? user-reputation { user: to }))
      (map-set user-reputation
        { user: to }
        {
          score: u50,
          positive-attestations: u0,
          negative-attestations: u0,
          last-updated: current-time
        }
      )
      true
    )
    
    ;; Record the attestation
    (map-set attestations
      { from: from, to: to }
      {
        value: value,
        timestamp: current-time,
        comment: comment
      }
    )
    
    ;; Update user's reputation
    (let (
      (user-rep (unwrap-panic (map-get? user-reputation { user: to })))
      (pos-count (get positive-attestations user-rep))
      (neg-count (get negative-attestations user-rep))
      (new-pos (if (> value 0) (+ pos-count u1) pos-count))
      (new-neg (if (< value 0) (+ neg-count u1) neg-count))
      (new-score (calculate-score new-pos new-neg))
    )
      (map-set user-reputation
        { user: to }
        {
          score: new-score,
          positive-attestations: new-pos,
          negative-attestations: new-neg,
          last-updated: current-time
        }
      )
      
      ;; Update category count for the user
      (update-category-count to category-id)
      
      (ok true)
    )
  )
)

;; Private function to calculate reputation score
(define-private (calculate-score (pos uint) (neg uint))
  (let (
    (total (+ pos neg))
    (score u50)  ;; Default neutral score
  )
    (if (> total u0)
      (let (
        (positive-weight (/ (* pos u100) total))
      )
        ;; Ensure score stays within bounds
        (if (< positive-weight MIN_SCORE)
          MIN_SCORE
          (if (> positive-weight MAX_SCORE)
            MAX_SCORE
            positive-weight
          )
        )
      )
      score
    )
  )
)

;; Helper to update category counts
(define-private (update-category-count (user principal) (category-id uint))
  (let (
    (user-category-key { user: user, category-id: category-id })
    (existing-count (default-to { count: u0 } (map-get? user-categories user-category-key)))
  )
    (map-set user-categories
      user-category-key
      { count: (+ (get count existing-count) u1) }
    )
  )
)

;; Get a user's reputation
(define-read-only (get-reputation (user principal))
  (map-get? user-reputation { user: user })
)

;; Get a specific attestation
(define-read-only (get-attestation (from principal) (to principal))
  (map-get? attestations { from: from, to: to })
)

;; Get category information
(define-read-only (get-category (category-id uint))
  (map-get? categories { category-id: category-id })
)

;; Get user's category count
(define-read-only (get-user-category-count (user principal) (category-id uint))
  (default-to { count: u0 }
    (map-get? user-categories { user: user, category-id: category-id })
  )
)

;; Helper to calculate decay factor based on time passed
(define-private (calculate-decay-factor (days-passed uint))
  (let (
    ;; Base monthly decay of 5%
    (monthly-decay-rate u5)
    (num-months (/ days-passed u30))
    (decay-percentage (* monthly-decay-rate num-months))
    ;; Cap max decay at 75% to preserve some history
    (capped-decay (if (> decay-percentage u75) u75 decay-percentage))
  )
    ;; Return the percentage to keep (100% - decay%)
    (- u100 capped-decay)
  )
)

;; Apply decay to a value
(define-private (calculate-decayed-value (original-value uint) (decay-factor uint))
  ;; Apply decay: original * (decay-factor / 100)
  (/ (* original-value decay-factor) u100)
)

;; New feature: Reputation Decay System
;; This ensures that reputation reflects recent behavior more heavily than past behavior
(define-public (apply-reputation-decay (user principal))
  (let (
    (current-time (unwrap-panic (get-block-info? time u0)))
    (user-rep (map-get? user-reputation { user: user }))
  )
    ;; Check if user exists
    (asserts! (is-some user-rep) (err ERR_NOT_FOUND))
    
    (let (
      (unwrapped-rep (unwrap-panic user-rep))
      (last-updated (get last-updated unwrapped-rep))
      (days-since-update (/ (- current-time last-updated) u86400))
    )
      ;; Only apply decay if it's been at least 30 days
      (if (>= days-since-update u30)
        (let (
          (decay-factor (calculate-decay-factor days-since-update))
          (current-score (get score unwrapped-rep))
          (pos-count (get positive-attestations unwrapped-rep))
          (neg-count (get negative-attestations unwrapped-rep))
          ;; Apply decay to the positive and negative attestation counts
          (decayed-pos (calculate-decayed-value pos-count decay-factor))
          (decayed-neg (calculate-decayed-value neg-count decay-factor))
          ;; Recalculate score with decayed values
          (new-score (calculate-score decayed-pos decayed-neg))
        )
          (map-set user-reputation
            { user: user }
            {
              score: new-score,
              positive-attestations: decayed-pos,
              negative-attestations: decayed-neg,
              last-updated: current-time
            }
          )
          (ok true)
        )
        (ok false)  ;; No decay needed yet
      )
    )
  )
)

