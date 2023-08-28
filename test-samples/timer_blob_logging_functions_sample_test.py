from ..function_app import appending_function, wiping_function
import random
import string
from unittest.mock import Mock


def test_appending_function():
    req = Mock()
    input_blob = "".join(random.SystemRandom().choice(string.ascii_uppercase + string.digits) for _ in range(random.randrange(100)))
    output_blob = Mock()

    resp = appending_function.build().get_user_function()(req, input_blob, output_blob)

    assert len(output_blob.set.call_args.args[0]) > len(input_blob)

def test_wiping_function():
    req = Mock()
    output_blob = Mock()

    resp = wiping_function.build().get_user_function()(req, output_blob)

    output_blob.set.assert_called_with("")
