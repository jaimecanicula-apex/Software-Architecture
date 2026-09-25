# Shared Azure Monitor workbook: the website dashboard people open in the portal.
# All queries run against the Log Analytics workspace (Front Door logs and
# workspace-based Application Insights tables).

locals {
  law_id = azurerm_log_analytics_workspace.this.id

  front_door_access = <<-KQL
    AzureDiagnostics
    | where Category == "FrontDoorAccessLog"
    | extend status = toint(column_ifexists("httpStatusCode_s", "0")),
             latencyMs = todouble(column_ifexists("timeTaken_s", "0")) * 1000,
             uri = tostring(column_ifexists("requestUri_s", "")),
             cache = tostring(column_ifexists("cacheStatus_s", ""))
  KQL

  workbook_queries = [
    {
      name  = "availability"
      title = "Availability by test (%)"
      viz   = "timechart"
      query = <<-KQL
        AppAvailabilityResults
        | summarize Availability = round(100.0 * countif(Success == true) / count(), 2) by bin(TimeGenerated, 1h), Name
      KQL
    },
    {
      name  = "availability-by-location"
      title = "Availability by test location"
      viz   = "table"
      query = <<-KQL
        AppAvailabilityResults
        | summarize Tests = count(), Failed = countif(Success == false), AvgDurationMs = round(avg(DurationMs), 0) by Location
        | order by Failed desc
      KQL
    },
    {
      name  = "requests-by-status"
      title = "Requests by status class"
      viz   = "timechart"
      query = <<-KQL
        ${local.front_door_access}
        | summarize Requests = count() by bin(TimeGenerated, 15m), StatusClass = strcat(tostring(status / 100), "xx")
      KQL
    },
    {
      name  = "latency"
      title = "Edge latency (ms): p50 and p95"
      viz   = "timechart"
      query = <<-KQL
        ${local.front_door_access}
        | summarize p50 = percentile(latencyMs, 50), p95 = percentile(latencyMs, 95) by bin(TimeGenerated, 15m)
      KQL
    },
    {
      name  = "top-pages"
      title = "Most requested paths"
      viz   = "table"
      query = <<-KQL
        ${local.front_door_access}
        | summarize Requests = count(), Errors = countif(status >= 400) by uri
        | top 20 by Requests
      KQL
    },
    {
      name  = "cache"
      title = "Edge cache hit ratio"
      viz   = "piechart"
      query = <<-KQL
        ${local.front_door_access}
        | summarize Requests = count() by cache
      KQL
    },
    {
      name  = "waf-actions"
      title = "WAF actions over time"
      viz   = "timechart"
      query = <<-KQL
        AzureDiagnostics
        | where Category == "FrontDoorWebApplicationFirewallLog"
        | summarize Requests = count() by bin(TimeGenerated, 15m), Action = tostring(column_ifexists("action_s", ""))
      KQL
    },
    {
      name  = "waf-rules"
      title = "Top WAF rules triggered"
      viz   = "table"
      query = <<-KQL
        AzureDiagnostics
        | where Category == "FrontDoorWebApplicationFirewallLog"
        | summarize Hits = count() by Rule = tostring(column_ifexists("ruleName_s", "")), Action = tostring(column_ifexists("action_s", ""))
        | top 20 by Hits
      KQL
    },
    {
      name  = "origin-health"
      title = "Origin health probe results"
      viz   = "timechart"
      query = <<-KQL
        AzureDiagnostics
        | where Category == "FrontDoorHealthProbeLog"
        | summarize Probes = count() by bin(TimeGenerated, 15m), Status = tostring(column_ifexists("httpStatusCode_s", ""))
      KQL
    },
    {
      name  = "alerts"
      title = "Alerts fired"
      viz   = "table"
      query = <<-KQL
        AzureActivity
        | where CategoryValue == "Alert" or OperationNameValue has "alerts"
        | project TimeGenerated, OperationNameValue, ActivityStatusValue, ResourceGroup
        | top 50 by TimeGenerated
      KQL
    },
  ]

  workbook = {
    version = "Notebook/1.0"
    items = concat(
      [
        {
          type = 1
          name = "header"
          content = {
            json = "## Static website: ${var.name_suffix}\nAvailability, traffic, latency, WAF and alerts. Front Door panels stay empty in environments without Front Door."
          }
        },
        {
          type = 9
          name = "parameters"
          content = {
            version = "KqlParameterItem/1.0"
            style   = "pills"
            parameters = [
              {
                id         = "7c1d8a4e-2f0b-4c56-9a53-0e2b1f6d3a10"
                version    = "KqlParameterItem/1.0"
                name       = "TimeRange"
                label      = "Time range"
                type       = 4
                isRequired = true
                value      = { durationMs = 86400000 }
                typeSettings = {
                  selectableValues = [
                    { durationMs = 3600000 },
                    { durationMs = 14400000 },
                    { durationMs = 86400000 },
                    { durationMs = 604800000 },
                    { durationMs = 2592000000 },
                  ]
                }
              },
            ]
          }
        },
      ],
      [
        for q in local.workbook_queries : {
          type        = 3
          name        = q.name
          customWidth = "50"
          content = {
            version                  = "KqlItem/1.0"
            title                    = q.title
            query                    = q.query
            size                     = 0
            timeContextFromParameter = "TimeRange"
            queryType                = 0
            resourceType             = "microsoft.operationalinsights/workspaces"
            crossComponentResources  = [local.law_id]
            visualization            = q.viz
          }
        }
      ],
    )
    fallbackResourceIds = [local.law_id]
    "$schema"           = "https://github.com/Microsoft/Application-Insights-Workbooks/blob/master/schema/workbook.json"
  }
}

resource "azurerm_application_insights_workbook" "site" {
  name                = uuidv5("url", "https://workbooks/static-website/${var.name_suffix}")
  resource_group_name = var.resource_group_name
  location            = var.location
  display_name        = "Static website - ${var.name_suffix}"
  source_id           = lower(local.law_id)
  category            = "workbook"
  data_json           = jsonencode(local.workbook)
  tags                = var.tags
}
