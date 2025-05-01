;; DataNest Business Storage Contract
;; This contract enables businesses to store file references, manage access permissions,
;; and track storage allocation on the Stacks blockchain in a decentralized manner.
;; It serves as the backbone of the DataNest platform, providing secure and transparent
;; data management infrastructure for small businesses.

;; =========================================
;; Constants and Error Codes
;; =========================================

;; Error codes related to business registration and management
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-REGISTERED (err u101))
(define-constant ERR-NOT-REGISTERED (err u102))
(define-constant ERR-INVALID-TIER (err u103))

;; Error codes related to file operations
(define-constant ERR-FILE-NOT-FOUND (err u200))
(define-constant ERR-FILE-ALREADY-EXISTS (err u201))
(define-constant ERR-INSUFFICIENT-STORAGE (err u202))
(define-constant ERR-INVALID-FOLDER (err u203))
(define-constant ERR-FOLDER-NOT-FOUND (err u204))
(define-constant ERR-FOLDER-ALREADY-EXISTS (err u205))

;; Error codes related to access control
(define-constant ERR-NO-ACCESS (err u300))
(define-constant ERR-ALREADY-HAS-ACCESS (err u301))
(define-constant ERR-INVALID-PERMISSION-LEVEL (err u302))

;; Permission levels
(define-constant PERMISSION-NONE u0)
(define-constant PERMISSION-READ u1)
(define-constant PERMISSION-EDIT u2)
(define-constant PERMISSION-ADMIN u3)

;; Storage tiers (in bytes)
(define-constant TIER-BASIC u1073741824)    ;; 1GB in bytes
(define-constant TIER-STANDARD u5368709120) ;; 5GB in bytes
(define-constant TIER-PREMIUM u10737418240) ;; 10GB in bytes
(define-constant TIER-ENTERPRISE u53687091200) ;; 50GB in bytes

;; Other constants
(define-constant CONTRACT-OWNER tx-sender)

;; =========================================
;; Data Maps and Variables
;; =========================================

;; Business registry stores information about registered businesses
(define-map businesses principal 
  {
    storage-tier: uint,
    storage-used: uint,
    active: bool,
    registration-time: uint
  }
)

;; File storage maps a file ID to its metadata
(define-map files 
  { business: principal, file-id: (string-ascii 64) }
  {
    file-hash: (string-ascii 64),
    file-name: (string-ascii 256),
    file-size: uint,
    folder-id: (optional (string-ascii 64)),
    timestamp: uint,
    owner: principal
  }
)

;; Folder structure for organizing files
(define-map folders
  { business: principal, folder-id: (string-ascii 64) }
  {
    folder-name: (string-ascii 256),
    parent-folder-id: (optional (string-ascii 64)),
    created-at: uint
  }
)

;; Access permissions track who can access which files
(define-map access-permissions
  { business: principal, file-id: (string-ascii 64), user: principal }
  {
    permission-level: uint,
    granted-at: uint,
    granted-by: principal
  }
)

;; Folder permissions track who can access which folders
(define-map folder-permissions
  { business: principal, folder-id: (string-ascii 64), user: principal }
  {
    permission-level: uint,
    granted-at: uint,
    granted-by: principal
  }
)

;; Audit log for tracking file access and changes
(define-map audit-log
  { log-id: uint }
  {
    business: principal,
    file-id: (optional (string-ascii 64)),
    folder-id: (optional (string-ascii 64)),
    user: principal,
    action: (string-ascii 64),
    timestamp: uint,
    details: (optional (string-ascii 256))
  }
)

;; Counter for audit log entries
(define-data-var audit-log-counter uint u0)

;; =========================================
;; Private Functions
;; =========================================

;; Creates a new audit log entry
(define-private (create-audit-log-entry
                  (business principal)
                  (file-id (optional (string-ascii 64)))
                  (folder-id (optional (string-ascii 64)))
                  (action (string-ascii 64))
                  (details (optional (string-ascii 256))))
  (let ((log-id (var-get audit-log-counter)))
    ;; Increment the counter first
    (var-set audit-log-counter (+ log-id u1))
    ;; Create the log entry
    (map-set audit-log
      { log-id: log-id }
      {
        business: business,
        file-id: file-id,
        folder-id: folder-id,
        user: tx-sender,
        action: action,
        timestamp: block-height,
        details: details
      }
    )
    log-id
  )
)

;; Checks if a user has the required permission level for a file
(define-private (has-file-permission 
                  (business principal) 
                  (file-id (string-ascii 64)) 
                  (user principal) 
                  (required-level uint))
  (let ((permission-data (map-get? access-permissions { business: business, file-id: file-id, user: user })))
    (if (and 
          (is-some permission-data) 
          (>= (get permission-level (unwrap! permission-data false)) required-level))
      true
      ;; If not direct permission, check if user is the business owner
      (is-eq user business)
    )
  )
)

;; Checks if a user has the required permission level for a folder
(define-private (has-folder-permission 
                  (business principal) 
                  (folder-id (string-ascii 64)) 
                  (user principal) 
                  (required-level uint))
  (let ((permission-data (map-get? folder-permissions { business: business, folder-id: folder-id, user: user })))
    (if (and 
          (is-some permission-data) 
          (>= (get permission-level (unwrap! permission-data false)) required-level))
      true
      ;; If not direct permission, check if user is the business owner
      (is-eq user business)
    )
  )
)

;; Gets a business's storage tier in bytes
(define-private (get-storage-tier-bytes (tier uint))
  (match tier
    u1 TIER-BASIC
    u2 TIER-STANDARD
    u3 TIER-PREMIUM
    u4 TIER-ENTERPRISE
    TIER-BASIC
  )
)

;; Checks if a business is registered and active
(define-private (is-business-active (business principal))
  (let ((business-data (map-get? businesses business)))
    (and
      (is-some business-data)
      (get active (unwrap! business-data false))
    )
  )
)

;; =========================================
;; Read-Only Functions
;; =========================================

;; Retrieves business information
(define-read-only (get-business-info (business principal))
  (map-get? businesses business)
)

;; Retrieves file metadata
(define-read-only (get-file-info (business principal) (file-id (string-ascii 64)))
  (map-get? files { business: business, file-id: file-id })
)

;; Retrieves folder information
(define-read-only (get-folder-info (business principal) (folder-id (string-ascii 64)))
  (map-get? folders { business: business, folder-id: folder-id })
)

;; Checks if a user has access to a file and returns their permission level
(define-read-only (get-file-permission-level (business principal) (file-id (string-ascii 64)) (user principal))
  (let ((permission-data (map-get? access-permissions { business: business, file-id: file-id, user: user })))
    (if (is-some permission-data)
      (ok (get permission-level (unwrap-panic permission-data)))
      (if (is-eq user business)
        (ok PERMISSION-ADMIN)
        (ok PERMISSION-NONE)
      )
    )
  )
)

;; Retrieves remaining storage space for a business
(define-read-only (get-remaining-storage (business principal))
  (let ((business-data (map-get? businesses business)))
    (if (is-some business-data)
      (let ((data (unwrap-panic business-data)))
        (ok (- (get-storage-tier-bytes (get storage-tier data)) (get storage-used data)))
      )
      (err ERR-NOT-REGISTERED)
    )
  )
)

;; Lists files in a specific folder for a business
(define-read-only (list-files-in-folder (business principal) (folder-id (optional (string-ascii 64))))
  ;; Note: In real implementations, this would require off-chain indexing
  ;; as Clarity doesn't support iterating over maps. Here we're acknowledging
  ;; the limitation of the smart contract model.
  (ok "Files would be listed via off-chain indexing")
)

;; Gets an audit log entry
(define-read-only (get-audit-log-entry (log-id uint))
  (map-get? audit-log { log-id: log-id })
)

;; =========================================
;; Public Functions
;; =========================================

;; Registers a new business with the platform
(define-public (register-business (tier uint))
  (let ((business tx-sender))
    ;; Check if business is already registered
    (asserts! (is-none (map-get? businesses business)) ERR-ALREADY-REGISTERED)
    ;; Validate tier selection
    (asserts! (and (>= tier u1) (<= tier u4)) ERR-INVALID-TIER)
    
    ;; Create business record
    (map-set businesses business 
      {
        storage-tier: tier,
        storage-used: u0,
        active: true,
        registration-time: block-height
      }
    )
    
    ;; Log the registration
    ;; (create-audit-log-entry business none none "business-registration" (some (concat "Tier: " (int-to-ascii tier))))
    (ok true)
  )
)

;; Upgrades a business's storage tier
(define-public (upgrade-storage-tier (new-tier uint))
  (let ((business tx-sender))
    ;; Check if business exists
    (asserts! (is-business-active business) ERR-NOT-REGISTERED)
    ;; Validate tier selection
    (asserts! (and (>= new-tier u1) (<= new-tier u4)) ERR-INVALID-TIER)
    
    ;; Get current business data
    (let ((current-data (unwrap-panic (map-get? businesses business))))
      ;; Ensure new tier is actually an upgrade
      (asserts! (> new-tier (get storage-tier current-data)) ERR-INVALID-TIER)
      
      ;; Update business record
      (map-set businesses business 
        (merge current-data { storage-tier: new-tier })
      )
      
      ;; Log the upgrade
      ;; (create-audit-log-entry 
      ;;   business 
      ;;   none 
      ;;   none 
      ;;   "tier-upgrade" 
      ;;   (some (concat "New tier: " (int-to-ascii new-tier)))
      ;; )
      (ok true)
    )
  )
)

;; Stores a new file reference
(define-public (store-file 
                (file-id (string-ascii 64)) 
                (file-hash (string-ascii 64)) 
                (file-name (string-ascii 256)) 
                (file-size uint)
                (folder-id (optional (string-ascii 64))))
  (let ((business tx-sender))
    ;; Check if business is registered and active
    (asserts! (is-business-active business) ERR-NOT-REGISTERED)
    
    ;; Check if file already exists
    (asserts! (is-none (map-get? files { business: business, file-id: file-id })) ERR-FILE-ALREADY-EXISTS)
    
    ;; Validate folder if specified
    (if (is-some folder-id)
      (asserts! (is-some (map-get? folders { business: business, folder-id: (unwrap-panic folder-id) })) ERR-FOLDER-NOT-FOUND)
      true
    )
    
    ;; Check if there's enough storage space
    (let ((business-data (unwrap-panic (map-get? businesses business))))
      (let ((new-storage-used (+ (get storage-used business-data) file-size)))
        (asserts! (<= new-storage-used (get-storage-tier-bytes (get storage-tier business-data))) ERR-INSUFFICIENT-STORAGE)
        
        ;; Update business storage used
        (map-set businesses business
          (merge business-data { storage-used: new-storage-used })
        )
        
        ;; Store file metadata
        (map-set files 
          { business: business, file-id: file-id }
          {
            file-hash: file-hash,
            file-name: file-name,
            file-size: file-size,
            folder-id: folder-id,
            timestamp: block-height,
            owner: business
          }
        )
        
        ;; Log file creation
        (create-audit-log-entry 
          business 
          (some file-id) 
          folder-id 
          "file-stored" 
          (some file-name)
        )
        (ok true)
      )
    )
  )
)

;; Creates a new folder
(define-public (create-folder 
                (folder-id (string-ascii 64)) 
                (folder-name (string-ascii 256))
                (parent-folder-id (optional (string-ascii 64))))
  (let ((business tx-sender))
    ;; Check if business is registered and active
    (asserts! (is-business-active business) ERR-NOT-REGISTERED)
    
    ;; Check if folder already exists
    (asserts! (is-none (map-get? folders { business: business, folder-id: folder-id })) ERR-FOLDER-ALREADY-EXISTS)
    
    ;; Validate parent folder if specified
    (if (is-some parent-folder-id)
      (asserts! (is-some (map-get? folders { business: business, folder-id: (unwrap-panic parent-folder-id) })) ERR-FOLDER-NOT-FOUND)
      true
    )
    
    ;; Create folder
    (map-set folders
      { business: business, folder-id: folder-id }
      {
        folder-name: folder-name,
        parent-folder-id: parent-folder-id,
        created-at: block-height
      }
    )
    
    ;; Log folder creation
    (create-audit-log-entry 
      business 
      none 
      (some folder-id) 
      "folder-created" 
      (some folder-name)
    )
    (ok true)
  )
)

;; Updates an existing file
(define-public (update-file
                (file-id (string-ascii 64))
                (new-file-hash (string-ascii 64))
                (new-file-name (optional (string-ascii 256)))
                (new-file-size (optional uint))
                (new-folder-id (optional (string-ascii 64))))
  (let ((business tx-sender)
        (file-data (map-get? files { business: business, file-id: file-id })))
    
    ;; Check if file exists
    (asserts! (is-some file-data) ERR-FILE-NOT-FOUND)
    (let ((file (unwrap-panic file-data)))
      
      ;; Check permissions - must be owner or have edit access
      (asserts! (has-file-permission business file-id tx-sender PERMISSION-EDIT) ERR-NOT-AUTHORIZED)
      
      ;; Validate new folder if specified
      (if (is-some new-folder-id)
        (asserts! (is-some (map-get? folders { business: business, folder-id: (unwrap-panic new-folder-id) })) ERR-FOLDER-NOT-FOUND)
        true
      )
      
      ;; Calculate size difference for storage accounting
      (let ((size-diff (if (is-some new-file-size)
                        (- (unwrap-panic new-file-size) (get file-size file))
                        u0)))
        
        ;; Update business storage used
        (if (> size-diff u0)
          (let ((business-data (unwrap-panic (map-get? businesses business))))
            (let ((new-storage-used (+ (get storage-used business-data) size-diff)))
              ;; Check if there's enough storage space
              (asserts! (<= new-storage-used (get-storage-tier-bytes (get storage-tier business-data))) ERR-INSUFFICIENT-STORAGE)
              
              ;; Update business storage used
              (map-set businesses business
                (merge business-data { storage-used: new-storage-used })
              )
            )
          )
          true
        )
        
        ;; Update file metadata
        (map-set files 
          { business: business, file-id: file-id }
          (merge file 
            {
              file-hash: new-file-hash,
              file-name: (default-to (get file-name file) new-file-name),
              file-size: (default-to (get file-size file) new-file-size),
              folder-id: (default-to (get folder-id file) new-folder-id),
              timestamp: block-height
            }
          )
        )
        
        ;; Log file update
        ;; (create-audit-log-entry 
        ;;   business 
        ;;   (some file-id) 
        ;;   (default-to (get folder-id file) new-folder-id) 
        ;;   "file-updated" 
        ;;   (some (concat "Updated by: " (int-to-ascii tx-sender)))
        ;; )
        (ok true)
      )
    )
  )
)

;; Deletes a file
(define-public (delete-file (file-id (string-ascii 64)))
  (let ((business tx-sender)
        (file-data (map-get? files { business: business, file-id: file-id })))
    
    ;; Check if file exists
    (asserts! (is-some file-data) ERR-FILE-NOT-FOUND)
    (let ((file (unwrap-panic file-data)))
      
      ;; Check permissions - must be owner or have admin access
      (asserts! (has-file-permission business file-id tx-sender PERMISSION-ADMIN) ERR-NOT-AUTHORIZED)
      
      ;; Update business storage used
      (let ((business-data (unwrap-panic (map-get? businesses business))))
        (map-set businesses business
          (merge business-data { storage-used: (- (get storage-used business-data) (get file-size file)) })
        )
      )
      
      ;; Log file deletion before actually deleting the file
      (create-audit-log-entry 
        business 
        (some file-id) 
        (get folder-id file) 
        "file-deleted" 
        (some (concat "Deleted by: " (int-to-ascii tx-sender)))
      )
      
      ;; Delete file metadata
      (map-delete files { business: business, file-id: file-id })
      
      ;; Note: We should also clean up access permissions, but we're not iterating through them here
      ;; This would typically be handled by off-chain indexing and subsequent transactions
      
      (ok true)
    )
  )
)

;; Grants access to a file for another user
(define-public (grant-file-access 
                (file-id (string-ascii 64)) 
                (user principal) 
                (permission-level uint))
  (let ((business tx-sender))
    ;; Check if file exists
    (asserts! (is-some (map-get? files { business: business, file-id: file-id })) ERR-FILE-NOT-FOUND)
    
    ;; Validate permission level
    (asserts! (and (>= permission-level PERMISSION-READ) (<= permission-level PERMISSION-ADMIN)) ERR-INVALID-PERMISSION-LEVEL)
    
    ;; Check if access already exists
    (asserts! (is-none (map-get? access-permissions { business: business, file-id: file-id, user: user })) ERR-ALREADY-HAS-ACCESS)
    
    ;; Grant access
    (map-set access-permissions
      { business: business, file-id: file-id, user: user }
      {
        permission-level: permission-level,
        granted-at: block-height,
        granted-by: tx-sender
      }
    )
    
    ;; Log access grant
    (create-audit-log-entry 
      business 
      (some file-id) 
      none 
      "access-granted" 
      (some (concat "To: " (int-to-ascii user)))
    )
    (ok true)
  )
)

;; Revokes access to a file
(define-public (revoke-file-access (file-id (string-ascii 64)) (user principal))
  (let ((business tx-sender))
    ;; Check if file exists
    (asserts! (is-some (map-get? files { business: business, file-id: file-id })) ERR-FILE-NOT-FOUND)
    
    ;; Check if access exists
    (asserts! (is-some (map-get? access-permissions { business: business, file-id: file-id, user: user })) ERR-NO-ACCESS)
    
    ;; Revoke access
    (map-delete access-permissions { business: business, file-id: file-id, user: user })
    
    ;; Log access revocation
    (create-audit-log-entry 
      business 
      (some file-id) 
      none 
      "access-revoked" 
      (some (concat "From: " (int-to-ascii user)))
    )
    (ok true)
  )
)

;; Records file access in the audit log
(define-public (record-file-access (business principal) (file-id (string-ascii 64)))
  ;; Check if file exists
  (asserts! (is-some (map-get? files { business: business, file-id: file-id })) ERR-FILE-NOT-FOUND)
  
  ;; Check if user has at least read permission
  (asserts! (has-file-permission business file-id tx-sender PERMISSION-READ) ERR-NO-ACCESS)
  
  ;; Log the access
  (create-audit-log-entry 
    business 
    (some file-id) 
    none 
    "file-accessed" 
    (some (concat "By: " (int-to-ascii tx-sender)))
  )
  (ok true)
)

;; Transfers file ownership to another business
(define-public (transfer-file-ownership (file-id (string-ascii 64)) (new-owner principal))
  (let ((business tx-sender)
        (file-data (map-get? files { business: business, file-id: file-id })))
    
    ;; Check if file exists
    (asserts! (is-some file-data) ERR-FILE-NOT-FOUND)
    (let ((file (unwrap-panic file-data)))
      
      ;; Ensure new owner is registered
      (asserts! (is-business-active new-owner) ERR-NOT-REGISTERED)
      
      ;; Check permissions - must be owner
      (asserts! (is-eq tx-sender business) ERR-NOT-AUTHORIZED)
      
      ;; Check if new owner has enough storage
      (let ((new-owner-data (unwrap-panic (map-get? businesses new-owner))))
        (let ((new-storage-used (+ (get storage-used new-owner-data) (get file-size file))))
          (asserts! (<= new-storage-used (get-storage-tier-bytes (get storage-tier new-owner-data))) ERR-INSUFFICIENT-STORAGE)
          
          ;; Update new owner's storage used
          (map-set businesses new-owner
            (merge new-owner-data { storage-used: new-storage-used })
          )
          
          ;; Update original owner's storage used
          (let ((owner-data (unwrap-panic (map-get? businesses business))))
            (map-set businesses business
              (merge owner-data { storage-used: (- (get storage-used owner-data) (get file-size file)) })
            )
          )
          
          ;; Transfer file ownership by creating a new entry for the new owner
          (map-set files 
            { business: new-owner, file-id: file-id }
            (merge file 
              {
                owner: new-owner,
                timestamp: block-height,
                folder-id: none ;; Reset folder since folder structure is per-business
              }
            )
          )
          
          ;; Delete original file entry
          (map-delete files { business: business, file-id: file-id })
          
          ;; Log the transfer for both parties
          (create-audit-log-entry 
            business 
            (some file-id) 
            none 
            "file-transferred-out" 
            (some (concat "To: " (int-to-ascii new-owner)))
          )
          
          (create-audit-log-entry 
            new-owner 
            (some file-id) 
            none 
            "file-transferred-in" 
            (some (concat "From: " (int-to-ascii business)))
          )
          
          (ok true)
        )
      )
    )
  )
)

;; Deactivates a business account
(define-public (deactivate-business)
  (let ((business tx-sender)
        (business-data (map-get? businesses business)))
    
    ;; Check if business exists
    (asserts! (is-some business-data) ERR-NOT-REGISTERED)
    
    ;; Deactivate the business
    (map-set businesses business
      (merge (unwrap-panic business-data) { active: false })
    )
    
    ;; Log deactivation
    (create-audit-log-entry 
      business 
      none 
      none 
      "business-deactivated" 
      none
    )
    (ok true)
  )
)

;; Reactivates a deactivated business account
(define-public (reactivate-business)
  (let ((business tx-sender)
        (business-data (map-get? businesses business)))
    
    ;; Check if business exists
    (asserts! (is-some business-data) ERR-NOT-REGISTERED)
    
    ;; Reactivate the business
    (map-set businesses business
      (merge (unwrap-panic business-data) { active: true })
    )
    
    ;; Log reactivation
    (create-audit-log-entry 
      business 
      none 
      none 
      "business-reactivated" 
      none
    )
    (ok true)
  )
)