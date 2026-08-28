# Instrução — Campo `_QTPROD` nas tabelas de nota (ZZ9/ZZA/ZZB/ZZC/ZZD/ZZE)

## Contexto

Campo `_QTPROD` criado no SIGACFG nas seis tabelas de nota:
`ZZ9_QTPROD`, `ZZA_QTPROD`, `ZZB_QTPROD`, `ZZC_QTPROD`, `ZZD_QTPROD`,
`ZZE_QTPROD`. Guarda a quantidade de produtos/itens da nota, vinda do
JSON recebido.

**Não é campo novo de lógica** — é só rastreabilidade/relatório. Não deve
influenciar nenhuma decisão de classificação, roteamento ou liberação de
nota. Tratar como metadado.

## Onde vem o valor

**Vem pronto no JSON, tag `qt_Produto`** (raiz de cada nota, alinhado com
o Arthur). Não precisa calcular (`Len(aPrd)` ou equivalente) nem se
preocupar com descarte de item durante classificação — é só ler a tag e
gravar o valor exatamente como veio.

## Onde preencher cada uma

Aproveitar o parâmetro genérico que `U_ZZX_Gravar` (`FATZZF01.prw`) já
tem — `cCampoExtra`/`cValorExtra` — em vez de alterar a assinatura da
função ou duplicar lógica de gravação:

```advpl
U_ZZX_Gravar(cTabMuro, cProc, cCampoChave, cChvRef, cJsonPayload, "QTPROD", AllTrim(U_PI_STR_X(oHead,'qt_Produto')), cPrdPend)
```

Pontos de chamada a atualizar (cada um já chama `U_ZZX_Gravar` hoje, só
precisa passar os dois parâmetros novos em vez de deixar vazio):

- **`ZZ9`**: `FATPI01_V2.prw`, na gravação bruta do endpoint.
- **`ZZA`/`ZZB`/`ZZC`**: `ZZ901_Classifica` (`FATZZ901.prw`), na gravação
  final pós-classificação.
- **`ZZD`**: `ZZD_MotorNFCe` (`FATZZD01.prw`), mesmo ponto.
- **`ZZE`**: motor do Recibo (`FATPI08_V2.prw`), no ponto equivalente de
  gravação — mesmo padrão, só ler `qt_Produto` do JSON recebido nesse
  fluxo.

Se `qt_Produto` não vier em algum payload (nulo/ausente), gravar vazio ou
`"0"` — decisão de time, não é algo que eu deva assumir sozinho; se
importar, confirmar com o Arthur se a tag é sempre obrigatória.

## Checklist

- [ ] Confirmar tamanho/tipo do campo no SIGACFG (numérico, quantas
      posições) — se for campo numérico (`N`), ajustar a gravação de
      `cValToChar`/`AllTrim` pra `Val()` conforme o tipo real.
- [ ] Testar uma nota real de cada tipo (NFe Saída, Devolução, Entrada,
      NFCe, Recibo) e conferir `_QTPROD` gravado batendo com o valor que
      veio em `qt_Produto`.
