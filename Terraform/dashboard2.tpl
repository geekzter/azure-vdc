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
                                    "title": "Automated VDC",
                                    "subtitle": ""
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
                                    "SubscriptionId": "${subscription}",
                                    "ResourceGroup": "${prefix}-${environment}-${suffix}"
                                }
                            },
                            {
                                "name": "TargetBlade",
                                "value": "Failures"
                            },
                            {
                                "name": "DataModel",
                                "value": {
                                    "version": "1.0.0",
                                    "experience": 1,
                                    "clientTypeMode": "Server",
                                    "timeContext": {
                                        "durationMs": 86400000,
                                        "isInitialTime": false,
                                        "grain": 1,
                                        "useDashboardTimeRange": false,
                                        "createdTime": "2019-11-19T12:07:25.044Z",
                                        "endTime": null
                                    },
                                    "prefix": "let OperationIdsWithExceptionType = (excType: string) { exceptions | where timestamp > ago(1d) \n    | where tobool(iff(excType == \"null\", isempty(type), type == excType)) \n    | distinct operation_ParentId };\nlet OperationIdsWithFailedReqResponseCode = (respCode: string) { requests | where timestamp > ago(1d)\n    | where iff(respCode == \"null\", isempty(resultCode), resultCode == respCode) and success == false \n    | distinct id };\nlet OperationIdsWithFailedDependencyType = (depType: string) { dependencies | where timestamp > ago(1d)\n    | where iff(depType == \"null\", isempty(type), type == depType) and success == false \n    | distinct operation_ParentId };\nlet OperationIdsWithFailedDepResponseCode = (respCode: string) { dependencies | where timestamp > ago(1d)\n    | where iff(respCode == \"null\", isempty(resultCode), resultCode == respCode) and success == false \n    | distinct operation_ParentId };\nlet OperationIdsWithExceptionBrowser = (browser: string) { exceptions | where timestamp > ago(1d)\n    | where tobool(iff(browser == \"null\", isempty(client_Browser), client_Browser == browser)) \n    | distinct operation_ParentId };",
                                    "grain": "5m",
                                    "selectedOperation": null,
                                    "selectedOperationName": null
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
                "8": {
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
                "9": {
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
                "10": {
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
            }
        }
    }
}