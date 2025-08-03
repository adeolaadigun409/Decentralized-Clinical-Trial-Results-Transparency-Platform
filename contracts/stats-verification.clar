;; Statistical Analysis Code Verification Contract
;; Validates statistical methods and ensures reproducibility

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-ANALYSIS-NOT-FOUND (err u301))
(define-constant ERR-INVALID-INPUT (err u302))
(define-constant ERR-ALREADY-VERIFIED (err u303))
(define-constant ERR-INVALID-STATUS (err u304))

;; Data Variables
(define-data-var next-analysis-id uint u1)

;; Data Maps
(define-map statistical-analyses
  { analysis-id: uint }
  {
    protocol-id: uint,
    analyst: principal,
    method-description: (string-ascii 1000),
    code-hash: (buff 32),
    submission-block: uint,
    status: (string-ascii 20),
    verified-by: (optional principal),
    verification-block: (optional uint)
  }
)

(define-map analysis-reviews
  { analysis-id: uint, reviewer: principal }
  {
    review-comments: (string-ascii 1000),
    recommendation: (string-ascii 20),
    review-block: uint,
    confidence-score: uint
  }
)

(define-map verification-criteria
  { criteria-id: uint }
  {
    name: (string-ascii 100),
    description: (string-ascii 500),
    weight: uint,
    active: bool
  }
)

(define-map authorized-verifiers
  { verifier: principal }
  {
    authorized: bool,
    expertise-area: (string-ascii 100)
  }
)

;; Read-only functions
(define-read-only (get-analysis (analysis-id uint))
  (map-get? statistical-analyses { analysis-id: analysis-id })
)

(define-read-only (get-analysis-review (analysis-id uint) (reviewer principal))
  (map-get? analysis-reviews { analysis-id: analysis-id, reviewer: reviewer })
)

(define-read-only (get-next-analysis-id)
  (var-get next-analysis-id)
)

(define-read-only (is-authorized-verifier (verifier principal))
  (default-to false (get authorized (map-get? authorized-verifiers { verifier: verifier })))
)

(define-read-only (verify-code-hash (expected-hash (buff 32)) (provided-hash (buff 32)))
  (is-eq expected-hash provided-hash)
)

(define-read-only (is-valid-confidence-score (score uint))
  (and (>= score u0) (<= score u100))
)

;; Public functions
(define-public (submit-analysis
  (protocol-id uint)
  (method-description (string-ascii 1000))
  (code-hash (buff 32))
)
  (let ((analysis-id (var-get next-analysis-id)))
    (asserts! (> protocol-id u0) ERR-INVALID-INPUT)
    (asserts! (> (len method-description) u0) ERR-INVALID-INPUT)
    (asserts! (> (len code-hash) u0) ERR-INVALID-INPUT)

    (map-set statistical-analyses
      { analysis-id: analysis-id }
      {
        protocol-id: protocol-id,
        analyst: tx-sender,
        method-description: method-description,
        code-hash: code-hash,
        submission-block: block-height,
        status: "submitted",
        verified-by: none,
        verification-block: none
      }
    )

    (var-set next-analysis-id (+ analysis-id u1))
    (ok analysis-id)
  )
)

(define-public (submit-review
  (analysis-id uint)
  (review-comments (string-ascii 1000))
  (recommendation (string-ascii 20))
  (confidence-score uint)
)
  (let ((analysis (unwrap! (map-get? statistical-analyses { analysis-id: analysis-id }) ERR-ANALYSIS-NOT-FOUND)))
    (asserts! (is-authorized-verifier tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> (len review-comments) u0) ERR-INVALID-INPUT)
    (asserts! (<= confidence-score u100) ERR-INVALID-INPUT)
    (asserts! (>= confidence-score u0) ERR-INVALID-INPUT)
    (asserts! (not (is-eq tx-sender (get analyst analysis))) ERR-NOT-AUTHORIZED)

    (map-set analysis-reviews
      { analysis-id: analysis-id, reviewer: tx-sender }
      {
        review-comments: review-comments,
        recommendation: recommendation,
        review-block: block-height,
        confidence-score: confidence-score
      }
    )
    (ok true)
  )
)

(define-public (verify-analysis (analysis-id uint))
  (let ((analysis (unwrap! (map-get? statistical-analyses { analysis-id: analysis-id }) ERR-ANALYSIS-NOT-FOUND)))
    (asserts! (is-authorized-verifier tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status analysis) "submitted") ERR-INVALID-STATUS)

    (map-set statistical-analyses
      { analysis-id: analysis-id }
      (merge analysis {
        status: "verified",
        verified-by: (some tx-sender),
        verification-block: (some block-height)
      })
    )
    (ok true)
  )
)

(define-public (reject-analysis (analysis-id uint))
  (let ((analysis (unwrap! (map-get? statistical-analyses { analysis-id: analysis-id }) ERR-ANALYSIS-NOT-FOUND)))
    (asserts! (is-authorized-verifier tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status analysis) "submitted") ERR-INVALID-STATUS)

    (map-set statistical-analyses
      { analysis-id: analysis-id }
      (merge analysis { status: "rejected" })
    )
    (ok true)
  )
)

(define-public (update-analysis
  (analysis-id uint)
  (method-description (string-ascii 1000))
  (code-hash (buff 32))
)
  (let ((analysis (unwrap! (map-get? statistical-analyses { analysis-id: analysis-id }) ERR-ANALYSIS-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get analyst analysis)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status analysis) "rejected") ERR-INVALID-STATUS)
    (asserts! (> (len method-description) u0) ERR-INVALID-INPUT)

    (map-set statistical-analyses
      { analysis-id: analysis-id }
      (merge analysis {
        method-description: method-description,
        code-hash: code-hash,
        status: "resubmitted",
        verified-by: none,
        verification-block: none
      })
    )
    (ok true)
  )
)

(define-public (authorize-verifier (verifier principal) (expertise-area (string-ascii 100)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-set authorized-verifiers
      { verifier: verifier }
      {
        authorized: true,
        expertise-area: expertise-area
      }
    )
    (ok true)
  )
)

(define-public (revoke-verifier (verifier principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-set authorized-verifiers
      { verifier: verifier }
      {
        authorized: false,
        expertise-area: ""
      }
    )
    (ok true)
  )
)
