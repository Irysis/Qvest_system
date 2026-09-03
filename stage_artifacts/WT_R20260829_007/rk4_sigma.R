# RK4 — Omega / D / Sigma = B O B' + D + estimator method shopping (selection_objective = condition_number)
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR=ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_007")
source(file.path(ROOT,"02_Infrastructure/portfolio/hrp_core.R"))
o <- readRDS(file.path(OUT,"rk3_objects.rds")); Fw <- o$Fw; RES <- o$RES; BB <- o$BB; X <- o$X; STY <- o$STY
pn <- readRDS(file.path(OUT,"panel.rds")); RET <- as.data.table(pn$fwd$returns_dt)
A <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
asof <- max(A$Date); cat("[RK4] as_of",as.character(asof),"\n")
ap <- fromJSON(file.path(ROOT,"qepm/mailbox/worktask/WT-R20260829_007/alpha_package.json"))
av <- unlist(ap$alpha_vector); ASSETS <- names(av); cat("[RK4] alpha_vector n",length(ASSETS),"\n")

## ---- B at as_of ----
Ba <- X[Date==asof & Ticker %in% ASSETS]
cat("[RK4] as_of 노출 행",nrow(Ba),"/",length(ASSETS),"\n")
secs_a <- sort(unique(Ba$sec))
Dm <- matrix(0, nrow(Ba), length(secs_a), dimnames=list(Ba$Ticker, secs_a))
Dm[cbind(seq_len(nrow(Ba)), match(Ba$sec, secs_a))] <- 1
B <- cbind(MKT=1, Dm, as.matrix(Ba[, ..STY])); rownames(B) <- Ba$Ticker
FNAMES <- colnames(B)
Fm <- as.matrix(Fw[,-1]); rownames(Fm) <- as.character(Fw$Date)
miss <- setdiff(FNAMES, colnames(Fm)); if(length(miss)) cat("[RK4] 요인 결측(0 처리):",miss,"\n")
Fm2 <- matrix(0, nrow(Fm), length(FNAMES), dimnames=list(rownames(Fm), FNAMES))
common <- intersect(FNAMES, colnames(Fm)); Fm2[,common] <- Fm[,common]
Fm2[!is.finite(Fm2)] <- 0

## ---- Omega: sample vs Ledoit-Wolf(linear) on factor returns ----
n_f <- nrow(Fm2); p_f <- ncol(Fm2)
Om_s  <- cov(Fm2)
Om_lw <- .get_cor_cov(Fm2, "ledoit_wolf")$cov
cond <- function(M){ e <- eigen((M+t(M))/2, symmetric=TRUE, only.values=TRUE)$values; max(e)/max(min(e),1e-16) }
cat(sprintf("[RK4] Omega n=%d p=%d · cond sample %.1f · cond LW %.1f\n", n_f,p_f,cond(Om_s),cond(Om_lw)))

## ---- D: 잔차 분산 (rolling 60m, min 24, sector-median Bayes shrink) ----
RES2 <- RES[Date > asof - 366*5]
dv <- RES2[, .(v=var(resid,na.rm=TRUE), n=sum(is.finite(resid))), by=Ticker]
secmap <- Ba[,.(Ticker,sec)]
dv <- merge(dv, secmap, by="Ticker", all.y=TRUE)
allres <- RES[, .(v_all=var(resid,na.rm=TRUE), n_all=.N), by=Ticker]
dv <- merge(dv, allres, by="Ticker", all.x=TRUE)
dv[is.na(v)|n<24, `:=`(v=v_all, n=pmin(n_all,60))]
secmed <- dv[is.finite(v), .(vsec=median(v,na.rm=TRUE)), by=sec]
dv <- merge(dv, secmed, by="sec", all.x=TRUE)
gm <- median(dv$v, na.rm=TRUE); dv[!is.finite(vsec), vsec:=gm]; dv[!is.finite(v), `:=`(v=vsec, n=0)]
K <- 24
dv[, w := pmin(pmax(n,0),120)/(pmin(pmax(n,0),120)+K)]
dv[, v_shrunk := w*v + (1-w)*vsec]
floorv <- quantile(dv$v_shrunk, 0.02, na.rm=TRUE)
dv[, v_shrunk := pmax(v_shrunk, floorv)]
setkey(dv,Ticker); dv <- dv[J(rownames(B))]
cat(sprintf("[RK4] D: 종목 %d · 특이변동성 연율 중앙 %.1f%% · min %.1f%% · max %.1f%%\n",
  nrow(dv), 100*median(sqrt(dv$v_shrunk*12)), 100*min(sqrt(dv$v_shrunk*12)), 100*max(sqrt(dv$v_shrunk*12))))
Dvec_raw <- { t <- dv$v; t[!is.finite(t)] <- gm; t }
Dvec <- dv$v_shrunk

mkS <- function(Om, Dv){ S <- B %*% Om %*% t(B); diag(S) <- diag(S) + Dv; (S+t(S))/2 }
Sig_struct_s  <- mkS(Om_s,  Dvec_raw)
Sig_struct_lw <- mkS(Om_lw, Dvec)

## ---- 직접 추정기 (p>n 대조) ----
RM <- dcast(RET[Ticker %in% ASSETS & Date<=asof], Date~Ticker, value.var="Ret_1m")
RM <- RM[Date > asof - 366*10]
M <- as.matrix(RM[,-1]); rownames(M) <- as.character(RM$Date)
keep <- colnames(M)[colSums(is.finite(M))==nrow(M)]
Md <- M[, keep, drop=FALSE]
cat(sprintf("[RK4] 직접추정 표본: n=%d months · p=%d (완전이력 %d/%d)\n", nrow(Md), ncol(Md), length(keep), length(ASSETS)))
S_dir_sample <- cov(Md)
lwd <- .get_cor_cov(Md, "ledoit_wolf"); S_dir_lw <- lwd$cov
nlsd <- tryCatch(.get_cor_cov(Md, "lw_nls"), error=function(e) NULL)
S_dir_nls <- if(!is.null(nlsd)) nlsd$cov else NULL
pd <- function(M){ e <- eigen((M+t(M))/2, symmetric=TRUE, only.values=TRUE)$values; c(min=min(e), cond=max(e)/max(min(e),1e-16), pd=as.numeric(min(e)>1e-12)) }
r_sample <- pd(S_dir_sample); r_lw <- pd(S_dir_lw); r_nls <- if(!is.null(S_dir_nls)) pd(S_dir_nls) else c(min=NA,cond=NA,pd=NA)
r_st_s <- pd(Sig_struct_s); r_st_lw <- pd(Sig_struct_lw)
cat(sprintf("[RK4] direct sample : min_eig %.3e cond %.3e PD %s\n", r_sample["min"], r_sample["cond"], r_sample["pd"]==1))
cat(sprintf("[RK4] direct LW-lin : min_eig %.3e cond %.3e PD %s (degenerate attr %s)\n", r_lw["min"], r_lw["cond"], r_lw["pd"]==1, !is.null(attr(S_dir_lw,"lw_degenerate"))))
cat(sprintf("[RK4] direct LW-NLS : min_eig %.3e cond %.3e PD %s\n", r_nls["min"], r_nls["cond"], r_nls["pd"]==1))
cat(sprintf("[RK4] struct sampleO: min_eig %.3e cond %.3e PD %s\n", r_st_s["min"], r_st_s["cond"], r_st_s["pd"]==1))
cat(sprintf("[RK4] struct LW-O+BD: min_eig %.3e cond %.3e PD %s\n", r_st_lw["min"], r_st_lw["cond"], r_st_lw["pd"]==1))

## 안정성: 전반부/후반부 요인표본으로 Omega 재추정 -> 상대 Frobenius 거리
h <- floor(n_f/2); f1 <- Fm2[1:h,]; f2 <- Fm2[(h+1):n_f,]
relF <- function(Aa,Bb) norm(Aa-Bb,"F")/norm((Aa+Bb)/2,"F")
st_s  <- relF(cov(f1), cov(f2))
st_lw <- relF(.get_cor_cov(f1,"ledoit_wolf")$cov, .get_cor_cov(f2,"ledoit_wolf")$cov)
h2 <- floor(nrow(Md)/2)
st_dir_s <- relF(cov(Md[1:h2,]), cov(Md[(h2+1):nrow(Md),]))
st_dir_lw<- relF(.get_cor_cov(Md[1:h2,],"ledoit_wolf")$cov, .get_cor_cov(Md[(h2+1):nrow(Md),],"ledoit_wolf")$cov)
st_dir_nls<- tryCatch(relF(.get_cor_cov(Md[1:h2,],"lw_nls")$cov, .get_cor_cov(Md[(h2+1):nrow(Md),],"lw_nls")$cov), error=function(e) NA)
cat(sprintf("[RK4] 안정성(split-half relFrob) Omega sample %.4f / LW %.4f | direct sample %.4f / LW %.4f / NLS %.4f\n",
    st_s, st_lw, st_dir_s, st_dir_lw, st_dir_nls))
cat("[RK4] LW shrinkage intensity: Omega", round(.get_cor_cov(Fm2,"ledoit_wolf")$shrinkage %||% NA,4), "\n")
saveRDS(list(B=B, Om_s=Om_s, Om_lw=Om_lw, Dvec=Dvec, Dvec_raw=Dvec_raw, dv=dv, Fm2=Fm2,
             Sig=Sig_struct_lw, Sig_struct_s=Sig_struct_s, asof=asof, ASSETS=ASSETS, Ba=Ba,
             FNAMES=FNAMES, secs_a=secs_a, Md=Md,
             diag=list(r_sample=r_sample,r_lw=r_lw,r_nls=r_nls,r_st_s=r_st_s,r_st_lw=r_st_lw,
                       st_s=st_s,st_lw=st_lw,st_dir_s=st_dir_s,st_dir_lw=st_dir_lw,st_dir_nls=st_dir_nls,
                       n_f=n_f,p_f=p_f,n_dir=nrow(Md),p_dir=ncol(Md),
                       lw_degenerate=!is.null(attr(S_dir_lw,"lw_degenerate")))),
        file.path(OUT,"rk4_objects.rds"))
cat("[RK4] done\n")
