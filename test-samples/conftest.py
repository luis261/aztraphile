import azure.functions as func
import json
import pytest


@pytest.fixture(scope="function")
def kv_sample_func_http_req():
    return func.HttpRequest(method="GET", url="/api/keyvault_function_sample", body=json.dumps({}).encode("utf8"))
