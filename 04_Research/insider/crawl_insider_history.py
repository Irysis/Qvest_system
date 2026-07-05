"""내부자 공시 활동(빈도) 역사 수집 — list.json 전역사 가용. 금액 파싱 없이 firm-month별 내부자 보고 수.
'임원ㆍ주요주주특정증권등소유상황보고서' 건수 = 내부자 활동 signal(방향 없는 coarse). 2012-2023 유니버스."""
import requests,pandas as pd,time,os,sys
R="C:/Users/99922/OneDrive/Quant_Module_Moltbot"
env=dict(l.split("=",1) for l in open(R+"/.env",encoding="utf-8",errors="ignore").read().splitlines() if "=" in l and not l.startswith("#"))
KEY=env["DART_API_KEY"].strip()
uni=pd.read_csv(R+"/.cache/dart/universe_corpcodes.csv",dtype=str)
CC={r.corp_code:r.ticker for r in uni.itertuples()}
CK=R+"/.cache/dart/insider_activity_hist.parquet"
months=pd.period_range("2012-01","2023-12",freq="M").astype(str).tolist()
rows=[]; done_ym=set()
if os.path.exists(CK):
    old=pd.read_parquet(CK); rows=old.to_dict("records"); done_ym=set(old.ym.unique())
for i,ym in enumerate(months):
    if ym in done_ym: continue
    bg=ym.replace("-","")+"01"; y,m=ym.split("-"); import calendar; ed=ym.replace("-","")+str(calendar.monthrange(int(y),int(m))[1])
    page=1; cnt={}
    while True:
        try:
            r=requests.get("https://opendart.fss.or.kr/api/list.json",params=dict(crtfc_key=KEY,bgn_de=bg,end_de=ed,pblntf_ty="D",page_no=page,page_count=100),timeout=25).json()
        except: time.sleep(2); continue
        if r.get("status")=="020": print(f"[020 rate-limit at {ym} p{page}] stop",flush=True); pd.DataFrame(rows).to_parquet(CK,index=False); sys.exit(0)
        if r.get("status")!="000" or not r.get("list"): break
        for x in r["list"]:
            if "임원ㆍ주요주주" in x.get("report_nm","") or "특정증권등소유" in x.get("report_nm",""):
                cc=x.get("corp_code")
                if cc in CC: cnt[cc]=cnt.get(cc,0)+1
        tp=r.get("total_page",1)
        if page>=tp: break
        page+=1; time.sleep(0.6)
    for cc,c in cnt.items(): rows.append(dict(ym=ym,corp_code=cc,Ticker=CC[cc],n_insider=c))
    if i%6==0: pd.DataFrame(rows).to_parquet(CK,index=False); print(f"[{ym}] cum {len(rows)} firm-months",flush=True)
    time.sleep(0.4)
pd.DataFrame(rows).to_parquet(CK,index=False)
print(f"DONE {len(rows)} firm-months",flush=True)
