# Gestão Segura de Dependências de Software — Componente Prática

Trabalho final da UC Desenvolvimento de Código Seguro — MEI ISCTE, 2025/2026.

> **"Gestão Segura de Dependências de Software: Análise de Práticas, Ferramentas e Falhas no Ecossistema NPM"**

---

## Guia do Projeto

Este repositório tem **três componentes distintos**, que em conjunto demonstram o ciclo completo: ataque → detecção → resposta.

| Componente    | Directório           | O que demonstra                                                                  |
| ------------- | -------------------- | -------------------------------------------------------------------------------- |
| **Lab**       | `lab/` + `evidence/` | Cenário de ataque controlado e avaliação de 6 ferramentas de segurança (T1–T6)   |
| **Protótipo** | `prototype/`         | Pipeline de segurança integrada recomendada para uma PME (VoIP Manager API)      |
| **CI/CD**     | `.github/workflows/` | Pipeline GitHub Actions real — detecta CVEs, cria Issue de alerta, falha o build |

### Como avaliar cada componente

**1. Lab (resultados já disponíveis — não requer execução)**
Os resultados de todos os testes estão em `evidence/`. Para cada ferramenta existe um directório com o output original capturado. Consultar directamente sem necessidade de correr Docker.

**2. Protótipo — pipeline em funcionamento no GitHub**
Ir ao separador **[Actions](../../actions)** deste repositório:
- Branch `main` → ver runs anteriores com pipeline **vermelha** (CVEs detectados em `lodash@4.17.11`)
- Branch `fix-test` → ver run com pipeline **verde** (dependências corrigidas, zero CVEs)
- Separador **[Issues](../../issues)** → ver issue de alerta criada automaticamente com tabela estruturada de vulnerabilidades

**3. Protótipo — correr localmente (opcional)**
Ver secção [Como correr o protótipo](#como-correr-o-protótipo) abaixo.

---

## O Laboratório

### O que demonstra

O lab confronta duas ameaças de supply chain com seis ferramentas de segurança:

| Ameaça                  | Pacote                              | Natureza                                                          |
| ----------------------- | ----------------------------------- | ----------------------------------------------------------------- |
| Zero-day comportamental | `@demo-lab/supply-chain-demo@1.0.0` | `postinstall` exfiltra `process.env` via HTTP — sem CVE registado |
| CVE conhecido           | `lodash@4.17.11`                    | Prototype pollution / code injection — 7 GHSAs, CVSS 9.1          |

### Resultados

| Teste | Ferramenta             | Paradigma              |       lodash@4.17.11       |           Ataque postinstall           |
| ----- | ---------------------- | ---------------------- | :------------------------: | :------------------------------------: |
| T1    | Baseline (npm install) | —                      |         instalado          | **EXECUTOU** — credenciais exfiltradas |
| T2    | Syft                   | SBOM                   |        inventariado        |       inventariado (sem alerta)        |
| T3a   | npm audit              | SCA reactivo           |   **detectado** (7 CVEs)   |        não detectado (sem CVE)         |
| T3b   | OSV Scanner            | SCA reactivo           |   **detectado** (7 CVEs)   |        não detectado (sem CVE)         |
| T3c   | Snyk                   | SCA reactivo           | **detectado** (9 findings) |        não detectado (sem CVE)         |
| T4    | Socket.dev             | Comportamental         |  detectado (npm público)   |    não detectado (registry privado)    |
| T5    | pnpm v10               | Arquitectural          |         instalado          |              **BLOQUEOU**              |
| T6    | Dependency-Track       | Monitorização contínua |  **7 CVEs** (2 CRITICAL)   |    0 findings (sem CVE — esperado)     |

**Conclusão central:** ferramentas SCA reactivas detectam CVEs conhecidos mas são cegas a zero-days comportamentais. Apenas o pnpm v10 (prevenção arquitectural) bloqueou o ataque. O Dependency-Track fecha o ciclo com monitorização contínua sem re-scanning.

Evidências completas em `evidence/` — um directório por teste com o output original das ferramentas.

### Arquitectura do lab

```
┌──────────────────────────────────────────────────────┐
│  lab-net (internal — sem saída para internet)        │
│                                                      │
│  ┌──────────┐   ┌──────────┐   ┌────────────────┐   │
│  │ verdaccio│   │ test-app │   │  exfil-server  │   │
│  │  :4873   │   │ Express  │   │     :9999      │   │
│  └──────────┘   └──────────┘   └────────────────┘   │
│   registry local  instala deps   regista dados       │
│   + proxy npmjs   (demo+lodash)  exfiltrados         │
└──────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────┐
│  public-net (com internet)                           │
│  syft │ npm-audit │ osv-scanner │ snyk │ socket-cli  │
│  (montam lab/test-app como volume read-only)         │
└──────────────────────────────────────────────────────┘
```

### Como correr o lab (requer Docker Desktop)

```bash
# Pré-requisito: copiar credenciais
cp .env.example .env   # preencher SNYK_TOKEN, SOCKET_TOKEN, SOCKET_ORG, DT_ADMIN_PASSWORD

# Arrancar infra e publicar pacote demo
./run-test.sh setup

# Testes individuais
./run-test.sh T1    # baseline — postinstall executa e exfiltra
./run-test.sh T2    # Syft — gera SBOM CycloneDX
./run-test.sh T3a   # npm audit
./run-test.sh T3b   # OSV Scanner (lockfile + SBOM)
./run-test.sh T3c   # Snyk (requer SNYK_TOKEN)
./run-test.sh T4    # Socket.dev (requer SOCKET_TOKEN + SOCKET_ORG)
./run-test.sh T5    # pnpm v10 — bloqueia postinstall
./run-test.sh T6    # Dependency-Track — monitorização contínua

# Suite completa
set -a; source .env; set +a
./run-test.sh all
```

---

## O Protótipo

### O que demonstra

Uma proposta de pipeline de segurança integrada para uma PME. A aplicação de demonstração é a **VoIP Manager API**: que consiste em um produto fictício composto por um backend Node.js que gere extensões, troncos SIP e registos de chamadas (CDR) de uma infraestrutura Asterisk.

### A pipeline de segurança (GitHub Actions)

A pipeline corre automaticamente em qualquer commit que altere `prototype/`. Implementa quatro camadas de defesa:

```
commit → GitHub Actions
          │
          ├─ pnpm install --ignore-scripts   [Camada 1: Prevenção]
          │   Lifecycle scripts bloqueados — postinstall malicioso não executa
          │
          ├─ OSV Scanner (pnpm-lock.yaml)    [Camada 2: Detecção]
          │   Detecta CVEs conhecidos — lodash@4.17.11 tem 7 CVEs
          │
          ├─ Syft → sbom.cdx.json            [Camada 3: Inventário]
          │   Gera SBOM CycloneDX como artefacto do run
          │
          └─ CVEs encontrados?
              Não → ✅ Pipeline verde
              Sim → Issue de alerta criada/atualizada no GitHub
                    🔴 Pipeline vermelha (build falha)
```

**Alerta sem configuração:** a issue é criada com `GITHUB_TOKEN` automático do GitHub Actions. A tabela na issue inclui: pacote, GHSA, CVE, CVSS, severidade, descrição e versão corrigida.

### O ciclo detectar → corrigir → verificar

O repositório demonstra o ciclo completo em duas branches:

| Branch     | Estado da pipeline | O que mostra                                                                 |
| ---------- | ------------------ | ---------------------------------------------------------------------------- |
| `main`     | 🔴 Vermelha         | Dependências vulneráveis e issue de alerta aberta                            |
| `fix-test` | 🟢 Verde            | lodash actualizado para `^4.18.0` e zero CVEs detectados no momento do teste |

> Para reproduzir a correcção: criar uma branch, actualizar `lodash` em `prototype/app/package.json` para `^4.18.0`, regenerar o `pnpm-lock.yaml` e fazer push. A pipeline corre automaticamente e passa.

### Como correr o protótipo localmente (opcional)

```bash
# 1. Correr a API
cd prototype/app
node src/index.js   # API disponível em http://localhost:3000

# Endpoints principais:
# POST /auth/register   → criar conta
# POST /auth/login      → obter JWT
# GET  /api/extensions  → listar extensões (requer JWT)
# GET  /api/calls/stats → estatísticas CDR agregadas

# 2. Monitorização contínua com Dependency-Track (requer Docker)
cd prototype
cp ../.env .env        # reutiliza DT_ADMIN_PASSWORD
docker compose up -d
# Aguardar ~60s → abrir http://localhost:8080
# Carregar o SBOM gerado pela pipeline (artefacto sbom-voip-manager)
```

---

## Estrutura do repositório

```
CODE/
├── .github/
│   └── workflows/
│       └── security-pipeline.yml ← pipeline CI/CD (OSV + Syft + Issue alert)
├── .env.example                  ← template de credenciais
├── docker-compose.yml            ← infra do lab + ferramentas de análise
├── run-test.sh                   ← orquestrador dos testes T1–T6
├── scripts/
│   └── sbom-reader.js            ← leitura legível do SBOM CycloneDX
├── lab/                          ← cenário de ataque
│   ├── verdaccio/                ← registry npm local
│   ├── supply-chain-demo/        ← pacote malicioso (@demo-lab/supply-chain-demo)
│   ├── test-app/                 ← app Express alvo
│   └── exfil-server/             ← servidor que regista exfiltrações
├── evidence/                     ← output capturado dos testes T1–T6
│   ├── T1-baseline/
│   ├── T2-syft/
│   ├── T3a-npm-audit/
│   ├── T3b-osv-scanner/
│   ├── T3b-osv-sbom/
│   ├── T3c-snyk/
│   ├── T4-socket/
│   ├── T5-pnpm/
│   └── T6-dependencytrack/
└── prototype/                    ← pipeline PME recomendada
    ├── app/                      ← VoIP Manager API (Express + SQLite + JWT)
    └── docker-compose.yml        ← Dependency-Track
```

---

## Credenciais (`.env`)

Necessárias apenas para correr o lab localmente. Copiar `.env.example` para `.env` e preencher:

| Variável            | Onde obter                                                         |
| ------------------- | ------------------------------------------------------------------ |
| `SNYK_TOKEN`        | [app.snyk.io](https://app.snyk.io) → Account Settings → Auth Token |
| `SOCKET_TOKEN`      | [socket.dev](https://socket.dev) → Settings → API Tokens           |
| `SOCKET_ORG`        | slug da organização no URL do Socket.dev                           |
| `DT_ADMIN_PASSWORD` | password à escolha para o Dependency-Track local                   |
