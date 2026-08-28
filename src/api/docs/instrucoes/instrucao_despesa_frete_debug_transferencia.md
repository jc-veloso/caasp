# Instrução — Restaurar D1_DESPESA/F2_FRETE + instrumentar bug de transferência

## Contexto

Wilson (consultor fiscal) reportou três problemas, todos ele acreditando
já estarem corrigidos na integração atual. Investigação comparando contra
o monólito original (`FATPI01__2_.prw`) confirmou dois como regressões
reais (campos que existiam no original e sumiram na extração pros fontes
atuais), e um terceiro que precisa de instrumentação pra decidir (o
mecanismo suspeito já existia idêntico no original, então não é
regressão simples — precisa ver o comportamento real).

---

## Parte 1 — `D1_DESPESA`/`SFT_DESPESA` sumiu do fluxo de Entrada

**Confirmado por ausência total**: `FATPI01E.prw` atual não tem nenhuma
ocorrência de `DESPESA` nem do campo fonte `vlr_ProdutoOutros` — nem
lê o valor, nem grava. No original (`FATPI01__2_.prw`, função
`FZ_PRON_X`, hoje `PI_GERANF_X`), o campo era lido e gravado assim:

```advpl
nDespesa := U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoOutros')
...
AAdd(aLin, {"D1_DESPESA", nDespesa, Nil})
```
(dentro do loop de montagem de `aLin`/itens, mesmo bloco que monta
`D1_TES`/`D1_CF`/etc. — ver função `PI_GERANF_X` em `FATPI01E.prw`)

E também em `SFT_DESPESA` (bloco de atualização pós-gravação do livro
fiscal — conferir se existe uma função equivalente ao `JSON_COMPRA`
original que trata `SFT` pra Entrada, e se ela tem esse update; no
original a atribuição correspondente é `SFT->FT_DESPESA := nDespesa`).

**Nota**: `F1_DESPESA` (nível de cabeçalho, não item) **não precisa** ser
restaurado — já estava comentado/desativado no próprio original
(`//AAdd(aCab, {"F1_DESPESA", nDespesa, Nil})`), não é regressão.

**Correção**: adicionar `nDespesa := U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoOutros')`
e `AAdd(aLin, {"D1_DESPESA", nDespesa, Nil})` no loop de itens de
`PI_GERANF_X` (`FATPI01E.prw`), e o `SFT_DESPESA` correspondente se
existir função de pós-gravação equivalente pra Entrada.

## Parte 2 — `F2_FRETE` sumiu do `PI_SAIDA_X`

**Confirmado por ausência total**: a lista de índices de campo do
`aCabs` em `PI_SAIDA_X` (`FATPI01S.prw`, ~linha 754) não inclui
`nF2FRETE`:
```advpl
Local nF2FILIAL, nF2TIPO, nF2DOC, nF2SERIE, nF2EMISSAO, nF2CLIENTE, nF2LOJA, nF2COND, nF2ESPECIE, nF2EST
```
No original (`FZ_PROS_X`), a mesma lista incluía `nF2FRETE`, resolvido via
`Ascan` e atribuído no array:
```advpl
nF2FRETE := Ascan(aStruSF2,{|x| AllTrim(x[1]) == "F2_FRETE"})
...
If nF2FRETE > 0 ; aCabs[nF2FRETE] := nValFrete ; EndIf
```
`nValFrete`/`nFreteTot` (`U_PI_VAL_X(oHead, 'vlr_Frete')`) já é lido hoje
dentro do `JSON_VENDA` (mesmo arquivo), mas só entra no cálculo de
`F2_VALBRUT` — nunca é escrito no campo `F2_FRETE` propriamente.

**Escopo**: `PI_SAIDA_X` é o motor compartilhado por `FATZZA01` (NFe
Saída) **e** `FATZZD01` (NFCe, desde a migração `LOJA701`→`PI_SAIDA_X`)
— o bug afeta as duas, não só NFCe como o Wilson percebeu.

**Correção**: adicionar `nF2FRETE` na declaração de índices, o `Ascan`
correspondente, e `If nF2FRETE > 0 ; aCabs[nF2FRETE] := nFreteTot ; EndIf`
no bloco de montagem do `aCabs` em `PI_SAIDA_X` — usar a variável
`nFreteTot` que já existe em `JSON_VENDA`, ou replicar a leitura
`U_PI_VAL_X(oHead, 'vlr_Frete')` diretamente dentro do `PI_SAIDA_X` se
`JSON_VENDA` rodar em escopo separado (confirmar isso antes de aplicar —
`JSON_VENDA` parece rodar depois da gravação inicial, tratamento
"cirúrgico pós-gravação" pelo nome, então `PI_SAIDA_X` provavelmente
precisa da própria leitura, não pode depender da variável de `JSON_VENDA`).

## Parte 3 — Instrumentação temporária pra investigar o bug de transferência

**Não aplicar correção ainda** — o mecanismo suspeito (`PI_GERANF_X`
reabrindo ambiente via `num_SubseccaoCNPJ`, sobrescrevendo a filial de
destino que `FATPI01NF` já preparou) já existia idêntico no original, e o
Wilson confirmou ter testado esse exato cenário com sucesso antes. Preciso
ver o comportamento real antes de decidir se é regressão ou coincidência
de teste anterior.

Adicionar `ConOut` temporário em `PI_GERANF_X` (`FATPI01E.prw`), ao redor
do bloco:
```advpl
cCnpjU  := U_PI_LIMPA_X(U_PI_STR_X(oHead, "num_SubseccaoCNPJ", "num_SubseccaoCNPJ"))
aEmpFil := U_FATPIEMP(cCnpjU)

ConOut("[DEBUG-TRANSF] PI_GERANF_X entrada | cCnpjU=" + cCnpjU + " | aEmpFil=" + IIF(Len(aEmpFil)>=2, aEmpFil[1]+"/"+aEmpFil[2], "VAZIO") + " | ambiente atual=" + cEmpAnt + "/" + cFilAnt)

if Len(aEmpFil) > 0
    If aEmpFil[1] != cEmpAnt .Or. aEmpFil[2] != cFilAnt
        ConOut("[DEBUG-TRANSF] PI_GERANF_X VAI TROCAR ambiente de " + cEmpAnt + "/" + cFilAnt + " para " + aEmpFil[1] + "/" + aEmpFil[2])
        RPCClearEnv()
        RpcSetEnv(aEmpFil[1], aEmpFil[2])
    Else
        ConOut("[DEBUG-TRANSF] PI_GERANF_X NAO trocou - ambiente ja bate")
    EndIf
Endif
```
Marcar com `[TEMP-DEBUG-TRANSF]` pra facilitar remover depois. Rodar de
novo o mesmo cenário de transferência (mesmas duas filiais/CNPJs do
payload já capturado) e mandar o trecho do log relevante.

## Checklist

- [ ] `D1_DESPESA` restaurado em `PI_GERANF_X`, testado com nota de
      entrada que tenha `vlr_ProdutoOutros` preenchido no item.
- [ ] `SFT_DESPESA` conferido/restaurado se existir função equivalente ao
      `JSON_COMPRA` pra Entrada com esse campo.
- [ ] `F2_FRETE` restaurado em `PI_SAIDA_X`, testado com nota de saída
      (NFe **e** NFCe) que tenha `vlr_Frete` preenchido no cabeçalho.
- [ ] Confirmar se `PI_SAIDA_X` precisa de leitura própria de
      `vlr_Frete` ou se pode reaproveitar variável de `JSON_VENDA`
      (checar ordem de execução entre as duas funções antes de decidir).
- [ ] Instrumentação `[TEMP-DEBUG-TRANSF]` aplicada, rodado o cenário de
      transferência de novo, log capturado — **não aplicar correção do
      bug de transferência até analisar esse log**.
