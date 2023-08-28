import azure.functions as func
from ..function_app import main
import json
import pytest


@pytest.mark.parametrize(
    "query_params, input_body, status_code, returned_body_keyword",
    [
        ({}, {}, 200, "executed successfully"),
        ({"name": "Bob"}, {}, 200, "Hello, Bob"),
        ({}, {"name": "Bob"}, 200, "Hello, Bob"),
        ({"name": "Bob"}, {"name": "Bob"}, 200, "Hello, Bob"),
    ]
)
def test_http_default_sample_param_variants(query_params, input_body, status_code, returned_body_keyword):
    req = func.HttpRequest(method="GET", url="/api/http_function_sample",
        params=query_params,
        body=json.dumps(input_body).encode("utf8")
    )
    main_func = main.build().get_user_function()

    resp = main_func(req)

    assert resp.status_code == status_code
    assert returned_body_keyword in resp.get_body().decode("utf-8")
