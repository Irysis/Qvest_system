cppFunction('IntegerVector jumpDP(NumericMatrix C, double lam){
  int n=C.nrow(); NumericMatrix D(n,2); IntegerMatrix B(n,2);
  D(0,0)=C(0,0); D(0,1)=C(0,1);
  for(int t=1;t<n;t++){ for(int k=0;k<2;k++){
    double stay=D(t-1,k); double sw=D(t-1,1-k)+lam;
    if(stay<=sw){D(t,k)=C(t,k)+stay;B(t,k)=k;} else {D(t,k)=C(t,k)+sw;B(t,k)=1-k;} }}
  IntegerVector s(n); s[n-1]= D(n-1,0)<=D(n-1,1)?0:1;
  for(int t=n-2;t>=0;t--) s[t]=B(t+1,s[t+1]);
  return s+1; }')
cppFunction('int jumpDPlast(NumericMatrix C, double lam){
  int n=C.nrow(); double d0=C(0,0), d1=C(0,1);
  for(int t=1;t<n;t++){ double n0=C(t,0)+std::min(d0,d1+lam); double n1=C(t,1)+std::min(d1,d0+lam); d0=n0; d1=n1; }
  return d0<=d1?1:2; }')
sparse_jm<-function(X,lam=50,kappa=sqrt(9.5),outer=8,inner=10){
  X<-as.matrix(X); T<-nrow(X); p<-ncol(X)
  wj<-rep(1/sqrt(p),p); s<-as.integer(X[,1] > median(X[,1]))+1L
  soft<-function(a,d) sign(a)*pmax(abs(a)-d,0)
  for(o in 1:outer){
    for(it in 1:inner){
      th<-matrix(0,2,p); for(k in 1:2){idx<-which(s==k); th[k,]<-if(length(idx)>0)colMeans(X[idx,,drop=FALSE]) else colMeans(X)}
      C<-matrix(0,T,2); for(k in 1:2){d2<-sweep(X,2,th[k,],"-")^2; C[,k]<-as.numeric(d2 %*% wj)}
      ns<-jumpDP(C,lam); if(all(ns==s))break; s<-ns }
    th<-matrix(0,2,p); for(k in 1:2){idx<-which(s==k);th[k,]<-if(length(idx)>0)colMeans(X[idx,,drop=FALSE]) else colMeans(X)}
    gm<-colMeans(X); TSS<-colSums(sweep(X,2,gm,"-")^2)
    WCSS<-rep(0,p); for(k in 1:2){idx<-which(s==k);if(length(idx)>0)WCSS<-WCSS+colSums(sweep(X[idx,,drop=FALSE],2,th[k,],"-")^2)}
    a<-pmax(TSS-WCSS,0)
    f<-function(d){sw<-soft(a,d);nm<-sqrt(sum(sw^2));if(nm<1e-12)return(0);sum(abs(sw/nm))}
    if(f(0)<=kappa){ d<-0 } else { lo<-0;hi<-max(a);for(b in 1:50){mid<-(lo+hi)/2;if(f(mid)>kappa)lo<-mid else hi<-mid};d<-hi }
    sw<-soft(a,d);nm<-sqrt(sum(sw^2));wnew<-if(nm<1e-12)rep(1/sqrt(p),p) else sw/nm
    if(max(abs(wnew-wj))<1e-4){wj<-wnew;break}; wj<-wnew }
  list(s=s, th=th, w=wj)
}
