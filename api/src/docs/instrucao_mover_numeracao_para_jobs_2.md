# Instrução — Numeração sai do `ZZ901_Classifica`, vai pros Jobs de destino

## Bug que originou essa mudança

Testando NFe Saída/Entrada: `ZZ9` gravou certo, mas `ZZA`/`ZZC` gravaram
com a filial errada (`01093`/`01042` em vez de `01001`) — porque
`ZZ901_Classifica` troca de ambiente pra resolver dados fiscais da filial
real da nota, e **nunca volta** antes de gravar via `U_ZZX_Gravar`, que
usa `xFilial()` (reflete a filial trocada, não a de bootstrap onde os
Jobs `FATZZA01`/`FATZZC01` procuram).

## Decisão: não restaurar ambiente, eliminar a troca do classificador

**Confirmado com o Zé Carlos**: `SA1`, `SA2`, `SF4` e `SX5` são todos
**compartilhados entre filiais** neste ambiente — não precisam de
`RpcSetEnv` na filial real pra serem encontrados. A única coisa que
realmente precisa da filial real é a **numeração** (`GetSxeNum`,
controlada via `SX8`, série/sequência por filial por natureza legal) e a
**gravação fiscal final** (`SF2`/`SD2`/`SF1`, via `U_PI_SAIDA_X`/
`U_PI_DEVOL_X`/`U_PI_GERAPC_X`+`U_PI_GERANF_X`).

**Achado importante, confirmado nos três fontes atuais**
(`FATZZA01.prw`, `FATZZB01.prw`, `FATZZC01.prw`): `ZZA_MotorSaida`,
`ZZB_MotorDevolucao` e `ZZC_MotorEntrada` **já trocam de ambiente** pra
filial real, exatamente pra fazer a gravação fiscal final. Ou seja, o
lugar certo pra numeração **já tem o ambiente certo trocado** — não
precisa adicionar nenhum `RpcSetEnv` novo, só mover a numeração pra
dentro desse trecho que já existe.

**Resultado**: `ZZ901_Classifica` (`FATZZ901.prw`) passa a rodar 100% no
ambiente de bootstrap, do início ao fim — nunca troca de ambiente, nunca
mais corre risco dessa classe de bug. Ele só classifica `cOper`/`cCod`/
`cLoja`/`cTab`/`cFil`, resolve CFOP/TES por item (tudo cadastro
compartilhado), e distribui pra `ZZA`/`ZZB`/`ZZC` — sem gerar número de
documento.

---

## Parte 1 — `FATZZ901.prw` (`ZZ901_Classifica`)

- **Remover por completo** o bloco de numeração: `GetSxeNum("SF2"/"SF1",
  ...)`, o loop de incremento/verificação de disponibilidade, e a
  checagem de duplicidade contra `SF2`/`SF1`.
- **Remover por completo** a troca de ambiente (`RpcClearEnv()`/
  `RpcSetEnv(aEmp[1], aEmp[2], ...)`) — não sobra nada nesta função que
  precise da filial real.
- **Manter**: resolução de `cOper`/`cCod`/`cLoja`/`cTab` (SA1/SA2),
  validação SX5 de série (é só cadastro, compartilhado — pode continuar
  aqui como fail-fast antes de gravar, sem precisar de filial real),
  loop de produtos (CFOP/TES/NCM/CEST), enriquecimento do `oHead`.
- **Ajustar**: `oHead['_NF']` não é mais setado aqui — remover essa
  atribuição. `oHead['_SER']` continua sendo setado (é resolução de
  série cadastrada, não geração de número).
- Toda nota classificada com sucesso agora **sempre** vira um registro em
  `ZZA`/`ZZB`/`ZZC` via `U_ZZX_Gravar` — não existe mais o atalho de
  "já processada, marca `ZZ9_STATUS='S'` sem gravar" (isso migra pra
  dentro de cada Job de destino, ver Parte 3).

## Parte 2 — Função de numeração compartilhada

Extrair o bloco de numeração removido do `ZZ901_Classifica` pra uma
função nova em `FATPI01U.prw`:

```advpl
User Function PI_NUMERA_X(cTabFis, cCampoDoc, cSer, cCod, cLoja)
```//
- `cTabFis`: `"SF2"` (saída/NFCe) ou `"SF1"` (entrada/devolução).
- `cCampoDoc`: `"F2_DOC"` ou `"F1_DOC"`.
- Gera via `GetSxeNum(cTabFis, cCampoDoc)`, confere disponibilidade
  (loop com `Soma1` até achar livre, mesmo padrão que já existia), e
  também checa duplicidade (nota já existe pra esse `cCod`/`cLoja`/
  `cSer` — mesma query que existia dentro do `ZZ901_Classifica`).
- Retorno: `{lOk, cNF, lDuplicado}` — `lDuplicado = .T.` quando a nota
  já foi processada antes (quem chama decide o que fazer: tratar como
  sucesso sem gravar de novo, não como erro).

**Confirmado com o Arthur**: quando a duplicidade é detectada, o
callback pro iPaaS deve informar sucesso, mas com mensagem explícita de
"nota já processada anteriormente" — não uma mensagem de sucesso genérica
indistinguível de uma gravação nova. Isso é requisito de contrato, não
só decisão técnica interna.

## Parte 3 — `FATZZA01.prw`/`FATZZB01.prw`/`FATZZC01.prw`

Em cada motor (`ZZA_MotorSaida`, `ZZB_MotorDevolucao`,
`ZZC_MotorEntrada`), logo **depois** da troca de ambiente que já existe
(`If aEmp[1] != cEmpAnt .Or. ... RpcSetEnv(aEmp[1], aEmp[2], ...)`) e
**antes** da chamada ao motor fiscal (`U_PI_SAIDA_X`/`U_PI_DEVOL_X`/
`U_PI_GERAPC_X`), inserir:

```advpl
Local aNum := U_PI_NUMERA_X("SF2", "F2_DOC", AllTrim(U_PI_STR_X(oHead,'_SER')), AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')))
If !aNum[1] ; Return {.F., "NUMERACAO: " + aNum[2], cSub} ; EndIf
If aNum[3] ; Return {.T., "Ja processada anteriormente: " + aNum[2], cSub, xFilial("SF2"), aNum[2]} ; EndIf
```
(`"SF1"`/`"F1_DOC"` pra `ZZB`/`ZZC`, que usam `SF1`, conferir contra o
`xFilial("SF1")` que já aparece no retorno de sucesso de cada uma).

Trocar toda referência a `AllTrim(U_PI_STR_X(oHead,'_NF'))` (usada como
`cNF` nas chamadas ao motor) pelo `aNum[2]` recém-gerado.

**Atenção em `FATZZC01.prw`**: a numeração aqui é feita depois de
`U_PI_GERAPC_X` (que gera `cPCNew`, pedido de compra) e antes de
`U_PI_GERANF_X` (que usa `_NF`) — confirmar em qual dos dois pontos o
número de documento fiscal de entrada é realmente necessário antes de
inserir a chamada a `U_PI_NUMERA_X` no lugar certo (provavelmente só
antes de `U_PI_GERANF_X`, não antes de `U_PI_GERAPC_X`, mas conferir).

## Parte 4 — `FATZZD01.prw` (NFCe) — mesmo requisito do Arthur se aplica aqui

O pedido do Arthur (retornar sucesso + mensagem explícita de "já
processada anteriormente" em caso de duplicidade) **não foi restrito a
NFe** — vale igualmente pra NFCe. O `ZZD_MotorNFCe` já tem seu próprio
bloco de numeração com checagem de duplicidade (adicionado durante a
migração `LOJA701`→`PI_SAIDA_X`) — conferir se a mensagem de retorno
nesse caso já segue o mesmo formato explícito (`"Ja processada
anteriormente: " + cNF`) ou se hoje só retorna sucesso genérico; ajustar
pra bater com o padrão acima.

Trocar essa numeração própria por `U_PI_NUMERA_X("SF2", "F2_DOC", ...)`
(consolidação de código, evita duas implementações da mesma lógica) é
bem-vindo nessa mesma rodada, já que os dois pontos estão sendo
mexidos juntos — mas não é bloqueante, só oportuno.

## Parte 5 — Conferir se a mensagem de duplicidade chega de verdade no callback

O retorno `{.T., "Ja processada anteriormente: " + cNF, cSub, xFilial(...), cNF}`
vira, no loop principal de cada Job, `cSub`/`cFilCb`/`cDocCb` — mas a
**mensagem** ("Ja processada anteriormente...") vai em `aRet[2]`, que
hoje **não é repassado** pro `U_ZZCALLBK` em caso de sucesso (o loop só
usa `cSub`/`cFilCb`/`cDocCb`, a mensagem de `aRet[2]` se perde). Conferir
se o Arthur precisa dessa mensagem especificamente no payload do
callback (`des_Processamento`) — se precisar, o loop principal de cada
Job (`FATZZA01`/`B01`/`C01`/`D01`) precisa capturar `aRet[2]` também e
passar como `cMsgCustom` (8º parâmetro do `U_ZZCALLBK`, já existe desde o
`[FIX-CALLBACK-PRODUTO]`) em vez de deixar `""` como está hoje nas
chamadas de sucesso.

---

## Checklist

- [ ] `FATZZ901.prw`: zero `RpcSetEnv` no arquivo inteiro (fora do
      bootstrap inicial). Testado com nota de filial diferente da
      bootstrap (repetir o teste que achou o bug).
- [ ] `U_PI_NUMERA_X` criada em `FATPI01U.prw`, cobrindo `SF2`/`SF1`.
- [ ] `FATZZA01`/`FATZZB01`/`FATZZC01`: numeração movida pro ponto certo,
      usando o ambiente já trocado que já existia. Testado com nota que
      antes tinha caído com filial errada.
- [ ] Confirmar em `FATZZC01` se a numeração vai antes de
      `U_PI_GERAPC_X` ou só antes de `U_PI_GERANF_X`.
- [ ] Rodar as notas presas dos testes anteriores (que ficaram na `ZZA`/
      `ZZC` com filial errada) — corrigir manualmente o `ZZA_FILIAL`/
      `ZZC_FILIAL` delas pra `01001` depois do fix, senão ficam órfãs
      pra sempre (o fix vale pra notas novas, não retroage nas antigas).
- [ ] **Confirmado com o Arthur**: duplicidade retorna sucesso (não erro)
      com mensagem explícita "já processada anteriormente" — testar que
      essa mensagem chega de verdade no payload do callback (`des_Processamento`),
      não só no log interno (ver Parte 5).
- [ ] `FATZZD01`/NFCe: mesmo requisito de mensagem explícita aplicado,
      não só NFe.
