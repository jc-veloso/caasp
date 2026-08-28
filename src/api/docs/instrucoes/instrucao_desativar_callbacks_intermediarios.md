# Instrução — Comentar callbacks intermediários (produto/cliente/fornecedor pendente)

## Contexto

Alinhamento pendente com o Arthur sobre a semântica exata de `"A"`
(`flg_Processamento`) no momento de liberação de nota por resolução de
pendência (produto/cliente/fornecedor) — o código atual documenta que o
Protheus só manda `"S"`/`"E"`, nunca `"A"` (ver comentário em
`CBackIpaas`), mas isso pode estar desatualizado frente ao que foi
combinado agora. Discussão longa, não é urgente resolver hoje.

**Decisão pragmática, pra não travar em cima dessa discussão**: comentar
os callbacks **intermediários** (disparados na liberação da nota por
pendência resolvida, antes do processamento fiscal de verdade) —
manter **só** o callback do processamento final da nota (sucesso/erro
real, disparado por `FATZZA01`/`B01`/`C01`/`D01`/`E01` depois que
`U_PI_SAIDA_X`/etc. roda). Reavaliar e reativar quando a semântica de
`"A"` estiver fechada com o Arthur.

**Não comentar** os callbacks de processamento final (fora de escopo
desta instrução) — só os cinco pontos abaixo, todos ligados a
liberação/erro de **pendência**, não ao resultado final da nota.

## Pontos a comentar

### `FATZZF01.prw` (produto pendente)

Linhas 126, 128 (sucesso — liberação por produto cadastrado) e 156
(falha — produto pendente não cadastrado). Comentar as três chamadas,
com marcador pra fácil localização:
```advpl
// [TEMP-CALLBACK-OFF] Jose Carlos - Artiq - 08/2026
// Callback intermediario de liberacao desativado - pendente alinhar com
// Arthur a semantica exata de flg_Processamento="A". Reavaliar antes de
// reativar. So o callback do processamento final da nota (FATZZA01/
// B01/C01/D01/E01) continua ativo.
// U_ZZCALLBK("ZZE", cChvRef, "", .T., "", "", "", "Todos os produtos cadastrados. Nota liberada para processamento.")
```
(mesmo padrão de comentário nas outras duas linhas, cada uma com a
chamada original preservada comentada logo abaixo do marcador, não
apagada — facilita reativar depois sem precisar reescrever).

### `FATZZG01.prw` (cliente/fornecedor pendente)

Linhas 133 (sucesso — liberação por cadastro concluído) e 145 (falha —
cadastro de cliente/fornecedor falhou). Mesmo tratamento: comentar com o
marcador `[TEMP-CALLBACK-OFF]`, chamada original preservada comentada
logo abaixo.

## O que continua acontecendo, mesmo com o callback desativado

- `U_ZZ_LIBNF`/liberação da nota continua rodando normalmente — a nota
  ainda sai do estado de pendência e entra na fila de processamento.
- `U_UPDSTAT` (status da fila `ZZF`/`ZZG`) continua gravando normalmente.
- Só o **aviso pro iPaaS** nesse momento intermediário para de ser
  enviado — o iPaaS não vai saber que a pendência foi resolvida até o
  callback final da nota chegar (sucesso ou erro do processamento fiscal
  de verdade).

## Checklist

- [ ] Cinco pontos comentados (3 em `FATZZF01.prw`, 2 em `FATZZG01.prw`),
      com marcador `[TEMP-CALLBACK-OFF]` e a chamada original preservada
      (comentada, não apagada).
- [ ] Confirmar que nenhum callback de processamento final foi
      comentado por engano (só os 5 pontos listados acima).
- [ ] Retomar a discussão com o Arthur sobre a semântica de `"A"` antes
      de reativar — não reativar só porque "parece que faz sentido",
      sem confirmar o contrato de verdade.
