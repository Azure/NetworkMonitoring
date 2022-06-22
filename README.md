![0]

# NetworkMonitoring

**Azure / NetworkMonitoring** is a repository for open source Azure network monitoring tools. Each tool or collection of tools lives in a folder under the main NetworkMonitoring repo.

The current tools/tool-sets are:
#### AzureCT
The Azure Connectivity Toolkit ([AzureCT][AzureCT]) is a PowerShell module and collection of server side web pages will test, generate, collect, store, and display performance and availability statistics of the network between you and Azure. The two main areas of functionality are:
 - A network availability test (Get-AzureNetworkAvailability) that runs pings and traceroutes over an extended period of time to show end to end availability and hop latency.
 - A bandwidth and latency tester (Get-LinkPerformance) that runs a series of iPerf3 load tests while concurently doing a TCP ping to show latency under various loads.

<!--Image References-->
[0]: ./AzureCT/media/AzureNMT.png "Azure Network Monitoring Tools"

<!--Link References-->
[AzureCT]: https://github.com/Azure/NetworkMonitoring/tree/master/AzureCT "AzureCT tree"
