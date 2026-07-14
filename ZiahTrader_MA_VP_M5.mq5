//+------------------------------------------------------------------+
//|                                       ZiahTrader_MA_VP_M5.mq5    |
//|              Indicador MA VP DAYTRADE (M5) -- v2.6               |
//|                                                                  |
//| Espelha o pipeline VP v2. Plota, em janela separada:             |
//| 1 MA Start + 1 MA Ref (EMAs paralelas sobre n_sigma) + 1 VP      |
//| Livre (VP com janela em horas, suavizacao EMA opcional) + a      |
//| linha VP instantanea. Calibragem unica, sem COMPRA/VENDA.        |
//|                                                                  |
//| v2.5: janelas por ATIVO (D1 312/365 + M5 276/288 via InpAtivo),  |
//| lambda/alpha por PERFIL (InpPerfil), winsor por toggle (InpWinsor)|
//| sobre os quantis kWinsor_*. 17 OBJ_HLINE de referencia (-8 a +8   |
//| sigma) desenhadas em runtime, sempre ativas.                     |
//|                                                                  |
//| v2.6: renomeado ZiahTrader_MA_VP -> ZiahTrader_MA_VP_M5 (familia |
//| de 3 tiers: M5 daytrade / M30 swing / M1 execucao). Defaults     |
//| canonicos (Emerson 2026-07-09): MA 6/18, VP Livre off (0/0).     |
//|                                                                  |
//| v2.7 (F1 parciais em cadeia, 2026-07-13): vela corrente ancora   |
//| no CLOSE do ultimo M1 FECHADO (parcial deterministica: 5         |
//| parciais por barra M5, amostra a cada barra M1 nova). Parcial =  |
//| previa recalculada sobre o estado ancorado -- as EMAs da barra   |
//| corrente ja recalculam sobre BufMA[i-1] fixo; estado so avanca   |
//| no fechamento real. InpParciais_Enable=false restaura o          |
//| comportamento v2.6 (midprice live + gate 300s).                  |
//|                                                                  |
//| PRICE NOW na vela corrente (parciais OFF): midprice live via     |
//| SymbolInfoTick (espelha modulo 20 v2 do EA). Barras historicas   |
//| usam o close M5. Gate de cadencia na vela corrente               |
//| (kSampleIntervalSec): entre amostras reusa os ultimos valores.   |
//|                                                                  |
//| REASON_PARAMETERS / RECOMPILE / CHARTCHANGE forcam full recalc   |
//| no proximo OnCalculate (senao as linhas somem ao trocar          |
//| calibragem). Gate MTF retorna prev_calculated (nao 0) p/ nao     |
//| apagar o ja calculado. OnDeinit so deleta OBJ_HLINE em           |
//| REMOVE/PROGRAM/CLOSE.                                            |
//|                                                                  |
//| Standalone -- nao depende de nenhum modulo do EA.                |
//+------------------------------------------------------------------+
#property copyright   "Ziah Trader"
#property link        "https://ziahtrader.com"
#property version     "2.70"
#property description "MA VP DAYTRADE (M5): VP (n_sigma 24h) + MA Start + MA Ref + VP Livre"
#property description "Calibragem unica universal (sem direcao COMPRA/VENDA)"
#property description "v2.7: PARCIAIS -- vela corrente viva via close do ultimo M1 fechado (5 parciais/barra). Rodar no M5"

#property indicator_separate_window
#property indicator_buffers 4
#property indicator_plots   4

//---- Plot 0: VP instantaneo (cinza pontilhado, opacidade baixa)
#property indicator_label1  "VP"
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

//---- Plot 3: VP Livre (laranja tracejado) -- VP com janela livre em horas
#property indicator_label4  "VP Livre"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrOrange
#property indicator_style4  STYLE_DASH
#property indicator_width4  2

// As 17 linhas horizontais de referencia (-8 a +8 sigma) sao criadas
// em runtime como OBJ_HLINE no _CreateRefLinesInSubwin (chamado pelo
// OnCalculate na primeira passagem com subjanela registrada). Nao usamos
// #property indicator_level porque eles forcam o auto-scale do eixo Y a
// incluir todo o range, comprimindo as MAs em TFs maiores. OBJ_HLINE e
// puramente visual -- nao influencia auto-scale.

//+------------------------------------------------------------------+
//| FLIP DE ATIVO (regra #1: contagem perfeitamente correspondente    |
//| ao ativo). Chave unica que ajusta TODAS as janelas do daytrade:   |
//|   D1 sigma_hist (1 ano)  : BTC=365 (7/sem) | XAU=312 (6/sem, com  |
//|                            domingo parcial)                        |
//|   M5 janela 24h          : BTC=288 (24/7)  | XAU=276 (~23h pregao) |
//| Contagens medidas pelo terminal (ZT_DiagContagemCandles 2026-06-29).|
//+------------------------------------------------------------------+
enum ZT_Ativo
{
   ATIVO_OURO     = 0,   // OURO (XAU) -- com gaps (D1=312/ano, M5=276/24h)
   ATIVO_BITCOIN  = 1    // BITCOIN -- 24h/7d sem gaps (D1=365/ano, M5=288/24h)
};

//+------------------------------------------------------------------+
//| PERFIL DE RISCO (lambda EWMA / alpha hibrido) -- da NIX.          |
//| Agressivo (default): pega o movimento antes (+ falsos positivos). |
//| Conservador: atrasa a entrada (- falsos, + chance de stop tarde). |
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
input group "=== Calibragem MAs VP ==="
input ZT_Ativo  InpAtivo      = ATIVO_OURO;       // Ativo: OURO (gaps) / BITCOIN (24h7d)
input ZT_Perfil InpPerfil     = PERFIL_AGRESSIVO; // Perfil de risco (lambda/alpha)
input bool InpWinsor          = true;   // Winsor (apara outliers de gap/spike no sigma)
input int  InpMA_Start_Period = 6;      // MA Start: periodo (0=off)
input int  InpMA_Ref_Period   = 18;     // MA Referencia: periodo (0=off)
input int  InpVP_Livre_Hours  = 0;      // VP Livre: janela em horas (0=off)
input int  InpVP_Livre_Smooth = 0;      // VP Livre: suavizacao EMA (0=off)
input bool InpShow_Lines      = true;   // Exibir linhas
input bool InpParciais_Enable = true;   // Parciais: vela corrente via close do ultimo M1 fechado

//+------------------------------------------------------------------+
//| Constantes internas (espelham modulo 20 v2 + 28 do EA)            |
//+------------------------------------------------------------------+
const int    kD1_Ouro            = 312;      // D1/ano OURO (6/sem, inclui domingo parcial)
const int    kD1_Bitcoin         = 365;      // D1/ano BITCOIN (7/sem, 24/7)
const double kWinsor_Lower       = 0.005;    // quantil inferior winsor
const double kWinsor_Upper       = 0.995;    // quantil superior winsor
const int    kM5_Win_Ouro        = 276;      // janela M5 24h no OURO (gaps: ~23h pregao/dia)
const int    kM5_Win_Bitcoin     = 288;      // janela M5 24h no BITCOIN (24/7, sem gaps)
const int    kSampleIntervalSec  = 300;      // gate de cadencia na vela corrente

#define VP_NMIN_D1   30          // minimo de retornos D1 para EWMA
#define VP_NMIN_M5   200         // minimo de retornos M5 winsorizados
#define VP_INVALID   DBL_MAX     // sentinel de valor invalido
#define VP_EPS       1e-12       // piso numerico para sigma_final

//+------------------------------------------------------------------+
//| OBJ_HLINE de referencia (sempre ativas, -8 a +8 sigma)            |
//|                                                                    |
//| O prefixo inclui o indice da sub-janela (ex: ZTMAVP_REF_W1_3)     |
//| para suportar 2+ instancias do indicador no mesmo chart sem que   |
//| uma encontre os objetos da outra via ObjectFind e deixe a propria |
//| sub-janela sem HLINEs.                                             |
//+------------------------------------------------------------------+
#define ZTMAVP_REF_PREFIX_BASE "ZTMAVP_REF_W"
#define ZTMAVP_REF_COUNT       17      // -8..+8 sigma (inclusivo)

//+------------------------------------------------------------------+
//| Buffers de plot (4 totais)                                         |
//+------------------------------------------------------------------+
double BufVP[];
double BufMA_Start[];
double BufMA_Ref[];
double BufVP_Livre[];

//+------------------------------------------------------------------+
//| Estado interno -- working copies dos inputs apos validacao R4-R6  |
//+------------------------------------------------------------------+
int  s_ma_start_eff = 0;
int  s_ma_ref_eff   = 0;
int    s_m5_window  = 288;   // janela M5 24h efetiva (setada em OnInit pelo InpAtivo)
int    s_d1_ewma    = 365;   // barras D1 do sigma_hist (setada pelo InpAtivo)
double s_lambda     = 0.92;  // lambda EWMA efetivo (setado pelo InpPerfil)
double s_alpha      = 0.55;  // alpha hibrido efetivo (setado pelo InpPerfil)
bool   s_winsor     = true;  // aplica winsor? (setado pelo InpWinsor)

//+------------------------------------------------------------------+
//| Cache D1 (sigma_hist por dia D1).                                  |
//| Nao causa divergencia EA vs indicador.                             |
//+------------------------------------------------------------------+
datetime g_cache_d1_key      = 0;
double   g_cache_sigma_hist  = VP_INVALID;

//+------------------------------------------------------------------+
//| Gate 300s na vela corrente + statics dos ultimos valores           |
//+------------------------------------------------------------------+
datetime s_last_sample_ts  = 0;
datetime s_last_lowtf_bar  = 0;   // barra M1 da ultima amostra (parciais ON)
double   s_last_vp         = EMPTY_VALUE;
double   s_last_ma_start   = EMPTY_VALUE;
double   s_last_ma_ref     = EMPTY_VALUE;
double   s_last_vp_livre   = EMPTY_VALUE;

//+------------------------------------------------------------------+
//| VP Livre -- janela em candles M5 pre-calculada em OnInit           |
//| (12 candles M5 = 1 hora). 0 = VP Livre desligado.                  |
//| Cap defensivo: 720h (30 dias) -- evita window > rates_total.      |
//|                                                                    |
//| Suavizacao EMA opcional: s_vp_livre_alpha = 2/(N+1) quando         |
//| InpVP_Livre_Smooth > 0. 0.0 = sem suavizacao (valor cru).          |
//+------------------------------------------------------------------+
int    s_vp_livre_window = 0;
double s_vp_livre_alpha  = 0.0;   // 0.0 = sem suavizacao

//+------------------------------------------------------------------+
//| Recalculo forcado + flag de reset por REASON_PARAMETERS et al     |
//+------------------------------------------------------------------+
bool     g_hadGaps           = false;
datetime g_lastFullRecalcTime = 0;
#define  RECALC_THROTTLE_SEC  5

bool     s_need_full_reset   = true;  // primeira carga forca full recalc
bool     g_chart_is_m5       = false; // setado em OnInit, otimizacao shift M5
int      g_subwin_idx        = -1;    // setado em _CreateRefLinesInSubwin

//+------------------------------------------------------------------+
//| Helpers numericos -- identicos aos do modulo 20 v2 do EA          |
//+------------------------------------------------------------------+

// pct_change: out[i] = in[i]/in[i-1] - 1.  out[0] = VP_INVALID.
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

// quantil com interpolacao linear sobre array ordenado, ignorando VP_INVALID.
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

// winsor: clip(in[], q_low_value, q_high_value).
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

// std amostral (ddof=1) ignorando VP_INVALID.
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

// EWMA RiskMetrics com var_0 = 0 (padrao Portal v2).
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
   g_cache_d1_key     = 0;
   g_cache_sigma_hist = VP_INVALID;
}

void _ResetLastSampleStatics()
{
   s_last_sample_ts = 0;
   s_last_lowtf_bar = 0;
   s_last_vp        = EMPTY_VALUE;
   s_last_ma_start  = EMPTY_VALUE;
   s_last_ma_ref    = EMPTY_VALUE;
   s_last_vp_livre  = EMPTY_VALUE;
}

//+------------------------------------------------------------------+
//| Validacao admin -- espelha modulo 28 do EA (apenas paralelas).    |
//|                                                                    |
//| R4: periodo ativo deve ser >= 2 (warn).                            |
//| R5: paralelas com Start >= Ref (BLOCK esperado, warn).            |
//| R6: MA inteira zerada (Start E Ref = 0) -> warn.                  |
//|                                                                    |
//| Retorna true se pelo menos um slot MA (Start ou Ref) esta ativo.  |
//+------------------------------------------------------------------+
bool _ApplyAdminRules()
{
   s_ma_start_eff = InpMA_Start_Period;
   s_ma_ref_eff   = InpMA_Ref_Period;

   // R4 -- periodos ativos abaixo de 2 sao atipicos
   if(s_ma_start_eff > 0 && s_ma_start_eff < 2)
      PrintFormat("[ZTMAVP] R4 MA Start=%d < 2 (valor atipico)", s_ma_start_eff);
   if(s_ma_ref_eff > 0 && s_ma_ref_eff < 2)
      PrintFormat("[ZTMAVP] R4 MA Ref=%d < 2 (valor atipico)", s_ma_ref_eff);

   // R5 -- paralelas com Start >= Ref -> BLOCK permanente esperado
   if(s_ma_start_eff > 0 && s_ma_ref_eff > 0
      && s_ma_start_eff >= s_ma_ref_eff)
      PrintFormat("[ZTMAVP] R5 paralelas: Start=%d >= Ref=%d (gate em BLOCK esperado)",
                  s_ma_start_eff, s_ma_ref_eff);

   // R6 -- nenhuma MA ativa
   const bool any_active = (s_ma_start_eff > 0 || s_ma_ref_eff > 0);
   if(!any_active)
      Print("[ZTMAVP] R6: nenhum slot MA ativo");

   return any_active;
}

//+------------------------------------------------------------------+
//| Getters de periodos efetivos                                       |
//+------------------------------------------------------------------+
int _GetMAStartPeriod() { return s_ma_start_eff; }
int _GetMARefPeriod()   { return s_ma_ref_eff;   }

//+------------------------------------------------------------------+
//| _GetCurrentPrice -- midprice live na vela corrente.               |
//| Espelha bloco SymbolInfoTick do modulo 20 v2 do EA. Fallback     |
//| para o close da vela se nenhum tick valido.                       |
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
//| _PriceNowVelaCorrente -- fonte do preco da vela corrente (v2.7).  |
//| Parciais ON: close do ultimo M1 FECHADO (deterministico, igual    |
//| p/ indicador e EA; no minuto 0 equivale ao close do M5 anterior). |
//| Parciais OFF: midprice live (comportamento v2.6).                 |
//+------------------------------------------------------------------+
double _PriceNowVelaCorrente(const double fallback)
{
   if(InpParciais_Enable)
   {
      const double c = iClose(_Symbol, PERIOD_M1, 1);
      return (c > 0.0) ? c : fallback;
   }
   return _GetCurrentPrice(fallback);
}

//+------------------------------------------------------------------+
//| OBJ_HLINE de referencia (sigmas -8 a +8)                          |
//|                                                                    |
//| Niveis cobrem range tipico do VP em eventos extremos. Estilo      |
//| uniforme (clrSilver, STYLE_DOT, width 1, BACK, HIDDEN).            |
//+------------------------------------------------------------------+
void _CreateRefLinesInSubwin(const int subwin)
{
   g_subwin_idx = subwin;   // memoriza para _DeleteRefLines

   // Cleanup transitivo: HLINEs de schema antigo (nome sem subwin) ficam
   // orfas e sobrepoem visualmente as novas na sub-janela. Removemos 1x na
   // criacao -- idempotente e barato apos primeira passagem.
   for(int i = 0; i < ZTMAVP_REF_COUNT; i++)
      ObjectDelete(0, StringFormat("ZTMAVP_ref_%d", i));

   // Cleanup transitivo: OBJ_TEXT "_LBL" (labels sigma dentro do plot, nao
   // usados neste build -- operador le o valor sigma via crosshair do MT5).
   for(int i = 0; i < ZTMAVP_REF_COUNT; i++)
      ObjectDelete(0,
         StringFormat("%s%d_%d_LBL", ZTMAVP_REF_PREFIX_BASE, subwin, i));

   for(int i = 0; i < ZTMAVP_REF_COUNT; i++)
   {
      const string name  = StringFormat("%s%d_%d", ZTMAVP_REF_PREFIX_BASE, subwin, i);
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
   if(g_subwin_idx < 0) return;   // HLINEs nunca foram criadas
   for(int i = 0; i < ZTMAVP_REF_COUNT; i++)
      ObjectDelete(0,
         StringFormat("%s%d_%d", ZTMAVP_REF_PREFIX_BASE, g_subwin_idx, i));
}

//+------------------------------------------------------------------+
//| OnInit                                                             |
//|                                                                    |
//| Detecta UninitializeReason() para tratar REASON_PARAMETERS /      |
//| RECOMPILE / CHARTCHANGE. Em todos esses casos, statics sao         |
//| zeradas e g_hadGaps=true para forcar full recalc no proximo        |
//| OnCalculate (senao as linhas somem ao trocar calibragem).          |
//+------------------------------------------------------------------+
int OnInit()
{
   const int reason_prev = UninitializeReason();
   s_need_full_reset = (reason_prev == REASON_PARAMETERS
                     || reason_prev == REASON_RECOMPILE
                     || reason_prev == REASON_CHARTCHANGE
                     || reason_prev == 0);   // primeira carga

   if(s_need_full_reset)
   {
      _ResetCaches();
      _ResetLastSampleStatics();
      g_hadGaps            = true;
      g_lastFullRecalcTime = 0;
   }

   // B3: cache de "chart e M5?" para shift aritmetico no OnCalculate
   g_chart_is_m5 = (_Period == PERIOD_M5);

   // Flip de ativo -> TODAS as janelas do daytrade (M5 24h + D1 sigma_hist 1 ano)
   const bool is_btc = (InpAtivo == ATIVO_BITCOIN);
   s_m5_window = is_btc ? kM5_Win_Bitcoin : kM5_Win_Ouro;
   s_d1_ewma   = is_btc ? kD1_Bitcoin     : kD1_Ouro;

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

   SetIndexBuffer(0, BufVP,        INDICATOR_DATA);
   SetIndexBuffer(1, BufMA_Start,  INDICATOR_DATA);
   SetIndexBuffer(2, BufMA_Ref,    INDICATOR_DATA);
   SetIndexBuffer(3, BufVP_Livre,  INDICATOR_DATA);

   for(int i = 0; i < 4; i++)
      PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   // Validar inputs admin (R4-R6). Idempotente.
   if(!_ApplyAdminRules())
      Print("[ZTMAVP] WARN: nenhuma MA ativa -- indicador nao plotara MA Start/Ref");

   // VP Livre -- validacao + pre-calculo da janela em candles M5 (12 = 1h)
   if(InpVP_Livre_Hours > 720)
      PrintFormat("[ZTMAVP] WARN VP_Livre_Hours=%d > 720 -- forcado para 720",
                  InpVP_Livre_Hours);
   const int vp_h = (int)MathMax(0, MathMin(720, InpVP_Livre_Hours));
   s_vp_livre_window = (vp_h > 0) ? vp_h * 12 : 0;

   // VP Livre -- suavizacao EMA opcional (alpha = 2/(N+1)). 0 = off (valor cru)
   const int smooth = (int)MathMax(0, InpVP_Livre_Smooth);
   if(smooth > 0 && smooth < 2)
      PrintFormat("[ZTMAVP] WARN VP_Livre_Smooth=%d < 2 (periodo EMA atipico)", smooth);
   s_vp_livre_alpha = (smooth > 0) ? 2.0 / ((double)smooth + 1.0) : 0.0;

   // Aplicar toggle de exibicao -- idempotente (re-aplica em todo OnInit
   // para garantir que mudancas de input revertam DRAW_NONE para DRAW_LINE).
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
      StringFormat("ZT_MA_VP_M5 v2.7 [%s %s%s%s %d/%d m5=%d d1=%d]",
                   ativo_str, perfil_str, (s_winsor ? "+w" : ""),
                   (InpParciais_Enable ? "+p" : ""),
                   _GetMAStartPeriod(), _GetMARefPeriod(), s_m5_window, s_d1_ewma));

   // Observabilidade: 1 linha de resumo final de config
   PrintFormat("[ZT_MA_VP_M5] v2.7 | ativo=%s perfil=%s(L%.2f/A%.2f) winsor=%s parciais=%s | M5_24h=%d D1_1ano=%d | MA %d/%d | VP_Livre=%dh s%d",
               ativo_str, perfil_str, s_lambda, s_alpha, (s_winsor ? "ON" : "OFF"),
               (InpParciais_Enable ? "ON(M1)" : "OFF"),
               s_m5_window, s_d1_ewma,
               _GetMAStartPeriod(), _GetMARefPeriod(), vp_h, smooth);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit -- so deleta OBJ_HLINE em REMOVE/PROGRAM/CLOSE.          |
//| Em REASON_PARAMETERS / RECOMPILE / CHARTCHANGE preserva os        |
//| objetos no chart (sao re-aproveitados via ObjectFind no recriar). |
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
//| sigma_hist as-of timestamp t (cache por dia D1)                     |
//|                                                                    |
//| Cache so guarda resultados VALIDOS.                                |
//+------------------------------------------------------------------+
double _SigmaHistAsOf(const datetime t)
{
   const int shift_d1 = iBarShift(_Symbol, PERIOD_D1, t, false);
   if(shift_d1 < 0) return VP_INVALID;

   const datetime d1_key = (datetime)iTime(_Symbol, PERIOD_D1, shift_d1);
   if(d1_key <= 0) return VP_INVALID;

   if(d1_key == g_cache_d1_key && g_cache_sigma_hist != VP_INVALID)
      return g_cache_sigma_hist;

   MqlRates rates_d1[];
   const int copied = CopyRates(_Symbol, PERIOD_D1, shift_d1, s_d1_ewma, rates_d1);
   if(copied < VP_NMIN_D1 + 2) return VP_INVALID;

   const int n_d1 = copied - 1;   // exclui o D1 que contem t (pattern v2 Portal)
   if(n_d1 < VP_NMIN_D1) return VP_INVALID;

   double closes_d1[];
   ArrayResize(closes_d1, n_d1, n_d1);
   for(int i = 0; i < n_d1; i++)
      closes_d1[i] = rates_d1[i].close;

   double rets_d1[];
   _PctChange(closes_d1, rets_d1, n_d1);

   double rets_d1_w[];
   _MaybeWinsor(rets_d1, rets_d1_w, n_d1, VP_NMIN_D1);

   const double sigma = _EwmaSigmaVar0(rets_d1_w, n_d1, s_lambda);
   if(sigma == VP_INVALID || sigma <= 0.0) return VP_INVALID;

   g_cache_d1_key     = d1_key;
   g_cache_sigma_hist = sigma;
   return sigma;
}

//+------------------------------------------------------------------+
//| n_sigma_raw as-of timestamp t. SEM cache M5: recalcula sempre      |
//| (cache por m5_key causaria divergencia EA vs indicador).           |
//|                                                                    |
//| price_now:                                                         |
//|   - is_current_bar = true  -> midprice live via _GetCurrentPrice  |
//|   - is_current_bar = false -> close da vela M5 (closes_m5[N-1])   |
//|                                                                    |
//| shift_m5_hint >= 0 evita o iBarShift quando o chart e M5 e         |
//| podemos derivar o shift por aritmetica de indice.                  |
//|                                                                    |
//| out_sigma_final e out_price_now sao expostos para reuso pelo       |
//| VP Livre (mesmo sigma_final, mesma referencia de price_now). Em   |
//| path invalido retornam respectivamente VP_INVALID e 0.0.           |
//+------------------------------------------------------------------+
double _NSigmaAsOfBarra(const datetime t, const double sigma_hist,
                        const bool is_current_bar, const int shift_m5_hint,
                        double &out_sigma_final, double &out_price_now)
{
   out_sigma_final = VP_INVALID;
   out_price_now   = 0.0;
   if(sigma_hist == VP_INVALID || sigma_hist <= 0.0) return VP_INVALID;

   const int shift_m5 = (shift_m5_hint >= 0) ? shift_m5_hint
                                              : iBarShift(_Symbol, PERIOD_M5, t, false);
   if(shift_m5 < 0) return VP_INVALID;

   MqlRates rates_m5[];
   const int copied = CopyRates(_Symbol, PERIOD_M5, shift_m5, s_m5_window, rates_m5);
   if(copied < VP_NMIN_M5) return VP_INVALID;

   const int n_m5 = copied;
   double closes_m5[];
   ArrayResize(closes_m5, n_m5, n_m5);
   for(int i = 0; i < n_m5; i++)
      closes_m5[i] = rates_m5[i].close;

   double rets_m5[];
   _PctChange(closes_m5, rets_m5, n_m5);

   double rets_m5_w[];
   _MaybeWinsor(rets_m5, rets_m5_w, n_m5, VP_NMIN_M5);

   // Paridade Portal: sigma_real = std bruto dos retornos M5 (winsor opcional),
   // SEM anualizacao. Replica passo 6 do _VP2_ComputeIntraday do EA.
   const double sigma_real = _StdSample(rets_m5_w, n_m5);
   if(sigma_real == VP_INVALID || sigma_real <= 0.0) return VP_INVALID;

   const double sigma_final = s_alpha * sigma_hist
                            + (1.0 - s_alpha) * sigma_real;
   if(sigma_final < VP_EPS) return VP_INVALID;

   // price_now SOMENTE na vela corrente (parciais ON = close do ultimo M1
   // fechado; OFF = midprice live). Barras historicas usam o close da vela.
   const double close_now = closes_m5[n_m5 - 1];
   const double price_now = is_current_bar ? _PriceNowVelaCorrente(close_now) : close_now;

   const double price_24h_ago = closes_m5[0];
   if(price_now <= 0.0 || price_24h_ago <= 0.0) return VP_INVALID;

   const double ret_24h = price_now / price_24h_ago - 1.0;
   const double n_sigma = ret_24h / sigma_final;

   out_sigma_final = sigma_final;
   out_price_now   = price_now;
   return n_sigma;
}

//+------------------------------------------------------------------+
//| OnCalculate -- loop por barra do chart                             |
//|                                                                    |
//| - Hook retardado para criar OBJ_HLINE (subwin so disponivel apos  |
//|   primeira chamada).                                               |
//| - Gate MTF: se dados insuficientes, retorna prev_calculated em    |
//|   vez de 0 (retornar 0 dispararia ArrayInitialize e apagaria tudo).|
//| - s_need_full_reset (setado pelo OnInit em REASON_PARAMETERS et   |
//|   al) forca full recalc no proximo passo.                          |
//| - g_hadGaps so marca true para gaps na ZONA QUENTE (ultimas       |
//|   s_m5_window barras). Gaps em barras antigas naturalmente        |
//|   invalidas (D1<420 ou M5<288) sao normais e nao re-armam o full   |
//|   recalc reciclico.                                                |
//| - Vela corrente: gate 300s -- entre amostras reusa s_last_*.       |
//| - alphas EMA pre-calculados fora do loop.                          |
//| - blocos MA pulados se MA inativa (Start=0 e Ref=0).               |
//| - shift M5 por aritmetica de indice quando chart e M5 e            |
//|   bars_m5 == rates_total. Fallback iBarShift caso contrario.       |
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

   //--- Criacao retardada das OBJ_HLINE (subwin so registrada apos OnInit retornar) ---
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
   const int bars_d1 = iBars(_Symbol, PERIOD_D1);
   const int bars_m5 = iBars(_Symbol, PERIOD_M5);
   if(bars_d1 < s_d1_ewma || bars_m5 < s_m5_window)
      return prev_calculated;   // retornar 0 aqui apagaria tudo (ArrayInitialize)

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

   //--- Snapshot da config admin para o loop ---
   const int    ms_per          = _GetMAStartPeriod();
   const int    mr_per          = _GetMARefPeriod();
   const bool   lines_active    = InpShow_Lines && (ms_per > 0 || mr_per > 0);
   const int    vp_w            = s_vp_livre_window;
   const bool   vp_livre_active = InpShow_Lines && (vp_w > 0);

   //--- alphas EMA pre-calculados fora do loop ---
   const double a_s = (ms_per > 0) ? 2.0 / ((double)ms_per + 1.0) : 0.0;
   const double a_r = (mr_per > 0) ? 2.0 / ((double)mr_per + 1.0) : 0.0;

   //--- shift_m5 por aritmetica se chart M5 e arrays alinhados ---
   const bool can_use_arith_shift = g_chart_is_m5 && (bars_m5 == rates_total);

   //--- zona quente para deteccao de gap (gaps fora dela sao normais) ---
   const int hot_start = (rates_total > s_m5_window)
                          ? rates_total - s_m5_window : 0;

   bool hadGapsThisPass = false;

   for(int i = start; i < rates_total; i++)
   {
      const bool     is_current_bar = (i == rates_total - 1);
      const datetime t              = time[i];

      //--- Gate na vela corrente: entre amostras, reusa s_last_*.
      //--- Parciais ON (v2.7): amostra a cada barra M1 NOVA (5 parciais por
      //--- barra M5); o teto kSampleIntervalSec segue como fallback de
      //--- seguranca. OFF: gate 300s original.
      if(is_current_bar && s_last_sample_ts != 0)
      {
         const bool within_gate =
            (TimeCurrent() - s_last_sample_ts) < (datetime)kSampleIntervalSec;
         const bool reuse = InpParciais_Enable
            ? (within_gate && iTime(_Symbol, PERIOD_M1, 0) == s_last_lowtf_bar)
            : within_gate;
         if(reuse)
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
      }

      //--- hint de shift M5 (ou -1 para fallback iBarShift) ---
      const int shift_m5 = can_use_arith_shift ? (rates_total - 1 - i) : -1;

      //--- Calculo sigma_hist + n_sigma para a barra ---
      const double sigma_hist = _SigmaHistAsOf(t);
      if(sigma_hist == VP_INVALID)
      {
         BufVP[i] = EMPTY_VALUE;
         if(lines_active)    { BufMA_Start[i] = EMPTY_VALUE; BufMA_Ref[i] = EMPTY_VALUE; }
         if(vp_livre_active) BufVP_Livre[i] = EMPTY_VALUE;
         if(i >= hot_start) hadGapsThisPass = true;   // gap na zona quente
         continue;
      }

      //--- out params do _NSigmaAsOfBarra para reuso pelo VP Livre ---
      double sigma_final = VP_INVALID;
      double price_now   = 0.0;
      const double n_sigma = _NSigmaAsOfBarra(t, sigma_hist, is_current_bar, shift_m5,
                                              sigma_final, price_now);
      if(n_sigma == VP_INVALID)
      {
         BufVP[i] = EMPTY_VALUE;
         if(lines_active)    { BufMA_Start[i] = EMPTY_VALUE; BufMA_Ref[i] = EMPTY_VALUE; }
         if(vp_livre_active) BufVP_Livre[i] = EMPTY_VALUE;
         if(i >= hot_start) hadGapsThisPass = true;   // gap na zona quente
         continue;
      }

      BufVP[i] = n_sigma;

      //--- VP Livre -- valor cru (janela em horas, chart M5: 12 candles = 1h)
      //--- Se s_vp_livre_alpha > 0, aplica EMA sobre o cru in-place.
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
            BufVP_Livre[i] = vp_raw;   // sem suavizacao OU seed
      }

      //--- MAs -- bloco inteiro pulado se MA inativa ---
      if(lines_active)
      {
         //--- MA Start ---
         if(ms_per > 0)
         {
            if(i == 0 || BufMA_Start[i-1] == EMPTY_VALUE)
               BufMA_Start[i] = n_sigma;
            else
               BufMA_Start[i] = a_s * n_sigma + (1.0 - a_s) * BufMA_Start[i-1];
         }
         else
            BufMA_Start[i] = EMPTY_VALUE;

         //--- MA Ref (paralela: input sempre n_sigma) ---
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

      //--- Statics da vela corrente (suporte ao gate de amostragem) ---
      if(is_current_bar)
      {
         s_last_vp        = BufVP[i];
         s_last_ma_start  = lines_active    ? BufMA_Start[i] : EMPTY_VALUE;
         s_last_ma_ref    = lines_active    ? BufMA_Ref[i]   : EMPTY_VALUE;
         s_last_vp_livre  = vp_livre_active ? BufVP_Livre[i] : EMPTY_VALUE;
         s_last_sample_ts = TimeCurrent();
         s_last_lowtf_bar = iTime(_Symbol, PERIOD_M1, 0);
      }
   }

   g_hadGaps = hadGapsThisPass;
   return rates_total;
}
//+------------------------------------------------------------------+
