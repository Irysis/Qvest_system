## run_ramp_r10_emit.R — R10 L-code 적립 (mode=ramp, backtested, construction_type·selection_type 명시)
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/ramp/ramp_loop.R")
RUNTAG <- "20260713"
TAB <- as.data.table(read_parquet(sprintf("outputs/ramp/r10_weighting_gates_%s.parquet", RUNTAG)))
PAIRED <- as.data.table(read_parquet(sprintf("outputs/ramp/r10_weighting_paired_%s.parquet", RUNTAG)))
CONC <- as.data.table(read_parquet(sprintf("outputs/ramp/r10_weighting_conc_%s.parquet", RUNTAG)))
g <- function(m,c) TAB[model==m, get(c)]
pc <- function(m) PAIRED[model==m & basis=="act_bm", paired_t]
cn <- function(m,c) CONC[model==m, get(c)]

lesson <- paste0(
 "RAMP R10 (FQ-023, 도훈 '비중 결정 통계적 고도화 적용해봤니'): P-pure(W36_K20) 동일가중(종목 EW × 팩터 EW)을 ",
 "알파/점수-비례 계열로 교체 시 개선 여부. R6 sel_traj 풀 고정(선별 재실행 아님) — WEIGHTING 축만. 4 config sweep, ",
 "weighted_screen_bt 계약경로(cap-w authoritative nwt act_bm), base parity Δ=1.4e-5(R6 2.6124 bit-consistent). ",
 sprintf("결과: base cap-w PORT_t=%.3f oos=%.3f. W-stock(종목 z-선형비례) cap-w=%.3f(2.95 근접)·oos=%.3f(부호전환)·paired vs base=%.2f. ",
   g("base","port_t_capwt"), g("base","oos_retention"), g("W_stock","port_t_capwt"), g("W_stock","oos_retention"), pc("W_stock")),
 sprintf("W-stock-sqrt(완만화) cap-w=%.3f·paired=%.2f(최고 paired). W-both cap-w=%.3f·paired=%.2f. W-factor(팩터 trailing-t 비례) cap-w=%.3f·paired=%.2f(base보다 악화). ",
   g("W_stock_sqrt","port_t_capwt"), pc("W_stock_sqrt"), g("W_both","port_t_capwt"), pc("W_both"), g("W_factor","port_t_capwt"), pc("W_factor")),
 sprintf("판정 KILL_axis=TRUE: 전 config paired NW-t < 2.0 문턱(최고 %.2f=W-stock-sqrt) → P-pure 비중 축 소진, 동일가중 유지 확정. HARD 3종 0/4 통과(어느 변형도 PORT_t 2.95·oos 0.7·calmar 0.64 미달). ", max(pc("W_stock"),pc("W_stock_sqrt"),pc("W_both"),pc("W_factor"))),
 "확립 지식: (1) 종목 점수-비례 틸트는 방향성 양(+)의 가장 순한 레버 — headline cap-w를 2.61→2.93으로 끌어올려 P-pure 사상 2.95 최근접이나 유의(paired 2.0) 미달, 'EW=통계 sizing 천장'(추정오차>신호) prior와 정합(근소 초과 못함). ",
 sprintf("(2) 소형주 농축 아티팩트 아님(challenge2): OTHER(소형) 비중 base %.3f→W-stock %.3f 거의 불변 — 개선은 동일 cap-tier 내 고점수명 재가중이지 소형 이동 아님. 유효종목수 25→%.1f·HHI %.4f→%.4f. ",
   cn("base","w_OTHER"), cn("W_stock","w_OTHER"), cn("W_stock","n_eff"), cn("base","hhi"), cn("W_stock","hhi")),
 "(3) 강한틸트 FAIL수렴 없음(challenge3): 완만한 sqrt 틸트가 paired 최고(1.78>W-stock 1.60), 강한 linear는 headline 높으나 paired 낮음(집중→분산 잡음) — 틸트 강할수록 나빠지는 degradation 부재, standalone FAIL(단일팩터 top-25)로의 수렴 아님. ",
 "(4) 회전비용 생존(challenge1): 가중변형 회전 소폭 증가(base TO 9.27→W-both 9.71, 1100% 한도 여유) — 개선은 delta-based 15bps 내장 차감 후 net 값. ",
 "(5) 팩터 성과-비례 가중은 오히려 악화(W-factor paired -0.17) = factor-of-factors momentum timing NULL(06-30) 독립 재확인 — trailing 팩터성과는 forward 팩터성과를 못 예측, EW 팩터결합이 우월. ",
 "메타: 병목은 여전히 cap-tier 국소화×cap-w 벤치 미스매치(R7/R8 확증). 비중 고도화는 벽을 극복 못함. 잔존 frontier: 점수-비례 틸트를 비-수익 패널(DART insider 등, FQ-001)에 재적용(방향성 양 확인됐으므로 substrate 개선 시 유의 도달 가능성). ",
 "vintage: r6_session_20260711 sel_traj 재사용, N1 d3 parity Δ=0. n_trials P-pure 계보 누적=14(R6 6+R7 4+R10 4). selection_type=sweep.")

res <- ramp_document(
  strategy_id = "RAMP_R10_WEIGHTING_20260713",
  grade = "C",
  lesson_text = lesson,
  construction_type = "composite",
  selection_type = "sweep",
  mechanism_hypothesis = paste0(
    "P-pure 동일가중을 종목 합의점수-비례(선형/sqrt)·팩터 trailing성과-비례로 교체하면 cap-w 성과가 유의 개선될 것 = 부분 FALSE. ",
    "종목 점수-비례는 headline cap-w 2.61→2.93(2.95 근접)·oos 부호전환으로 방향성 양이나 paired NW-t<2.0(유의 미달) → EW 유지. ",
    "팩터 성과-비례는 악화(factor momentum timing NULL 재확인). 소형주농축·강틸트degradation 아님. 벽=cap-tier 국소화 불변."),
  core_reference = "L-RAMP-20260712_161537(R7)·L-RAMP-20260712_175852(R8)·project-selection-discipline-arc-r4r5r6·project-hrp-frontier-weighting-settled·measurement-graduation §6·project-captier-alpha-localization",
  portfolio_alpha_t = round(g("W_stock","port_t_capwt"),4),
  oos_retention = round(g("W_stock","oos_retention"),4),
  metrics = list(
    round="R10", fq="FQ-023",
    base_capwt=round(g("base","port_t_capwt"),4), base_oos=round(g("base","oos_retention"),4),
    wstock_capwt=round(g("W_stock","port_t_capwt"),4), wstock_ewuni=round(g("W_stock","port_t_EWuni"),4),
    wstock_oos=round(g("W_stock","oos_retention"),4), wstock_calmar=round(g("W_stock","calmar"),4),
    wstock_paired=round(pc("W_stock"),4), wstock_to=round(g("W_stock","turnover"),4),
    wstocksqrt_capwt=round(g("W_stock_sqrt","port_t_capwt"),4), wstocksqrt_paired=round(pc("W_stock_sqrt"),4),
    wboth_capwt=round(g("W_both","port_t_capwt"),4), wboth_paired=round(pc("W_both"),4),
    wfactor_capwt=round(g("W_factor","port_t_capwt"),4), wfactor_paired=round(pc("W_factor"),4),
    max_paired_capw=round(max(pc("W_stock"),pc("W_stock_sqrt"),pc("W_both"),pc("W_factor")),4),
    paired_kill_threshold=2.0, kill_axis=TRUE, any_graduation=FALSE,
    conc_neff_base=round(cn("base","n_eff"),3), conc_neff_wstock=round(cn("W_stock","n_eff"),3),
    conc_other_base=round(cn("base","w_OTHER"),4), conc_other_wstock=round(cn("W_stock","w_OTHER"),4),
    hhi_base=round(cn("base","hhi"),5), hhi_wstock=round(cn("W_stock","hhi"),5),
    base_parity_delta=1.39e-5, n_trials_lineage=14,
    config_hash="1648fada1bd7f4f8", vintage_pin="r6_session_20260711"))
cat("L-code emitted:\n"); str(res, max.level=1)
cat(sprintf("\nR10_EMIT_DONE l_code=%s\n", res$l_code %||% res$lcode %||% "(see above)"))
