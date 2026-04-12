#!/usr/bin/env bash
# run-test.sh — Supply Chain Security Lab v2
# Uso: ./run-test.sh [start|setup|archive|reset|T1|T2|T3a|T3b|T3c|T4|T5|T6|all]
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
  docker compose up -d verdaccio exfil-server
  sleep 3
  docker compose --profile setup run --rm publisher 2>&1 || true
  sleep 1
  pass "Pacote @demo-lab/supply-chain-demo publicado no Verdaccio (ou já existia)"
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
  docker compose down --volumes --remove-orphans
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
    local vulns
    vulns=$(grep -oP '\d+ vulnerabilit' "$EVIDENCE/T3a-npm-audit/npm-audit.txt" | head -1 || echo "?")
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
    pass "RESULTADO: relatório gerado — $vulns pacotes com findings"
  else
    info "RESULTADO: sem ficheiro JSON — sem vulnerabilidades ou erro"
  fi
  timer_end
  info "Evidências: evidence/T3b-osv-scanner/"
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
  set -a; source "$SCRIPT_DIR/.env"; set +a

  docker compose --profile analysis run --rm snyk

  sep
  if grep -q "lodash" "$EVIDENCE/T3c-snyk/snyk.txt" 2>/dev/null; then
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

# ─── T6: SONATYPE ─────────────────────────────────────────────────────────────

t6() {
  banner
  header "T6 — Sonatype Nexus Repository OSS"
  info "T6 requer configuração manual do proxy npm no UI do Nexus."
  info "Arrancar: docker compose -f docker-compose.yml -f docker-compose.sonatype.yml up -d sonatype verdaccio exfil-server"
  info "UI disponível em: http://localhost:8081"
  info "Ver: .specs/features/lab-environment/2026-04-11-lab-implementation-plan.md (Task 12)"
}

# ─── ALL ──────────────────────────────────────────────────────────────────────

all() {
  banner; preflight
  setup
  t1; t2; t3a; t3b
  if [ -n "${SNYK_TOKEN:-}" ]; then t3c; else log "T3c ignorado (sem SNYK_TOKEN)"; fi
  if [ -n "${SOCKET_TOKEN:-}" ] && [ -n "${SOCKET_ORG:-}" ]; then t4; else log "T4 ignorado (sem SOCKET_TOKEN/SOCKET_ORG)"; fi
  t5
  sep
  log "Suite completa. Evidências em:"
  for dir in "$EVIDENCE"/T*/; do
    [ -d "$dir" ] && echo "  $(basename "$dir")"
  done
  info "T6 (Sonatype) requer configuração manual — ver ./run-test.sh T6"
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
    echo "    T6        Sonatype Nexus OSS (configuração manual)"
    echo "    all       T1–T5 em sequência"
    echo
    exit 1
    ;;
esac
