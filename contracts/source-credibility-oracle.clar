;; Source Credibility Oracle Contract
;; Automated source credibility assessment using historical accuracy and bias analysis

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-SOURCE-NOT-FOUND (err u101))
(define-constant ERR-INVALID-SCORE (err u102))
(define-constant ERR-SOURCE-EXISTS (err u103))
(define-constant ERR-INSUFFICIENT-DATA (err u104))

;; Minimum reports required for credibility calculation
(define-constant MIN-REPORTS u10)
(define-constant MAX-CREDIBILITY-SCORE u100)
(define-constant BIAS-THRESHOLD u30)

;; Data Variables
(define-data-var contract-owner principal tx-sender)
(define-data-var total-sources uint u0)
(define-data-var assessment-fee uint u1000000) ;; 1 STX in microSTX

;; Source credibility structure
(define-map source-registry
    { source-id: (string-ascii 128) }
    {
        name: (string-utf8 256),
        domain: (string-ascii 128),
        credibility-score: uint,
        accuracy-rate: uint,
        bias-score: uint,
        total-reports: uint,
        verified-reports: uint,
        last-updated: uint,
        status: (string-ascii 20),
        created-at: uint
    }
)

;; Source reporting history
(define-map source-reports
    { source-id: (string-ascii 128), report-id: uint }
    {
        reporter: principal,
        accuracy: uint,
        bias-rating: uint,
        evidence-quality: uint,
        timestamp: uint,
        verified: bool
    }
)

;; Reporter reputation tracking
(define-map reporter-stats
    { reporter: principal }
    {
        total-reports: uint,
        accurate-reports: uint,
        reputation-score: uint,
        stake-amount: uint,
        joined-at: uint
    }
)

;; Source assessment requests
(define-map assessment-queue
    { request-id: uint }
    {
        source-id: (string-ascii 128),
        requester: principal,
        priority: uint,
        status: (string-ascii 20),
        created-at: uint
    }
)

;; Counters
(define-data-var next-report-id uint u1)
(define-data-var next-request-id uint u1)

;; Public Functions

;; Register new source for credibility tracking
(define-public (register-source (source-id (string-ascii 128)) 
                                (name (string-utf8 256))
                                (domain (string-ascii 128)))
    (let ((existing-source (map-get? source-registry { source-id: source-id })))
        (if (is-some existing-source)
            (err ERR-SOURCE-EXISTS)
            (begin
                (map-set source-registry
                    { source-id: source-id }
                    {
                        name: name,
                        domain: domain,
                        credibility-score: u50, ;; Starting neutral score
                        accuracy-rate: u0,
                        bias-score: u50, ;; Starting neutral bias
                        total-reports: u0,
                        verified-reports: u0,
                        last-updated: stacks-block-height,
                        status: "active",
                        created-at: stacks-block-height
                    }
                )
                (var-set total-sources (+ (var-get total-sources) u1))
                (ok source-id)
            )
        )
    )
)

;; Submit credibility report for a source
(define-public (submit-report (source-id (string-ascii 128))
                             (accuracy uint)
                             (bias-rating uint)
                             (evidence-quality uint))
    (let (
        (report-id (var-get next-report-id))
        (source-data (unwrap! (map-get? source-registry { source-id: source-id }) (err ERR-SOURCE-NOT-FOUND)))
        (reporter-data (default-to 
            { total-reports: u0, accurate-reports: u0, reputation-score: u50, stake-amount: u0, joined-at: stacks-block-height }
            (map-get? reporter-stats { reporter: tx-sender })
        ))
    )
        ;; Validate input parameters
        (asserts! (<= accuracy MAX-CREDIBILITY-SCORE) (err ERR-INVALID-SCORE))
        (asserts! (<= bias-rating MAX-CREDIBILITY-SCORE) (err ERR-INVALID-SCORE))
        (asserts! (<= evidence-quality MAX-CREDIBILITY-SCORE) (err ERR-INVALID-SCORE))
        
        ;; Store the report
        (map-set source-reports
            { source-id: source-id, report-id: report-id }
            {
                reporter: tx-sender,
                accuracy: accuracy,
                bias-rating: bias-rating,
                evidence-quality: evidence-quality,
                timestamp: stacks-block-height,
                verified: false
            }
        )
        
        ;; Update reporter stats
        (map-set reporter-stats
            { reporter: tx-sender }
            {
                total-reports: (+ (get total-reports reporter-data) u1),
                accurate-reports: (get accurate-reports reporter-data),
                reputation-score: (get reputation-score reporter-data),
                stake-amount: (get stake-amount reporter-data),
                joined-at: (get joined-at reporter-data)
            }
        )
        
        ;; Update source total reports
        (map-set source-registry
            { source-id: source-id }
            (merge source-data { total-reports: (+ (get total-reports source-data) u1) })
        )
        
        ;; Increment report ID counter
        (var-set next-report-id (+ report-id u1))
        
        ;; Trigger credibility recalculation if enough reports
        (if (>= (+ (get total-reports source-data) u1) MIN-REPORTS)
            (begin
                (unwrap! (recalculate-credibility source-id) (err ERR-INSUFFICIENT-DATA))
                (ok report-id)
            )
            (ok report-id)
        )
    )
)

;; Verify a report (only contract owner or authorized verifiers)
(define-public (verify-report (source-id (string-ascii 128)) (report-id uint) (is-accurate bool))
    (let (
        (report-data (unwrap! (map-get? source-reports { source-id: source-id, report-id: report-id }) (err ERR-SOURCE-NOT-FOUND)))
        (reporter (get reporter report-data))
        (reporter-stats-data (unwrap! (map-get? reporter-stats { reporter: reporter }) (err ERR-SOURCE-NOT-FOUND)))
    )
        ;; Only contract owner can verify reports for now
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR-NOT-AUTHORIZED))
        
        ;; Update report verification status
        (map-set source-reports
            { source-id: source-id, report-id: report-id }
            (merge report-data { verified: true })
        )
        
        ;; Update reporter reputation based on accuracy
        (map-set reporter-stats
            { reporter: reporter }
            (merge reporter-stats-data {
                accurate-reports: (if is-accurate 
                    (+ (get accurate-reports reporter-stats-data) u1)
                    (get accurate-reports reporter-stats-data)
                ),
                reputation-score: (calculate-reputation-score 
                    (get total-reports reporter-stats-data)
                    (if is-accurate 
                        (+ (get accurate-reports reporter-stats-data) u1)
                        (get accurate-reports reporter-stats-data)
                    )
                )
            })
        )
        
        ;; Trigger credibility recalculation
        (try! (recalculate-credibility source-id))
        
        (ok true)
    )
)

;; Recalculate source credibility score
(define-private (recalculate-credibility (source-id (string-ascii 128)))
    (let (
        (source-data (unwrap! (map-get? source-registry { source-id: source-id }) (err ERR-SOURCE-NOT-FOUND)))
        (total-reports (get total-reports source-data))
    )
        (if (>= total-reports MIN-REPORTS)
            (let (
                (credibility-score (calculate-credibility-score source-id))
                (accuracy-rate (calculate-accuracy-rate source-id))
                (bias-score (calculate-bias-score source-id))
            )
                (map-set source-registry
                    { source-id: source-id }
                    (merge source-data {
                        credibility-score: credibility-score,
                        accuracy-rate: accuracy-rate,
                        bias-score: bias-score,
                        last-updated: stacks-block-height
                    })
                )
                (ok true)
            )
            (ok true)
        )
    )
)

;; Calculate credibility score based on reports
(define-private (calculate-credibility-score (source-id (string-ascii 128)))
    (let ((weighted-score (calculate-weighted-average source-id)))
        (if (<= weighted-score MAX-CREDIBILITY-SCORE)
            weighted-score
            MAX-CREDIBILITY-SCORE
        )
    )
)

;; Calculate weighted average of all reports
(define-private (calculate-weighted-average (source-id (string-ascii 128)))
    ;; Simplified calculation - in practice would iterate through all reports
    u75 ;; Placeholder return value
)

;; Calculate accuracy rate
(define-private (calculate-accuracy-rate (source-id (string-ascii 128)))
    ;; Simplified calculation
    u80 ;; Placeholder return value
)

;; Calculate bias score
(define-private (calculate-bias-score (source-id (string-ascii 128)))
    ;; Simplified calculation  
    u45 ;; Placeholder return value
)

;; Calculate reporter reputation score
(define-private (calculate-reputation-score (total-reports uint) (accurate-reports uint))
    (if (is-eq total-reports u0)
        u50
        (/ (* accurate-reports u100) total-reports)
    )
)

;; Request credibility assessment
(define-public (request-assessment (source-id (string-ascii 128)))
    (let (
        (request-id (var-get next-request-id))
        (fee (var-get assessment-fee))
    )
        ;; Transfer assessment fee
        (try! (stx-transfer? fee tx-sender (var-get contract-owner)))
        
        ;; Queue assessment request
        (map-set assessment-queue
            { request-id: request-id }
            {
                source-id: source-id,
                requester: tx-sender,
                priority: u1,
                status: "pending",
                created-at: stacks-block-height
            }
        )
        
        (var-set next-request-id (+ request-id u1))
        (ok request-id)
    )
)

;; Read-only functions

;; Get source credibility data
(define-read-only (get-source-credibility (source-id (string-ascii 128)))
    (map-get? source-registry { source-id: source-id })
)

;; Get reporter statistics
(define-read-only (get-reporter-stats (reporter principal))
    (map-get? reporter-stats { reporter: reporter })
)

;; Get source report
(define-read-only (get-source-report (source-id (string-ascii 128)) (report-id uint))
    (map-get? source-reports { source-id: source-id, report-id: report-id })
)

;; Check if source meets credibility threshold
(define-read-only (is-source-credible (source-id (string-ascii 128)) (threshold uint))
    (match (map-get? source-registry { source-id: source-id })
        source-data (>= (get credibility-score source-data) threshold)
        false
    )
)

;; Get total number of registered sources
(define-read-only (get-total-sources)
    (var-get total-sources)
)

;; Get current assessment fee
(define-read-only (get-assessment-fee)
    (var-get assessment-fee)
)

;; Administrative functions

;; Update assessment fee (owner only)
(define-public (set-assessment-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR-NOT-AUTHORIZED))
        (var-set assessment-fee new-fee)
        (ok true)
    )
)

;; Transfer contract ownership
(define-public (transfer-ownership (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR-NOT-AUTHORIZED))
        (var-set contract-owner new-owner)
        (ok true)
    )
)

;; title: source-credibility-oracle
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

