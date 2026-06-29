# SPEC -- Indicadores MA VP: DAYTRADE (M5) + SWING (M30) -- alicerce 2026-06-29

> **Status:** concluido e validado no grafico pelo Emerson (2026-06-29) -- "operacionalmente perfeito".
> **Arquivos:** `Indicators/ZiahTrader_MA_VP.mq5` (daytrade, v2.5) + `Indicators/ZiahTrader_MA_VP_M30.mq5` (swing, v1.1).
> **Supersede parcial:** `SPEC_INDICADOR_MA_VP.md` (v2.3, so M5, pre-flip) -- este cobre a era flip/perfil/winsor + swing.
> **Regra #0:** codigo = fonte da verdade. **Regra #1 (Emerson):** contagem de candles PERFEITAMENTE
> correspondente ao ativo (medida pelo terminal, nao media provisionada).

## 1. O que sao
Dois indicadores standalone (janela separada) que plotam o mesmo motor de volatilidade (VP / `n_sigma`) em dois
horizontes, mais 2 EMAs (MA Start/Ref) sobre o `n_sigma` e VP Livre opcional. 17 OBJ_HLINE de referencia (-8..+8).
- **DAYTRADE (M5):** n_sigma de **24h** (ret_24h / vol diaria). Roda no grafico M5.
- **SWING (M30):** n_sigma de **7 dias** (ret_7d / vol semanal). Roda no grafico M30. Da a TENDENCIA PRINCIPAL.

## 2. Motor VP v2 (identico nos dois, escalado por horizonte)
```
sigma_hist  = EWMA RiskMetrics (var0=0, lambda) sobre retornos winsorizados do TF historico
              (DAYTRADE: D1 | SWING: W1), excluindo a barra corrente.
sigma_real  = std amostral (ddof=1) dos retornos winsorizados do TF intraday
              (DAYTRADE: M5 | SWING: M30), SEM anualizacao.
sigma_final = alpha*sigma_hist + (1-alpha)*sigma_real        (piso 1e-12)
ret         = price_now / price_(janela atras) - 1
n_sigma     = ret / sigma_final                              (SEM clip)
MA Start/Ref = EMA(periodo) sobre o stream de n_sigma, alpha=2/(N+1), seed pelo 1o valor.
```
- `price_now`: vela corrente = midprice live (SymbolInfoTick); barras historicas = close.
- Gate de cadencia na vela corrente: DAYTRADE 300s / SWING 1800s.
- **SEM clip** no n_sigma (no NIX o clip[-3,3] era so frontend -- decisao Emerson 2026-06-29).

## 3. FLIP DE ATIVO (`InpAtivo`: OURO / BITCOIN) -- contagens medidas pelo terminal
Chave unica por indicador que ajusta TODAS as janelas dependentes do ativo. (ZT_DiagContagemCandles, Exness-MT5Trial11.)
| Janela | Uso | BITCOIN (24/7) | OURO/XAU (gaps) |
|---|---|---|---|
| D1 sigma_hist (1 ano) | daytrade | 365 (7/sem) | **312** (6/sem, inclui domingo parcial) |
| M5 (24h) | daytrade | 288 | **276** (~23h pregao/dia) |
| W1 sigma_hist (2 anos) | swing | 105 | 105 (semanal calendar-based, **sem flip**) |
| M30 (7 dias) | swing | 336 (7x48) | **230** (5 dias pregao x 46) |
- **Por que contagem e nao timestamp:** no ouro, "7 dias calendario" cairia no fim de semana sem pregao
  (24h de domingo = sabado vazio). A janela por CONTAGEM de barras pula o gap sozinha. (Emerson, regra #1.)
- W1/D1 sao calendar-based; so D1 difere por ativo (BTC 7/sem vs XAU 6/sem).

## 4. PERFIL DE RISCO (`InpPerfil`, default AGRESSIVO) -- lambda/alpha (NIX)
| Perfil | lambda | alpha | efeito |
|---|---|---|---|
| Conservador | 0.96 | 0.80 | atrasa a entrada (- falsos, + risco de stop tarde) |
| Moderado | 0.94 | 0.70 | meio-termo |
| **Agressivo (default)** | **0.92** | **0.55** | pega o movimento ANTES (+ falsos positivos) |
| Ultra | 0.90 | 0.45 | o mais reativo |
- Default agressivo = exatamente o que o EA/indicador M5 antigo ja usava (lambda0.92/alpha0.55).

## 5. WINSOR (`InpWinsor`, toggle, default ON)
Apara retornos extremos (quantis 0.005/0.995) antes do sigma. **ON recomendado p/ OURO** (gaps de fim de
semana/rollover geram outliers que inflam o sigma sem winsor; o NIX nao tinha winsor pois BTC e 24/7 sem gaps).
Toggle p/ comparar no visual. (Decisao final no grafico -- Emerson.)

## 6. >>> CAMADA 1 DE DECISAO OPERACIONAL (Emerson 2026-06-29) -- hierarquia de 2 timeframes <<<
O **swing da a direcao principal**; o **daytrade temporiza** dentro dela; a **convergencia** prioriza.
1. **MA VP Swing pra BAIXO** -> **VENDAS liberadas** (regime vendedor). (Swing pra cima -> compras liberadas.)
2. **MA VP Daytrade prioriza na direcao do swing.** Em regime vendedor, o daytrade prioriza VENDA e o
   **robo de COMPRA fica PARADO** -- ate acharmos oportunidade de operar CONTRA a tendencia principal do swing.
3. **Convergencia Swing + Daytrade = "corredor" operacional:** quando os 2 timeframes concordam, as entradas
   sao priorizadas (coerencia dos dois TFs). E a 1a camada do filtro de entrada da nova estrutura de ordem unica.

## 7. Inputs (identicos nos 2; daytrade 8 / swing 7)
`InpAtivo` (OURO/BITCOIN) | `InpPerfil` (CON/MOD/AGR/ULT) | `InpWinsor` (bool) | `InpMA_Start_Period` |
`InpMA_Ref_Period` | `InpVP_Livre_Hours` | `InpVP_Livre_Smooth` | `InpShow_Lines`.
(Daytrade tem os mesmos; janelas D1/M5 vem do flip. Swing: janela M30 do flip, W1=105 fixo.)

## 8. PROXIMA ETAPA -- alinhamento com o EA (principio)
- O sensor swing entra no EA p/ rodar **logs reais** (sem precisar de scripts/ajustes offline). No robo, os
  indicadores devem estar **EXATAMENTE alinhados com o codigo do robo** (mesmas contagens por ativo, mesmo
  lambda/alpha/perfil, mesmo winsor, mesmo pipeline n_sigma) -- paridade total indicador <-> EA <-> analise.
- **Achado p/ a integracao:** o EA atual (modulo 20 VP v2) usa **288 M5 / 420 D1** no XAU -- valores BTC-ish/
  herdados, NAO os corretos do ouro (276 M5 / 312 D1). Alinhar ao adotar o sensor. PROD e BLINDADA -> integracao
  e testes em TESTES (673D6831) primeiro; compilacao = Emerson.
