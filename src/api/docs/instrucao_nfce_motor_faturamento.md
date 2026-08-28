# Instrução — NFCe sai do SIGALOJA (LOJA701) e passa a morar no Faturamento (MaNfs2Nfs)

## Contexto e decisão (não pular)

O `FATPI09.prw` (endpoint de NFCe) tinha uma decisão registrada no cabeçalho
de manter `LOJA701` (ExecAuto do módulo SIGALOJA, grava em `SL1`) por
enquanto, citando risco de recálculo fiscal indevido (a NFCe já foi
autorizada pela SEFAZ com os valores calculados pelo PDV da CAASP).

**Essa decisão foi revista.** Análise do fonte legado original (monolito
`FATPI01` pré-refatoração, que tratava NFe e NFCe juntos) mostrou que o
padrão correto é **NFCe morar no Faturamento (SF2/SD2), igual NFe**, só
marcada com `F2_ESPECIE := "NFCE"` (e `F3_ESPECIE` nos itens) — não em
`SL1`/SIGALOJA. O legado usava `MaNfs2Nfs` pra isso; o projeto atual já
tem o equivalente pronto: `U_PI_SAIDA_X` (a mesma função que `FATZZA01.prw`
já usa pra NFe Saída comum). O risco de recálculo fiscal existe também
aqui (aceito conscientemente, mesmo trade-off que já existe pra NFe) — não
é um problema resolvido pela troca, é um risco que passa a ser compartilhado
com o mesmo motor que a NFe já usa em produção.

**Arquivos envolvidos:** `FATZZD01.prw` (Job de NFCe — recebe a mudança
principal), `FATZZF01.prw` (candidato a receber `BuscaCad` promovida, ver
seção final), `FATZZ901.prw` (mesmo problema de `BuscaCad`).

---

## Parte 1 — `FATZZD01.prw`: trocar o motor

### 1.1 — Ambiente: sai "LOJ", entra "FAT"

- `User Function FATZZD01()`: `RpcSetEnv(CEMPPAD, CFILPAD, Nil, Nil, "LOJ")`
  vira `RpcSetEnv(CEMPPAD, CFILPAD, Nil, Nil, "FAT")`.
- Remover `Private __cXEvento := "LOJ"` (não se aplica mais — isso é
  específico do módulo SIGALOJA).
- Dentro de `ZZD_MotorNFCe`, a troca de ambiente por CNPJ também usa `"LOJ"`
  hoje (`RpcSetEnv(aEmp[1], aEmp[2], Nil, Nil, "LOJ")`) — trocar pra
  `"FAT"`, igual `ZZA_MotorSaida` (`FATZZA01.prw`) já faz.

### 1.2 — Numeração: bloco novo, não existia em `ZZD_MotorNFCe`

Hoje o comentário do arquivo (linha ~213) diz explicitamente que `cNF` não
é necessário porque `PI_LOJA_X` gera o próprio número via
`GetSxeNum("SL1","L1_NUM")`. Isso deixa de ser verdade — `PI_SAIDA_X`
precisa de um `F2_DOC` já resolvido.

Adicionar em `ZZD_MotorNFCe`, depois da resolução de `cSer` (linha ~218) e
antes do loop de produtos, o mesmo padrão de numeração + duplicidade que já
existe em `ZZ901_Classifica` (`FATZZ901.prw`), adaptado:
- `cCod`/`cLoja` já resolvidos (consumidor, sempre `SA1`).
- `cOper` é sempre `"S"` aqui (NFCe é sempre saída) — não precisa do
  `Do Case` que a NFe tem, só o ramo de saída.
- Gerar `cNF` via `GetSxeNum("SF2", "F2_DOC")` + loop de verificação de
  disponibilidade (mesmo padrão: consulta `SF2` por `F2_DOC`/`F2_SERIE`/
  `F2_CLIENTE`/`F2_LOJA`, incrementa com `Soma1` até achar livre).
- **Validação prévia de série (SX5)** — a NFe já protege contra "Problema
  Numeracao NF" checando a série na Tabela 01 antes de gravar (ver
  `ZZ901_Classifica`, bloco `cOper == "S"`). Adicionar a mesma checagem
  aqui antes de chamar `U_PI_SAIDA_X` — evita erro fatal do Protheus por
  série de NFCe não cadastrada na SX5.
- Checagem de duplicidade contra `SF2` (nota já processada) também deveria
  entrar aqui, mesmo padrão — hoje não existe porque `SL1` é uma tabela
  diferente da NFe, então nunca havia esse risco. Agora que passa a
  escrever em `SF2`, o mesmo risco de duplicidade existe.

### 1.3 — Chamada final: `U_PI_LOJA_X` → `U_PI_SAIDA_X`

**Assinatura confirmada** (conferida direto no fonte, `FATPI01S.prw`
linha 641):
```advpl
User Function PI_SAIDA_X(aPrd, oHead, cCli, cLoja, cLeg, cSer, cFil, cTab, lIsTransf, cNF, cSerNF, cLegT, cCond)
```
`cLeg`, `cFil`, `cSerNF` e `cLegT` são parâmetros declarados mas **nunca
usados dentro da função** — código morto (não são referências de origem
separadas, como eu tinha suspeitado antes de ver o fonte real). Podem ir
vazios na chamada, sem risco.

Troca:
```advpl
aRet := U_PI_LOJA_X(aPrd, oData, cCod, cLoja, cSer, cTab, cCondSafe)
```
por:
```advpl
aRet := U_PI_SAIDA_X(aPrd, oData, cCod, cLoja, "", cSer, "", cTab, .F., cNF, "", "", cCondSafe)
```
Onde `cNF` é o número gerado no bloco de numeração da seção 1.2, e `.F.`
no lugar de `lIsTransf` porque NFCe não tem fluxo de transferência/
CONVENIOS (isso é exclusivo de NFe Saída comum).

Ajustar checagem de retorno igual `ZZA_MotorSaida`:
```advpl
If !aRet[1]
    Return {.F., "MANFS2NFS: " + cValToChar(aRet[2]), cSub}
EndIf
```

**Atenção, pré-requisito bloqueante**: `PI_SAIDA_X` chama internamente
`FATPIEMP(...)`, que hoje é `Static Function` em `FATPI01U.prw` — não
visível de `FATPI01S.prw`. Isso precisa estar corrigido (ver instrução
separada `instrucao_correcoes_globais.md`, seção 2) **antes** desta
migração funcionar, senão `PI_SAIDA_X` quebra em runtime pra qualquer
chamador, incluindo o `FATZZA01` que já está em produção.

**Confirmado também**: `PI_SAIDA_X` só grava `F2_ESPECIE` como `"SPED"`
ou `"NFE"` (nunca `"NFCE"`) — o patch pós-gravação da seção 1.4 abaixo
continua necessário, não tem como evitar mexendo só na chamada.

### 1.4 — `F2_ESPECIE`/`F3_ESPECIE := "NFCE"` (pós-gravação)

Depois que `U_PI_SAIDA_X` retorna sucesso, o `aRet[2]` traz o número do
`F2_DOC` gerado (mesmo padrão do retorno de `ZZA_MotorSaida`). Adicionar:
```advpl
TCSqlExec("UPDATE " + RetSqlName("SF2") + " SET F2_ESPECIE = '" + PadR("NFCE", TamSx3("F2_ESPECIE")[1]) + "' WHERE F2_DOC = '" + PadL(AllTrim(cValToChar(aRet[2])), TamSx3("F2_DOC")[1], "0") + "' AND F2_SERIE = '" + cSer + "' AND F2_CLIENTE = '" + cCod + "' AND F2_LOJA = '" + cLoja + "' AND D_E_L_E_T_ = ' '")
TCSqlExec("UPDATE " + RetSqlName("SF3") + " SET F3_ESPECIE = '" + PadR("NFCE", TamSx3("F3_ESPECIE")[1]) + "' WHERE F3_NFISCAL = '" + PadL(AllTrim(cValToChar(aRet[2])), TamSx3("F2_DOC")[1], "0") + "' AND F3_SERIE = '" + cSer + "' AND F3_CLIEFOR = '" + cCod + "' AND F3_LOJA = '" + cLoja + "' AND D_E_L_E_T_ = ' '")
```
(Igual o legado fazia — ver `FATPI01__2_.prw`, linhas 1873-1879/2110-2122
e 2940-2946/3019 — os dois lugares onde `F2_ESPECIE`/`F3_ESPECIE` eram
gravados como `"NFCE"` pra modelo 65.)

### 1.5 — Retorno pro callback: `SL1` → `SF2`

```advpl
Return {.T., "Orcamento LOJA701: " + cValToChar(aRet[2]), cSub, xFilial("SL1"), cValToChar(aRet[2])}
```
vira
```advpl
Return {.T., "NFCe: " + xFilial("SF2") + " - " + cValToChar(aRet[2]), cSub, xFilial("SF2"), cValToChar(aRet[2])}
```
(igual `ZZA_MotorSaida` retorna pra NFe comum).

### 1.6 — Atualizar o cabeçalho do arquivo

O comentário `[FIX-MOTOR]` (linha ~24-26) e a descrição no topo dizem
"NFCe usa LOJA701" — atualizar pra refletir a migração, com data e o
motivo (decisão revista após análise do legado, ver Parte 1 do contexto
acima). Manter o histórico anterior (não apagar, só marcar como superado).

---

## Parte 2 — `BuscaCad` não é visível fora de `FATPI01U.prw` (achado à parte)

`BuscaCad` é `Static Function` dentro de `FATPI01U.prw` — só visível
naquele arquivo. Tanto `FATZZD01.prw` quanto `FATZZ901.prw` chamam
`BuscaCad(...)` na validação de NCM/CEST do loop de produtos, e nenhum dos
dois vai compilar/linkar sem isso.

**Correção recomendada**: promover `BuscaCad` a `User Function` dentro de
`FATZZF01.prw` (mesmo lugar de `ZZX_Gravar`/`UPDSTAT`/`ZZCALLBK`), já que
agora é usada por pelo menos dois Jobs diferentes — mais consistente que
copiar `Static Function` local em cada arquivo que precisar dela (evita
o mesmo problema se um terceiro Job vier a precisar). Atualizar as
chamadas em `FATZZD01.prw` e `FATZZ901.prw` de `BuscaCad(...)` para
`U_BUSCACAD(...)` (ou o nome que ficar depois da promoção, respeitando o
limite de 10 caracteres do AdvPL pra símbolo `U_` — `U_BUSCACAD` já tem 10,
está no limite, conferir se não colide com nada existente antes de
compilar).

Manter a função original em `FATPI01U.prw` intacta ou removê-la — decisão
do Antonio, já que ele mexe nesse arquivo (ver conversa anterior sobre o
`STATIC CEMPPAD`).

---

## Checklist de validação

- [x] Assinatura de `U_PI_SAIDA_X` confirmada em `FATPI01S.prw` — ver
      seção 1.3. `cLeg`/`cFil`/`cSerNF`/`cLegT` são parâmetros mortos,
      podem ir vazios.
- [ ] Pré-requisito bloqueante: `FATPIEMP` promovida a `User Function`
      (ver `instrucao_correcoes_globais.md`) — sem isso `PI_SAIDA_X`
      quebra em runtime.
- [ ] Pré-requisito: `CEMPPAD`/`CFILPAD` de `FATZZD01.prw` corrigidos pra
      `"01"`/`"01001"` (ver `instrucao_correcoes_globais.md`, seção 1) —
      sem isso o Job nem encontra os registros da ZZD pra processar.
- [ ] `BuscaCad` promovida pra `User Function` em `FATZZF01.prw`, chamadas
      atualizadas em `FATZZD01.prw` e `FATZZ901.prw`.
- [ ] Numeração de NFCe (novo bloco) testada com duas notas na mesma série
      pra confirmar que o incremento/duplicidade funciona.
- [ ] Validação de série (SX5) testada com uma série de NFCe não
      cadastrada na Tabela 01, pra confirmar que dá erro tratado em vez de
      erro fatal do Protheus.
- [ ] `F2_ESPECIE`/`F3_ESPECIE` conferidos como `"NFCE"` após uma nota real
      processada — não `"NFE"` genérico.
- [ ] Callback (`U_ZZCALLBK`) testado ponta a ponta — confirmar que o
      `cFilCb`/`cDocCb` batem com o `SF2` gerado, não mais com `SL1`.
- [ ] Teste ponta a ponta completo: POST `/fatpi09/v2` com nota real →
      `FATZZD01` processa → nota aparece em `SF2` (não em `SL1`) com
      `F2_ESPECIE = 'NFCE'`.
