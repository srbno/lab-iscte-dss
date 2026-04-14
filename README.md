# Lab — Gestão Segura de Dependências de Software

Componente prático do trabalho "Gestão Segura de Dependências de Software: Análise de Práticas, Ferramentas e Falhas no Ecossistema NPM" (MEI ISCTE, Desenvolvimento de Código Seguro, 2025/2026).

O laboratório demonstra empiricamente dois tipos de ameaça de supply chain e avalia o comportamento de seis ferramentas de segurança face a cada uma:

| Ameaça | Pacote | Detecção esperada |
|--------|--------|-------------------|
| Zero-day comportamental | `@demo-lab/supply-chain-demo@1.0.0` — `postinstall` exfiltra `process.env` | Apenas ferramentas comportamentais |
| CVE conhecido | `lodash@4.17.11` — prototype pollution (7 GHSAs, CVSS 9.1) | Ferramentas SCA reativas |

---

## Pré-requisitos

- Docker Desktop em execução
- `CODE/.env` preenchido a partir de `CODE/.env.example` (ver secção Credenciais)

Nada é instalado no sistema operativo do utilizador — todas as ferramentas correm em containers.

---

## Arquitectura

```
┌─────────────────────────────────────────────────────┐
│  lab-net (internal: true — sem acesso directo à net)│
│                                                     │
│  ┌──────────┐   ┌──────────┐   ┌────────────────┐  │
│  │ verdaccio│   │ test-app │   │  exfil-server  │  │
│  │  :4873   │   │ Express  │   │     :9999      │  │
│  └──────────┘   └──────────┘   └────────────────┘  │
│   registry       instala as       recebe POSTs      │
│   local +        dependências     do postinstall    │
│   proxy npmjs    (demo+lodash)                      │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│  rede Docker padrão (com internet)                  │
│                                                     │
│  syft │ npm-audit │ osv-scanner │ snyk │ socket-cli │
│       (montam lab/test-app como volume read-only)   │
└─────────────────────────────────────────────────────┘
```

**Cenário simulado:** uma PME sem registry privado. O Verdaccio representa o npmjs.com onde um pacote comprometido foi publicado. O `test-app` representa o ambiente de desenvolvimento ou CI/CD da empresa. O Verdaccio serve o pacote demo localmente e faz proxy de pacotes públicos (lodash, express) via uplink npmjs.

---

## Pacotes do test-app

**`@demo-lab/supply-chain-demo@1.0.0`** (`lab/supply-chain-demo/`)
O script `postinstall` simula um ataque de supply chain real: explora o ambiente de forma cega (sem conhecer os nomes das variáveis) e envia `process.env` completo por HTTP POST para o `exfil-server`. O `test-app` tem variáveis de ambiente fake que representam os tipos de credenciais visadas por ataques reais (AWS keys, tokens de CI/CD, URLs de base de dados).

**`lodash@4.17.11`** (npm público, via proxy Verdaccio→npmjs)
Versão com múltiplos CVEs de prototype pollution e code injection. Incluída para que as ferramentas SCA reativas tenham algo a detectar, criando o contraste central do lab.

---

## Estrutura de directórios

```
CODE/
├── .env.example                  ← template de credenciais (sem valores)
├── .env                          ← credenciais reais (não commitado)
├── docker-compose.yml            ← infra principal + ferramentas de análise
├── run-test.sh                   ← orquestrador v2
├── lab/
│   ├── verdaccio/config.yaml     ← registry local com uplink npmjs
│   ├── supply-chain-demo/        ← pacote malicioso demo
│   ├── test-app/                 ← aplicação Express alvo (deps: demo + lodash)
│   └── exfil-server/             ← servidor que regista dados exfiltrados
└── evidence/
    ├── lab-results.txt           ← resumo completo dos testes v2
    ├── archive/                  ← evidências v1 arquivadas (não commitadas)
    ├── T1-baseline/
    ├── T2-syft/
    ├── T3a-npm-audit/
    ├── T3b-osv-scanner/
    ├── T3c-snyk/
    ├── T4-socket/
    └── T5-pnpm/
```

---

## Como correr

### Gestão da infra

```bash
./run-test.sh start      # arranca verdaccio e exfil-server
./run-test.sh setup      # publica pacote demo no Verdaccio (obrigatório antes de T1/T5)
./run-test.sh archive    # arquiva evidências actuais → evidence/archive/TIMESTAMP/
./run-test.sh reset      # docker compose down --volumes --remove-orphans
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

### Executar a suite completa (T1–T5)

```bash
set -a; source .env; set +a   # carregar tokens antes de T3c e T4
./run-test.sh all
```

---

## Credenciais (`CODE/.env`)

Copiar `.env.example` para `.env` e preencher:

| Variável | Onde obter |
|----------|-----------|
| `SNYK_TOKEN` | [app.snyk.io](https://app.snyk.io) → Account Settings → Auth Token |
| `SOCKET_TOKEN` | [socket.dev](https://socket.dev) → Settings → API Tokens |
| `SOCKET_ORG` | slug da organização no URL do Socket.dev |

---

## Resultados (v2)

| Teste | Ferramenta | Paradigma | lodash@4.17.11 | postinstall attack |
|-------|-----------|-----------|:--------------:|:-----------------:|
| T1 | Baseline (npm install) | — | instalado | **EXECUTOU** — 7 vars exfiltradas |
| T2 | Syft | SBOM | inventariado | inventariado (sem alerta) |
| T3a | npm audit | SCA reativo | **1 crítica** | não detectado (sem CVE) |
| T3b | OSV Scanner | SCA reativo | **7 vulns** | não detectado (sem CVE) |
| T3c | Snyk | SCA reativo | **9 vulns** | não detectado (sem CVE) |
| T4 | Socket.dev | Comportamental | detectado (npm público) | não detectado (registry privado) |
| T5 | pnpm v10 | Arquitectural | instalado | **BLOQUEOU** — "Ignored build scripts" |

Evidências completas em `evidence/`. Resumo detalhado em `evidence/lab-results.txt`.
