#Include "Totvs.ch"
#Include "RESTFul.ch"
#Include "TopConn.ch"
#Include "FWMVCDef.ch"
#Include "TbiConn.ch"

/*/{Protheus.doc} WSRESTFUL FATPI03_V2
Fonte: baseado em api/src/FATPI03.PRW (Antonio Nunes, 24/02/2026)
Descricao: Fornecedor CAASP - Upsert com dados bancarios (MATA020).

[ZZG] Jose Carlos - Artiq - 08/2026
Primeira copia deste endpoint em refactoring/ - nao existia aqui antes
(o original em api/src/FATPI03.PRW nunca tinha sido tocado pelo REV2).
Passa a existir agora porque a logica de upsert de fornecedor precisou
ser extraida pra User Function PI_FORN_X (em FATPI01U.prw, processa UM
fornecedor por chamada), pro Job assincrono FATZZG01.prw poder cadastrar
fornecedor sem passar por HTTP (mesmo padrao ja usado pra produto -
U_PI_PROD_X - e ja documentado em instrucao_zzg_cliente_fornecedor.md).
WSRESTFUL declarado como FATPI03_V2 (nao "FATPI03" puro) porque o nome
bare ja esta compilado no ambiente pelo original top-level - colisao de
recurso REST, mesma regra ja documentada no CLAUDE.md pros outros
endpoints _V2. Nao replica o WSMETHOD GET SEARCH_CNPJ do original -
fora do escopo desta tarefa, so o POST precisava ser extraido.
[FIX-RESPOSTA] A resposta original (api/src/FATPI03.PRW linha 169,
`Self:SetResponse(oResult)`) devolvia so o ULTIMO item processado (nao
o array agregado jResponse['results']), sem EncodeUTF8/toJSON - parece
bug do original, nao comportamento intencional a preservar. Aqui devolve
jResponse com o resultado de cada item, corretamente serializado.
Nenhuma outra regra de negocio mudou dentro de PI_FORN_X; e transcricao
1:1 do que ja existia no loop (api/src/FATPI03.PRW, linhas 90-167).
/*/

WSRESTFUL FATPI03_V2 DESCRIPTION 'Fornecedor CAASP - Upsert com dados bancarios'
    WSMETHOD POST DESCRIPTION 'Upsert de Fornecedor(es)' WSSYNTAX "/fatpi03/v2" PATH "/fatpi03/v2" PRODUCES APPLICATION_JSON
END WSRESTFUL

WSMETHOD POST WSRECEIVE WSSERVICE FATPI03_V2
    Local cJson      := Self:GetContent()
    Local jJson      := JsonObject():New()
    Local jResponse  := JsonObject():New()
    Local jResult    := Nil
    Local jItems     := {}
    Local jItem      := Nil
    Local aRes       := {}
    Local nX         := 0
    Local nStat      := 200

    // [PREPAREIN] RpcSetEnv/RpcClearEnv nao se usa dentro de WSRESTFUL -
    // o ambiente ja vem pronto via PREPAREIN do appserver.ini (mesma
    // regra ja documentada no CLAUDE.md pros demais endpoints _V2).
    Self:SetContentType('application/json')

    If Empty(jJson:FromJson(cJson))
        nStat := 400
        jResponse['erro']     := "JSON"
        jResponse['mensagem'] := "JSON invalido"
        Self:setStatus(nStat)
        Self:SetResponse(EncodeUTF8(jResponse:toJSON()))
        FreeObj(jJson)
        FreeObj(jResponse)
        Return .T.
    EndIf

    jItems := IIF(jJson:HasProperty("items"), jJson['items'], {jJson})
    jResponse['results'] := {}

    For nX := 1 To Len(jItems)
        jItem  := jItems[nX]
        aRes   := U_PI_FORN_X(jItem)
        jResult := JsonObject():New()

        If aRes[1]
            jResult['resultado']    := "Sucesso"
            jResult['mensagem']     := aRes[2]
            jResult['cod_erp']      := aRes[3]
        Else
            jResult['resultado'] := "Erro"
            jResult['mensagem']  := aRes[2]
        EndIf

        aAdd(jResponse['results'], jResult)
    Next nX

    nStat := 201
    Self:setStatus(nStat)
    Self:SetResponse(EncodeUTF8(jResponse:toJSON()))
    FreeObj(jJson)
    FreeObj(jResponse)
Return .T.
