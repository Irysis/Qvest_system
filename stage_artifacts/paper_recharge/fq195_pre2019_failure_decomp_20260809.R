#!/usr/bin/env Rscript
# fq195_pre2019_failure_decomp_20260809.R — FQ-195: pre2019 파싱 실패 1147건의 **사유 분해**.
#
# ★왜: 계약 lane 전체가 여기서 막혀 있다. FQ-193 의 w_amt 는 커버-시대 구조적 교락으로 확립 불가이고,
#   교락을 깰 독립 구간(2005~2016)이 파서에 막혀 있다. 인코딩은 이미 배제됨
#   (파서 v3 CP949 수리 09:08 < 파싱 09:51 < stage1 측정 12:06 — 수리 이후 수치).
# ★목표: 실패가 **단일 서식 사유**로 몰리면 전용 분기로 열 수 있고,
#   '규정상 필드 자체가 없음'이면 능력 게이트를 폐쇄하고 lane 을 2019+ scoped 로 확정한다.
#   두 결과 모두 정보값이 크다(열리면 두 FQ 동시 해소, 닫히면 lane 범위 확정).
# 자본 판정 아님(metric_type=diagnostic).
suppressMessages({ library(data.table); library(jsonlite) })
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(...) cat(sprintf(...), "\n", sep = "")

CK <- ".cache/dart/contract_backfill"
fs <- list.files(CK, pattern = "^\\d{6}\\.csv$", full.names = TRUE)
if (!length(fs)) { say("★체크포인트 부재: %s — 분해 불가", CK); quit(status = 0) }
say("체크포인트 %d개월 파일", length(fs))
raw <- rbindlist(lapply(fs, function(f) fread(f, colClasses = list(character = "corp_code"))), fill = TRUE)
D <- raw[!is.na(rcept_no)]
say("총 %d행 · 컬럼: %s", nrow(D), paste(names(D), collapse = ", "))

NO_SOURCE <- c("NO_SOURCE_CORRECTION", "NO_SOURCE_014")
D[, era := fifelse(ym >= 201901L, "usable_2019plus", "pre2019")]
say("\n=== era × parse_status ===")
tb <- D[, .N, by = .(era, parse_status)][order(era, -N)]
print(tb)

PRE <- D[era == "pre2019"]
say("\n=== ★pre2019 실패 사유 분해 (n=%d) ===", nrow(PRE))
f <- PRE[!parse_status %in% c("OK", NO_SOURCE), .N, by = parse_status][order(-N)]
f[, share := round(N / sum(N), 4)]
print(f)
say("  최다 사유 = %s (%d건, %.1f%%)", f$parse_status[1], f$N[1], 100 * f$share[1])
say("  상위 2사유 누적 %.1f%% · 상위 3사유 %.1f%%",
    100 * sum(head(f$share, 2)), 100 * sum(head(f$share, 3)))

say("\n=== 연도별 pre2019 성공률 (규정 변경 시점 탐지) ===")
PRE[, yr := ym %/% 100L]
byy <- PRE[, .(rows = .N, ok = sum(parse_status == "OK"),
               ok_pct = round(100 * mean(parse_status == "OK"), 1)), by = yr][order(yr)]
print(byy)
say("  ★성공률이 특정 연도에서 계단식으로 바뀌면 = 서식/규정 전환점")

say("\n=== 2019+ 대조 (같은 사유가 거기서도 나오나) ===")
POST <- D[era == "usable_2019plus"]
fp <- POST[!parse_status %in% c("OK", NO_SOURCE), .N, by = parse_status][order(-N)]
if (nrow(fp)) { fp[, share := round(N / sum(N), 4)]; print(head(fp, 6)) } else say("  2019+ 실패 0")
say("  ★pre2019 최다 사유가 2019+ 에서도 흔하면 서식 문제가 아니라 **일반 결함**이다(수리 가능성 ↑)")

top <- f$parse_status[1]
in_post <- if (nrow(fp)) fp[parse_status == top]$share else numeric(0)
verdict <- if (length(f$share) && f$share[1] >= 0.60) {
  if (length(in_post) && in_post >= 0.30)
    "OPENABLE — 단일 사유가 pre2019 60%+ 이고 2019+ 에서도 흔함 = 서식 아닌 일반 결함. 전용 수리로 열릴 가능성."
  else "FORMAT_SPECIFIC — 단일 사유가 pre2019 60%+ 이나 2019+ 엔 드묾 = 서식/규정 고유. 전용 분기 필요(비용 재산정)."
} else "DISPERSED — 실패 사유가 분산. 단일 수리로 못 연다 → 능력 게이트 폐쇄 후보(lane 을 2019+ scoped 로 확정)."
say("\n★판별: %s", verdict)

write(toJSON(list(schema = "fq195_pre2019_decomp_v1", date = "20260809", metric_type = "diagnostic",
  total_rows = nrow(D), pre2019_rows = nrow(PRE),
  era_status = lapply(seq_len(nrow(tb)), function(i) as.list(tb[i])),
  pre2019_failure_reasons = lapply(seq_len(nrow(f)), function(i) as.list(f[i])),
  pre2019_by_year = lapply(seq_len(nrow(byy)), function(i) as.list(byy[i])),
  post2019_failure_reasons = if (nrow(fp)) lapply(seq_len(min(6, nrow(fp))), function(i) as.list(fp[i])) else list(),
  top_reason = top, top_share = if (length(f$share)) f$share[1] else NA_real_,
  verdict = verdict), pretty = TRUE, auto_unbox = TRUE, na = "null"),
  "stage_artifacts/paper_recharge/fq195_pre2019_decomp_20260809.json")
say("\n저장: stage_artifacts/paper_recharge/fq195_pre2019_decomp_20260809.json")
