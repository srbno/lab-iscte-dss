#!/usr/bin/env node
/**
 * sbom-reader.js — Lê um SBOM CycloneDX JSON e imprime uma tabela legível.
 * Uso: node scripts/sbom-reader.js [caminho-para-sbom.json]
 */

const fs = require('fs');
const path = require('path');

const sbomPath = process.argv[2] || path.join(__dirname, '../evidence/T2-syft/sbom.json');

if (!fs.existsSync(sbomPath)) {
  console.error(`Erro: ficheiro não encontrado — ${sbomPath}`);
  process.exit(1);
}

const sbom = JSON.parse(fs.readFileSync(sbomPath, 'utf8'));
const components = sbom.components || [];

// Separa o componente raiz (o próprio projecto) dos pacotes
const packages = components.filter(c => c.type === 'library');
const files    = components.filter(c => c.type === 'file');

// Ordena por nome
packages.sort((a, b) => a.name.localeCompare(b.name));

// ─── Cabeçalho ────────────────────────────────────────────────────────────────
console.log('\n══════════════════════════════════════════════════════════════');
console.log(`  SBOM — ${sbom.metadata?.component?.name || sbomPath}`);
console.log(`  Gerado em: ${sbom.metadata?.timestamp || 'desconhecido'}`);
console.log(`  Ferramenta: ${sbom.metadata?.tools?.components?.[0]?.name} ${sbom.metadata?.tools?.components?.[0]?.version || ''}`);
console.log(`  Total de pacotes: ${packages.length}`);
console.log('══════════════════════════════════════════════════════════════\n');

// ─── Tabela de pacotes ────────────────────────────────────────────────────────
const COL_NAME    = 40;
const COL_VERSION = 12;
const COL_LICENSE = 12;

const pad = (str, len) => String(str || '').padEnd(len).slice(0, len);

console.log(
  pad('Pacote', COL_NAME) + ' ' +
  pad('Versão', COL_VERSION) + ' ' +
  pad('Licença', COL_LICENSE)
);
console.log('─'.repeat(COL_NAME + COL_VERSION + COL_LICENSE + 2));

for (const pkg of packages) {
  const license = pkg.licenses?.[0]?.license?.id || '—';
  const flag    = pkg.name === '@demo-lab/supply-chain-demo' ? ' ⚠ DEMO MALICIOSO' :
                  pkg.name === 'lodash' && pkg.version === '4.17.11' ? ' ⚠ CVE CONHECIDO' : '';

  console.log(
    pad(pkg.name, COL_NAME) + ' ' +
    pad(pkg.version, COL_VERSION) + ' ' +
    pad(license, COL_LICENSE) +
    flag
  );
}

// ─── Dependências directas ────────────────────────────────────────────────────
const rootDeps = sbom.dependencies?.find(d => d.ref?.includes('test-app'));
if (rootDeps?.dependsOn?.length) {
  console.log('\n── Dependências directas do test-app ──────────────────────');
  for (const dep of rootDeps.dependsOn) {
    // extrai nome@versão do purl
    const match = dep.match(/pkg:npm\/(.+?)@([^?]+)/);
    if (match) console.log(`  • ${decodeURIComponent(match[1])}@${match[2]}`);
  }
}

console.log('\n');
