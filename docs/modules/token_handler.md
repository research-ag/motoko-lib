# TokenHandler

Library that allows a canister to detect deposits by individual users into per-user subaccounts on an ICRC1 ledger.
Works asynchronously.

### Responsibilities:
- track the available balance for each user
- consolidate the funds from the subaccounts into a main account but credit the user appropriately to always know an accurate number for the user’s spendable balance.
- provide functionality to debit/credit user

### Interface
- **Constructor** `TokenHandler(icrc1LedgerPrincipal : Principal, ownPrincipal : Principal)`
  <br>
  `icrc1LedgerPrincipal` is a principal of ICRC1 canister, used for tracking accounts and transferring tokens during consolidation
  <br>
  `ownPrincipal` is a principal of own canister, which should be registered in ICRC1 ledger and used by users to send tokens

- **Notify** `notify(p : Principal) : async* ()`
  <br>
  This function should be called after user sent some tokens to the appropriate subaccount, which belongs to us.
  The handler will call icrc1_balance(S:P) to query the balance. It will detect if it has increased compared
  to the last balance seen. If it has increased then it will adjust the deposit_balance (and hence the usable_balance).
  It will also trigger a “consolidation”, i.e. moving the newly deposited funds from S:P to S:0.

- **Debit** `debit(p : Principal, amount : Nat) : Bool`
  <br>
  Deducts amount from P’s usable balance. Returns false if the balance is insufficient.

- **Credit** `credit(p : Principal, amount : Nat) : ()`
  <br>
  Adds amount to P’s usable balance

- **Query balance** `balance(p : Principal) : Nat`
  <br>
  Queries the usable balance

- **Balances info (for debug)** `info(p : Principal) : { deposit_balance : Nat; credit_balance : Int; usable_balance : Int; }`
  <br>
  Queries all tracked balances

- **Backlog size** `backlogSize() : Nat`
  <br>
  Queries consolidation backlog size

- **Get ICRC1 subaccount for principal** `toSubaccount(principal : Principal) : Icrc1Interface.Subaccount`
  <br>
  This function returns corresponding subaccount for client. Use this function to inform user where to send tokens to.
  The user has to send tokens to ICRC1 account
  `(<this canister principal>, toSubaccount(<user's principal>))`

- **Process consolidation backlog** `processConsolidationBacklog() : async ()`
  <br>
  If some consolidation process has been failed, the account would have been added to the backlog, this function
  will take one account from the backlog and retry the consolidation. Backlog works like a stack: last added element will be executed first.
  It is useful to call this function with some timer

- **Share** `share() : [(Principal, { deposit_balance : Nat; credit_balance : Int; })]`
  <br>
  This function returns the tracking info data in sharable format. This function has to be called before canister
  upgrade and value stored in stable memory

- **Unshare** `unshare(values : [(Principal, { deposit_balance : Nat; credit_balance : Int; })]) : ()`
  <br>
  This function consumes the shared tracking info and overwrites own tracking info storage with the data from it.
  This function has to be called after canister upgrade with provided data from stable memory

## Implementation notes

TBD
