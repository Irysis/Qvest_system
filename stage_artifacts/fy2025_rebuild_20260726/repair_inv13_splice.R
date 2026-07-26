# repair_inv13_splice.R — 범위-재빌드가 떨어뜨린 INV13 3변형 복원
#
# 기전 (2026-07-26 실측 확인):
#   compute_investor.R 의 INV13 은 **프로세스-수명 누산기** .fdb_env$INV13_BETA_ACC 에
#   의존한다(expanding no-intercept OLS). 누산기는 compute_investor() 호출 1회당 n_months+1
#   (writer = compute_investor.R:422 `assign(inv13_beta_cache_key, ...)` — 변수 경유라
#   리터럴 grep 으로는 안 잡힌다). burn-in 은 **한 프로세스 안에서의 호출 60회**이므로,
#   61개월 미만을 재빌드하면 beta_lagged = NA → return(NULL) → INV13 3변형이 **조용히 소실**된다.
#   (07-25 전량 재빌드 434개월은 burn-in 충족 → 존재. 07-26 5개월 범위 재빌드 → 소실.)
#
# 복원이 정확한 근거:
#   ① INV13 은 fundamental 의존이 **없다** (compute_investor 시그니처의 FUND 미사용,
#      데이터원 = investor_wide.parquet — 2026-07-17 이후 무변경). FY2025 백필과 무관.
#   ② .standardize_factors() 는 winsorize/z 를 `by = Factor_Name`,
#      sector-z 를 `by = .(Factor_Name, Sector)` 로 계산 → INV13 표준화값은 타 팩터와 독립.
#   ③ 양측 ticker 집합 동일(사전 검사) → pin 의 INV13 행이 전량 재빌드가 산출했을 값과 동일.
#
# 안전: temp-rename 쓰기(가드레일 ②). 사전/사후 팩터집합 parity 검사 + 위반 주입 통제(가드레일 ⑤).

suppressPackageStartupMessages({ library(data.table); library(arrow) })
QM  <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PIN <- file.path(QM, ".cache", "pins", "fy2025_rebuild_20260726")
FDB <- file.path(QM, ".cache", "factor_db")
YMS <- c("202603","202604","202605","202606","202607")
INV13 <- c("INV13_Foreign_Resid_Individual_21d",
           "INV13_Foreign_Resid_Individual_63d",
           "INV13_Foreign_Resid_Individual_126d")

# ── 판정부: 재빌드 전후 팩터집합 parity (순수 함수 — 주입 가능) ────────────────
factor_parity <- function(old_names, new_names) {
  miss <- setdiff(old_names, new_names); added <- setdiff(new_names, old_names)
  list(ok = length(miss) == 0L, missing = miss, added = added)
}

# ── 위반 주입 통제 (가드레일 ⑤): 판정부가 진짜 결손에 발화하는지 ──────────────
cat("=== 위반 주입 통제 ===\n")
.base <- c("A","B","C")
.t1 <- factor_parity(.base, .base)                 # 음성 통제: 동일 → ok
.t2 <- factor_parity(.base, setdiff(.base, "B"))   # 주입: 결손 → FAIL 이어야
.t3 <- factor_parity(.base, c(.base, "D"))         # 추가만 → ok(결손 아님)
stopifnot(isTRUE(.t1$ok), !isTRUE(.t2$ok), identical(.t2$missing, "B"), isTRUE(.t3$ok))
cat("  [PASS] 동일→ok / 결손주입→FAIL(missing=B) / 추가만→ok  (판정부 차단 실효 확인)\n\n")

report <- list()
for (ym in YMS) {
  fp_new <- file.path(FDB, sprintf("factor_db_%s.parquet", ym))
  fp_old <- file.path(PIN, sprintf("factor_db_%s.parquet", ym))
  stopifnot(file.exists(fp_new), file.exists(fp_old))

  new_dt <- as.data.table(read_parquet(fp_new))
  old_dt <- as.data.table(read_parquet(fp_old))

  par0 <- factor_parity(unique(old_dt$Factor_Name), unique(new_dt$Factor_Name))
  cat(sprintf("[%s] 사전 parity: ok=%s | missing=%s\n", ym, par0$ok,
              if (length(par0$missing)) paste(par0$missing, collapse=",") else "-"))

  # 복원 대상 = 사전 결손 중 INV13 3변형에 한정 (그 외 결손이 있으면 중단 — 미지 원인)
  unexpected <- setdiff(par0$missing, INV13)
  if (length(unexpected)) stop(sprintf("[%s] 예상 밖 결손 %s — 원인 규명 전 복원 금지",
                                       ym, paste(unexpected, collapse=",")))
  if (par0$ok) { cat(sprintf("[%s] 결손 없음 — skip\n", ym)); next }

  inv_rows <- old_dt[Factor_Name %chin% INV13]
  # 무결성 전제: 컬럼 동일 + 복원 ticker ⊆ 신 파일 ticker
  stopifnot(identical(sort(names(old_dt)), sort(names(new_dt))))
  tick_ok <- all(unique(inv_rows$Ticker) %chin% unique(new_dt$Ticker))
  # Date 컬럼 = 해당 sig_date 로 동일해야 함
  date_ok <- identical(unique(as.Date(inv_rows$Date)), unique(as.Date(new_dt$Date)))
  cat(sprintf("[%s] 복원행 %s | ticker⊆new=%s | Date일치=%s\n",
              ym, format(nrow(inv_rows), big.mark=","), tick_ok, date_ok))
  stopifnot(tick_ok, date_ok)

  setcolorder(inv_rows, names(new_dt))
  out <- rbindlist(list(new_dt, inv_rows), use.names = TRUE)
  setorder(out, Factor_Name, Ticker)

  par1 <- factor_parity(unique(old_dt$Factor_Name), unique(out$Factor_Name))
  stopifnot(isTRUE(par1$ok))

  tmp <- paste0(fp_new, ".tmp")                       # 가드레일 ②: temp → rename
  write_parquet(out, tmp)
  stopifnot(file.exists(tmp), file.size(tmp) > 1e6)
  ok <- file.rename(tmp, fp_new); stopifnot(ok)

  chk <- as.data.table(read_parquet(fp_new, col_select = c("Factor_Name")))
  par2 <- factor_parity(unique(old_dt$Factor_Name), unique(chk$Factor_Name))
  cat(sprintf("[%s] 사후 parity: ok=%s | 팩터수 %d→%d | 행수 %s\n\n", ym, par2$ok,
              uniqueN(new_dt$Factor_Name), uniqueN(chk$Factor_Name),
              format(nrow(out), big.mark=",")))
  stopifnot(isTRUE(par2$ok))
  report[[ym]] <- list(restored_rows = nrow(inv_rows),
                       factors_before = uniqueN(new_dt$Factor_Name),
                       factors_after = uniqueN(chk$Factor_Name))
}
cat("=== INV13 복원 완료 ===\n"); print(rbindlist(lapply(names(report), function(k)
  data.table(ym = k, restored_rows = report[[k]]$restored_rows,
             factors_before = report[[k]]$factors_before,
             factors_after = report[[k]]$factors_after))))
