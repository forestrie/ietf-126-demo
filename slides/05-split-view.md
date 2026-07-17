<!-- _class: compact -->

## Split-view protection

- For split-view protection we accept a little blockchain in our lives: checkpoints are published to the log owners instance of the Univocity smart contract.
- Anyone can deploy one and register it with the TS
- Checkpoints are **submitted permissionlessly**, but each must be **signed** or **delegated to** by the log owner **and** carry a valid MMR-profile consistency proof
- The first checkpoint of a *child* log needs a grant from its parent log; the **root** log owner is bound at contract deployment
- One instance carries a **hierarchy** of log owners, each with independent split-view

On this slide we *deploy* that contract based on a pre-built contract artefact.

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
