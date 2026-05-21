#!/usr/bin/env bash
set -euo pipefail

# Phase A: deploy everything WITHOUT static routes (vWAN, hubs, AzFW, VNets, peering, VMs).
# Phase B: re-run with enableStaticRoutes=true to add the static routes.

RG="${1:-${RG:-}}"
PREFIX="${PREFIX:-vwansr}"
PHASE="${PHASE:-A}"
LOC="${LOC:-australiaeast}"
SSH_KEY_FILE="${SSH_KEY_FILE:-$HOME/.ssh/vwansr_ed25519.pub}"

if [[ -z "$RG" ]]; then
  echo "usage: RG=<rg> $0   (or pass rg as first arg)" >&2
  exit 1
fi

PUBKEY="$(cat "$SSH_KEY_FILE")"
ENABLE_SR=false
[[ "$PHASE" == "B" ]] && ENABLE_SR=true

echo "Deploying phase=$PHASE  rg=$RG  prefix=$PREFIX  enableStaticRoutes=$ENABLE_SR"

az deployment group create \
  -g "$RG" \
  -n "vwansr-phase-${PHASE}" \
  -f main.bicep \
  -p prefix="$PREFIX" \
     adminSshPublicKey="$PUBKEY" \
     enableStaticRoutes="$ENABLE_SR" \
  --no-wait

echo "Submitted. Watch with: az deployment group show -g $RG -n vwansr-phase-${PHASE} --query properties.provisioningState -o tsv"
