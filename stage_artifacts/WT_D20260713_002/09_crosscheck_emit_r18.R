## R18 교차확인 emit — 매트릭스 차트 + 결정 JSON + 텔레그램 v7 (원칙 9)
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")
OUT <- "stage_artifacts/WT_D20260713_002"
X <- readRDS(file.path(OUT,"v02ep_crosscheck.rds")); V<-X$V02_EP
P6<-readRDS(file.path(OUT,"consumption_diagnostic.rds")); Pab<-P6$ab$FB; Pcr<-P6$criteria$FB

# ── chart 1: 4-criteria matrix (2 substrates x 4 criteria) ──
crit_lab<-c("C1 걸림실재","C2 꼬리>무작위","C3 알파비손상","C4 비집중")
Pv<-c(Pcr$C1_binding_real,Pcr$C2_tail_beats_random,Pcr$C3_alpha_intact,Pcr$C4_not_concentrated)
Vv<-c(V$criteria$C1,V$criteria$C2,V$criteria$C3,V$criteria$C4)
f1<-file.path(OUT,"crosscheck_matrix.png")
png(f1,width=1000,height=440,res=110); par(mar=c(3.5,9,4,2))
plot(NA,xlim=c(0.5,4.5),ylim=c(0.5,2.5),axes=FALSE,xlab="",ylab="",
  main="R18 교차확인 — 기질별 승격 4종 요건 (녹=충족 / 적=미달)")
subs<-c("V02_EP (제2 독립기질)","P-pure (제1 기질)"); mat<-rbind(Vv,Pv)
for(i in 1:2) for(j in 1:4){ col<-if(mat[i,j]) "#2e8b57" else "#c0392b"
  rect(j-0.45,i-0.45,j+0.45,i+0.45,col=col,border="white",lwd=2)
  text(j,i,if(mat[i,j])"PASS" else "FAIL",col="white",cex=1.0,font=2) }
axis(2,at=1:2,labels=subs,las=1,tick=FALSE,cex.axis=0.9)
axis(3,at=1:4,labels=crit_lab,tick=FALSE,cex.axis=0.8,line=-0.5)
text(4.5,1,sprintf("%d/4",sum(Vv)),pos=4,xpd=TRUE,font=2); text(4.5,2,sprintf("%d/4",sum(Pv)),pos=4,xpd=TRUE,font=2)
dev.off()

# ── chart 2: C2 crux — Δdownside-dev forensic vs random per substrate ──
f2<-tg_chart_sweep(
  labels=c("P-pure 포렌식","P-pure 무작위(평균)","V02_EP 포렌식","V02_EP 무작위(평균)"),
  values=c(Pab$d_dd, Pab$rand_d_dd_mean, V$d_downside_dev, mean(V$rand_d_dd_seeds)),
  out_dir=OUT, title="R18 교차확인 — 하방편차 개선Δ: P-pure는 무작위 능가, V02_EP는 반전(미재현)",
  value_label="Δ downside-deviation (연율)", hline=0, hline_label="무개선",
  highlight="V02_EP 포렌식", filename="crosscheck_ddd.png")
charts<-c(f1,f2)

# ── decision JSON ──
dec<-list(
  label="제2 독립 소형 기질 교차확인 — 승격 최종 관문 (판정-후 소비진단, 게이트 불변)",
  substrates=list(
    Ppure_W36_K20=list(source="d3 holdings_monthly_ppure.parquet", n_months=P6$baseline_tail$n,
      criteria=Pcr, d_downside_dev=Pab$d_dd, d_downside_dev_rel_pct=100*Pab$d_dd/P6$baseline_tail$downside_dev,
      beats_random=TRUE, pass="4/4"),
    V02_EP=list(source="d3 holdings_monthly_v02ep.parquet", n_months=V$n_months,
      binding_overall=V$binding_overall, by_tier=V$by_tier, criteria=V$criteria,
      d_downside_dev=V$d_downside_dev, d_downside_dev_rel_pct=V$d_downside_dev_rel_pct,
      rand_d_dd_seeds=V$rand_d_dd_seeds, beats_random=FALSE, paired_nwt=V$paired_nwt, pass="2/4")
  ),
  third_substrate_R13_D2="EXCLUDED — R13 arms(armD1 등)은 Ppure_W36_K20 base 변형(독립 기질 아님) + 재사용 holdings 아티팩트 부재(신규 엔진 금지). 2 독립 기질로 결정 도달.",
  reproduction="NOT REPRODUCED — 방향 불일치. P-pure에서 F-B exclusion이 하방편차 개선(무작위 3seed 전부 능가, 4/4), V02_EP에서 하방편차 악화(-0.82% rel)이며 무작위(양수)에 패배 → C2 반전, 2/4.",
  verdict="2기질 교차 미재현 → 승격안 상정 불가. F-B exclusion 효과 = P-pure-특이(config-scoped). Production Constraints 기본 필터 승격 부적격.",
  honesty_note="P-pure 4/4는 substrate-특이 false-positive였음 — 교차확인 관문이 이를 적발(효과크기 marginal 경고가 실증됨). 게이트 판정(F-B/F-A config-scoped negative)과 정합.",
  next_probe="F-B는 TEXT/forensic feature로 보존(OVERLAY_CANDIDATE). 범용 기본필터 승격 재도전 조건 = 다수 독립 소형기질서 하방편차>무작위 재현 시(현재 미충족)."
)
write_json(dec, file.path(OUT,"crosscheck_decision.json"), pretty=TRUE, auto_unbox=TRUE, digits=5, na="null")
cat("charts:", paste(basename(charts),collapse=", "), " | V pass", V$criteria$pass, " P pass", Pcr$pass_count, "\n")

# ── telegram v7 ──
tg_agent_brief(
  agent="Alpha",
  title="R18 교차확인 — Benford 배제필터 제2 기질서 미재현, 승격 부적격(P-pure 특이)",
  sections=list(
    list(type="summary", emoji="📌",
      body="F-B 배제필터 승격 최종관문: 제2 독립 소형기질(V02_EP)서 미재현(2/4). P-pure 4/4는 기질-특이 — 승격 부적격 정직 판정."),
    list(type="bullet", emoji="📖", heading="쉬운 설명",
      items=c(
        "관문: 한 전략(P-pure)서만 좋으면 우연 — 다른 독립 소형전략서도 되는지 교차확인",
        "제2 기질 = V02_EP(가치 EP sleeve, P-pure와 다른 팩터족)",
        "결과: V02_EP서 벤포드 배제가 하방편차를 오히려 악화(-0.8%)·무작위-제외에 패배",
        "P-pure 4/4 vs V02_EP 2/4 = 방향 반전 → 재현 실패",
        "결론: P-pure 4/4는 그 전략 특유의 우연(false-positive)이었음",
        "관문이 제 역할 = marginal 경고가 실증됨, 승격 상정 안 함")),
    list(type="kv", emoji="📊", heading="기질별 승격 4종 (F-B 단독)",
      kv=list(
        "P-pure 종합"    = "4/4 (하방편차 +2.6% rel·무작위 3seed 능가)",
        "V02_EP 종합"    = "2/4 (하방편차 -0.8% rel·무작위에 패배)",
        "걸림율 V02_EP"  = "소형 7.3% (실재하나 효과 반전)",
        "C2 꼬리>무작위" = "P-pure 충족 / V02_EP 미달 (핵심 반전)",
        "C3 알파비손상"  = "양 기질 충족 (paired-t -0.42/0.19)",
        "재현 판정"      = "미재현 — config-scoped(P-pure 특이)")),
    list(type="bullet", emoji="🚩", heading="주의 · 정직",
      items=c(
        "게이트 판정 불변: F-B 선택 알파 여전히 null·재측정 없음",
        "제3 기질(R13 D-2)은 P-pure 변형이라 독립 아님 + holdings 아티팩트 부재 → 제외",
        "2 독립 기질로 결정 충분 도달 — 미재현 명확",
        "AX-005: exclusion 필요조건, 포렌식 tail정보가 기질-불변이지 않음 = 범용필터 부적격",
        "P-pure 4/4의 marginal 경고(직전 보고)가 교차확인서 실증됨")),
    list(type="bullet", emoji="➡️", heading="판정 · 다음",
      items=c(
        "판정: 2기질 교차 미재현 → Production Constraints 기본필터 승격 부적격(승격안 미상정)",
        "F-B = forensic feature로 보존(OVERLAY_CANDIDATE) — 범용 승격 아님",
        "재도전 조건: 다수 독립 소형기질서 하방편차>무작위 재현 시(현재 미충족)",
        "R18 전체 종결: 게이트 2/2 config-scoped negative + 소비 승격 부적격"))
  ),
  charts=charts,
  footer="📚 교차확인 결정 · consumption_prereg e7d6c8d8 · FQ-031 · 게이트판정 불변 · 승격 부적격(P-pure 특이)"
)
cat("R18_CROSSCHECK_TG_DONE charts=", length(charts), "\n")
