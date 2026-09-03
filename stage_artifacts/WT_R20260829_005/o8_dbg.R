setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressPackageStartupMessages({library(data.table)})
S <- readRDS("stage_artifacts/WT_R20260829_005/opt_r5.rds")
RET <- S$RET; sel <- S$sel; A <- S$A
dates <- sort(unique(A$Date))
RW <- dcast(RET, Date ~ Ticker, value.var="Ret_1m"); rw_dates <- RW$Date
RWm <- as.matrix(RW[,-1]); rownames(RWm) <- as.character(rw_dates)
d <- dates[150]; tk <- sel[Date==d]$Ticker
idx <- tail(which(rw_dates < d), 60)
Rt <- RWm[idx, tk, drop=FALSE]
cat("d:", as.character(d), " rows:", nrow(Rt), " NA frac:", mean(is.na(Rt)), "\n")

C <- cor(Rt, use="pairwise.complete.obs"); C[!is.finite(C)] <- 0; diag(C) <- 1
V <- cov(Rt, use="pairwise.complete.obs"); V[!is.finite(V)] <- 0
dv <- diag(V); dv[!is.finite(dv)|dv<=0] <- median(dv[is.finite(dv)&dv>0]); diag(V) <- dv
dd <- sqrt(pmax(0,0.5*(1-C)))
cat("dd any NA:", any(is.na(dd)), "\n")
hc <- try(hclust(as.dist(dd), method="single"))
cat("hclust class:", class(hc), "\n")
ord <- hc$order
ivp <- function(i) { iv <- 1/diag(V)[i]; iv/sum(iv) }
cvc <- function(i) { wv <- ivp(i); as.numeric(t(wv) %*% V[i,i,drop=FALSE] %*% wv) }
w <- rep(1, length(ord)); names(w) <- colnames(Rt)[ord]
clusters <- list(ord)
r <- try({
 while (length(clusters) > 0) {
  nxt <- list()
  for (cl in clusters) {
    if (length(cl) <= 1) next
    h <- floor(length(cl)/2); c1 <- cl[1:h]; c2 <- cl[(h+1):length(cl)]
    v1 <- cvc(c1); v2 <- cvc(c2); a1 <- 1 - v1/(v1+v2)
    w[colnames(Rt)[c1]] <- w[colnames(Rt)[c1]] * a1
    w[colnames(Rt)[c2]] <- w[colnames(Rt)[c2]] * (1-a1)
    nxt <- c(nxt, list(c1), list(c2))
  }
  clusters <- nxt
 }
 w
})
print(class(r)); print(r)
cat("sum:", sum(r), " finite:", all(is.finite(r)), "\n")
## how many dates pass the strict gate?
pass <- 0; passIVP <- 0
for (dd2 in dates) {
  i2 <- which(rw_dates < dd2)
  if (length(i2) < 24) next
  i2 <- tail(i2, 60); tks <- sel[Date==dd2]$Ticker
  have <- intersect(tks, colnames(RWm))
  if (length(have) != length(tks)) next
  Rt2 <- RWm[i2, tks, drop=FALSE]
  if (all(colSums(!is.na(Rt2)) >= 12L)) pass <- pass + 1
}
cat("strict gate pass:", pass, "/", length(dates), "\n")
