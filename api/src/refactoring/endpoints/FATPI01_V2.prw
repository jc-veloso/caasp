#Include "Protheus.ch"
#Include "TbiConn.ch"
#Include "TopConn.ch"
#Include "RestFul.ch"

/*
+----------------------------------------------------------------------------+
| Autor: Antonio Nunes O Jr / Jose Carlos - Artiq                            |
| Data: 07/2026                                                              |
| Descritivo: FATPI01_V2 - Orquestrador REST (NFe modelo 55 apenas)            |
|             Endpoint: POST /fatpi01/v2                                    |
|             Recebe JSON do iPaaS, valida e enfileira BRUTO na ZZ9         |
|             Ordem de compilacao: FATPI01U > E > S > D > FATPI01           |
| [REV2] Jose Carlos - Artiq - 07/2026                                      |
|   Remapeamento de tabelas Muro Z (NFe Saida e Devolucao separadas):       |
|     ZZA = NFe Saida (cOper=S)      -- sem mudanca de dominio              |
|     ZZB = NFe Devolucao (cOper=D)  -- nova fila, antes ia junto na ZZA    |
|     ZZC = NFe Entrada (cOper=E)    -- antes era ZZB                      |
| [REV2-EXTRACAO-NFCE] Jose Carlos - Artiq - 07/2026                        |
|   NFCe (modelo 65, antes ZZD) foi extraida para o FATPI09 (endpoint       |
|   dedicado, POST /fatpi09/v2). Este arquivo processa exclusivamente NFe   |
|   modelo 55 (Saida/Devolucao/Entrada). Guard no topo rejeita cModDoc==65. |
| [ZZ9] Jose Carlos - Artiq - 08/2026                                       |
|   Endpoint emagrecido pra ficar consistente com o resto do projeto: nao   |
|   classifica mais CFOP/cOper/cliente-fornecedor, nao numera, nao roda     |
|   loop de produtos, e nao enfileira mais direto em ZZA/ZZB/ZZC. So        |
|   valida payload/filial, checa duplicidade e grava bruto na ZZ9 (tabela   |
|   intermediaria - ver CLAUDE.md pra estrutura completa). Motivo: o aviso  |
|   de produto pendente do FATPI10 nao traz CFOP, entao a classificacao     |
|   nao pode mais acontecer na hora do recebimento - precisa esperar        |
|   confirmacao de que nao ha produto pendente. Toda a logica que saiu      |
|   daqui (roteamento fiscal SA1/SA2, numeracao, duplicidade contra         |
|   SF1/SF2, loop de produtos/CFOP/TES, enriquecimento de oHead, gravacao   |
|   final em ZZA/ZZB/ZZC) migrou pro Job FATZZ901.prw, que le a ZZ9 e faz   |
|   exatamente o que este endpoint fazia antes, so que assincrono.         |
|   ZZX_Gravar tambem migrou (promovida a User Function) pra               |
|   FATZZF01.prw, pra poder ser chamada tanto daqui quanto do FATZZ901.    |
+----------------------------------------------------------------------------+
*/

WSRESTFUL FATPI01_V2 DESCRIPTION 'Hub de Vendas e Compras CAASP'
	WSMETHOD POST DESCRIPTION 'Processamento Global' WSSYNTAX "/fatpi01/v2" PATH "/fatpi01/v2" PRODUCES APPLICATION_JSON
END WSRESTFUL

WSMETHOD POST WSRECEIVE WSSERVICE FATPI01_V2
	// --- 1. DECLARACAO GERAL DE VARIAVEIS ---
	Local lRet         := .T.
	Local cJson        := Self:GetContent()
	Local jJson        := JsonObject():New()
	Local jRes         := JsonObject():New()
	Local nStat        := 200
	Local cModDoc      := ""
	Local aInv         := {}
	Local oHead        := Nil
	Local aEmp         := {}
	Local cCnpj        := ""
	Local cChave       := ""
	Local cProdPend    := ""
	Local lOk          := .T.
	Local cQryAux      := ""
	Local cAliAux      := ""
	Local cOldRestNfe  := ""

	Private __cBatch   := "1"

	// --- 2. PREPARACAO DE AMBIENTE ---
	// [PREPAREIN] Jose Carlos - Artiq - 08/2026
	// RpcSetEnv/RpcClearEnv removidos - nao se usa dentro de WSRESTFUL (TDN
	// oficial, "Abertura de ambiente em Web Service", a partir da 12.1.27).
	// O ambiente ja vem pronto via PREPAREIN do appserver.ini, e
	// empresa/filial resolvidos pelo header TenantId da requisicao. Chamar
	// RpcSetEnv de novo aqui conflitava com esse ambiente ja aberto - foi a
	// causa do erro visto em teste (confirmado primeiro no FATPI09). Vale
	// so pros endpoints REST; os Jobs (FATZZA01...FATZZF01, FATZZ901)
	// continuam precisando, eles rodam via Schedule sem PREPAREIN.
	cOldRestNfe := SuperGetMv("MV_RESTNFE", .F., "S")
	PutMv("MV_RESTNFE", "N")

	Self:SetContentType('application/json')

	If !Empty(jJson:FromJson(cJson))
		lOk := .F.
		nStat := 200
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "Payload"
		jRes['detalhe']   := "Estrutura JSON"
		jRes['mensagem']  := "JSON invalido ou vazio."

		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		PutMv("MV_RESTNFE", cOldRestNfe)
		Return .T.
	EndIf

	// [ZZ9] prod_Pendente vive na RAIZ do payload (irmao de notas/items),
	// nao dentro do item da nota - por isso le direto do jJson, nao via
	// U_PI_STR_X sobre oHead (que e escopo do item).
	cProdPend := jJson['prod_Pendente']
	If ValType(cProdPend) != "C" .Or. Empty(cProdPend)
		cProdPend := "N"
	EndIf

	// --- 3. IDENTIFICACAO DO OBJETO E NATUREZA ---
	aInv := jJson['notas']
	If ValType(aInv) != "A"
		aInv := jJson['items']
	EndIf

	If ValType(aInv) == "A" .And. Len(aInv) > 0
		oHead   := aInv[1]
		cModDoc := U_PI_STR_X(oHead, 'cod_Mod', 'modelo')

		// [REV2-EXTRACAO-NFCE] Este endpoint e exclusivo de NFe (modelo 55).
		// NFCe (modelo 65) foi extraida para o FATPI09 (endpoint dedicado).
		If cModDoc == "65"
			nStat := 200
			jRes['status']    := nStat
			jRes['resultado'] := "Falha"
			jRes['erro']      := "ModeloIncorreto"
			jRes['mensagem']  := "FATPI01_V2 aceita apenas NFe (modelo 55). NFCe deve ser enviada para /fatpi09/v2."

			Self:setStatus(nStat)
			Self:SetResponse(EncodeUTF8(jRes:toJSON()))
			PutMv("MV_RESTNFE", cOldRestNfe)
			Return .T.
		EndIf

		// [ZZ9] Chave extraida cedo - o endpoint fino precisa dela pra
		// checar duplicidade na ZZ9 antes de decidir se grava (antes so
		// era lida la na hora do ZZX_Gravar, no fim do fluxo completo).
		cChave := AllTrim(U_PI_STR_X(oHead, 'cod_ChaveNFe'))

		cCnpj := U_PI_LIMPA_X(U_PI_STR_X(oHead, 'num_SubseccaoCNPJ', 'num_SubseccaoCNPJ'))
		aEmp := U_PI_FILIAL_X(cCnpj)

		If Len(aEmp) < 2
			lOk := .F.
			nStat := 200
			jRes['status']    := nStat
			jRes['resultado'] := "Falha"
			jRes['erro']      := "Filial"
			jRes['detalhe']   := cCnpj
			jRes['mensagem']  := "Filial nao encontrada para CNPJ: " + AllTrim(cCnpj)
		EndIf

		If lOk
			// --- 4. DUPLICIDADE CONTRA A ZZ9 ---
			// [ZZ9] Nao checa mais contra SF2/SF1 (nota ja classificada/
			// lancada) - isso migrou pro FATZZ901, que so sabe se e SF2 ou
			// SF1 depois de resolver cOper. Aqui so importa se essa chave
			// ja esta na fila de classificacao (P/A) ou ja foi classificada
			// com sucesso (S) - reenvio do iPaaS com o mesmo payload nao
			// deve duplicar linha na ZZ9.
			cQryAux := "SELECT ZZ9_COD FROM " + RetSqlName("ZZ9") + " WHERE ZZ9_CHVNFE = '" + cChave + "' AND ZZ9_STATUS IN ('P','A','S') AND D_E_L_E_T_ = ' '"
			cAliAux := GetNextAlias()
			MpSysOpenQuery(cQryAux, cAliAux)
			If (cAliAux)->(!Eof())
				(cAliAux)->(DbCloseArea())

				nStat := 200
				jRes['status']    := nStat
				jRes['resultado'] := "Sucesso"
				jRes['doc']       := "NFe: " + cChave
				jRes['info']      := "NFe ja enfileirada anteriormente."
				Self:setStatus(nStat)
				Self:SetResponse(EncodeUTF8(jRes:toJSON()))
				PutMv("MV_RESTNFE", cOldRestNfe)
				Return .T.
			EndIf
			(cAliAux)->(DbCloseArea())

			// --- 5. GRAVACAO BRUTA NA ZZ9 ---
			// [ZZ9] Classificacao/roteamento/numeracao/loop de produtos e
			// gravacao final em ZZA/ZZB/ZZC migraram pro FATZZ901.prw.
			// ZZ9 nao tem campo _PROC (diferente de ZZA-ZZE) - passa "" pra
			// cProc, o ZZX_Gravar (FATZZF01.prw) ja ignora esse campo pra
			// tabelas que nao tem ele.
			// [QTPROD] Jose Carlos - Artiq - 08/2026 - vem pronto no JSON,
			// tag qt_Produto na raiz da nota (oHead) - so le e repassa, sem
			// calcular (ver instrucao_qtprod.md).
			If U_ZZX_Gravar("ZZ9", "", "CHVNFE", cChave, jJson:toJSON(), "", "", cProdPend, AllTrim(U_PI_STR_X(oHead, 'qt_Produto')))
				nStat := 201
				jRes['status']    := nStat
				jRes['resultado'] := "Sucesso"
				jRes['doc']       := "NFe enfileirada na ZZ9: " + cChave
				jRes['info']      := "Nota registrada para classificacao e processamento assincrono."
			Else
				lOk := .F.
				nStat := 230
				jRes['status']    := nStat
				jRes['resultado'] := "Falha"
				jRes['erro']      := "FilaMuroZ"
				jRes['mensagem']  := "Falha ao gravar na fila ZZ9. Tente novamente."
			EndIf
		EndIf
	EndIf

	PutMv("MV_RESTNFE", cOldRestNfe)

	Self:setStatus(nStat)
	Self:SetResponse(EncodeUTF8(jRes:toJSON()))
	FreeObj(jJson)
	FreeObj(jRes)

Return lRet
