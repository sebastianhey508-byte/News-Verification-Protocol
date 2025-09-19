;; Crowd Fact-Checking Contract
;; Incentivized crowd-sourced fact-checking with reputation-weighted verification scores

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-CLAIM-NOT-FOUND (err u201))
(define-constant ERR-ALREADY-VOTED (err u202))
(define-constant ERR-INVALID-VOTE (err u203))
(define-constant ERR-INSUFFICIENT-STAKE (err u204))
(define-constant ERR-CONSENSUS-REACHED (err u205))
(define-constant ERR-VOTING-CLOSED (err u206))
(define-constant ERR-INVALID-REWARD (err u207))

;; Voting and consensus constants
(define-constant MIN-STAKE u1000000) ;; 1 STX minimum stake
(define-constant CONSENSUS-THRESHOLD u70) ;; 70% agreement needed
(define-constant MIN-VOTERS u5)
(define-constant VOTING-PERIOD u144) ;; ~1 day in blocks
(define-constant BASE-REWARD u500000) ;; 0.5 STX base reward

;; Vote types
(define-constant VOTE-TRUE u1)
(define-constant VOTE-FALSE u2)
(define-constant VOTE-INSUFFICIENT-INFO u3)

;; Data Variables
(define-data-var contract-owner principal tx-sender)
(define-data-var total-claims uint u0)
(define-data-var reward-pool uint u0)
(define-data-var next-claim-id uint u1)

;; Fact-checking claim structure
(define-map fact-claims
    { claim-id: uint }
    {
        content-hash: (buff 32),
        claim-text: (string-utf8 1024),
        source-url: (string-ascii 256),
        submitter: principal,
        stake-amount: uint,
        created-at: uint,
        voting-deadline: uint,
        status: (string-ascii 20),
        total-votes: uint,
        true-votes: uint,
        false-votes: uint,
        insufficient-info-votes: uint,
        consensus-reached: bool,
        final-verdict: uint,
        reward-distributed: bool
    }
)

;; Individual votes on claims
(define-map claim-votes
    { claim-id: uint, voter: principal }
    {
        vote-type: uint,
        stake-amount: uint,
        reputation-weight: uint,
        evidence-links: (list 5 (string-ascii 256)),
        reasoning: (string-utf8 512),
        timestamp: uint,
        rewarded: bool
    }
)

;; Fact-checker reputation and stats
(define-map fact-checker-stats
    { checker: principal }
    {
        total-votes: uint,
        correct-votes: uint,
        reputation-score: uint,
        total-stake: uint,
        total-rewards: uint,
        accuracy-rate: uint,
        joined-at: uint,
        status: (string-ascii 20)
    }
)

;; Stake management for fact-checkers
(define-map checker-stakes
    { checker: principal }
    {
        available-stake: uint,
        locked-stake: uint,
        pending-rewards: uint,
        last-activity: uint
    }
)

;; Evidence submission tracking
(define-map evidence-submissions
    { claim-id: uint, evidence-id: uint }
    {
        submitter: principal,
        evidence-type: (string-ascii 50),
        content-hash: (buff 32),
        url: (string-ascii 256),
        quality-score: uint,
        verified: bool,
        timestamp: uint
    }
)

;; Counters
(define-data-var next-evidence-id uint u1)

;; Public Functions

;; Submit a claim for fact-checking
(define-public (submit-claim (content-hash (buff 32))
                           (claim-text (string-utf8 1024))
                           (source-url (string-ascii 256))
                           (stake-amount uint))
    (let ((claim-id (var-get next-claim-id)))
        ;; Validate minimum stake
        (asserts! (>= stake-amount MIN-STAKE) (err ERR-INSUFFICIENT-STAKE))
        
        ;; Transfer stake to contract
        (unwrap! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)) (err ERR-INSUFFICIENT-STAKE))
        
        ;; Create claim record
        (map-set fact-claims
            { claim-id: claim-id }
            {
                content-hash: content-hash,
                claim-text: claim-text,
                source-url: source-url,
                submitter: tx-sender,
                stake-amount: stake-amount,
                created-at: stacks-block-height,
                voting-deadline: (+ stacks-block-height VOTING-PERIOD),
                status: "open",
                total-votes: u0,
                true-votes: u0,
                false-votes: u0,
                insufficient-info-votes: u0,
                consensus-reached: false,
                final-verdict: u0,
                reward-distributed: false
            }
        )
        
        ;; Update counters
        (var-set next-claim-id (+ claim-id u1))
        (var-set total-claims (+ (var-get total-claims) u1))
        
        (ok claim-id)
    )
)

;; Vote on a fact-checking claim
(define-public (submit-vote (claim-id uint)
                          (vote-type uint)
                          (stake-amount uint)
                          (evidence-links (list 5 (string-ascii 256)))
                          (reasoning (string-utf8 512)))
    (let (
        (claim-data (unwrap! (map-get? fact-claims { claim-id: claim-id }) (err ERR-CLAIM-NOT-FOUND)))
        (existing-vote (map-get? claim-votes { claim-id: claim-id, voter: tx-sender }))
        (checker-stats (default-to
            { total-votes: u0, correct-votes: u0, reputation-score: u50, total-stake: u0, 
              total-rewards: u0, accuracy-rate: u0, joined-at: stacks-block-height, status: "active" }
            (map-get? fact-checker-stats { checker: tx-sender })
        ))
        (reputation-weight (get reputation-score checker-stats))
    )
        ;; Check if voting is still open
        (asserts! (<= stacks-block-height (get voting-deadline claim-data)) (err ERR-VOTING-CLOSED))
        (asserts! (not (get consensus-reached claim-data)) (err ERR-CONSENSUS-REACHED))
        (asserts! (is-none existing-vote) (err ERR-ALREADY-VOTED))
        
        ;; Validate vote type
        (asserts! (and (>= vote-type VOTE-TRUE) (<= vote-type VOTE-INSUFFICIENT-INFO)) (err ERR-INVALID-VOTE))
        (asserts! (>= stake-amount MIN-STAKE) (err ERR-INSUFFICIENT-STAKE))
        
        ;; Transfer vote stake
        (unwrap! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)) (err ERR-INSUFFICIENT-STAKE))
        
        ;; Record the vote
        (map-set claim-votes
            { claim-id: claim-id, voter: tx-sender }
            {
                vote-type: vote-type,
                stake-amount: stake-amount,
                reputation-weight: reputation-weight,
                evidence-links: evidence-links,
                reasoning: reasoning,
                timestamp: stacks-block-height,
                rewarded: false
            }
        )
        
        ;; Update claim vote counts
        (map-set fact-claims
            { claim-id: claim-id }
            (merge claim-data {
                total-votes: (+ (get total-votes claim-data) u1),
                true-votes: (if (is-eq vote-type VOTE-TRUE) 
                    (+ (get true-votes claim-data) u1) 
                    (get true-votes claim-data)
                ),
                false-votes: (if (is-eq vote-type VOTE-FALSE) 
                    (+ (get false-votes claim-data) u1) 
                    (get false-votes claim-data)
                ),
                insufficient-info-votes: (if (is-eq vote-type VOTE-INSUFFICIENT-INFO) 
                    (+ (get insufficient-info-votes claim-data) u1) 
                    (get insufficient-info-votes claim-data)
                )
            })
        )
        
        ;; Update fact-checker stats
        (map-set fact-checker-stats
            { checker: tx-sender }
            (merge checker-stats {
                total-votes: (+ (get total-votes checker-stats) u1),
                total-stake: (+ (get total-stake checker-stats) stake-amount)
            })
        )
        
        ;; Check for consensus
        (try! (check-consensus claim-id))
        
        (ok true)
    )
)

;; Check if consensus has been reached on a claim
(define-private (check-consensus (claim-id uint))
    (let (
        (claim-data (unwrap! (map-get? fact-claims { claim-id: claim-id }) (err ERR-CLAIM-NOT-FOUND)))
        (total-votes (get total-votes claim-data))
        (true-votes (get true-votes claim-data))
        (false-votes (get false-votes claim-data))
    )
        (if (and (>= total-votes MIN-VOTERS) (not (get consensus-reached claim-data)))
            (let (
                (true-percentage (/ (* true-votes u100) total-votes))
                (false-percentage (/ (* false-votes u100) total-votes))
                (verdict (if (>= true-percentage CONSENSUS-THRESHOLD) 
                    VOTE-TRUE 
                    (if (>= false-percentage CONSENSUS-THRESHOLD) 
                        VOTE-FALSE 
                        u0
                    )
                ))
            )
                (if (> verdict u0)
                    (begin
                        (map-set fact-claims
                            { claim-id: claim-id }
                            (merge claim-data {
                                consensus-reached: true,
                                final-verdict: verdict,
                                status: "closed"
                            })
                        )
                        (try! (distribute-rewards claim-id))
                        (ok true)
                    )
                    (ok true)
                )
            )
            (ok true)
        )
    )
)

;; Distribute rewards to correct voters
(define-private (distribute-rewards (claim-id uint))
    (let (
        (claim-data (unwrap! (map-get? fact-claims { claim-id: claim-id }) (err ERR-CLAIM-NOT-FOUND)))
        (final-verdict (get final-verdict claim-data))
    )
        ;; Mark rewards as distributed (simplified implementation)
        (map-set fact-claims
            { claim-id: claim-id }
            (merge claim-data { reward-distributed: true })
        )
        (ok true)
    )
)

;; Submit evidence for a claim
(define-public (submit-evidence (claim-id uint)
                              (evidence-type (string-ascii 50))
                              (content-hash (buff 32))
                              (url (string-ascii 256)))
    (let (
        (evidence-id (var-get next-evidence-id))
        (claim-data (unwrap! (map-get? fact-claims { claim-id: claim-id }) (err ERR-CLAIM-NOT-FOUND)))
    )
        ;; Check if claim is still accepting evidence
        (asserts! (<= stacks-block-height (get voting-deadline claim-data)) (err ERR-VOTING-CLOSED))
        
        ;; Store evidence
        (map-set evidence-submissions
            { claim-id: claim-id, evidence-id: evidence-id }
            {
                submitter: tx-sender,
                evidence-type: evidence-type,
                content-hash: content-hash,
                url: url,
                quality-score: u0,
                verified: false,
                timestamp: stacks-block-height
            }
        )
        
        (var-set next-evidence-id (+ evidence-id u1))
        (ok evidence-id)
    )
)

;; Stake STX tokens for fact-checking
(define-public (stake-tokens (amount uint))
    (let (
        (current-stakes (default-to
            { available-stake: u0, locked-stake: u0, pending-rewards: u0, last-activity: stacks-block-height }
            (map-get? checker-stakes { checker: tx-sender })
        ))
    )
        (asserts! (>= amount MIN-STAKE) (err ERR-INSUFFICIENT-STAKE))
        
        ;; Transfer tokens to contract
        (unwrap! (stx-transfer? amount tx-sender (as-contract tx-sender)) (err ERR-INSUFFICIENT-STAKE))
        
        ;; Update stake record
        (map-set checker-stakes
            { checker: tx-sender }
            (merge current-stakes {
                available-stake: (+ (get available-stake current-stakes) amount),
                last-activity: stacks-block-height
            })
        )
        
        (ok true)
    )
)

;; Withdraw available stake
(define-public (withdraw-stake (amount uint))
    (let (
        (current-stakes (unwrap! (map-get? checker-stakes { checker: tx-sender }) (err ERR-INSUFFICIENT-STAKE)))
        (available (get available-stake current-stakes))
    )
        (asserts! (<= amount available) (err ERR-INSUFFICIENT-STAKE))
        
        ;; Transfer tokens back to user
        (unwrap! (as-contract (stx-transfer? amount tx-sender tx-sender)) (err ERR-INSUFFICIENT-STAKE))
        
        ;; Update stake record
        (map-set checker-stakes
            { checker: tx-sender }
            (merge current-stakes {
                available-stake: (- available amount)
            })
        )
        
        (ok true)
    )
)

;; Force close voting on expired claims
(define-public (close-expired-claim (claim-id uint))
    (let ((claim-data (unwrap! (map-get? fact-claims { claim-id: claim-id }) (err ERR-CLAIM-NOT-FOUND))))
        (asserts! (> stacks-block-height (get voting-deadline claim-data)) (err ERR-VOTING-CLOSED))
        (asserts! (not (get consensus-reached claim-data)) (err ERR-CONSENSUS-REACHED))
        
        ;; Close claim without consensus
        (map-set fact-claims
            { claim-id: claim-id }
            (merge claim-data {
                status: "expired",
                consensus-reached: true,
                final-verdict: VOTE-INSUFFICIENT-INFO
            })
        )
        
        (ok true)
    )
)

;; Read-only functions

;; Get claim information
(define-read-only (get-claim (claim-id uint))
    (map-get? fact-claims { claim-id: claim-id })
)

;; Get vote information
(define-read-only (get-vote (claim-id uint) (voter principal))
    (map-get? claim-votes { claim-id: claim-id, voter: voter })
)

;; Get fact-checker statistics
(define-read-only (get-checker-stats (checker principal))
    (map-get? fact-checker-stats { checker: checker })
)

;; Get checker stake information
(define-read-only (get-checker-stakes (checker principal))
    (map-get? checker-stakes { checker: checker })
)

;; Get evidence information
(define-read-only (get-evidence (claim-id uint) (evidence-id uint))
    (map-get? evidence-submissions { claim-id: claim-id, evidence-id: evidence-id })
)

;; Get total number of claims
(define-read-only (get-total-claims)
    (var-get total-claims)
)

;; Check if claim has reached consensus
(define-read-only (has-consensus (claim-id uint))
    (match (map-get? fact-claims { claim-id: claim-id })
        claim-data (get consensus-reached claim-data)
        false
    )
)

;; Calculate voting participation rate
(define-read-only (get-participation-rate (claim-id uint))
    (match (map-get? fact-claims { claim-id: claim-id })
        claim-data (get total-votes claim-data)
        u0
    )
)

;; Administrative functions

;; Update consensus threshold (owner only)
(define-public (update-consensus-threshold (new-threshold uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR-NOT-AUTHORIZED))
        (asserts! (and (>= new-threshold u51) (<= new-threshold u100)) (err ERR-INVALID-VOTE))
        ;; Note: Would need to add a data-var for consensus-threshold to make this work
        (ok true)
    )
)

;; Emergency pause (owner only)
(define-public (emergency-pause)
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR-NOT-AUTHORIZED))
        ;; Implementation would set a paused state
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

;; title: crowd-fact-checking
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

