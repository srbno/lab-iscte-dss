#!/bin/bash
# run-test.sh — orquestrador dos testes do lab de supply chain security
# Uso: ./run-test.sh [setup|T1|T2|T3a|T3b|T3c|T4|T5|T6|all]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EVIDENCE="$SCRIPT_DIR/evidence"

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
pass() { echo "  ✓ $*"; }
fail() { echo "  ✗ $*"; }
sep()  { echo; echo "$(printf '─%.0s' {1..60})"; echo; }

# ─── SETUP ────────────────────────────────────────────────────────────────────

setup() {
  sep
  log "SETUP: A iniciar infra e publicar pacote demo..."
  docker compose up -d verdaccio exfil-server
  sleep 4
  docker compose --profile setup run --rm publisher
  sleep 1
  log "Setup completo."
}

# ─── T1: BASELINE ─────────────────────────────────────────────────────────────

t1() {
  sep
  log "T1: Baseline — npm install sem protecção"
  mkdir -p "$EVIDENCE/T1-baseline"

  # Limpar logs anteriores do exfil-server
  docker compose restart exfil-server
  sleep 2

  # Instalar o pacote demo (dispara o postinstall)
  # Instala numa diretoria limpa (/install) para evitar resolver deps do express
  # sem acesso à internet (lab-net é internal:true).
  log "A executar npm install..."
  docker compose run --rm -T test-app \
    sh -c "mkdir -p /install && cd /install && echo '{\"dependencies\":{\"@demo-lab/supply-chain-demo\":\"1.0.0\"}}' > package.json && npm install --@demo-lab:registry=http://verdaccio:4873" \
    2>&1 | tee "$EVIDENCE/T1-baseline/npm-install.txt"

  sleep 2

  # Capturar logs do exfil-server
  docker compose logs exfil-server > "$EVIDENCE/T1-baseline/exfil-server.txt"

  if grep -q "EXFILTRATION RECEIVED" "$EVIDENCE/T1-baseline/exfil-server.txt"; then
    pass "exfil-server recebeu dados — postinstall executou com sucesso"
  else
    fail "exfil-server NÃO recebeu dados — verificar configuração"
  fi

  log "Evidências: evidence/T1-baseline/"
}

# ─── T2: SYFT ────────────────────────────────────────────────────────────────

t2() {
  sep
  log "T2: Syft — geração de SBOM"
  mkdir -p "$EVIDENCE/T2-syft"

  docker compose --profile analysis run --rm syft

  if [ -f "$EVIDENCE/T2-syft/sbom.json" ]; then
    pass "SBOM gerado: evidence/T2-syft/sbom.json"
    if grep -q "supply-chain-demo" "$EVIDENCE/T2-syft/sbom.json"; then
      pass "Pacote demo consta do inventário"
    else
      fail "Pacote demo NÃO encontrado no SBOM"
    fi
  else
    fail "SBOM não foi gerado"
  fi
}

# ─── T3a: NPM AUDIT ───────────────────────────────────────────────────────────

t3a() {
  sep
  log "T3a: npm audit — SCA reativo"
  mkdir -p "$EVIDENCE/T3a-npm-audit"

  docker compose --profile analysis run --rm npm-audit

  if grep -q "found 0 vulnerabilities" "$EVIDENCE/T3a-npm-audit/npm-audit.txt" 2>/dev/null; then
    pass "npm audit: 0 vulnerabilidades — comportamento esperado (sem CVE)"
  else
    log "npm audit: verificar output em evidence/T3a-npm-audit/npm-audit.txt"
  fi
}

# ─── T3b: OSV SCANNER ─────────────────────────────────────────────────────────

t3b() {
  sep
  log "T3b: OSV Scanner — SCA reativo"
  mkdir -p "$EVIDENCE/T3b-osv-scanner"

  docker compose --profile analysis run --rm osv-scanner 2>&1 || true
  # output escrito para /evidence/osv-scanner.json via volume mount

  if [ -f "$EVIDENCE/T3b-osv-scanner/osv-scanner.json" ]; then
    pass "OSV Scanner: relatório gerado"
  else
    log "OSV Scanner: verificar output — o ficheiro pode estar vazio se não foram encontradas vulnerabilidades"
  fi

  log "Evidências: evidence/T3b-osv-scanner/"
}

# ─── T3c: SNYK ────────────────────────────────────────────────────────────────

t3c() {
  sep
  log "T3c: Snyk — SCA reativo (base de dados proprietária)"

  if [ -z "${SNYK_TOKEN:-}" ]; then
    fail "SNYK_TOKEN não definido. Adicionar ao ficheiro .env e reexecutar."
    return 1
  fi

  mkdir -p "$EVIDENCE/T3c-snyk"
  set -a; source .env; set +a

  docker compose --profile analysis run --rm snyk

  log "Evidências: evidence/T3c-snyk/"
}

# ─── T4: SOCKET.DEV ───────────────────────────────────────────────────────────

t4() {
  sep
  log "T4: Socket.dev — análise comportamental"
  mkdir -p "$EVIDENCE/T4-socket"

  docker compose --profile analysis run --rm socket-cli

  log "Evidências: evidence/T4-socket/"
}

# ─── T5: PNPM V10 ─────────────────────────────────────────────────────────────

t5() {
  sep
  log "T5: pnpm v10 — bloqueio de lifecycle scripts"
  mkdir -p "$EVIDENCE/T5-pnpm"

  docker compose restart exfil-server
  sleep 2

  log "A executar pnpm install..."
  docker compose run --rm -T test-app \
    sh -c "mkdir -p /install-pnpm && cd /install-pnpm && echo '{\"dependencies\":{\"@demo-lab/supply-chain-demo\":\"1.0.0\"}}' > package.json && pnpm install --@demo-lab:registry=http://verdaccio:4873" \
    2>&1 | tee "$EVIDENCE/T5-pnpm/pnpm-install.txt"

  sleep 2

  # --since 15s: apenas logs após o restart do exfil-server (evita falsos positivos do T1)
  docker compose logs --since 15s exfil-server > "$EVIDENCE/T5-pnpm/exfil-server.txt"

  if grep -q "EXFILTRATION RECEIVED" "$EVIDENCE/T5-pnpm/exfil-server.txt"; then
    fail "INESPERADO: postinstall executou — pnpm não bloqueou"
  else
    pass "postinstall bloqueado pelo pnpm v10 — exfil-server não recebeu dados"
  fi

  log "Evidências: evidence/T5-pnpm/"
}

# ─── T6: SONATYPE ─────────────────────────────────────────────────────────────

t6() {
  sep
  log "T6: Sonatype Repository Firewall — bloqueio na entrada"
  log "Ver Task 12 do plano para configuração do Sonatype antes de executar este teste."
  log "Comando: docker compose -f docker-compose.yml -f docker-compose.sonatype.yml up -d sonatype"
}

# ─── ALL ──────────────────────────────────────────────────────────────────────

all() {
  setup
  t1; t2; t3a; t3b
  t3c || log "T3c ignorado (sem SNYK_TOKEN)"
  t4; t5
  sep
  log "Todos os testes concluídos. Resumo:"
  for dir in "$EVIDENCE"/*/; do
    echo "  $(basename "$dir")"
  done
  log "T6 (Sonatype) requer configuração manual — ver Task 12."
}

# ─── ROUTER ───────────────────────────────────────────────────────────────────

case "${1:-}" in
  setup) setup ;;
  T1|t1) setup; t1 ;;
  T2|t2) t2 ;;
  T3a|t3a) t3a ;;
  T3b|t3b) t3b ;;
  T3c|t3c) t3c ;;
  T4|t4) t4 ;;
  T5|t5) setup; t5 ;;
  T6|t6) t6 ;;
  all) all ;;
  *) echo "Uso: ./run-test.sh [setup|T1|T2|T3a|T3b|T3c|T4|T5|T6|all]"; exit 1 ;;
esac
