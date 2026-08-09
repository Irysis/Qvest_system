## FQ-165 P0 — CLAIM + 착수 전 사전 확인 (base 확보 가능성 · 검정력)
## 대상: M26_Revenue_Mom 소비면 ⑥ — book-marginal ΔIR
## ★필수 전제(measurement-graduation §7b): incumbent base 권위 = **05_Production 현행 코드 파생**.
##   재구성 base 는 판정을 뒤집는다 — 실측: 같은 필터가 재구성 +0.169 vs production −0.149
##   ([[project-base-strength-flips-verdict-20260803]] · FQ-127).
## ⇒ production base 를 확보 못하면 **이 라운드는 착수 자격이 없다**.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ165")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p0] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")

## ---- 0. 배정 규약 1조 — owner 확인 후 CLAIM ---------------------------------
source("02_Infrastructure/ops/frontier_queue_io.R")
Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
i <- which(ids == "FQ-165")
if (!length(i)) { say("★FQ-165 부재 — 중단"); quit(status = 1) }
own <- paste(Q$entries[[i]]$owner, collapse = " ")
say("=== 0. 배정 확인 ===")
say("  FQ-165 status=%s", Q$entries[[i]]$status)
say("  owner: %s", substr(own, 1, 140))
if (grepl("CLAIMED", own) && !grepl("UNCLAIMED", own)) { say("★이미 CLAIMED — 착수 금지"); quit(status = 0) }

## ---- 1. ★production base 확보 가능성 (이게 착수 자격을 정한다) ---------------
say("=== 1. ★production base 경로 실측 (read-only) ===")
cand <- c("05_Production", "06_Registry/book_carrier", "qepm/registry", ".cache")
for (d in cand) say("  %-28s 존재=%s", d, dir.exists(d))
bs <- "06_Registry/book_state.json"
if (file.exists(bs)) {
  B <- fromJSON(bs, simplifyVector = FALSE)
  say("  book_state.json 키: %s", paste(head(names(B), 14), collapse = ", "))
  for (k in c("incumbent_book_ir", "ir_convention", "as_of", "composition", "sleeves"))
    if (!is.null(B[[k]])) say("    %-20s %s", k, substr(paste(unlist(B[[k]]), collapse=" | "), 1, 110))
} else say("  ★book_state.json 부재")

say("  --- 05_Production 내 PG2 산출물 (Grep 툴 대신 목록만) ---")
if (dir.exists("05_Production")) {
  f <- list.files("05_Production", recursive = TRUE, full.names = FALSE)
  say("  파일 %d개 · 상위 확장자: %s", length(f),
      paste(names(sort(table(tools::file_ext(f)), decreasing = TRUE))[1:5], collapse=", "))
  hit <- grep("pg2|PG2|book|weight|nav|NAV", f, value = TRUE)
  say("  PG2/book/weight/nav 매칭 %d개:", length(hit))
  for (x in head(hit, 12)) say("    %s", x)
} else say("  ★05_Production 부재")

## ---- 2. 기존 재사용 가능한 book NAV/수익 계열 --------------------------------
say("=== 2. 재사용 가능한 book 수익 계열 탐색 ===")
for (p in c(".cache/pg2_book_returns.rds", ".cache/book_nav.parquet",
            "06_Registry/book_carrier", "qepm/registry/backtest_registry.csv")) {
  say("  %-42s %s", p, if (file.exists(p) || dir.exists(p)) "존재" else "부재")
}
if (dir.exists("06_Registry/book_carrier")) {
  f <- list.files("06_Registry/book_carrier", full.names = FALSE)
  say("  book_carrier 내용 %d건: %s", length(f), paste(head(f, 8), collapse=", "))
}

## ---- 3. 검정력 사전 계산 (§4 book-marginal ΔIR >= 0.05) ---------------------
say("=== 3. 착수 전 검정력 — ΔIR 문턱 0.05 를 검출할 수 있나 ===")
source("02_Infrastructure/contracts/required_effect_size.R")
say("  measurement-graduation §4: admission = book-marginal **ΔIR >= 0.05**")
say("  ΔIR 은 비율량이라 required_effect(수익 단위)와 직접 대응 안 됨 — 대리 지표로 paired 월 활성수익 차이를 쓴다")
for (n in c(268L, 283L)) {
  for (sd_m in c(0.010, 0.017, 0.026)) {
    r <- required_effect(n = n, t_threshold = 2.0, sd_monthly = sd_m, design = "full")
    say("  n=%d sd=%.3f : 필요 월 %.5f = 연 %.2f%%", n, sd_m, r$required_monthly, r$required_annual*100)
  }
}
say("  ★M26 실측 참고: FMB 효과 연 2.004%% · canonical top-25 alpha_ann 5.86%%(net)")
say("  ★비교 선례: MAX5 필터 ΔIR +0.1692 (문턱 0.05 의 3.4배) — 이 저장소 필터면 유일 성공")

say("=== 4. 착수 자격 판정 (사전 고정) ===")
say("  ①production base 파생 경로 확보 : 위 실측으로 판정")
say("  ②검정력 : 관측 가능 효과가 위 바를 넘을 개연")
say("  ★①이 안 되면 착수 금지 — 재구성 base 로 측정하면 FQ-127 이 경고한 부호 반전 재생산")
say("=== P0 완료 ===")
