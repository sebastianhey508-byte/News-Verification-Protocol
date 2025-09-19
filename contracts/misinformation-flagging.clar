;; Misinformation Flagging Contract
;; Automated detection and community flagging of misinformation with AI and consensus

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-CONTENT-NOT-FOUND (err u301))
(define-constant ERR-ALREADY-FLAGGED (err u302))
(define-constant ERR-INVALID-SEVERITY (err u303))
(define-constant ERR-INSUFFICIENT-REPUTATION (err u304))
(define-constant ERR-CONTENT-ALREADY-VERIFIED (err u305))
(define-constant ERR-FLAG-NOT-FOUND (err u306))
(define-constant ERR-INVALID-CONFIDENCE (err u307))

;; Severity levels
(define-constant SEVERITY-LOW u1)
(define-constant SEVERITY-MEDIUM u2)
(define-constant SEVERITY-HIGH u3)
(define-constant SEVERITY-CRITICAL u4)

;; Flag types
(define-constant FLAG-MISLEADING u1)
(define-constant FLAG-FALSE-INFO u2)
(define-constant FLAG-MANIPULATED-MEDIA u3)
(define-constant FLAG-CONSPIRACY-THEORY u4)
(define-constant FLAG-HATE-SPEECH u5)
(define-constant FLAG-SPAM u6)

;; AI confidence thresholds
(define-constant MIN-AI-CONFIDENCE u60)
(define-constant HIGH-CONFIDENCE-THRESHOLD u85)
(define-constant MIN-FLAGGER-REPUTATION u25)

;; Consensus requirements
(define-constant MIN-VALIDATORS u3)
(define-constant CONSENSUS-THRESHOLD u66) ;; 66% agreement
(define-constant VALIDATION-PERIOD u1008) ;; ~1 week in blocks

;; Data Variables
(define-data-var contract-owner principal tx-sender)
(define-data-var total-content uint u0)
(define-data-var total-flags uint u0)
(define-data-var next-content-id uint u1)
(define-data-var next-flag-id uint u1)
(define-data-var ai-oracle-address principal tx-sender) ;; Placeholder for AI oracle

;; Content registry for tracking all flaggable content
(define-map content-registry
    { content-id: uint }
    {
        content-hash: (buff 32),
        content-url: (string-ascii 512),
        content-type: (string-ascii 50),
        submitter: principal,
        timestamp: uint,
        total-flags: uint,
        verified-status: (string-ascii 20),
        ai-analysis: {
            confidence: uint,
            classification: uint,
            risk-score: uint,
            analyzed: bool
        },
        community-consensus: {
            total-votes: uint,
            misinformation-votes: uint,
            legitimate-votes: uint,
            consensus-reached: bool,
            final-verdict: uint
        }
    }
)

;; Individual flags submitted by community members
(define-map misinformation-flags
    { flag-id: uint }
    {
        content-id: uint,
        flagger: principal,
        flag-type: uint,
        severity: uint,
        description: (string-utf8 512),
        evidence-links: (list 3 (string-ascii 256)),
        confidence-score: uint,
        timestamp: uint,
        validated: bool,
        validator-count: uint,
        support-votes: uint,
        dispute-votes: uint
    }
)

;; Flag validation by trusted community members
(define-map flag-validations
    { flag-id: uint, validator: principal }
    {
        supports-flag: bool,
        confidence: uint,
        reasoning: (string-utf8 256),
        validator-reputation: uint,
        timestamp: uint
    }
)

;; Community member reputation for flagging
(define-map flagger-reputation
    { flagger: principal }
    {
        total-flags: uint,
        accurate-flags: uint,
        false-positives: uint,
        reputation-score: uint,
        specialization: (string-ascii 50),
        trust-level: uint,
        joined-at: uint,
        last-activity: uint
    }
)

;; AI analysis results for content
(define-map ai-analysis-results
    { content-id: uint, analysis-id: uint }
    {
        model-version: (string-ascii 20),
        confidence-score: uint,
        predicted-classification: uint,
        risk-indicators: (list 5 (string-ascii 100)),
        feature-scores: {
            sentiment: uint,
            factuality: uint,
            source-reliability: uint,
            emotional-manipulation: uint
        },
        timestamp: uint
    }
)

;; Rapid response for viral misinformation
(define-map rapid-response-queue
    { content-id: uint }
    {
        priority-level: uint,
        viral-score: uint,
        reach-estimate: uint,
        response-deadline: uint,
        assigned-reviewers: (list 3 principal),
        status: (string-ascii 20),
        created-at: uint
    }
)

;; Counters
(define-data-var next-analysis-id uint u1)

;; Public Functions

;; Register content for monitoring
(define-public (register-content (content-hash (buff 32))
                                (content-url (string-ascii 512))
                                (content-type (string-ascii 50)))
    (let ((content-id (var-get next-content-id)))
        ;; Register new content
        (map-set content-registry
            { content-id: content-id }
            {
                content-hash: content-hash,
                content-url: content-url,
                content-type: content-type,
                submitter: tx-sender,
                timestamp: stacks-block-height,
                total-flags: u0,
                verified-status: "pending",
                ai-analysis: {
                    confidence: u0,
                    classification: u0,
                    risk-score: u0,
                    analyzed: false
                },
                community-consensus: {
                    total-votes: u0,
                    misinformation-votes: u0,
                    legitimate-votes: u0,
                    consensus-reached: false,
                    final-verdict: u0
                }
            }
        )
        
        ;; Update counters
        (var-set next-content-id (+ content-id u1))
        (var-set total-content (+ (var-get total-content) u1))
        
        ;; Request AI analysis
        (try! (request-ai-analysis content-id))
        
        (ok content-id)
    )
)

;; Submit misinformation flag
(define-public (submit-flag (content-id uint)
                          (flag-type uint)
                          (severity uint)
                          (description (string-utf8 512))
                          (evidence-links (list 3 (string-ascii 256)))
                          (confidence-score uint))
    (let (
        (flag-id (var-get next-flag-id))
        (content-data (unwrap! (map-get? content-registry { content-id: content-id }) (err ERR-CONTENT-NOT-FOUND)))
        (flagger-stats (default-to
            { total-flags: u0, accurate-flags: u0, false-positives: u0, reputation-score: u50,
              specialization: "general", trust-level: u1, joined-at: stacks-block-height, last-activity: stacks-block-height }
            (map-get? flagger-reputation { flagger: tx-sender })
        ))
    )
        ;; Validate inputs
        (asserts! (and (>= flag-type FLAG-MISLEADING) (<= flag-type FLAG-SPAM)) (err ERR-INVALID-SEVERITY))
        (asserts! (and (>= severity SEVERITY-LOW) (<= severity SEVERITY-CRITICAL)) (err ERR-INVALID-SEVERITY))
        (asserts! (and (>= confidence-score u1) (<= confidence-score u100)) (err ERR-INVALID-CONFIDENCE))
        (asserts! (>= (get reputation-score flagger-stats) MIN-FLAGGER-REPUTATION) (err ERR-INSUFFICIENT-REPUTATION))
        
        ;; Check if already verified as legitimate
        (asserts! (not (is-eq (get verified-status content-data) "legitimate")) (err ERR-CONTENT-ALREADY-VERIFIED))
        
        ;; Create flag record
        (map-set misinformation-flags
            { flag-id: flag-id }
            {
                content-id: content-id,
                flagger: tx-sender,
                flag-type: flag-type,
                severity: severity,
                description: description,
                evidence-links: evidence-links,
                confidence-score: confidence-score,
                timestamp: stacks-block-height,
                validated: false,
                validator-count: u0,
                support-votes: u0,
                dispute-votes: u0
            }
        )
        
        ;; Update content flag count
        (map-set content-registry
            { content-id: content-id }
            (merge content-data { total-flags: (+ (get total-flags content-data) u1) })
        )
        
        ;; Update flagger stats
        (map-set flagger-reputation
            { flagger: tx-sender }
            (merge flagger-stats {
                total-flags: (+ (get total-flags flagger-stats) u1),
                last-activity: stacks-block-height
            })
        )
        
        ;; Update counters
        (var-set next-flag-id (+ flag-id u1))
        (var-set total-flags (+ (var-get total-flags) u1))
        
        ;; Check if needs rapid response
        (if (is-eq severity SEVERITY-CRITICAL)
            (begin
                (unwrap! (queue-rapid-response content-id) (err ERR-INVALID-SEVERITY))
                (ok flag-id)
            )
            (ok flag-id)
        )
    )
)

;; Validate a flag (community consensus)
(define-public (validate-flag (flag-id uint)
                             (supports-flag bool)
                             (confidence uint)
                             (reasoning (string-utf8 256)))
    (let (
        (flag-data (unwrap! (map-get? misinformation-flags { flag-id: flag-id }) (err ERR-FLAG-NOT-FOUND)))
        (existing-validation (map-get? flag-validations { flag-id: flag-id, validator: tx-sender }))
        (validator-rep (default-to
            { reputation-score: u50, trust-level: u1 }
            (map-get? flagger-reputation { flagger: tx-sender })
        ))
    )
        ;; Prevent double validation
        (asserts! (is-none existing-validation) (err ERR-ALREADY-FLAGGED))
        (asserts! (and (>= confidence u1) (<= confidence u100)) (err ERR-INVALID-CONFIDENCE))
        
        ;; Record validation
        (map-set flag-validations
            { flag-id: flag-id, validator: tx-sender }
            {
                supports-flag: supports-flag,
                confidence: confidence,
                reasoning: reasoning,
                validator-reputation: (get reputation-score validator-rep),
                timestamp: stacks-block-height
            }
        )
        
        ;; Update flag vote counts
        (map-set misinformation-flags
            { flag-id: flag-id }
            (merge flag-data {
                validator-count: (+ (get validator-count flag-data) u1),
                support-votes: (if supports-flag 
                    (+ (get support-votes flag-data) u1)
                    (get support-votes flag-data)
                ),
                dispute-votes: (if supports-flag 
                    (get dispute-votes flag-data)
                    (+ (get dispute-votes flag-data) u1)
                )
            })
        )
        
        ;; Check if consensus reached
        (try! (check-flag-consensus flag-id))
        
        (ok true)
    )
)

;; Check if flag validation consensus is reached
(define-private (check-flag-consensus (flag-id uint))
    (let (
        (flag-data (unwrap! (map-get? misinformation-flags { flag-id: flag-id }) (err ERR-FLAG-NOT-FOUND)))
        (total-validations (get validator-count flag-data))
        (support-votes (get support-votes flag-data))
    )
        (if (and (>= total-validations MIN-VALIDATORS) (not (get validated flag-data)))
            (let ((support-percentage (/ (* support-votes u100) total-validations)))
                (if (>= support-percentage CONSENSUS-THRESHOLD)
                    (begin
                        ;; Mark flag as validated
                        (map-set misinformation-flags
                            { flag-id: flag-id }
                            (merge flag-data { validated: true })
                        )
                        ;; Update content status
                        (try! (update-content-status (get content-id flag-data)))
                        (ok true)
                    )
                    (ok true)
                )
            )
            (ok true)
        )
    )
)

;; Update content misinformation status
(define-private (update-content-status (content-id uint))
    (let ((content-data (unwrap! (map-get? content-registry { content-id: content-id }) (err ERR-CONTENT-NOT-FOUND))))
        ;; Calculate overall risk based on flags and AI analysis
        (map-set content-registry
            { content-id: content-id }
            (merge content-data { verified-status: "flagged" })
        )
        (ok true)
    )
)

;; Request AI analysis for content
(define-private (request-ai-analysis (content-id uint))
    (let ((analysis-id (var-get next-analysis-id)))
        ;; Simulate AI analysis request (in real implementation, would call external AI service)
        (map-set ai-analysis-results
            { content-id: content-id, analysis-id: analysis-id }
            {
                model-version: "v1.0",
                confidence-score: u75, ;; Placeholder
                predicted-classification: u2, ;; Placeholder
                risk-indicators: (list "high-emotion" "unverified-claims" "biased-language"),
                feature-scores: {
                    sentiment: u65,
                    factuality: u30,
                    source-reliability: u45,
                    emotional-manipulation: u80
                },
                timestamp: stacks-block-height
            }
        )
        
        ;; Update content with AI results
        (let ((content-data (unwrap! (map-get? content-registry { content-id: content-id }) (err ERR-CONTENT-NOT-FOUND))))
            (map-set content-registry
                { content-id: content-id }
                (merge content-data {
                    ai-analysis: {
                        confidence: u75,
                        classification: u2,
                        risk-score: u80,
                        analyzed: true
                    }
                })
            )
        )
        
        (var-set next-analysis-id (+ analysis-id u1))
        (ok true)
    )
)

;; Queue content for rapid response
(define-private (queue-rapid-response (content-id uint))
    (let ((viral-score (calculate-viral-score content-id)))
        (map-set rapid-response-queue
            { content-id: content-id }
            {
                priority-level: SEVERITY-CRITICAL,
                viral-score: viral-score,
                reach-estimate: (* viral-score u1000), ;; Simplified calculation
                response-deadline: (+ stacks-block-height u24), ;; 4 hours
                assigned-reviewers: (list tx-sender tx-sender tx-sender), ;; Placeholder
                status: "urgent",
                created-at: stacks-block-height
            }
        )
        (ok true)
    )
)

;; Calculate viral score (simplified)
(define-private (calculate-viral-score (content-id uint))
    ;; Simplified viral score calculation
    u50 ;; Placeholder
)

;; Bulk flag content (for automated systems)
(define-public (bulk-flag-content (content-ids (list 10 uint))
                                 (flag-type uint)
                                 (severity uint)
                                 (description (string-utf8 512)))
    (begin
        (asserts! (is-eq tx-sender (var-get ai-oracle-address)) (err ERR-NOT-AUTHORIZED))
        ;; Process each content ID (simplified implementation)
        (ok (len content-ids))
    )
)

;; Read-only functions

;; Get content information
(define-read-only (get-content (content-id uint))
    (map-get? content-registry { content-id: content-id })
)

;; Get flag information
(define-read-only (get-flag (flag-id uint))
    (map-get? misinformation-flags { flag-id: flag-id })
)

;; Get flagger reputation
(define-read-only (get-flagger-reputation (flagger principal))
    (map-get? flagger-reputation { flagger: flagger })
)

;; Get flag validation
(define-read-only (get-flag-validation (flag-id uint) (validator principal))
    (map-get? flag-validations { flag-id: flag-id, validator: validator })
)

;; Get AI analysis
(define-read-only (get-ai-analysis (content-id uint) (analysis-id uint))
    (map-get? ai-analysis-results { content-id: content-id, analysis-id: analysis-id })
)

;; Check if content is flagged as misinformation
(define-read-only (is-flagged-content (content-id uint))
    (match (map-get? content-registry { content-id: content-id })
        content-data (> (get total-flags content-data) u0)
        false
    )
)

;; Get content risk score
(define-read-only (get-content-risk-score (content-id uint))
    (match (map-get? content-registry { content-id: content-id })
        content-data (get risk-score (get ai-analysis content-data))
        u0
    )
)

;; Get total statistics
(define-read-only (get-platform-stats)
    {
        total-content: (var-get total-content),
        total-flags: (var-get total-flags),
        ai-oracle: (var-get ai-oracle-address)
    }
)

;; Administrative functions

;; Update AI oracle address
(define-public (set-ai-oracle (new-oracle principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR-NOT-AUTHORIZED))
        (var-set ai-oracle-address new-oracle)
        (ok true)
    )
)

;; Update flagger reputation (admin override)
(define-public (update-flagger-reputation (flagger principal) (new-score uint))
    (let ((current-rep (unwrap! (map-get? flagger-reputation { flagger: flagger }) (err ERR-NOT-AUTHORIZED))))
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR-NOT-AUTHORIZED))
        (asserts! (<= new-score u100) (err ERR-INVALID-CONFIDENCE))
        
        (map-set flagger-reputation
            { flagger: flagger }
            (merge current-rep { reputation-score: new-score })
        )
        (ok true)
    )
)

;; Emergency content removal
(define-public (emergency-remove-content (content-id uint))
    (let ((content-data (unwrap! (map-get? content-registry { content-id: content-id }) (err ERR-CONTENT-NOT-FOUND))))
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR-NOT-AUTHORIZED))
        
        (map-set content-registry
            { content-id: content-id }
            (merge content-data { verified-status: "removed" })
        )
        (ok true)
    )
)

;; Transfer ownership
(define-public (transfer-ownership (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR-NOT-AUTHORIZED))
        (var-set contract-owner new-owner)
        (ok true)
    )
)

;; title: misinformation-flagging
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

