#!/usr/bin/env Rscript
# extract_book_carrier_d3.R — 현 PG2(STR_1715_on_M4gAE_R05_noLayer4_PG2)의 A/B 캐리어 (도훈 승인 1안, 2026-08-08).
#
# 배경(08-08 도훈 적발): Σ-A/B 배터리가 구 PG2(2-1, overlay+Layer4) 캐리어를 기준선으로 7주 사용.
#   현 PG2 는 2-4(M4∩AE D3 게이트, Layer4 제거 — 2026-07-02 도훈 FINAL). per-stock 이력 부재로 미해결이었다.
#
# ★설계 — 실측이 확정한 세 사실 위에 선다:
#   F1. 북 시계열(live_book_series·incumbent_book_ir 1.416)의 base 는 tophi 판 비중이다
#       (2-1 캐리어 w21 vs ret_orig: cor 0.999973, MAD 0.13%). → per-stock 은 2-1 캐리어를
#       **재사용하는 것이 §7b 정합**이다(북이 실제 한 것). 재계산이 아니라 재사용이 정답.
#   F2. 2-1 캐리어와 현 PG2 의 차이는 전부 **오버레이**다(선별·비중·종목수익 동일):
#       구 = m4 × beta_threshold(Layer4) × beta_R05_V5  /  신 = (m4→D3 gate 전환분) × beta_R05.
#       신 노출은 live_book_series 의 beta_R05·m4 컬럼이 **북 실측값**으로 이미 보유(271m).
#   F3. forward 생성기(단순 .tilt)와 북 기록 체계(tophi)의 불일치는 **별도 결함**(칩 task_fea61227)
#       — 본 캐리어는 북 기록 체계를 따른다(기준선의 정의가 그것이므로).
#
# 산출:
#   06_Registry/book_carrier/carrier_STR_1715_on_M4gAE_R05_noLayer4_PG2.parquet
#     (per-stock: decision/eval/Ticker/score/weight_strategy/ret_fwd/rank/selected/regime — 2-1 내용
#      + invested/dR05: 북 실측 오버레이 노출)
#   carrier_meta.json 갱신 (strategy=현 admitted → pg2_coherence C2·C3 해소)
# 검증(fail-closed): invested×Σ(w×ret_fwd) − dR05×0.0015 vs 시리즈 ret_net — cor<0.999 시 저장 거부.
#
# 단일스레드 권장: OMP_NUM_THREADS=1 ARROW_NUM_THREADS=1.
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b
root <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
if (dir.exists(root)) setwd(root)

# 1) 권위 확인 — resolver 경유 (C5 우회 금지의 자기 준수)
source("02_Infrastructure/portfolio/resolve_admitted_slot.R")
slot <- resolve_admitted_slot(strict = TRUE, quiet = TRUE)
ADMIT <- slot$id
stopifnot(identical(ADMIT, "STR_1715_on_M4gAE_R05_noLayer4_PG2"))   # 본 빌더는 이 PG2 전용 — 다른 admit 이면 설계 재검토
cat(sprintf("[d3-carrier] admitted = %s (slot %s)\n", ADMIT, slot$slot))

# 2) 입력
SRC_CAR <- "06_Registry/book_carrier/carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet"   # per-stock 원천(F1 검증됨)
LBS     <- sprintf("06_Registry/live_track/%s/live_book_series.csv", ADMIT)                # 북 실측 노출·검증 정답지
for (p in c(SRC_CAR, LBS)) if (!file.exists(p)) stop("[d3-carrier] 입력 부재: ", p)
car <- as.data.table(read_parquet(SRC_CAR))
car[, `:=`(decision_date = as.Date(decision_date), eval_date = as.Date(eval_date))]
lbs <- fread(LBS)
need <- c("realized_ym", "ret_net", "ret_orig", "beta_R05", "m4", "dR05")
stopifnot(all(need %in% names(lbs)))
COST_DBETA <- 0.0015   # extend_nolayer4_series.R:78 산식의 |Δβ| 비용 (per-layer 규약)

# 3) 결합: eval_date 의 실현월 ↔ 시리즈 realized_ym
car[, ym := format(eval_date, "%Y-%m")]
ov <- lbs[, .(ym = realized_ym, invested = as.numeric(beta_R05) * as.numeric(m4),
              dR05 = as.numeric(dR05), ret_net_book = as.numeric(ret_net), ret_orig_book = as.numeric(ret_orig))]
d3 <- merge(car, ov, by = "ym", all.x = TRUE)
n_nomatch <- d3[is.na(invested), uniqueN(ym)]
if (n_nomatch > 0) {
  cat(sprintf("[d3-carrier] ★노출 미매칭 %d개월: %s — 해당 월 제외(결측을 1.0 으로 내려앉히지 않는다)\n",
              n_nomatch, paste(head(d3[is.na(invested), unique(ym)], 6), collapse = ", ")))
  d3 <- d3[!is.na(invested)]
}

# 4) 검증 (fail-closed) — 북 시계열 재현
chk <- d3[, .(r_base = sum((weight_strategy / sum(weight_strategy)) * ret_fwd),
              invested = invested[1], dR05 = dR05[1],
              ret_net_book = ret_net_book[1], ret_orig_book = ret_orig_book[1]), by = ym]
chk[, ret_net_hat := invested * r_base - dR05 * COST_DBETA]
c_base <- cor(chk$r_base, chk$ret_orig_book)
c_net  <- cor(chk$ret_net_hat, chk$ret_net_book)
mad_net <- median(abs(chk$ret_net_hat - chk$ret_net_book))
cat(sprintf("[검증] base 재현 cor=%.6f · net 재현 cor=%.6f · net MAD=%.5f (%d개월)\n",
            c_base, c_net, mad_net, nrow(chk)))
if (c_base < 0.999 || c_net < 0.999) {
  stop(sprintf("[d3-carrier] 재현 실패 (base %.6f / net %.6f < 0.999) — 저장 거부. 산식 또는 매칭 오류.", c_base, c_net))
}

# 5) 저장 + 메타 갱신
OUT <- sprintf("06_Registry/book_carrier/carrier_%s.parquet", ADMIT)
keep <- c("decision_date", "eval_date", "regime", "Ticker", "score", "weight_strategy",
          "ret_fwd", "rank", "selected", "invested", "dR05")
write_parquet(d3[, ..keep], OUT)
cat(sprintf("[d3-carrier] 저장 %s — %d행 · %d개월 (%s ~ %s)\n", OUT, nrow(d3), uniqueN(d3$ym),
            min(d3$ym), max(d3$ym)))

bs <- fromJSON("qepm/mailbox/governor/book_state.json", simplifyVector = FALSE)
meta <- list(
  strategy = ADMIT,
  per_stock_source = SRC_CAR,
  per_stock_provenance = "F1: 북 시계열 base = tophi 판 실측(w21 vs ret_orig cor 0.999973) — 재사용이 §7b 정합. 선별·비중·ret_fwd 는 2-1 캐리어와 동일(차이는 오버레이뿐)",
  overlay_source = LBS,
  overlay_def = "invested = beta_R05 × m4 (북 실측, D3 gate 전환 반영분). 비용 = dR05 × 0.0015 (extend_nolayer4_series.R:78)",
  forward_tilt_mismatch_note = "forward 생성기(단순 .tilt)와 북 기록 체계(tophi)의 불일치는 별도 결함(칩 task_fea61227) — 본 캐리어는 북 기록 체계 기준",
  validation = list(base_reproduction_cor = round(c_base, 6), net_reproduction_cor = round(c_net, 6),
                    net_mad = round(mad_net, 6), months = nrow(chk)),
  n_months = uniqueN(d3$ym), n_rows = nrow(d3),
  ym_min = min(d3$ym), ym_max = max(d3$ym),
  book_state_updated_at = as.character(bs[["updated_at"]] %||% NA),
  built = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  parquet = OUT,
  note = "도훈 승인 1안(2026-08-08). PG2 변경 시 pg2_coherence_check.R C2/C3 가 stale 을 검거한다."
)
write_json(meta, "06_Registry/book_carrier/carrier_meta.json", pretty = TRUE, auto_unbox = TRUE)
cat("[d3-carrier] carrier_meta.json 갱신 (strategy=현 admitted — C2/C3 해소)\n")
