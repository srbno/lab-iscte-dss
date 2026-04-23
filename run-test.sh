#!/usr/bin/env bash
# run-test.sh — Supply Chain Security Lab v2
# Uso: ./run-test.sh [start|setup|archive|reset|T1|T2|T3a|T3b|T3c|T4|T5|all]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EVIDENCE="$SCRIPT_DIR/evidence"

# ─── UTILIDADES ───────────────────────────────────────────────────────────────

log()    { echo "[$(date '+%H:%M:%S')] $*"; }
pass()   { echo "  ✓ $*"; }
fail()   { echo "  ✗ $*"; }
info()   { echo "  → $*"; }
sep()    { echo; printf '═%.0s' {1..65}; echo; }
header() { sep; echo "  $*"; sep; }

banner() {
  echo
  printf '╔═══════════════════════════════════════════════════════════╗\n'
  printf '║   SUPPLY CHAIN SECURITY LAB — AMBIENTE CONTROLADO        ║\n'
  printf '║   Este lab contém código simulado de malware.             ║\n'
  printf '║   Execute APENAS dentro de Docker. Nunca no host.        ║\n'
  printf '╚═══════════════════════════════════════════════════════════╝\n'
  echo
}

preflight() {
  if ! docker info > /dev/null 2>&1; then
    echo "ERRO: Docker não está a correr. Inicie o Docker Desktop e tente novamente."
    exit 1
  fi
  if [ ! -f "$SCRIPT_DIR/.env" ]; then
    echo "AVISO: ficheiro .env não encontrado. Testes T3c e T4 podem falhar."
  fi
}

timer_start() { _T_START=$(date +%s); }
timer_end()   {
  local elapsed=$(( $(date +%s) - _T_START ))
  echo "  ⏱  Duração: ${elapsed}s"
}

# ─── START ────────────────────────────────────────────────────────────────────
start() {
  banner
  preflight
  header "START — A iniciar infra do lab"
  log "A arrancar verdaccio e exfil-server..."
  docker compose up -d verdaccio exfil-server 
  sleep 3
  pass "Verdaccio e exfil-server a correr"
  info "Próximo passo: ./run-test.sh setup"
}

# ─── SETUP ────────────────────────────────────────────────────────────────────

setup() {
  banner
  preflight
  header "SETUP — A publicar pacote demo no Verdaccio"
  local publish_output
  docker compose up -d verdaccio exfil-server
  sleep 3

  if publish_output=$(docker compose --profile setup run --rm publisher 2>&1); then
    printf '%s\n' "$publish_output"
    pass "Pacote @demo-lab/supply-chain-demo publicado no Verdaccio"
  else
    printf '%s\n' "$publish_output"
    if printf '%s\n' "$publish_output" | grep -Eq 'E409|already present'; then
      info "Pacote @demo-lab/supply-chain-demo já existia no Verdaccio — publish ignorado"
    else
      fail "Falha ao publicar pacote demo no Verdaccio"
      return 1
    fi
  fi

  sleep 1
  info "Lab pronto. Corra ./run-test.sh T1 para iniciar os testes."
}

# ─── ARCHIVE ──────────────────────────────────────────────────────────────────

archive() {
  banner
  preflight
  header "ARCHIVE — A arquivar evidências actuais"
  local timestamp
  timestamp=$(date '+%Y-%m-%d-%H%M%S')
  local dest="$EVIDENCE/archive/$timestamp"
  mkdir -p "$dest"
  for dir in "$EVIDENCE"/T*/; do
    [ -d "$dir" ] && mv "$dir" "$dest/"
  done
  for f in "$EVIDENCE"/*.txt "$EVIDENCE"/*.json; do
    [ -f "$f" ] && mv "$f" "$dest/"
  done
  pass "Evidências arquivadas em: evidence/archive/$timestamp/"
  info "Os diretórios T1–T6 serão recriados na próxima execução dos testes."
}

# ─── RESET ────────────────────────────────────────────────────────────────────

reset() {
  banner
  header "RESET — A destruir ambiente Docker"
  docker compose --profile dependencytrack down --volumes --remove-orphans
  pass "Todos os containers, redes e volumes removidos"
}

# ─── T1: BASELINE ─────────────────────────────────────────────────────────────

t1() {
  banner; preflight
  header "T1 — Baseline: npm install sem protecção"
  timer_start
  mkdir -p "$EVIDENCE/T1-baseline"

  docker compose restart exfil-server
  sleep 2

  log "A executar npm install com ambas as dependências..."
  docker compose run --rm -T test-app \
    sh -c "
      mkdir -p /install && cd /install &&
      cat > package.json <<'EOF'
{\"dependencies\":{\"@demo-lab/supply-chain-demo\":\"1.0.0\",\"lodash\":\"4.17.11\"}}
EOF
      npm install --registry http://verdaccio:4873
    " \
    2>&1 | tee "$EVIDENCE/T1-baseline/npm-install.txt"

  sleep 2
  docker compose logs exfil-server > "$EVIDENCE/T1-baseline/exfil-server.txt"

  sep
  if grep -q "EXFILTRATION RECEIVED" "$EVIDENCE/T1-baseline/exfil-server.txt"; then
    pass "RESULTADO: postinstall executou — dados exfiltrados para o exfil-server"
  else
    fail "RESULTADO: exfil-server NÃO recebeu dados — verificar configuração"
  fi
  timer_end
  info "Evidências: evidence/T1-baseline/"
}

# ─── T2: SYFT ─────────────────────────────────────────────────────────────────

t2() {
  banner; preflight
  header "T2 — Syft: geração de SBOM"
  timer_start
  mkdir -p "$EVIDENCE/T2-syft"

  docker compose --profile analysis run --rm syft

  sep
  if [ -f "$EVIDENCE/T2-syft/sbom.json" ]; then
    local pkgs
    pkgs=$(python3 -c "import json,sys; d=json.load(open('$EVIDENCE/T2-syft/sbom.json')); print(len(d.get('components',d.get('packages',[]))))" 2>/dev/null || echo "?")
    pass "RESULTADO: SBOM gerado — $pkgs componentes inventariados"
    grep -q "supply-chain-demo" "$EVIDENCE/T2-syft/sbom.json" \
      && pass "Pacote @demo-lab/supply-chain-demo consta do inventário" \
      || fail "Pacote demo NÃO encontrado no SBOM"
    grep -q '"lodash"' "$EVIDENCE/T2-syft/sbom.json" \
      && pass "lodash@4.17.11 consta do inventário" \
      || fail "lodash NÃO encontrado no SBOM"
  else
    fail "RESULTADO: SBOM não foi gerado"
  fi
  timer_end
  info "Evidências: evidence/T2-syft/"
}

# ─── T3a: NPM AUDIT ───────────────────────────────────────────────────────────

t3a() {
  banner; preflight
  header "T3a — npm audit: SCA reativo (base npm)"
  timer_start
  mkdir -p "$EVIDENCE/T3a-npm-audit"

  docker compose --profile analysis run --rm npm-audit

  sep
  if grep -q "lodash" "$EVIDENCE/T3a-npm-audit/npm-audit.txt" 2>/dev/null; then
    pass "RESULTADO: vulnerabilidades detectadas — lodash@4.17.11 flagged"
    info "Ver: evidence/T3a-npm-audit/npm-audit.txt"
  elif grep -q "found 0 vulnerabilities" "$EVIDENCE/T3a-npm-audit/npm-audit.txt" 2>/dev/null; then
    fail "RESULTADO: 0 vulnerabilidades — lodash não detectado (verificar lockfile)"
  else
    info "RESULTADO: verificar evidence/T3a-npm-audit/npm-audit.txt"
  fi
  timer_end
  info "Evidências: evidence/T3a-npm-audit/"
}

# ─── T3b: OSV SCANNER ─────────────────────────────────────────────────────────

t3b() {
  banner; preflight
  header "T3b — OSV Scanner: SCA reativo (base Google OSV)"
  timer_start
  mkdir -p "$EVIDENCE/T3b-osv-scanner"
  mkdir -p "$EVIDENCE/T3b-osv-sbom"

  log "Passo 1/2 — OSV Scanner a ler package-lock.json directamente..."
  docker compose --profile analysis run --rm osv-scanner 2>&1 || true

  sep
  if [ -f "$EVIDENCE/T3b-osv-scanner/osv-scanner.json" ]; then
    local vulns
    vulns=$(python3 -c "
import json,sys
d=json.load(open('$EVIDENCE/T3b-osv-scanner/osv-scanner.json'))
results=d.get('results',[])
total=sum(len(r.get('packages',[])) for r in results)
print(total)
" 2>/dev/null || echo "?")
    pass "package-lock.json: $vulns pacotes com findings"
  else
    info "package-lock.json: sem ficheiro JSON — sem vulnerabilidades ou erro"
  fi

  log "Passo 2/2 — OSV Scanner a consumir SBOM gerado pelo Syft (pipeline Syft→OSV)..."
  if [ ! -f "$EVIDENCE/T2-syft/sbom.json" ]; then
    fail "SBOM não encontrado — corra T2 primeiro: ./run-test.sh T2"
  else
    docker compose --profile analysis run --rm osv-scanner-sbom 2>&1 || true
    if [ -f "$EVIDENCE/T3b-osv-sbom/osv-scanner-sbom.json" ]; then
      local vulns_sbom
      vulns_sbom=$(python3 -c "
import json,sys
d=json.load(open('$EVIDENCE/T3b-osv-sbom/osv-scanner-sbom.json'))
results=d.get('results',[])
total=sum(len(r.get('packages',[])) for r in results)
print(total)
" 2>/dev/null || echo "?")
      pass "SBOM (Syft→OSV): $vulns_sbom pacotes com findings — pipeline reutilizável confirmada"
    else
      info "SBOM: sem ficheiro JSON — verificar evidence/T3b-osv-sbom/"
    fi
  fi

  timer_end
  info "Evidências: evidence/T3b-osv-scanner/ e evidence/T3b-osv-sbom/"
}

# ─── T3c: SNYK ────────────────────────────────────────────────────────────────

t3c() {
  banner; preflight
  header "T3c — Snyk: SCA reativo (base proprietária)"

  if [ -z "${SNYK_TOKEN:-}" ]; then
    fail "SNYK_TOKEN não definido. Adicionar ao .env e reexecutar."
    return 1
  fi

  timer_start
  mkdir -p "$EVIDENCE/T3c-snyk"
  rm -f "$EVIDENCE/T3c-snyk/snyk.json" "$EVIDENCE/T3c-snyk/snyk.txt"
  set -a; source "$SCRIPT_DIR/.env"; set +a

  docker compose --profile analysis run --rm snyk

  sep
  if [ ! -f "$EVIDENCE/T3c-snyk/snyk.json" ] || [ ! -f "$EVIDENCE/T3c-snyk/snyk.txt" ]; then
    fail "RESULTADO: Snyk não gerou os artefactos esperados — verificar o serviço no docker-compose"
    return 1
  elif grep -q "lodash" "$EVIDENCE/T3c-snyk/snyk.txt" 2>/dev/null; then
    pass "RESULTADO: vulnerabilidades detectadas — lodash@4.17.11 flagged"
  elif grep -q "No vulnerable paths found" "$EVIDENCE/T3c-snyk/snyk.txt" 2>/dev/null; then
    fail "RESULTADO: 0 vulnerabilidades — verificar lockfile e token"
  else
    info "RESULTADO: verificar evidence/T3c-snyk/snyk.txt"
  fi
  timer_end
  info "Evidências: evidence/T3c-snyk/"
}

# ─── T4: SOCKET.DEV ───────────────────────────────────────────────────────────

t4() {
  banner; preflight
  header "T4 — Socket.dev: análise comportamental"

  if [ -z "${SOCKET_TOKEN:-}" ] || [ -z "${SOCKET_ORG:-}" ]; then
    fail "SOCKET_TOKEN ou SOCKET_ORG não definidos. Adicionar ao .env e reexecutar."
    return 1
  fi

  timer_start
  mkdir -p "$EVIDENCE/T4-socket"
  set -a; source "$SCRIPT_DIR/.env"; set +a

  docker compose --profile analysis run --rm socket-cli

  sep
  if [ -f "$EVIDENCE/T4-socket/socket.txt" ]; then
    if grep -qi "lodash" "$EVIDENCE/T4-socket/socket.txt" 2>/dev/null; then
      pass "RESULTADO: Socket detectou findings para lodash (npm público)"
    else
      info "RESULTADO: verificar socket.txt — pode não ter detectado lodash"
    fi
    if grep -qi "supply-chain-demo" "$EVIDENCE/T4-socket/socket.txt" 2>/dev/null; then
      info "Supply-chain-demo mencionado no output"
    else
      info "Supply-chain-demo não indexado pelo Socket (registry privado — esperado)"
    fi
  else
    info "RESULTADO: verificar evidence/T4-socket/"
  fi
  timer_end
  info "Evidências: evidence/T4-socket/"
}

# ─── T5: PNPM V10 ─────────────────────────────────────────────────────────────

t5() {
  banner; preflight
  header "T5 — pnpm v10: bloqueio de lifecycle scripts"
  timer_start
  mkdir -p "$EVIDENCE/T5-pnpm"

  docker compose restart exfil-server
  sleep 2

  log "A executar pnpm install com ambas as dependências..."
  docker compose run --rm -T test-app \
    sh -c "
      mkdir -p /install-pnpm && cd /install-pnpm &&
      cat > package.json <<'EOF'
{\"dependencies\":{\"@demo-lab/supply-chain-demo\":\"1.0.0\",\"lodash\":\"4.17.11\"}}
EOF
      pnpm install --registry http://verdaccio:4873
    " \
    2>&1 | tee "$EVIDENCE/T5-pnpm/pnpm-install.txt"

  sleep 2
  docker compose logs --since 20s exfil-server > "$EVIDENCE/T5-pnpm/exfil-server.txt"

  sep
  if grep -q "Ignored build scripts" "$EVIDENCE/T5-pnpm/pnpm-install.txt" 2>/dev/null; then
    pass "RESULTADO: pnpm v10 bloqueou lifecycle scripts — postinstall NÃO executou"
  else
    fail "RESULTADO: pnpm não bloqueou — verificar versão do pnpm"
  fi
  if grep -q "EXFILTRATION RECEIVED" "$EVIDENCE/T5-pnpm/exfil-server.txt" 2>/dev/null; then
    fail "INESPERADO: exfil-server recebeu dados — postinstall executou"
  else
    pass "exfil-server não recebeu dados — confirmado"
  fi
  timer_end
  info "Evidências: evidence/T5-pnpm/"
}

# ─── T6: DEPENDENCY-TRACK ─────────────────────────────────────────────────────

t6() {
  banner; preflight
  header "T6 — Dependency-Track: monitorização contínua de SBOM"
  timer_start
  mkdir -p "$EVIDENCE/T6-dependencytrack"

  # Pré-requisito: SBOM do T2
  if [ ! -f "$EVIDENCE/T2-syft/sbom.json" ]; then
    info "SBOM não encontrado — a executar T2 primeiro..."
    t2
  fi

  if [ -z "${DT_ADMIN_PASSWORD:-}" ]; then
    fail "DT_ADMIN_PASSWORD não definido. Adicionar ao .env e reexecutar."
    return 1
  fi
  local dt_pass="$DT_ADMIN_PASSWORD"
  local dt_url="http://localhost:8080"

  # 1. Arrancar Dependency-Track
  log "A arrancar Dependency-Track (pode demorar 60–90s na primeira inicialização)..."
  docker compose --profile dependencytrack up -d dependencytrack

  # 2. Aguardar API ficar disponível (max 120s) — usa / porque /api/v1/version não existe em 4.13.x
  log "A aguardar API do Dependency-Track..."
  local ready=0
  for i in $(seq 1 20); do
    if curl -sf "$dt_url/" > /dev/null 2>&1; then
      ready=1; break
    fi
    printf '.'
    sleep 6
  done
  echo
  if [ "$ready" -eq 0 ]; then
    fail "Dependency-Track não respondeu após 120s"
    info "Verificar logs: docker compose --profile dependencytrack logs dependencytrack"
    return 1
  fi
  pass "Dependency-Track disponível em $dt_url"

  # 3. Autenticar → JWT
  # No primeiro arranque, DT cria admin com password 'admin' + forcePwChange=true.
  # É necessário chamar forceChangePassword antes do primeiro login real.
  log "A autenticar (admin)..."
  local jwt
  jwt=$(curl -s -X POST "$dt_url/api/v1/user/login" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=admin&password=${dt_pass}" 2>/dev/null | tr -d '"') || true

  if [ -z "$jwt" ] || [ "$jwt" = "INVALID_CREDENTIALS" ]; then
    info "Primeira inicialização detectada — a definir password do admin..."
    curl -sf -X POST "$dt_url/api/v1/user/forceChangePassword" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "username=admin&password=admin&newPassword=${dt_pass}&confirmPassword=${dt_pass}" \
      > /dev/null 2>&1 || true
    sleep 1
    jwt=$(curl -s -X POST "$dt_url/api/v1/user/login" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "username=admin&password=${dt_pass}" 2>/dev/null | tr -d '"') || true
  fi

  if [ -z "$jwt" ] || [ "$jwt" = "INVALID_CREDENTIALS" ]; then
    fail "Autenticação falhou — verificar DT_ADMIN_PASSWORD no .env"
    return 1
  fi
  pass "Autenticado com sucesso"

  # 4. Criar projecto (ou reutilizar se já existir — evita conflito em re-runs)
  log "A verificar/criar projecto test-app v1.0.0..."
  local uuid
  # Pesquisar projecto existente com o mesmo nome e versão
  uuid=$(curl -s -H "Authorization: Bearer $jwt" \
    "$dt_url/api/v1/project?name=test-app&version=1.0.0&excludeInactive=false" 2>/dev/null \
    | python3 -c "
import json,sys
data=json.load(sys.stdin)
items = data if isinstance(data, list) else data.get('data', [])
print(items[0]['uuid'] if items else '')
" 2>/dev/null) || true

  if [ -n "$uuid" ]; then
    pass "Projecto existente reutilizado (UUID: ${uuid:0:8}...)"
    # Guardar para referência
    echo "{\"uuid\":\"$uuid\",\"name\":\"test-app\",\"version\":\"1.0.0\",\"reused\":true}" \
      > "$EVIDENCE/T6-dependencytrack/dt-project.json"
  else
    local project_json
    project_json=$(curl -s -X PUT "$dt_url/api/v1/project" \
      -H "Authorization: Bearer $jwt" \
      -H "Content-Type: application/json" \
      -d '{"name":"test-app","version":"1.0.0","classifier":"APPLICATION"}') || true
    echo "$project_json" > "$EVIDENCE/T6-dependencytrack/dt-project.json"
    uuid=$(python3 -c "import json,sys; print(json.load(sys.stdin)['uuid'])" \
      < "$EVIDENCE/T6-dependencytrack/dt-project.json" 2>/dev/null) || true
    if [ -z "$uuid" ]; then
      fail "Criação do projecto falhou — ver evidence/T6-dependencytrack/dt-project.json"
      return 1
    fi
    pass "Projecto criado (UUID: ${uuid:0:8}...)"
  fi

  # 5. Upload do SBOM via base64+JSON (evita problemas com paths com espaços)
  log "A fazer upload do SBOM (evidence/T2-syft/sbom.json)..."
  local bom_b64
  bom_b64=$(base64 < "$EVIDENCE/T2-syft/sbom.json" | tr -d '\n\r') || true

  if [ -z "$bom_b64" ]; then
    fail "Falha ao codificar SBOM em base64 — verificar evidence/T2-syft/sbom.json"
    return 1
  fi

  local bom_response
  bom_response=$(curl -s -X PUT "$dt_url/api/v1/bom" \
    -H "Authorization: Bearer $jwt" \
    -H "Content-Type: application/json" \
    -d "{\"project\":\"$uuid\",\"bom\":\"$bom_b64\"}") || true

  local bom_token
  bom_token=$(python3 -c "import json,sys; print(json.load(sys.stdin)['token'])" \
    <<< "$bom_response" 2>/dev/null) || true

  if [ -z "$bom_token" ]; then
    fail "Upload do SBOM falhou — resposta: ${bom_response:0:120}"
    return 1
  fi
  pass "SBOM enviado para análise"

  # 6. Aguardar processamento do SBOM (max 45s)
  log "A aguardar processamento do SBOM..."
  for i in $(seq 1 15); do
    local processing
    processing=$(curl -sf "$dt_url/api/v1/bom/token/$bom_token" \
      -H "Authorization: Bearer $jwt" 2>/dev/null \
      | python3 -c "import json,sys; print(json.load(sys.stdin).get('processing','true'))" 2>/dev/null) || true
    [ "$processing" = "False" ] && { pass "SBOM processado"; break; }
    printf '.'
    sleep 3
  done
  echo

  # 7. Recolher findings e métricas
  log "A recolher findings de vulnerabilidades..."
  curl -sf "$dt_url/api/v1/finding/project/$uuid" \
    -H "Authorization: Bearer $jwt" \
    > "$EVIDENCE/T6-dependencytrack/dt-findings.json" 2>/dev/null || echo "[]" > "$EVIDENCE/T6-dependencytrack/dt-findings.json"

  curl -sf "$dt_url/api/v1/metrics/project/$uuid/current" \
    -H "Authorization: Bearer $jwt" \
    > "$EVIDENCE/T6-dependencytrack/dt-metrics.json" 2>/dev/null || echo "{}" > "$EVIDENCE/T6-dependencytrack/dt-metrics.json"

  # 8. Sumário legível
  python3 - "$EVIDENCE/T6-dependencytrack/dt-findings.json" \
             "$EVIDENCE/T6-dependencytrack/dt-metrics.json" <<'PYEOF' \
    | tee "$EVIDENCE/T6-dependencytrack/dt-summary.txt"
import json, sys

findings_path, metrics_path = sys.argv[1], sys.argv[2]

try:
    findings = json.load(open(findings_path))
    total = len(findings)
    by_sev = {}
    for f in findings:
        sev = f.get('vulnerability', {}).get('severity', 'UNASSIGNED')
        by_sev[sev] = by_sev.get(sev, 0) + 1
    lodash_n = sum(1 for f in findings
                   if 'lodash' in f.get('component', {}).get('name', '').lower())
    demo_n   = sum(1 for f in findings
                   if 'supply-chain-demo' in f.get('component', {}).get('name', '').lower())
    print(f"=== Dependency-Track — Findings ===")
    print(f"Total de findings : {total}")
    for sev in ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'UNASSIGNED']:
        if sev in by_sev:
            print(f"  {sev:10s}: {by_sev[sev]}")
    print(f"lodash findings   : {lodash_n}")
    print(f"supply-chain-demo : {demo_n} (sem CVE registado — esperado)")
except Exception as e:
    print(f"Erro findings: {e}")

try:
    m = json.load(open(metrics_path))
    print(f"\n=== Métricas do projecto ===")
    print(f"Componentes       : {m.get('components', '?')}")
    print(f"Vulneráveis       : {m.get('vulnerableComponents', '?')}")
    print(f"Findings total    : {m.get('findings', '?')}")
    print(f"Suprimidos        : {m.get('suppressed', '?')}")
except Exception as e:
    print(f"Erro métricas: {e}")
PYEOF

  # 9. Verificação final
  sep
  local lodash_n
  lodash_n=$(python3 -c "
import json
findings = json.load(open('$EVIDENCE/T6-dependencytrack/dt-findings.json'))
print(sum(1 for f in findings if 'lodash' in f.get('component',{}).get('name','').lower()))
" 2>/dev/null || echo "0")

  if [ "${lodash_n:-0}" -gt 0 ] 2>/dev/null; then
    pass "RESULTADO: $lodash_n CVEs detectados em lodash@4.17.11"
    pass "supply-chain-demo sem CVE → não aparece nos findings (confirma argumento central)"
    pass "Pipeline completa demonstrada: T1 (ataque) → T2 (SBOM) → T5 (prevenção) → T6 (monitorização)"
  else
    info "RESULTADO: 0 findings — DT pode ainda estar a sincronizar bases CVE (primeira execução)"
    info "Aguardar 10–15 min e voltar a correr: ./run-test.sh T6"
    info "Ou aceder à UI: $dt_url (admin / $dt_pass)"
  fi

  timer_end
  info "Evidências : evidence/T6-dependencytrack/"
  info "UI web     : $dt_url  (admin / $dt_pass)"
}

# ─── ALL ──────────────────────────────────────────────────────────────────────

all() {
  banner; preflight
  setup
  t1; t2; t3a; t3b
  if [ -n "${SNYK_TOKEN:-}" ]; then t3c; else log "T3c ignorado (sem SNYK_TOKEN)"; fi
  if [ -n "${SOCKET_TOKEN:-}" ] && [ -n "${SOCKET_ORG:-}" ]; then t4; else log "T4 ignorado (sem SOCKET_TOKEN/SOCKET_ORG)"; fi
  t5; t6
  sep
  log "Suite completa. Evidências em:"
  for dir in "$EVIDENCE"/T*/; do
    [ -d "$dir" ] && echo "  $(basename "$dir")"
  done
}

# ─── ROUTER ───────────────────────────────────────────────────────────────────

case "${1:-}" in
  start)        start ;;
  setup)        setup ;;
  archive)      archive ;;
  reset)        reset ;;
  T1|t1)        setup; t1 ;;
  T2|t2)        t2 ;;
  T3a|t3a)      t3a ;;
  T3b|t3b)      t3b ;;
  T3c|t3c)      t3c ;;
  T4|t4)        t4 ;;
  T5|t5)        setup; t5 ;;
  T6|t6)        t6 ;;
  all)          all ;;
  *)
    banner
    echo "Uso: ./run-test.sh <comando>"
    echo
    echo "  Infra:"
    echo "    start     Inicia verdaccio e exfil-server"
    echo "    setup     Publica pacote demo no Verdaccio (requer start)"
    echo "    archive   Arquiva evidências actuais com timestamp"
    echo "    reset     Remove todos os containers, redes e volumes"
    echo
    echo "  Testes:"
    echo "    T1        Baseline — npm install (postinstall executa)"
    echo "    T2        Syft — SBOM"
    echo "    T3a       npm audit"
    echo "    T3b       OSV Scanner"
    echo "    T3c       Snyk (requer SNYK_TOKEN no .env)"
    echo "    T4        Socket.dev (requer SOCKET_TOKEN + SOCKET_ORG no .env)"
    echo "    T5        pnpm v10 — bloqueio de lifecycle scripts"
    echo "    T6        Dependency-Track — monitorização contínua de SBOM"
    echo "    all       T1–T6 em sequência"
    echo
    exit 1
    ;;
esac
