# Rename de funções FZ_ para PI_ — Projeto CAASP/Protheus

## Contexto

O prefixo `FZ_` usado em 27 `User Function` do projeto colide com fontes antigos
já compilados no ambiente do cliente. Vamos adotar `PI_` (referência ao próprio
padrão de nomenclatura já usado no projeto: FATPI01, FATPI02, FATPI08, FATPI09),
e aproveitar pra dar nomes que reflitam o que cada função realmente faz, em vez
de nomes abreviados sem contexto.

## Regra crítica do AdvPL/Protheus — LER ANTES DE EXECUTAR

`User Function` é chamada com o prefixo `U_` (ex: `U_PI_STR_X`), e o compilador
só considera os **primeiros 10 caracteres** desse nome completo (`U_` + nome)
pra checar duplicidade/link — não precisa que o nome tenha exatamente 10
caracteres, só que os primeiros 10 sejam únicos entre TODAS as funções do
projeto (as 27 daqui e qualquer outra `User Function` já existente nos fontes).

Antes de aplicar qualquer rename, gerar um script (Python ou o que preferir)
que:
1. Liste todas as `User Function` de todo o projeto (`.prw`/`.PRW`)
2. Confirme que os 27 novos nomes abaixo não colidem entre si nem com nenhuma
   outra função já existente, comparando só os 10 primeiros caracteres de
   `U_<nome>`
3. Só depois disso, aplicar o rename

## Escopo do rename

Renomear em **todos** os arquivos `.prw`/`.PRW` do projeto:
- A declaração (`User Function FZ_XXX(...)`)
- Toda chamada (`U_FZ_XXX(...)`)
- Referências em comentários que mencionem o nome antigo (pra não deixar
  documentação desatualizada)

## Tabela de/para (27 funções)

| Atual | Novo | O que a função faz |
|---|---|---|
| `FZ_STR_X` | `PI_STR_X` | Extrai string de JSON, com campo alternativo de fallback |
| `FZ_VAL_X` | `PI_VAL_X` | Extrai número de JSON, com fallback |
| `FZ_DATA_X` | `PI_DATA_X` | Converte data do JSON pra tipo Date |
| `FZ_LIMPA_X` | `PI_LIMPA_X` | Remove `.`, `-`, `/` de string (CNPJ/CPF) |
| `FZ_LOJA_X` | `PI_LOJA_X` | Motor NFCe — ExecAuto LOJA701 |
| `FZ_NAT_X` | `PI_NAT_X` | Natureza financeira do cliente (SA1) |
| `FZ_LOG_X` | `PI_LOG_X` | Grava log de erro do ExecAuto em arquivo |
| `FZ_INVERT_CFOP` | `PI_INVCFOP` | Inverte dígito do CFOP (Saída↔Entrada) |
| `FZ_CC_X` | `PI_CCUSTO_X` | Centro de custo do produto (B1_CC) |
| `FZ_ACC_X` | `PI_CONTA_X` | Conta contábil do produto (B1_CONTA) |
| `FZ_LOC_X` | `PI_LOCAL_X` | Local/armazém padrão do produto (B1_LOCPAD) |
| `FZ_GETEST` | `PI_UF_X` | Estado (UF) do cliente |
| `FZ_INF_X` | `PI_CHVNFE_X` | Grava chave de acesso NFe no SF2 |
| `FZ_SM0_X` | `PI_FILIAL_X` | Busca filial por CNPJ (SM0) |
| `FZ_SQL_X` | `PI_BUSCA_X` | Busca genérica de cliente por chave |
| `FZ_PRD_X` | `PI_PROD_X` | Upsert de produto (MATA010) |
| `FZ_PROS_X` | `PI_SAIDA_X` | Motor NFe Saída |
| `FZ_PRDEV_X` | `PI_DEVOL_X` | Motor NFe Devolução |
| `FZ_PROC_X` | `PI_GERAPC_X` | Motor de compra — gera PC (MATA120) |
| `FZ_PRON_X` | `PI_GERANF_X` | Converte PC em NF de entrada (MATA103) |
| `FZ_GER_E2` | `PI_GER_E2` | Gera título no SE2 (contas a pagar) |
| `FZ_E103_GEN` | `PI_EXE103_X` | Wrapper genérico do MATA103 |
| `FZ_EX120_X` | `PI_EXE120_X` | Wrapper genérico do MATA120 |
| `FZ_FIX_PROD` | `PI_FIXPROD` | ⚠️ Corpo vazio hoje (só `Return`) — nome pela intenção aparente |
| `FZ_SETFCA` | `PI_SETFCA` | ⚠️ Corpo vazio hoje (só `Return`) — propósito real incerto, nome mantido igual (só prefixo trocado) |
| `FZ_COND_X` | `PI_COND_X` | ⚠️ Hoje só `Return c` (passa-reto, sem lógica) — nome mantido igual (só prefixo trocado) |
| `FZ_COND9` | `PI_COND1_X` | ⚠️ Sempre retorna `"001"` hardcoded |

As 4 marcadas com ⚠️ são stubs ou passa-reto sem lógica real hoje — o rename
não muda o comportamento delas, só o nome. Vale confirmar com o Antonio (autor
original) se algum dia tiveram lógica e foram esvaziadas, mas isso não bloqueia
o rename.

## Depois de aplicar

Rodar um diff estrutural simples em cada arquivo alterado (contagem de
`If`/`EndIf`, `For`/`Next`) comparando antes/depois — deve ser idêntico, já que
é troca de texto pura, não deveria alterar nenhuma lógica.
