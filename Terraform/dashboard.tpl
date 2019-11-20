{
  "lenses": {
    "0": {
      "order": 0,
      "parts": {
        "0": {
          "position": {
            "x": 0,
            "y": 0,
            "rowSpan": 2,
            "colSpan": 4
          },
          "metadata": {
            "inputs": [],
            "type": "Extension/HubsExtension/PartType/MarkdownPart",
            "settings": {
              "content": {
                "settings": {
                  "content": "__Description__\n\nThis project contains a hub & spoke Virtual Datacenter deployment. See <a href='https://github.com/geekzter/azure-vdc' target='_blank'>project on GitHub</a> for a description and source code.\n",
                  "subtitle": "",
                  "title": "Automated VDC"
                }
              }
            }
          }
        },
        "1": {
          "position": {
            "x": 4,
            "y": 0,
            "rowSpan": 3,
            "colSpan": 7
          },
          "metadata": {
            "inputs": [
              {
                "name": "partTitle",
                "value": "VDC Resources by Suffix",
                "isOptional": true
              },
              {
                "name": "query",
                "value": "Resources | where tags['application']=='Automated VDC' and tags['suffix']=='${suffix}'| summarize ResourceCount=count() by Environment=tostring(tags['environment']), Workspace=tostring(tags['workspace']), ResourceGroup=resourceGroup | order by ResourceGroup asc",
                "isOptional": true
              },
              {
                "name": "chartType",
                "isOptional": true
              },
              {
                "name": "isShared",
                "isOptional": true
              },
              {
                "name": "queryId",
                "value": "183f4042-6fe0-4362-b2bd-7575cf2ddf98",
                "isOptional": true
              }
            ],
            "type": "Extension/HubsExtension/PartType/ArgQueryGridTile",
            "settings": {}
          }
        },
        "2": {
          "position": {
            "x": 11,
            "y": 0,
            "rowSpan": 1,
            "colSpan": 2
          },
          "metadata": {
            "inputs": [
              {
                "name": "id",
                "value": "${subscription}/resourceGroups/${prefix}-${environment}-${suffix}/providers/Microsoft.Compute/virtualMachines/${prefix}-${environment}-${suffix}-bastion",
                "isOptional": true
              },
              {
                "name": "resourceId",
                "isOptional": true
              },
              {
                "name": "menuid",
                "isOptional": true
              }
            ],
            "type": "Extension/HubsExtension/PartType/ResourcePart",
            "asset": {
              "idInputName": "id"
            }
          }
        },
        "3": {
          "position": {
            "x": 13,
            "y": 0,
            "rowSpan": 4,
            "colSpan": 5
          },
          "metadata": {
            "inputs": [
              {
                "name": "resourceGroup",
                "isOptional": true
              },
              {
                "name": "id",
                "value": "${subscription}/resourceGroups/${prefix}-${environment}-paasapp-${suffix}",
                "isOptional": true
              }
            ],
            "type": "Extension/HubsExtension/PartType/ResourceGroupMapPinnedPart"
          }
        },
        "4": {
          "position": {
            "x": 18,
            "y": 0,
            "rowSpan": 7,
            "colSpan": 5
          },
          "metadata": {
            "inputs": [
              {
                "name": "resourceGroup",
                "isOptional": true
              },
              {
                "name": "id",
                "value": "${subscription}/resourceGroups/${prefix}-${environment}-iaasapp-${suffix}",
                "isOptional": true
              }
            ],
            "type": "Extension/HubsExtension/PartType/ResourceGroupMapPinnedPart"
          }
        },
        "5": {
          "position": {
            "x": 23,
            "y": 0,
            "rowSpan": 13,
            "colSpan": 5
          },
          "metadata": {
            "inputs": [
              {
                "name": "resourceGroup",
                "isOptional": true
              },
              {
                "name": "id",
                "value": "${subscription}/resourceGroups/${prefix}-${environment}-${suffix}",
                "isOptional": true
              }
            ],
            "type": "Extension/HubsExtension/PartType/ResourceGroupMapPinnedPart"
          }
        },
        "6": {
          "position": {
            "x": 0,
            "y": 2,
            "rowSpan": 2,
            "colSpan": 4
          },
          "metadata": {
            "inputs": [
              {
                "name": "ResourceId",
                "value": "${subscription}/resourceGroups/${prefix}-${environment}-${suffix}/providers/microsoft.insights/components/${prefix}-${environment}-${suffix}-insights"
              },
              {
                "name": "ComponentId",
                "value": {
                  "Name": "${prefix}-${environment}-${suffix}-insights",
                  "ResourceGroup": "${prefix}-${environment}-${suffix}",
                  "SubscriptionId": "/subscriptions/84c1a2c7-585a-4753-ad28-97f69618cf12"
                }
              },
              {
                "name": "TargetBlade",
                "value": "Failures"
              },
              {
                "name": "DataModel",
                "value": {
                  "clientTypeMode": "Server",
                  "experience": 1,
                  "grain": "5m",
                  "prefix": "let OperationIdsWithExceptionType = (excType: string) { exceptions | where timestamp > ago(1d) \n    | where tobool(iff(excType == \"null\", isempty(type), type == excType)) \n    | distinct operation_ParentId };\nlet OperationIdsWithFailedReqResponseCode = (respCode: string) { requests | where timestamp > ago(1d)\n    | where iff(respCode == \"null\", isempty(resultCode), resultCode == respCode) and success == false \n    | distinct id };\nlet OperationIdsWithFailedDependencyType = (depType: string) { dependencies | where timestamp > ago(1d)\n    | where iff(depType == \"null\", isempty(type), type == depType) and success == false \n    | distinct operation_ParentId };\nlet OperationIdsWithFailedDepResponseCode = (respCode: string) { dependencies | where timestamp > ago(1d)\n    | where iff(respCode == \"null\", isempty(resultCode), resultCode == respCode) and success == false \n    | distinct operation_ParentId };\nlet OperationIdsWithExceptionBrowser = (browser: string) { exceptions | where timestamp > ago(1d)\n    | where tobool(iff(browser == \"null\", isempty(client_Browser), client_Browser == browser)) \n    | distinct operation_ParentId };",
                  "selectedOperation": null,
                  "selectedOperationName": null,
                  "timeContext": {
                    "createdTime": "2019-11-19T12:07:25.044Z",
                    "durationMs": 86400000,
                    "endTime": null,
                    "grain": 1,
                    "isInitialTime": false,
                    "useDashboardTimeRange": false
                  },
                  "version": "1.0.0"
                },
                "isOptional": true
              },
              {
                "name": "Version",
                "value": "1.0"
              }
            ],
            "type": "Extension/AppInsightsExtension/PartType/FailuresCuratedPinnedChartPart",
            "asset": {
              "idInputName": "ResourceId",
              "type": "ApplicationInsights"
            }
          }
        },
        "7": {
          "position": {
            "x": 4,
            "y": 3,
            "rowSpan": 5,
            "colSpan": 7
          },
          "metadata": {
            "inputs": [
              {
                "name": "ComponentId",
                "value": {
                  "SubscriptionId": "84c1a2c7-585a-4753-ad28-97f69618cf12",
                  "ResourceGroup": "${prefix}-${environment}-${suffix}",
                  "Name": "${prefix}-${environment}-${suffix}-loganalytics",
                  "ResourceId": "${subscription}/resourcegroups/${prefix}-${environment}-${suffix}/providers/microsoft.operationalinsights/workspaces/${prefix}-${environment}-${suffix}-loganalytics"
                }
              },
              {
                "name": "Query",
                "value": "// Taken from https://docs.microsoft.com/en-us/azure/firewall/log-analytics-samples\nAzureDiagnostics\n| where Category == \"AzureFirewallApplicationRule\" \n| parse msg_s with Protocol \" request from \" SourceIP \":\" SourcePortInt:int \" \" TempDetails\n| parse TempDetails with \"was \" Action1 \". Reason: \" Rule1\n| parse TempDetails with \"to \" FQDN \":\" TargetPortInt:int \". Action: \" Action2 \".\" *\n| parse TempDetails with * \". Rule Collection: \" RuleCollection2a \". Rule:\" Rule2a\n| parse TempDetails with * \"Deny.\" RuleCollection2b \". Proceeding with\" Rule2b\n| extend TargetPort = tostring(TargetPortInt)\n| extend Action1 = case(Action1 == \"Deny\",\"Deny\",\"Unknown Action\")\n| extend Action = case(Action2 == \"\",Action1,Action2),Rule = case(Rule2a == \"\", case(Rule1 == \"\",case(Rule2b == \"\",\"N/A\", Rule2b),Rule1),Rule2a), \nRuleCollection = case(RuleCollection2b == \"\",case(RuleCollection2a == \"\",\"No rule matched\",RuleCollection2a), RuleCollection2b),FQDN = case(FQDN == \"\", \"N/A\", FQDN),TargetPort = case(TargetPort == \"\", \"N/A\", TargetPort)\n| project TimeGenerated, SourceIP, FQDN, TargetPort, Action ,RuleCollection, Rule\n| order by TimeGenerated desc\n| where Action == \"Deny\"\n"
              },
              {
                "name": "TimeRange",
                "value": "P1D"
              },
              {
                "name": "Version",
                "value": "1.0"
              },
              {
                "name": "PartId",
                "value": "dd66a9d3-5b28-4ecf-b169-7dd179535af1"
              },
              {
                "name": "PartTitle",
                "value": "Analytics"
              },
              {
                "name": "PartSubTitle",
                "value": "${prefix}-${environment}-${suffix}-loganalytics"
              },
              {
                "name": "resourceTypeMode",
                "value": "workspace"
              },
              {
                "name": "ControlType",
                "value": "AnalyticsGrid"
              },
              {
                "name": "Dimensions",
                "isOptional": true
              },
              {
                "name": "DashboardId",
                "isOptional": true
              },
              {
                "name": "SpecificChart",
                "isOptional": true
              }
            ],
            "type": "Extension/AppInsightsExtension/PartType/AnalyticsPart",
            "settings": {
              "content": {
                "PartTitle": "Denied outbound HTTP Traffic",
                "PartSubTitle": "${prefix}-${environment}-${suffix}-loganalytics"
              }
            },
            "asset": {
              "idInputName": "ComponentId",
              "type": "ApplicationInsights"
            }
          }
        },
        "8": {
          "position": {
            "x": 0,
            "y": 4,
            "rowSpan": 2,
            "colSpan": 4
          },
          "metadata": {
            "inputs": [
              {
                "name": "id",
                "value": "${subscription}/resourcegroups/${prefix}-${environment}-${suffix}/providers/Microsoft.OperationalInsights/workspaces/${prefix}-${environment}-${suffix}-loganalytics/views/Updates(${prefix}-${environment}-${suffix}-loganalytics)"
              },
              {
                "name": "solutionId",
                "isOptional": true
              },
              {
                "name": "timeInterval",
                "value": {
                  "_Now": "2019-11-19T12:09:05.945Z",
                  "_duration": 86400000,
                  "_end": null
                },
                "isOptional": true
              },
              {
                "name": "timeRange",
                "binding": "timeRange",
                "isOptional": true
              }
            ],
            "type": "Extension/Microsoft_OperationsManagementSuite_Workspace/PartType/ViewTileIFramePart"
          }
        },
        "9": {
          "position": {
            "x": 0,
            "y": 6,
            "rowSpan": 2,
            "colSpan": 4
          },
          "metadata": {
            "inputs": [
              {
                "name": "id",
                "value": "${subscription}/resourcegroups/${prefix}-${environment}-${suffix}/providers/Microsoft.OperationalInsights/workspaces/${prefix}-${environment}-${suffix}-loganalytics/views/AzureAppGatewayAnalytics(${prefix}-${environment}-${suffix}-loganalytics)"
              },
              {
                "name": "solutionId",
                "isOptional": true
              },
              {
                "name": "timeInterval",
                "value": {
                  "_Now": "2019-11-19T12:09:05.945Z",
                  "_duration": 86400000,
                  "_end": null
                },
                "isOptional": true
              },
              {
                "name": "timeRange",
                "binding": "timeRange",
                "isOptional": true
              }
            ],
            "type": "Extension/Microsoft_OperationsManagementSuite_Workspace/PartType/ViewTileIFramePart"
          }
        },
        "10": {
          "position": {
            "x": 0,
            "y": 8,
            "rowSpan": 2,
            "colSpan": 4
          },
          "metadata": {
            "inputs": [
              {
                "name": "id",
                "value": "${subscription}/resourcegroups/${prefix}-${environment}-${suffix}/providers/Microsoft.OperationalInsights/workspaces/${prefix}-${environment}-${suffix}-loganalytics/views/AzureSQLAnalytics(${prefix}-${environment}-${suffix}-loganalytics)"
              },
              {
                "name": "solutionId",
                "isOptional": true
              },
              {
                "name": "timeInterval",
                "value": {
                  "_Now": "2019-11-19T12:10:07.715Z",
                  "_duration": 86400000,
                  "_end": null
                },
                "isOptional": true
              },
              {
                "name": "timeRange",
                "binding": "timeRange",
                "isOptional": true
              }
            ],
            "type": "Extension/Microsoft_OperationsManagementSuite_Workspace/PartType/ViewTileIFramePart"
          }
        },
        "11": {
          "position": {
            "x": 0,
            "y": 10,
            "rowSpan": 2,
            "colSpan": 4
          },
          "metadata": {
            "inputs": [
              {
                "name": "id",
                "value": "${subscription}/resourcegroups/${prefix}-${environment}-${suffix}/providers/Microsoft.OperationalInsights/workspaces/${prefix}-${environment}-${suffix}-loganalytics/views/AzureAppGatewayAnalytics(${prefix}-${environment}-${suffix}-loganalytics)"
              },
              {
                "name": "solutionId",
                "isOptional": true
              },
              {
                "name": "timeInterval",
                "value": {
                  "_Now": "2019-11-19T12:10:07.715Z",
                  "_duration": 86400000,
                  "_end": null
                },
                "isOptional": true
              },
              {
                "name": "timeRange",
                "binding": "timeRange",
                "isOptional": true
              }
            ],
            "type": "Extension/Microsoft_OperationsManagementSuite_Workspace/PartType/ViewTileIFramePart"
          }
        }
      }
    }
  },
  "metadata": {
    "model": {
      "timeRange": {
        "value": {
          "relative": {
            "duration": 24,
            "timeUnit": 1
          }
        },
        "type": "MsPortalFx.Composition.Configuration.ValueTypes.TimeRange"
      },
      "filterLocale": {
        "value": "en-us"
      },
      "filters": {
        "value": {
          "MsPortalFx_TimeRange": {
            "model": {
              "format": "utc",
              "granularity": "auto",
              "relative": "24h"
            },
            "displayCache": {
              "name": "UTC Time",
              "value": "Past 24 hours"
            },
            "filteredPartIds": [
              "StartboardPart-AnalyticsPart-ee3554d4-02d6-422e-9c9c-34287665a057"
            ]
          }
        }
      }
    }
  }
}
