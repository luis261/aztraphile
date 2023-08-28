import azure.functions as func
import datetime
import logging


app = func.FunctionApp()

# in order for this function to run as intended, you will need to specify paths pointing to a valid storage container
# I have provided an easy way to create such containers via a powershell function named "Create-StorageContainer";
# to utilize it, just start a powershell session and import "aztra_utils.ps1":
# your-ps-prompt>. .\utils\aztra_utils.ps1
# then call "Create-StorageContainer" as such:
# your-ps-prompt>Create-StorageContainer "YourFunctionContainingGroup-rg" "yourstorageaccountsa" "test-slot-blobcontainer"
# after creating the storage container that will contain the blob file, you will need to setup (upload) a file (log.txt) that should be used as a target to write to by the sample functions

@app.function_name(name="timer_blob_appending_function")
@app.schedule(schedule="%Schedule%",
              arg_name="req",
              run_on_startup=False)
@app.blob_input(arg_name="inputblob",
                path="%BlobOutpath%/log.txt", # using dynamic path config via appsettings (resolves to different container on default/prod functions and functions running in the test slot)
                connection="")
@app.blob_output(arg_name="outputblob",
                path="%BlobOutpath%/log.txt", # using dynamic path config via appsettings (resolves to different container on default/prod functions and functions running in the test slot)
                connection="")
def appending_function(req: func.TimerRequest, inputblob: str, outputblob: func.Out[str]) -> None:
    utc_timestamp = datetime.datetime.utcnow().replace(
        tzinfo=datetime.timezone.utc).isoformat()
    outputblob.set(inputblob + "\nPython timer-triggered function ran at " + str(utc_timestamp))

@app.function_name(name="timer_blob_wiping_function")
@app.schedule(schedule="0 59 0 * * *",
              arg_name="req",
              run_on_startup=False)
@app.blob_output(arg_name="outputblob",
                path="%BlobOutpath%/log.txt",
                connection="")
def wiping_function(req: func.TimerRequest, outputblob: func.Out[str]) -> None:
    utc_timestamp = datetime.datetime.utcnow().replace(
        tzinfo=datetime.timezone.utc).isoformat()
    logging.info("Python timer-triggered function wiped the specified blob file at %s", utc_timestamp)
    outputblob.set("")
