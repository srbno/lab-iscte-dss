# Lab — Gestão Segura de Dependências de Software

Componente prático do trabalho "Gestão Segura de Dependências de Software: Análise de Práticas, Ferramentas e Falhas no Ecossistema NPM" (MEI ISCTE, Desenvolvimento de Código Seguro, 2025/2026).

O laboratório demonstra empiricamente como um pacote NPM com script `postinstall` malicioso exfiltra variáveis de ambiente — e avalia o comportamento de seis ferramentas de segurança face a esse ataque.

---

## Pré-requisitos

- Docker Desktop em execução
- `CODE/.env` preenchido a partir de `CODE/.env.example` (ver secção Credenciais)

Nada é instalado no sistema operativo do utilizador — todas as ferramentas correm em containers.

---

## Arquitectura

```
┌─────────────────────────────────────────────────────┐
│  lab-net (internal: true — sem acesso à internet)   │
│                                                     │
│  ┌──────────┐   ┌──────────┐   ┌────────────────┐  │
│  │ verdaccio│   │ test-app │   │  exfil-server  │  │
│  │  :4873   │   │ Express  │   │     :9999      │  │
│  └──────────┘   └──────────┘   └────────────────┘  │
│   registry       instala o        recebe POSTs      │
│   local          pacote demo      do postinstall    │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│  rede Docker padrão (com internet)                  │
│                                                     │
│  syft │ npm-audit │ osv-scanner │ snyk │ socket-cli │
│       (montam lab/test-app como volume read-only)   │
└─────────────────────────────────────────────────────┘
```

**Cenário simulado:** uma PME sem registry privado. O Verdaccio representa o npmjs.com onde um pacote comprometido foi publicado. O `test-app` representa o ambiente de desenvolvimento ou CI/CD da empresa.

---

## Pacote demo

**`@demo-lab/supply-chain-demo@1.0.0`** — em `lab/supply-chain-demo/`

O script `postinstall` simula um ataque de supply chain real: explora o ambiente de forma cega (sem conhecer os nomes das variáveis) e envia `process.env` completo por HTTP POST para o `exfil-server`. O `test-app` tem variáveis de ambiente fake que representam os tipos de credenciais visadas por ataques reais (AWS keys, tokens de CI/CD, URLs de base de dados).

---

## Estrutura de directórios

```
CODE/
├── .env.example                  ← template de credenciais (sem valores)
├── .env                          ← credenciais reais (não commitado)
├── docker-compose.yml            ← infra principal + ferramentas de análise
├── docker-compose.sonatype.yml   ← overlay para T6 (Sonatype Nexus)
├── run-test.sh                   ← orquestrador de testes
├── lab/
│   ├── verdaccio/config.yaml     ← configuração do registry local
│   ├── supply-chain-demo/        ← pacote malicioso demo
│   ├── test-app/                 ← aplicação Express alvo
│   └── exfil-server/             ← servidor que regista dados exfiltrados
└── evidence/
    ├── lab-results.txt           ← resumo de todos os testes
    ├── summary.txt               ← output completo da suite
    ├── T1-baseline/
    ├── T2-syft/
    ├── T3a-npm-audit/
    ├── T3b-osv-scanner/
    ├── T3c-snyk/
    ├── T4-socket/
    ├── T5-pnpm/
    └── T6-sonatype/
```

---

## Como correr

### Primeira vez (setup)

```bash
# Arrancar infra e publicar o pacote demo no Verdaccio
./run-test.sh setup
```

### Executar um teste individual

```bash
./run-test.sh T1    # baseline — npm install sem protecção
./run-test.sh T2    # Syft — geração de SBOM
./run-test.sh T3a   # npm audit
./run-test.sh T3b   # OSV Scanner
./run-test.sh T3c   # Snyk (requer SNYK_TOKEN no .env)
./run-test.sh T4    # Socket.dev (requer SOCKET_TOKEN + SOCKET_ORG no .env)
./run-test.sh T5    # pnpm v10
```

### Executar a suite completa

```bash
set -a; source .env; set +a   # carregar tokens antes de T3c e T4
./run-test.sh all
```

### T6 — Sonatype (requer setup manual)

```bash
# Arrancar Nexus (demora ~3 minutos a iniciar)
docker compose -f docker-compose.yml -f docker-compose.sonatype.yml up -d sonatype verdaccio exfil-server

# Obter password inicial do admin
docker exec $(docker compose -f docker-compose.yml -f docker-compose.sonatype.yml ps -q sonatype) \
  cat /nexus-data/admin.password

# Aceder ao UI em http://localhost:8081 e configurar proxy npm apontando para http://verdaccio:4873
```

### Parar tudo

```bash
docker compose down          # infra principal
docker compose -f docker-compose.yml -f docker-compose.sonatype.yml down -v   # incluindo Sonatype
```

---

## Credenciais (`CODE/.env`)

Copiar `.env.example` para `.env` e preencher:

| Variável | Onde obter |
|----------|-----------|
| `SNYK_TOKEN` | [app.snyk.io](https://app.snyk.io) → Account Settings → Auth Token |
| `SOCKET_TOKEN` | [socket.dev](https://socket.dev) → Settings → API Tokens |
| `SOCKET_ORG` | slug da organização no URL do Socket.dev |
| `SONATYPE_PASS` | definida ao configurar o Nexus pela primeira vez |

---

## Resultados

| Teste | Ferramenta | Resultado |
|-------|-----------|-----------|
| T1 | Baseline (npm install) | Ataque executou — credenciais exfiltradas |
| T2 | Syft | Inventariou o pacote no SBOM |
| T3a | npm audit | 0 vulnerabilidades (sem CVE) |
| T3b | OSV Scanner | 0 vulnerabilidades (sem CVE) |
| T3c | Snyk | 0 vulnerabilidades (sem CVE) |
| T4 | Socket.dev | Não detetou — pacote em registry privado não indexado |
| T5 | pnpm v10 | Bloqueou — "Ignored build scripts" |
| T6 | Sonatype Nexus OSS | Não bloqueou — Community Edition sem firewall comportamental |

Evidências completas em `evidence/`. Resumo em `evidence/lab-results.txt`.
