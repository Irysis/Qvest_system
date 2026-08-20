## export_smv_factor_regime.R — 팩터별 SJM 국면 신호 export (FQ-239 P2, 소비면 전개용)
## 산출: outputs/ramp/smv_factor_regime_daily.parquet (long: Date × factor)
##   state      : 1/2 (refit 라벨 공간; bull 여부는 m_ann 비교로 — 라벨 자체는 소비 금지 권장)
##   bear_prob  : ★연속 1급 — 상대근접도 c_bull/(c_bear+c_bull) ∈ [0,1] (자유도 0, softmax 스케일 파라미터 없음)
##   view_ann   : 상태조건부 기대 active 연율 (±5% cap) — 연속 대안축
##   effective_date : T+2 규약상 최초 반영 가능 거래일 (Date=T 신호)
## ★소비 규약: Date=T 신호는 effective_date 이후 수익에만. 월간 프레임 컷오프 = 홀딩월 시작 2거래일 전.
##   결측일(bear_prob NA)은 소비자 locf. 진행월 소비 금지. regime_jump_daily의 블록-fill 패턴 복제 금지
##   (본 export는 walk-forward 산출 — 각 행은 그 시점 가용 정보만).
suppressPackageStartupMessages({library(data.table); library(arrow)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/ramp/ramp_shumulvey_features.R")
source("02_Infrastructure/ramp/ramp_io.R")

IDXFILE<-Sys.getenv("SMV_IDXFILE","outputs/ramp/shumulvey_index_returns_202608.parquet")
FEATSET<-"f15"; TUNE<-"fixed"
R<-as.data.table(read_parquet(IDXFILE)); R[,Date:=as.Date(Date)]; setorder(R,Date); R<-R[is.finite(Market)]
NS<-nrow(R)
FACN<-c("Value","Size","Momentum","Quality","LowVol","Growth")
ACT<-copy(R[,.(Date)]); for(f in FACN) ACT[[f]]<-R[[f]]-R$Market
ym<-format(R$Date,"%Y-%m"); meix<-which(!duplicated(ym,fromLast=TRUE))
feats<-lapply(FACN,function(f)build_feat_v2(ACT[[f]],R$Market,FEATSET,NULL)); names(feats)<-FACN

rc<-sprintf(".cache/_smv_v5_refit_%s_%s_%s.rds",FEATSET,TUNE,gsub("[^A-Za-z0-9]","_",basename(IDXFILE)))
rc_old<-sprintf(".cache/_smv_v5_refit_%s_%s.rds",FEATSET,gsub("[^A-Za-z0-9]","_",basename(IDXFILE)))
stopifnot(file.exists(rc)||file.exists(rc_old))
REF<-readRDS(if(file.exists(rc))rc else rc_old)$REF
sc<-Sys.glob(sprintf(".cache/_smv_v5_states_%s_*%s*_lm1.rds",FEATSET,gsub("[^A-Za-z0-9]","_",basename(IDXFILE))))
S<-if(length(sc)) readRDS(sc[1])$S else NULL   # 온라인 상태(점프-지속). 없으면 state NA — bear_prob는 독립 산출
gmi<-findInterval(seq_len(NS), meix)

rows<-list()
for(fi in seq_along(FACN)){ f<-FACN[fi]; X0<-as.matrix(feats[[f]]); rl<-REF[[f]]
  bp<-rep(NA_real_,NS); va<-rep(NA_real_,NS); st<-rep(NA_integer_,NS)
  for(t in seq_len(NS)){ mi<-gmi[t]; if(mi<1)next; rf<-rl[[mi]]; if(is.null(rf))next
    x<-(X0[t,]-rf$mu)/rf$sg
    if(all(is.finite(x))){
      c1<-sum(rf$wj*(x-rf$th[1,])^2); c2<-sum(rf$wj*(x-rf$th[2,])^2)
      bear<-which.min(rf$m_ann)            # 기대 active 낮은 상태 = bear
      cb<-if(bear==1)c1 else c2; cu<-if(bear==1)c2 else c1
      bp[t]<-cu/(cb+cu+1e-12) }
    sti<-if(!is.null(S)) S[t,fi] else NA_integer_
    st[t]<-sti
    if(!is.na(sti)) va[t]<-rf$m_ann[sti]
  }
  eff<-c(R$Date[-(1:2)],rep(NA,2))         # effective_date = Date[t+2]
  rows[[fi]]<-data.table(Date=R$Date, factor=f, state=st, bear_prob=bp, view_ann=va,
                         effective_date=as.Date(eff),
                         refit_ym=ifelse(gmi>=1,format(R$Date[meix[pmax(gmi,1)]],"%Y-%m"),NA_character_),
                         lam=vapply(seq_len(NS),function(t){mi<-gmi[t];if(mi<1)return(NA_real_);rf<-rl[[mi]];if(is.null(rf)||is.null(rf$lam))return(50)else rf$lam},numeric(1)),
                         model_version="smv_v5_f15_fixed_20260820")
}
OUT<-rbindlist(rows)
ramp_write_parquet(OUT, "outputs/ramp/smv_factor_regime_daily.parquet", id_field="factor")
cat(sprintf("EXPORT_DONE rows=%d factors=%d range=%s~%s | bear_prob 결측률=%.1f%%\n",
    nrow(OUT),length(FACN),min(OUT$Date),max(OUT$Date),100*mean(!is.finite(OUT$bear_prob))))
