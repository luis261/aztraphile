import azure.functions as func
import logging


app = func.FunctionApp()

# in order for this function to run as intended, you will need to specify paths pointing to valid storage containers (in the "blob_input" and "blob_output" decorators)
# I have provided an easy way to create such containers via a powershell function named "Create-StorageContainer":
# your-ps-prompt>Create-StorageContainer "YourFunctionContainingGroup-rg" "yourstorageaccountsa" "blob-replication-container"
# after creating the storage container(s) that will be used as input/output containers for the blob file copying, you will need to upload the input file that should be replicated
@app.function_name(name="http_blob_replication_function_sample")
@app.route(route="file")
# if you want to separate/have to access the in- and output files on a different storage account (other than the one used to host the app),
# you will either have to obtain the appropriate connection string and save it under a key in the appsettings of the app and then configure that key as the connection parameter in the decorator above OR look into identity based connections
@app.blob_input(arg_name="inputblob",
                path="blob-replication-container/input.txt",
                connection="") # assuming input blob container in default storage account (used to host the app), therefore leaving connection empty
@app.blob_output(arg_name="outputblob",
                path="blob-replication-container/replicated_output.txt",
                connection="") # assuming output blob container in default storage account (used to host the app), therefore leaving connection empty
# when acquiring an URL to invoke this sample (via the "Get Function Url" option in the portal), be sure to avoid the "blobs_extension (system key)" option,
# which might be selected by default in the portal and won't lead to successful requests in my experience
# instead, just choose any of the other listed options, e.g. "default (function key)"
def main(req: func.HttpRequest, inputblob: str, outputblob: func.Out[str]) -> func.HttpResponse:
    logging.info(f"Python HTTP-triggered function processed {len(inputblob)} bytes")
    outputblob.set(inputblob)
    logging.info("Successfully copied the blob")
    return func.HttpResponse("Copied the given input blob to the specified output blob")
