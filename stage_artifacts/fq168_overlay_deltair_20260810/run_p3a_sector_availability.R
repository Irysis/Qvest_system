## FQ-168 P3a — 섹터 라벨 가용성 확인 (P3 방향 확인의 선행 조건)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P3 = "하위 25% 의 forward 초과수익 **부호**가 FQ-168 의 전제('하위 = long 기피')와 맞는가".
##  그러려면 **섹터-중립 역전 스코어**가 필요하고, 그건 **종목별 섹터 라벨**을 요구한다.
##  ★가용성부터 실측한다(오늘 반복 규약: 입력 형태를 가정하고 재기 시작하지 말 것).
##  확인 대상: ①기존 패널에 섹터 열이 있는가 ②RAWDATA 에 있는가 ③factor DB 경유로 얻어지는가
##  판정: A1_AVAILABLE(경로 확정) / A2_PARTIAL(일부 커버) / A3_ABSENT(없음 → P3 설계 변경)
##  ★read-only.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq168_overlay_deltair_20260810")

found <- list()
## ① 기존 패널
P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
for (nm in names(P)) {
  x <- P[[nm]]
  if (is.data.frame(x)) {
    hits <- grep("sector|industry|gics|krx_ind|업종|섹터", names(x), ignore.case = TRUE, value = TRUE)
    cat(sprintf("  p0_panels$%-10s 열 %2d · 섹터 후보: %s\n", nm, ncol(x),
                if (length(hits)) paste(hits, collapse=", ") else "-"))
    if (length(hits)) found[[paste0("p0_panels$", nm)]] <- hits
  }
}
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds"))
hb <- grep("sector|industry|gics|업종", names(B), ignore.case = TRUE, value = TRUE)
cat(sprintf("  merged_panel 열 %d · 섹터 후보: %s\n", ncol(B), if (length(hb)) paste(hb, collapse=", ") else "-"))

## ② RAWDATA (스키마만 — 전체 로드 금지)
rp <- ".cache/RAWDATA.parquet"
if (file.exists(rp)) {
  sch <- names(read_parquet(rp, as_data_frame = FALSE)$schema)
  hs <- grep("sector|industry|gics|업종|krx", sch, ignore.case = TRUE, value = TRUE)
  cat(sprintf("  RAWDATA.parquet 열 %d · 섹터 후보: %s\n", length(sch),
              if (length(hs)) paste(hs, collapse=", ") else "-"))
  if (length(hs)) found[["RAWDATA"]] <- hs
} else cat("  RAWDATA.parquet 부재\n")

## ③ factor DB — 섹터 기반 팩터가 있으면 섹터 정보가 파이프라인 어딘가에 있다는 신호
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
ds <- sort(unique(as.Date(B$Date)))
pr <- as.data.table(load_month_factors(ds[floor(length(ds)/2)]))
fn <- sort(unique(pr$Factor_Name))
sec_f <- grep("sector|industry|CR0", fn, ignore.case = TRUE, value = TRUE)
cat(sprintf("  factor DB %d팩터 · 섹터 관련: %s\n", length(fn),
            if (length(sec_f)) paste(head(sec_f, 6), collapse=", ") else "-"))

## ④ 섹터 매핑 파일이 별도로 있는가 (이름 아닌 내용으로 확인은 불가하므로 후보만)
cand <- c("02_Infrastructure/data/sector_map.csv", "06_Registry/sector_map.json",
          "02_Infrastructure/data/krx_sector.parquet")
ex <- cand[file.exists(cand)]
cat(sprintf("  별도 매핑 파일: %s\n", if (length(ex)) paste(ex, collapse=", ") else "(후보 3종 모두 부재)"))

has_direct <- length(found) > 0L
verdict <- if (has_direct) "A1_AVAILABLE" else if (length(sec_f)) "A2_PARTIAL" else "A3_ABSENT"
cat(sprintf("\n판정: %s\n", verdict))
if (verdict == "A2_PARTIAL")
  cat("=> 섹터 **라벨**은 직접 없고 섹터 **기반 팩터**만 있다 ⇒ P3 를 섹터-중립 없이 재설계하거나,\n",
      "   CR01_Sector_Comovement 를 섹터 대리로 쓰는 설계를 사전등록할 것\n")
if (verdict == "A3_ABSENT")
  cat("=> 섹터 정보 부재 ⇒ FQ-168 의 '섹터-중립' 전제를 충족할 수 없다. 큐에 data_gate 표기 필요\n")
write_json(list(verdict = verdict, direct_sources = found, sector_factors = sec_f,
                mapping_files = ex),
           file.path(OUT, "p3a_result.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
