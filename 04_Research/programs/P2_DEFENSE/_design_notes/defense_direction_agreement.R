## 방어 팩터의 정렬 방향(as-of IC 부호) vs 이론 방향(레지스트리 direction) 일치율 — P2R04 설계 입력(보는 창 월말 2005-01 ~ 2022-12)
##   왜: 팩터 DB 의 Z_Score_Aligned 는 Usable_Date ≤ 신호일의 IC 부호로 방향을 정한다(factor_db_connector.R::align_factor_direction ·
##   36개월 확장창 · IC 부족이면 레지스트리 방향). 그래서 '저변동 틸트'가 어떤 달에는 고변동 쪽으로 기울 수 있다 — 방어적 보유 장치가
##   구조상 방어 쪽으로 기우는지 먼저 본다(C13 수동 부호 반전 금지 — 정렬 경로만 쓴다).
##   ★정정(10-18 같은 날): 방어 팩터 원값은 위험량에 음수를 붙여 저장된다(compute_defense.R — D01 = −특이변동 · D02 = −β · D03 = −sd ·
##   D04 = −하락β · D06 = −상승β · D07 = 상승β − 하락β · D08 = −꼬리β · D15 = −약세β · D25 = −왼꼬리β · D16 = −공왜도). 그래서 ic_sign = +1 이
##   '방어 쪽(저위험)' 정렬이다. 레지스트리 direction(lower_better)은 음수화 전 양을 가리켜 원값과 어긋난다 — IC 부족 구간의 레지스트리 대체 경로는
##   이 팩터들을 공격 쪽으로 뒤집는다(별도 수리 대상 · 보는 창 216개월은 IC 경로라 무관).
##   산출 = 팩터별 방어 정렬 비율(ic_sign = +1 인 달) · 성과 수치 없음(IC 부호만).
##   실행: Rscript defense_direction_agreement.R → 같은 폴더 defense_direction_agreement.md
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "04_Research/programs/P2_DEFENSE/_design_notes")
suppressMessages(source(file.path(ROOT, "02_Infrastructure/factor_db/factor_db_connector.R")))
TAU <- as.Date("2022-12-31")
reg <- fromJSON(file.path(ROOT, ".cache/factor_db/factor_registry.json"), simplifyVector = FALSE)
fs  <- reg$factors %||% reg
CAND <- c("D01_IdioVol", "D02_Beta", "D03_RealVol", "D04_Downside_Beta", "D07_Beta_Asymmetry", "D08_Tail_Beta",
          "D15_Cond_Bear_Beta", "D16_Coskewness", "D25_Left_Tail_Beta", "D28_Unlevered_Beta", "Q07_Earnings_Stability", "Q08_Composite_Quality")
theory <- vapply(CAND, function(k) { d <- fs[[k]]$direction %||% NA_character_; if (identical(d, "lower_better")) -1 else if (identical(d, "higher_better")) 1 else NA_real_ }, numeric(1))
B <- as.data.table(read_parquet(file.path(ROOT, ".cache/benchmark.parquet")))[, .(Date = as.Date(Date))]
ME <- B[Date >= as.Date("2005-01-01") & Date <= TAU, .(sig = max(Date)), by = .(ym = format(Date, "%Y-%m"))]$sig
rows <- rbindlist(lapply(ME, function(d) {
  ic <- tryCatch(.load_ic_direction_cached(d, min_ic_months = 36L), error = function(e) NULL)
  if (is.null(ic)) return(data.table(sig = d, Factor_Name = CAND, ic_sign = NA_real_))
  ic <- as.data.table(ic)[Factor_Name %in% CAND, .(Factor_Name, ic_sign = as.numeric(ic_sign))]
  merge(data.table(Factor_Name = CAND), ic, by = "Factor_Name", all.x = TRUE)[, sig := d]
}), fill = TRUE)
rows[, theory := theory[Factor_Name]]
S <- rows[, .(months = .N, known = sum(is.finite(ic_sign)), agree = sum(ic_sign == theory, na.rm = TRUE),
              first_known = if (any(is.finite(ic_sign))) format(min(sig[is.finite(ic_sign)])) else NA_character_), by = Factor_Name]
S[, `:=`(agree_share = round(agree / pmax(known, 1L), 3), theory = theory[Factor_Name], name = vapply(Factor_Name, function(k) fs[[k]]$name %||% k, ""))]
S <- merge(S, rows[is.finite(ic_sign), .(defensive_share = round(mean(ic_sign == 1), 3)), by = Factor_Name], by = "Factor_Name", all.x = TRUE)
flips <- rows[is.finite(ic_sign), .(flips = sum(diff(ic_sign) != 0)), by = Factor_Name]
S <- merge(S, flips, by = "Factor_Name", all.x = TRUE)[order(-agree_share)]
md <- function(D) c(paste0("| ", paste(names(D), collapse = " | "), " |"), paste0("|", strrep("---|", ncol(D))),
                    apply(D, 1, function(r) paste0("| ", paste(trimws(r), collapse = " | "), " |")))
writeLines(c("# 방어 팩터 정렬 방향 vs 이론 방향(보는 창 월말 2005-01 ~ 2022-12 · 2026-10-18)", "",
             "- 정렬 = 그 월말의 as-of IC 부호(factor_db_connector.R · 36개월 확장창). 원값은 방어 쪽이 높게 저장된다(위험량 음수화 · compute_defense.R) → **defensive_share = ic_sign = +1 인 달의 비율** = 틸트가 방어 쪽으로 기운 달.",
             "- agree_share(레지스트리 direction 과의 일치)는 참고용 — 레지스트리 lower_better 는 음수화 전 양을 가리켜 원값과 어긋난다(D01~D04 · D07 = 0 은 정렬 오류가 아니라 레지스트리 표기 불일치). IC 부족 구간의 레지스트리 대체 경로는 이 팩터들을 공격 쪽으로 뒤집는다 — 별도 수리.",
             "- D16 공왜도는 원값 = −공왜도라 +1 정렬 = 음의 공왜도(위험 프리미엄 쪽) — 위기 방어 틸트가 아니다.", "",
             md(S[, .(Factor_Name, name, known, defensive_share, flips, registry_theory = theory, agree_share, first_known)])),
           file.path(OUT, "defense_direction_agreement.md"), useBytes = TRUE)
print(S[, .(Factor_Name, known, defensive_share, flips, agree_share)])
