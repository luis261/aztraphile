from ..function_app import main
import os
from unittest import mock


@mock.patch.dict(os.environ, {}, clear=True)
def test_http_keyvault_sample_config_miss(kv_sample_func_http_req):
    main_func = main.build().get_user_function()

    resp = main_func(kv_sample_func_http_req)

    assert resp.status_code == 500
    assert "no variable with name" in resp.get_body().decode("utf-8")

@mock.patch.dict(os.environ, {"ExampleSecret": "@Microsoft.KeyVault(SecretUri=https://kvname-kv.vault.azure.net/secrets/ExampleSecret)"}, clear=True)
def test_http_keyvault_sample_config_unresolved_hit(kv_sample_func_http_req):
    main_func = main.build().get_user_function()

    resp = main_func(kv_sample_func_http_req)

    assert resp.status_code == 500
    assert "signatures indicating an unresolved secret" in resp.get_body().decode("utf-8")

@mock.patch.dict(os.environ, {"ExampleSecret": "1234"}, clear=True)
def test_http_keyvault_sample_config_hit(kv_sample_func_http_req):
    main_func = main.build().get_user_function()

    resp = main_func(kv_sample_func_http_req)

    assert resp.status_code == 200
    assert "has been logged" in resp.get_body().decode("utf-8")
