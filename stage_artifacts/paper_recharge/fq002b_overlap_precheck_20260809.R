#!/usr/bin/env Rscript
# fq002b_overlap_precheck_20260809.R — FQ-002 (B) 배제형 필터 라운드 착수 전 겹침률 확인.
#
# ★왜 이게 첫 항목인가: FQ-170 아크의 최대 교훈 = "판정을 바꾼 건 매번 데이터가 아니라 통제"이고
#   그 중 첫째가 **겹침률**(음성대조가 항등식이었던 사고). book top-25 중 계약 패널에 있는 종목이
#   거의 없으면 배제형 필터는 **발화조차 못 하고**, 그때 나오는 ΔIR≈0 은 '효과 없음'이 아니라
#   '측정 안 됨'이다. 두 상태는 겉보기가 같다.
# 자본 판정 아님(metric_type=diagnostic).
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(...) cat(sprintf(...), "\n", sep = "")

mt  <- fromJSON("06_Registry/book_carrier/carrier_meta.json", simplifyVector = FALSE)
car <- as.data.table(read_parquet(as.character(mt$parquet)))
car[, `:=`(decision_date = as.Date(decision_date), eval_date = as.Date(eval_date))]
car <- car[selected == TRUE & !is.na(ret_fwd)]
car[, ym := as.integer(format(decision_date, "%Y%m"))]   # 홀딩월 = month(decision_date)

P <- as.data.table(read_parquet("04_Research/method_frontier/fq002_contract_magnitude/panelx_B_corrected.parquet"))
P[, ym := as.integer(ym)]
say("캐리어 %d개월(%d~%d) · 계약패널 %d개월(%d~%d) · 패널 종목 %d",
    uniqueN(car$ym), min(car$ym), max(car$ym), uniqueN(P$ym), min(P$ym), max(P$ym), uniqueN(P$Ticker))

# ★신호 = w_ratio (12M 창 계약금액/최근매출액 비율 — 패널의 primary 후보). 비영 100%.
#   시총-분모 셀은 별도 조인이 필요하므로 본 겹침 확인은 신호 존재 여부만 본다.
ov_ym <- intersect(unique(car$ym), unique(P$ym))
say("공통 홀딩월 %d개 (%d ~ %d)", length(ov_ym), min(ov_ym), max(ov_ym))
if (length(ov_ym) < 12) { say("★공통월 <12 — 라운드 성립 불가"); quit(status = 0) }

C <- car[ym %in% ov_ym]
setorder(C, ym, rank)
C25 <- C[rank <= 25]
say("book top-25 행 %d (월평균 %.1f)", nrow(C25), nrow(C25) / uniqueN(C25$ym))

M <- merge(C25[, .(ym, Ticker, rank)], P[, .(ym, Ticker, w_ratio, w_amt, n_contracts)],
           by = c("ym", "Ticker"), all.x = TRUE)
M[, has_sig := !is.na(w_ratio)]
byym <- M[, .(n_held = .N, n_cov = sum(has_sig), cov = mean(has_sig)), by = ym][order(ym)]

say("\n=== 겹침률: book top-25 중 계약 신호 보유 ===")
say("  전체 평균 %.1f%% · 중앙 %.1f%% · 최소 %.1f%% · 최대 %.1f%%",
    100 * mean(byym$cov), 100 * median(byym$cov), 100 * min(byym$cov), 100 * max(byym$cov))
say("  월평균 커버 종목 %.1f / 25", mean(byym$n_cov))
say("  커버 0종인 달: %d / %d", byym[n_cov == 0, .N], nrow(byym))
say("\n연도별:")
byym[, yr := substr(as.character(ym), 1, 4)]
print(byym[, .(n_months = .N, mean_cov_n = round(mean(n_cov), 1), mean_cov_pct = round(100 * mean(cov), 1)), by = yr])

say("\n=== 발화 가능성: 하위 3분위 제외 시 실제로 빠지는 종목 수 ===")
M2 <- M[has_sig == TRUE]
M2[, q := cut(frank(w_ratio, ties.method = "average") / .N, breaks = c(0, .3, .7, 1), labels = c("low", "mid", "high")), by = ym]
drop <- M2[q == "low", .(n_drop = .N), by = ym]
allym <- data.table(ym = byym$ym); drop <- merge(allym, drop, by = "ym", all.x = TRUE)
drop[is.na(n_drop), n_drop := 0L]
say("  월평균 제외 %.2f 종목 / 25 (중앙 %d · 0인 달 %d/%d)",
    mean(drop$n_drop), as.integer(median(drop$n_drop)), drop[n_drop == 0, .N], nrow(drop))

verdict <- if (mean(byym$cov) < 0.10) "ABORT — 겹침 <10%, 필터 발화 불가(측정 안 됨을 효과 없음으로 읽을 위험)" else
           if (mean(drop$n_drop) < 1.0) "WEAK — 월평균 제외 <1종목, 효과 크기가 구조적으로 작음(사전등록에 명시)" else
           "PROCEED — 겹침·발화 충분"
say("\n★착수 판정: %s", verdict)

out <- list(schema = "fq002b_overlap_precheck_v1", date = "20260809", metric_type = "diagnostic",
            n_common_months = length(ov_ym), window = c(min(ov_ym), max(ov_ym)),
            coverage = list(mean_pct = round(100 * mean(byym$cov), 2),
                            median_pct = round(100 * median(byym$cov), 2),
                            mean_names = round(mean(byym$n_cov), 2),
                            zero_months = byym[n_cov == 0, .N]),
            firing = list(mean_drop = round(mean(drop$n_drop), 3),
                          zero_drop_months = drop[n_drop == 0, .N], n_months = nrow(drop)),
            verdict = verdict)
write(toJSON(out, pretty = TRUE, auto_unbox = TRUE, na = "null"),
      "stage_artifacts/paper_recharge/fq002b_overlap_precheck_20260809.json")
say("저장: stage_artifacts/paper_recharge/fq002b_overlap_precheck_20260809.json")
