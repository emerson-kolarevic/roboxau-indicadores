# ZiahTrader MA VP Indicators -- 3-tier family

> **Type:** standalone indicators for MetaTrader 5 (MQL5).
> **Files:** `MQL5/Indicators/ZiahTrader_MA_VP_M5.mq5` (day trade, v2.6) +
> `ZiahTrader_MA_VP_M30.mq5` (swing, v1.2) + `ZiahTrader_MA_VP_M1.mq5` (execution, v1.0).
> (Compile in MetaEditor to generate the `.ex5` files.)
> **Canonical spec:** `specs/SPEC_MA_VP_3_TIERS.md` (formula, per-asset windows, defaults, hierarchy).
> **Distribution:** optional, bundled with the ZiahTrader EA.
>
> **Note:** detailed specs, reports and code comments are written in Portuguese (pt-BR).

---

## 1. Purpose

**Visual transparency** tools that let the trader follow, on the MT5 chart,
the price volatility regime across three time horizons. Each indicator plots
the **VP** signal (`n_sigma` -- the window return normalized by a composite
volatility estimate) + two EMAs over it (**MA Start** and **MA Ref**) + an
optional **Free VP**. A single universal calibration is used (no separate
BUY/SELL direction since v2.3).

| Tier | File | Chart | Horizon | Role |
|---|---|---|---|---|
| DAY TRADE | `ZiahTrader_MA_VP_M5` | M5 | 24h return / daily volatility (D1) | daily regime |
| SWING | `ZiahTrader_MA_VP_M30` | M30 | 7-day return / weekly volatility (W1) | main trend |
| EXECUTION | `ZiahTrader_MA_VP_M1` | M1 | 1h return / hourly volatility (H1) | micro-timing |

Operational hierarchy: **M30 + M5 define the corridor** (convergence =
validated trend); **M1 is the decision layer** inside the corridor, looking
for tradable micro pullbacks. See section 6 of the spec for details.

---

## 2. Principle P3 -- full independence from the EA

The indicators are **standalone**: no `#include` from the EA, no shared
global variables, and they compile on any MT5 terminal without the EA. The EA
implements the same pipeline internally (in its own modules); the relationship
is **mathematical mirroring**, not dependency. Removing an indicator from the
chart does not affect the EA.

---

## 3. What is shown on the chart (identical across all 3, in a separate subwindow)

| Plot | Line | Color | Style | Meaning |
|---|---|---|---|---|
| 0 | VP | gray (clrSilver) | thin dotted | instantaneous n_sigma for the tier |
| 1 | MA Start | strong blue (clrDodgerBlue) | solid | short EMA over n_sigma |
| 2 | MA Ref | light blue (clrAqua) | solid | long EMA over n_sigma |
| 3 | Free VP | orange (clrOrange) | dashed | VP with a configurable window in hours (optional) |

Plus **17 reference OBJ_HLINE levels** (-8 to +8 sigma), subwindow-aware (2+
instances can coexist on the same chart -- prefixes ZTMAVP_REF_W /
ZTMAVPSW_REF_W / ZTMAVPM1_REF_W). Each line's sigma value is readable via the
crosshair.

---

## 4. Inputs (8, identical across all 3) and canonical defaults

| Input | Default | Description |
|---|---|---|
| `InpAtivo` (asset) | `OURO` (gold) | per-asset window set (`OURO` = gold, with session gaps / `BITCOIN` = 24/7 market) |
| `InpPerfil` (profile) | `AGRESSIVO` (aggressive) | lambda/alpha of the sigma estimator (conservative / moderate / aggressive / ultra -- see spec section 4) |
| `InpWinsor` | true | trims gap/spike outliers in the returns used for sigma (winsorization) |
| `InpMA_Start_Period` | M5/M30: **6** ; M1: **4** | short EMA (0 = off) |
| `InpMA_Ref_Period` | M5/M30: **18** ; M1: **10** | long EMA (0 = off) |
| `InpVP_Livre_Hours` | 0 (off) | Free VP window in hours (max 720) |
| `InpVP_Livre_Smooth` | 0 (off) | EMA smoothing for the Free VP |
| `InpShow_Lines` | true | single toggle for the configurable lines |

Internal per-asset windows: see the table in spec section 3 (bar counts
measured on the terminal with the `ZT_DiagContagemCandles` diagnostic).

---

## 5. How to install on MT5

1. Copy the desired `.ex5` files to the terminal's `MQL5/Indicators/` folder.
2. Refresh the Navigator (right-click -> Refresh) or restart MT5.
3. Drag each indicator onto a chart with the TIMEFRAME matching its tier
   (M5 / M30 / M1) -- running it on another timeframe logs a warning and
   produces incorrect visual cadence.
4. Set `InpAtivo` according to the symbol (`OURO` for XAUUSD; `BITCOIN` for BTCUSD).

**History requirements:** DAY TRADE: D1 >= ~314 + M5 >= 276. SWING: W1 >=
~22 + M30 >= 230. EXECUTION: H1 >= ~32 + M1 >= 60. Insufficient history =
warmup (empty plot until the minimums are reached).

---

## 6. Relationship with the web portal and the EA

- **Web portal (results page):** uses the same `n_sigma` computed by the
  Python backend ("same indicator, two environments"); the portal is the
  auditable reference, the indicator is the real-time reading. See
  `relatorios/RELATORIO_ORIGEM_VP_v2.md`.
- **EA:** implements the same pipeline internally (day trade VP + swing VP).
  Cadence and sampling differ -- **strict visual equivalence is NOT expected**
  (see `investigacoes/DIVERGENCIA_CADENCIA_EA.md`).

---

## 7. Known limitations

- **Do not work in the Strategy Tester** (they rely on live `SymbolInfoTick()`
  for the current bar's midprice).
- **Visual cadence depends on the chart timeframe** -- run each tier on its own timeframe.
- **Bootstrap on a new symbol:** warmup until the history minimums are met.
- **M1 tier:** sigma_real with ~60 samples is noisier than in the other tiers,
  and winsorization is nearly inert on the M1 side (accepted by design --
  spec section 5). The broker's M1 history limits the plot range (XAU ~3.5
  months; BTC only a few days as of July 2026).
- **Performance:** v2.1 optimizations preserved (hot zone, arithmetic shift,
  precomputed alphas); on M1 charts, watch CPU usage on first load.

---

## 8. Detailed documentation (in Portuguese)

| Document | Content |
|---|---|
| `specs/SPEC_MA_VP_3_TIERS.md` | **CANONICAL** -- formula, measured windows, profiles, defaults, 3-timeframe hierarchy |
| `specs/SPEC_INDICADOR_MA_VP.md` | [partially superseded] v2.3 era, M5 only, pre-flip -- buffer/validation details |
| `relatorios/RELATORIO_ORIGEM_VP_v2.md` | porting the volatility gauge from the portal (Python) to MQL5 |
| `investigacoes/DIVERGENCIA_CADENCIA_EA.md` | indicator vs. EA cadence |
| `sprints/SPRINT_CRIACAO_INDICADOR.md` | development timeline (f02ba42 -> v2.3) |
| `legado/CHANGELOG_LEGADO.md` | remocoes e descontinuacoes historicas |
| `CLAUDE.md` | instrucoes para o Claude Code operar neste repositorio |

---

*Fim do README.md*
