# aztraphile
TODO \<insert screenshot of output as seen on startup\>

## Introduction
aztraphile 🌩️ is an automation tool intended to help you accelerate the process of rolling out new Python Azure Functions 🚀 as well as ensuring you are adequately equipped to keep those Functions running smoothly. Overall, it entails:
- automated resource provisioning 🏗️ in Azure
- pre-written code 📦 (and unittest 🔬) samples using the brand new V2 programming model for Python Azure Functions
- automated setup of Azure DevOps constructs that assure quality 📋 while conducting continuous deployment ⚙️
- flexible monitoring 💡 and alerting 🚨 setup capabilities designed to fit your needs

## Feature summary/showcase
### Automated provisioning in Azure
the following resources are created by the main script:
- Storage Account
  - required to host the App
  - can hold Storage Containers for the Function App to read from and write to (Blob) files
- App Service Plan
  - consists of the underlying VM's that host the App
  - makes up the majority of the costs of running the App
- Function App
  - this is where your code gets executed
  - contains your application settings (environment variables)
  - contains a test slot that's configured to be an environment nearly identical to PROD and which is also a target for automatic deployments
- Application Insights
- Key Vault (only created if "createKeyVault" is set to true in the config file)
  - it can securely store confidential data (such as API credentials) for you in the form of secrets
  - a secret with name "ExampleSecret" is created by default, you can use it for experimentation purposes
- an action group which handles the sending of E-Mail alerts specified in the monitoring section below (if there is at least one E-Mail address in the config file under "alertRecipientMailAddresses", otherwise NO alerts are created)
  - having automated E-Mail alerts in place means you don't have to proactively check the status of your Functions

![overview diagramm of resulting Azure architecture as setup by the script](./readme_attachments/azure_overview.png)

### Function samples and corresponding unittests
- an HTTP Function that replies with a message depending on the passed parameters
- an HTTP Function that reads a secret from the keyvault (so you have code you can reference showing how to properly store credentials your code needs to access)
- a timer triggered Function
- an HTTP Function that copies a Blob file
- a timer triggered Function that logs to a Blob file (and another function that periodically clears that file)
- there are unit test samples for all of these Functions (written using pytest)
  - since you inherit a functioning assortment of tests that are properly integrated into your deployment process from the start, the usual entry barrier of having to setup a test-suite from scratch is avoided
  - this way, you can make it a habit to using automated testing for your Azure Functions from the start instead of putting it off and accruing tech debt over time

### Setup of Azure DevOps constructs
the following is a description of the setup in Azure DevOps:
- Service Connection (needed to connect to Azure from the Azure Devops pipeline when conducting the automatic deployments)
- git repository to hold your code/the sample functions
- pipeline defined by an azure-pipelines.yml file which carries out the testing and deployment process
    - automatically deploys the latest commit on the main branch to Azure
    - variables for that pipeline that allow you to parameterize certain aspects relating to your code in Azure, e.g. configuring a CRON schedule for your test slot that differs from the one used productively (to avoid load interference)
    - when deploying your code, the pipeline also configures the appsettings of the Function according to the "appsettings.json" file that is tracked by git
      - this way, configuration changes also undergo a peer review process and can be tracked over time
      - just make sure to never directly store credentials in the mentioned JSON file; instead, store them as a secret in the Key Vault as shown in the corresponding function samples (you do need a Key Vault reference in the appsettings file though, as shown here)
    - the pipeline also integrates with the builtin Azure Devops test reporting feature TODO \<insert screenshot of example test report\>
- repository policy ensuring PRs targeting main can't get merged unless they have at least 2 approvers
- build policy that ensures pending changes get deployed to the test slot once a PR is created
  - PRs that cause failing tests are blocked from merging until all unittests are passed
  - this policy, together with the test slot mentioned above (which is used as a deployment target instead of PROD when the pipeline runs for changes proposed in a PR) enables you to verify new versions of your code in a safe, isolated environment, even if you haven't bothered to keep your code covered with unittests

TODO \<insert anatomy of deployment, hosting & runtime interactions (depicts code lifecycle stages)\>

### Monitoring and alerting
- this project contains code that can plot graphs in the console (by including this version of Show-Graph: https://gist.github.com/PrateekKumarSingh/9168afa8e7c7da801efa858705fb485b)
  - that feature is in "Show-FaMetric" which graphically displays CPU and memory consumption
  - displaying key metrics over configurable spans of times like that can help you recognize patterns at first glance you might have missed otherwise
- by default (if the condition described in the provisioning section above is met in the config file), you will receive E-Mail alerts pertaining to your function
  - there is a metric alert rule that triggers if the average CPU percentage is over 90
  - there is a metric alert rule that triggers if the maximum memory usage percentage is over 90
  - additionally, a log search alert rule is created that activates if any exceptions occurred in the execution of your Functions during the last hour
- instead of using such builtin push-based constructs, you could easily opt for a polling-based approach by running queries periodically using "Fetch-FaMetrics" and "Fetch-FaInsights" (a simple example of expre-built keyword filtering for Fetchfainsights is shown in the "Advanced features" section, you can go explore the code or run the Get-Help commandlet on the mentioned utility functions for in-depth documentation)

TODO: pic mail alert

### Additional orchestration features
there are lots of orchestration/utility features in the form of powerhsell functions stored in ```aztra\_utils.ps1```. You can run them locally, so you don'T have to bother with the Azure portal
- ```Set-AzPipelinesVar``` can create/update DevOps build variables for you
- ```Create-StorageContainer``` let's you create Storage Containers
- ```Set-KvSecret``` let's you create secrets
- ```Restart-FunctionCompletely``` performs a full restart on a Function App; you can also shut it off prematurely to keep the App shut off (charges still apply)
- ```Invoke-Function``` let's you call a Function via it's HTTP API

## Advanced usage
- you can try to be extra smart about your testing strategy and achieve a level of efficiency that's usually only achievable with proper suites of unittests (even without covering your code in unittests and maintaining them)
  - (you could also use this strategy complementary to your unittest, I definitely don't discourage having unittests anyway!)
  - the way to achieve efficient integration/system-level testing in this context is via leveraging the automatic deployments that trigger on PR creation
    - let's say you have an important service that is the main consumer of you functions API
    - but you also have a dashboard internal to your team that's used to guide/support some day-to-day manual activity
    - or just another, less critical service
    - or maybe just some other legacy service your in the process of phasing out anyway
    - configure that non-critical service/dashboard to use the URL pointing to the test slot => can then observe new changes in a PR being "tested" automatically with limited potential for repercussions b4 merging into main thus moving them to PROD
    - or maybe there's another team that's pushing for new features you are responsible for, which they need in a new service they're currently getting off the ground
    - you could offer them access to test slot for faster access to new features ... under the caveat that it might be unstable (but guess what, since they are still in DEV phase, they might prefer faster access to features over stability)
- filtering logs based on their message ```Fetch-FaInsights -InsightsSpecifier "logs" -Raw | Where-Object (Build-LogMessageSieve "executed")```
- polling of logs (live, without duplicated events) and optional filtering based on a passed query (coming soon)
- live metric plotting in a console window (coming soon)
