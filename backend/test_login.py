import urllib.request, json

url = 'http://127.0.0.1:8000/login'
payload = {
    'email': 'testuser+auto@example.com',
    'password': 'Passw0rd!'
}

data = json.dumps(payload).encode('utf-8')
req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'}, method='POST')

try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        print('STATUS:', resp.status)
        body = resp.read().decode('utf-8')
        print('RESPONSE:', body)
except Exception as e:
    print('ERROR:', repr(e))
