"""역사 exec 순매수-방향 신호 수집 — document.xml 파싱(cp949+AUNIT). RPT_RSN(장내매수+/매도-)·STF_RYN(임원).
firm-month exec net-buy-count = (임원 장내매수 보고) - (임원 장내매도 보고). resumable(월 체크포인트)·budget-aware."""
import requests,io,zipfile,re,pandas as pd,time,os,sys,calendar
R="C:/Users/99922/OneDrive/Quant_Module_Moltbot"
env=dict(l.split("=",1) for l in open(R+"/.env",encoding="utf-8",errors="ignore").read().splitlines() if "=" in l and not l.startswith("#"))
KEY=env["DART_API_KEY"].strip()
uni=pd.read_csv(R+"/.cache/dart/universe_corpcodes.csv",dtype=str); CC={r.corp_code:r.ticker for r in uni.itertuples()}
CKDIR=R+"/.cache/dart/exec_netbuy"; os.makedirs(CKDIR,exist_ok=True)
BUDGET=int(os.environ.get("DART_BUDGET","8500")); calls=0
def parse_doc(rc):
    global calls; calls+=1
    try:
        c=requests.get("https://opendart.fss.or.kr/api/document.xml",params=dict(crtfc_key=KEY,rcept_no=rc),timeout=25).content
        txt=zipfile.ZipFile(io.BytesIO(c)).read(zipfile.ZipFile(io.BytesIO(c)).namelist()[0]).decode("cp949",errors="replace")
    except: return None
    def au(code):
        m=re.search(rf'AUNIT="{code}"[^>]*>(.*?)</T',txt,re.DOTALL); return re.sub(r'<[^>]+>','',m.group(1)).strip() if m else ""
    stf=au("STF_RYN"); rsn=au("RPT_RSN"); main=au("MAIN_SH")
    is_exec="임원" in stf   # 등기임원/비등기임원
    d = 1 if "매수" in rsn or "+" in rsn else (-1 if "매도" in rsn or "-" in rsn else 0)
    return dict(exec=is_exec, dir=d, major=("주요주주" in main or main not in("","-")))
months=pd.period_range(os.environ.get("BF_START","2012-01"),os.environ.get("BF_END","2023-12"),freq="M").astype(str).tolist()
for ym in months:
    ck=f"{CKDIR}/{ym}.csv"
    if os.path.exists(ck): continue
    if calls>=BUDGET: print(f"[budget {calls}] stop before {ym} (resume)",flush=True); break
    bg=ym.replace("-","")+"01"; y,m=ym.split("-"); ed=ym.replace("-","")+str(calendar.monthrange(int(y),int(m))[1])
    recs=[]; page=1
    while calls<BUDGET:
        calls+=1
        try: r=requests.get("https://opendart.fss.or.kr/api/list.json",params=dict(crtfc_key=KEY,bgn_de=bg,end_de=ed,pblntf_ty="D",page_no=page,page_count=100),timeout=25).json()
        except: time.sleep(1.5); continue
        if r.get("status")=="020": print("[020] stop",flush=True); sys.exit(0)
        if r.get("status")!="000" or not r.get("list"): break
        for x in r["list"]:
            if ("임원" in x.get("report_nm","") or "특정증권등소유" in x.get("report_nm","")) and x.get("corp_code") in CC:
                recs.append((x["corp_code"],x["rcept_no"]))
        if page>=r.get("total_page",1): break
        page+=1; time.sleep(0.5)
    agg={}
    for cc,rc in recs:
        if calls>=BUDGET: break
        p=parse_doc(rc); time.sleep(0.4)
        if p and p["exec"] and p["dir"]!=0:
            agg[cc]=agg.get(cc,0)+p["dir"]
    pd.DataFrame([dict(ym=ym,corp_code=cc,Ticker=CC[cc],exec_netbuy=v) for cc,v in agg.items()]).to_csv(ck,index=False)
    print(f"[{ym}] {len(recs)} insider filings → {len(agg)} firms exec-netbuy (calls={calls})",flush=True)
print(f"RUN END calls={calls}",flush=True)
