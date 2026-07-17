#!/usr/bin/env bash
#
# Slide 5 — Split-view protection: throwaway deploy + on-chain binding.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]:-$0}")/demo-lib.sh"
demo_init 05

# Deploying is easy — a THROWAWAY instance so we don't disturb the live forest
# (its own --out + pem; we do NOT re-export ROBERT_LOG_ID / UNIVOCITY_ADDRESS).
# The gas-paying key is fetched at runtime, never stored in demo.env.
run 'DEPLOYER_KEY=$(doppler secrets get DEPLOY_KEY --project canopy --config dev --plain)'

run './forestrie deploy --bootstrap-alg es256 --bootstrap-es256-generate \
	--bootstrap-es256-pem-out "$S/throwaway.es256.pem" \
	--owner-address "$OWNER_ADDRESS" --deployer-key "$DEPLOYER_KEY" \
	--rpc-url "$RPC_URL" --out "$S/throwaway.json"'

note "the real payoff: on-chain, the live contract's bootstrap key IS the key that"
note 'signed our root grant — split-view lives in the contract, not the operator'
run '~/.foundry/bin/cast call "$UNIVOCITY_ADDRESS" "bootstrapConfig()(int64,bytes)" --rpc-url "$RPC_URL"'
