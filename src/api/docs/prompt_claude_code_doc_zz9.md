# Documentar tabela ZZ9 (Intermediária NFe) no CLAUDE.md

## Contexto

Tabela `ZZ9` já foi criada no SIGACFG pelo José Carlos. Esta tarefa é só
**documentar a estrutura no `CLAUDE.md`** — nenhuma mudança de código
ainda. As mudanças que vão usar essa tabela de verdade (`FATPI01_V2`
gravando nela, Job novo pra classificar/rotear, `FATZZF01` liberando
produto pendente nela) ficam para uma próxima rodada, ainda não desenhada
em detalhe.

## O que adicionar ao CLAUDE.md

Uma seção nova, no mesmo formato/nível de detalhe das outras 6 tabelas
Muro já documentadas (`ZZA`-`ZZF`).

### Propósito
`ZZ9` é uma tabela intermediária, **exclusiva do domínio NFe**
(`ZZA`/`ZZB`/`ZZC`). Recebe todas as notas de NFe do iPaaS — com ou sem
produto pendente — antes de qualquer classificação por CFOP. Existe
porque o payload de aviso de produto pendente (`FATPI10`) não traz CFOP,
então não dá mais pra classificar a nota direto no endpoint como se fazia
antes; a classificação precisa esperar a confirmação de que não há
produto pendente.

NFCe (`ZZD`) e Recibo (`ZZE`) **não** usam intermediária — já cumprem
esse papel sozinhas, sem ambiguidade de classificação.

Nome escolhido (`ZZ9`, não `ZZG`) — decisão do José Carlos, pra ordenar
antes de `ZZA` alfabeticamente/numericamente, refletindo que é a etapa
anterior no fluxo.

### Campos

| Campo | Tipo | Descrição |
|---|---|---|
| `ZZ9_FILIAL` | C(5) | Filial do registro |
| `ZZ9_COD` | C(10) | Sequencial (GetSxeNum) |
| `ZZ9_STATUS` | C(1) | P=Pendente / A=Em andamento / S=Classificada e roteada / E=Erro de classificação. **Atenção: aqui STATUS não significa "nota processada" como nas outras tabelas — significa "classificada e gravada na tabela muro final".** O processamento real da nota acontece em ZZA/ZZB/ZZC, não aqui. |
| `ZZ9_CHVNFE` | C(44) | Chave de acesso NFe — unicidade |
| `ZZ9_JSON` | M | Payload completo da nota, usado pra classificar por CFOP e montar a gravação final em ZZA/ZZB/ZZC |
| `ZZ9_PRDPEN` | C(1) | S/N — vem direto do campo `prod_pendente` do payload recebido. Nome com 9 caracteres (não `PRDPEND`, 10 — mesmo motivo do rename já feito nas outras 6 tabelas: limite de 10 caracteres de campo no SIGACFG) |
| `ZZ9_DESTMU` | C(3) | ZZA/ZZB/ZZC — preenchido só depois de classificada. Rastreabilidade de "pra onde essa nota foi roteada" |
| `ZZ9_DTINCL` | D | Data de inclusão na fila |
| `ZZ9_HRINCL` | C(8) | Hora de inclusão na fila |
| `ZZ9_DTPROC` | D | Data da classificação/roteamento |
| `ZZ9_HRPROC` | C(8) | Hora da classificação/roteamento |
| `ZZ9_ERRMSG` | M | Erro de classificação (ex: CFOP não bateu em nenhuma regra de roteamento) |

### Índices

| Índice | Campos | Finalidade |
|---|---|---|
| 001 | FILIAL + COD | Chave primária única |
| 002 | FILIAL + STATUS + DTINCL + HRINCL | Fila FIFO do Job de classificação |
| 003 | FILIAL + CHVNFE | Unicidade / deduplicação |
| 004 | FILIAL + PRDPEN + STATUS | Job filtra só o que já está liberado (PRDPEN='N') |

### Pendências registradas (não implementar agora, só documentar como
pendente)

- Job que vai ler `ZZ9`, classificar por CFOP e gravar em `ZZA`/`ZZB`/`ZZC`
  ainda não tem nome definido (candidato: `FATZZ901.prw`)
- A lógica de classificação por CFOP que hoje mora em `FATPI01_V2.prw`
  precisa **migrar** pra esse Job novo, não ser recriada do zero
- `FATZZF01.prw` (produtos pendentes) vai precisar apontar a liberação de
  `PRDPEN` pra `ZZ9` quando o domínio for NFe (`NFS`/`NFD`/`NFE`) — hoje
  aponta direto pra `ZZA`/`ZZB`/`ZZC`. NFCe/Recibo (`NFC`/`RCV`) não
  mudam, continuam apontando direto pra `ZZD`/`ZZE`
- A classificação por CFOP em si ainda depende do `FATCFOP01`, que hoje é
  passa-reto (não faz nada) — decisão pendente de migrar pros perfis do
  configurador de tributos (`MV_PERVDA`/`MV_PERDVV`/`MV_PERDVC`) ou manter
  CFOP hardcoded, só mudando de arquivo
