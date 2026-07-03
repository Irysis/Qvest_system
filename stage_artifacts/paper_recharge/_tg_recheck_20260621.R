## Factor deep-recheck (tier-2) telegram brief — 20260621 (single tg_agent_brief call)
## locale: C.UTF-8 startup 실패로 PCRE [가-힣] 컴파일 깨짐 → Windows UTF-8 로케일 강제
for (loc in c("Korean_Korea.utf8","Korean_Korea.65001","English_United States.utf8","C")) {
  if (suppressWarnings(nzchar(Sys.setlocale("LC_CTYPE", loc)))) break
}
suppressWarnings(suppressMessages({ library(jsonlite) }))
ROOT <- Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", getwd()))
if (!nzchar(ROOT)) ROOT <- getwd()
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure", "telegram", "telegram_notify.R"))

TODAY <- "20260621"
base  <- file.path("stage_artifacts", "paper_recharge")
res_j <- fromJSON(file.path(base, sprintf("factor_recheck_result_%s.json", TODAY)), simplifyVector = FALSE)

n_in   <- res_j$n_input
n_prom <- length(res_j$promoted)
n_inf  <- length(res_j$confirmed_infeasible)
n_red  <- length(res_j$redundant)
n_unc  <- length(res_j$still_uncertain)

b_prom <- c(
  "size_enhanced_left_side_momentum [2606.04576]",
  "= size×tail-risk 상호작용(Eq.11, too-big-to-fail). registry 부재 신규.",
  "논문 scaling: 경량 ES forecaster로도 FF5 α 유의 → 충실재구성 가능(ReSGA 딥모델 불요).",
  "전일 redundant→승격. long-only=대형주×고꼬리위험 long leg, 부호 KR 양방향 검증.",
  "caveat: base ES sort은 redundant(대조군)·short leg 상실 약화·성능 미실측.")

b_rej <- "price_network_centrality [2606.07450] — 논문=인도네시아 섹터 taxonomy 복원/community detection(AMI). 종목 수익신호 전무(centrality 산출조차 없음) → 팩터 합성=batch_434 날조 가드."

sections <- list(
  list(emoji = "✅", heading = sprintf("승격(testable) %d건", n_prom), type = "bullet", items = b_prom),
  list(emoji = "⛔", heading = sprintf("확정기각 %d건", n_inf), type = "text", body = b_rej),
  list(emoji = "🐞", heading = "runner 버그(surface)", type = "bullet",
       items = c(
         "3일 연속 동일 2 paper_id 재유입(둘 다 done 20260619/infeasible 등재됨에도 큐 포함).",
         "큐빌더 done-제외(dedup) 미작동 — 정상 신규입력 0건이어야.",
         "단 오늘 full-text 재독이 2606.04576 Eq.(11) 정밀화→승격 산출(재유입이 실익낸 케이스).",
         "후속: 큐생성 시 factor_recheck_done.processed[].paper_id 대조 제외."))
)

res <- tg_agent_brief(
  agent = "AlphaSearch",
  title = "팩터 심층 재검 (tier-2)",
  as_of = "2026-06-21",
  relaxed = TRUE,
  force = TRUE,
  lock_scope = sprintf("factor_recheck_%s", TODAY),
  sections = sections,
  footer = sprintf("입력 %d건(전일분 재유입, runner dedup 버그). 승격 %d(size_enhanced_left_side_momentum) / 확정기각 %d / 중복 %d / 보류 %d. alpha_search_queue_%s.json 추가. 산출: factor_recheck_result_%s.json",
                   n_in, n_prom, n_inf, n_red, n_unc, TODAY, TODAY))

cat("TG_OK:", isTRUE(res$ok), " bytes:", res$bytes %||% NA, " err:", res$error %||% "NULL", "\n")
