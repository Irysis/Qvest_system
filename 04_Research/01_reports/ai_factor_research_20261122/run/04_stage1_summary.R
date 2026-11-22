## 04_stage1_summary.R — 단계 1 결과 한 통(텔레그램 · 세션 보고용 요약). 숫자는 결과 표에서만 읽는다(손으로 적지 않는다).
##   읽는 것: results/selftest_measurer.json · results/stage1/common_period_perf.csv · factor_db_misc.csv · 두 실행이 남긴 그림 목록
##   쓰는 것: .cache/aif_research/stage_summary_stage1.json (진행 알림 스크립트의 --summary 입력) · results/stage1/SUMMARY.md(같은 내용의 글)
##   실행: Rscript run/04_stage1_summary.R ["머리말 한 줄"]
here <- function() {   # 이 스크립트가 든 폴더의 위 폴더(연구 폴더). 경로 정규화 함수는 쓰지 않는다 — 구분자만 맞춘다
  a <- commandArgs(FALSE); f <- gsub("\\\\", "/", sub("^--file=", "", a[grepl("^--file=", a)])[1])
  if (!grepl("^([A-Za-z]:)?/", f)) f <- file.path(getwd(), f)
  dirname(dirname(f))
}
D <- here()
source(file.path(D, "R", "aif_common.R"))
root <- aif_root(); cfg <- aif_cfg(root); lead <- commandArgs(TRUE)[1]
RES <- function(...) aif_results("stage1", ..., root = root, cfg = cfg)
num <- function(x, d = 2) formatC(x, format = "f", digits = d); pct <- function(x) sprintf("%+.1f%%", 100 * x)
st <- fromJSON(aif_results("selftest_measurer.json", root = root, cfg = cfg), simplifyVector = FALSE)
C <- fread(RES("common_period_perf.csv"), encoding = "UTF-8"); MI <- fread(RES("factor_db_misc.csv"), encoding = "UTF-8")
from <- substr(min(C[period == "ALL", start]), 1L, 7L); bl <- cfg$measure$benchmark_label
g <- function(k, port, per) C[kind %in% k & portfolio == port & period == per]
best <- function(x) x[which.max(SR)]
rank_in <- function(port, per, id) { e <- g("개별 팩터", port, per)$SR; 1L + sum(e > g("새 팩터", port, per)[factor == id, SR]) }
n_ind <- MI[kind == "개별 팩터", .N]; n_cmp <- MI[kind != "개별 팩터", .N]; n_new <- uniqueN(g("새 팩터", "top", "ALL")$factor)

bm <- g("벤치마크", "top", "ALL"); tot <- C[factor == "CAT_TOTAL" & portfolio == "top" & period == "ALL"]
nt <- best(g("새 팩터", "top", "ALL")); nl <- best(g("새 팩터", "ls", "ALL")); cl <- best(g(c("카테고리 합성", "전체 합성"), "ls", "ALL"))
o <- g("새 팩터", "ls", "OOS")[order(-SR)]; ot <- g("새 팩터", "top", "OOS")[order(-SR)]
beat_top <- g("새 팩터", "top", "ALL")[SR > tot$SR, .N]; neg_oos <- o[SR < 0, factor]
lines <- c(
  sprintf("측정기 자가 시험 %d건 통과 · 새 팩터 %d개 · 기존 개별 팩터 %d개 · 기존 합성 %d개를 같은 방식으로 측정(전 종목 5분위 · 거래비용 전)", length(st$tests), n_new, n_ind, n_cmp),
  sprintf("공통 기간(%s ~) 상위 분위 롱온리 SR — %s %s · 기존 전체 합성 %s · 새 팩터 최고 %s %s (기존 전체 합성을 넘는 새 팩터 %d개)", from, bl, num(bm$SR), num(tot$SR), nt$factor, num(nt$SR), beat_top),
  sprintf("같은 기간 롱숏 SR — 새 팩터 최고 %s %s · 기존 합성 최고 %s %s", nl$factor, num(nl$SR), sub("^CAT_", "", cl$factor), num(cl$SR)),
  sprintf("OOS(2023-01 ~) 롱숏 SR — %s %s(기존 %d개 가운데 %d위) · %s %s(%d위)%s", o$factor[1], num(o$SR[1]), n_ind, rank_in("ls", "OOS", o$factor[1]),
          o$factor[2], num(o$SR[2]), rank_in("ls", "OOS", o$factor[2]), if (length(neg_oos)) sprintf(" · 음수 = %s", paste(neg_oos, collapse = " · ")) else ""),
  sprintf("OOS 상위 분위 롱온리 — %s CAGR %s · 새 팩터 최고 %s CAGR %s(SR %s)", bl, pct(g("벤치마크", "top", "OOS")$CAGR), ot$factor[1], pct(ot$CAGR[1]), num(ot$SR[1])),
  "그림 순서 = 새 팩터 성과표(전기간 · IS · OOS · 롱숏) → 공통 기간 비교표 → 기존 팩터 가운데 순위 → P/L 격자 → 분포 · P/L 비교 → 팩터별 상세")
if (!is.na(lead) && nzchar(lead)) lines <- c(lead, lines)

sm <- function(f) { x <- fromJSON(aif_out(f, root = root, cfg = cfg), simplifyVector = FALSE); list(p = unlist(x$charts), n = unlist(x$chart_names)) }
a <- sm("stage_summary_perf_new.json"); b <- sm("stage_summary_perf_db.json")
is_tab <- grepl("table_", basename(a$p)); is_grid <- grepl("grid_", basename(a$p)); is_cmp <- grepl("table_common", basename(b$p)); is_pos <- grepl("table_position", basename(b$p))
ord <- function(x, k) list(p = x$p[k], n = x$n[k])
parts <- list(ord(a, is_tab), ord(b, is_cmp), ord(b, is_pos), ord(a, is_grid), ord(b, !is_cmp & !is_pos), ord(a, !is_tab & !is_grid))
charts <- unlist(lapply(parts, `[[`, "p")); names_ <- unlist(lapply(parts, `[[`, "n"))
aif_write_json(list(at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"), title = "단계 1 결과 — 새 팩터 6개와 기존 팩터 DB 비교", lines = as.list(lines),
                    charts = as.list(charts), chart_names = as.list(names_)), aif_out("stage_summary_stage1.json", root = root, cfg = cfg))
aif_write_atomic(RES("SUMMARY.md"), function(p) writeLines(c("# 단계 1 결과 요약", "", sprintf("만든 때: %s", format(Sys.time(), "%Y-%m-%d %H:%M")), "", paste0("- ", lines), "",
                                                              "표: `new_factors_perf.csv` · `common_period_perf.csv` · `factor_db_perf.csv` · `new_vs_db_position.csv` · `new_vs_db_overlap.csv`", "그림: `charts/`"), p, useBytes = TRUE))
cat(paste0(lines, collapse = "\n"), "\n"); cat(sprintf("[aif] 그림 %d장 · 요약 저장\n", length(charts)))
