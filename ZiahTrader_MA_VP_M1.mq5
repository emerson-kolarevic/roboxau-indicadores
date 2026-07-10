//+------------------------------------------------------------------+
//|                                        ZiahTrader_MA_VP_M1.mq5    |
//|              Indicador MA VP EXECUCAO (M1) -- v1.0                |
//|                                                                  |
//| 3o tier da familia MA VP (M5 daytrade / M30 swing / M1 execucao). |
//| Espelha a MESMA metodologia do pipeline VP v2 (perfis lambda/     |
//| alpha, winsor 0.005/0.995, sem anualizacao, sem clip), escalada   |
//| UM TIER ABAIXO do daytrade, para execucao/micro-timing:           |
//|                                                                  |
//|   DAYTRADE (M5)            ->  EXECUCAO (M1)                      |
//|   sigma_hist: EWMA D1      ->  EWMA H1 (horario, 8 pregoes)       |
//|   sigma_real: std M5 (24h) ->  std M1 (1 hora)                    |
//|   retorno:    ret_24h      ->  ret_1h                             |
//|   n_sigma = ret_1h / sigma_final_horario                          |
//|                                                                  |
//| Plota, em janela separada: VP instantaneo (execucao) + MA Start   |
//| + MA Ref (EMAs paralelas sobre n_sigma) + VP Livre opcional.      |
//| 17 OBJ_HLINE de referencia (-8..+8 sigma).                        |
//|                                                                  |
//| >>> CONTAGEM DE CANDLES (regra #1 Emerson, medida pelo terminal   |
//| via ZT_DiagContagemCandles v1.1, 2026-07-09, Exness-MT5Trial11):  |
//| H1 sigma_hist (8 pregoes) = XAU 184 (8 x 23 H1/pregao CHEIO) |    |
//| BTC 192 (8 x 24, medido exato). M1 em 1h = 60 nos DOIS ativos     |
//| (XAU mediu 59.9 -- horas cheias de M1; flip nao atua aqui).       |
//| NOTA: a media da semana medida em 2026-07-09 (18.5 H1/pregao)     |
//| estava distorcida pelo feriado de 4 de julho + domingo parcial;   |
//| o criterio e o pregao CHEIO (23 H1 = 276 M5 / 12), o mesmo com    |
//| que o 276 do daytrade foi cadastrado.                             |
//|                                                                  |
//| Ruido esperado: com ~60 amostras M1, o sigma_real e mais nervoso  |
//| que nos tiers irmaos (276/230 amostras) e o winsor e quase        |
//| inerte no lado M1 (0.005*60 nao apara nada) -- a protecao contra  |
//| outlier vem do lado H1. Comportamento aceito p/ sensor de         |
//| execucao (decisao Emerson 2026-07-09).                            |
//|                                                                  |
//| PRICE NOW na vela corrente: midprice live via SymbolInfoTick.     |
//| Barras historicas usam o close M1. Gate de cadencia 60s (M1).     |
//|                                                                  |
//| Papel operacional (camada futura): M30 + M5 dao o corredor        |
//| (convergencia); o M1 navega o corredor buscando micro pullbacks.  |
//| Nesta versao: validacao VISUAL apenas.                            |
//|                                                                  |
//| Standalone -- nao depende de nenhum modulo do EA. Para rodar no   |
//| GRAFICO M1. Calibragem unica (sem COMPRA/VENDA).                  |
//+------------------------------------------------------------------+
#property copyright   "Ziah Trader"
#property link        "https://ziahtrader.com"
#property version     "1.00"
#property description "MA VP EXECUCAO (M1): VP (n_sigma 1h / vol horaria) + MA Start + MA Ref + VP Livre"
#property description "Espelha o pipeline VP v2, escalado p/ execucao (H1 8 pregoes + M1 + ret_1h)"
#property description "v1.0: flip de ativo OURO/BITCOIN (H1 184/192) + perfil de risco + winsor toggle. Rodar no M1"

#property indicator_separate_window
#property indicator_buffers 4
#property indicator_plots   4

//---- Plot 0: VP instantaneo execucao (cinza pontilhado)
#property indicator_label1  "VP_M1"
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
//| Neste tier o flip atua SO no sigma_hist H1 (8 pregoes):           |
//|   H1 8 pregoes : BTC=192 (8x24, 24/7) | XAU=184 (8x23, pregao     |
//|                  cheio de 23h)                                     |
//| Janela M1 de 1h = 60 nos DOIS ativos (medido 59.9/60.0) -> fixa.  |
//| Contagens medidas pelo terminal (ZT_DiagContagemCandles 2026-07-09).|
//+------------------------------------------------------------------+
enum ZT_Ativo
{
   ATIVO_OURO     = 0,   // OURO (XAU) -- com gaps (H1 8 pregoes=184)
   ATIVO_BITCOIN  = 1    // BITCOIN -- 24h/7d sem gaps (H1 8 pregoes=192)
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
//| Defaults canonicos (Emerson 2026-07-09): tier M1 usa MA 4/10      |
//| (mais curtas que o 6/18 dos tiers M5/M30 -- sensor de execucao);  |
//| VP Livre off (0/0).                                                |
//+------------------------------------------------------------------+
input group "=== Calibragem MA VP Execucao (M1) ==="
input ZT_Ativo  InpAtivo      = ATIVO_OURO;       // Ativo: OURO (gaps) / BITCOIN (24h7d)
input ZT_Perfil InpPerfil     = PERFIL_AGRESSIVO; // Perfil de risco (lambda/alpha)
input bool InpWinsor          = true;   // Winsor (apara outliers de gap/spike no sigma)
input int  InpMA_Start_Period = 4;      // MA Start: periodo EMA sobre n_sigma execucao (0=off)
input int  InpMA_Ref_Period   = 10;     // MA Ref: periodo EMA sobre n_sigma execucao (0=off)
input int  InpVP_Livre_Hours  = 0;      // VP Livre: janela em horas (0=off) -- M1: 60 candles/h
input int  InpVP_Livre_Smooth = 0;      // VP Livre: suavizacao EMA (0=off)
input bool InpShow_Lines      = true;   // Exibir linhas

//+------------------------------------------------------------------+
//| Constantes internas (espelham pipeline VP v2 -- iguais aos irmaos)|
//+------------------------------------------------------------------+
const int    kH1_Ouro           = 184;      // H1 em 8 pregoes no OURO (8 x 23 H1/pregao cheio)
const int    kH1_Bitcoin        = 192;      // H1 em 8 pregoes no BITCOIN (8 x 24, 24/7)
const int    kM1_1h             = 60;       // janela 1h em M1 -- IGUAL nos 2 ativos (medido)
const double kWinsor_Lower      = 0.005;    // quantil inferior winsor
const double kWinsor_Upper      = 0.995;    // quantil superior winsor
const int    kSampleIntervalSec = 60;       // gate de cadencia na vela corrente (M1 = 1min)

#define VP_NMIN_H1   30          // minimo de retornos H1 para EWMA horario
#define VP_NMIN_M1   50          // minimo de retornos M1 winsorizados (1h)
#define VP_INVALID   DBL_MAX     // sentinel de valor invalido
#define VP_EPS       1e-12       // piso numerico para sigma_final

//+------------------------------------------------------------------+
//| OBJ_HLINE de referencia (-8 a +8 sigma). Prefixo proprio do M1    |
//| (nao colide com os indicadores M5/M30 no mesmo chart).            |
//+------------------------------------------------------------------+
#define ZTMAVPM1_REF_PREFIX_BASE "ZTMAVPM1_REF_W"
#define ZTMAVPM1_REF_COUNT       17      // -8..+8 sigma (inclusivo)

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
int    s_exec_window  = 0;   // janela M1 (1h) efetiva (kM1_1h -- sem flip)
int    s_h1_ewma_bars = 0;   // barras H1 para sigma_hist horario (setada pelo InpAtivo)
double s_lambda       = 0.92;// lambda EWMA efetivo (setado pelo InpPerfil)
double s_alpha        = 0.55;// alpha hibrido efetivo (setado pelo InpPerfil)
bool   s_winsor       = true;// aplica winsor? (setado pelo InpWinsor)

//+------------------------------------------------------------------+
//| Cache H1 (sigma_hist por hora H1)                                  |
//+------------------------------------------------------------------+
datetime g_cache_h1_key      = 0;
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
//| VP Livre -- janela em candles M1 (60 candles = 1 hora)            |
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
bool     g_chart_is_m1     = false;  // setado em OnInit, otimizacao shift M1
int      g_subwin_idx      = -1;     // setado em _CreateRefLinesInSubwin

//+------------------------------------------------------------------+
//| Helpers numericos -- identicos aos indicadores M5/M30 (VP v2)     |
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
   g_cache_h1_key     = 0;
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
//| Validacao admin (espelha M5/M30: apenas paralelas).               |
//+------------------------------------------------------------------+
bool _ApplyAdminRules()
{
   s_ma_start_eff = InpMA_Start_Period;
   s_ma_ref_eff   = InpMA_Ref_Period;

   if(s_ma_start_eff > 0 && s_ma_start_eff < 2)
      PrintFormat("[ZTMAVP_M1] R4 MA Start=%d < 2 (valor atipico)", s_ma_start_eff);
   if(s_ma_ref_eff > 0 && s_ma_ref_eff < 2)
      PrintFormat("[ZTMAVP_M1] R4 MA Ref=%d < 2 (valor atipico)", s_ma_ref_eff);

   if(s_ma_start_eff > 0 && s_ma_ref_eff > 0
      && s_ma_start_eff >= s_ma_ref_eff)
      PrintFormat("[ZTMAVP_M1] R5 paralelas: Start=%d >= Ref=%d (gate em BLOCK esperado)",
                  s_ma_start_eff, s_ma_ref_eff);

   const bool any_active = (s_ma_start_eff > 0 || s_ma_ref_eff > 0);
   if(!any_active)
      Print("[ZTMAVP_M1] R6: nenhum slot MA ativo");

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

   for(int i = 0; i < ZTMAVPM1_REF_COUNT; i++)
   {
      const string name  = StringFormat("%s%d_%d", ZTMAVPM1_REF_PREFIX_BASE, subwin, i);
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
   for(int i = 0; i < ZTMAVPM1_REF_COUNT; i++)
      ObjectDelete(0,
         StringFormat("%s%d_%d", ZTMAVPM1_REF_PREFIX_BASE, g_subwin_idx, i));
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

   g_chart_is_m1 = (_Period == PERIOD_M1);
   if(!g_chart_is_m1)
      Print("[ZTMAVP_M1] AVISO: indicador desenhado para o grafico M1 -- TF atual difere de M1");

   SetIndexBuffer(0, BufVP,        INDICATOR_DATA);
   SetIndexBuffer(1, BufMA_Start,  INDICATOR_DATA);
   SetIndexBuffer(2, BufMA_Ref,    INDICATOR_DATA);
   SetIndexBuffer(3, BufVP_Livre,  INDICATOR_DATA);

   for(int i = 0; i < 4; i++)
      PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   if(!_ApplyAdminRules())
      Print("[ZTMAVP_M1] WARN: nenhuma MA ativa -- indicador nao plotara MA Start/Ref");

   // Flip de ativo -> sigma_hist H1 8 pregoes (OURO 184 / BITCOIN 192).
   // Janela M1 de 1h = 60 nos dois ativos (medido) -- sem flip.
   const bool is_btc = (InpAtivo == ATIVO_BITCOIN);
   s_h1_ewma_bars = is_btc ? kH1_Bitcoin : kH1_Ouro;
   s_exec_window  = kM1_1h;

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

   // VP Livre -- janela em candles M1 (60 = 1h)
   if(InpVP_Livre_Hours > 720)
      PrintFormat("[ZTMAVP_M1] WARN VP_Livre_Hours=%d > 720 -- forcado para 720", InpVP_Livre_Hours);
   const int vp_h = (int)MathMax(0, MathMin(720, InpVP_Livre_Hours));
   s_vp_livre_window = (vp_h > 0) ? vp_h * 60 : 0;

   const int smooth = (int)MathMax(0, InpVP_Livre_Smooth);
   if(smooth > 0 && smooth < 2)
      PrintFormat("[ZTMAVP_M1] WARN VP_Livre_Smooth=%d < 2 (periodo EMA atipico)", smooth);
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
      StringFormat("ZT_MA_VP_M1 v1.0 [%s %s%s %d/%d m1=%d H1=%d]",
                   ativo_str, perfil_str, (s_winsor ? "+w" : ""),
                   _GetMAStartPeriod(), _GetMARefPeriod(), s_exec_window, s_h1_ewma_bars));

   PrintFormat("[ZTMAVP_M1] v1.0 | ativo=%s perfil=%s(L%.2f/A%.2f) winsor=%s | M1_1h=%d H1_8preg=%d | MA %d/%d | VP_Livre=%dh s%d",
               ativo_str, perfil_str, s_lambda, s_alpha, (s_winsor ? "ON" : "OFF"),
               s_exec_window, s_h1_ewma_bars,
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
//| sigma_hist as-of timestamp t (cache por hora H1)                   |
//| EWMA RiskMetrics sobre retornos H1 winsorizados.                   |
//+------------------------------------------------------------------+
double _SigmaHistAsOf(const datetime t)
{
   const int shift_h1 = iBarShift(_Symbol, PERIOD_H1, t, false);
   if(shift_h1 < 0) return VP_INVALID;

   const datetime h1_key = (datetime)iTime(_Symbol, PERIOD_H1, shift_h1);
   if(h1_key <= 0) return VP_INVALID;

   if(h1_key == g_cache_h1_key && g_cache_sigma_hist != VP_INVALID)
      return g_cache_sigma_hist;

   MqlRates rates_h1[];
   const int copied = CopyRates(_Symbol, PERIOD_H1, shift_h1, s_h1_ewma_bars, rates_h1);
   if(copied < VP_NMIN_H1 + 2) return VP_INVALID;

   const int n_h1 = copied - 1;   // exclui a H1 que contem t (pattern v2 Portal)
   if(n_h1 < VP_NMIN_H1) return VP_INVALID;

   double closes_h1[];
   ArrayResize(closes_h1, n_h1, n_h1);
   for(int i = 0; i < n_h1; i++)
      closes_h1[i] = rates_h1[i].close;

   double rets_h1[];
   _PctChange(closes_h1, rets_h1, n_h1);

   double rets_h1_w[];
   _MaybeWinsor(rets_h1, rets_h1_w, n_h1, VP_NMIN_H1);

   const double sigma = _EwmaSigmaVar0(rets_h1_w, n_h1, s_lambda);
   if(sigma == VP_INVALID || sigma <= 0.0) return VP_INVALID;

   g_cache_h1_key     = h1_key;
   g_cache_sigma_hist = sigma;
   return sigma;
}

//+------------------------------------------------------------------+
//| n_sigma execucao as-of timestamp t. SEM cache M1 (recalcula       |
//| sempre). ret_1h = price_now / close[1h atras] - 1 ;               |
//| n_sigma = ret_1h / sigma_final                                     |
//+------------------------------------------------------------------+
double _NSigmaExecAsOf(const datetime t, const double sigma_hist,
                       const bool is_current_bar, const int shift_m1_hint,
                       double &out_sigma_final, double &out_price_now)
{
   out_sigma_final = VP_INVALID;
   out_price_now   = 0.0;
   if(sigma_hist == VP_INVALID || sigma_hist <= 0.0) return VP_INVALID;

   const int shift_m1 = (shift_m1_hint >= 0) ? shift_m1_hint
                                             : iBarShift(_Symbol, PERIOD_M1, t, false);
   if(shift_m1 < 0) return VP_INVALID;

   MqlRates rates_m1[];
   const int copied = CopyRates(_Symbol, PERIOD_M1, shift_m1, s_exec_window, rates_m1);
   if(copied < VP_NMIN_M1) return VP_INVALID;

   const int n_m1 = copied;
   double closes_m1[];
   ArrayResize(closes_m1, n_m1, n_m1);
   for(int i = 0; i < n_m1; i++)
      closes_m1[i] = rates_m1[i].close;

   double rets_m1[];
   _PctChange(closes_m1, rets_m1, n_m1);

   double rets_m1_w[];
   _MaybeWinsor(rets_m1, rets_m1_w, n_m1, VP_NMIN_M1);

   // sigma_real = std bruto dos retornos M1 (winsor opcional; sem anualizacao -- paridade VP v2).
   // Com ~60 amostras o winsor e quase inerte aqui -- protecao vem do lado H1.
   const double sigma_real = _StdSample(rets_m1_w, n_m1);
   if(sigma_real == VP_INVALID || sigma_real <= 0.0) return VP_INVALID;

   const double sigma_final = s_alpha * sigma_hist
                            + (1.0 - s_alpha) * sigma_real;
   if(sigma_final < VP_EPS) return VP_INVALID;

   const double close_now = closes_m1[n_m1 - 1];
   const double price_now = is_current_bar ? _GetCurrentPrice(close_now) : close_now;

   const double price_1h_ago = closes_m1[0];   // s_exec_window barras atras ~ 1 hora
   if(price_now <= 0.0 || price_1h_ago <= 0.0) return VP_INVALID;

   const double ret_1h  = price_now / price_1h_ago - 1.0;
   const double n_sigma = ret_1h / sigma_final;

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
   const int bars_h1 = iBars(_Symbol, PERIOD_H1);
   const int bars_m1 = iBars(_Symbol, PERIOD_M1);
   if(bars_h1 < (VP_NMIN_H1 + 2) || bars_m1 < s_exec_window)
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

   const bool can_use_arith_shift = g_chart_is_m1 && (bars_m1 == rates_total);

   const int hot_start = (rates_total > s_exec_window)
                          ? rates_total - s_exec_window : 0;

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

      const int shift_m1 = can_use_arith_shift ? (rates_total - 1 - i) : -1;

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
      const double n_sigma = _NSigmaExecAsOf(t, sigma_hist, is_current_bar, shift_m1,
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

      //--- VP Livre -- janela em horas (M1: 60 candles = 1h) ---
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

      //--- MAs (EMAs paralelas sobre n_sigma execucao) ---
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
