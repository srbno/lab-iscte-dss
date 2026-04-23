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

> Os slides da apresentação do trabalho podem ser acedidos pelo ficheiro [`Gestão Segura de Dependências de Software.pptx`](<Gestão Segura de Dependências de Software.pptx>).

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

# Carregar credenciais para a sessão actual
set -a; source .env; set +a

# Arrancar infra e publicar pacote demo
./run-test.sh setup

# Suite completa
./run-test.sh all

# Caso deseje correr testes individualmente
./run-test.sh T1    # baseline — postinstall executa e exfiltra
./run-test.sh T2    # Syft — gera SBOM CycloneDX
./run-test.sh T3a   # npm audit
./run-test.sh T3b   # OSV Scanner (lockfile + SBOM)
./run-test.sh T3c   # Snyk (requer SNYK_TOKEN)
./run-test.sh T4    # Socket.dev (requer SOCKET_TOKEN + SOCKET_ORG)
./run-test.sh T5    # pnpm v10 — bloqueia postinstall
./run-test.sh T6    # Dependency-Track — monitorização contínua

# Simular primeira execução do lab a partir de ambiente Docker limpo
./run-test.sh reset
docker network rm lab-projeto-dss_default 2>/dev/null || true

# O reset remove containers, redes e volumes Docker do lab.
# Isto apaga o estado persistente do Verdaccio e do Dependency-Track,
# mas não apaga os ficheiros em evidence/.
```

---

## O Protótipo

### O que demonstra

Uma proposta de pipeline de segurança integrada para uma PME. A aplicação de demonstração é a **VoIP Manager API**: um backend Node.js que gere extensões, troncos SIP e registos de chamadas (CDR) de uma infraestrutura Asterisk.

### Ferramentas seleccionadas para o protótipo

Das seis ferramentas avaliadas no lab (T1–T6), quatro foram integradas no protótipo. A tabela abaixo justifica cada decisão.

| Ferramenta       | Paradigma               |  No protótipo  | Justificação                                                                                                                                                                                                                                                   |
| ---------------- | ----------------------- | :------------: | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| pnpm v10         | Prevenção arquitectural |   ✅ Camada 1   | Único controlo que bloqueou o ataque zero-day (T5). Recusa *lifecycle scripts* por omissão, sem depender de qualquer base de dados. Sem custo, sem conta.                                                                                                      |
| OSV Scanner      | SCA reactivo            |   ✅ Camada 2   | Detecta CVEs conhecidos (7 para `lodash@4.17.11`, T3b). Gratuito, sem conta, base de dados OSV/Google. Usa apenas `GITHUB_TOKEN` automático — sem configuração de *secrets*.                                                                                   |
| Syft             | Inventário SBOM         |   ✅ Camada 3   | Gera SBOM CycloneDX (72 componentes, T2). Acção oficial `anchore/sbom-action`; output compatível com Dependency-Track. Gratuito, sem conta.                                                                                                                    |
| Dependency-Track | Monitorização contínua  |   ✅ Opcional   | Alerta sobre novos CVEs em dependências já instaladas, sem novo scan (T6). Requer instância persistente — não integrado no CI/CD; disponível como complemento local.                                                                                           |
| npm audit        | SCA reactivo            | ❌ Substituído  | Resultados equivalentes ao OSV Scanner (7 CVEs, T3a). O OSV Scanner tem base de dados mais abrangente, não depende do npm registry e produz JSON estruturado de melhor qualidade.                                                                              |
| Snyk             | SCA reactivo            | ❌ Não incluído | Modelo freemium com limites de uso e de funcionalidades na versão gratuita, o que compromete a adopção sustentada por uma PME. Detectou 9 *findings* vs. 7 do OSV Scanner, mas a diferença não justifica a dependência operacional de um serviço proprietário. |
| Socket.dev       | Comportamental          | ❌ Não incluído | Cobertura limitada ao registry npm público — não analisou o pacote demo alojado no Verdaccio privado (T4). A capacidade comportamental, embora conceptualmente relevante, não é exercível sem publicação pública dos pacotes.                                  |

### A pipeline de segurança (GitHub Actions)

A pipeline corre automaticamente em qualquer commit que altere `prototype/`. Implementa três camadas automatizadas de defesa:

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

> **Nota — Dependency-Track:** o DT **não faz parte da pipeline automatizada**. É usado no lab como T6 (avaliação da ferramenta de monitorização contínua) e está disponível como complemento opcional do protótipo (ver abaixo). A separação é intencional: o DT requer uma instância persistente acessível a partir do GitHub Actions, o que foge ao âmbito deste protótipo académico.

### O ciclo detectar → corrigir → verificar

O repositório demonstra o ciclo completo em duas branches:

| Branch     | Estado da pipeline | O que mostra                                                                 |
| ---------- | ------------------ | ---------------------------------------------------------------------------- |
| `main`     | 🔴 Vermelha         | Dependências vulneráveis e issue de alerta aberta                            |
| `fix-test` | 🟢 Verde            | lodash actualizado para `^4.18.0` e zero CVEs detectados no momento do teste |

> Para reproduzir a correcção: criar uma branch, actualizar `lodash` em `prototype/app/package.json` para `^4.18.0`, regenerar o `pnpm-lock.yaml` e fazer push. A pipeline corre automaticamente e passa.

### Monitorização contínua — Dependency-Track 

O Dependency-Track não faz parte da pipeline CI/CD mas complementa-a como camada de monitorização contínua: recebe o SBOM gerado pela pipeline e alerta quando são publicadas novas CVEs para os componentes já instalados — sem necessitar de novo scan.

```bash
# Arrancar o Dependency-Track localmente (requer Docker)
cd prototype
docker compose up -d
# Aguardar ~60s → abrir http://localhost:8080

# Primeiro acesso à UI:
# username: admin
# password: admin
# O Dependency-Track obriga a trocar a password inicial.
# Depois pode também criar outro utilizador administrativo.

# Após a pipeline correr no GitHub Actions:
# 1. Descarregar o artefacto "sbom-voip-manager" do run
# 2. No DT: Projects → voip-manager-api → Components → Upload BOM
# 3. Aguardar ~30s → ver findings em Vulnerabilities (7 CVEs do lodash)
```

> Esta é a mesma ferramenta avaliada no lab como **T6**. Os resultados do T6 (2 CRITICAL, 2 HIGH, 3 MEDIUM em lodash@4.17.11) estão em `evidence/T6-dependencytrack/`.

---

## Estrutura do repositório

```
CODE/
├── .github/
│   └── workflows/
│       └── security-pipeline.yml ← pipeline CI/CD (OSV + Syft + Issue alert)
├── .env.example                  ← template de credenciais
├── Gestão Segura de Dependências de Software.pptx ← slides de apresentação do projeto
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
    └── docker-compose.yml        ← Dependency-Track (complemento opcional — monitorização contínua)
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
