import azure.functions as func
import logging
try:
    import kv_util as kv
# when running the tests, local modules have to be imported differently (as opposed to running on the function host in Azure)
except (ImportError, ModuleNotFoundError):
    from . import kv_util as kv


app = func.FunctionApp()

@app.function_name(name="keyvault_function_sample")
@app.route(route="req")
def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Python HTTP-triggered function processed a request.")

    secret_name = "ExampleSecret"
    try:
        _ = kv.read_secret_via_appsetting(secret_name, verbose=True)
        return func.HttpResponse(f"The value of the environment variable configured in the appsettings under \"{secret_name}\" has been logged in Azure.")
    except Exception as e:
        return func.HttpResponse(str(e), status_code=500)
