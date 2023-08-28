import azure.functions as func
import datetime
import logging


app = func.FunctionApp()

@app.function_name(name="timer_function_sample")
@app.schedule(schedule="0 */5 * * * *",
              arg_name="req",
              run_on_startup=False)
def main(req: func.TimerRequest) -> None:
    if req.past_due:
        logging.info('The timer is past due!')
    utc_timestamp = datetime.datetime.utcnow().replace(
        tzinfo=datetime.timezone.utc).isoformat()
    logging.info('Python timer-triggered function ran at %s', utc_timestamp)
