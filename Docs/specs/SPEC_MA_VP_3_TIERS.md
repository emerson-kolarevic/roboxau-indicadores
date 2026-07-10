# SPEC -- Familia de indicadores MA VP: 3 TIERS (M5 daytrade + M30 swing + M1 execucao)

> **Status:** M5 v2.6 + M30 v1.2 validados no grafico; M1 v1.0 escrito em 2026-07-09, validacao visual pendente.
> **Arquivos:** `Indicators/ZiahTrader_MA_VP_M5.mq5` (daytrade, v2.6) + `Indicators/ZiahTrader_MA_VP_M30.mq5`
> (swing, v1.2) + `Indicators/ZiahTrader_MA_VP_M1.mq5` (execucao, v1.0).
> **Historico:** este doc era `SPEC_MA_VP_DAYTRADE_E_SWING.md` (2 tiers, 2026-06-29); renomeado em 2026-07-09
> ao nascer o 3o tier. Supersede parcial de `SPEC_INDICADOR_MA_VP.md` (v2.3, so M5, pre-flip) permanece.
> Em 2026-07-09 o indicador daytrade foi renomeado `ZiahTrader_MA_VP` -> `ZiahTrader_MA_VP_M5`.
> **Regra #0:** codigo = fonte da verdade. **Regra #1 (Emerson):** contagem de candles PERFEITAMENTE
> correspondente ao ativo (medida pelo terminal, nao media provisionada).

## 1. O que sao
Tres indicadores standalone (janela separada) que plotam o mesmo motor de volatilidade (VP / `n_sigma`) em tres
horizontes, mais 2 EMAs (MA Start/Ref) sobre o `n_sigma` e VP Livre opcional. 17 OBJ_HLINE de referencia (-8..+8).
- **DAYTRADE (M5):** n_sigma de **24h** (ret_24h / vol diaria). Roda no grafico M5.
- **SWING (M30):** n_sigma de **7 dias** (ret_7d / vol semanal). Roda no grafico M30. Da a TENDENCIA PRINCIPAL.
- **EXECUCAO (M1):** n_sigma de **1 hora** (ret_1h / vol horaria). Roda no grafico M1. Sensor de micro-timing.

## 2. Motor VP v2 (identico nos tres, escalado por horizonte)
```
sigma_hist  = EWMA RiskMetrics (var0=0, lambda) sobre retornos winsorizados do TF historico
              (DAYTRADE: D1 | SWING: W1 | EXECUCAO: H1), excluindo a barra corrente.
sigma_real  = std amostral (ddof=1) dos retornos winsorizados do TF intraday
              (DAYTRADE: M5 | SWING: M30 | EXECUCAO: M1), SEM anualizacao.
sigma_final = alpha*sigma_hist + (1-alpha)*sigma_real        (piso 1e-12)
ret         = price_now / price_(janela atras) - 1
n_sigma     = ret / sigma_final                              (SEM clip)
MA Start/Ref = EMA(periodo) sobre o stream de n_sigma, alpha=2/(N+1), seed pelo 1o valor.
```
- `price_now`: vela corrente = midprice live (SymbolInfoTick); barras historicas = close.
- Gate de cadencia na vela corrente: DAYTRADE 300s / SWING 1800s / EXECUCAO 60s (= 1 barra do chart).
- **SEM clip** no n_sigma (no NIX o clip[-3,3] era so frontend -- decisao Emerson 2026-06-29).
- A lei de formacao dos tiers: **horizonte do retorno = 1 barra do TF historico** (24h~D1 ; 7d~W1 ; 1h~H1).

## 3. FLIP DE ATIVO (`InpAtivo`: OURO / BITCOIN) -- contagens medidas pelo terminal
Chave unica por indicador que ajusta as janelas dependentes do ativo. (ZT_DiagContagemCandles, Exness-MT5Trial11;
daytrade/swing medidos 2026-06-29, execucao medido 2026-07-09 com diag v1.1.)
| Janela | Uso | BITCOIN (24/7) | OURO/XAU (gaps) |
|---|---|---|---|
| D1 sigma_hist (1 ano) | daytrade | 365 (7/sem) | **312** (6/sem, inclui domingo parcial) |
| M5 (24h) | daytrade | 288 | **276** (~23h pregao/dia) |
| W1 sigma_hist (2 anos) | swing | 105 | 105 (semanal calendar-based, **sem flip**) |
| M30 (7 dias) | swing | 336 (7x48) | **230** (5 dias pregao x 46) |
| H1 sigma_hist (8 pregoes) | execucao | 192 (8x24) | **184** (8x23, pregao CHEIO) |
| M1 (1 hora) | execucao | 60 | 60 (medido 59.9 -- horas cheias, **sem flip**) |
- **Por que contagem e nao timestamp:** no ouro, janela por CONTAGEM de barras pula gap de fim de semana E
  feriado sozinha. (Emerson, regra #1.)
- **Licao do 4 de julho (2026-07-09):** a medicao do H1 em semana com feriado deu media 18.5 H1/pregao (a sessao
  encurtada de 03/07 + domingo parcial contam como pregao no divisor). O criterio correto e o pregao CHEIO:
  23 H1 no XAU (= 276 M5 / 12, semana limpa de 2026-06-29) -> janela 8 pregoes = 184. Mesmo criterio do 276.

## 4. PERFIL DE RISCO (`InpPerfil`, default AGRESSIVO) -- lambda/alpha (NIX)
| Perfil | lambda | alpha | efeito |
|---|---|---|---|
| Conservador | 0.96 | 0.80 | atrasa a entrada (- falsos, + risco de stop tarde) |
| Moderado | 0.94 | 0.70 | meio-termo |
| **Agressivo (default)** | **0.92** | **0.55** | pega o movimento ANTES (+ falsos positivos) |
| Ultra | 0.90 | 0.45 | o mais reativo |

## 5. WINSOR (`InpWinsor`, toggle, default ON)
Apara retornos extremos (quantis 0.005/0.995) antes do sigma. ON recomendado p/ OURO (gaps geram outliers).
**Particularidade do tier M1:** com ~60 amostras na janela intraday, o winsor e quase inerte no lado M1
(0.005*60 = 0.3 amostra -- nao apara nada); a protecao contra outlier vem do lado H1 (184/192 amostras).
Ruido maior do sigma_real com 60 amostras e ACEITO por desenho (sensor de execucao deve ser reativo).

## 6. >>> CAMADA DE DECISAO OPERACIONAL -- hierarquia de 3 timeframes (Emerson 2026-07-09) <<<
Evolucao da camada 1 de 2026-06-29 (que era: swing dirige, daytrade temporiza, convergencia = corredor):
1. **M30 (swing) + M5 (daytrade) ditam o CORREDOR** (convergencia dos dois = tendencia principal validada).
2. **M1 (execucao) e o DECISOR quando tudo converge:** com o corredor na tendencia principal, o M1 navega
   dentro dele buscando os **micro pullbacks operacionais** (pontos de entrada). Assume o posto de timing
   que na camada 1 original era do M5.
3. Em estudo (conversa aberta): **M30 passar a atualizar POR TICK** (hoje gate de cadencia 1800s no indicador
   e amostragem propria no EA), para o corredor reagir sem esperar o fechamento do candle de 30min.
- **Status:** VISAO de arquitetura. Nesta etapa os indicadores validam o VISUAL; a insercao da camada no EA
  tem investigacao read-only propria (`MQL5/Docs/temp/INVESTIGACAO_CAMADA_M1_HIERARQUIA_2026-07-09.md`).

## 7. Inputs (8 identicos nos 3 indicadores) e defaults canonicos
`InpAtivo` (OURO/BITCOIN) | `InpPerfil` (CON/MOD/AGR/ULT) | `InpWinsor` (bool) | `InpMA_Start_Period` |
`InpMA_Ref_Period` | `InpVP_Livre_Hours` | `InpVP_Livre_Smooth` | `InpShow_Lines`.

Defaults canonicos (imagem `Tela_Parametros_Indicador.png`, Emerson 2026-07-09): OURO + AGRESSIVO + winsor ON
+ VP Livre off (0/0) + linhas ON. Periodos das MAs por tier:
| Tier | MA Start | MA Ref |
|---|---|---|
| M5 daytrade (v2.6) | 6 | 18 |
| M30 swing (v1.2) | 6 | 18 |
| **M1 execucao (v1.0)** | **4** | **10** |

VP Livre: janela em horas convertida p/ candles do chart (M5: x12 | M30: x2 | M1: x60). Cap 720h.

## 8. Historico de dados (medido em PROD 2026-07-09, Exness-MT5Trial11)
- XAU: M1 disponivel desde 2026-03-27 (cap ~100k barras) -> plot M1 cobre ~3.5 meses. H1 fundo (2021+).
- BTC: M1 so desde 2026-06-30 (~9 dias de plot). Warmup OK (H1 desde 2023).

## 9. PROXIMA ETAPA -- alinhamento com o EA (principio)
- Paridade total indicador <-> EA <-> analise (mesmas contagens, calibragem e pipeline). O EA ja tem o VP
  daytrade (modulo 20 v2) e o VP swing + corredor logado (modulo 23, paridade com o indicador M30).
- NOVO: camada M1 decisoria (sec 6) -- investigacao read-only antes de qualquer edicao; PROD blindada;
  compilacao = Emerson. Pendencia herdada: `VP2_D1_BARS` 260 vs 312 (decisao C de 2026-06-29, em aberto).
