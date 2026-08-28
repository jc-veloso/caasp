# Instrução — Correções globais urgentes (filial errada + FATPIEMP inacessível)

## 1. `CEMPPAD`/`CFILPAD` errado em seis Jobs

Confirmado por varredura em todos os fontes do projeto: só o `FATZZF01.prw`
tem a filial de bootstrap corrigida pra `"01"`/`"01001"` (ambiente CAASP,
confirmado com o Zé Carlos). Todos os outros Jobs ainda estão com o valor
antigo/errado `"99"`/`"01"`:

```
FATZZ901.prw
FATZZA01.prw
FATZZB01.prw
FATZZC01.prw
FATZZD01.prw
FATZZE01.prw
```

**Padrão de declaração**: `Static` no topo do arquivo (fora de função),
não `#Define` — mesma abordagem que o `FATZZF01.prw` já está adotando
(só falta o `:=`, que é o próprio erro de sintaxe que travou aquele
arquivo). Em todos os seis Jobs acima, trocar:
```advpl
#Define CEMPPAD "99"
#Define CFILPAD "01"
```
por:
```advpl
Static CEMPPAD := "01"
Static CFILPAD := "01001"
```
(reparar no `:=` — sem ele não compila, foi exatamente o problema que já
apareceu no `FATZZF01.prw`).

**Por que isso é urgente**: cada Job filtra sua query principal por
`WHERE ZZX_FILIAL = xFilial('ZZX')`, avaliado logo após o `RpcSetEnv`
inicial. Como os registros são gravados pelos endpoints na filial real
(`01`/`01001`, via PREPAREIN/TenantId), mas os Jobs abrem ambiente em
`99`/`01`, **nenhum desses seis Jobs encontra registro nenhum pra
processar** — falha silenciosa, sem erro, só fila que nunca esvazia.
Isso pode já estar mascarando outros problemas em teste (parece "Job não
faz nada" quando na verdade é "Job não vê os dados").

`FATZZF01.prw` já está com o valor certo (`Static CEMPPAD "01"` /
`Static CFILPAD "01001"`), só falta o `:=` — combinado que o Antonio
ajusta essa parte separadamente, não mexer nela aqui. Só garantir que os
outros seis arquivos fiquem usando a mesma sintaxe `Static ... := ...`
pra não haver dois padrões diferentes coexistindo no projeto.

## 2. `FATPIEMP` — `Static Function` no arquivo errado, bloqueia o motor de Saída

`FATPIEMP` está definida como `Static Function` em `FATPI01U.prw` (linha
269) — só visível dentro daquele arquivo. Mas é **chamada** de dentro de:
- `FATPI01S.prw`, linha 685, dentro de `PI_SAIDA_X` (o motor `MaNfs2Nfs`
  que `FATZZA01.prw` já usa pra NFe Saída, e que a NFCe vai passar a usar
  também).
- `FATPI01D.prw`, linha 93.
- `FATPI01E.prw`, linhas 66 e 263.

Mesmo padrão de bug já visto com `BuscaCad`/`ZZX_Gravar`: no monólito
original (`FATPI01__2_.prw`) funcionava porque tudo vivia no mesmo
arquivo; depois da separação em `FATPI01D`/`FATPI01E`/`FATPI01S`/
`FATPI01U`, essa função ficou presa como `Static` num arquivo que os
outros não enxergam. Isso bloqueia `PI_SAIDA_X` (e os motores de Entrada
de `FATPI01D`/`FATPI01E`) em tempo de link/execução — provavelmente ainda
não estourou em teste porque a NFe "ainda não foi testada ponta a ponta
com nota real" (conforme o resumo do projeto).

**Correção**: promover `FATPIEMP` de `Static Function` para
`User Function` dentro de `FATPI01U.prw` (mesmo padrão já usado pras
outras utilidades desse arquivo: `PI_STR_X`, `PI_VAL_X`, `PI_FILIAL_X`
etc.). Atualizar as quatro chamadas (`FATPI01S.prw:685`,
`FATPI01D.prw:93`, `FATPI01E.prw:66`, `FATPI01E.prw:263`) de
`FATPIEMP(...)` para `U_FATPIEMP(...)`.

Conferir colisão de nome pelos 10 primeiros caracteres de `U_` + nome
(`U_FATPIEMP` — 10 caracteres exatos, no limite) antes de compilar.

## Checklist

- [ ] `CEMPPAD`/`CFILPAD` corrigidos pra `Static CEMPPAD := "01"` /
      `Static CFILPAD := "01001"` nos seis Jobs listados na seção 1
      (mesma sintaxe `Static ... := ...` em todos, consistente com o
      `FATZZF01.prw` depois que o Antonio ajustar o `:=` lá).
- [ ] `FATPIEMP` promovida a `User Function` em `FATPI01U.prw`, chamadas
      atualizadas nos quatro pontos da seção 2.
- [ ] Teste de fumaça: rodar qualquer um dos seis Jobs manualmente com
      pelo menos um registro pendente na fila correspondente e confirmar
      que ele processa (não só "roda sem erro e sem fazer nada").
- [ ] Testar `PI_SAIDA_X` (via `FATZZA01`) ponta a ponta pela primeira vez
      com nota real, agora que `FATPIEMP` está resolvida — isso nunca foi
      validado de verdade ainda.
