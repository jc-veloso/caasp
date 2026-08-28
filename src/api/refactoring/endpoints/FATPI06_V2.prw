#Include "Totvs.ch"
#Include "RESTFul.ch"
#Include "TopConn.ch"
#Include "FWMVCDef.ch"

// POST /fatpi06/v2 - endpoint de upsert de cliente (SA1), delega para U_PI_CLI_X

WSRESTFUL FATPI06_V2 DESCRIPTION 'Importador CAASP - Clientes MVC'
    WSMETHOD POST DESCRIPTION 'Inclusao de Cliente' WSSYNTAX "/fatpi06/v2" PATH "/fatpi06/v2" PRODUCES APPLICATION_JSON
END WSRESTFUL

WSMETHOD POST WSRECEIVE WSSERVICE FATPI06_V2
    Local cJson     := Self:GetContent()
    Local jJson     := JsonObject():New()
    Local jResponse := JsonObject():New()
    Local nStat     := 200
    Local aRes      := {}

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

    aRes := U_PI_CLI_X(jJson)

    If aRes[1]
        nStat := 201
        jResponse['resultado']    := "Sucesso"
        jResponse['protheus_cod'] := aRes[3]
    Else
        nStat := 200
        jResponse['resultado'] := "Erro"
        jResponse['mensagem']  := aRes[2]
    EndIf

    Self:setStatus(nStat)
    Self:SetResponse(EncodeUTF8(jResponse:toJSON()))
    FreeObj(jJson)
    FreeObj(jResponse)
Return .T.
