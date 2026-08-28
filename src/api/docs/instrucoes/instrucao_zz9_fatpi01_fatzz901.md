# Instrução — Migração FATPI01_V2 para ZZ9 + criação do Job FATZZ901

## Contexto (não pular)

Projeto CAASP/Protheus (Artiq). Arquitetura de filas assíncronas "Muro Z".
O endpoint `FATPI01_V2` hoje faz **duas coisas** numa chamada só: (1)
classifica a NFe (SA1/SA2, `cOper`, numeração, motor CFOP/TES) e (2)
enfileira o resultado já classificado em `ZZA`/`ZZB`/`ZZC`. Isso vai
parar de funcionar porque o iPaaS vai passar a mandar um aviso de
produto pendente **sem CFOP** — não dá mais pra classificar na hora do
recebimento.

Solução (Opção B, já validada e em produção no fluxo NFCe): intercalar
uma tabela intermediária `ZZ9` **só para NFe**. O endpoint vira fino
(só recebe e enfileira bruto na ZZ9); toda a classificação migra para
um Job novo, `FATZZ901`, que lê a ZZ9 e grava o resultado classificado
em ZZA/ZZB/ZZC — exatamente como o endpoint faz hoje, só que de forma
assíncrona.

A tabela `ZZ9` **já existe no SIGACFG** e a estrutura de campos/índices
já está formalizada no `CLAUDE.md` do projeto — **não inventar campos
novos**, usar exatamente o que já está documentado lá. Se o `CLAUDE.md`
não estiver acessível no ambiente do Claude Code, parar e avisar antes
de prosseguir, ao invés de supor a estrutura.

Ordem de compilação do projeto (não muda): `FATPI01U` → `FATPI01E` →
`FATPI01S` → `FATPI01D` → `FATPI01`. Entre os Jobs, `FATZZF01` compila
**primeiro** porque concentra funções compartilhadas (`ZZX_UpdStatus`,
`ZZX_Callback`) usadas pelos outros Jobs — `FATZZ901` depende dela
também.

---

## Parte 1 — Emagrecer `FATPI01_V2.prw`

Arquivo de referência atual: `FATPI01_V2.prw` (anexado nesta sessão).

### 1.1 — O que PERMANECE no endpoint (sem mudança de lógica)

- Bloco 1-2: declaração de variáveis, `SuperGetMv("MV_RESTNFE"...)`,
  `Self:SetContentType`. **Não reintroduzir `RpcSetEnv`** — o
  comentário `[PREPAREIN]` já documenta por que foi removido; isso
  continua valendo, o endpoint segue sem `RpcSetEnv`.
- Bloco 3: parse do JSON (`jJson:FromJson`), guard de payload vazio
  (400... na verdade `nStat := 200` conforme já está, não mexer nisso).
- Guard de modelo 65 (`cModDoc == "65"` → retorna erro orientando pro
  `/fatpi09/v2`). Continua igual.
- Resolução de filial via CNPJ: `cCnpj := U_PI_LIMPA_X(...)` e
  `aEmp := U_PI_FILIAL_X(cCnpj)`, com o erro "Filial nao encontrada"
  se `Len(aEmp) < 2`. Isso é validação leve e rápida, fica no endpoint.
- Extração de `cod_ChaveNFe` do `oHead` (hoje só é lido lá na hora do
  `ZZX_Gravar`, no endpoint fino precisa ser lido mais cedo, logo após
  identificar `oHead`).

### 1.2 — O que SAI do endpoint (migra inteiro para o Job, ver Parte 2)

Cortar tudo isso do `FATPI01_V2.prw`, do jeito que está, sem reescrever
a lógica — só mover:

- **Roteamento fiscal completo**: da linha `dVencto := U_PI_DATA_X(...)`
  até o fim do bloco de resolução de `cCod`/`cLoja`/`cFil`/`cOper`/`cTab`
  (inclui o ramo `cUsuario` para devolução via SA1, o `Do Case` de
  CFOP/transferência, a busca `U_PI_BUSCA_X`, o ajuste especial
  `cOper=='D' .AND. cTab=='SA2'` contra `SA2` ordem 3, e as validações
  de "Destinatario nao localizado" / "Fornecedor nao cadastrado").
- **Numeração e duplicidade**: bloco `nValNF := U_PI_VAL_X(...)` até a
  checagem de duplicidade em `SF2`/`SF1` e o `Return` antecipado de
  "Nota ja processada anteriormente" — **essa checagem de duplicidade
  específica (contra SF2/SF1, já classificada) migra pro Job**, porque
  só faz sentido depois que `cCod`/`cLoja`/`cOper` já foram resolvidos.
  Ver 1.3 para a duplicidade que o endpoint passa a fazer no lugar.
- **Limpeza de órfãos SFT/SF3** (`TCSqlExec` de `D_E_L_E_T_ = '*'`).
- **Loop de produtos completo** (`For nI := 1 To Len(aPrd)`): resolução
  de produto legado→interno via `SB1`/`LEGADO`, validação NCM/CEST
  (`BuscaCad`), `U_PI_FIXPROD`, resolução de CFOP via
  `oMotorRegras:ProcessaRegras`, resolução de TES via `SF4`, e a busca
  de `_NFORI`/`_SERIORI`/`_ITEMORI` em `SD2` para devolução.
- **Enriquecimento do `oHead`** com `_COD/_LOJA/_NF/_SER/_LEG/_FIL/_TAB/
  _TRANSF/_COND/_CNPJEMIT/_CNPJDEST` — esse bloco também migra, mas
  passa a rodar **dentro do Job**, sobre o JSON que foi lido de volta
  da `ZZ9` (não sobre o `jJson` recebido na requisição).
- **Pré-validação SX5** (série cadastrada na Tabela 01) que hoje roda
  só para `cOper == "S"`, antes do `ZZX_Gravar` — migra junto, roda no
  Job antes do `ZZX_Gravar` final em ZZA.
- **O `Do Case cOper` de enfileiramento em ZZA/ZZB/ZZC** — sai do
  endpoint por completo. O endpoint não decide mais `cOper`, então não
  tem como decidir em qual tabela final gravar.

### 1.3 — O que É NOVO no endpoint

Substituir o bloco cortado por:

1. Checagem de duplicidade **contra a ZZ9** (não mais contra SF2/SF1):
   `SELECT ZZ9_COD FROM <tabela ZZ9> WHERE ZZ9_CHVNFE = <chave> AND
   ZZ9_STATUS IN ('P','A','S') AND D_E_L_E_T_ = ' '`. Se encontrar,
   responder sucesso informativo tipo "NFe já enfileirada
   anteriormente" (mesmo espírito da resposta atual de "Nota ja
   processada", só que apontando pra fila em vez de nota lançada) e
   sair sem gravar de novo.
   - Incluir `'S'` no filtro (não só `'P'/'A'`) porque uma nota que já
     foi processada pelo Job e está com `ZZ9_STATUS='S'` não deve ser
     reenfileirada se o iPaaS reenviar o mesmo payload.
2. Gravação bruta na ZZ9: `ZZ9_FILIAL`, `ZZ9_COD` (via `GetSxeNum`),
   `ZZ9_STATUS := "P"`, `ZZ9_CHVNFE := <chave>`, `ZZ9_JSON :=
   jJson:toJSON()`, `ZZ9_PRDPEN := <lido do payload>` (ver abaixo),
   `ZZ9_DESTMU := ""` (vazio até o Job classificar), timestamps de
   inclusão. Seguir o padrão de `RecLock`/`FieldPut`/`ConfirmSx8` que
   `ZZX_Gravar` já usa hoje, adaptado pros campos da ZZ9 (não
   reaproveitar `ZZX_Gravar` aqui — ela é parametrizada pra ZZA/B/C/D/E
   com `_CHVNFE`/`_CODRCB`, a ZZ9 pode usar a mesma função se os nomes
   de campo baterem; **conferir se `ZZX_Gravar` genérica já resolve
   pra ZZ9 antes de duplicar código** — provavelmente sim, já que ela
   recebe `cTabMuro` como parâmetro).
   - **`ZZ9_PRDPEN` vem do payload, campo `prod_Pendente` (S/N) na
     raiz do JSON**, irmão de `notas`/`items` — **não** dentro do
     `oHead`/item da nota:
     ```json
     {
         "prod_Pendente": "N",
         "notas": [ {dados...} ]
     }
     ```
     Ler com `jJson['prod_Pendente']` logo após o `FromJson`, junto
     com a extração de `aInv`/`oHead` (não com `U_PI_STR_X` sobre
     `oHead`, que é escopo do item da nota). Gravar o valor lido
     direto em `ZZ9_PRDPEN` (default `"N"` só se a chave vier ausente
     ou vazia no payload).
3. Resposta de sucesso: status 201, `jRes['doc'] := "NFe enfileirada
   na ZZ9: " + <chave>`.

### 1.4 — Estrutura final esperada do `WSMETHOD POST` de `FATPI01_V2`

```
1. Ambiente (MV_RESTNFE) — igual
2. Parse JSON — igual
3. Identifica objeto/natureza, guard modelo 65 — igual
4. Extrai cod_ChaveNFe do oHead
5. Resolve filial via CNPJ (aEmp) — igual
6. Se lOk: checa duplicidade contra ZZ9 (novo)
7. Se não duplicado: grava bruto na ZZ9 (novo)
8. Monta resposta, restaura MV_RESTNFE, retorna
```

Tamanho esperado: cai de ~600 linhas pra provavelmente menos de 150.

---

## Parte 2 — Novo Job `FATZZ901.prw`

### 2.1 — Esqueleto do arquivo

Job Schedule, roda sem `PREPAREIN` (diferente do endpoint) — **precisa**
de `RpcSetEnv`/`RpcClearEnv`, com bootstrap fixo via `#Define CEMPPAD`/
`CFILPAD` no topo (não dá pra usar `SuperGetMv` nesse ponto, `SX6`
ainda não existe — regra já documentada no projeto). **Antes de
escrever esse bootstrap do zero, abrir um dos Jobs já existentes
(`FATZZA01.prw`, `FATZZD01.prw` etc., devem estar no repositório do
Claude Code mesmo não estando anexados aqui) e replicar exatamente o
padrão de abertura de ambiente que eles já usam** — não inventar um
novo padrão de bootstrap.

### 2.2 — Query principal

```
SELECT ZZ9_FILIAL, ZZ9_COD, R_E_C_N_O_ AS RECNO
FROM <tabela ZZ9>
WHERE ZZ9_STATUS IN ('P','A')
  AND ZZ9_PRDPEN = 'N'
  AND D_E_L_E_T_ = ' '
```

- `STATUS IN ('P','A')`, não só `'P'` — regra já documentada (senão
  registro que trava em "Em Andamento" por Job interrompido fica
  órfão pra sempre).
- `PRDPEN = 'N'` — registros com produto pendente ficam parados na
  ZZ9 até serem liberados (fluxo futuro do `FATPI10`, fora de escopo
  aqui).
- Ler o JSON via `R_E_C_N_O_` + `DbGoto` na área nativa — **nunca ler
  campo memo direto do resultset SQL** (regra já documentada, já
  causou bug real).

### 2.3 — Corpo do loop (por registro)

Para cada `ZZ9` pendente:

1. `DbGoto(RECNO)` na área nativa da ZZ9, ler `ZZ9_JSON`.
2. `jJson:FromJson(ZZ9_JSON)`, reconstituir `oHead`, `aPrd`, `cNatOp`,
   `cModDoc`, `cCheckCFOP`, `lIsTransf`, `cCnpj`, `cCnpjEmit`,
   `cCnpjDest` — mesma lógica de extração que hoje está nas linhas
   ~136-175 do `FATPI01_V2.prw` original (identificação do objeto e
   natureza), reaproveitada aqui porque o Job também precisa desses
   valores derivados do JSON bruto.
   - `prod_Pendente` (raiz do JSON) **não precisa ser relido aqui** —
     o filtro `ZZ9_PRDPEN = 'N'` da query em 2.2 já garante que só chegam
     nesse ponto os registros com produto liberado. Não confundir esse
     campo de raiz com nada dentro de `oHead`.
3. Rodar o bloco de **roteamento fiscal completo** (item 1.2, primeiro
   sub-bullet) — cole a lógica tal como está, só trocando o que hoje
   sai direto em `jRes`/`Return .T.` do WSMETHOD por gravação de erro
   na ZZ9 (`ZZ9_STATUS := "E"`, `ZZ9_ERRMSG := <mensagem>`) e `Loop`
   pro próximo registro, ao invés de abortar a requisição HTTP inteira
   — aqui é um Job, um registro com erro não pode travar os outros.
4. Rodar **numeração + duplicidade real** (contra SF2/SF1) — se
   duplicado, marcar `ZZ9_STATUS := "S"` direto (nota já existe,
   não precisa reprocessar) e `Loop`.
5. Limpeza SFT/SF3 órfãos — igual ao endpoint original.
6. **Loop de produtos completo** (item 1.2) — igual ao endpoint
   original, incluindo motor CFOP/TES.
7. Enriquecer `oHead` com os campos sintéticos (`_COD/_LOJA/_NF/...`)
   — igual ao endpoint original.
8. Pré-validação SX5 se `cOper == "S"` — igual.
9. Gravar na tabela final via `ZZX_Gravar("ZZA"/"ZZB"/"ZZC", ...)` —
   **ver 2.4 sobre promoção dessa função**.
10. Se `ZZX_Gravar` retornar sucesso: `ZZ9_STATUS := "S"` +
    `ZZ9_DESTMU := "ZZA"/"ZZB"/"ZZC"` (conforme `cOper`). Se falhar:
    `ZZ9_STATUS := "E"` + `ZZ9_ERRMSG` com o motivo.
11. Usar `U_ZZX_UpdStatus` (função compartilhada já existente em
    `FATZZF01`) pra gravar `_DTPROC`/`_HRPROC` junto com o status —
    a ZZ9 tem esses campos (diferente da ZZF, que não tem — regra já
    documentada não se aplica aqui).

### 2.4 — Promoção de `ZZX_Gravar` (decidido)

Hoje `ZZX_Gravar` é `Static Function` dentro de `FATPI01_V2.prw` — só
visível para o próprio endpoint. Pra `FATZZ901` conseguir chamá-la:

- **Mover `ZZX_Gravar` de `FATPI01_V2.prw` para `FATZZF01.prw`**, junto
  das outras funções compartilhadas (`ZZX_UpdStatus`, `ZZX_Callback`),
  e renomear de `Static Function` para `User Function`.
- Conferir colisão de nome pelos 10 primeiros caracteres de `U_` +
  nome (`U_ZZX_GRAV` — checar se já não colide com nada existente no
  projeto antes de compilar).
- Remover a definição de `ZZX_Gravar` de dentro de `FATPI01_V2.prw`
  depois de movida — não deixar cópia duplicada nos dois arquivos.
- Se a Parte 1.3 reaproveitar `ZZX_Gravar` genérica pra gravar também
  na própria ZZ9 (em vez de um `RecLock`/`FieldPut` manual só pra ZZ9),
  ela já está acessível de `FATPI01_V2.prw` normalmente, por ser
  `User Function` compartilhada — sem trabalho extra.

---

## Parte 3 — Checklist de validação pós-implementação

- [ ] Confirmar estrutura de campos da `ZZ9` contra o `CLAUDE.md` do
      projeto antes de escrever qualquer `FieldPut` — não assumir.
- [ ] Confirmar que os prefixos `ZZA`-`ZZF` ainda estão livres no
      SIGACFG (já é um pendente anterior, não específico desta tarefa,
      mas vale reconferir já que mexemos nesse fluxo).
- [ ] `FATZZF01` precisa compilar **antes** de `FATZZ901` (contém
      `ZZX_Gravar` promovida + `ZZX_UpdStatus`/`ZZX_Callback`).
- [ ] Rodar teste ponta a ponta com nota real: POST em `/fatpi01/v2` →
      confirma registro `STATUS='P'` na ZZ9 → roda `FATZZ901` →
      confirma registro `STATUS='S'` + `DESTMU` preenchido na ZZ9 e
      registro correspondente criado em ZZA/ZZB/ZZC com o `_TRANSF`
      correto quando aplicável.
- [ ] Testar reenvio do mesmo payload (mesma chave NFe) duas vezes
      seguidas no endpoint — segunda chamada deve retornar "já
      enfileirada" sem duplicar linha na ZZ9.
- [ ] Verificar encoding em todas as strings alteradas (regra já
      documentada — Claude Code já corrompeu acentuação em rodadas
      anteriores).
- [x] `ZZX_Gravar` promovida para `User Function` dentro de
      `FATZZF01.prw` — decisão fechada, ver seção 2.4.
- [x] Origem do `ZZ9_PRDPEN` confirmada: campo `prod_Pendente` (S/N)
      na raiz do payload — ver seção 1.3.
