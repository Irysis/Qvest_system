## P1R02 롱 레그만 판 — 1801.01777(Abe & Nakayama 2018 DNN) 충실구현 재검증판 engine.R 의 **롱 레그만**(상위 분위 · 동일가중 · Σw = 1)
##   도훈 10-17 "롱 레그만 판부터 사전등록해서 측정" — 롱숏 A 의 알파가 롱 레그에서 나오는지(롱온리 경로의 가능성) 분해한다.
##   엔진 원산출 = 레인 재검증 측정이 같은 데이터 판에서 심은 기저 캐시(02_Infrastructure/reinforcement/rf_base_cache.R '기저 캐시 시드' ·
##   키 = 엔진 md5 + RAWDATA · 벤치 · 팩터 DB 도장 + 데이터 지문 + 시작일). 키가 맞으면 캐시(DNN 재학습 없음 · 같은 판의 증명),
##   안 맞으면 같은 엔진을 그대로 돌린다(같은 산출 · 시간만 더 든다 — 출처는 P1R02_SOURCE 로 남긴다).
##   PIT: 같은 엔진의 같은 신호에서 양(+) 비중 종목만 남기고 그 안에서 다시 합 1 로 맞춘다 — 정보를 더하지 않는다.
##   러너(run_paper_replication)가 RAWDATA · BM_DT · .RP_START_DATE 를 이 환경에 넣는다(엔진 계약).
.p1r02_rt  <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
.p1r02_eng <- file.path(.p1r02_rt, "04_Research/strategies/RP_AUTO_CLEAN_1801_01777/engine.R")
.p1r02_md5 <- "fead7df9787aebb8aa7b554e88e361bc"   # 사전등록 고정 — 재검증판(10-17 00:24 · 고정 팩터 지도)
if (!identical(unname(tools::md5sum(.p1r02_eng)), .p1r02_md5))
  stop("[P1R02] 기저 엔진 md5 가 사전등록과 다르다: ", unname(tools::md5sum(.p1r02_eng)))
source(file.path(.p1r02_rt, "02_Infrastructure/reinforcement/rf_base_cache.R"), local = TRUE)
.p1r02_ck  <- rf_base_cache_seed_key(.p1r02_eng, RAWDATA, root = .p1r02_rt, start = .RP_START_DATE)
.p1r02_hit <- rf_base_cache_load(file.path(.p1r02_rt, ".cache", "rf_base_signal", .p1r02_ck$file), .p1r02_ck$key)
if (identical(.p1r02_hit$why, "hit")) {
  .p1r02_B <- data.table::as.data.table(.p1r02_hit$obj)
  P1R02_SOURCE <- paste0("base_cache:", .p1r02_ck$file)
} else {
  .p1r02_e <- new.env(parent = environment())
  .p1r02_e$RAWDATA <- RAWDATA; .p1r02_e$BM_DT <- BM_DT; .p1r02_e$.RP_START_DATE <- .RP_START_DATE
  source(.p1r02_eng, local = .p1r02_e)
  .p1r02_B <- .p1r02_e$PORTFOLIO[, .(Date, Ticker, .base_sig = as.numeric(Weight))]
  P1R02_SOURCE <- paste0("engine_rerun:", .p1r02_hit$why)
  rm(.p1r02_e)
}
cat(sprintf("[P1R02] 기저 신호 출처 = %s · 신호일 %d\n", P1R02_SOURCE, data.table::uniqueN(.p1r02_B$Date)))
.p1r02_L <- .p1r02_B[is.finite(.base_sig) & .base_sig > 0]
.p1r02_L[, Weight := .base_sig / sum(.base_sig), by = Date]
PORTFOLIO <- .p1r02_L[, .(Date, Ticker, Weight, Leg = "long")]
cat(sprintf("[P1R02] 롱 레그 PORTFOLIO %d행 · 신호일 %d · 신호일당 중앙 %d종\n", nrow(PORTFOLIO), data.table::uniqueN(PORTFOLIO$Date),
            as.integer(stats::median(PORTFOLIO[, .N, by = Date]$N))))
rm(.p1r02_B, .p1r02_L, .p1r02_hit)
