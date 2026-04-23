# VoIP Manager API — Protótipo de Pipeline de Segurança PME

Protótipo que demonstra a pipeline de segurança de dependências recomendada para uma PME.

A **VoIP Manager API** é um backend Node.js que gere extensões, troncos SIP e registos de chamadas (CDR) de uma infraestrutura VoIP sobre Asterisk. Representa uma aplicação real de uma PME — o seu código-fonte está protegido pela pipeline de segurança descrita neste documento.

---

## Estrutura

```
prototype/
├── app/
│   ├── src/
│   │   ├── index.js            ← Express entry point
│   │   ├── db.js               ← SQLite (better-sqlite3) + schema
│   │   ├── middleware/
│   │   │   └── auth.js         ← JWT middleware
│   │   └── routes/
│   │       ├── auth.js         ← POST /auth/register, /auth/login
│   │       ├── extensions.js   ← CRUD /api/extensions
│   │       ├── trunks.js       ← CRUD /api/trunks (admin only)
│   │       └── calls.js        ← /api/calls + /api/calls/stats
│   ├── package.json
│   └── pnpm-lock.yaml
└── docker-compose.yml          ← Dependency-Track (monitorização contínua)
```

---

## API

### Autenticação

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| POST | `/auth/register` | Cria conta (email + password ≥ 8 chars, role: admin\|operator) |
| POST | `/auth/login` | Devolve JWT (válido 8h) |

Todos os outros endpoints requerem `Authorization: Bearer <token>`.

### Extensões

| Método | Endpoint | Acesso |
|--------|----------|--------|
| GET | `/api/extensions` | todos |
| GET | `/api/extensions/:id` | todos |
| POST | `/api/extensions` | todos autenticados |
| PUT | `/api/extensions/:id` | todos autenticados |
| DELETE | `/api/extensions/:id` | todos autenticados |

Filtro opcional: `GET /api/extensions?status=active`

### Troncos SIP

| Método | Endpoint | Acesso |
|--------|----------|--------|
| GET | `/api/trunks` | todos autenticados |
| GET | `/api/trunks/:id` | todos autenticados |
| POST | `/api/trunks` | admin only |
| PUT | `/api/trunks/:id` | admin only |
| DELETE | `/api/trunks/:id` | admin only |

### Registos de Chamadas (CDR)

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| GET | `/api/calls` | CDR com filtros: `extension`, `status`, `from`, `to`, `limit` |
| GET | `/api/calls/stats` | Estatísticas agregadas por extensão e estado |
| GET | `/api/calls/:id` | Detalhe de uma chamada |
| POST | `/api/calls` | Registar chamada (ex: via Asterisk AGI) |

---

## Correr localmente

```bash
cd prototype/app
corepack enable
pnpm install
pnpm run start   # API disponível em http://localhost:3000
```

> A base de dados SQLite é criada em `prototype/app/data/voip.db` na primeira execução.
> Se surgir erro de bindings do `better-sqlite3`, usar Node.js LTS (20/22) e reconstruir a dependência nativa com `pnpm rebuild better-sqlite3`. O CI usa `pnpm install --ignore-scripts` de propósito para demonstrar bloqueio de lifecycle scripts; para correr a API localmente, o módulo SQLite nativo precisa de build.

---

## Pipeline de Segurança (GitHub Actions)

A pipeline em `.github/workflows/security-pipeline.yml` corre automaticamente em qualquer push que altere ficheiros em `prototype/`.

```
commit → GitHub Actions
          │
          ├─ pnpm install --ignore-scripts    [Camada 1: Prevenção]
          │   lifecycle scripts bloqueados — postinstall malicioso não executa
          │
          ├─ OSV Scanner (pnpm-lock.yaml)     [Camada 2: Detecção]
          │   verifica CVEs conhecidos na base de dados OSV/Google
          │
          ├─ Syft → sbom.cdx.json             [Camada 3: Inventário]
          │   gera SBOM CycloneDX como artefacto do run
          │
          └─ CVEs encontrados?
              Não → ✅ Pipeline verde
              Sim → Issue de alerta criada/actualizada no GitHub  [Alerta]
                    🔴 Pipeline vermelha (build falha)
```

**Sem configuração de secrets:** a issue é criada com o `GITHUB_TOKEN` automático do GitHub Actions. Não é necessário configurar nenhum secret adicional no repositório.

---

## Monitorização Contínua — Dependency-Track

O Dependency-Track complementa a pipeline CI: monitoriza continuamente o SBOM gerado e alerta quando são publicados novos CVEs para os componentes em uso — sem necessidade de novo scan.

```bash
# Arrancar o DT localmente
cd prototype
docker compose up -d
# Aguardar ~60s → abrir http://localhost:8080

# Primeiro acesso à UI:
# username: admin
# password: admin
# O Dependency-Track obriga a trocar a password inicial.
# Depois pode também criar outro utilizador administrativo.
```

Após a pipeline GitHub Actions correr:
1. Descarregar o artefacto `sbom-voip-manager` (ficheiro `sbom.cdx.json`)
2. No DT: **Projects → Create Project → voip-manager-api**
3. **Components → Upload BOM** → seleccionar `sbom.cdx.json`
4. Aguardar processamento (~30s) → ver findings em **Vulnerabilities**

> O DT detectará os 7 CVEs do `lodash@4.17.11` (2 CRITICAL, 2 HIGH, 3 MEDIUM).
