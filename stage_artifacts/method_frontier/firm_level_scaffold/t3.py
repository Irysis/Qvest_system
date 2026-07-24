from fq073_customs_probe import *
import urllib.request, urllib.error

def raw(url, timeout=25):
    req = urllib.request.Request(url)
    req.add_header("User-Agent","Mozilla/5.0")
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=CTX) as r:
            return r.status, r.read().decode("utf-8","replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8","replace")
    except Exception as e:
        return -1, "EXC %s %s" % (type(e).__name__, e)

# 1) odcloud 재시험 (키 형태 2종) — 전역 키 유효성 판정용
for kf,kv in (("enc",KEY_ENC),("dec",urllib.parse.quote(KEY_DEC,safe="+/="))):
    u = "https://api.odcloud.kr/api/15083277/v1/uddi:00000000?page=1&perPage=1&serviceKey="+kv
    st,b = raw(u); print("odcloud[%s] HTTP=%s %s" % (kf, st, mask(re.sub(r"\s+"," ",b))[:180]))

# 2) infuser swagger 명세 (인증 불요) — 1220000 네임스페이스 전수
for ns in ["1220000/Itemtrade","1220000/nitemtrade","1220000/ItemtradeService",
           "1220000/tradeStat","1220000"]:
    st,b = raw("https://infuser.odcloud.kr/oas/docs?namespace="+urllib.parse.quote(ns,safe="/"))
    print("--- swagger ns=%-24s HTTP=%s len=%d" % (ns, st, len(b)))
    if st==200: print("    ", re.sub(r"\s+"," ",b)[:700])
