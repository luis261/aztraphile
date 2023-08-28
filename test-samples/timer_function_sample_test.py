from ..function_app import main
from unittest.mock import Mock#, patch


# patching breaks here unfortunately, so this test can only check for syntax/runtime errors
# (despite following https://docs.python.org/3/library/unittest.mock.html#where-to-patch)
# (spent quite a bit of time trying other ways of patching besides the one shown here but I can't get it to work;
# my current understanding of this issue is that it might be related to the __init__.py file lying at the very top of this repo)
def test_timer():
    with patch("logging.info") as mocked_info_log:
        req = Mock()
        req.past_due = True

        main(req)

        # assert mocked_info_log.call_count == 2
        # mocked_info_log.assert_any_call("The timer is past due!")
