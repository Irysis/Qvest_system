#!/usr/bin/env Rscript
# fq193_field_precheck_20260809.R — FQ-193 착수 전: 커버 종목 안에서 각 필드가 **분위 분할 가능한가**.
# ★대부분 0 인 필드는 frank 가 동률 덩어리라 하위/상위 3분위가 임의로 갈린다 = 신호가 아니라 잡음 배정.
#   측정 전에 떨어뜨려야 다중검정 부담이 준다.
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(...) cat(sprintf(...), "\n", sep = "")

mt  <- fromJSON("06_Registry/book_carrier/carrier_meta.json", simplifyVector = FALSE)
car <- as.data.table(read_parquet(as.character(mt$parquet)))
car[, `:=`(decision_date = as.Date(decision_date), eval_date = as.Date(eval_date))]
car <- car[selected == TRUE & !is.na(ret_fwd)]
car[, ym := as.integer(format(decision_date, "%Y%m"))]
P <- as.data.table(read_parquet("04_Research/method_frontier/fq002_contract_magnitude/panelx_B_corrected.parquet"))
P[, ym := as.integer(ym)]
shift_ym <- function(y) { yr <- y %/% 100L; mo <- y %% 100L + 1L
  yr <- yr + (mo - 1L) %/% 12L; mo <- ((mo - 1L) %% 12L) + 1L; yr * 100L + mo }
P[, ym_use := shift_ym(ym)]

FLD <- c("n_contracts", "amt_sum", "ratio_rev_sum", "amend_n", "round_n", "fx_n",
         "w_n", "w_amt", "w_ratio", "w_amend")
C <- merge(car, P[, c("ym_use", "Ticker", FLD), with = FALSE],
           by.x = c("ym", "Ticker"), by.y = c("ym_use", "Ticker"), all.x = TRUE)
C[, covered := !is.na(w_ratio)]
CV <- C[covered == TRUE]
say("커버 행 %d · 개월 %d · 월평균 %.2f종", nrow(CV), uniqueN(CV$ym), nrow(CV)/uniqueN(CV$ym))

say("\n=== 커버 종목 안에서의 필드 분포 (분위 분할 가능성) ===")
res <- rbindlist(lapply(FLD, function(f) {
  v <- CV[[f]]
  # 월별 고유값 개수 — 1이면 그 달은 분할 불가
  u <- CV[, .(nu = uniqueN(get(f)), n = .N), by = ym]
  data.table(field = f,
             zero_share = round(mean(v == 0, na.rm = TRUE), 3),
             uniq_overall = uniqueN(v),
             mean_uniq_per_month = round(mean(u$nu), 2),
             months_no_split = u[nu <= 1, .N],
             n_months = nrow(u))
}))
res[, splittable := months_no_split / n_months < 0.25 & mean_uniq_per_month >= 2.5]
print(res)

cat("\n★판정 규칙(사전): 커버 안 0비율 >0.60 또는 분할불가 월 >25% 또는 월평균 고유값 <2.5 → **측정 제외**\n")
keep <- res[splittable == TRUE & zero_share <= 0.60]$field
drop <- setdiff(FLD, keep)
say("  측정 대상 %d: %s", length(keep), paste(keep, collapse = ", "))
say("  제외      %d: %s", length(drop), paste(drop, collapse = ", "))
cat("\n※ w_ratio 는 FQ-002(B)에서 사전등록 F1 반증으로 판정 종료 — 재측정 대상 아님(재탕 금지).\n")

# ★중복 확인 — 창만 다른 같은 재료면 독립 검정이 아니다(다중검정 부담만 늘고 정보는 안 는다)
say("\n=== 측정 대상 후보 간 상관 (커버 행 기준, Spearman) ===")
cand <- setdiff(keep, "w_ratio")
if (length(cand) >= 2) {
  M <- as.matrix(CV[, ..cand])
  S <- suppressWarnings(cor(M, method = "spearman", use = "pairwise.complete.obs"))
  print(round(S, 3))
  say("\n★|rho|>0.90 쌍은 같은 재료의 창 변형 — 하나만 대표로 측정한다(다중검정 부담 축소).")
  for (a in seq_along(cand)) for (b in seq_along(cand)) if (b > a && is.finite(S[a, b]) && abs(S[a, b]) > 0.90)
    say("   중복: %s ↔ %s (rho %.3f)", cand[a], cand[b], S[a, b])
}
say("\n=== w_ratio(판정종료) 와의 상관 — 새 정보인가 ===")
for (f in cand) {
  r <- suppressWarnings(cor(CV[[f]], CV$w_ratio, method = "spearman", use = "pairwise.complete.obs"))
  say("   %-14s vs w_ratio rho %+.3f %s", f, r,
      if (is.finite(r) && abs(r) > 0.90) "← 사실상 같은 신호(측정 가치 없음)" else "")
}

write(toJSON(list(schema = "fq193_field_precheck_v1", date = "20260809", metric_type = "diagnostic",
                  covered_rows = nrow(CV), n_months = uniqueN(CV$ym),
                  fields = lapply(seq_len(nrow(res)), function(i) as.list(res[i])),
                  keep = keep, drop = drop,
                  already_judged = "w_ratio (FQ-002 B, F1 반증)"),
            pretty = TRUE, auto_unbox = TRUE, na = "null"),
      "stage_artifacts/paper_recharge/fq193_field_precheck_20260809.json")
say("저장: stage_artifacts/paper_recharge/fq193_field_precheck_20260809.json")
