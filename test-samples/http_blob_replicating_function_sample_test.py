import azure.functions as func
from ..function_app import main
import json
from unittest.mock import Mock


def test_http_blob_replicating_sample():
    req = func.HttpRequest(method="GET", url="/api/http_blob_replication_function_sample", body=json.dumps({}).encode("utf8"))
    input_blob = Mock()
    input_blob.__len__ = lambda _ : 1
    output_blob = Mock()
    main_func = main.build().get_user_function()

    resp = main_func(req, input_blob, output_blob)

    assert resp.status_code == 200
    output_blob.set.assert_called_with(input_blob)
