#Include "Totvs.ch"
#Include "RESTFul.ch"
#Include "TopConn.ch"
#Include "FWMVCDef.ch"
#Include "TbiConn.ch"

// POST /fatpi03/v2 - endpoint de upsert de fornecedor (SA2), delega para U_PI_FORN_X

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
