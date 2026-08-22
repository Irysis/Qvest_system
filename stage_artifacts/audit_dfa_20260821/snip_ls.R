GRID9<-expand.grid(lam=c(20,50,100),k2=c(6,9.5,14))   # v3 grid 승계 (사전등록 v3 프로토콜)
ls_sh_t1<-function(s,aok){ n<-length(s); if(n<100)return(-9)   # 검증 L/S: T+1 적용 + 5bps (v3 same-day 결함 수리)
  vr<-sapply(1:2,function(k){v<-mean(aok[s==k])*PER; if(!is.finite(v))0 else max(min(v,0.05),-0.05)})
  pos<-pmax(pmin(vr[s]/0.05,1),-1)
  cost<-5e-4*abs(c(0,diff(pos)))
  net<-pos[1:(n-1)]*aok[2:n]-cost[1:(n-1)]
  net<-net[is.finite(net)]; if(length(net)<100||sd(net)<1e-9)return(-9)
  mean(net)/sd(net)*sqrt(PER) }
