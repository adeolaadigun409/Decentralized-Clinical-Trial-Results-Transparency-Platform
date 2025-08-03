;; Publication Bias Detection Contract
;; Monitors trial completion vs publication rates

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-PUBLICATION-NOT-FOUND (err u401))
(define-constant ERR-INVALID-INPUT (err u402))
(define-constant ERR-TRIAL-NOT-COMPLETED (err u403))
(define-constant ERR-ALREADY-PUBLISHED (err u404))

;; Data Variables
(define-data-var next-publication-id uint u1)
(define-data-var publication-deadline-days uint u730) ;; 2 years default

;; Data Maps
(define-map trial-publications
  { protocol-id: uint }
  {
    publication-id: (optional uint),
    completion-block: uint,
    publication-block: (optional uint),
    publication-status: (string-ascii 20),
    results-summary: (optional (string-ascii 1000)),
    statistical-significance: (optional bool),
    journal-name: (optional (string-ascii 200))
  }
)

(define-map publication-details
  { publication-id: uint }
  {
    protocol-id: uint,
    title: (string-ascii 300),
    authors: (string-ascii 500),
    doi: (string-ascii 100),
    publication-date: uint,
    peer-reviewed: bool,
    open-access: bool
  }
)

(define-map bias-reports
  { report-id: uint }
  {
    protocol-id: uint,
    reporter: principal,
    bias-type: (string-ascii 50),
    evidence: (string-ascii 1000),
    report-block: uint,
    status: (string-ascii 20),
    severity-level: uint
  }
)

(define-map authorized-reporters
  { reporter: principal }
  { authorized: bool }
)

;; Read-only functions
(define-read-only (get-trial-publication (protocol-id uint))
  (map-get? trial-publications { protocol-id: protocol-id })
)

(define-read-only (get-publication-details (publication-id uint))
  (map-get? publication-details { publication-id: publication-id })
)

(define-read-only (get-bias-report (report-id uint))
  (map-get? bias-reports { report-id: report-id })
)

(define-read-only (is-overdue-publication (protocol-id uint))
  (match (map-get? trial-publications { protocol-id: protocol-id })
    trial-pub (let ((days-since-completion (/ (- block-height (get completion-block trial-pub)) u144))) ;; ~144 blocks per day
                (and
                  (is-none (get publication-block trial-pub))
                  (> days-since-completion (var-get publication-deadline-days))
                ))
    false
  )
)

(define-read-only (calculate-publication-rate (total-trials uint) (published-trials uint))
  (if (> total-trials u0)
    (/ (* published-trials u10000) total-trials) ;; Fixed calculation for publication rate
    u0
  )
)

(define-read-only (is-authorized-reporter (reporter principal))
  (default-to false (get authorized (map-get? authorized-reporters { reporter: reporter })))
)

(define-read-only (validate-publication-deadline (days uint))
  (and (>= days u30) (<= days u1825)) ;; 30 days to 5 years
)

;; Public functions
(define-public (register-trial-completion (protocol-id uint))
  (begin
    (asserts! (> protocol-id u0) ERR-INVALID-INPUT)
    ;; In a real implementation, this would verify the trial is actually completed
    ;; by checking the trial-protocol-registry contract

    (map-set trial-publications
      { protocol-id: protocol-id }
      {
        publication-id: none,
        completion-block: block-height,
        publication-block: none,
        publication-status: "unpublished",
        results-summary: none,
        statistical-significance: none,
        journal-name: none
      }
    )
    (ok true)
  )
)

(define-public (register-publication
  (protocol-id uint)
  (title (string-ascii 300))
  (authors (string-ascii 500))
  (doi (string-ascii 100))
  (peer-reviewed bool)
  (open-access bool)
  (results-summary (string-ascii 1000))
  (statistically-significant bool)
  (journal-name (string-ascii 200))
)
  (let ((publication-id (var-get next-publication-id))
        (trial-pub (unwrap! (map-get? trial-publications { protocol-id: protocol-id }) ERR-TRIAL-NOT-COMPLETED)))

    (asserts! (is-none (get publication-id trial-pub)) ERR-ALREADY-PUBLISHED)
    (asserts! (> (len title) u0) ERR-INVALID-INPUT)
    (asserts! (> (len authors) u0) ERR-INVALID-INPUT)

    (map-set publication-details
      { publication-id: publication-id }
      {
        protocol-id: protocol-id,
        title: title,
        authors: authors,
        doi: doi,
        publication-date: block-height,
        peer-reviewed: peer-reviewed,
        open-access: open-access
      }
    )

    (map-set trial-publications
      { protocol-id: protocol-id }
      (merge trial-pub {
        publication-id: (some publication-id),
        publication-block: (some block-height),
        publication-status: "published",
        results-summary: (some results-summary),
        statistical-significance: (some statistically-significant),
        journal-name: (some journal-name)
      })
    )

    (var-set next-publication-id (+ publication-id u1))
    (ok publication-id)
  )
)

(define-public (report-publication-bias
  (report-id uint)
  (protocol-id uint)
  (bias-type (string-ascii 50))
  (evidence (string-ascii 1000))
  (severity-level uint)
)
  (begin
    (asserts! (is-authorized-reporter tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> protocol-id u0) ERR-INVALID-INPUT)
    (asserts! (> (len bias-type) u0) ERR-INVALID-INPUT)
    (asserts! (> (len evidence) u0) ERR-INVALID-INPUT)
    (asserts! (and (>= severity-level u1) (<= severity-level u4)) ERR-INVALID-INPUT) ;; Validate severity level

    (map-set bias-reports
      { report-id: report-id }
      {
        protocol-id: protocol-id,
        reporter: tx-sender,
        bias-type: bias-type,
        evidence: evidence,
        report-block: block-height,
        status: "pending",
        severity-level: severity-level
      }
    )
    (ok true)
  )
)

(define-public (update-publication-status (protocol-id uint) (new-status (string-ascii 20)))
  (let ((trial-pub (unwrap! (map-get? trial-publications { protocol-id: protocol-id }) ERR-PUBLICATION-NOT-FOUND)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set trial-publications
      { protocol-id: protocol-id }
      (merge trial-pub { publication-status: new-status })
    )
    (ok true)
  )
)

(define-public (set-publication-deadline (days uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (validate-publication-deadline days) ERR-INVALID-INPUT) ;; Validate publication deadline
    (var-set publication-deadline-days days)
    (ok true)
  )
)

(define-public (authorize-reporter (reporter principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-set authorized-reporters
      { reporter: reporter }
      { authorized: true }
    )
    (ok true)
  )
)

(define-public (revoke-reporter (reporter principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-set authorized-reporters
      { reporter: reporter }
      { authorized: false }
    )
    (ok true)
  )
)

(define-public (validate-bias-severity (severity-level uint))
  (begin
    (asserts! (and (>= severity-level u1) (<= severity-level u4)) ERR-INVALID-INPUT)
    (ok true)
  )
)
