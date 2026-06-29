# SPEC -- Indicador ZiahTrader MA VP v2.3

> **Tipo:** Especificacao tecnica do indicador standalone.
> **Versao do indicador:** v2.3 (calibragem unica universal, 2 EMAs paralelas sobre VP, 1 VP Livre opcional c/ suavizacao EMA, 4 plots, 5 inputs em grupo unico, otimizacoes B1-B6 preservadas).
> **Arquivo do codigo:** `MQL5/Indicators/ZiahTrader_MA_VP.mq5` (~851 linhas).
> **Status:** estavel; rodando em desenvolvimento no terminal de TESTES.

---

## 1. Visao geral

O indicador calcula um sinal de volatilidade composta (VP, `n_sigma`) sobre
o preco do par configurado e desenha sobre ele 2 medias moveis exponenciais
(EMAs) -- **MA Start** e **MA Ref** -- ambas em modo paralela sobre o
`n_sigma`. Adicionalmente, plota 1 linha opcional de **VP Livre** com janela
em horas inteiras configuravel pelo operador (1 a 720h), reusando o mesmo
`sigma_final` do VP 24h e com suavizacao EMA opcional aplicada in-place no
proprio buffer (0 = valor cru, >0 = periodo da EMA). 17 linhas horizontais
de referencia (niveis -8 a +8 sigma) ficam sempre ativas como escala visual.

A partir da v2.3, a calibragem e **universal**: nao ha mais separacao
COMPRA/VENDA. Operador define um unico conjunto de periodos (Start, Ref) e
uma unica janela de VP Livre, interpretando visualmente as linhas conforme
o regime observado no chart.

A janela do indicador e separada (`indicator_separate_window`), com 4 plots
(VP, MA Start, MA Ref, VP Livre) mais 17 objetos `OBJ_HLINE` criados em
runtime com nomes subwin-aware (cada instancia do indicador tem seu proprio
conjunto de HLINEs).

---

## 2. Pipeline VP v2 -- formula passo a passo

A formula segue o pipeline portado do velocimetro do Portal Ziah Trader
(Python). Detalhes do historico de portabilidade em
`../relatorios/RELATORIO_ORIGEM_VP_v2.md`.

### 2.1 Componente historico -- `sigma_hist`

Calculado a partir das ultimas N barras D1 (default 420 barras, minimo 30):

```
1. Copiar N barras D1 do simbolo (CopyRates).
2. Excluir a barra D1 atual que contem o timestamp (pattern v2 Portal).
3. Calcular pct_change sobre os closes D1 restantes:
       ret[i] = close[i] / close[i-1] - 1
4. Aplicar winsor com quantis (0.005, 0.995):
       ret_w[i] = clip(ret[i], q_005, q_995)
5. Aplicar EWMA RiskMetrics com lambda = 0.92 e var_0 = 0:
       var[t] = lambda * var[t-1] + (1 - lambda) * ret_w[t]^2
6. sigma_hist = sqrt(var_final)
```

Cache: o resultado e cacheado por dia D1 (chave = timestamp da barra D1
contendo o tick atual). Recalculo so na virada do dia.

### 2.2 Componente recente -- `sigma_real`

Calculado a partir das ultimas N barras M5 (default 288 barras, minimo 200):

```
1. Copiar N barras M5 do simbolo.
2. Calcular pct_change sobre os closes M5.
3. Aplicar winsor com quantis (0.005, 0.995).
4. Calcular std amostral (ddof=1) sobre os retornos winsorizados.
5. sigma_real = std (SEM anualizacao -- decisao consciente vs NIX).
```

**Sem anualizacao** e divergencia consciente do legado NIX e essencial para
paridade com o Portal. Multiplicar por `sqrt(N)` quebraria a paridade.

### 2.3 Volatilidade composta -- `sigma_final`

Combinacao hibrida ponderada:

```
sigma_final = alpha * sigma_hist + (1 - alpha) * sigma_real
              com alpha = 0.55
```

Piso numerico de seguranca: se `sigma_final < 1e-12`, o calculo da barra
falha (retorna sentinela invalido).

### 2.4 Sinal final -- `n_sigma`

```
ret_24h  =  price_now / price_24h_ago - 1
n_sigma  =  ret_24h / sigma_final
```

Onde:

- `price_now`:
  - na **vela corrente** (i == rates_total - 1): midprice live calculado
    via `SymbolInfoTick`: `(bid + ask) / 2`. Fallback para `last`, depois
    `bid`, depois `ask`, depois close da vela.
  - em **barras historicas**: close da propria vela M5 (definitivo).
- `price_24h_ago`: close da primeira barra do buffer M5 (288 barras
  atras = aproximadamente 24 horas).

**Sem clamp.** O valor de `n_sigma` e exportado sem limitar amplitude.
Visualmente, o intervalo tipico fica entre -4 e +4; eventos extremos
podem ultrapassar.

### 2.5 Gate de cadencia (vela corrente)

Na vela corrente, o calculo de `n_sigma` so e refeito quando passaram
pelo menos `kSampleIntervalSec = 300` segundos desde a ultima amostra.
Entre amostras, o indicador reusa os ultimos valores calculados
(`s_last_*`), o que mantem o plot estavel e evita oscilacoes
sub-amostrais.

Cache M5 do v1.34 foi **removido** -- substituido por este gate temporal,
que evita a divergencia conhecida do cache por chave M5.

### 2.6 VP Livre -- `n_sigma_short` (v2.2+ unificado em v2.3)

A partir da v2.2, o indicador pode plotar 1 linha adicional de **VP Livre**.
Em v2.2 eram 2 linhas (uma por direcao); em v2.3 a linha foi unificada
seguindo a colapso da calibragem direcional. Formula identica ao VP 24h,
divergindo apenas na janela do retorno e com suavizacao EMA opcional:

```
# Valor cru por barra (sempre calculado quando VP Livre esta ativo)
ret_short[i]      = (price_now / close[i - window_candles_M5]) - 1
n_sigma_raw[i]    = ret_short[i] / sigma_final

# Suavizacao EMA opcional (in-place no proprio buffer)
if alpha > 0 and Buf[i-1] != EMPTY:
    Buf[i] = alpha * n_sigma_raw[i] + (1 - alpha) * Buf[i-1]
else:
    Buf[i] = n_sigma_raw[i]    # seed (primeira amostra) OU Smooth = 0
```

Onde:

- `price_now` -- mesma referencia do VP 24h: midprice live na vela
  corrente, close M5 nas barras historicas.
- `sigma_final` -- mesmo valor calculado para o VP 24h naquela mesma
  barra (reusado via out params de `_NSigmaAsOfBarra`). Nao recalcula.
- `window_candles_M5` -- janela em candles M5 derivada da janela em
  horas configurada via input: `horas * 12` (12 candles M5 = 1 hora).
  Aceita 1 a 720 horas (30 dias); 0 desliga o VP Livre; >720 e forcado
  a 720 com warning no log.
- `alpha` -- `2 / (Smooth + 1)` quando `InpVP_Livre_Smooth > 0`;
  `0.0` quando o input e 0 (suavizacao desligada). Periodo < 2 loga
  WARN (atipico, mas permitido).

**Sem buffer extra para o cru:** quando a suavizacao esta ativa, o
buffer `BufVP_Livre` recebe diretamente o valor suavizado. O cru
nao e persistido. Quando suavizacao = 0, o cru vai direto no buffer.

**Implicacao operacional:** janela menor produz linha mais nervosa
(sensivel a movimentos curtos); janela proxima de 23h se aproxima
visualmente do VP 24h pontilhado (default v2.3 e 23h justamente para
operar como gate macro "alinhado a janela do VP base"). Janelas longas
(ex: 36h, 48h, 72h) expressam movimentos macro. A suavizacao EMA
reduz oscilacoes sub-amostrais sem deslocar a tendencia. Permite ao
operador calibrar visualmente qual combinacao janela+suavizacao
funciona melhor como gate macro.

**Premissa de chart:** o `close[]` consumido e o array do CHART
corrente, nao do simbolo M5. A formula `horas * 12` so e correta em
chart M5. Em outros timeframes a janela vira "horas * 12 candles do
chart" (ex: em chart H1 com input=1h, janela efetiva = 12 horas).
**Usar em chart M5.**

Gate de cadencia 300s e gate MTF se aplicam igualmente -- VP Livre
respeita as mesmas guardas do VP 24h. A suavizacao opera sobre o
cru ja calculado (apos o gate).

---

## 3. EMAs sobre `n_sigma`

### 3.1 Formula classica

```
alpha[N] = 2.0 / (N + 1.0)
```

### 3.2 Seed e atualizacao

```
Seed (primeira amostra valida):
    EMA[0] = n_sigma[0]

Atualizacao (i >= 1):
    EMA[i] = alpha[N] * n_sigma[i] + (1 - alpha[N]) * EMA[i-1]
```

Se a EMA estava em `EMPTY_VALUE` (gap, warmup), o proximo valor valido
reinicia o seed (EMA reseta para o valor corrente).

### 3.3 Modo unico -- paralela

Ambas as MAs (Start e Ref) operam em **modo paralela**: o input da EMA
Ref e sempre o proprio `n_sigma`, exatamente como a EMA Start. As duas
EMAs "competem" diretamente sobre o mesmo sinal.

O modo cadeia (Ref consumindo a saida ja suavizada da Start) existiu como
opcao reservada na v2.0 mas nunca foi ativado e foi removido
definitivamente em v2.1 por decisao do Emerson de 2026-05-18. Detalhes
em `../legado/CHANGELOG_LEGADO.md`.

---

## 4. Validacao admin R4-R6

A validacao espelha o modulo interno do EA que governa configuracoes
admin-driven (apenas a parte relativa a paralelas). Roda em `OnInit` apos
a leitura dos inputs e e idempotente.

| Regra | Verificacao | Acao |
|---|---|---|
| **R4** | Qualquer periodo ativo (`InpMA_Start_Period` ou `InpMA_Ref_Period`) `< 2` | Loga aviso (valor atipico, mas permitido). |
| **R5** | Paralelas com `InpMA_Start_Period >= InpMA_Ref_Period` (ambos > 0) | Loga aviso (gate em BLOCK permanente esperado). |
| **R6** | Ambos os slots de MA zerados (Start = 0 E Ref = 0) | Loga aviso `"R6: nenhum slot MA ativo"`; indicador nao plota MA Start nem MA Ref. |

R1/R2/R3 do esquema antigo (todas relativas a configuracoes Suavizadas)
foram removidas em v2.1 -- nao ha mais conflito possivel entre Bruta e
Suavizada nem cadeia desativada por falta de insumo. R6 foi simplificada
em v2.3 (uma direcao apenas, em vez de duas).

Apos validacao, valores efetivos sao gravados em variaveis estaticas
`s_*_eff` consumidas pelo `OnCalculate`.

---

## 5. Buffers e plots

### 5.1 Buffers

```
double BufVP[]        -- n_sigma 24h instantaneo (plot 0)
double BufMA_Start[]  -- EMA Start (plot 1)
double BufMA_Ref[]    -- EMA Ref (plot 2)
double BufVP_Livre[]  -- VP Livre (plot 3)
```

Total: **4 buffers, 4 plots**.

### 5.2 Estilo dos plots

| Plot | Label | Cor | Estilo | Largura |
|---|---|---|---|---|
| 0 | VP | clrSilver | STYLE_DOT | 1 |
| 1 | MA Start | clrDodgerBlue | STYLE_SOLID | 2 |
| 2 | MA Ref | clrAqua | STYLE_SOLID | 2 |
| 3 | VP Livre | clrOrange | STYLE_DASH | 2 |

O toggle unico `InpShow_Lines` alterna entre `DRAW_LINE` e `DRAW_NONE`
para os plots 1-3 -- idempotente em todo `OnInit`. O plot 0 (VP)
permanece sempre visivel (nao recebe toggle). O plot 3 (VP Livre) so
fica visivel quando `InpShow_Lines = true` **e** `InpVP_Livre_Hours > 0`
(janela ativa); caso contrario, `DRAW_NONE`. STYLE_DASH escolhido para
diferenciar visualmente das EMAs (STYLE_SOLID).

### 5.3 Linhas horizontais de referencia (`OBJ_HLINE`)

17 objetos `OBJ_HLINE` desenhados em runtime na sub-janela do indicador,
nos niveis inteiros de **-8 a +8 sigma** (inclusivo):

- Prefixo do nome: `ZTMAVP_REF_W<subwin>_<i>` (ex: `ZTMAVP_REF_W1_3`).
- O componente `<subwin>` torna o nome unico por instancia do indicador.
  Permite multiplas instancias coexistindo no mesmo chart sem colisao de
  nomes via `ObjectFind`.
- Estilo: cinza (`clrSilver`), pontilhado (`STYLE_DOT`), largura 1, BACK,
  HIDDEN (nao selecionavel).
- **Sem labels visuais no plot.** Operador le valor sigma via crosshair
  do MT5 (passar o mouse na linha mostra o preco). Decisao da v2.1:
  tentativas anteriores de labels via `OBJPROP_TEXT` (nao renderiza) e
  via OBJ_TEXT complementares (polui o plot) foram descartadas.

Por que `OBJ_HLINE` em vez de `#property indicator_level`? Porque
`indicator_level` forca o auto-scale do eixo Y a incluir todo o range,
comprimindo as MAs visualmente em timeframes maiores. `OBJ_HLINE` e
puramente visual e nao influencia o auto-scale -- a escala vertical fica
guiada pelos plots dinamicos.

Os objetos sao criados apos a primeira chamada de `OnCalculate` (assim
que a sub-janela esta registrada via `ChartWindowFind()`). Sao deletados
em `OnDeinit` apenas se o motivo for `REMOVE` / `PROGRAM` / `CLOSE`;
em `PARAMETERS` / `RECOMPILE` / `CHARTCHANGE` os objetos sao preservados
e reaproveitados.

**Cleanup transitivo:** em cada criacao, o indicador deleta 1x os objetos
orfaos de schemas anteriores (HLINEs `ZTMAVP_ref_*` da v2.0 e OBJ_TEXT
`..._LBL` da v2.1.1) para evitar lixo visual em quem migrar do schema
antigo. Idempotente e barato apos primeira passagem.

---

## 6. Inputs (5 totais, 1 grupo unico)

### 6.1 Grupo `=== Calibragem MAs VP ===`

| Input | Tipo | Default | Descricao |
|---|---|---|---|
| `InpMA_Start_Period` | int | 14 | Periodo MA Start (0 desativa) |
| `InpMA_Ref_Period` | int | 0 | Periodo MA Ref (0 desativa) |
| `InpVP_Livre_Hours` | int | 23 | VP Livre: janela em horas (0=off, max=720) |
| `InpVP_Livre_Smooth` | int | 15 | VP Livre: suavizacao EMA (0=off, >0=periodo da EMA in-place) |
| `InpShow_Lines` | bool | true | Exibir linhas (toggle unico para MA Start, MA Ref e VP Livre) |

**Calibragem unica universal:** a partir da v2.3 nao existe mais
distincao entre direcao de compra e direcao de venda. Um unico conjunto
de inputs controla todas as linhas configuraveis. Defaults baseados na
calibragem de referencia validada (14/0 para MAs, 23h/s15 para VP Livre).

---

## 7. Constantes internas

Todas em escopo de arquivo, nao expostas como input.

| Constante | Valor | Significado |
|---|---|---|
| `kD1_EWMA_Bars` | 420 | Numero de barras D1 copiadas para EWMA |
| `kLambda_EWMA` | 0.92 | Lambda do EWMA RiskMetrics |
| `kAlpha_Hibrido` | 0.55 | Peso de `sigma_hist` na combinacao hibrida |
| `kWinsor_Lower` | 0.005 | Quantil inferior do winsor |
| `kWinsor_Upper` | 0.995 | Quantil superior do winsor |
| `kM5_Window_Bars` | 288 | Janela M5 para `sigma_real` e `ret_24h` (~24h) |
| `kSampleIntervalSec` | 300 | Gate de cadencia na vela corrente (5 minutos) |

E os defines numericos:

| Define | Valor | Significado |
|---|---|---|
| `VP_NMIN_D1` | 30 | Minimo de retornos D1 para EWMA valida |
| `VP_NMIN_M5` | 200 | Minimo de retornos M5 winsorizados |
| `VP_INVALID` | DBL_MAX | Sentinela de valor invalido |
| `VP_EPS` | 1e-12 | Piso numerico para `sigma_final` |
| `RECALC_THROTTLE_SEC` | 5 | Throttle entre full recalcs quando ha gap real |
| `ZTMAVP_REF_PREFIX_BASE` | "ZTMAVP_REF_W" | Prefixo base dos nomes de OBJ_HLINE |
| `ZTMAVP_REF_COUNT` | 17 | Numero de HLINEs (-8..+8 sigma inclusivo) |

Statics derivados de inputs (calculados em `OnInit`):

| Variavel | Tipo | Calculo | Significado |
|---|---|---|---|
| `s_ma_start_eff`    | int    | `InpMA_Start_Period` apos R4-R6 | Periodo efetivo da MA Start |
| `s_ma_ref_eff`      | int    | `InpMA_Ref_Period` apos R4-R6 | Periodo efetivo da MA Ref |
| `s_vp_livre_window` | int    | `clamp(InpVP_Livre_Hours, 0, 720) * 12` | Janela VP Livre em candles M5 (0 = off) |
| `s_vp_livre_alpha`  | double | `2 / (max(0, InpVP_Livre_Smooth) + 1)` se input > 0, senao `0.0` | Alpha da EMA de suavizacao; 0.0 = suavizacao off |

---

## 8. Lifecycle

### 8.1 OnInit

1. Detectar `UninitializeReason()` do init anterior.
2. Se motivo for `PARAMETERS`, `RECOMPILE`, `CHARTCHANGE` ou `0` (cold
   start), resetar caches e statics dos ultimos valores, e marcar
   `s_need_full_reset = true`.
3. Memorizar se o chart e M5 (`g_chart_is_m5 = (_Period == PERIOD_M5)`)
   para a otimizacao B3.
4. Registrar 4 buffers (`SetIndexBuffer`).
5. Configurar `PLOT_EMPTY_VALUE` em todos os 4 plots.
6. Rodar validacao R4-R6 sobre os inputs (`_ApplyAdminRules`).
7. Validar `InpVP_Livre_Hours` (forcar `[0, 720]`, logar WARN se >720)
   e pre-calcular `s_vp_livre_window` em candles M5 (`horas * 12`).
   Em seguida, validar `InpVP_Livre_Smooth` (forcar `max(0, ...)`,
   logar WARN se `> 0 && < 2`) e pre-calcular `s_vp_livre_alpha =
   2/(N+1)` (0.0 quando input = 0).
8. Aplicar toggle unico `InpShow_Lines` via
   `PlotIndexSetInteger(PLOT_DRAW_TYPE, ...)` para os plots 1-3.
   Plot 1 (MA Start) visivel quando `InpShow_Lines = true` e
   `InpMA_Start_Period > 0`. Plot 2 (MA Ref) idem para Ref. Plot 3
   (VP Livre) visivel quando `InpShow_Lines = true` e
   `s_vp_livre_window > 0`. Plot 0 (VP) sempre visivel.
9. Definir `IndicatorSetString(INDICATOR_SHORTNAME, ...)` com config
   efetiva no formato `"ZT_MA_VP v2.3 [X/Y Wh/sN]"` (X = MA Start,
   Y = MA Ref, W = janela VP Livre em horas, N = periodo da suavizacao
   EMA; 0/s0 quando desligado).
10. Logar 1 linha de observabilidade com config final:
    `[ZT_MA_VP] v2.3 | <ON|OFF> MA Start=X Ref=Y | VP_Livre=Wh Smooth=N`.

### 8.2 OnCalculate (por barra)

1. Se `rates_total == 0`, retornar 0 (chart vazio).
2. **Criacao retardada das OBJ_HLINE:** se ainda nao criadas, chama
   `ChartWindowFind()`. Se a sub-janela esta registrada, cria os 17
   objetos com nome subwin-aware e memoriza `g_subwin_idx`.
3. **Gate MTF:** se historico D1 ou M5 insuficiente, retornar
   `prev_calculated` (fix bug 4.1: evita zerar buffers em retentativa).
4. **Decisao de full recalc:** se `s_need_full_reset == true` ou
   (`g_hadGaps == true` e throttle de 5s respeitado), force full recalc.
   Em full recalc, zera todos os 4 buffers e starts em 0.
5. **Snapshot da config + pre-calculo (otimizacoes B3/B4/B5):**
   - Determina `can_use_arith_shift = g_chart_is_m5 && (bars_m5 == rates_total)`
     (B3).
   - Calcula `hot_start = rates_total - kM5_Window_Bars` (B1).
   - Pre-calcula 2 alphas EMA (`a_s` para MA Start, `a_r` para MA Ref) (B5).
   - Flags `lines_active` (InpShow_Lines E pelo menos 1 MA com periodo > 0)
     e `vp_livre_active` (InpShow_Lines E `s_vp_livre_window > 0`).
6. **Loop por barra (i = start ate rates_total - 1):**
   - Vela corrente + gate 300s nao expirado: reusa `s_last_vp`,
     `s_last_ma_start`, `s_last_ma_ref` e `s_last_vp_livre`.
   - Caso contrario: calcula `sigma_hist` (com cache D1), depois
     `n_sigma` (pipeline 2.4, passando `shift_m5` por aritmetica se
     possivel, e capturando `sigma_final` + `price_now` via out params
     de `_NSigmaAsOfBarra`), depois VP Livre, depois EMAs ativas.
   - **VP Livre:** se ativo e `i >= window`, calcula `n_sigma_raw =
     (price_now / close[i - window] - 1) / sigma_final` reusando o
     `sigma_final` e `price_now` ja calculados. Se `s_vp_livre_alpha > 0`
     e `Buf[i-1] != EMPTY_VALUE`, aplica EMA in-place; caso contrario
     `Buf[i] = raw` (seed ou suavizacao desligada).
   - Em gap (`sigma_hist` ou `n_sigma` invalido), marca buffers ativos
     com `EMPTY_VALUE`. So sinaliza `hadGapsThisPass = true` se
     `i >= hot_start` (zona quente) -- fix B1.
   - Bloco MA (Start + Ref) fica atras de `if(lines_active)` -- MA
     totalmente inativa pula calculo inteiro (B4 adaptada).
   - Apos a vela corrente, atualiza `s_last_vp`, `s_last_ma_start`,
     `s_last_ma_ref`, `s_last_vp_livre` e `s_last_sample_ts`.

### 8.3 OnDeinit

Deleta as 17 `OBJ_HLINE` da sub-janela memorizada em `g_subwin_idx`
**apenas** se motivo for `REMOVE` / `PROGRAM` / `CLOSE`. Em `PARAMETERS`
/ `RECOMPILE` / `CHARTCHANGE`, preserva os objetos (sao reaproveitados
no proximo `OnCalculate` via `ObjectFind`).

---

## 9. Otimizacoes de performance (v2.1, preservadas em v2.2/v2.3)

As otimizacoes abaixo nao alteram nenhum valor calculado -- preservam
exatamente a matematica da v2.0. O objetivo e eliminar custo CPU
redundante que causava degradacao perceptivel no terminal MT5.

| Codigo | Otimizacao | Impacto |
|---|---|---|
| **B1** | Deteccao de gap restrita a zona quente (ultimas `kM5_Window_Bars` barras). Gaps em barras antigas naturalmente invalidas (`bars_d1 < 420` no inicio da serie) deixam de re-armar `g_hadGaps`. | CRITICO -- elimina o loop reciclico de full recalc a cada 5s que era a root cause da degradacao de CPU em v2.0. |
| **B3** | Substitui `iBarShift(_Symbol, PERIOD_M5, t, false)` por aritmetica de indice (`rates_total - 1 - i`) quando o chart e M5 e `bars_m5 == rates_total`. Fallback iBarShift caso contrario. | MEDIO -- elimina N chamadas de iBarShift no hot path por OnCalculate em chart M5. |
| **B4** | Bloco EMA (MA Start + MA Ref) pulado inteiro se `lines_active == false`. Em v2.3, MA passou de "BUY+SELL" para um unico bloco unificado. | MEDIO -- quando MAs desligadas (toggle off ou ambos periodos = 0), evita escrita de EMPTY_VALUE em cada barra. |
| **B5** | Alphas EMA (`2/(N+1)`) pre-calculados fora do loop em vez de recomputados a cada barra. Em v2.3 sao 2 alphas (Start + Ref) em vez de 4 (BUY/SELL Start/Ref). | BAIXO -- divisoes deslocadas para fora do hot path. |
| **B6** | `ArrayResize(arr, n, n)` com reserve em vez de `ArrayResize(arr, n)` no hot path (`_PctChange`, `_Winsor`, `_Quantile`, `_StdSample`). | BAIXO -- reduz reallocs em arrays temporarios. |

Otimizacao adicional aplicada como consequencia natural de B1:
`RECALC_THROTTLE_SEC = 5` continua existindo mas raramente dispara, pois
`g_hadGaps` so vira true em gaps reais agora.

---

## 10. Limitacoes conhecidas

- **Nao funciona no Strategy Tester.** O Tester nao alimenta
  `SymbolInfoTick()` da mesma forma que um chart live, e o calculo do
  midprice na vela corrente fica indefinido.
- **Cadencia visual proporcional ao timeframe do chart.** Em chart M5,
  uma amostra por 5 minutos; em chart H1, uma por hora. Mudar o
  timeframe muda a escala temporal das EMAs sem mudar o periodo `N`.
- **Bootstrap em par novo.** Em par recem-disponibilizado no broker
  (historico D1 < 420 ou M5 < 288), o indicador retorna
  `prev_calculated` em loop, mantendo o que ja desenhou ate dados
  suficientes serem alimentados.
- **Sem persistencia entre sessoes do MT5.** Caches e statics sao
  reconstruidos a cada cold start.
- **Sem labels visuais nas HLINEs.** Operador le valor sigma de cada
  linha via crosshair (passar mouse). Decisao da v2.1 -- ver
  `../legado/CHANGELOG_LEGADO.md`.
- **VP Livre assume chart M5.** A formula `horas * 12` para derivar a
  janela em candles M5 so e exata em chart M5. Em outros timeframes a
  janela vira "horas * 12 candles do chart" (ex: chart H1 com input=1h
  => janela efetiva = 12 horas). Usar VP Livre em chart M5; alternar
  timeframe sem ajustar input distorce a leitura.
- **Cap defensivo de 720h (30 dias) na janela do VP Livre.** Janelas
  maiores exigiriam `rates_total > 720 * 12 = 8640` candles M5 e seriam
  raramente uteis -- o cap evita acesso fora dos limites do array
  `close[]`. Valores >720 sao reduzidos a 720 com WARN no log.

---

## 11. Equivalencia conceitual com modulo interno do EA

O EA mantem um modulo interno que espelha matematicamente este pipeline
(mesmo `sigma_hist`, mesmo `sigma_real`, mesmo `sigma_final`, mesma
formula EMA). O alinhamento foi validado em 2026-04-28 com paridade
empirica dentro de pequena margem numerica.

Note bem que o modulo interno do EA e ferramenta de decisao de trading,
operando em cadencia diferente da cadencia visual do chart. Para detalhes
sobre a diferenca de cadencia entre indicador e EA, ver
`../investigacoes/DIVERGENCIA_CADENCIA_EA.md`.

A documentacao deste indicador descreve **o que o indicador faz**. Como o
EA usa internamente o sinal -- gates, scores, mecanismos defensivos --
nao e escopo deste repositorio.

---

## 12. Glossario

| Termo | Definicao |
|---|---|
| **VP** | Volatilidade composta (`n_sigma`), sinal final do pipeline |
| **`n_sigma`** | Z-score do retorno de 24h dividido pela volatilidade composta |
| **`sigma_hist`** | Volatilidade historica EWMA sobre retornos D1 winsorizados |
| **`sigma_real`** | Std amostral de retornos M5 winsorizados (sem anualizacao) |
| **`sigma_final`** | Combinacao hibrida `alpha * sigma_hist + (1-alpha) * sigma_real` |
| **EWMA** | Exponentially Weighted Moving Average (modelo RiskMetrics) |
| **Winsor** | Clip de outliers nos quantis [q_low, q_high] |
| **pct_change** | Retorno percentual: `(p_t / p_{t-1}) - 1` |
| **EMA** | Exponential Moving Average classica com `alpha = 2/(N+1)` |
| **Paralela** | Modo unico das MAs (Start e Ref) desde v2.1: ambas operam sobre `n_sigma` em paralelo, sem cadeia |
| **Cadeia (legado)** | Modo descartado em v2.1: Ref consumiria a saida ja suavizada da Start. Ver `../legado/CHANGELOG_LEGADO.md` |
| **VP Livre** | Variante do VP 24h com janela de retorno em horas (1-720) configuravel. Reusa o mesmo `sigma_final`. Suavizacao EMA opcional in-place. Introduzido em v2.2; unificado em v2.3 (1 linha em vez de 2). |
| **Calibragem unica (v2.3)** | A partir da v2.3 nao existe mais separacao COMPRA/VENDA. Um unico conjunto de inputs (`InpMA_Start_Period`, `InpMA_Ref_Period`, `InpVP_Livre_Hours`, `InpVP_Livre_Smooth`) controla todas as linhas. |

---

## 13. Historico de versoes

| Versao | Data | Marco |
|---|---|---|
| v2.0 | 2026-05-11 | Admin-driven, 4 EMAs, 10 inputs, validacao R1-R6, 17 OBJ_HLINE |
| v2.1 | 2026-05-19 | Paralelas-only (6 inputs), otimizacoes B1-B6, HLINEs subwin-aware, sem labels visuais |
| v2.2 | 2026-05-19 | 2 linhas VP Livre por direcao (janela em horas, cap 720, 10 inputs c/ Smooth); suavizacao EMA opcional in-place; `_NSigmaAsOfBarra` expoe `sigma_final` + `price_now` via out params; assume chart M5 |
| v2.3 | 2026-05-19 | Unificacao da calibragem (remove COMPRA/VENDA): 10 -> 5 inputs em 1 grupo, 7 -> 4 buffers/plots, 2 toggles -> 1 (`InpShow_Lines`), variaveis e statics direcionais colapsadas. R6 simplificada para uma direcao. Defaults novos: Start=14, Ref=0, VP_Livre=23h/Smooth=15. Pipeline VP, formulas EMA, gate 300s, OBJ_HLINE e otimizacoes B1-B6 preservados. |

---

*Fim do SPEC_INDICADOR_MA_VP.md*
