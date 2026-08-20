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
| [CONTRATO-CONFIRMADO-V2] Jose Carlos - Artiq - 08/2026                    |
|   Contrato mudou de novo (confirmado com o Arthur em 16/08, ver          |
|   instrucao_sync_pi_cli_forn_2.md) - "tipo" nao e mais CLI/FOR, agora e   |
|   o TIPO DA NOTA (mesmo dominio de ZZG_TIPONF - "ZZ9" pra NFe, "NFC"      |
|   pra NFCe). Quem carrega CLI/FOR agora e o campo novo                   |
|   "tp_Participante", no nivel raiz do envelope. "chave" e enviada de      |
|   verdade (cod_ChaveNFe) - suspeita anterior de que nao viria estava      |
|   errada. "dados" e exatamente o cadastro (Json tabela muro Cliente/     |
|   Fornecedor.txt) menos o tp_Participante, que foi extraido pra fora.    |
|   Payload atual:                                                          |
|     { "tipo": "NFC", "chave": "...", "tp_Participante": "CLI",           |
|       "dados": {...} }                                                    |
|   Como "tipo" ja diz a tabela, a busca da nota pai agora e direta (SELECT |
|   na tabela certa), sem precisar varrer ZZ9 e ZZD como antes.            |
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
	Local cTipoNF     := ""
	Local cChave      := ""
	Local cTipoPen    := ""
	Local cTabAch     := ""
	Local cCampChv    := ""
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
	// [CONTRATO-CONFIRMADO-V2] tipo = tipo da nota (ZZ9/NFC), nao mais
	// CLI/FOR - quem carrega isso agora e tp_Participante.
	cTipoNF  := Upper(AllTrim(U_PI_STR_X(jJson, 'tipo')))
	cChave   := AllTrim(U_PI_STR_X(jJson, 'chave'))
	cTipoPen := Upper(AllTrim(U_PI_STR_X(jJson, 'tp_Participante')))
	jDados   := jJson['dados']

	If Empty(cTipoNF) .Or. Empty(cChave) .Or. Empty(cTipoPen) .Or. (ValType(jDados) != "J" .And. ValType(jDados) != "O")
		nStat := 200
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "Payload"
		jRes['mensagem']  := "Campos obrigatorios: tipo (ZZ9/NFC), chave, tp_Participante (CLI/FOR), dados (objeto)."
		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		Return .T.
	EndIf

	// Aceita "NFE" alem de "ZZ9" (mesmo dominio, ver contrato no cabecalho) -
	// normalizado pro literal correto logo abaixo.
	If !(cTipoNF $ "ZZ9/NFE/NFC")
		nStat := 200
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "Tipo"
		jRes['mensagem']  := "tipo invalido: " + cTipoNF + ". Esperado ZZ9, NFE ou NFC."
		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		Return .T.
	EndIf

	// FATZZG01.prw compara ZZG_TIPONF == "ZZ9" pra achar a tabela pai - sem
	// normalizar aqui, "NFE" gravado ao pe da letra cairia no Else errado (ZZD).
	If cTipoNF == "NFE"
		cTipoNF := "ZZ9"
	EndIf

	If !(cTipoPen $ "CLI/FOR")
		nStat := 200
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "TipoParticipante"
		jRes['mensagem']  := "tp_Participante invalido: " + cTipoPen + ". Esperado CLI ou FOR."
		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		Return .T.
	EndIf

	// --- 4. LOCALIZA A NOTA PAI (busca direta - "tipo" ja diz a tabela, ---
	// --- nao precisa mais varrer ZZ9 e ZZD)                             ---
	cTabAch  := IIF(cTipoNF == "NFC", "ZZD", "ZZ9")
	cCampChv := cTabAch + "_CHVNFE"

	cQryAux := "SELECT " + cCampChv + " FROM " + RetSqlName(cTabAch) + " WHERE " + cCampChv + " = '" + cChave + "' AND D_E_L_E_T_ = ' '"
	cAliAux := GetNextAlias()
	MpSysOpenQuery(cQryAux, cAliAux)
	If (cAliAux)->(Eof())
		(cAliAux)->(DbCloseArea())
		// [FIX-STATUS-404] Jose Carlos - Artiq - 08/2026
		// NUNCA 4xx/5xx aqui - convencao do projeto e sempre 200 com corpo
		// explicando o erro (4xx/5xx quebra o iPaaS em transporte, mesmo
		// motivo do [IPASS-FIX] mais abaixo). Achado numa rodada anterior,
		// corrigido nesta reescrita - nao repetir o erro.
		nStat := 200
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "NotaNaoEncontrada"
		jRes['mensagem']  := "Nota nao encontrada na " + cTabAch + " para chave: " + cChave
		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		Return .T.
	EndIf
	(cAliAux)->(DbCloseArea())

	// --- 5. GRAVA NA FILA ZZG (com dedup contra retry) ---
	cQryAux := "SELECT ZZG_COD FROM " + RetSqlName("ZZG") + " WHERE ZZG_CHVREF = '" + cChave + "' AND ZZG_TIPOPE = '" + cTipoPen + "' AND ZZG_STATUS IN ('P','A','S') AND D_E_L_E_T_ = ' '"
	cAliAux := GetNextAlias()
	MpSysOpenQuery(cQryAux, cAliAux)
	lJa := (cAliAux)->(!Eof())
	(cAliAux)->(DbCloseArea())

	If !lJa
		lGravou := U_ZZG_GRV(cChave, cTipoPen, cTipoNF, jDados:toJSON())
	Else
		lGravou := .T.
	EndIf

	// --- 6. GARANTE <TAB>_CLIPEN/FORPEN = 'S' NA NOTA PAI (idempotente - ---
	// --- ingestao ja deveria ter marcado via cliente_Pendente/           ---
	// --- fornecedor_Pendente no payload da nota)                        ---
	cCampPen := IIF(cTipoPen == "CLI", cTabAch + "_CLIPEN", cTabAch + "_FORPEN")
	TCSqlExec("UPDATE " + RetSqlName(cTabAch) + " SET " + cCampPen + " = 'S' WHERE " + cCampChv + " = '" + cChave + "' AND D_E_L_E_T_ = ' '")

	If lGravou
		nStat := 201
		jRes['status']    := nStat
		jRes['resultado'] := "Sucesso"
		jRes['tabela']    := cTabAch
		jRes['mensagem']  := IIF(cTipoPen == "CLI", "Cliente", "Fornecedor") + " pendente enfileirado na ZZG."
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
