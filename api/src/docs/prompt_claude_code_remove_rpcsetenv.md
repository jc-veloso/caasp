# Remover RpcSetEnv/RpcClearEnv dos 5 endpoints REST

## Contexto

Confirmado (TDN oficial da TOTVS, doc "Abertura de ambiente em Web
Service", a partir da versão 12.1.27): **não se deve usar `RpcSetEnv`/
`RpcClearEnv` dentro de `WSRESTFUL`** — o ambiente já é preparado
automaticamente pelo `PREPAREIN` do `appserver.ini`, e empresa/filial
vêm resolvidos pelo header `TenantId` da requisição. Chamar
`RpcSetEnv` de novo dentro do endpoint conflita com esse ambiente já
aberto — foi a causa do erro que estávamos vendo.

**Importante: isso vale só pros 5 ENDPOINTS. Os 6 JOBS (`FATZZA01` até
`FATZZF01`) continuam precisando de `RpcSetEnv` — eles rodam via Schedule,
começam sem ambiente nenhum, `PREPAREIN` não se aplica a eles. Não tocar
nos Jobs.**

José Carlos já testou e confirmou que comentar essas linhas resolve, no
`FATPI09.prw`. Esta tarefa é replicar o mesmo padrão **removendo de
verdade** (não só comentando) nos 5 arquivos, e limpando o código morto
que sobra.

## Arquivos afetados

`FATPI01_V2.prw`, `FATPI02_V2.prw`, `FATPI08_V2.prw`, `FATPI09.prw`,
`FATPI10.prw`

## O que remover, em cada um

Usar `FATPI09.prw` como referência do padrão exato a procurar (adaptar o
`cEmp`/`cFil` que cada arquivo usa, os nomes podem variar):

### 1. Remover a preparação de ambiente
```advpl
// REMOVER POR COMPLETO (não só comentar):
If Type("cEmpAnt") == "U" .Or. Empty(cEmpAnt) .Or. Select("SX6") == 0
    RpcSetEnv(cEmpAPI, cFilAPI, Nil, Nil, "LOJ")   // ou "FAT", varia por arquivo
    lAbreEnv := .T.
EndIf
```

### 2. Remover todo `If lAbreEnv ... RpcClearEnv() ... EndIf`
Cada ponto de saída da função (existem vários — todo `Return` cedo tem um
antes dele) tem um bloco assim, também pra remover por completo:
```advpl
// REMOVER POR COMPLETO:
If lAbreEnv
    RpcClearEnv()
EndIf
```

### 3. Remover as declarações `Local` que ficam órfãs
Depois dos passos 1 e 2, checar se estas variáveis ainda são usadas em
algum outro lugar da função — se não forem (não deveriam ser), remover a
declaração:
- `cEmpAPI`
- `cFilAPI`
- `lAbreEnv`

## Cuidado ao remover

Em cada arquivo, **antes de remover**, confirmar que a variável de
empresa/filial (`cEmpAPI`/`cFilAPI` ou nome equivalente) realmente não é
usada em mais nenhum lugar da função além do bloco de `RpcSetEnv` que
está sendo removido — se for usada em outro contexto (pouco provável, mas
checar), manter a declaração e só remover a chamada de `RpcSetEnv` em si.

## Validação depois de aplicar (nos 5 arquivos)

1. Buscar `RpcSetEnv\|RpcClearEnv\|lAbreEnv` em cada arquivo — deve
   retornar **vazio** (nem ativo, nem comentado — remoção completa, sem
   sobra)
2. Balanceamento `If`/`EndIf` deve **diminuir** (removeu blocos inteiros)
   — comparar contagem antes/depois pra garantir que a remoção não
   desbalanceou nada
3. Confirmar que os 6 arquivos de Job (`FATZZA01` a `FATZZF01`) **não**
   foram tocados — eles mantêm `RpcSetEnv(CEMPPAD, CFILPAD, ...)` normal
