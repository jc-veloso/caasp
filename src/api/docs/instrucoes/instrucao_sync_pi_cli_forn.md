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
- [ ] Considerar, como prevenção pra próxima vez: se `FATPI06.prw`/
      `FATPI03.PRW` ainda tiverem lógica própria (não delegando pra
      `U_PI_CLI_X`/`U_PI_FORN_X`), avaliar se vale fazer os dois
      endpoints síncronos chamarem as funções compartilhadas também (como
      já ficou combinado desde a instrução original da ZZG) — isso
      eliminaria de vez o risco de as duas cópias divergirem de novo no
      futuro.
