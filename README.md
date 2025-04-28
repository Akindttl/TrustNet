# TrustNet: Decentralized Reputation System Smart Contract

## Overview

This Clarity smart contract implements a decentralized reputation system, enabling users to build and maintain a verifiable reputation through attestations from other users. The system allows for both positive and negative feedback, categorized attestations, and a reputation decay mechanism to ensure that the reputation score reflects more recent behavior.

This contract aims to provide a transparent and immutable way to assess the trustworthiness and standing of users within a decentralized ecosystem. It can be integrated into various applications requiring user reputation, such as marketplaces, governance systems, and social platforms.

## Key Features

* **User Reputation Tracking:** Maintains a reputation score for each user, along with counts of positive and negative attestations and the last update timestamp.
* **Attestations:** Allows users to make attestations (positive or negative) about other users, including a category and a comment.
* **Categorized Feedback:** Supports categorization of attestations, allowing for nuanced reputation assessment based on different aspects of a user's behavior.
* **Attestation Cooldown:** Prevents users from spamming attestations about the same user by enforcing a 24-hour cooldown period.
* **Self-Attestation Prevention:** Disallows users from making attestations about themselves.
* **Reputation Initialization:** Automatically initializes a user's reputation when they receive their first attestation.
* **Reputation Decay:** Implements a decay mechanism that gradually reduces the impact of older attestations, ensuring that the reputation score reflects more recent interactions. The decay starts after 30 days and has a base monthly decay rate of 5%, capped at a maximum decay of 75%.
* **Administrative Category Management:** Allows the contract owner to add new categories for attestations.
* **Read-Only Functions:** Provides functions to query user reputation, specific attestations, category information, and user category counts.

## Data Structures

The contract utilizes several Clarity maps and data variables to store and manage reputation data:

* **`user-reputation` (Map):** Stores the reputation details for each user.
    ```clarity
    {
        user: principal,
        score: uint,
        positive-attestations: uint,
        negative-attestations: uint,
        last-updated: uint
    }
    ```
* **`attestations` (Map):** Records individual attestations made between users.
    ```clarity
    {
        from: principal,
        to: principal
    }
    =>
    {
        value: int,        ;; Positive or negative
        timestamp: uint,
        comment: (string-utf8 256)
    }
    ```
* **`categories` (Map):** Stores the names of different attestation categories.
    ```clarity
    {
        category-id: uint
    }
    =>
    {
        name: (string-utf8 64)
    }
    ```
* **`user-categories` (Map):** Tracks the number of attestations a user has received within each category.
    ```clarity
    {
        user: principal,
        category-id: uint
    }
    =>
    {
        count: uint
    }
    ```
* **`next-category-id` (Data Variable):** A counter for assigning unique IDs to new categories.

## Constants

The contract defines the following constants:

* **`ATTESTATION_COOLDOWN`:** `u86400` (24 hours in seconds) - The minimum time interval between attestations from one user to another.
* **`MIN_SCORE`:** `u0` - The minimum possible reputation score.
* **`MAX_SCORE`:** `u100` - The maximum possible reputation score.
* **`CONTRACT_OWNER`:** `tx-sender` - The principal who deployed the contract and has administrative privileges for adding categories.

## Error Codes

The contract defines the following error codes for clarity and debugging:

* **`ERR_UNAUTHORIZED`:** `u401` - Returned when an unauthorized user attempts an administrative action.
* **`ERR_NOT_FOUND`:** `u404` - Returned when a requested resource (e.g., category, user reputation) does not exist.
* **`ERR_COOLDOWN_ACTIVE`:** `u429` - Returned when a user attempts to make an attestation before the cooldown period has expired.
* **`ERR_SELF_ATTESTATION`:** `u403` - Returned when a user attempts to make an attestation about themselves.

## Public Functions

* **`(initialize-reputation)`:**
    * Initializes the reputation record for the transaction sender if it doesn't already exist.
    * Sets the initial score to `u50`, positive and negative attestation counts to `u0`, and the last updated timestamp to the current block time.
    * Returns `(ok true)` if successful or if the reputation is already initialized.

* **`(add-category (name (string-utf8 64)))`:**
    * Adds a new category for attestations.
    * Only callable by the `CONTRACT_OWNER`.
    * Assigns a unique `category-id` to the new category.
    * Returns `(ok category-id)` of the newly added category or `(err ERR_UNAUTHORIZED)` if called by a non-owner.

* **`(make-attestation (to principal) (value int) (category-id uint) (comment (string-utf8 256)))`:**
    * Allows the transaction sender (`from`) to make an attestation about another user (`to`).
    * `value`: An integer representing the attestation value (e.g., `u1` for positive, `-u1` for negative).
    * `category-id`: The ID of the category the attestation belongs to.
    * `comment`: A string providing additional context for the attestation.
    * **Checks:**
        * Ensures that the `from` and `to` principals are not the same (`ERR_SELF_ATTESTATION`).
        * Verifies that the `category-id` exists (`ERR_NOT_FOUND`).
        * Enforces a cooldown period of 24 hours between attestations from the same `from` to the same `to` (`ERR_COOLDOWN_ACTIVE`).
    * Initializes the `to` user's reputation if it doesn't exist.
    * Records the attestation details.
    * Updates the `to` user's reputation score, positive and negative attestation counts, and last updated timestamp.
    * Updates the count of attestations the `to` user has received in the specified `category-id`.
    * Returns `(ok true)` upon successful attestation.

* **`(apply-reputation-decay (user principal))`:**
    * Applies the reputation decay mechanism to the specified `user`.
    * Checks if the user's reputation exists (`ERR_NOT_FOUND`).
    * Calculates the number of days since the last update.
    * If at least 30 days have passed, it calculates a decay factor based on the time elapsed (5% monthly decay, capped at 75%).
    * Applies the decay factor to the positive and negative attestation counts.
    * Recalculates the user's reputation score based on the decayed attestation counts.
    * Updates the user's reputation record with the new score, decayed counts, and the current timestamp.
    * Returns `(ok true)` if decay was applied, `(ok false)` if no decay was needed yet.

## Private Functions

* **`(calculate-score (pos uint) (neg uint))`:**
    * Calculates the reputation score based on the number of positive (`pos`) and negative (`neg`) attestations.
    * The score is a percentage of positive attestations out of the total, clamped between `MIN_SCORE` and `MAX_SCORE`.
    * Returns `u50` if there are no attestations.

* **`(update-category-count (user principal) (category-id uint))`:**
    * Increments the count of attestations received by the `user` in the specified `category-id`.

* **`(calculate-decay-factor (days-passed uint))`:**
    * Calculates the decay factor (percentage to keep) based on the number of `days-passed` since the last update.
    * Applies a 5% monthly decay rate, capped at a maximum total decay of 75%.
    * Returns the percentage of the original value to retain.

* **`(calculate-decayed-value (original-value uint) (decay-factor uint))`:**
    * Applies the calculated `decay-factor` to the `original-value`.
    * Returns the decayed value.

## Read-Only Functions

* **`(get-reputation (user principal))`:**
    * Returns an optional tuple containing the reputation details of the specified `user`.
    * Returns `none` if the user's reputation has not been initialized.

* **`(get-attestation (from principal) (to principal))`:**
    * Returns an optional tuple containing the details of a specific attestation made by `from` to `to`.
    * Returns `none` if no such attestation exists.

* **`(get-category (category-id uint))`:**
    * Returns an optional tuple containing the name of the category with the specified `category-id`.
    * Returns `none` if the category does not exist.

* **`(get-user-category-count (user principal) (category-id uint))`:**
    * Returns a tuple containing the count of attestations received by the specified `user` in the given `category-id`.
    * Returns `{ count: u0 }` if the user has no attestations in that category.

## Usage

To interact with this smart contract, you will need a compatible Stacks wallet and interface with the contract deployed on the Stacks blockchain.

### Initializing Reputation

Users do not need to explicitly call an initialization function. Their reputation will be automatically initialized upon receiving their first attestation.

### Adding Categories (Admin Only)

The contract owner can add new attestation categories using the `add-category` function:

`(contract-call 'SPXXXXXXXXXXXXXXX.reputation-system 'add-category "Professionalism")`

Replace `'SPXXXXXXXXXXXXXXX.reputation-system'` with the actual contract address.

### Making an Attestation

Users can make attestations about other users using the `make-attestation` function:

`(contract-call 'SPXXXXXXXXXXXXXXX.reputation-system 'make-attestation 'SPYYYYYYYYYYYYYYY u1 "communication" "Excellent communication skills.")`


* `'SPYYYYYYYYYYYYYYY'`: The principal of the user being attested.
* `u1`: The attestation value (e.g., `u1` for positive, `-u1` for negative).
* `"communication"`: The ID of the category (you'll need to query the category ID first).
* `"Excellent communication skills."`: The comment for the attestation.

### Applying Reputation Decay

Users (or potentially an automated process) can trigger the reputation decay for a specific user:

`(contract-call 'SPXXXXXXXXXXXXXXX.reputation-system 'apply-reputation-decay 'SPYYYYYYYYYYYYYYY)`


### Querying Reputation

To get a user's reputation:

`(contract-call? 'SPXXXXXXXXXXXXXXX.reputation-system 'get-reputation 'SPZZZZZZZZZZZZZZZ)`


### Querying an Attestation

To get a specific attestation:

`(contract-call? 'SPXXXXXXXXXXXXXXX.reputation-system 'get-attestation 'SPAAAAAAA' 'SPBBBBBBB')`


### Querying a Category

To get category information:

`(contract-call? 'SPXXXXXXXXXXXXXXX.reputation-system 'get-category u0)`


### Querying User Category Count

To get the number of attestations a user has in a specific category:

`(contract-call? 'SPXXXXXXXXXXXXXXX.reputation-system 'get-user-category-count 'SPCCCCCCCCCCC' u0)`


## Security Considerations

* **Immutability:** Once deployed, the contract logic is immutable, ensuring the integrity of the reputation system.
* **Transparency:** All interactions with the contract are recorded on the public Stacks blockchain, providing transparency.
* **Access Control:** Administrative functions (like adding categories) are restricted to the contract owner.
* **DoS Prevention:** The attestation cooldown helps prevent simple denial-of-service attacks through repeated attestations.
* **Smart Contract Auditing:** It is highly recommended to have this contract audited by security professionals before deploying it in a production environment.

## License

This smart contract is released under the MIT License. See the `LICENSE` file for more details.

## Contribution

Contributions to this project are welcome. Please follow these guidelines:

1. Fork the repository.
2. Create a new branch for your feature or bug fix.
3. Make your changes and ensure they are well-tested.
4. Submit a pull request with a clear description of your changes.

## Acknowledgements

We would like to acknowledge the Stacks community for their support and the developers of the Clarity language for providing a robust platform for building decentralized applications.

This README provides a comprehensive overview of the Decentralized Reputation System smart contract. Developers and users can refer to this document for understanding its functionality, data structures, and how to interact with it.
