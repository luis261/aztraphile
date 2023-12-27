import azure.functions as func
import logging


app = func.FunctionApp()

@app.function_name(name="http_function_sample")
@app.route(route="req")
def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Python HTTP-triggered function processed a request.")

    name = req.params.get('name')
    if not name:
        try:
            req_body = req.get_json()
        except ValueError:
            pass
        else:
            name = req_body.get('name')

    if name:
        """
        directly embedding user-controlled data like this (without escaping it) is only ok because the mimetype is `text/plain` by default
        https://learn.microsoft.com/en-us/python/api/azure-functions/azure.functions.httpresponse?view=azure-python#parameters
        """
        return func.HttpResponse(
            f"Hello, {name}. This HTTP-triggered function executed successfully."
         )
    else:
        return func.HttpResponse(
            "This HTTP-triggered function executed successfully. Pass a name in the query string or in the request body for a personalized response.",
            status_code=200
        )
