## alpha_validation.json 에 T+1 실행앵커 + 정적검증 이력 추가 + 차트 재생성
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_002")
say <- function(fmt,...) { cat(sprintf(paste0("[av] ",fmt,"\n"),...)); flush.console() }
source("02_Infrastructure/telegram/tg_chart_pack.R")

AV <- fromJSON(file.path(OUT,"alpha_validation.json"), simplifyVector=TRUE)
T1 <- readRDS(file.path(OUT,"m26_t1exec.rds"))
SP <- fread(file.path(OUT,"m26_subperiod_power.csv"))
say("★입력 실측: alpha_validation 키 %d · T+1 tab %d행 · 부기간 검정력 %d행",
    length(AV), nrow(T1$tab), nrow(SP))

t1t <- T1$tab[term=="M26_Revenue_Mom", t_nw3]
AV$pit_robustness <- list(
  static_verifier = "02_Infrastructure/ast/ast_verify.py (ast_spec_gate.sh ③)",
  initial_verdict = "FAIL_LOOKAHEAD — REGISTRY[M26_Revenue_Mom] avail 2026-08-01 > t_d 2026-07-31",
  cause = paste0("컨센서스 계열 33종이 registry availability.known_discrepancy 를 보유(선언 T-1 vs 코드 ",
    "Date <= sig_d same-day 허용, 제공시각 메타 부재) → 검증기가 보수 가용시점을 sig_date + 1d 로 잡는다 ",
    "(CONSENSUS_DISC_LAG_DAYS=1). ★후보 고유 결함이 아니라 하네스-전역: 동일 33종에 북 incumbent ",
    "C01_SUE·C02_EPS_Chg_1m·C04_ESBR 이 전부 포함된다."),
  response = paste0("AST 에 TS_LAG 를 '선언만' 하는 것은 거짓 선언이므로 실제로 늦춰서 재측정. ",
    "T+1 실행앵커 = 체결이 익월 첫 거래일 종가 → 그 다음달 첫 거래일 종가. ",
    "병합 align_signal_return_ym(off=+1, realized_month) — 헬퍼의 look-ahead 가드가 off<=0 를 거부한다."),
  t1exec = list(
    n_months = T1$n_months,
    period = "2003-01 ~ 2026-06 (신호월 기준)",
    fmb_nw3_t = t1t,
    retention_vs_baseline = t1t / AV$primary$fmb_nw3_t,
    control_t = as.list(setNames(T1$tab$t_nw3, T1$tab$term)),
    rank_ic_mean = mean(T1$ic$ic),
    verdict = if (abs(t1t) >= 2.0) "문턱 위 생존 — 재료 자격 판정 PIT-강건" else "문턱 미달 — 재료 자격 철회 필요"
  ),
  final_gate = "ast_spec_gate.sh 통과 ({}). decision_ts=2026-08-03 선언은 측정한 실행 컨벤션과 일치.",
  gate_block_efficacy_check = "위반 주입(mechanism.friction 공백) 시 게이트가 block 발행 확인 — 통과가 침묵이 아님",
  residual = "원천 컨센서스 T-1 strict 재빌드(Date <= sig_d - 1) A/B 는 미실시 — FQ 등재"
)
AV$subperiod_power <- as.list(SP)
AV$subperiod_power_note <- paste0("★3구간 전부 INCONCLUSIVE_UNDERPOWERED (각 구간 자체 sd 기준). ",
  "점추정은 단조 하락(연 3.58%→1.82%→0.99%)하나 '감쇠 확정'으로 쓰지 않는다 — ",
  "분할 설계는 검정력을 파괴한다(2026-08-08 3/3 실증).")
AV$self_adversarial = "stage_artifacts/WT_D20260808_002/challenge_note.md"

write(toJSON(AV, auto_unbox=TRUE, pretty=TRUE, digits=NA, null="null"),
      file.path(OUT,"alpha_validation.json"))
say("alpha_validation.json 갱신")

## 차트 재생성 (T+1 축 포함)
p1 <- tg_chart_sweep(
  labels = c("정보계수 t (M26 단독)", "증분 회귀 t (주판정)", "T+1 실행앵커 t",
             "동일가중 유니버스 대비 t", "시총가중 t (판정 권위)", "2017년 이후 t", "자본 문턱 2.95"),
  values = c(AV$secondary$rank_ic_t_nw3, AV$primary$fmb_nw3_t, t1t,
             AV$transition$dual_basis$ew_universe_port_t_raw,
             AV$transition$canonical_port_t_raw,
             AV$transition$dual_basis$post2017_t_nw_lag3, 2.95),
  out_dir = OUT, title = "M26 전이 사다리 — 정보계수에서 실현 초과수익까지")
p2 <- tg_chart_sweep(
  labels = c("C01_SUE (이익 서프라이즈)", "C02_EPS_Chg_1m (EPS 개정)", "C04_ESBR (개정폭)",
             "M26_Revenue_Mom (매출 개정·신규)", "재료 자격 문턱 2.0"),
  values = c(AV$primary$control_coefs$C01_SUE$t_nw3, AV$primary$control_coefs$C02_EPS_Chg_1m$t_nw3,
             AV$primary$control_coefs$C04_ESBR$t_nw3, AV$primary$fmb_nw3_t, 2.0),
  out_dir = OUT, title = "4팩터 동시 회귀 t값 — 이익 3종 대비 매출 증분")
writeLines(c(p1,p2), file.path(OUT,"chart_paths.txt"))
say("차트: %s | %s", basename(p1), basename(p2))
say("★T+1 판정: %s (t %+.3f · 유지율 %.2f)", AV$pit_robustness$t1exec$verdict, t1t, t1t/AV$primary$fmb_nw3_t)
