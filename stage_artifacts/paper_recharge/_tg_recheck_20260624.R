## Factor deep-recheck (tier-2) telegram brief — 20260624 (single tg_agent_brief call)
for (loc in c("Korean_Korea.utf8","Korean_Korea.65001","English_United States.utf8","C")) {
  if (suppressWarnings(nzchar(Sys.setlocale("LC_CTYPE", loc)))) break
}
suppressWarnings(suppressMessages({ library(jsonlite) }))
ROOT <- Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", getwd()))
if (!nzchar(ROOT)) ROOT <- getwd()
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure", "telegram", "telegram_notify.R"))

TODAY <- "20260624"
base  <- file.path("stage_artifacts", "paper_recharge")
res_j <- fromJSON(file.path(base, sprintf("factor_recheck_result_%s.json", TODAY)), simplifyVector = FALSE)

n_in   <- res_j$n_input
n_prom <- length(res_j$promoted)
n_inf  <- length(res_j$confirmed_infeasible)
n_red  <- length(res_j$redundant)
n_unc  <- length(res_j$still_uncertain)

b_rej <- c(
  "resga_predicted_ES_sort [2606.04576] — 06-21 testable 승격 후 백테 양방향 사멸: POS(대형주×고꼬리, 논문 미국부호) PORT_t -2.81 유의 underperform / NEG(소형주×고꼬리) screen-fail MDD 74.6% → QUARANTINE. 충실 Eq.(11) 재구성·PIT clean이나 실현α 음(-). empirically-dead, 재큐 금지.",
  "price_network_centrality [2606.07450] — 인도네시아 섹터 taxonomy 복원/community detection(AMI) 논문, 종목 수익신호 전무 → 팩터화=batch_434 날조 가드. infeasible 5회차 불변.")

sections <- list(
  list(emoji = "✅", heading = sprintf("승격(testable) %d건", n_prom), type = "text",
       body = "신규 승격 0 — 입력 2건 모두 전일까지 해소된 후보의 runner-bug 재유입. 신규 후보 없음."),
  list(emoji = "⛔", heading = sprintf("확정기각 %d건", n_inf), type = "bullet", items = b_rej),
  list(emoji = "🔧", heading = "runner 버그 근본수리 완료(5일째→해소)", type = "bullet",
       items = c(
         "ROOT CAUSE: factor_deep_recheck_run.sh L27 dedup = set()을 processed[](dict 리스트)에 적용 → TypeError → bare except가 삼켜 done=빈set → 제외 영구 무작동.",
         "수리: processed[].paper_id 추출(string-tolerant) + queue date=TODAY(기존 `if False`→null placeholder 제거).",
         "실측 검증: 수리 후 done={2606.04576, 2606.07450} 정확 추출, 양 paper_id excluded=True → 차회 실행 n=0 skip 예상.",
         "효과: 5일 연속 동일 2 paper_id 재유입 + queue date:null 동시 해소."))
)

res <- tg_agent_brief(
  agent = "AlphaSearch",
  title = "팩터 심층 재검 (tier-2)",
  as_of = "2026-06-24",
  relaxed = TRUE,
  force = TRUE,
  lock_scope = sprintf("factor_recheck_%s", TODAY),
  sections = sections,
  footer = sprintf("입력 %d건(전일분 재유입 — 단 runner dedup 버그 근본수리 완료). 승격 %d / 확정기각 %d(2606.04576 백테사멸·2606.07450 신호부재) / 중복 %d / 보류 %d. alpha_search_queue 미생성(승격 0). 산출: factor_recheck_result_%s.json",
                   n_in, n_prom, n_inf, n_red, n_unc, TODAY))

cat("TG_OK:", isTRUE(res$ok), " bytes:", res$bytes %||% NA, " err:", res$error %||% "NULL", "\n")
