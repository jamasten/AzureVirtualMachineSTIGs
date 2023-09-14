param ArtifactsLocation string
param AutomationAccountName string
param ConfigurationName string
param Location string
param LogAnalyticsWorkspaceResourceId string = ''
param Tags object
param Timestamp string
param VirtualMachineNames array
param VirtualMachinesResourceGroupName string

var Modules = [
  {
    name: 'AccessControlDSC'
    version: '1.4.1'
  }
  {
    name: 'AuditPolicyDsc'
    version: '1.4.0.0'
  }
  {
    name: 'AuditSystemDsc'
    version: '1.1.0'
  }
  {
    name: 'CertificateDsc'
    version: '5.0.0'
  }
  {
    name: 'ComputerManagementDsc'
    version: '8.4.0'
  }
  {
    name: 'FileContentDsc'
    version: '1.3.0.151'
  }
  {
    name: 'GPRegistryPolicyDsc'
    version: '1.2.0'
  }
  {
    name: 'nx'
    version: '1.0'
  }
  {
    name: 'PSDscResources'
    version: '2.12.0.0'
  }
  {
    name: 'SecurityPolicyDsc'
    version: '2.10.0.0'
  }
  {
    name: 'SqlServerDsc'
    version: '13.3.0'
  }
  {
    name: 'WindowsDefenderDsc'
    version: '2.1.0'
  }
  {
    name: 'xDnsServer'
    version: '1.16.0.0'
  }
  {
    name: 'xWebAdministration'
    version: '3.2.0'
  }
  {
    name: 'PowerSTIG'
    version: '4.10.1'
  }
]

resource automationAccount 'Microsoft.Automation/automationAccounts@2021-06-22' = {
  name: AutomationAccountName
  location: Location
  tags: Tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: 'Free'
    }
  }
}

// Enables logging in a log analytics workspace for alerting and dashboards
resource diagnosticsSetting 'Microsoft.Insights/diagnosticsettings@2017-05-01-preview' = if (!empty(LogAnalyticsWorkspaceResourceId)) {
  scope: automationAccount
  name: 'diag-${AutomationAccountName}'
  properties: {
    logs: [
      {
        category: 'DscNodeStatus'
        enabled: true
      }
      {
        category: 'JobLogs'
        enabled: true
      }
      {
        category: 'JobStreams'
        enabled: true
      }
    ]
    workspaceId: LogAnalyticsWorkspaceResourceId
  }
}

@batchSize(1)
resource modules 'Microsoft.Automation/automationAccounts/modules@2019-06-01' = [for Module in Modules: {
  parent: automationAccount
  name: Module.name
  location: Location
  properties: {
    contentLink: {
      uri: 'https://www.powershellgallery.com/api/v2/package/${Module.name}/${Module.version}'
      version: Module.version
    }
  }
}]

resource configuration 'Microsoft.Automation/automationAccounts/configurations@2019-06-01' = {
  parent: automationAccount
  name: ConfigurationName
  location: Location
  properties: {
    source: {
      type: 'uri'
      value: '${ArtifactsLocation}Windows10.ps1'
      version: Timestamp
    }
    parameters: {}
    description: 'Hardens the VM using the Azure STIG Template'
  }
  dependsOn: [
    modules
  ]
}

resource compilationJob 'Microsoft.Automation/automationAccounts/compilationjobs@2019-06-01' = {
  parent: automationAccount
  name: guid(Timestamp)
  location: Location
  properties: {
    configuration: {
      name: configuration.name
    }
  }
  dependsOn: [
    modules
  ]
}

module virtualMachineExtensions 'modules/desiredStateConfiguration.bicep' = [for VirtualMachine in VirtualMachineNames: {
  name: 'DSC_${VirtualMachine}_${Timestamp}'
  scope: resourceGroup(VirtualMachinesResourceGroupName)
  params: {
    ConfigurationName: ConfigurationName
    Location: Location
    RegistrationKey: automationAccount.listKeys().keys[0].Value
    RegistrationUrl: reference('automationAccount').registrationUrl
    Tags: Tags
    Timestamp: Timestamp
    VirtualMachineName: VirtualMachine
  }
}]
