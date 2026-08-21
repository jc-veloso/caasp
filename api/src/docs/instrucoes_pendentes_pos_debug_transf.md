# Instruções pendentes — desde a instrumentação `[TEMP-DEBUG-TRANSF]`

Consolidação de tudo que ficou pendente de aplicar depois que a
instrumentação de debug (`[TEMP-DEBUG-TRANSF]`, `ConOut` em
`PI_GERANF_X`) foi adicionada pra investigar o bug de transferência.
Três frentes, nesta ordem: (1) os bugs de transferência confirmados,
(2) despesa/frete, (3) campos novos em `SE1`.

---

# Parte A — Bugs de transferência (CONVENIOS)

## Contexto

Investigação anterior usou uma cópia desatualizada do fonte original,
gerando um diagnóstico errado (já revisto). A versão real do fonte
original (confirmada pelo Zé Carlos) revela dois bugs reais na versão
atual, mais um terceiro ponto de atenção que precisa ser conferido.

**Cenário de teste de referência**: `des_EmitDocumento: "44692168008408"`
(origem), `des_DestDocumento: "44692168003953"` (destino),
`num_SubseccaoCNPJ: "44692168008408"` (igual ao emit — confirma que o
payload processado é sempre do lado da origem).

## A.1 — Bug 1: `cTab` errado no roteamento de saída (`ZZ901_Classifica`)

**Confirmado**: no original real, o branch de saída da transferência usa
`SA1`, não `SA2`:
```advpl
ElseIf cCnpj == cCnpjEmit .And. cCnpj != cCnpjDest
    cOper := "S"
    cTab  := "SA1"
```
No `ZZ901_Classifica` atual (`FATZZ901.prw`), esse mesmo branch está com
`cTab := "SA2"`. **Corrigir para `"SA1"`.**

Consistente com a validação que já existe logo abaixo no próprio
`ZZ901_Classifica` (`[REV2-EXTRACAO-NFCE]`), que já confere `cCnpjEmit`
como fornecedor (`SA2`) — confirma a convenção: **origem = fornecedor,
destino = cliente**, sempre.

**Não é necessário** adicionar a validação extra de pré-checagem
`SA1`/`SA2` que aparece no fonte original — o `ZZ901_Classifica` atual
já cobre os dois casos por outro caminho (checagem genérica de
"Destinatario nao localizado" + checagem de emitente-fornecedor já
existente). **Confirmar isso em teste** antes de considerar fechado.

## A.2 — Bug 2: `PI_GERANF_X` resolve o CNPJ errado pro ambiente de destino

**Confirmado**: no original real, `FZ_PRON_X` (hoje `PI_GERANF_X`) ganhou
um parâmetro novo, `lIsTransf`, e passou a resolver o CNPJ de contexto
condicionalmente:
```advpl
User Function FZ_PRON_X(..., cCond, lIsTransf)
    ...
    If lIsTransf
        cCnpjU := U_FZ_LIMPA_X(U_FZ_STR_X(oHead, "des_DestDocumento", "des_DestDocumento"))
    Else
        cCnpjU := U_FZ_LIMPA_X(U_FZ_STR_X(oHead, "num_SubseccaoCNPJ", "num_SubseccaoCNPJ"))
    Endif
    aEmpFil := FATPIEMP(cCnpjU)
    ...
```
Não é que a função "sobrescreve" um ambiente correto por engano de forma
genérica — ela **sempre** recalcula o ambiente a partir de
`num_SubseccaoCNPJ` (sempre o CNPJ de **origem**, nunca muda dentro do
mesmo `oHead`), e só passou a usar `des_DestDocumento` quando
`lIsTransf` é verdadeiro.

### Mudanças em cadeia

1. **`PI_GERANF_X`** (`FATPI01E.prw`): adicionar parâmetro `lIsTransf`,
   aplicar a resolução condicional de `cCnpjU` mostrada acima.
2. **`FATPI01NF`** (`FATPI01S.prw`): adicionar parâmetro `lIsTransf`,
   repassar pro `U_PI_GERANF_X` (último parâmetro).
3. **`FATZZA01.prw`** (`ZZA_MotorSaida`): já calcula `lIsTransf` — só
   precisa **repassar** na chamada a `U_FATPI01NF`, que hoje não passa
   esse parâmetro.

**Ambiente**: `PI_GERANF_X` hoje roda dentro de um **Job** (não mais
`WSRESTFUL` como o original), onde `RpcSetEnv`/`RpcClearEnv` reais são
permitidos. **Não replicar o hack `cFilAnt := aEmpFil[2]`** que o
original usava só pra contornar a restrição de `WSRESTFUL` — manter
`RpcSetEnv(aEmpFil[1], aEmpFil[2])` real, só corrigindo de onde `cCnpjU`
vem.

## A.3 — Bug 3 (a confirmar): `PI_SAIDA_X` também precisa resolver cliente via `SA1`

No original real, `FZ_PROS_X` (hoje `PI_SAIDA_X`) tem um bloco dedicado:
```advpl
If lIsTransf
    cCnpjCli := U_FZ_LIMPA_X(U_FZ_STR_X(oHead, "des_DestDocumento", "des_DestDocumento"))
    DbSelectArea("SA1")
    SA1->(DbSetOrder(3))
    If SA1->(DbSeek(xFilial("SA1") + cCnpjCli))
        cCli  := SA1->A1_COD
        cLoja := SA1->A1_LOJA
    Endif
    cTipoOper := 'N'
Endif
```
`PI_SAIDA_X` já recebe `lIsTransf` como parâmetro hoje (9º parâmetro) —
não precisa de mudança de assinatura, só adicionar esse bloco de lógica
interna, usando `oHead['des_DestDocumento']` diretamente.

**Confirmar se esse bloco já existe no `PI_SAIDA_X` atual antes de
adicionar** — se o Bug 1 já resolve `cCod`/`cLoja` certo lá atrás no
`ZZ901_Classifica`, esse bloco seria redundante (mas inofensivo, o
original também tinha os dois) — adicionar mesmo assim, por segurança e
paridade com o original.

## Checklist — Parte A

- [ ] Bug 1: `cTab := "SA1"` corrigido no branch de saída da
      transferência, `ZZ901_Classifica`.
- [ ] Bug 2: `lIsTransf` adicionado em `PI_GERANF_X` e `FATPI01NF`,
      repassado desde `FATZZA01`.
- [ ] `RpcSetEnv`/`RpcClearEnv` reais mantidos em `PI_GERANF_X` (sem o
      hack `cFilAnt`).
- [ ] Bug 3: confirmado/adicionado o bloco `SA1` por `des_DestDocumento`
      em `PI_SAIDA_X`.
- [ ] Testado o cenário de referência ponta a ponta (CNPJs
      `...008408`/`...003953`): saída na origem com cliente certo,
      entrada automática na filial de destino certa.
- [ ] **Remover a instrumentação `[TEMP-DEBUG-TRANSF]`** (`ConOut`) de
      `PI_GERANF_X` — não deve ir pra produção.

---

# Parte B — Despesa (Entrada) e Frete (Entrada + Saída)

## Contexto

Wilson reportou três problemas. Investigação contra a versão real do
original confirmou regressões reais de campo.

## B.1 — `D1_DESPESA`/`SFT_DESPESA` sumiu do fluxo de Entrada

**Confirmado por ausência total** em `FATPI01E.prw` — nem lê
`vlr_ProdutoOutros`, nem grava. No original (`PI_GERANF_X`):
```advpl
nDespesa := U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoOutros')
...
AAdd(aLin, {"D1_DESPESA", nDespesa, Nil})
```
E também `SFT->FT_DESPESA := nDespesa` no bloco de pós-gravação
equivalente ao `JSON_COMPRA` pra Entrada.

**`F1_DESPESA`** (cabeçalho) **não precisa** ser restaurado — já estava
desativado no próprio original, não é regressão.

**Nota de teste**: Wilson confirmou que o teste que reportou esse
problema tinha o **JSON de origem já sem o valor** — não valida a
correção. Aplicar mesmo assim; retestar com JSON correto.

## B.2 — Frete: quatro campos, não um

### Entrada (`PI_GERANF_X`) — cabeçalho e item, os dois ausentes
```advpl
nValFrete := Round(U_FZ_VAL_X(oHead, 'vlr_Frete'), 4)
AAdd(aCab, {"F1_FRETE", nValFrete, Nil})              ' cabeçalho

nValFreteUnit := Round(U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoFrete'), 4)
AAdd(aLin, {"D1_VALFRE", nValFreteUnit, Nil})          ' por item
```

### Saída (`PI_SAIDA_X`) — falta o item (`F2_FRETE` cabeçalho já deve
### estar aplicado de uma instrução anterior; confirmar)
```advpl
nFreteItem := U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoFrete')
nD2FRETE := Ascan(aStruSD2,{|x| AllTrim(x[1]) == "D2_VALFRE"})
...
If nD2FRETE > 0 ; aItens[nPos, nD2FRETE] := nFreteItem ; EndIf
```
Mesmo padrão do `nF2FRETE` — adicionar `nD2FRETE` na declaração de
índices do `aStruSD2` e no bloco de montagem de `aItens`.

**Escopo**: `PI_SAIDA_X` é compartilhado por `FATZZA01` (NFe) e
`FATZZD01` (NFCe) — vale pros dois.

### `SF3_FRETE`? — verificar antes de decidir

O array `aGrpSF3` (dentro de `JSON_VENDA`) ganhou um elemento a mais pra
frete (`nFrete`), usado pra somar em `nVlrLiqItm`, mas não encontrei
nenhuma atribuição `SF3->F3_FRETE` no bloco de gravação final — só
`SF3->F3_DESPESA`. **Verificar no dicionário se `F3_FRETE` existe como
campo de `SF3`** antes de decidir se falta algo — não aplicar nada aí
sem confirmar.

## Checklist — Parte B

- [ ] `D1_DESPESA`/`SFT_DESPESA` restaurados em `PI_GERANF_X`, testado
      com JSON que tenha `vlr_ProdutoOutros` preenchido de verdade.
- [ ] `F1_FRETE`/`D1_VALFRE` restaurados em `PI_GERANF_X`.
- [ ] `F2_FRETE`/`D2_VALFRE` restaurados em `PI_SAIDA_X`, testado com
      NFe **e** NFCe.
- [ ] `SF3_FRETE`: verificado no dicionário antes de aplicar qualquer
      coisa.

---

# Parte C — Campos novos em `SE1` (`E1_CODFUNC`, `E1_MOEDA`)

## Contexto

Conferência pontual: `E1_CARTAUT`/`E1_NSUTEF` já estão corretos nos
fontes atuais (nenhuma ação necessária). `E1_CODFUNC` e `E1_MOEDA` são
inclusões novas, sem precedente idêntico no original — confirmadas com
o Zé Carlos.

## C.1 — `E1_CODFUNC := A1_XCODRH`

Adicionar nos **dois** pontos que tocam `SE1`, em `FATPI01S.prw`:

**`FZ_GER_E1`** (criação via `RecLock`), logo depois de `E1_NOMCLI`:
```advpl
SE1->E1_NOMCLI  := Posicione('SA1', 1, FWxFilial('SA1') + SE1->E1_CLIENTE + SE1->E1_LOJA, 'A1_NOME')
SE1->E1_CODFUNC := Posicione('SA1', 1, FWxFilial('SA1') + SE1->E1_CLIENTE + SE1->E1_LOJA, 'A1_XCODRH')
```

**`JSON_VENDA`** (`UPDATE` SQL), junto de `E1_NATUREZ`:
```advpl
cQrySE1 += "E1_CODFUNC = '" + PadR(Posicione('SA1', 1, FWxFilial('SA1') + cCliPad + cLojaPad, 'A1_XCODRH'), TamSx3("E1_CODFUNC")[1]) + "', "
```

**Pré-requisito**: confirmar no dicionário que `E1_CODFUNC` (`SE1`) e
`A1_XCODRH` (`SA1`) existem exatamente com esses nomes antes de aplicar.

## C.2 — `E1_MOEDA := 1`

Mesmo valor fixo que `E2_MOEDA` já usa do lado de compras (`FZ_GER_E2`).

**`FZ_GER_E1`**:
```advpl
SE1->E1_MOEDA := 1
```

**`JSON_VENDA`**:
```advpl
cQrySE1 += "E1_MOEDA = 1, "
```

## Checklist — Parte C

- [ ] Confirmar no dicionário: `E1_CODFUNC` (`SE1`) e `A1_XCODRH`
      (`SA1`) existem.
- [ ] `E1_CODFUNC` adicionado em `FZ_GER_E1` e `JSON_VENDA`, testado com
      cliente que tenha `A1_XCODRH` preenchido.
- [ ] `E1_MOEDA := 1` adicionado em `FZ_GER_E1` e `JSON_VENDA`.
