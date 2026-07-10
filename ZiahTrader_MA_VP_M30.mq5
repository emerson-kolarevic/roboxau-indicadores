//+------------------------------------------------------------------+
//|                                       ZiahTrader_MA_VP_M30.mq5    |
//|                Indicador MA VP SWING (M30) -- v1.2                |
//|                                                                  |
//| Versao SWING do ZiahTrader_MA_VP (que roda no M5/24h). Espelha a  |
//| MESMA metodologia do pipeline VP v2 (lambda 0.92, alpha 0.55,     |
//| winsor 0.005/0.995, sem anualizacao), porem escalada UM TIER      |
//| ACIMA para swing (~1 semana):                                     |
//|                                                                  |
//|   DAYTRADE (M5)            ->  SWING (M30)                        |
//|   sigma_hist: EWMA D1      ->  EWMA W1 (semanal)                  |
//|   sigma_real: std M5 (24h) ->  std M30 (7 dias)                  |
//|   retorno:    ret_24h      ->  ret_7d                            |
//|   n_sigma = ret_7d / sigma_final_semanal                         |
//|                                                                  |
//| Plota, em janela separada: VP instantaneo (swing) + MA Start +   |
//| MA Ref (EMAs paralelas sobre n_sigma) + VP Livre opcional.       |
//| 17 OBJ_HLINE de referencia (-8..+8 sigma).                       |
//|                                                                  |
//| >>> CONTAGEM DE CANDLES (regra #1 Emerson, medida pelo terminal): |
//| 7 dias = 336 barras M30 no BTC (7*48, 24/7) ; 230 no XAU (5 dias  |
//| pregao x 46, com gaps). Selecionado pela CHAVE InpAtivo (flip).   |
//| W1 sigma_hist (2 anos) = 105 barras nos DOIS (semanal calendar-   |
//| based, sem ajuste por gap).                                       |
//|                                                                  |
//| PRICE NOW na vela corrente: midprice live via SymbolInfoTick.    |
//| Barras historicas usam o close M30. Gate de cadencia 1800s (M30). |
//|                                                                  |
//| Standalone -- nao depende de nenhum modulo do EA. Para rodar no   |
//| GRAFICO M30. Calibragem unica (sem COMPRA/VENDA).                 |
//+------------------------------------------------------------------+
#property copyright   "Ziah Trader"
#property link        "https://ziahtrader.com"
#property version     "1.20"
#property description "MA VP SWING (M30): VP (n_sigma 7d / vol semanal) + MA Start + MA Ref + VP Livre"
#property description "Espelha o pipeline VP v2, escalado p/ swing (W1 + M30 + ret_7d)"
#property description "v1.2: defaults canonicos MA 6/18 (Emerson 2026-07-09). Rodar no M30"

#property indicator_separate_window
#property indicator_buffers 4
#property indicator_plots   4

//---- Plot 0: VP instantaneo swing (cinza pontilhado)
#property indicator_label1  "VP_SW"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrSilver
#property indicator_style1  STYLE_DOT
#property indicator_width1  1

//---- Plot 1: MA Start (azul forte continua)
#property indicator_label2  "MA Start"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDodgerBlue
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

//---- Plot 2: MA Ref (azul claro continua)
#property indicator_label3  "MA Ref"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrAqua
#property indicator_style3  STYLE_SOLID
#property indicator_width3  2

//---- Plot 3: VP Livre (laranja tracejado)
#property indicator_label4  "VP Livre"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrOrange
#property indicator_style4  STYLE_DASH
#property indicator_width4  2

//+------------------------------------------------------------------+
//| FLIP DE ATIVO (regra #1: contagem perfeitamente correspondente).  |
//| Chave unica que ajusta a janela SWING do M30 (7 dias):           |
//|   M30 7 dias : BTC=336 (7x48, 24/7) | XAU=230 (5 dias pregao x46) |
//| W1 sigma_hist (2 anos)=105 nos DOIS (semanal ~52/ano) -> sem flip. |
//| Contagens medidas pelo terminal (ZT_DiagContagemCandles 2026-06-29).|
//+------------------------------------------------------------------+
enum ZT_Ativo
{
   ATIVO_OURO     = 0,   // OURO (XAU) -- com gaps (7d=230 M30)
   ATIVO_BITCOIN  = 1    // BITCOIN -- 24h/7d sem gaps (7d=336 M30)
};

//+------------------------------------------------------------------+
//| PERFIL DE RISCO (lambda EWMA / alpha hibrido) -- da NIX.          |
//+------------------------------------------------------------------+
enum ZT_Perfil
{
   PERFIL_CONSERVADOR = 0,   // lambda 0.96 / alpha 0.80
   PERFIL_MODERADO    = 1,   // lambda 0.94 / alpha 0.70
   PERFIL_AGRESSIVO   = 2,   // lambda 0.92 / alpha 0.55  (default)
   PERFIL_ULTRA       = 3    // lambda 0.90 / alpha 0.45
};

//+------------------------------------------------------------------+
//| Inputs do usuario (8 totais, 1 grupo unico)                       |
//+------------------------------------------------------------------+
input group "=== Calibragem MA VP Swing (M30) ==="
input ZT_Ativo  InpAtivo      = ATIVO_OURO;       // Ativo: OURO (gaps) / BITCOIN (24h7d)
input ZT_Perfil InpPerfil     = PERFIL_AGRESSIVO; // Perfil de risco (lambda/alpha)
input bool InpWinsor          = true;   // Winsor (apara outliers de gap/spike no sigma)
input int  InpMA_Start_Period = 6;      // MA Start: periodo EMA sobre n_sigma swing (0=off)
input int  InpMA_Ref_Period   = 18;     // MA Ref: periodo EMA sobre n_sigma swing (0=off)
input int  InpVP_Livre_Hours  = 0;      // VP Livre: janela em horas (0=off) -- M30: 2 candles/h
input int  InpVP_Livre_Smooth = 0;      // VP Livre: suavizacao EMA (0=off)
input bool InpShow_Lines      = true;   // Exibir linhas

//+------------------------------------------------------------------+
//| Constantes internas (espelham pipeline VP v2 -- iguais ao M5)     |
//+------------------------------------------------------------------+
const int    kM30_Ouro          = 230;      // janela 7d M30 no OURO (5 dias pregao x 46)
const int    kM30_Bitcoin       = 336;      // janela 7d M30 no BITCOIN (7 x 48, 24/7)
const int    kW1_2anos          = 105;      // barras W1 (sigma_hist 2 anos) -- igual nos 2 ativos
const double kWinsor_Lower      = 0.005;    // quantil inferior winsor
const double kWinsor_Upper      = 0.995;    // quantil superior winsor
const int    kSampleIntervalSec = 1800;     // gate de cadencia na vela corrente (M30 = 30min)

#define VP_NMIN_W    20          // minimo de retornos W1 para EWMA semanal
#define VP_NMIN_M30  100         // minimo de retornos M30 winsorizados (7d)
#define VP_INVALID   DBL_MAX     // sentinel de valor invalido
#define VP_EPS       1e-12       // piso numerico para sigma_final

//+------------------------------------------------------------------+
//| OBJ_HLINE de referencia (-8 a +8 sigma). Prefixo proprio do SW    |
//| (nao colide com o indicador M5 no mesmo chart).                   |
//+------------------------------------------------------------------+
#define ZTMAVPSW_REF_PREFIX_BASE "ZTMAVPSW_REF_W"
#define ZTMAVPSW_REF_COUNT       17      // -8..+8 sigma (inclusivo)

//+------------------------------------------------------------------+
//| Buffers de plot (4 totais)                                         |
//+------------------------------------------------------------------+
double BufVP[];
double BufMA_Start[];
double BufMA_Ref[];
double BufVP_Livre[];

//+------------------------------------------------------------------+
//| Estado interno -- working copies dos inputs apos validacao         |
//+------------------------------------------------------------------+
int    s_ma_start_eff = 0;
int    s_ma_ref_eff   = 0;
int    s_swing_window = 0;   // janela M30 (7d) efetiva (setada pelo InpAtivo)
int    s_w_ewma_bars  = 0;   // barras W1 para sigma_hist semanal (kW1_2anos)
double s_lambda       = 0.92;// lambda EWMA efetivo (setado pelo InpPerfil)
double s_alpha        = 0.55;// alpha hibrido efetivo (setado pelo InpPerfil)
bool   s_winsor       = true;// aplica winsor? (setado pelo InpWinsor)

//+------------------------------------------------------------------+
//| Cache W1 (sigma_hist por semana W1)                                |
//+------------------------------------------------------------------+
datetime g_cache_w1_key      = 0;
double   g_cache_sigma_hist  = VP_INVALID;

//+------------------------------------------------------------------+
//| Gate na vela corrente + statics dos ultimos valores                |
//+------------------------------------------------------------------+
datetime s_last_sample_ts  = 0;
double   s_last_vp         = EMPTY_VALUE;
double   s_last_ma_start   = EMPTY_VALUE;
double   s_last_ma_ref     = EMPTY_VALUE;
double   s_last_vp_livre   = EMPTY_VALUE;

//+------------------------------------------------------------------+
//| VP Livre -- janela em candles M30 (2 candles = 1 hora)            |
//+------------------------------------------------------------------+
int    s_vp_livre_window = 0;
double s_vp_livre_alpha  = 0.0;   // 0.0 = sem suavizacao

//+------------------------------------------------------------------+
//| Recalculo forcado + flag de reset por REASON_PARAMETERS et al     |
//+------------------------------------------------------------------+
bool     g_hadGaps            = false;
datetime g_lastFullRecalcTime = 0;
#define  RECALC_THROTTLE_SEC  5

bool     s_need_full_reset = true;   // primeira carga forca full recalc
bool     g_chart_is_m30    = false;  // setado em OnInit, otimizacao shift M30
int      g_subwin_idx      = -1;     // setado em _CreateRefLinesInSubwin

//+------------------------------------------------------------------+
//| Helpers numericos -- identicos ao indicador M5 (pipeline VP v2)   |
//+------------------------------------------------------------------+
void _PctChange(const double &in[], double &out[], const int n)
{
   ArrayResize(out, n, n);
   if(n <= 0) return;
   out[0] = VP_INVALID;
   for(int i = 1; i < n; i++)
   {
      double p0 = in[i-1];
      double p1 = in[i];
      if(p0 == 0.0 || p0 == VP_INVALID || p1 == VP_INVALID)
         out[i] = VP_INVALID;
      else
         out[i] = p1 / p0 - 1.0;
   }
}

double _Quantile(const double &in[], const int n_in, const double q)
{
   if(n_in <= 0) return VP_INVALID;
   double tmp[]; ArrayResize(tmp, n_in, n_in);
   int n = 0;
   for(int i = 0; i < n_in; i++)
   {
      if(in[i] == VP_INVALID) continue;
      tmp[n++] = in[i];
   }
   if(n < 2) return VP_INVALID;
   ArrayResize(tmp, n, n);
   ArraySort(tmp);

   double idx = q * (double)(n - 1);
   int lo = (int)MathFloor(idx);
   int hi = (int)MathCeil(idx);
   if(lo < 0)  lo = 0;
   if(hi >= n) hi = n - 1;
   if(lo == hi) return tmp[lo];
   double frac = idx - (double)lo;
   return tmp[lo] + frac * (tmp[hi] - tmp[lo]);
}

void _Winsor(const double &in[], double &out[], const int n,
             const double qlow, const double qhigh, const int n_min)
{
   ArrayResize(out, n, n);
   if(n < n_min)
   {
      for(int i = 0; i < n; i++) out[i] = in[i];
      return;
   }
   double q_lo = _Quantile(in, n, qlow);
   double q_hi = _Quantile(in, n, qhigh);
   if(q_lo == VP_INVALID || q_hi == VP_INVALID)
   {
      for(int i = 0; i < n; i++) out[i] = in[i];
      return;
   }
   for(int i = 0; i < n; i++)
   {
      if(in[i] == VP_INVALID) { out[i] = VP_INVALID; continue; }
      out[i] = MathMax(q_lo, MathMin(q_hi, in[i]));
   }
}

// Winsor condicional (toggle InpWinsor via s_winsor). OFF = copia crua.
void _MaybeWinsor(const double &in[], double &out[], const int n, const int n_min)
{
   if(s_winsor)
   {
      _Winsor(in, out, n, kWinsor_Lower, kWinsor_Upper, n_min);
      return;
   }
   ArrayResize(out, n, n);
   for(int i = 0; i < n; i++) out[i] = in[i];
}

double _StdSample(const double &in[], const int n_in)
{
   if(n_in <= 0) return VP_INVALID;
   double sum = 0.0; int count = 0;
   for(int i = 0; i < n_in; i++)
   {
      if(in[i] == VP_INVALID) continue;
      sum += in[i];
      count++;
   }
   if(count < 2) return VP_INVALID;

   double mean = sum / (double)count;
   double ss = 0.0;
   for(int i = 0; i < n_in; i++)
   {
      if(in[i] == VP_INVALID) continue;
      double d = in[i] - mean;
      ss += d * d;
   }
   double var = ss / (double)(count - 1);
   if(var < 0.0) var = 0.0;
   return MathSqrt(var);
}

double _EwmaSigmaVar0(const double &returns[], const int n, const double lambda)
{
   if(n < 1) return VP_INVALID;
   double var = 0.0;
   for(int i = 0; i < n; i++)
   {
      if(returns[i] == VP_INVALID) continue;
      double r = returns[i];
      var = lambda * var + (1.0 - lambda) * r * r;
   }
   if(var < 0.0) var = 0.0;
   return MathSqrt(var);
}

//+------------------------------------------------------------------+
//| Resets                                                             |
//+------------------------------------------------------------------+
void _ResetCaches()
{
   g_cache_w1_key     = 0;
   g_cache_sigma_hist = VP_INVALID;
}

void _ResetLastSampleStatics()
{
   s_last_sample_ts = 0;
   s_last_vp        = EMPTY_VALUE;
   s_last_ma_start  = EMPTY_VALUE;
   s_last_ma_ref    = EMPTY_VALUE;
   s_last_vp_livre  = EMPTY_VALUE;
}

//+------------------------------------------------------------------+
//| Validacao admin (espelha M5: apenas paralelas).                   |
//+------------------------------------------------------------------+
bool _ApplyAdminRules()
{
   s_ma_start_eff = InpMA_Start_Period;
   s_ma_ref_eff   = InpMA_Ref_Period;

   if(s_ma_start_eff > 0 && s_ma_start_eff < 2)
      PrintFormat("[ZTMAVP_SW] R4 MA Start=%d < 2 (valor atipico)", s_ma_start_eff);
   if(s_ma_ref_eff > 0 && s_ma_ref_eff < 2)
      PrintFormat("[ZTMAVP_SW] R4 MA Ref=%d < 2 (valor atipico)", s_ma_ref_eff);

   if(s_ma_start_eff > 0 && s_ma_ref_eff > 0
      && s_ma_start_eff >= s_ma_ref_eff)
      PrintFormat("[ZTMAVP_SW] R5 paralelas: Start=%d >= Ref=%d (gate em BLOCK esperado)",
                  s_ma_start_eff, s_ma_ref_eff);

   const bool any_active = (s_ma_start_eff > 0 || s_ma_ref_eff > 0);
   if(!any_active)
      Print("[ZTMAVP_SW] R6: nenhum slot MA ativo");

   return any_active;
}

int _GetMAStartPeriod() { return s_ma_start_eff; }
int _GetMARefPeriod()   { return s_ma_ref_eff;   }

//+------------------------------------------------------------------+
//| _GetCurrentPrice -- midprice live na vela corrente.               |
//+------------------------------------------------------------------+
double _GetCurrentPrice(const double fallback)
{
   MqlTick tk;
   if(!SymbolInfoTick(_Symbol, tk)) return fallback;

   if(tk.bid > 0.0 && tk.ask > 0.0) return (tk.bid + tk.ask) / 2.0;
   if(tk.last > 0.0)                return tk.last;
   if(tk.bid > 0.0)                 return tk.bid;
   if(tk.ask > 0.0)                 return tk.ask;
   return fallback;
}

//+------------------------------------------------------------------+
//| OBJ_HLINE de referencia (sigmas -8 a +8)                          |
//+------------------------------------------------------------------+
void _CreateRefLinesInSubwin(const int subwin)
{
   g_subwin_idx = subwin;

   for(int i = 0; i < ZTMAVPSW_REF_COUNT; i++)
   {
      const string name  = StringFormat("%s%d_%d", ZTMAVPSW_REF_PREFIX_BASE, subwin, i);
      const double level = (double)(i - 8);   // i=0 -> -8 ; i=16 -> +8

      if(ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_HLINE, subwin, 0, level);
      ObjectSetDouble (0, name, OBJPROP_PRICE, level);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrSilver);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
}

void _DeleteRefLines()
{
   if(g_subwin_idx < 0) return;
   for(int i = 0; i < ZTMAVPSW_REF_COUNT; i++)
      ObjectDelete(0,
         StringFormat("%s%d_%d", ZTMAVPSW_REF_PREFIX_BASE, g_subwin_idx, i));
}

//+------------------------------------------------------------------+
//| OnInit                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   const int reason_prev = UninitializeReason();
   s_need_full_reset = (reason_prev == REASON_PARAMETERS
                     || reason_prev == REASON_RECOMPILE
                     || reason_prev == REASON_CHARTCHANGE
                     || reason_prev == 0);

   if(s_need_full_reset)
   {
      _ResetCaches();
      _ResetLastSampleStatics();
      g_hadGaps            = true;
      g_lastFullRecalcTime = 0;
   }

   g_chart_is_m30 = (_Period == PERIOD_M30);
   if(!g_chart_is_m30)
      Print("[ZTMAVP_SW] AVISO: indicador desenhado para o grafico M30 -- TF atual difere de M30");

   SetIndexBuffer(0, BufVP,        INDICATOR_DATA);
   SetIndexBuffer(1, BufMA_Start,  INDICATOR_DATA);
   SetIndexBuffer(2, BufMA_Ref,    INDICATOR_DATA);
   SetIndexBuffer(3, BufVP_Livre,  INDICATOR_DATA);

   for(int i = 0; i < 4; i++)
      PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   if(!_ApplyAdminRules())
      Print("[ZTMAVP_SW] WARN: nenhuma MA ativa -- indicador nao plotara MA Start/Ref");

   // Flip de ativo -> janela swing 7d em M30 (OURO 230 / BITCOIN 336)
   const bool is_btc = (InpAtivo == ATIVO_BITCOIN);
   s_swing_window = is_btc ? kM30_Bitcoin : kM30_Ouro;
   // W1 sigma_hist (2 anos) = 105 nos dois ativos (semanal calendar-based, sem flip)
   s_w_ewma_bars  = kW1_2anos;

   // Perfil de risco -> lambda EWMA / alpha hibrido (NIX)
   switch(InpPerfil)
   {
      case PERFIL_CONSERVADOR: s_lambda = 0.96; s_alpha = 0.80; break;
      case PERFIL_MODERADO:    s_lambda = 0.94; s_alpha = 0.70; break;
      case PERFIL_ULTRA:       s_lambda = 0.90; s_alpha = 0.45; break;
      case PERFIL_AGRESSIVO:
      default:                 s_lambda = 0.92; s_alpha = 0.55; break;
   }

   // Toggle winsor
   s_winsor = InpWinsor;

   // VP Livre -- janela em candles M30 (2 = 1h)
   if(InpVP_Livre_Hours > 720)
      PrintFormat("[ZTMAVP_SW] WARN VP_Livre_Hours=%d > 720 -- forcado para 720", InpVP_Livre_Hours);
   const int vp_h = (int)MathMax(0, MathMin(720, InpVP_Livre_Hours));
   s_vp_livre_window = (vp_h > 0) ? vp_h * 2 : 0;

   const int smooth = (int)MathMax(0, InpVP_Livre_Smooth);
   if(smooth > 0 && smooth < 2)
      PrintFormat("[ZTMAVP_SW] WARN VP_Livre_Smooth=%d < 2 (periodo EMA atipico)", smooth);
   s_vp_livre_alpha = (smooth > 0) ? 2.0 / ((double)smooth + 1.0) : 0.0;

   const bool show_start = InpShow_Lines && (_GetMAStartPeriod() > 0);
   const bool show_ref   = InpShow_Lines && (_GetMARefPeriod()   > 0);
   const bool show_vpl   = InpShow_Lines && (s_vp_livre_window   > 0);

   PlotIndexSetInteger(1, PLOT_DRAW_TYPE, (show_start ? DRAW_LINE : DRAW_NONE));
   PlotIndexSetInteger(2, PLOT_DRAW_TYPE, (show_ref   ? DRAW_LINE : DRAW_NONE));
   PlotIndexSetInteger(3, PLOT_DRAW_TYPE, (show_vpl   ? DRAW_LINE : DRAW_NONE));

   const string ativo_str  = (InpAtivo == ATIVO_BITCOIN) ? "BTC" : "OURO";
   const string perfil_str = (InpPerfil == PERFIL_CONSERVADOR) ? "CON"
                           : (InpPerfil == PERFIL_MODERADO)    ? "MOD"
                           : (InpPerfil == PERFIL_ULTRA)       ? "ULT" : "AGR";

   IndicatorSetInteger(INDICATOR_DIGITS, 4);
   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("ZT_MA_VP_SW M30 [%s %s%s %d/%d m30=%d W%d]",
                   ativo_str, perfil_str, (s_winsor ? "+w" : ""),
                   _GetMAStartPeriod(), _GetMARefPeriod(), s_swing_window, s_w_ewma_bars));

   PrintFormat("[ZTMAVP_SW] v1.2 | ativo=%s perfil=%s(L%.2f/A%.2f) winsor=%s | M30_7d=%d W1_2a=%d | MA %d/%d | VP_Livre=%dh s%d",
               ativo_str, perfil_str, s_lambda, s_alpha, (s_winsor ? "ON" : "OFF"),
               s_swing_window, s_w_ewma_bars,
               _GetMAStartPeriod(), _GetMARefPeriod(), vp_h, smooth);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(reason == REASON_REMOVE
      || reason == REASON_PROGRAM
      || reason == REASON_CLOSE)
   {
      _DeleteRefLines();
   }
}

//+------------------------------------------------------------------+
//| sigma_hist as-of timestamp t (cache por semana W1)                 |
//| EWMA RiskMetrics sobre retornos W1 winsorizados.                   |
//+------------------------------------------------------------------+
double _SigmaHistAsOf(const datetime t)
{
   const int shift_w1 = iBarShift(_Symbol, PERIOD_W1, t, false);
   if(shift_w1 < 0) return VP_INVALID;

   const datetime w1_key = (datetime)iTime(_Symbol, PERIOD_W1, shift_w1);
   if(w1_key <= 0) return VP_INVALID;

   if(w1_key == g_cache_w1_key && g_cache_sigma_hist != VP_INVALID)
      return g_cache_sigma_hist;

   MqlRates rates_w1[];
   const int copied = CopyRates(_Symbol, PERIOD_W1, shift_w1, s_w_ewma_bars, rates_w1);
   if(copied < VP_NMIN_W + 2) return VP_INVALID;

   const int n_w1 = copied - 1;   // exclui a W1 que contem t (pattern v2 Portal)
   if(n_w1 < VP_NMIN_W) return VP_INVALID;

   double closes_w1[];
   ArrayResize(closes_w1, n_w1, n_w1);
   for(int i = 0; i < n_w1; i++)
      closes_w1[i] = rates_w1[i].close;

   double rets_w1[];
   _PctChange(closes_w1, rets_w1, n_w1);

   double rets_w1_w[];
   _MaybeWinsor(rets_w1, rets_w1_w, n_w1, VP_NMIN_W);

   const double sigma = _EwmaSigmaVar0(rets_w1_w, n_w1, s_lambda);
   if(sigma == VP_INVALID || sigma <= 0.0) return VP_INVALID;

   g_cache_w1_key     = w1_key;
   g_cache_sigma_hist = sigma;
   return sigma;
}

//+------------------------------------------------------------------+
//| n_sigma swing as-of timestamp t. SEM cache M30 (recalcula sempre).|
//| ret_7d = price_now / close[7d atras] - 1 ; n_sigma = ret_7d/sigma |
//+------------------------------------------------------------------+
double _NSigmaSwingAsOf(const datetime t, const double sigma_hist,
                        const bool is_current_bar, const int shift_m30_hint,
                        double &out_sigma_final, double &out_price_now)
{
   out_sigma_final = VP_INVALID;
   out_price_now   = 0.0;
   if(sigma_hist == VP_INVALID || sigma_hist <= 0.0) return VP_INVALID;

   const int shift_m30 = (shift_m30_hint >= 0) ? shift_m30_hint
                                               : iBarShift(_Symbol, PERIOD_M30, t, false);
   if(shift_m30 < 0) return VP_INVALID;

   MqlRates rates_m30[];
   const int copied = CopyRates(_Symbol, PERIOD_M30, shift_m30, s_swing_window, rates_m30);
   if(copied < VP_NMIN_M30) return VP_INVALID;

   const int n_m30 = copied;
   double closes_m30[];
   ArrayResize(closes_m30, n_m30, n_m30);
   for(int i = 0; i < n_m30; i++)
      closes_m30[i] = rates_m30[i].close;

   double rets_m30[];
   _PctChange(closes_m30, rets_m30, n_m30);

   double rets_m30_w[];
   _MaybeWinsor(rets_m30, rets_m30_w, n_m30, VP_NMIN_M30);

   // sigma_real = std bruto dos retornos M30 (winsor opcional; sem anualizacao -- paridade VP v2)
   const double sigma_real = _StdSample(rets_m30_w, n_m30);
   if(sigma_real == VP_INVALID || sigma_real <= 0.0) return VP_INVALID;

   const double sigma_final = s_alpha * sigma_hist
                            + (1.0 - s_alpha) * sigma_real;
   if(sigma_final < VP_EPS) return VP_INVALID;

   const double close_now = closes_m30[n_m30 - 1];
   const double price_now = is_current_bar ? _GetCurrentPrice(close_now) : close_now;

   const double price_7d_ago = closes_m30[0];   // s_swing_window barras atras ~ 7 dias
   if(price_now <= 0.0 || price_7d_ago <= 0.0) return VP_INVALID;

   const double ret_7d  = price_now / price_7d_ago - 1.0;
   const double n_sigma = ret_7d / sigma_final;

   out_sigma_final = sigma_final;
   out_price_now   = price_now;
   return n_sigma;
}

//+------------------------------------------------------------------+
//| OnCalculate                                                        |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total <= 0) return 0;

   //--- Criacao retardada das OBJ_HLINE ---
   static bool s_refs_created = false;
   if(!s_refs_created)
   {
      const int subwin = ChartWindowFind();
      if(subwin >= 0)
      {
         _CreateRefLinesInSubwin(subwin);
         s_refs_created = true;
         ChartRedraw();
      }
   }

   //--- Gate MTF: dados insuficientes -> preserva o que ja foi calculado ---
   const int bars_w1  = iBars(_Symbol, PERIOD_W1);
   const int bars_m30 = iBars(_Symbol, PERIOD_M30);
   if(bars_w1 < (VP_NMIN_W + 2) || bars_m30 < s_swing_window)
      return prev_calculated;

   //--- s_need_full_reset (REASON_PARAMETERS/RECOMPILE/CHARTCHANGE) ---
   int  start;
   bool forceFullRecalc = false;

   if(s_need_full_reset)
   {
      forceFullRecalc      = true;
      s_need_full_reset    = false;
      g_lastFullRecalcTime = TimeLocal();
   }
   else if(g_hadGaps && prev_calculated > 0)
   {
      const datetime now_l = TimeLocal();
      if(now_l - g_lastFullRecalcTime >= RECALC_THROTTLE_SEC)
      {
         forceFullRecalc      = true;
         g_lastFullRecalcTime = now_l;
      }
   }

   if(prev_calculated <= 0 || forceFullRecalc)
   {
      ArrayInitialize(BufVP,        EMPTY_VALUE);
      ArrayInitialize(BufMA_Start,  EMPTY_VALUE);
      ArrayInitialize(BufMA_Ref,    EMPTY_VALUE);
      ArrayInitialize(BufVP_Livre,  EMPTY_VALUE);
      _ResetCaches();
      _ResetLastSampleStatics();
      start = 0;
      g_hadGaps = false;
   }
   else
   {
      start = prev_calculated - 1;
      if(start < 0) start = 0;
   }

   //--- Snapshot da config ---
   const int  ms_per          = _GetMAStartPeriod();
   const int  mr_per          = _GetMARefPeriod();
   const bool lines_active    = InpShow_Lines && (ms_per > 0 || mr_per > 0);
   const int  vp_w            = s_vp_livre_window;
   const bool vp_livre_active = InpShow_Lines && (vp_w > 0);

   const double a_s = (ms_per > 0) ? 2.0 / ((double)ms_per + 1.0) : 0.0;
   const double a_r = (mr_per > 0) ? 2.0 / ((double)mr_per + 1.0) : 0.0;

   const bool can_use_arith_shift = g_chart_is_m30 && (bars_m30 == rates_total);

   const int hot_start = (rates_total > s_swing_window)
                          ? rates_total - s_swing_window : 0;

   bool hadGapsThisPass = false;

   for(int i = start; i < rates_total; i++)
   {
      const bool     is_current_bar = (i == rates_total - 1);
      const datetime t              = time[i];

      //--- Gate de cadencia na vela corrente: entre amostras, reusa s_last_* ---
      if(is_current_bar && s_last_sample_ts != 0
         && (TimeCurrent() - s_last_sample_ts) < (datetime)kSampleIntervalSec)
      {
         BufVP[i] = s_last_vp;
         if(lines_active)
         {
            BufMA_Start[i] = s_last_ma_start;
            BufMA_Ref[i]   = s_last_ma_ref;
         }
         if(vp_livre_active) BufVP_Livre[i] = s_last_vp_livre;
         continue;
      }

      const int shift_m30 = can_use_arith_shift ? (rates_total - 1 - i) : -1;

      const double sigma_hist = _SigmaHistAsOf(t);
      if(sigma_hist == VP_INVALID)
      {
         BufVP[i] = EMPTY_VALUE;
         if(lines_active)    { BufMA_Start[i] = EMPTY_VALUE; BufMA_Ref[i] = EMPTY_VALUE; }
         if(vp_livre_active) BufVP_Livre[i] = EMPTY_VALUE;
         if(i >= hot_start) hadGapsThisPass = true;
         continue;
      }

      double sigma_final = VP_INVALID;
      double price_now   = 0.0;
      const double n_sigma = _NSigmaSwingAsOf(t, sigma_hist, is_current_bar, shift_m30,
                                              sigma_final, price_now);
      if(n_sigma == VP_INVALID)
      {
         BufVP[i] = EMPTY_VALUE;
         if(lines_active)    { BufMA_Start[i] = EMPTY_VALUE; BufMA_Ref[i] = EMPTY_VALUE; }
         if(vp_livre_active) BufVP_Livre[i] = EMPTY_VALUE;
         if(i >= hot_start) hadGapsThisPass = true;
         continue;
      }

      BufVP[i] = n_sigma;

      //--- VP Livre -- janela em horas (M30: 2 candles = 1h) ---
      if(vp_livre_active)
      {
         double vp_raw = EMPTY_VALUE;
         if(i >= vp_w && sigma_final > VP_EPS)
         {
            const double price_ago = close[i - vp_w];
            if(price_ago > 0.0)
               vp_raw = ((price_now / price_ago) - 1.0) / sigma_final;
         }

         if(vp_raw == EMPTY_VALUE)
            BufVP_Livre[i] = EMPTY_VALUE;
         else if(s_vp_livre_alpha > 0.0
                 && i > 0 && BufVP_Livre[i - 1] != EMPTY_VALUE)
            BufVP_Livre[i] = s_vp_livre_alpha * vp_raw
                            + (1.0 - s_vp_livre_alpha) * BufVP_Livre[i - 1];
         else
            BufVP_Livre[i] = vp_raw;
      }

      //--- MAs (EMAs paralelas sobre n_sigma swing) ---
      if(lines_active)
      {
         if(ms_per > 0)
         {
            if(i == 0 || BufMA_Start[i-1] == EMPTY_VALUE)
               BufMA_Start[i] = n_sigma;
            else
               BufMA_Start[i] = a_s * n_sigma + (1.0 - a_s) * BufMA_Start[i-1];
         }
         else
            BufMA_Start[i] = EMPTY_VALUE;

         if(mr_per > 0)
         {
            if(i == 0 || BufMA_Ref[i-1] == EMPTY_VALUE)
               BufMA_Ref[i] = n_sigma;
            else
               BufMA_Ref[i] = a_r * n_sigma + (1.0 - a_r) * BufMA_Ref[i-1];
         }
         else
            BufMA_Ref[i] = EMPTY_VALUE;
      }

      if(is_current_bar)
      {
         s_last_vp        = BufVP[i];
         s_last_ma_start  = lines_active    ? BufMA_Start[i] : EMPTY_VALUE;
         s_last_ma_ref    = lines_active    ? BufMA_Ref[i]   : EMPTY_VALUE;
         s_last_vp_livre  = vp_livre_active ? BufVP_Livre[i] : EMPTY_VALUE;
         s_last_sample_ts = TimeCurrent();
      }
   }

   g_hadGaps = hadGapsThisPass;
   return rates_total;
}
//+------------------------------------------------------------------+
