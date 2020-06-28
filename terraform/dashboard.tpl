{
  "lenses": {
    "0": {
      "order": 0,
      "parts": {
        "0": {
          "metadata": {
            "inputs": [],
            "settings": {
              "content": {
                "settings": {
                  "content": "\nThis project contains a hub & spoke Virtual Datacenter deployment. \n<br/>\n<br/>\n<a href='https://portal.azure.com/#@/dashboard/arm${subscription}/resourcegroups/${prefix}-${deployment_name}-${suffix}/providers/microsoft.portal/dashboards/${appinsights_id}-dashboard' target='_blank'>Application Insights Dashboard</a>\n<br/>\n<a href='https://${prefix}-${deployment_name}-paasapp-${suffix}-appsvc-app.scm.azurewebsites.net' target='_blank'>App Service Kudu Console</a>\n<br/>\n<a href='https://github.com/geekzter/azure-vdc' target='_blank'>GitHub project</a>\n<br/>\n<a href='${iaas_app_url}' target='_blank'>IaaS App</a>\n<br/>\n<a href='${paas_app_url}' target='_blank'>PaaS App</a>\n<br/>\n<a href='${build_web_url}' target='_blank'>Build Pipeline</a>\n<br/>\n<a href='${build_web_url}' target='_blank'>Release Pipeline</a>\n<br/>\n<a href='${vso_url}' target='_blank'>Visual Studio Codespace</a>\n",
                  "subtitle": "",
                  "title": "Automated VDC"
                }
              }
            },
            "type": "Extension/HubsExtension/PartType/MarkdownPart"
          },
          "position": {
            "colSpan": 4,
            "rowSpan": 4,
            "x": 0,
            "y": 0
          }
        },
        "1": {
          "metadata": {
            "inputs": [
              {
                "isOptional": true,
                "name": "partTitle",
                "value": "VDC Resources by Suffix"
              },
              {
                "isOptional": true,
                "name": "query",
                "value": "Resources | where tags['application']=='Automated VDC' and tags['suffix']=='${suffix}'| summarize Count=count() by Environment=tostring(tags['environment']), Workspace=tostring(tags['workspace']), ResourceGroup=resourceGroup | order by ResourceGroup asc"
              },
              {
                "isOptional": true,
                "name": "chartType"
              },
              {
                "isOptional": true,
                "name": "isShared"
              },
              {
                "isOptional": true,
                "name": "queryId",
                "value": "183f4042-6fe0-4362-b2bd-7575cf2ddf98"
              },
              {
                "isOptional": true,
                "name": "formatResults"
              }
            ],
            "settings": {},
            "type": "Extension/HubsExtension/PartType/ArgQueryGridTile"
          },
          "position": {
            "colSpan": 6,
            "rowSpan": 4,
            "x": 4,
            "y": 0
          }
        },
        "10": {
          "metadata": {
            "inputs": [
              {
                "name": "id",
                "value": "${subscription}/resourceGroups/${prefix}-${deployment_name}-paasapp-${suffix}/providers/Microsoft.EventHub/namespaces/${paas_app_resource_group_short}eventhubNamespace"
              }
            ],
            "type": "Extension/Microsoft_Azure_EventHub/PartType/NamespaceOverviewPart"
          },
          "position": {
            "colSpan": 2,
            "rowSpan": 1,
            "x": 10,
            "y": 4
          }
        },
        "11": {
          "metadata": {
            "asset": {
              "idInputName": "id",
              "type": "StorageAccount"
            },
            "inputs": [
              {
                "name": "id",
                "value": "${subscription}/resourceGroups/${prefix}-${deployment_name}-paasapp-${suffix}/providers/Microsoft.Storage/storageAccounts/${paas_app_resource_group_short}stor"
              }
            ],
            "type": "Extension/HubsExtension/PartType/ResourcePart"
          },
          "position": {
            "colSpan": 2,
            "rowSpan": 1,
            "x": 10,
            "y": 5
          }
        },
        "12": {
          "metadata": {
            "asset": {
              "idInputName": "id",
              "type": "PrivateDnsZone"
            },
            "inputs": [
              {
                "name": "id",
                "value": "${subscription}/resourceGroups/${prefix}-${deployment_name}-${suffix}/providers/Microsoft.Network/privateDnsZones/privatelink.database.windows.net"
              }
            ],
            "type": "Extension/Microsoft_Azure_PrivateDNS/PartType/PrivateDnsZonePart"
          },
          "position": {
            "colSpan": 2,
            "rowSpan": 1,
            "x": 10,
            "y": 6
          }
        },
        "13": {
          "metadata": {
            "inputs": [
              {
                "isOptional": true,
                "name": "resourceGroup"
              },
              {
                "isOptional": true,
                "name": "id",
                "value": "${subscription}/resourceGroups/${prefix}-${deployment_name}-paasapp-${suffix}"
              }
            ],
            "type": "Extension/HubsExtension/PartType/ResourceGroupMapPinnedPart"
          },
          "position": {
            "colSpan": 6,
            "rowSpan": 4,
            "x": 12,
            "y": 6
          }
        },
        "14": {
          "metadata": {
            "asset": {
              "idInputName": "id"
            },
            "inputs": [
              {
                "isOptional": true,
                "name": "id",
                "value": "${subscription}/resourceGroups/${prefix}-${deployment_name}-${suffix}/providers/Microsoft.Network/virtualNetworks/${prefix}-${deployment_name}-${suffix}-hub-network"
              },
              {
                "isOptional": true,
                "name": "resourceId"
              },
              {
                "isOptional": true,
                "name": "menuid"
              }
            ],
            "type": "Extension/HubsExtension/PartType/ResourcePart"
          },
          "position": {
            "colSpan": 2,
            "rowSpan": 1,
            "x": 10,
            "y": 7
          }
        },
        "15": {
          "metadata": {
            "filters": {
              "MsPortalFx_TimeRange": {
                "model": {
                  "format": "local",
                  "granularity": "auto",
                  "relative": "60m"
                }
              }
            },
            "inputs": [
              {
                "isOptional": true,
                "name": "sharedTimeRange"
              },
              {
                "isOptional": true,
                "name": "options",
                "value": {
                  "chart": {
                    "metrics": [
                      {
                        "aggregationType": 7,
                        "metricVisualization": {
                          "color": "#EC008C",
                          "resourceDisplayName": "${prefix}-${deployment_name}-${suffix}-insights"
                        },
                        "name": "requests/failed",
                        "namespace": "microsoft.insights/components",
                        "resourceMetadata": {
                          "id": "${subscription}/resourceGroups/${prefix}-${deployment_name}-${suffix}/providers/microsoft.insights/components/${prefix}-${deployment_name}-${suffix}-insights",
                          "resourceGroup": "${prefix}-${deployment_name}-${suffix}"
                        }
                      }
                    ],
                    "openBladeOnClick": {
                      "destinationBlade": {
                        "bladeName": "ResourceMenuBlade",
                        "extensionName": "HubsExtension",
                        "metadata": {},
                        "options": {
                          "parameters": {
                            "id": "${subscription}/resourceGroups/${prefix}-${deployment_name}-${suffix}/providers/microsoft.insights/components/${prefix}-${deployment_name}-${suffix}-insights",
                            "menuid": "failures",
                            "resourceGroup": "${prefix}-${deployment_name}-${suffix}"
                          }
                        },
                        "parameters": {
                          "id": "${subscription}/resourceGroups/${prefix}-${deployment_name}-${suffix}/providers/microsoft.insights/components/${prefix}-${deployment_name}-${suffix}-insights",
                          "menuid": "failures",
                          "resourceGroup": "${prefix}-${deployment_name}-${suffix}"
                        }
                      },
                      "openBlade": true
                    },
                    "title": "Failed requests",
                    "titleKind": 2,
                    "visualization": {
                      "chartType": 3
                    }
                  }
                }
              }
            ],
            "settings": {
              "content": {
                "options": {
                  "chart": {
                    "metrics": [
                      {
                        "aggregationType": 7,
                        "metricVisualization": {
                          "color": "#EC008C",
                          "resourceDisplayName": "${prefix}-${deployment_name}-${suffix}-insights"
                        },
                        "name": "requests/failed",
                        "namespace": "microsoft.insights/components",
                        "resourceMetadata": {
                          "id": "${subscription}/resourceGroups/${prefix}-${deployment_name}-${suffix}/providers/microsoft.insights/components/${prefix}-${deployment_name}-${suffix}-insights",
                          "resourceGroup": "${prefix}-${deployment_name}-${suffix}"
                        }
                      }
                    ],
                    "openBladeOnClick": {
                      "destinationBlade": {
                        "bladeName": "ResourceMenuBlade",
                        "extensionName": "HubsExtension",
                        "metadata": {},
                        "options": {
                          "parameters": {
                            "id": "${subscription}/resourceGroups/${prefix}-${deployment_name}-${suffix}/providers/microsoft.insights/components/${prefix}-${deployment_name}-${suffix}-insights",
                            "menuid": "failures",
                            "resourceGroup": "${prefix}-${deployment_name}-${suffix}"
                          }
                        },
                        "parameters": {
                          "id": "${subscription}/resourceGroups/${prefix}-${deployment_name}-${suffix}/providers/microsoft.insights/components/${prefix}-${deployment_name}-${suffix}-insights",
                          "menuid": "failures",
                          "resourceGroup": "${prefix}-${deployment_name}-${suffix}"
                        }
                      },
                      "openBlade": true
                    },
                    "title": "Failed requests",
                    "titleKind": 2,
                    "visualization": {
                      "chartType": 3,
                      "disablePinning": true
                    }
                  }
                }
              }
            },
            "type": "Extension/HubsExtension/PartType/MonitorChartPart"
          },
          "position": {
            "colSpan": 4,
            "rowSpan": 2,
            "x": 0,
            "y": 8
          }
        },
        "16": {
          "metadata": {
            "asset": {
              "idInputName": "ComponentId",
              "type": "ApplicationInsights"
            },
            "inputs": [
              {
                "name": "ComponentId",
                "value": {
                  "Name": "${prefix}-${deployment_name}-${suffix}-loganalytics",
                  "ResourceGroup": "${prefix}-${deployment_name}-${suffix}",
                  "ResourceId": "${subscription}/resourcegroups/${prefix}-${deployment_name}-${suffix}/providers/microsoft.operationalinsights/workspaces/${prefix}-${deployment_name}-${suffix}-loganalytics",
                  "SubscriptionId": "${subscription_guid}"
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
                "value": "${prefix}-${deployment_name}-${suffix}-loganalytics"
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
                "isOptional": true,
                "name": "Dimensions"
              },
              {
                "isOptional": true,
                "name": "DashboardId"
              },
              {
                "isOptional": true,
                "name": "SpecificChart"
              }
            ],
            "settings": {
              "content": {
                "PartSubTitle": "${prefix}-${deployment_name}-${suffix}-loganalytics",
                "PartTitle": "Denied outbound HTTP Traffic",
                "Query": "// Taken from https://docs.microsoft.com/en-us/azure/firewall/log-analytics-samples\nAzureDiagnostics\n| where Category == \"AzureFirewallApplicationRule\" \n| parse msg_s with Protocol \" request from \" SourceIP \":\" SourcePortInt:int \" \" TempDetails\n| parse TempDetails with \"was \" Action1 \". Reason: \" Rule1\n| parse TempDetails with \"to \" FQDN \":\" TargetPortInt:int \". Action: \" Action2 \".\" *\n| parse TempDetails with * \". Rule Collection: \" RuleCollection2a \". Rule:\" Rule2a\n| parse TempDetails with * \"Deny.\" RuleCollection2b \". Proceeding with\" Rule2b\n| extend TargetPort = tostring(TargetPortInt)\n| extend Action1 = case(Action1 == \"Deny\",\"Deny\",\"Unknown Action\")\n| extend Action = case(Action2 == \"\",Action1,Action2),Rule = case(Rule2a == \"\", case(Rule1 == \"\",case(Rule2b == \"\",\"N/A\", Rule2b),Rule1),Rule2a), \nRuleCollection = case(RuleCollection2b == \"\",case(RuleCollection2a == \"\",\"No rule matched\",RuleCollection2a), RuleCollection2b),FQDN = case(FQDN == \"\", \"N/A\", FQDN),Port = case(TargetPort == \"\", \"N/A\", TargetPort)\n| project TimeGenerated, FQDN, SourceIP, Port, Action ,RuleCollection, Rule\n| order by TimeGenerated desc\n| where Action == \"Deny\"\n"
              }
            },
            "type": "Extension/AppInsightsExtension/PartType/AnalyticsPart"
          },
          "position": {
            "colSpan": 6,
            "rowSpan": 5,
            "x": 4,
            "y": 8
          }
        },
        "17": {
          "metadata": {
            "asset": {
              "idInputName": "id"
            },
            "inputs": [
              {
                "isOptional": true,
                "name": "id",
                "value": "${subscription}/resourceGroups/${prefix}-${deployment_name}-${suffix}/providers/Microsoft.Network/virtualNetworks/${prefix}-${deployment_name}-${suffix}-iaas-spoke-network"
              },
              {
                "isOptional": true,
                "name": "resourceId"
              },
              {
                "isOptional": true,
                "name": "menuid"
              }
            ],
            "type": "Extension/HubsExtension/PartType/ResourcePart"
          },
          "position": {
            "colSpan": 2,
            "rowSpan": 1,
            "x": 10,
            "y": 8
          }
        },
        "18": {
          "metadata": {
            "asset": {
              "idInputName": "id"
            },
            "inputs": [
              {
                "isOptional": true,
                "name": "id",
                "value": "${subscription}/resourceGroups/${prefix}-${deployment_name}-${suffix}/providers/Microsoft.Network/virtualNetworks/${prefix}-${deployment_name}-${suffix}-paas-spoke-network"
              },
              {
                "isOptional": true,
                "name": "resourceId"
              },
              {
                "isOptional": true,
                "name": "menuid"
              }
            ],
            "type": "Extension/HubsExtension/PartType/ResourcePart"
          },
          "position": {
            "colSpan": 2,
            "rowSpan": 1,
            "x": 10,
            "y": 9
          }
        },
        "19": {
          "metadata": {
            "inputs": [
              {
                "name": "queryInputs",
                "value": {
                  "communicationType": "incident",
                  "endTime": "2020-06-27T15:06:15.281Z",
                  "loadFromCache": false,
                  "operationNames": "all",
                  "queryId": "c5597911-5dca-465d-b662-61dadc9d60ca",
                  "queryName": "Key Regions",
                  "regions": "southeastasia;eastus;westeurope;uksouth;westus2;global;northeurope",
                  "resourceGroupId": "all",
                  "searchText": "",
                  "services": "",
                  "startTime": "2020-06-24T15:06:15.281Z",
                  "statusFilter": "active",
                  "subscriptions": "${subscription_guid}",
                  "timeSpan": "5"
                }
              }
            ],
            "type": "Extension/Microsoft_Azure_Health/PartType/ServiceIssuesTilePart"
          },
          "position": {
            "colSpan": 4,
            "rowSpan": 3,
            "x": 0,
            "y": 10
          }
        },
        "2": {
          "metadata": {
            "asset": {
              "idInputName": "id",
              "type": "Workspace"
            },
            "inputs": [
              {
                "name": "id",
                "value": "${subscription}/resourcegroups/${prefix}-${deployment_name}-${suffix}/providers/microsoft.operationalinsights/workspaces/${prefix}-${deployment_name}-${suffix}-loganalytics"
              }
            ],
            "type": "Extension/Microsoft_OperationsManagementSuite_Workspace/PartType/WorkspacePart"
          },
          "position": {
            "colSpan": 2,
            "rowSpan": 1,
            "x": 10,
            "y": 0
          }
        },
        "20": {
          "metadata": {
            "inputs": [
              {
                "name": "id",
                "value": "${subscription}/resourceGroups/${prefix}-${deployment_name}-${suffix}/providers/Microsoft.Automation/automationAccounts/${prefix}-${deployment_name}-${suffix}-automation"
              }
            ],
            "type": "Extension/Microsoft_Azure_Automation/PartType/AccountDashboardBladePinnedPart"
          },
          "position": {
            "colSpan": 2,
            "rowSpan": 1,
            "x": 10,
            "y": 10
          }
        },
        "21": {
          "metadata": {
            "inputs": [
              {
                "isOptional": true,
                "name": "resourceGroup"
              },
              {
                "isOptional": true,
                "name": "id",
                "value": "${subscription}/resourceGroups/${prefix}-${deployment_name}-iaasapp-${suffix}"
              }
            ],
            "type": "Extension/HubsExtension/PartType/ResourceGroupMapPinnedPart"
          },
          "position": {
            "colSpan": 6,
            "rowSpan": 8,
            "x": 12,
            "y": 10
          }
        },
        "22": {
          "metadata": {
            "inputs": [
              {
                "name": "id",
                "value": "${subscription}/resourcegroups/${prefix}-${deployment_name}-${suffix}/providers/Microsoft.OperationalInsights/workspaces/${prefix}-${deployment_name}-${suffix}-loganalytics/views/ServiceMap(${prefix}-${deployment_name}-${suffix}-loganalytics)"
              },
              {
                "isOptional": true,
                "name": "solutionId"
              },
              {
                "isOptional": true,
                "name": "timeInterval",
                "value": {
                  "_Now": "2019-11-20T17:11:43.326Z",
                  "_duration": 86400000,
                  "_end": null
                }
              },
              {
                "binding": "timeRange",
                "isOptional": true,
                "name": "timeRange"
              }
            ],
            "type": "Extension/Microsoft_OperationsManagementSuite_Workspace/PartType/ViewTileIFramePart"
          },
          "position": {
            "colSpan": 4,
            "rowSpan": 2,
            "x": 0,
            "y": 13
          }
        },
        "23": {
          "metadata": {
            "asset": {
              "idInputName": "ComponentId",
              "type": "ApplicationInsights"
            },
            "inputs": [
              {
                "name": "ComponentId",
                "value": {
                  "Name": "${prefix}-${deployment_name}-${suffix}-loganalytics",
                  "ResourceGroup": "${prefix}-${deployment_name}-${suffix}",
                  "ResourceId": "${subscription}/resourcegroups/${prefix}-${deployment_name}-${suffix}/providers/microsoft.operationalinsights/workspaces/${prefix}-${deployment_name}-${suffix}-loganalytics",
                  "SubscriptionId": "${subscription_guid}"
                }
              },
              {
                "name": "Query",
                "value": "AzureDiagnostics\n| where Category == \"AzureFirewallNetworkRule\"\n| parse msg_s with Protocol \" request from \" SourceIP \":\" SourcePortInt:int \" to \" TargetIP \":\" TargetPortInt:int *\n| parse msg_s with * \". Action: \" Action1a\n| parse msg_s with * \" was \" Action1b \" to \" NatDestination\n| parse msg_s with Protocol2 \" request from \" SourceIP2 \" to \" TargetIP2 \". Action: \" Action2\n| extend SourcePort = tostring(SourcePortInt),Port = tostring(TargetPortInt)\n| extend Action = case(Action1a == \"\", case(Action1b == \"\",Action2,Action1b), Action1a),Protocol = case(Protocol == \"\", Protocol2, Protocol),SourceIP = case(SourceIP == \"\", SourceIP2, SourceIP),TargetIP = case(TargetIP == \"\", TargetIP2, TargetIP),SourcePort = case(SourcePort == \"\", \"N/A\", SourcePort),Port = case(Port == \"\", \"N/A\", Port),NatDestination = case(NatDestination == \"\", \"N/A\", NatDestination)\n| where Action == \"Deny\"\n| order by TimeGenerated desc\n| project TimeGenerated, Protocol, SourceIP,TargetIP,Port\n"
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
                "value": "48cb1d1b-e95d-4949-a31e-f5bc2dda37e6"
              },
              {
                "name": "PartTitle",
                "value": "Analytics"
              },
              {
                "name": "PartSubTitle",
                "value": "${prefix}-${deployment_name}-${suffix}-loganalytics"
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
                "isOptional": true,
                "name": "Dimensions"
              },
              {
                "isOptional": true,
                "name": "DashboardId"
              },
              {
                "isOptional": true,
                "name": "SpecificChart"
              }
            ],
            "settings": {
              "content": {
                "GridColumnsWidth": {
                  "Protocol": "65px",
                  "SourceIP": "96px",
                  "TargetIP": "138px"
                },
                "PartSubTitle": "${prefix}-${deployment_name}-${suffix}-loganalytics",
                "PartTitle": "Denied non-HTTP traffic"
              }
            },
            "type": "Extension/AppInsightsExtension/PartType/AnalyticsPart"
          },
          "position": {
            "colSpan": 6,
            "rowSpan": 4,
            "x": 4,
            "y": 13
          }
        },
        "24": {
          "metadata": {
            "inputs": [
              {
                "name": "id",
                "value": "${subscription}/resourcegroups/${prefix}-${deployment_name}-${suffix}/providers/Microsoft.OperationalInsights/workspaces/${prefix}-${deployment_name}-${suffix}-loganalytics/views/Updates(${prefix}-${deployment_name}-${suffix}-loganalytics)"
              },
              {
                "isOptional": true,
                "name": "solutionId"
              },
              {
                "isOptional": true,
                "name": "timeInterval",
                "value": {
                  "_Now": "2019-11-19T12:09:05.945Z",
                  "_duration": 86400000,
                  "_end": null
                }
              },
              {
                "binding": "timeRange",
                "isOptional": true,
                "name": "timeRange"
              }
            ],
            "type": "Extension/Microsoft_OperationsManagementSuite_Workspace/PartType/ViewTileIFramePart"
          },
          "position": {
            "colSpan": 4,
            "rowSpan": 2,
            "x": 0,
            "y": 15
          }
        },
        "25": {
          "metadata": {
            "asset": {
              "idInputName": "ComponentId",
              "type": "ApplicationInsights"
            },
            "inputs": [
              {
                "name": "ComponentId",
                "value": "Network Insights AppGateways Minified"
              },
              {
                "isOptional": true,
                "name": "ResourceIds",
                "value": [
                  "${subscription}/resourcegroups/${prefix}-${deployment_name}-${suffix}/providers/microsoft.network/applicationgateways/${prefix}-${deployment_name}-${suffix}-waf"
                ]
              },
              {
                "isOptional": true,
                "name": "Type",
                "value": "workbook"
              },
              {
                "isOptional": true,
                "name": "TimeContext"
              },
              {
                "isOptional": true,
                "name": "ConfigurationId",
                "value": "Community-Workbooks/Network Insights/NetworkInsights-AppGatewayMetrics-Minified"
              },
              {
                "isOptional": true,
                "name": "ViewerMode"
              },
              {
                "isOptional": true,
                "name": "GalleryResourceType",
                "value": "Network Insights AppGateways Minified"
              },
              {
                "isOptional": true,
                "name": "Version",
                "value": "1.0"
              }
            ],
            "type": "Extension/AppInsightsExtension/PartType/NotebookPinnedPart",
            "viewState": {
              "content": {
                "configurationId": "Community-Workbooks/Network Insights/NetworkInsights-AppGatewayMetrics-Minified"
              }
            }
          },
          "position": {
            "colSpan": 2,
            "rowSpan": 2,
            "x": 0,
            "y": 17
          }
        },
        "26": {
          "metadata": {
            "inputs": [],
            "type": "Extension/Microsoft_Azure_FlowLog/PartType/TrafficAnalyticsDashboardPinnedPart"
          },
          "position": {
            "colSpan": 2,
            "rowSpan": 2,
            "x": 2,
            "y": 17
          }
        },
        "27": {
          "metadata": {
            "asset": {
              "idInputName": "ComponentId",
              "type": "ApplicationInsights"
            },
            "inputs": [
              {
                "name": "ComponentId",
                "value": {
                  "Name": "${prefix}-${deployment_name}-${suffix}-loganalytics",
                  "ResourceGroup": "${prefix}-${deployment_name}-${suffix}",
                  "ResourceId": "${subscription}/resourcegroups/${prefix}-${deployment_name}-${suffix}/providers/microsoft.operationalinsights/workspaces/${prefix}-${deployment_name}-${suffix}-loganalytics",
                  "SubscriptionId": "${subscription_guid}"
                }
              },
              {
                "name": "Query",
                "value": "AzureDiagnostics \n| where Category == \"ApplicationGatewayAccessLog\" and httpStatus_d >= 500\n| project TimeGenerated, httpStatus_d, listenerName_s, backendPoolName_s, ruleName_s\n| order by TimeGenerated desc\n"
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
                "value": "42ad871f-2614-484d-8e7e-0b9a1a522403"
              },
              {
                "name": "PartTitle",
                "value": "Analytics"
              },
              {
                "name": "PartSubTitle",
                "value": "${prefix}-${deployment_name}-${suffix}-loganalytics"
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
                "isOptional": true,
                "name": "Dimensions"
              },
              {
                "isOptional": true,
                "name": "DashboardId"
              },
              {
                "isOptional": true,
                "name": "SpecificChart"
              }
            ],
            "settings": {
              "content": {
                "PartSubTitle": "${prefix}-${deployment_name}-${suffix}-loganalytics",
                "PartTitle": "Errors on HTTP inbound traffic (WAF)"
              }
            },
            "type": "Extension/AppInsightsExtension/PartType/AnalyticsPart"
          },
          "position": {
            "colSpan": 6,
            "rowSpan": 3,
            "x": 4,
            "y": 17
          }
        },
        "28": {
          "metadata": {
            "asset": {
              "idInputName": "ComponentId",
              "type": "ApplicationInsights"
            },
            "inputs": [
              {
                "name": "ComponentId",
                "value": {
                  "Name": "${prefix}-${deployment_name}-${suffix}-loganalytics",
                  "ResourceGroup": "${prefix}-${deployment_name}-${suffix}",
                  "ResourceId": "${subscription}/resourcegroups/${prefix}-${deployment_name}-${suffix}/providers/microsoft.operationalinsights/workspaces/${prefix}-${deployment_name}-${suffix}-loganalytics",
                  "SubscriptionId": "${subscription_guid}"
                }
              },
              {
                "name": "Query",
                "value": "AzureDiagnostics\n| where Category == 'SQLSecurityAuditEvents'\n| project event_time_t, statement_s, succeeded_s, affected_rows_d, client_ip_s\n| order by event_time_t desc\n| take 100\n"
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
                "value": "4b9491b1-a6ea-4a30-a11a-2eb5d4107d35"
              },
              {
                "name": "PartTitle",
                "value": "Analytics"
              },
              {
                "name": "PartSubTitle",
                "value": "${prefix}-${deployment_name}-${suffix}-loganalytics"
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
                "isOptional": true,
                "name": "Dimensions"
              },
              {
                "isOptional": true,
                "name": "DashboardId"
              },
              {
                "isOptional": true,
                "name": "SpecificChart"
              }
            ],
            "settings": {
              "content": {
                "PartSubTitle": "${prefix}-${deployment_name}-${suffix}-loganalytics",
                "PartTitle": "SQL Client Queries",
                "Query": "AzureDiagnostics\n| where Category == 'SQLSecurityAuditEvents'\n| project event_time_t, client_ip_s, statement_s, affected_rows_d\n| order by event_time_t desc\n| take 100"
              }
            },
            "type": "Extension/AppInsightsExtension/PartType/AnalyticsPart"
          },
          "position": {
            "colSpan": 6,
            "rowSpan": 4,
            "x": 4,
            "y": 20
          }
        },
        "3": {
          "metadata": {
            "inputs": [
              {
                "name": "subscriptionIds",
                "value": [
                  "${subscription_guid}"
                ]
              },
              {
                "name": "resourceType",
                "value": [
                  "microsoft.network/virtualnetworks",
                  "microsoft.network/virtualnetworkgateways",
                  "microsoft.network/connections",
                  "microsoft.network/networkinterfaces",
                  "microsoft.network/publicipaddresses",
                  "microsoft.network/networksecuritygroups",
                  "microsoft.network/applicationgateways",
                  "microsoft.network/loadbalancers",
                  "microsoft.network/localnetworkgateways",
                  "microsoft.network/expressroutecircuits",
                  "microsoft.network/routetables",
                  "microsoft.network/azurefirewalls",
                  "microsoft.network/frontdoors",
                  "microsoft.network/virtualhubs",
                  "microsoft.network/virtualwans",
                  "microsoft.network/trafficmanagerprofiles",
                  "microsoft.network/privatelinkservices",
                  "microsoft.network/privateendpoints",
                  "microsoft.network/applicationgatewaywebapplicationfirewallpolicies",
                  "microsoft.network/frontdoorwebapplicationfirewallpolicies",
                  "microsoft.network/networkvirtualappliances"
                ]
              },
              {
                "name": "resourceGroup",
                "value": null
              }
            ],
            "type": "Extension/Microsoft_Azure_FlowLog/PartType/HealthTilePinnedPart"
          },
          "position": {
            "colSpan": 6,
            "rowSpan": 6,
            "x": 12,
            "y": 0
          }
        },
        "4": {
          "metadata": {
            "inputs": [
              {
                "isOptional": true,
                "name": "resourceGroup"
              },
              {
                "isOptional": true,
                "name": "id",
                "value": "${subscription}/resourceGroups/${prefix}-${deployment_name}-${suffix}"
              }
            ],
            "type": "Extension/HubsExtension/PartType/ResourceGroupMapPinnedPart"
          },
          "position": {
            "colSpan": 6,
            "rowSpan": 21,
            "x": 18,
            "y": 0
          }
        },
        "5": {
          "metadata": {
            "asset": {
              "idInputName": "id",
              "type": "CloudNativeFirewall"
            },
            "inputs": [
              {
                "name": "id",
                "value": "${subscription}/resourceGroups/${prefix}-${deployment_name}-${suffix}/providers/Microsoft.Network/azureFirewalls/${prefix}-${deployment_name}-${suffix}-iag"
              }
            ],
            "type": "Extension/Microsoft_Azure_HybridNetworking/PartType/CloudNativeFirewallPart"
          },
          "position": {
            "colSpan": 2,
            "rowSpan": 1,
            "x": 10,
            "y": 1
          }
        },
        "6": {
          "metadata": {
            "asset": {
              "idInputName": "id",
              "type": "Website"
            },
            "inputs": [
              {
                "name": "id",
                "value": "${subscription}/resourceGroups/${prefix}-${deployment_name}-paasapp-${suffix}/providers/Microsoft.Web/sites/${prefix}-${deployment_name}-paasapp-${suffix}-appsvc-app"
              }
            ],
            "type": "Extension/WebsitesExtension/PartType/SingleWebsitePart"
          },
          "position": {
            "colSpan": 2,
            "rowSpan": 1,
            "x": 10,
            "y": 2
          }
        },
        "7": {
          "metadata": {
            "asset": {
              "idInputName": "resourceId",
              "type": "Server"
            },
            "inputs": [
              {
                "name": "resourceId",
                "value": "${subscription}/resourceGroups/${prefix}-${deployment_name}-paasapp-${suffix}/providers/Microsoft.Sql/servers/${paas_app_resource_group_short}sqlserver"
              }
            ],
            "type": "Extension/SqlAzureExtension/PartType/ServerPart"
          },
          "position": {
            "colSpan": 2,
            "rowSpan": 1,
            "x": 10,
            "y": 3
          }
        },
        "8": {
          "metadata": {
            "asset": {
              "idInputName": "ComponentId",
              "type": "ApplicationInsights"
            },
            "inputs": [
              {
                "name": "ComponentId",
                "value": "${subscription}/resourceGroups/${prefix}-${deployment_name}-${suffix}/providers/microsoft.insights/components/${prefix}-${deployment_name}-${suffix}-insights"
              },
              {
                "isOptional": true,
                "name": "MainResourceId"
              },
              {
                "isOptional": true,
                "name": "ResourceIds"
              },
              {
                "isOptional": true,
                "name": "TimeContext",
                "value": {
                  "createdTime": "Wed Dec 04 2019 08:28:36 GMT+0100 (Central European Standard Time)",
                  "durationMs": 3600000,
                  "grain": 1,
                  "isInitialTime": false,
                  "useDashboardTimeRange": false
                }
              },
              {
                "isOptional": true,
                "name": "ConfigurationId",
                "value": "69015b20-1c24-4c5b-82cb-67701774a2d4"
              },
              {
                "isOptional": true,
                "name": "DataModel",
                "value": {
                  "exclude4xxError": true,
                  "layoutOption": "Organic",
                  "timeContext": {
                    "createdTime": "Wed Dec 04 2019 08:28:36 GMT+0100 (Central European Standard Time)",
                    "durationMs": 3600000,
                    "grain": 1,
                    "isInitialTime": false,
                    "useDashboardTimeRange": false
                  }
                }
              },
              {
                "isOptional": true,
                "name": "UseCallerTimeContext"
              },
              {
                "isOptional": true,
                "name": "OverrideSettings"
              },
              {
                "isOptional": true,
                "name": "PartId"
              }
            ],
            "settings": {},
            "type": "Extension/AppInsightsExtension/PartType/ApplicationMapPart"
          },
          "position": {
            "colSpan": 4,
            "rowSpan": 4,
            "x": 0,
            "y": 4
          }
        },
        "9": {
          "metadata": {
            "inputs": [
              {
                "name": "scope",
                "value": "/subscriptions/${subscription_guid}"
              },
              {
                "name": "scopeName",
                "value": "Microsoft Azure Internal Consumption Eric van Wijk"
              },
              {
                "isOptional": true,
                "name": "view",
                "value": {
                  "accumulated": "true",
                  "chart": "Area",
                  "currency": "USD",
                  "dateRange": "LastMonth",
                  "displayName": "AccumulatedCosts",
                  "kpis": [
                    {
                      "enabled": true,
                      "extendedProperties": {
                        "amount": 2000,
                        "name": "NormalBudget",
                        "timeGrain": "Monthly",
                        "type": "provider"
                      },
                      "id": "subscriptions/${subscription_guid}/providers/Microsoft.Consumption/budgets/NormalBudget",
                      "type": "Budget"
                    },
                    {
                      "enabled": true,
                      "type": "Forecast"
                    }
                  ],
                  "pivots": [
                    {
                      "name": "ServiceName",
                      "type": "Dimension"
                    },
                    {
                      "name": "ResourceLocation",
                      "type": "Dimension"
                    },
                    {
                      "name": "ResourceGroupName",
                      "type": "Dimension"
                    }
                  ],
                  "query": {
                    "dataSet": {
                      "aggregation": {
                        "totalCost": {
                          "function": "Sum",
                          "name": "PreTaxCost"
                        }
                      },
                      "filter": {
                        "And": [
                          {
                            "Tags": {
                              "Name": "application",
                              "Operator": "In",
                              "Values": [
                                "automated vdc"
                              ]
                            }
                          },
                          {
                            "Tags": {
                              "Name": "environment",
                              "Operator": "In",
                              "Values": [
                                "${deployment_name}"
                              ]
                            }
                          }
                        ]
                      },
                      "granularity": "Daily",
                      "sorting": [
                        {
                          "direction": "ascending",
                          "name": "UsageDate"
                        }
                      ]
                    },
                    "timeframe": "None",
                    "type": "ActualCost"
                  },
                  "scope": "subscriptions/${subscription_guid}"
                }
              },
              {
                "isOptional": true,
                "name": "externalState"
              }
            ],
            "type": "Extension/Microsoft_Azure_CostManagement/PartType/CostAnalysisPinPart"
          },
          "position": {
            "colSpan": 6,
            "rowSpan": 4,
            "x": 4,
            "y": 4
          }
        }
      }
    }
  },
  "metadata": {
    "model": {
      "filterLocale": {
        "value": "en-us"
      },
      "filters": {
        "value": {
          "MsPortalFx_TimeRange": {
            "displayCache": {
              "name": "UTC Time",
              "value": "Past 24 hours"
            },
            "filteredPartIds": [
              "StartboardPart-ApplicationMapPart-87b43f3a-d1f0-4e20-9e64-db5c9374f3df",
              "StartboardPart-MonitorChartPart-87b43f3a-d1f0-4e20-9e64-db5c9374f3ed",
              "StartboardPart-AnalyticsPart-87b43f3a-d1f0-4e20-9e64-db5c9374f3ef",
              "StartboardPart-AnalyticsPart-87b43f3a-d1f0-4e20-9e64-db5c9374f3ff",
              "StartboardPart-AnalyticsPart-87b43f3a-d1f0-4e20-9e64-db5c9374f407",
              "StartboardPart-AnalyticsPart-87b43f3a-d1f0-4e20-9e64-db5c9374f409"
            ],
            "model": {
              "format": "utc",
              "granularity": "auto",
              "relative": "24h"
            }
          }
        }
      },
      "timeRange": {
        "type": "MsPortalFx.Composition.Configuration.ValueTypes.TimeRange",
        "value": {
          "relative": {
            "duration": 24,
            "timeUnit": 1
          }
        }
      }
    }
  }
}
