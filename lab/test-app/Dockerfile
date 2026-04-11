FROM node:20-alpine

# pnpm v10 disponível para o teste T5
RUN npm install -g pnpm@10

WORKDIR /app

# Instala apenas express durante o build; não copia package.json ainda para
# evitar que npm tente resolver @demo-lab/supply-chain-demo (não está no registry público).
# O pacote demo é instalado em runtime via Verdaccio durante os testes.
RUN npm install --ignore-scripts --registry https://registry.npmjs.org express

COPY . .
CMD ["node", "index.js"]
