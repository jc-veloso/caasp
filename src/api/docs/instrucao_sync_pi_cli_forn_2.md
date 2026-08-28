# Instrução — Sincronizar `PI_CLI_X`/`PI_FORN_X` com as correções já validadas

## Contexto

`U_PI_CLI_X`/`U_PI_FORN_X` (`FATPI01U.prw`) foram extraídas de
`FATPI06.prw`/`FATPI03.PRW` **antes** das correções de mapeamento de
campo que fechamos comparando contra os payloads reais do Arthur
(`Json tabela muro Cliente.txt`/`Json tabela muro Fornecedor.txt`). O
caminho síncrono (`FATPI06`/`FATPI03`, se ainda tiver lógica própria) já
está certo; o caminho assíncrono (`FATPI11`→`ZZG`→`FATZZG01`→`PI_CLI_X`/
`PI_FORN_X`) está desatualizado — precisa sincronizar antes de ir pra
produção, senão cliente/fornecedor cadastrado via fila sai com campo
errado/vazio.

**Referência de verdade**: os `FATPI06.prw`/`FATPI03.PRW` já corrigidos
(enviados nesta sessão) — não o payload de exemplo isolado, que só serviu
pra descobrir a divergência.

---

## Parte 1 — `PI_CLI_X` (cliente)

### 1.1 — `A1_COD_MUN`: falta o default de `cod_Municipio`

Hoje (`FATPI01U.prw`, ~linha 382):
```advpl
If !Empty(U_PI_STR_X(oJson, "cod_ibge"))
    oSA1Mod:SetValue("A1_COD_MUN", U_PI_STR_X(oJson, "cod_ibge"))
EndIf
```
Trocar pra bater com `FATPI06.prw` atualizado — default primeiro, depois
override:
```advpl
oSA1Mod:SetValue("A1_COD_MUN", U_PI_STR_X(oJson, "cod_Municipio"))

If !Empty(U_PI_STR_X(oJson, "cod_ibge"))
    oSA1Mod:SetValue("A1_COD_MUN", U_PI_STR_X(oJson, "cod_ibge"))
EndIf
```
Posicionar antes do `If oModel:VldData()`, mesmo lugar relativo que já
está hoje.

### 1.2 — `A1_PESSOA`: falta a lógica F/J por tamanho de documento

Hoje (~linha 379): `oSA1Mod:SetValue("A1_PESSOA" , "F")` fixo. Trocar
pra bater com `FATPI06.prw` atualizado:
```advpl
If Len(U_PI_STR_X(oJson, "cpf")) = 11
    oSA1Mod:SetValue("A1_PESSOA" , "F")
ElseIf Len(U_PI_STR_X(oJson, "cpf")) = 14
    oSA1Mod:SetValue("A1_PESSOA" , "J")
EndIf
```
(Substituir a linha fixa por esse bloco — remover a linha antiga.)

---

## Parte 2 — `PI_FORN_X` (fornecedor)

### 2.1 — `A2_NUMCON`: campo errado no JSON

Hoje (~linha 480):
```advpl
oModel:SetValue("SA2MASTER", "A2_NUMCON" , cValToChar(jItem["num_ContaCorrente"]))
```
Trocar pra:
```advpl
oModel:SetValue("SA2MASTER", "A2_NUMCON" , cValToChar(jItem["num_Conta"]))
```

### 2.2 — Três campos ausentes, adicionar no mesmo bloco bancário/localização

Bater com `FATPI03.PRW` atualizado — adicionar, próximo aos campos
correspondentes já existentes:
```advpl
oModel:SetValue("SA2MASTER", "A2_DVCTA"  , cValToChar(jItem["num_ContaDig"]))
oModel:SetValue("SA2MASTER", "A2_COD_MUN", AllTrim(cValToChar(jItem["cod_IBGE"])))
oModel:SetValue("SA2MASTER", "A2_CODPAIS", cValToChar(jItem["cod_pais"]))
```

---

## Contrato confirmado com o Arthur (16/08) — MUDOU de novo

**Atenção**: o significado de `tipo` mudou desde a primeira versão do
`FATPI11.prw`. Contrato final, confirmado:
```json
{
    "tipo": "NFC",
    "chave": "35260744692168005816550020000019451978264552",
    "tp_Participante": "CLI",
    "dados": { ...cadastro completo... }
}
```
- **`tipo`**: agora é o **tipo da nota** (mesmo domínio de `ZZG_TIPONF`
  já usado no projeto — `"ZZ9"` pra NFe, `"NFC"` pra NFCe; único domínio
  relevante hoje, conforme escopo já fechado na Parte 5 da instrução
  original). **Não é mais CLI/FOR.**
- **`tp_Participante`** (campo novo, nível raiz do envelope, fora de
  `dados`): é quem carrega `"CLI"`/`"FOR"` agora.
- **`chave`**: confirmado que **é** enviada — é a chave da nota
  (`cod_ChaveNFe`), minha suspeita anterior de que não viria estava
  errada (os dois exemplos que o Arthur mandou antes eram só o conteúdo
  de `dados`, não o envelope completo).
- **`dados`**: confirmado que **não** repete `tp_Participante` dentro —
  esse campo vive só no nível raiz do envelope agora. `dados` é
  exatamente os dois exemplos reais (`Json tabela muro Cliente.txt`/
  `Fornecedor.txt`) **menos** o campo `tp_Participante`, que já foi
  extraído pra fora. Sem impacto em `PI_CLI_X`/`PI_FORN_X` (Partes 1/2
  acima) — nenhuma das duas nunca leu esse campo de dentro do JSON.

## Parte 3 — Reescrever `FATPI11.prw` pro contrato novo

O código atual (`cTipo := U_PI_STR_X(jJson, 'tipo')`, validando
`cTipo $ "CLI/FOR"`, depois buscando a nota nas duas tabelas `ZZ9`/`ZZD`
até achar onde bate) fica **desatualizado** e precisa ser reescrito:

```advpl
Local cTipoNF  := Upper(AllTrim(U_PI_STR_X(jJson, 'tipo')))          // "ZZ9" ou "NFC"
Local cChave   := AllTrim(U_PI_STR_X(jJson, 'chave'))
Local cTipoPen := Upper(AllTrim(U_PI_STR_X(jJson, 'tp_Participante'))) // "CLI" ou "FOR"
Local jDados   := jJson['dados']
Local cTabAch  := ""
```

Validação de campos obrigatórios: `cTipoNF`, `cChave`, `cTipoPen`,
`jDados` (objeto) — todos obrigatórios agora, ajustar a mensagem de erro
de "Campos obrigatorios" pra listar os quatro.

Validar `cTipoNF $ "ZZ9/NFC"` (não mais `cTipoPen $ "CLI/FOR"` sozinho —
os dois precisam ser validados agora, ver abaixo).

Validar `cTipoPen $ "CLI/FOR"` (mesma validação de antes, só que lendo
de `tp_Participante` em vez de `tipo`).

**Busca da nota pai fica direta, não precisa mais varrer as duas
tabelas**: como `tipo` já diz qual é a tabela, elimina o loop `For nI :=
1 To Len(aTabs)` inteiro — substituir por:
```advpl
cTabAch := IIF(cTipoNF == "NFC", "ZZD", "ZZ9")

cQryAux := "SELECT " + cTabAch + "_CHVNFE FROM " + RetSqlName(cTabAch) + " WHERE " + cTabAch + "_CHVNFE = '" + cChave + "' AND D_E_L_E_T_ = ' '"
cAliAux := GetNextAlias()
MpSysOpenQuery(cQryAux, cAliAux)
If (cAliAux)->(Eof())
    (cAliAux)->(DbCloseArea())
    nStat := 200  // lembrar: NUNCA 404, ver Parte 4 abaixo
    jRes['status']    := nStat
    jRes['resultado'] := "Falha"
    jRes['erro']      := "NotaNaoEncontrada"
    jRes['mensagem']  := "Nota nao encontrada na " + cTabAch + " para chave: " + cChave
    Self:setStatus(nStat)
    Self:SetResponse(EncodeUTF8(jRes:toJSON()))
    Return .T.
EndIf
(cAliAux)->(DbCloseArea())
```

Daqui pra frente (gravação na `ZZG` via `U_ZZG_GRV(cChave, cTipoPen,
cTipoNF, jDados:toJSON())`, atualização de `<cTabAch>_CLIPEN`/`FORPEN`)
já usa as variáveis renomeadas (`cTipoPen` no lugar do antigo `cTipo`,
`cTabAch` já resolvido direto) — lógica de gravação em si não muda, só
os nomes/origem das variáveis.

## Parte 4 — Lembrete: status `404` ainda pendente (achado em rodada anterior)

Já tinha sido identificado que o `FATPI11` original usava `nStat := 404`
pra "nota não encontrada" — quebra a convenção do projeto (nunca 4xx/5xx,
sempre 200 com corpo explicando erro, iPaaS quebra em transporte com
4xx). Confirmar que isso foi corrigido nesta reescrita (o trecho de
código na Parte 3 acima já vem com `200`, só reforçando que é
intencional, não esquecer de novo).

## Checklist

- [ ] `PI_CLI_X`: `A1_COD_MUN` com default `cod_Municipio` + override
      `cod_ibge`, igual `FATPI06.prw`.
- [ ] `PI_CLI_X`: `A1_PESSOA` por tamanho de CPF/CNPJ (F/J), igual
      `FATPI06.prw`.
- [ ] `PI_FORN_X`: `A2_NUMCON` lendo `num_Conta` (não `num_ContaCorrente`).
- [ ] `PI_FORN_X`: `A2_DVCTA`/`A2_COD_MUN`/`A2_CODPAIS` adicionados.
- [ ] Testar via `FATPI11`→`ZZG`→`FATZZG01` com os dois payloads de
      exemplo reais (`Json tabela muro Cliente.txt`/`Fornecedor.txt`) e
      conferir `A1_COD_MUN`/`A1_PESSOA`/`A2_NUMCON`/`A2_DVCTA`/
      `A2_COD_MUN`/`A2_CODPAIS` gravados certos no `SA1`/`SA2` resultante.
- [ ] `FATPI11.prw` reescrito pro contrato novo (`tipo`=tipo de nota,
      `tp_Participante`=CLI/FOR, busca direta na tabela certa em vez de
      varrer as duas). Testado com os payloads reais do Arthur (envelope
      completo, não só o conteúdo de `dados`).
- [ ] Confirmado: `FATPI11` nunca retorna 404 (nem nenhum 4xx/5xx) —
      sempre 200 com corpo de erro.
- [ ] Considerar, como prevenção pra próxima vez: se `FATPI06.prw`/
      `FATPI03.PRW` ainda tiverem lógica própria (não delegando pra
      `U_PI_CLI_X`/`U_PI_FORN_X`), avaliar se vale fazer os dois
      endpoints síncronos chamarem as funções compartilhadas também (como
      já ficou combinado desde a instrução original da ZZG) — isso
      eliminaria de vez o risco de as duas cópias divergirem de novo no
      futuro.
