# Instrução — Fechar a Parte B do id_Ipaas (ZZG + parking pra ZZF)

**Contexto**: revisão dos fontes atuais (2026-08-25) confirmou Parte A completa
e a propagação `ZZ9`→`ZZA`/`ZZB`/`ZZC` funcionando. Faltam dois pontos pra
fechar a Parte B. Os outros achados da revisão (`ZZC_PRDPEN`, segredos
hardcoded, `ZZX_Gravar` duplicado) **ficam de fora desta rodada** — decisão
do José Carlos, ver seção "Fora de escopo" no fim.

## 1. Captura do id_Ipaas na fila ZZG

### Campo novo SX3
`ZZG_IDIPS`, Character(36) — mesmo padrão dos outros campos `_IDIPS` (ex.
`ZZF_IDIPS`), não é chave, não precisa índice.

### FATPI11.prw
No corpo do endpoint, antes de chamar `U_ZZG_GRV`, extrair `cIdIpaas` do
payload do Arthur (`{tipo, chave, tp_Participante, dados}`) — mesmo padrão já
usado em `FATPI01_V2`/`FATPI09`: tentar em nível de cabeçalho do JSON
recebido (`jJson['id_Ipaas']`). Não tenho o formato exato desse payload
específico do Arthur à mão — se `id_Ipaas` não estiver na raiz, conferir
contra um payload de exemplo real antes de assumir o caminho.

### FATZZG01.prw — User Function ZZG_GRV
Adicionar parâmetro `cIdIpaas` (com `Default cIdIpaas := ""`, igual ao
`ZZF_GRV`), e gravar condicionalmente antes do `MsUnlock()`:

```advpl
If ZZG->(FieldPos("ZZG_IDIPS")) > 0
    ZZG->(FieldPut(ZZG->(FieldPos("ZZG_IDIPS")), PadR(cIdIpaas, TamSx3("ZZG_IDIPS")[1])))
EndIf
```

Atualizar a chamada em `FATPI11.prw` pra passar o novo argumento:
`U_ZZG_GRV(cChvRef, cTipoPen, cTipoNF, jDados:toJSON(), cIdIpaas)`.

## 2. Propagar id_Ipaas no parking pra ZZF

Em vez de reextrair do JSON dentro de `ZZ901_Classifica`/`ZZD_MotorNFCe`, ler
o valor que **já está gravado** na própria linha de origem (`ZZ9_IDIPS` ou
`ZZD_IDIPS` — já capturado desde a Parte A/B anterior).

### FATZZ901.prw — User Function FATZZ901
Incluir `ZZ9_IDIPS` no SELECT principal (junto com `ZZ9_COD`, `ZZ9_CHVNFE`
etc.), guardar em variável local `cIdIpaas` por linha, e trocar a chamada de
parking:

```advpl
// antes:
U_ZZF_GRV(cChvNFe, "ZZ9", cProdPend, "")
// depois:
U_ZZF_GRV(cChvNFe, "ZZ9", cProdPend, "", cIdIpaas)
```

### FATZZD01.prw — User Function FATZZD01
Mesma lógica: incluir `ZZD_IDIPS` no SELECT, guardar em `cIdIpaas`, e trocar:

```advpl
// antes:
U_ZZF_GRV(cChvNFe, "NFC", cProdPend, "")
// depois:
U_ZZF_GRV(cChvNFe, "NFC", cProdPend, "", cIdIpaas)
```

`ZZF_GRV` já aceita `cIdIpaas` como 5º parâmetro (implementado na Parte A) —
não precisa mexer na função em si, só nas duas chamadas acima.

## Fora de escopo desta instrução (decisões já tomadas, não mexer)

- **`ZZC_PRDPEN`**: comportamento intencional/redundante, mesmo padrão já
  resolvido na `ZZ9` (equivalente ao que `CLIPEN`/`FORPEN` fazem) — não fazer
  nada.
- **Segredos hardcoded em `FATZZF01.prw`** (token CAASP, API-keys do
  callback iPaaS na URL): fica pra depois.
- **Duplicação de `ZZX_Gravar`** (global em `FATZZF01.prw` vs. cópias locais
  em `FATPI08_V2.prw`/`FATPI09.prw`): fica pra uma rodada de limpeza
  separada.

## Checklist de teste

- [ ] Criar/confirmar campo `ZZG_IDIPS` (SX3, Character 36) antes de
      compilar.
- [ ] Mandar um payload de teste do Arthur pra `FATPI11` com `id_Ipaas` e
      conferir que grava em `ZZG_IDIPS`.
- [ ] Forçar um produto pendente numa nota de entrada de teste (via `ZZ9`) e
      conferir que `ZZF_IDIPS` recebe o `id_Ipaas` da nota original.
- [ ] Forçar um produto pendente numa NFCe de teste (via `ZZD`) e conferir o
      mesmo.
- [ ] Conferir encoding do(s) arquivo(s) depois da edição (acentos/travessão
      não virarem `�`).
