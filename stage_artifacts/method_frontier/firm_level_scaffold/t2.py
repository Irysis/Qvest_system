from fq073_customs_probe import *
import urllib.request, urllib.error, urllib.parse

def raw_get(url, ua=True, timeout=25):
    req = urllib.request.Request(url)
    if ua:
        req.add_header("User-Agent","Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=CTX) as r:
            return r.status, r.read().decode("utf-8","replace"), dict(r.headers)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8","replace"), dict(e.headers)
    except Exception as e:
        return -1, "EXC %s %s" % (type(e).__name__, e), {}

B = "https://apis.data.go.kr/1220000/nitemtrade/getNitemtradeList"
tests = [
 ("bogus-key",  B + "?serviceKey=ZZZBOGUSKEY123&strtYymm=202401&endYymm=202401&cntyCd=US"),
 ("no-key",     B + "?strtYymm=202401&endYymm=202401&cntyCd=US"),
 ("bare-path",  B),
 ("svc-root",   "https://apis.data.go.kr/1220000/nitemtrade"),
 ("org-root",   "https://apis.data.go.kr/1220000/"),
]
for tag,u in tests:
    st, body, hdr = raw_get(u)
    print("---- %-10s HTTP=%s  server=%s  ctype=%s" % (tag, st, hdr.get("Server"), hdr.get("Content-Type")))
    print("     BODY:", mask(re.sub(r"\s+"," ",body).strip())[:300])

# 대조군: 널리 열린 기상청 단기예보 (동일 게이트웨이, 우리 키)
KMA = "https://apis.data.go.kr/1360000/VilageFcstInfoService_2.0/getUltraSrtNcst"
u = KMA + "?serviceKey=" + KEY_ENC + "&pageNo=1&numOfRows=10&dataType=JSON&base_date=20260720&base_time=0600&nx=60&ny=127"
st, body, hdr = raw_get(u)
print("==== KMA-control HTTP=%s ctype=%s" % (st, hdr.get("Content-Type")))
print("     BODY:", mask(re.sub(r"\s+"," ",body).strip())[:400])
