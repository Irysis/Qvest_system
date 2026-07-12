# -*- coding: utf-8 -*-
"""N3 (FQ-022) — DART 담보/질권·감사의견 metadata census. 2026-07-13 야간 라운드.
METADATA ONLY: list.json / majorstock.json / accnutAdtorNmNdAdtOpinion.json.
document.xml 다운로드 절대 없음.

쿼터 규약:
- 총 호출 캡 1,500 (모든 HTTP 시도를 콜로 계상). 100콜 단위 로그.
- HTTP 429 / HTTP!=200 3회 / DART status in {010,011,012,020,100,800,900,901} 1회 → 즉시 전체 중단 + 부분 저장.
- status 013(조회 데이터 없음)은 정상 0건 응답으로 해석(레퍼런스 crawl_insider_history.py 동일 의미론) — 카운트만 기록.
"""
import requests, csv, json, os, time, collections

R = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT = R + "/04_Research/dart_census"
os.makedirs(OUT, exist_ok=True)
RAW = OUT + "/census_raw_20260713.json"
STATE = OUT + "/census_state_20260713.json"

env = dict(l.split("=", 1) for l in open(R + "/.env", encoding="utf-8", errors="ignore").read().splitlines()
           if "=" in l and not l.startswith("#"))
KEY = env["DART_API_KEY"].strip()

CAP = 1500
SLEEP = 0.30
TODAY = "20260713"
YEARS = list(range(2005, 2027))
ABORT_ST = {"010", "011", "012", "020", "100", "800", "900", "901"}

state = {"calls": 0, "aborted": False, "abort_reason": None, "n_status013": 0,
         "started": time.strftime("%Y-%m-%d %H:%M:%S")}
res = {"meta": {"date": "2026-07-13", "cap": CAP, "apis": ["list.json", "majorstock.json",
       "accnutAdtorNmNdAdtOpinion.json"], "note": "metadata only, no document downloads"}}


class Abort(Exception):
    pass


def save():
    for path, obj in ((STATE, state), (RAW, res)):
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(obj, f, ensure_ascii=False, indent=1, default=str)
        os.replace(tmp, path)


def abort(reason):
    state["aborted"] = True
    state["abort_reason"] = reason
    print("[ABORT] " + reason, flush=True)
    save()
    raise Abort(reason)


def api(url, params, tag):
    if state["calls"] >= CAP:
        abort("call cap %d reached at %s" % (CAP, tag))
    for attempt in range(3):
        state["calls"] += 1
        if state["calls"] % 100 == 0:
            print("[quota] %d calls used (%s)" % (state["calls"], tag), flush=True)
            save()
        try:
            resp = requests.get(url, params=dict(params, crtfc_key=KEY), timeout=25)
        except Exception as e:
            if attempt == 2:
                abort("network fail x3 at %s: %r" % (tag, e))
            time.sleep(2 * (attempt + 1))
            continue
        if resp.status_code == 429:
            abort("HTTP 429 at %s" % tag)
        if resp.status_code != 200:
            if attempt == 2:
                abort("HTTP %d x3 at %s" % (resp.status_code, tag))
            time.sleep(2 * (attempt + 1))
            continue
        try:
            j = resp.json()
        except Exception as e:
            abort("bad json at %s: %r" % (tag, e))
        st = j.get("status")
        if st == "000":
            time.sleep(SLEEP)
            return j
        if st == "013":
            state["n_status013"] += 1
            time.sleep(SLEEP)
            return j
        abort("DART status %s (%s) at %s" % (st, j.get("message"), tag))


def lst(tag, **p):
    p.setdefault("page_no", 1)
    p.setdefault("page_count", 100)
    return api("https://opendart.fss.or.kr/api/list.json", p, tag)


def num(x):
    try:
        return float(str(x).replace(",", "").strip() or 0)
    except Exception:
        return 0.0


PAT = {"dambo": "담보", "jilkwon": "질권", "jungjung": "정정"}  # 담보/질권/정정


def scan_names(rows):
    c = {k: 0 for k in PAT}
    for r in rows:
        nm = r.get("report_nm", "")
        for k, pat in PAT.items():
            if pat in nm:
                c[k] += 1
    return c


# ---------------- Phase 1: market-wide year x type grid ----------------
# 실측 제약: corp_code 없는 list.json은 검색기간 최대 3개월(status 100) → 분기창 4콜/년.
# 예산상 corp_cls 분할·F005 제거(유니버스 정밀치는 P4 per-corp가 담당). 전수(ALL)만.
def quarters(y):
    qs = [("%d0101" % y, "%d0331" % y), ("%d0401" % y, "%d0630" % y),
          ("%d0701" % y, "%d0930" % y), ("%d1001" % y, "%d1231" % y)]
    out = []
    for b, e in qs:
        if b > TODAY:
            break
        out.append((b, min(e, TODAY)))
    return out


def p1_grid():
    grid = []
    combos = [("D001", "N"), ("F001", "N"), ("F001", "Y"), ("F002", "N")]
    for dty, last in combos:
        for y in YEARS:
            tot = 0
            pats = {k: 0 for k in PAT}
            sample = []
            for b, e in quarters(y):
                tag = "grid:%s/last%s/%s" % (dty, last, b)
                j = lst(tag, bgn_de=b, end_de=e, pblntf_detail_ty=dty, last_reprt_at=last)
                rows = j.get("list") or []
                tot += int(j.get("total_count") or 0)
                q = scan_names(rows)
                for k in pats:
                    pats[k] += q[k]
                if not sample:
                    sample = [r.get("report_nm") for r in rows[:3]]
            grid.append(dict(detail_ty=dty, last_reprt_at=last, year=y, total_count=tot,
                             page1x4_patterns=pats, page1_sample=sample))
        res["p1_grid"] = grid
        save()
        print("[p1] done %s/last%s (calls=%d)" % (dty, last, state["calls"]), flush=True)


# ---------------- Phase 2: schema probes ----------------
def p2_probes():
    uni = list(csv.DictReader(open(R + "/.cache/dart/universe_corpcodes.csv", encoding="utf-8")))
    res["meta"]["n_universe"] = len(uni)
    probe = {}
    # majorstock.json probe: 삼성전자 + universe 처음/끝
    cands = ["00126380", uni[0]["corp_code"], uni[-1]["corp_code"]]
    ms = []
    for cc in cands:
        j = api("https://opendart.fss.or.kr/api/majorstock.json", dict(corp_code=cc), "probe:majorstock:" + cc)
        rows = j.get("list") or []
        ms.append(dict(corp_code=cc, status=j.get("status"), n=len(rows),
                       keys=sorted(rows[0].keys()) if rows else [],
                       dt_range=[min((r.get("rcept_dt", "") for r in rows), default=None),
                                 max((r.get("rcept_dt", "") for r in rows), default=None)],
                       sample=rows[:2]))
    probe["majorstock"] = ms
    # 감사의견 구조화 API probe (사업보고서 주요정보) — 커버리지 경계(2015?) 실검
    op = []
    for cc in ["00126380", uni[0]["corp_code"]]:
        for by in ("2010", "2016", "2023"):
            j = api("https://opendart.fss.or.kr/api/accnutAdtorNmNdAdtOpinion.json",
                    dict(corp_code=cc, bsns_year=by, reprt_code="11011"),
                    "probe:adtopinion:%s:%s" % (cc, by))
            rows = j.get("list") or []
            trim = [{k: (str(v)[:160]) for k, v in r.items()} for r in rows[:2]]
            op.append(dict(corp_code=cc, bsns_year=by, status=j.get("status"), n=len(rows),
                           keys=sorted(rows[0].keys()) if rows else [], sample=trim))
    probe["adt_opinion"] = op
    res["p2_probe"] = probe
    save()
    print("[p2] probes done (calls=%d)" % state["calls"], flush=True)
    return uni


# ---------------- Phase 3: universe majorstock sweep (담보/질권 모수 proxy) ----------------
def p3_majorstock(uni):
    agg_year = collections.defaultdict(lambda: dict(reports=0, ctr_pos=0, resn_pledge=0))
    corps = []
    report_tp_dist = collections.Counter()
    resn_dist = collections.Counter()
    for i, u in enumerate(uni):
        cc = u["corp_code"]
        j = api("https://opendart.fss.or.kr/api/majorstock.json", dict(corp_code=cc), "ms:" + cc)
        rows = j.get("list") or []
        yrs = []
        n_ctr = 0
        n_resn = 0
        for r in rows:
            d = "".join(ch for ch in str(r.get("rcept_dt", "")) if ch.isdigit())
            y = int(d[:4]) if len(d) >= 4 else 0
            yrs.append(y)
            ctr = num(r.get("ctr_stkqy"))
            resn = str(r.get("report_resn", ""))
            agg_year[y]["reports"] += 1
            if ctr > 0:
                agg_year[y]["ctr_pos"] += 1
                n_ctr += 1
            if PAT["dambo"] in resn or PAT["jilkwon"] in resn:
                agg_year[y]["resn_pledge"] += 1
                n_resn += 1
            report_tp_dist[r.get("report_tp", "?")] += 1
            resn_dist[resn[:40]] += 1
        corps.append(dict(corp_code=cc, ticker=u.get("ticker"), n=len(rows), n_ctr_pos=n_ctr,
                          n_resn_pledge=n_resn,
                          yr_min=min(yrs) if yrs else None, yr_max=max(yrs) if yrs else None))
        if i % 50 == 0:
            res["p3_majorstock"] = dict(by_year={str(k): v for k, v in sorted(agg_year.items())},
                                        report_tp_dist=dict(report_tp_dist),
                                        resn_top=dict(resn_dist.most_common(30)), corps=corps)
            save()
            print("[p3] %d/%d corps (calls=%d)" % (i + 1, len(uni), state["calls"]), flush=True)
    res["p3_majorstock"] = dict(by_year={str(k): v for k, v in sorted(agg_year.items())},
                                report_tp_dist=dict(report_tp_dist), corps=corps)
    save()
    print("[p3] done (calls=%d)" % state["calls"], flush=True)


# ---------------- Phase 4: universe per-corp F-group sweep (감사보고서 정정 지도) ----------------
def p4_audit(uni):
    JJ = PAT["jungjung"]
    YG = "연결"
    GB = "감사보고서"
    agg = collections.defaultdict(lambda: dict(f_total=0, audit_sep=0, audit_cons=0, other_f=0, corr=0))
    corps = []
    truncated = 0
    for i, u in enumerate(uni):
        cc = u["corp_code"]
        rows = []
        tag = "aud:" + cc
        j = lst(tag, corp_code=cc, pblntf_ty="F", bgn_de="20050101", end_de=TODAY, last_reprt_at="N")
        rows += j.get("list") or []
        tp = int(j.get("total_page") or 1)
        tc = int(j.get("total_count") or 0)
        if tp >= 2:
            j2 = lst(tag + ":p2", corp_code=cc, pblntf_ty="F", bgn_de="20050101", end_de=TODAY,
                     last_reprt_at="N", page_no=2)
            rows += j2.get("list") or []
        trunc = tp > 2
        truncated += int(trunc)
        yr_min = None
        n_corr = 0
        for r in rows:
            d = "".join(ch for ch in str(r.get("rcept_dt", "")) if ch.isdigit())
            y = int(d[:4]) if len(d) >= 4 else 0
            nm = r.get("report_nm", "")
            a = agg[y]
            a["f_total"] += 1
            if GB not in nm:
                a["other_f"] += 1
            elif YG in nm:
                a["audit_cons"] += 1
            else:
                a["audit_sep"] += 1
            if JJ in nm:
                a["corr"] += 1
                n_corr += 1
            yr_min = y if yr_min is None else min(yr_min, y)
        corps.append(dict(corp_code=cc, ticker=u.get("ticker"), total_count=tc, n_rows=len(rows),
                          n_corr=n_corr, yr_min=yr_min, truncated=trunc))
        if i % 50 == 0:
            res["p4_audit"] = dict(by_year={str(k): v for k, v in sorted(agg.items())},
                                   corps=corps, n_truncated=truncated)
            save()
            print("[p4] %d/%d corps (calls=%d)" % (i + 1, len(uni), state["calls"]), flush=True)
    res["p4_audit"] = dict(by_year={str(k): v for k, v in sorted(agg.items())},
                           corps=corps, n_truncated=truncated)
    save()
    print("[p4] done (calls=%d)" % state["calls"], flush=True)


def main():
    try:
        p1_grid()
        uni = p2_probes()
        p3_majorstock(uni)
        p4_audit(uni)
        state["finished"] = time.strftime("%Y-%m-%d %H:%M:%S")
        save()
        print("[DONE] total calls=%d status013=%d" % (state["calls"], state["n_status013"]), flush=True)
    except Abort:
        print("[PARTIAL] saved up to abort. calls=%d" % state["calls"], flush=True)


if __name__ == "__main__":
    main()
