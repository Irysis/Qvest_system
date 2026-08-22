# WT-D20260822_005 · alpha_vector @ sig_date 2026-07-31 (selected = M08+Q01+C03 EW-Z)
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); Sys.setenv(QM_ROOT=root)
source(file.path(root,"02_Infrastructure/config.R"))
source(file.path(root,"02_Infrastructure/factor_db/factor_db_connector.R"))
stage <- file.path(root,"stage_artifacts/WT-D20260822_005")

sig <- as.Date("2026-07-31")
FAC <- c("M08_Residual_Mom","Q01_GPA","C03_EPS_Chg_3m")
raw <- as.data.table(read_parquet(RAWDATA_CACHE, col_select=c("Date","Ticker","K200","KQ150","Size")))
raw[, Date := as.Date(Date)]
md <- max(raw[Date<=sig, Date])
uni <- raw[Date==md & (K200==TRUE|KQ150==TRUE), .(Ticker, Size)]

fm <- load_month_factors(sig, factor_names=FAC, coverage_min=0.03)
asof <- attr(fm, "factor_db_asof_date")
w <- dcast(fm, Ticker ~ Factor_Name, value.var="Z_Score_Aligned", fun.aggregate=function(x) mean(x,na.rm=TRUE))
w <- merge(uni, w, by="Ticker")   # 유니버스 제한
present <- intersect(FAC, names(w))
M <- as.matrix(w[, ..present]); w[, score := rowMeans(M, na.rm=TRUE)]; w[, n_fac := rowSums(!is.na(M))]
w <- w[n_fac>=1 & is.finite(score)]
setorder(w, -score)
w[, rank := seq_len(.N)]
# confidence = n_fac 커버리지 × |z| 정규화 (advisory)
w[, confidence := pmin(1, n_fac/length(FAC)) * pmin(1, abs(score)/2)]

cat("sig=", as.character(sig), " asof=", as.character(asof), " univ=", nrow(uni), " scored=", nrow(w), "\n")
cat("top 25:\n"); print(head(w[, .(rank, Ticker, score=round(score,3), n_fac, conf=round(confidence,2))], 25))

# alpha_scores.parquet (전 종목 score + rank + confidence)
alpha_scores <- w[, .(sig_date=sig, factor_db_asof=asof, Ticker, score, rank, n_fac, confidence,
                       M08=get("M08_Residual_Mom"), Q01=get("Q01_GPA"), C03=get("C03_EPS_Chg_3m"))]
write_parquet(alpha_scores, file.path(stage, "alpha_scores.parquet"))
cat("saved alpha_scores.parquet rows=", nrow(alpha_scores), "\n")

# alpha_vector (top-25 EW = screening portfolio; scores 전체는 parquet)
av <- head(w[, .(Ticker, score, rank, confidence)], 25)
write_json(list(sig_date=as.character(sig), factor_db_asof=as.character(asof),
   n_universe=nrow(uni), n_scored=nrow(w), top_n=25,
   alpha_vector=av, note="score = EW mean of aligned-Z {M08_Residual_Mom, Q01_GPA, C03_EPS_Chg_3m}. long-only top-25 EW screening portfolio."),
   file.path(stage, "alpha_vector.json"), auto_unbox=TRUE, na="null", pretty=TRUE)
cat("saved alpha_vector.json (top-25)\n")
