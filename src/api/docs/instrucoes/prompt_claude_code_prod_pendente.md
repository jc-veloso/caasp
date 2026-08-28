# Simplificar FATPI09 e FATPI08_V2 — confiar em `prod_Pendente` do payload

## Contexto

O iPaaS vai passar a mandar um campo novo no nível raiz do payload,
irmão de `"notas"`:

```json
{
  "prod_Pendente": "S",  // ou "N"
  "notas": [ { ... } ]
}
```

Isso substitui a checagem de produto que o próprio endpoint fazia. A
responsabilidade de detectar produto faltante passa a ser do iPaaS (via um
endpoint novo, ainda não implementado, fora do escopo desta tarefa). Os
dois endpoints abaixo só precisam **ler a flag e confiar nela**.

## Arquivo 1: `FATPI09.prw` (NFCe) — REMOVER lógica de checagem

### 1.1 — Ler o campo `prod_Pendente`
Logo depois de onde `jJson` é parseado/validado com sucesso (mesmo ponto
onde `oHead`/`aPrd` já estão disponíveis), extrair:
```advpl
Local cProdPend := AllTrim(U_PI_STR_X(jJson, 'prod_Pendente'))
If Empty(cProdPend) ; cProdPend := "N" ; EndIf  // default seguro se nao vier
```
(ajustar nome da variável se já existir alguma convenção local; declarar no
topo da função junto das outras `Local`, nunca depois de `Private`)

### 1.2 — Remover a seção "7. CHECAGEM DE EXISTENCIA DE PRODUTO"
Localizar e **remover por completo** o bloco entre os comentários
`// --- 7. CHECAGEM DE EXISTENCIA DE PRODUTO (1a passada...` e o `EndIf`
que fecha `If Len(aProdPend) > 0` (inclui o loop de scan no SB1, a
montagem do array `aProdPend`, e todo o branch que grava na `ZZF` +
`ZZD(PRDPEND='S')` e retorna cedo). Esse bloco inteiro deixa de existir —
a variável `aProdPend` e o loop `For nI := 1 To Len(aPrd)` que faz
`SB1->(DbSeek(...))` não são mais necessários aqui.

### 1.3 — Ajustar a gravação final na ZZD (seção "7b", vira só "7")
Trocar:
```advpl
If ZZX_Gravar("ZZD", "NFC", "CHVNFE", cChvNFe, jJson:toJSON())
```
Por:
```advpl
If ZZX_Gravar("ZZD", "NFC", "CHVNFE", cChvNFe, jJson:toJSON(), "", "", cProdPend)
```
(usa a assinatura de 8 parâmetros do `ZZX_Gravar`, que já existe e já
aceita PRDPEND como último argumento — só passar `cProdPend` em vez de
deixar no default `"N"`)

### 1.4 — Limpar imports/variáveis órfãs
Depois da remoção, checar se `SB1` ainda é referenciada em outro lugar da
função — se não for, não precisa de ação adicional (a área continua
disponível globalmente, só não é mais usada aqui).

## Arquivo 2: `FATPI08_V2.prw` (Recibo) — ADICIONAR leitura da flag

Este endpoint nunca teve checagem de produto própria — só precisa
**aprender a respeitar** a flag recebida, nada para remover.

### 2.1 — Ler o campo `prod_Pendente`
Mesmo padrão do item 1.1, no ponto onde `oData` já está disponível (perto
de onde `cExpCli`/`cCpfCnpj` são extraídos, seção "EXTRACAO DOS DADOS DO
USUARIO"):
```advpl
Local cProdPend := AllTrim(U_PI_STR_X(oData, 'prod_Pendente'))
If Empty(cProdPend) ; cProdPend := "N" ; EndIf
```

### 2.2 — Ajustar a gravação na ZZE
Localizar:
```advpl
If ZZX_Gravar("ZZE", "RCV", "CODRCB", cDocPad, cJson)
```
Trocar por:
```advpl
If ZZX_Gravar("ZZE", "RCV", "CODRCB", cDocPad, cJson, "", "", cProdPend)
```

## Validação depois de aplicar (nos dois arquivos)

1. Contagem de `If`/`EndIf` deve mudar **para menos** no `FATPI09.prw`
   (removeu um bloco inteiro com `If`s aninhados) e ficar **igual** no
   `FATPI08_V2.prw` (só adicionou 2 linhas simples, sem novo `If` de
   bloco — o `If Empty(cProdPend)` é de uma linha só com `;`, não conta
   como bloco separado).
2. Confirmar que `ZZF_Gravar` não é mais chamada em `FATPI09.prw` (a
   função em si continua existindo em `FATZZF01.prw`, só não é mais usada
   a partir daqui).
3. Rodar um teste manual com `prod_Pendente: "S"` e depois `"N"` em cada
   endpoint, conferindo que o `PRDPEN` gravado na `ZZD`/`ZZE` bate com o
   valor enviado.
