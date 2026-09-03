# OP3 module — risk 모형 결정시점 인스턴스화 (추정기/창/floor 전량 risk rk5 승계)
local({
  o3 <- readRDS(file.path(OUT,"rk3_objects.rds"))
  X <<- o3$X; STY <<- o3$STY
  Fw <- o3$Fw; ME <<- sort(unique(Fw$Date))
  Fm <<- { m <- as.matrix(Fw[,-1]); m[!is.finite(m)] <- 0; m }
  resw <- dcast(o3$RES, Date~Ticker, value.var="resid")
  RD <<- { m <- as.matrix(resw[,-1]); rownames(m)<-as.character(resw$Date); m }
})
lwcov <- function(M){ p<-ncol(M); n<-nrow(M); S<-cov(M); mu<-mean(diag(S))
  rho <- min(((n-2)/n*sum(diag(S)^2)+sum(S)^2)/((n+2)*(sum(S^2)-sum(diag(S)^2)/p)),1)
  (1-rho)*S+rho*mu*diag(p) }
sigma_at <- function(j, tk){
  Fh <- Fm[1:(j-1), , drop=FALSE]
  xd <- X[Date==ME[j] & Ticker %in% tk]; if(nrow(xd) < 2) return(NULL)
  secs <- sort(unique(xd$sec))
  Dm <- matrix(0,nrow(xd),length(secs),dimnames=list(NULL,secs)); Dm[cbind(seq_len(nrow(xd)),match(xd$sec,secs))] <- 1
  Bm <- cbind(MKT=1, Dm, as.matrix(xd[,..STY])); rownames(Bm) <- xd$Ticker
  cn <- colnames(Bm); Fh2 <- matrix(0,nrow(Fh),length(cn),dimnames=list(NULL,cn))
  cc <- intersect(cn,colnames(Fh)); Fh2[,cc] <- Fh[,cc]
  Om <- lwcov(Fh2)
  rlo <- max(1,(j-1)-59); Rh <- RD[rlo:(j-1), , drop=FALSE]
  dvv <- sapply(xd$Ticker, function(t2){ if(!(t2 %in% colnames(Rh))) return(NA_real_)
      v<-Rh[,t2]; v<-v[is.finite(v)]; if(length(v)<24) return(NA_real_); var(v) })
  allv <- sapply(xd$Ticker, function(t2){ if(!(t2 %in% colnames(RD))) return(NA_real_)
      v<-RD[1:(j-1),t2]; v<-v[is.finite(v)]; if(length(v)<12) return(NA_real_); var(v) })
  dvv[!is.finite(dvv)] <- allv[!is.finite(dvv)]
  med <- median(c(dvv,allv),na.rm=TRUE); if(!is.finite(med)) med <- 0.01
  dvv[!is.finite(dvv)] <- med
  dfloor <- pmax(dvv, quantile(dvv,0.10,na.rm=TRUE))
  S <- Bm%*%Om%*%t(Bm); diag(S) <- diag(S)+dfloor; S <- (S+t(S))/2
  list(S=S, names=xd$Ticker, d_raw=dvv, d_floored=dfloor, floored=dfloor>dvv+1e-14)
}
