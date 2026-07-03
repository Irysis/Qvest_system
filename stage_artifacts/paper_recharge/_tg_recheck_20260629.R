## Factor deep-recheck (tier-2) telegram brief — 20260629 (single tg_agent_brief call)
for (loc in c("Korean_Korea.utf8","Korean_Korea.65001","English_United States.utf8","C")) {
  if (suppressWarnings(nzchar(Sys.setlocale("LC_CTYPE", loc)))) break
}
suppressWarnings(suppressMessages({ library(jsonlite) }))
ROOT <- Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", getwd()))
if (!nzchar(ROOT)) ROOT <- getwd()
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure", "telegram", "telegram_notify.R"))

TODAY <- "20260629"
base  <- file.path("stage_artifacts", "paper_recharge")
res_j <- fromJSON(file.path(base, sprintf("factor_recheck_result_%s.json", TODAY)), simplifyVector = FALSE)

n_in   <- res_j$n_input
n_prom <- length(res_j$promoted)
n_inf  <- length(res_j$confirmed_infeasible)
n_red  <- length(res_j$redundant)
n_unc  <- length(res_j$still_uncertain)

b_rej <- c(
  "market_body_tail_leg [2606.23596 — Anatomy of the Market, Shin/Sogang] — 전문(~100k) 정독. 팩터모델 *평가 진단* 논문이지 거래 알파 아님. CRSP 시장을 누적시총 기준 body(대형)·tail(소형) leg로 분할해 CAPM/FF3/Carhart/FF5/FF6/q5가 size-ranked 분해에 systematic pricing error를 남기는지 비교 → q5만 negative-body/positive-tail alpha(ROE·EG block 탓).",
  "infeasible 사유: ① 저자 명시 'legs are NOT anomaly portfolios... size-ranked portfolios' = 종목 선택신호 부재 ② 문서화된 alpha = 미국 q5 모델의 잔차(diagnostic, 'not an out-of-sample test') — 포팅할 수익예측 규칙 없음 ③ KR 구성가능 유일 신호 = 누적시총 leg 분할 = 순수 SIZE → S01_Size/L26_Log_MktCap redundant ④ L/S 가드: tail leg long-only 사상도 소형주 틸트=size, 신규 long-leg 신호 없음.")

sections <- list(
  list(emoji = "✅", heading = sprintf("승격(testable) %d건", n_prom), type = "text",
       body = "승격 0 — 입력 1건은 거래 신호 없는 팩터모델 평가 진단 논문. alpha_search_queue 미생성."),
  list(emoji = "⛔", heading = sprintf("확정기각(infeasible) %d건", n_inf), type = "bullet", items = b_rej)
)

res <- tg_agent_brief(
  agent = "AlphaSearch",
  title = "팩터 심층 재검 (tier-2)",
  as_of = "2026-06-29",
  relaxed = TRUE,
  force = TRUE,
  lock_scope = sprintf("factor_recheck_%s", TODAY),
  sections = sections,
  footer = sprintf("입력 %d건. 승격 %d / 확정기각 %d(2606.23596 팩터모델 진단·수익신호 부재) / 중복 %d / 보류 %d. alpha_search_queue 미생성(승격 0). 산출: factor_recheck_result_%s.json",
                   n_in, n_prom, n_inf, n_red, n_unc, TODAY))

cat("TG_OK:", isTRUE(res$ok), " bytes:", res$bytes %||% NA, " err:", res$error %||% "NULL", "\n")
