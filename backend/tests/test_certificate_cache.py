from concurrent.futures import ThreadPoolExecutor
from unittest.mock import Mock
import pytest
from app.certificate_cache import CertificateCache,CertificateResponse,CERTS_URL


def response(control='max-age=60'):
    return CertificateResponse(200,b'{"public-key":"certificate"}',{'Cache-Control':control})


def test_simultaneous_public_certificate_reads_fetch_once():
    cache=CertificateCache();fetch=Mock(return_value=response())
    with ThreadPoolExecutor(max_workers=10) as pool:
        results=list(pool.map(lambda _:cache.request(fetch,CERTS_URL),range(30)))
    assert all(r.data==response().data for r in results)
    assert fetch.call_count==1


def test_expired_certificate_is_not_used_on_network_failure():
    clock=[0];cache=CertificateCache(clock=lambda:clock[0]);fetch=Mock(return_value=response())
    cache.request(fetch,CERTS_URL);clock[0]=61;fetch.side_effect=RuntimeError('offline')
    with pytest.raises(RuntimeError):cache.request(fetch,CERTS_URL)
    fetch.side_effect=None;cache.request(fetch,CERTS_URL)
    assert fetch.call_count==3


def test_no_store_and_other_urls_are_not_cached():
    cache=CertificateCache();fetch=Mock(return_value=response('no-store,max-age=60'))
    for _ in range(2):cache.request(fetch,CERTS_URL)
    for _ in range(2):cache.request(fetch,'https://example.com')
    assert fetch.call_count==4
