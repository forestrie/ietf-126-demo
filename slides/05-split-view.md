<!-- _class: compact -->

## Split-view protection

- For split-view protection we accept **a little blockchain**: the Univocity contract
- Anyone can deploy one and register it with the TS
- Checkpoints are **submitted permissionlessly**, but each must be **signed by a key the log
  owner delegated** (or the owner, self-hosting) **and** carry a valid consistency proof
- The first checkpoint of a *child* log needs a grant; the **root** owner is bound at deploy
- One instance carries a **hierarchy** of log owners, each with independent split-view

```bash
# Deploying is easy (throwaway instance — doesn't touch the live demo forest):
forestrie deploy --bootstrap-alg es256 --bootstrap-es256-generate … --out /tmp/throwaway.json

# The binding is on-chain: the contract's bootstrap key == the key that signed our grant
~/.foundry/bin/cast call "$UNIVOCITY_ADDRESS" "bootstrapConfig()(int64,bytes)" --rpc-url "$RPC_URL"
```

- The operator has **no special privilege** — the Univocity owner can move to another TS anytime

<!--
The mechanism: the contract only advances a log's accumulator on a valid consistency proof, and
Ethereum consensus gives one global view — so a receipt whose peak reached the chain can't be
shown two ways. Split-view is externalised to the contract, NOT the operator. The live deploy is a
throwaway so it can't clobber ROBERT_LOG_ID / deployment.json that later slides depend on; the real
payoff is the cast call showing bootstrapConfig == the key that signed root-grant.b64.
-->
