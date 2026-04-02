# ─────────────────────────────────────────────────────────────
#  MeshLink — API Test Commands
#  Linux:   use the curl commands below directly in terminal
#  Windows: use the PowerShell (Invoke-RestMethod) equivalents
# ─────────────────────────────────────────────────────────────

BASE=http://localhost:3000


# ══════════════════════════════════════════════════════════════
#  1. HEALTH CHECK
# ══════════════════════════════════════════════════════════════

# Linux
curl $BASE/health

# Windows PowerShell
Invoke-RestMethod $env:BASE/health
# or simply:
Invoke-RestMethod http://localhost:3000/health


# ══════════════════════════════════════════════════════════════
#  2. GENERATE HOST CONFIG (no disk write)
# ══════════════════════════════════════════════════════════════

# Linux
curl -s -X POST $BASE/api/generate-host-config \
  -H "Content-Type: application/json" \
  -d '{
    "hostVirtualIP": "10.0.0.1",
    "listenPort": 51820,
    "peers": [
      { "name": "Rahul", "publicKey": "PLACEHOLDER_KEY=", "virtualIP": "10.0.0.2" }
    ]
  }' | jq .

# Linux — minimal (no peers)
curl -s -X POST $BASE/api/generate-host-config \
  -H "Content-Type: application/json" \
  -d '{ "hostVirtualIP": "10.0.0.1" }' | jq .

# Windows PowerShell
Invoke-RestMethod -Uri http://localhost:3000/api/generate-host-config `
  -Method POST `
  -ContentType "application/json" `
  -Body '{
    "hostVirtualIP": "10.0.0.1",
    "listenPort": 51820,
    "peers": []
  }'


# ══════════════════════════════════════════════════════════════
#  3. GENERATE MEMBER CONFIG (no disk write)
#     Replace HOST_PUBLIC_KEY with the publicKey from step 2
# ══════════════════════════════════════════════════════════════

# Linux
curl -s -X POST $BASE/api/generate-config \
  -H "Content-Type: application/json" \
  -d '{
    "memberName": "Rahul",
    "memberVirtualIP": "10.0.0.2",
    "hostPublicKey": "HOST_PUBLIC_KEY_HERE=",
    "hostEndpoint": "203.0.113.10",
    "hostVirtualIP": "10.0.0.1"
  }' | jq .

# Windows PowerShell
Invoke-RestMethod -Uri http://localhost:3000/api/generate-config `
  -Method POST `
  -ContentType "application/json" `
  -Body '{
    "memberName": "Rahul",
    "memberVirtualIP": "10.0.0.2",
    "hostPublicKey": "HOST_PUBLIC_KEY_HERE=",
    "hostEndpoint": "203.0.113.10",
    "hostVirtualIP": "10.0.0.1"
  }'


# ══════════════════════════════════════════════════════════════
#  4. APPLY HOST CONFIG (writes to disk + starts WireGuard)
#     Requires: WireGuard installed + backend running as root
# ══════════════════════════════════════════════════════════════

# Linux
curl -s -X POST $BASE/api/apply-host-config \
  -H "Content-Type: application/json" \
  -d '{
    "hostVirtualIP": "10.0.0.1",
    "listenPort": 51820,
    "peers": []
  }' | jq .

# Windows PowerShell
Invoke-RestMethod -Uri http://localhost:3000/api/apply-host-config `
  -Method POST `
  -ContentType "application/json" `
  -Body '{
    "hostVirtualIP": "10.0.0.1",
    "listenPort": 51820,
    "peers": []
  }'


# ══════════════════════════════════════════════════════════════
#  5. APPLY MEMBER CONFIG (writes to disk + starts WireGuard)
#     Requires: WireGuard installed + backend running as root
# ══════════════════════════════════════════════════════════════

# Linux
curl -s -X POST $BASE/api/apply-member-config \
  -H "Content-Type: application/json" \
  -d '{
    "memberName": "Rahul",
    "memberVirtualIP": "10.0.0.2",
    "hostPublicKey": "HOST_PUBLIC_KEY_HERE=",
    "hostEndpoint": "203.0.113.10",
    "hostVirtualIP": "10.0.0.1"
  }' | jq .

# Windows PowerShell
Invoke-RestMethod -Uri http://localhost:3000/api/apply-member-config `
  -Method POST `
  -ContentType "application/json" `
  -Body '{
    "memberName": "Rahul",
    "memberVirtualIP": "10.0.0.2",
    "hostPublicKey": "HOST_PUBLIC_KEY_HERE=",
    "hostEndpoint": "203.0.113.10",
    "hostVirtualIP": "10.0.0.1"
  }'


# ══════════════════════════════════════════════════════════════
#  6. WIREGUARD STATUS
# ══════════════════════════════════════════════════════════════

# Linux
curl -s $BASE/api/wg/status | jq .

# Windows PowerShell
Invoke-RestMethod http://localhost:3000/api/wg/status


# ══════════════════════════════════════════════════════════════
#  7. WIREGUARD STOP
# ══════════════════════════════════════════════════════════════

# Linux
curl -s -X POST $BASE/api/wg/stop \
  -H "Content-Type: application/json" \
  -d '{}' | jq .

# Windows PowerShell
Invoke-RestMethod -Uri http://localhost:3000/api/wg/stop `
  -Method POST -ContentType "application/json" -Body '{}'


# ══════════════════════════════════════════════════════════════
#  8. WIREGUARD START
# ══════════════════════════════════════════════════════════════

# Linux
curl -s -X POST $BASE/api/wg/start \
  -H "Content-Type: application/json" \
  -d '{}' | jq .

# Windows PowerShell
Invoke-RestMethod -Uri http://localhost:3000/api/wg/start `
  -Method POST -ContentType "application/json" -Body '{}'


# ══════════════════════════════════════════════════════════════
#  9. PING
# ══════════════════════════════════════════════════════════════

# Linux — ping localhost (always works, good smoke test)
curl -s -X POST $BASE/api/ping \
  -H "Content-Type: application/json" \
  -d '{ "ip": "127.0.0.1" }' | jq .

# Linux — ping a virtual peer (only works after WG is up)
curl -s -X POST $BASE/api/ping \
  -H "Content-Type: application/json" \
  -d '{ "ip": "10.0.0.2" }' | jq .

# Linux — invalid IP (should return 400)
curl -s -X POST $BASE/api/ping \
  -H "Content-Type: application/json" \
  -d '{ "ip": "not-an-ip" }' | jq .

# Windows PowerShell
Invoke-RestMethod -Uri http://localhost:3000/api/ping `
  -Method POST -ContentType "application/json" `
  -Body '{ "ip": "127.0.0.1" }'


# ══════════════════════════════════════════════════════════════
#  VALIDATION FAILURE TESTS (all should return 400)
# ══════════════════════════════════════════════════════════════

# Missing hostVirtualIP
curl -s -X POST $BASE/api/generate-host-config \
  -H "Content-Type: application/json" \
  -d '{ "listenPort": 51820 }' | jq .

# Missing required member fields
curl -s -X POST $BASE/api/generate-config \
  -H "Content-Type: application/json" \
  -d '{ "memberName": "Rahul" }' | jq .

# Missing ip in ping
curl -s -X POST $BASE/api/ping \
  -H "Content-Type: application/json" \
  -d '{}' | jq .

# Unknown route — should return 404
curl -s $BASE/api/does-not-exist | jq .
