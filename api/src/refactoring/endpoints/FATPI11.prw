#Include 'totvs.ch'
#Include 'TbiConn.ch'
#Include 'TopConn.ch'
#Include 'RestFul.ch'

/*
+----------------------------------------------------------------------------+
| Autor: Jose Carlos - Artiq                                                 |
| Data: 08/2026                                                              |
| Descritivo: FATPI11 - Fila de Cliente/Fornecedor Pendente (ZZG)           |
|             Endpoint: POST /fatpi11/v2                                    |
|                                                                             |
| [ZZG] Mesmo esqueleto do FATPI10.prw (produto pendente), adaptado pra     |
|   cliente/fornecedor - ver instrucao_zzg_cliente_fornecedor.md pro        |
|   contexto completo. Diferenca chave: aqui o Arthur ja manda o cadastro   |
|   TRATADO e pronto em "dados" (nao so um codigo, como no FATPI10) - nao   |
|   precisa consultar API externa nenhuma, o Job (FATZZG01) so chama       |
|   U_PI_CLI_X/U_PI_FORN_X direto com o JSON recebido.                     |
|                                                                             |
| [ESCOPO] Cliente/fornecedor pendente so e relevante pra ZZ9 (NFe, onde    |
|   ZZ901_Classifica resolve cliente/fornecedor) e ZZD (NFCe, onde          |
|   ZZD_MotorNFCe resolve cliente) - ver Parte 5 da instrucao. ZZA/ZZB/ZZC  |
|   nunca chegam a existir com cliente/fornecedor pendente (so sao         |
|   gravadas DEPOIS que ZZ901_Classifica ja resolveu com sucesso), e ZZE    |
|   (Recibo) fica fora de escopo - decisao consciente do Mauricio,          |
|   confirmada pelo Arthur (ver instrucao, "seguimos com o recibo no       |
|   modelo antigo"). Por isso a busca da nota pai aqui e mais restrita que |
|   a do FATPI10 (que precisa cobrir produto pendente em qualquer         |
|   dominio, inclusive ZZA/ZZB/ZZC/ZZE).                                    |
|                                                                             |
| [CONTRATO-CONFIRMADO] Jose Carlos - Artiq - 08/2026                       |
|   Formato do payload ({tipo, chave, dados}) e o numero do endpoint       |
|   (FATPI11, POST /fatpi11/v2) confirmados com o Arthur - bateram exato   |
|   com a melhor interpretacao original da instrucao, sem mudanca de       |
|   codigo necessaria. Item de checklist da instrucao_zzg_cliente_         |
|   fornecedor.md fechado.                                                  |
|                                                                             |
| [FIX-ZZG-GRV] A gravacao usa U_ZZG_GRV (FATZZG01.prw), nao               |
|   U_ZZX_Gravar como o doc sugeria literalmente na Parte 3 - ZZG precisa  |
|   de DOIS campos extras (TIPOPEN e TIPONF), e ZZX_Gravar so suporta UM   |
|   campo extra generico. Mesma situacao que ja levou ZZF a ter sua        |
|   propria U_ZZF_GRV dedicada em vez de reusar ZZX_Gravar - seguido o     |
|   mesmo precedente aqui. Compilar FATZZG01.prw antes deste fonte, mesma  |
|   regra ja valida pro FATZZF01.prw/FATPI10.prw.                          |
+----------------------------------------------------------------------------+
*/

WSRESTFUL FATPI11_V2 DESCRIPTION 'Fila de Cliente/Fornecedor Pendente CAASP'
	WSMETHOD POST DESCRIPTION 'Cliente/Fornecedor Pendente' WSSYNTAX "/fatpi11/v2" PATH "/fatpi11/v2" PRODUCES APPLICATION_JSON
END WSRESTFUL

WSMETHOD POST WSRECEIVE WSSERVICE FATPI11_V2
	// --- 1. DECLARACAO GERAL DE VARIAVEIS ---
	Local cJson       := Self:GetContent()
	Local jJson       := JsonObject():New()
	Local jRes        := JsonObject():New()
	Local jDados      := Nil
	Local nStat       := 200
	Local cTipo       := ""
	Local cChave      := ""
	Local aTabs       := {}
	Local cTabAch     := ""
	Local cTipoAch    := ""
	Local cCampChv    := ""
	Local nI          := 0
	Local cQryAux     := ""
	Local cAliAux     := ""
	Local lJa         := .F.
	Local lGravou     := .F.
	Local cCampPen    := ""

	// --- 2. PREPARACAO DE AMBIENTE ---
	// [PREPAREIN] Jose Carlos - Artiq - 08/2026
	// RpcSetEnv/RpcClearEnv nao se usa dentro de WSRESTFUL (TDN oficial,
	// "Abertura de ambiente em Web Service", a partir da 12.1.27). O
	// ambiente ja vem pronto via PREPAREIN do appserver.ini, mesma regra
	// ja documentada nos demais endpoints _V2.
	Self:SetContentType('application/json')

	If !Empty(jJson:FromJson(cJson))
		nStat := 200
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "Payload"
		jRes['mensagem']  := "JSON invalido ou vazio."
		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		Return .T.
	EndIf

	// --- 3. EXTRACAO E VALIDACAO DO PAYLOAD ---
	cTipo  := Upper(AllTrim(U_PI_STR_X(jJson, 'tipo')))
	cChave := AllTrim(U_PI_STR_X(jJson, 'chave'))
	jDados := jJson['dados']

	If Empty(cTipo) .Or. Empty(cChave) .Or. (ValType(jDados) != "J" .And. ValType(jDados) != "O")
		nStat := 200
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "Payload"
		jRes['mensagem']  := "Campos obrigatorios: tipo (CLI/FOR), chave, dados (objeto)."
		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		Return .T.
	EndIf

	If !(cTipo $ "CLI/FOR")
		nStat := 200
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "Tipo"
		jRes['mensagem']  := "Tipo invalido: " + cTipo + ". Esperado CLI ou FOR."
		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		Return .T.
	EndIf

	// --- 4. LOCALIZA A NOTA PAI (ZZ9 ou ZZD - unicos dominios com     ---
	// --- cliente/fornecedor pendente, ver Parte 5 da instrucao)       ---
	aTabs := {{"ZZ9", "CHVNFE", "ZZ9"}, {"ZZD", "CHVNFE", "NFC"}}

	For nI := 1 To Len(aTabs)
		cCampChv := aTabs[nI][1] + "_" + aTabs[nI][2]
		cQryAux := "SELECT " + cCampChv + " FROM " + RetSqlName(aTabs[nI][1]) + " WHERE " + cCampChv + " = '" + cChave + "' AND D_E_L_E_T_ = ' '"
		cAliAux := GetNextAlias()
		MpSysOpenQuery(cQryAux, cAliAux)
		If (cAliAux)->(!Eof())
			cTabAch  := aTabs[nI][1]
			cTipoAch := aTabs[nI][3]
			(cAliAux)->(DbCloseArea())
			Exit
		EndIf
		(cAliAux)->(DbCloseArea())
	Next nI

	If Empty(cTabAch)
		nStat := 404
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "NotaNaoEncontrada"
		jRes['mensagem']  := "Nenhuma nota encontrada para chave: " + cChave + " (ZZ9/ZZD)."
		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		Return .T.
	EndIf

	// --- 5. GRAVA NA FILA ZZG (com dedup contra retry) ---
	cQryAux := "SELECT ZZG_COD FROM " + RetSqlName("ZZG") + " WHERE ZZG_CHVREF = '" + cChave + "' AND ZZG_TIPOPEN = '" + cTipo + "' AND ZZG_STATUS IN ('P','A','S') AND D_E_L_E_T_ = ' '"
	cAliAux := GetNextAlias()
	MpSysOpenQuery(cQryAux, cAliAux)
	lJa := (cAliAux)->(!Eof())
	(cAliAux)->(DbCloseArea())

	If !lJa
		lGravou := U_ZZG_GRV(cChave, cTipo, cTipoAch, jDados:toJSON())
	Else
		lGravou := .T.
	EndIf

	// --- 6. GARANTE <TAB>_CLIPEN/FORPEN = 'S' NA NOTA PAI (idempotente - ---
	// --- ingestao ja deveria ter marcado via cliente_Pendente/           ---
	// --- fornecedor_Pendente no payload da nota)                        ---
	cCampPen := IIF(cTipo == "CLI", cTabAch + "_CLIPEN", cTabAch + "_FORPEN")
	TCSqlExec("UPDATE " + RetSqlName(cTabAch) + " SET " + cCampPen + " = 'S' WHERE " + cCampChv + " = '" + cChave + "' AND D_E_L_E_T_ = ' '")

	If lGravou
		nStat := 201
		jRes['status']    := nStat
		jRes['resultado'] := "Sucesso"
		jRes['tabela']    := cTabAch
		jRes['mensagem']  := IIF(cTipo == "CLI", "Cliente", "Fornecedor") + " pendente enfileirado na ZZG."
	Else
		nStat := 230  // [IPASS-FIX] Falha de sistema (gravacao na fila) - 2xx pra nao quebrar o iPaaS em transporte, mesmo padrao do FATPI10
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "FilaMuroZ"
		jRes['mensagem']  := "Falha ao gravar pendencia na ZZG."
	EndIf

	Self:setStatus(nStat)
	Self:SetResponse(EncodeUTF8(jRes:toJSON()))
	FreeObj(jJson)
	FreeObj(jRes)
Return .T.
