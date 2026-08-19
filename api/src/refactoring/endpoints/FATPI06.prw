#Include "Totvs.ch"
#Include "RESTFul.ch"
#Include "TopConn.ch"
#Include "FWMVCDef.ch"

/*/{Protheus.doc} WSRESTFUL FATPI06_V2
Fonte: baseado em api/src/FATPI06.prw (Andr� Luiz Monteiro, 18/05/2026)
Descricao: Importador CAASP - Clientes (MVC/CRMA980).

[ZZG] Jose Carlos - Artiq - 08/2026
Primeira copia deste endpoint em refactoring/ - nao existia aqui antes
(o original em api/src/FATPI06.prw nunca tinha sido tocado pelo REV2).
Passa a existir agora porque a logica de upsert de cliente precisou ser
extraida pra User Function PI_CLI_X (em FATPI01U.prw), pro Job assincrono
FATZZG01.prw poder cadastrar cliente sem passar por HTTP (mesmo padrao
ja usado pra produto - U_PI_PROD_X/FATPI02_V2.prw - e ja documentado em
instrucao_zzg_cliente_fornecedor.md). WSRESTFUL declarado como
FATPI06_V2 (nao "FATPI06" puro) porque o nome bare ja esta compilado no
ambiente pelo original top-level - colisao de recurso REST, mesma regra
ja documentada no CLAUDE.md pros outros endpoints _V2. Nao replica o
WSMETHOD GET GetClient (consulta) do original - fora do escopo desta
tarefa, so o POST precisava ser extraido.
Nenhuma regra de negocio mudou dentro de PI_CLI_X; e transcricao 1:1 do
que ja existia em DoPost (api/src/FATPI06.prw, linhas 44-163).
/*/

WSRESTFUL FATPI06_V2 DESCRIPTION 'Importador CAASP - Clientes MVC'
    WSMETHOD POST DESCRIPTION 'Inclusao de Cliente' WSSYNTAX "/fatpi06/v2" PATH "/fatpi06/v2" PRODUCES APPLICATION_JSON
END WSRESTFUL

WSMETHOD POST WSRECEIVE WSSERVICE FATPI06_V2
    Local cJson     := Self:GetContent()
    Local jJson     := JsonObject():New()
    Local jResponse := JsonObject():New()
    Local nStat     := 200
    Local aRes      := {}

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
