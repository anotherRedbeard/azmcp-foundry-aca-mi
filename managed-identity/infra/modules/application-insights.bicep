@description('Location for all resources')
param location string = resourceGroup().location

@description('Name for Application Insights')
param name string

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${name}-workspace'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: name
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

@secure()
output connectionString string = applicationInsights.properties.ConnectionString

@secure()
output instrumentationKey string = applicationInsights.properties.InstrumentationKey

output resourceId string = applicationInsights.id
output logAnalyticsCustomerId string = logAnalyticsWorkspace.properties.customerId

@secure()
output logAnalyticsSharedKey string = logAnalyticsWorkspace.listKeys().primarySharedKey
