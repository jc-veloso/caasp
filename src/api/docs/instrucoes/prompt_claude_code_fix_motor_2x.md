# Corrigir motor rodando 2x + parâmetros vazios nos Jobs de NFe

## Contexto — LER COM ATENÇÃO, é sensível (nota fiscal + financeiro real)

Achado ao planejar a migração pra `ZZ9`: o `FATPI01_V2.prw` roda o motor
fiscal (`U_PI_SAIDA_X`/`U_PI_DEVOL_X`/`U_PI_GERAPC_X`+`U_PI_GERANF_X`) **de
forma síncrona, dentro do endpoint**, e só grava na fila (`ZZA`/`ZZB`/`ZZC`)
**depois** do motor já ter concluído com sucesso — a fila hoje é log de
auditoria de trabalho já feito, não fila de trabalho pendente.

Só que `FATZZA01`/`FATZZB01`/`FATZZC01` **também** chamam o mesmo motor,
lendo parâmetros (`cCod`, `cLoja`, `cNF`, `cSer` etc.) de campos
sintéticos (`_COD`, `_LOJA`, `_NF`...) que **nunca são gravados** no JSON
em lugar nenhum do `FATPI01_V2` — confirmado via `U_PI_STR_X`, que
retorna string vazia quando a chave não existe. Ou seja: os Jobs sempre
rodaram (ou tentaram rodar) o motor com parâmetros vazios, desde que
foram escritos. Nunca foi pego porque o fluxo completo nunca rodou de
ponta a ponta em teste.

**Objetivo desta tarefa:** o `FATPI01_V2` continua fazendo toda a
resolução (roteamento fiscal SA1/SA2, numeração, CFOP/TES) — isso NÃO
muda. O que muda: em vez de chamar o motor e só gravar na fila depois do
sucesso, ele **enriquece o JSON com os campos sintéticos** (que nunca
existiram) **e grava na fila antes de qualquer motor rodar**. O motor +
lançamento financeiro (`JSON_COMPRA`/`PI_GER_E2`) + o fluxo de
transferência entre filiais (`CONVENIOS`+rollback) migram pros 3 Jobs.

**Isso NÃO inclui a arquitetura da tabela `ZZ9`** — essa é uma etapa
seguinte, separada. Por enquanto o fluxo continua `FATPI01_V2` →
`ZZA`/`ZZB`/`ZZC` diretamente, só que assíncrono de verdade agora.

## Arquivo 1: `FATPI01_V2.prw`

### 1.1 — Manter INTOCADO
Seções 1 a 6 completas: parse/validação, guard de modelo, roteamento
fiscal (SA1/SA2), determinação de `cOper` (S/D/E), numeração, checagem de
duplicidade (contra SF1/SF2 — continua fazendo sentido, é a fonte da
verdade de "já foi criado fiscalmente"), e o loop de produto (SB1, NCM/
CEST, CFOP/TES via `oMotorRegras`). Nada disso muda.

### 1.2 — Antes de gravar na fila, enriquecer o `oHead`
Logo depois do loop de produto (fim da seção 6, antes de onde hoje começa
a seção "7. DISPARO DOS MOTORES"), adicionar:

```advpl
// [FIX-MOTOR-2X] Jose Carlos - Artiq - 08/2026
// Enriquece o oHead com os campos que os Jobs (FATZZA01/B01/C01) precisam
// pra rodar o motor sozinhos — antes esses campos nunca eram gravados,
// entao os Jobs sempre rodaram com parametro vazio (bug nunca detectado
// por falta de teste ponta a ponta). cCnpjEmit/cCnpjDest sao novos, pro
// fluxo CONVENIOS que tambem esta migrando pro FATZZA01.
oHead['_COD']      := cCod
oHead['_LOJA']     := cLoja
oHead['_NF']       := cNF
oHead['_SER']      := cSer
oHead['_LEG']      := cLeg
oHead['_FIL']      := cFil
oHead['_TAB']      := cTab
oHead['_TRANSF']   := IIF(lIsTransf, "S", "N")
oHead['_COND']     := cCondSafe
oHead['_CNPJEMIT'] := cCnpjEmit
oHead['_CNPJDEST'] := cCnpjDest
```

### 1.3 — Substituir a seção "7. DISPARO DOS MOTORES" inteira

Remover todo o conteúdo atual dessa seção (as chamadas de
`U_PI_SETFCA`, `U_PI_DEVOL_X`, `U_PI_SAIDA_X`, `U_PI_GERAPC_X`,
`U_PI_GERANF_X`, `JSON_COMPRA`, `PI_GER_E2`, e todo o bloco `CONVENIOS`
com `U_FATPI01NF`/`FZ_ROLLBACK_NF`) e substituir por:

```advpl
// --- 7. ENFILEIRAMENTO (motor + financeiro migraram pros Jobs) ---
If lOk
    Do Case
        Case cOper == "D"
            If ZZX_Gravar("ZZB", "NFD", "CHVNFE", AllTrim(U_PI_STR_X(oHead, 'cod_ChaveNFe')), jJson:toJSON())
                nStat := 201
                jRes['status']    := nStat
                jRes['resultado'] := "Sucesso"
                jRes['doc']       := "NFe Devolucao enfileirada: " + AllTrim(U_PI_STR_X(oHead, 'cod_ChaveNFe'))
                jRes['info']      := "Nota registrada para processamento assincrono."
            Else
                lOk := .F.
                nStat := 230
                jRes['status']    := nStat
                jRes['resultado'] := "Falha"
                jRes['erro']      := "FilaMuroZ"
                jRes['mensagem']  := "Falha ao gravar na fila ZZB. Tente novamente."
            EndIf

        Case cOper == "S"
            // Validacao SX5 continua aqui — pre-flight antes de enfileirar,
            // evita erro fatal do Protheus "Problema Numeracao NF" mais tarde
            cQryAux := "SELECT X5_CHAVE FROM " + RetSqlName("SX5") + " WHERE X5_FILIAL = '" + xFilial("SX5") + "' AND X5_TABELA = '01' AND X5_CHAVE = '" + cSer + "' AND D_E_L_E_T_ = ' '"
            cAliAux := GetNextAlias()
            MpSysOpenQuery(cQryAux, cAliAux)
            If (cAliAux)->(Eof())
                lOk := .F.
                nStat := 201
                jRes['status']    := nStat
                jRes['resultado'] := "Falha"
                jRes['erro']      := "SERIE_SX5"
                jRes['mensagem']  := "Serie '" + AllTrim(cSer) + "' nao cadastrada na Tabela 01 (SX5) da filial " + xFilial("SX5") + "."
            EndIf
            (cAliAux)->(DbCloseArea())

            If lOk
                If ZZX_Gravar("ZZA", "NFS", "CHVNFE", AllTrim(U_PI_STR_X(oHead, 'cod_ChaveNFe')), jJson:toJSON(), "TRANSF", IIF(lIsTransf, "S", "N"))
                    nStat := 201
                    jRes['status']    := nStat
                    jRes['resultado'] := "Sucesso"
                    jRes['doc']       := "NFe Saida enfileirada: " + AllTrim(U_PI_STR_X(oHead, 'cod_ChaveNFe'))
                    jRes['info']      := "Nota registrada para processamento assincrono."
                Else
                    lOk := .F.
                    nStat := 230
                    jRes['status']    := nStat
                    jRes['resultado'] := "Falha"
                    jRes['erro']      := "FilaMuroZ"
                    jRes['mensagem']  := "Falha ao gravar na fila ZZA. Tente novamente."
                EndIf
            EndIf

        Otherwise
            If ZZX_Gravar("ZZC", "NFE", "CHVNFE", AllTrim(U_PI_STR_X(oHead, 'cod_ChaveNFe')), jJson:toJSON())
                nStat := 201
                jRes['status']    := nStat
                jRes['resultado'] := "Sucesso"
                jRes['doc']       := "NFe Entrada enfileirada: " + AllTrim(U_PI_STR_X(oHead, 'cod_ChaveNFe'))
                jRes['info']      := "Nota registrada para processamento assincrono."
            Else
                lOk := .F.
                nStat := 230
                jRes['status']    := nStat
                jRes['resultado'] := "Falha"
                jRes['erro']      := "FilaMuroZ"
                jRes['mensagem']  := "Falha ao gravar na fila ZZC. Tente novamente."
            EndIf
    EndCase
EndIf
```

### 1.4 — Checar variáveis órfãs
Depois da remoção, `oMotorRegras`/`aRetCfop` continuam em uso (loop de
produto, seção 6 — não mexer). Verificar se alguma variável fica
genuinamente sem uso após a remoção específica da seção 7 (ex:
`aEmpDest`, `cFilDest`, `aRetTransf` — só existiam pro CONVENIOS que
saiu) e remover a declaração se for o caso.

## Arquivo 2: `FATZZB01.prw` (NFe Devolução) — adicionar JSON_COMPRA

Depois de `aRet := U_PI_DEVOL_X(...)`, dentro do `If aRet[1]` (sucesso),
adicionar antes do `Return {.T., ...}`:

```advpl
// [MIGRADO-DO-ENDPOINT] JSON_COMPRA - gatilho financeiro (SE2).
// Antes rodava no FATPI01_V2 logo apos o motor. Mesmos parametros.
JSON_COMPRA(AllTrim(U_PI_STR_X(oHead,'_NF')), AllTrim(U_PI_STR_X(oHead,'_SER')), AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), aPrd, oHead, AllTrim(U_PI_STR_X(oHead,'_TAB')))
```

## Arquivo 3: `FATZZC01.prw` (NFe Entrada) — adicionar JSON_COMPRA + PI_GER_E2

Depois do segundo `aRet := U_PI_GERANF_X(...)`, dentro do `If aRet[1]`
(sucesso), adicionar antes do `Return {.T., ...}`:

```advpl
// [MIGRADO-DO-ENDPOINT] JSON_COMPRA + PI_GER_E2 - gatilho financeiro
// (SE2). Antes rodava no FATPI01_V2 logo apos o motor. PI_GER_E2 depende
// do RECNO do SE2 gerado pelo JSON_COMPRA — manter a ordem exata.
JSON_COMPRA(AllTrim(U_PI_STR_X(oHead,'_NF')), AllTrim(U_PI_STR_X(oHead,'_SER')), AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), aPrd, oHead, AllTrim(U_PI_STR_X(oHead,'_TAB')))
PI_GER_E2(AllTrim(U_PI_STR_X(oHead,'_NF')), AllTrim(U_PI_STR_X(oHead,'_SER')), AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), aPrd, oHead, AllTrim(U_PI_STR_X(oHead,'_TAB')), SE2->(RECNO()))
```

## Arquivo 4: `FATZZA01.prw` (NFe Saída) — adicionar CONVENIOS + rollback

Depois de `aRet := U_PI_SAIDA_X(...)`, dentro do `If aRet[1]` (sucesso),
adicionar antes do `Return {.T., ...}`:

```advpl
// [MIGRADO-DO-ENDPOINT] CONVENIOS - transferencia entre filiais com
// rollback automatico. Antes rodava no FATPI01_V2 logo apos o motor.
Local lIsTransf  := U_PI_STR_X(oHead,'_TRANSF') == "S"
Local cCnpjEmit  := AllTrim(U_PI_STR_X(oHead,'_CNPJEMIT'))
Local cCnpjDest  := AllTrim(U_PI_STR_X(oHead,'_CNPJDEST'))
Local aEmpDest   := {}
Local aRetTransf := {}

If lIsTransf .And. cCnpjEmit != cCnpjDest
    aEmpDest := U_PI_FILIAL_X(cCnpjDest)
    If Len(aEmpDest) >= 2
        aRetTransf := U_FATPI01NF(aPrd, oHead, cCnpjEmit, AllTrim(U_PI_STR_X(oHead,'_NF')), AllTrim(U_PI_STR_X(oHead,'_SER')), aEmpDest)
        If !aRetTransf[1]
            FZ_ROLLBACK_NF(AllTrim(U_PI_STR_X(oHead,'_NF')), AllTrim(U_PI_STR_X(oHead,'_SER')), AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')))
            Return {.F., "ROLLBACK_CONVENIOS: " + cValToChar(aRetTransf[2]) + " | Saida (SF2) na origem foi ESTORNADA."}
        EndIf
    EndIf
EndIf
```

**Atenção**: declarar essas `Local` novas (`lIsTransf`, `cCnpjEmit`,
`cCnpjDest`, `aEmpDest`, `aRetTransf`) no topo da função, junto das
outras `Local` já existentes — nunca depois de `Private`, mesma regra de
sempre. Não usar esses nomes se já existir variável com nome igual na
função (checar antes de declarar).

## Validação depois de aplicar (crítica — envolve nota fiscal real)

1. Balanceamento `If`/`EndIf`/`Do Case`/`EndCase` nos 4 arquivos
2. Confirmar que `U_PI_SETFCA`, `JSON_COMPRA`, `PI_GER_E2`,
   `U_FATPI01NF`, `FZ_ROLLBACK_NF` **não são mais chamados** em
   `FATPI01_V2.prw` (só nos Jobs agora)
3. Confirmar que os 3 Jobs continuam lendo os campos sintéticos do
   mesmo jeito de sempre (`U_PI_STR_X(oHead,'_COD')` etc.) — agora vão
   receber valor de verdade, não mais vazio
4. **Não testar direto em ambiente com dado real** — se possível, testar
   primeiro com uma nota de teste/homologação antes do Antonio rodar
   qualquer coisa real amanhã, dado que isso cria documento fiscal e
   lançamento financeiro de verdade
