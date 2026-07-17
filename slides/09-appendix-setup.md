<!-- _class: compact -->

## Appendix — Setup (run before the talk, not presented)

`preflight.sh` stands up a fresh forest and writes a secret-free `demo.env` into
`.output/shared/`:

1. **deploy** a Univocity instance (generates Robert's ES256 bootstrap key)
2. **onboard** the root genesis (`onboard-genesis.mjs`)
3. **fetch + cache** `genesis.cbor` (offline trust root thereafter)
4. **delegate** root sealing to the operator's vouched sealer
5. **mint** the self-referential root grant

```bash
./preflight.sh            # ~1 min: deploys + provisions on Base Sepolia
source .output/shared/demo.env
```

Then paste `demo-script.sh`, slide by slide, into the long-lived terminal.

- Secrets (ops-admin token, gas-paying deployer key) are pulled from Doppler at
  runtime — never written to `demo.env` or committed.

<!--
This slide is not shown live; it documents the one-time prep. The terminal session runs
preflight ONCE, sources the env file once, and every demo slide reuses that state.
-->
