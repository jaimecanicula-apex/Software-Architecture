// Naming convention: <type>-<workload>-<environment>-<region>-<instance>
// Follows the Cloud Adoption Framework abbreviations. Pure computation, no
// resources. These are functions, not a module, because Bicep needs a resource
// name to be known when the deployment starts, and a module output is not.
//
//   import * as naming from 'modules/naming.bicep'
//   var sfx = naming.suffix(workload, environment, location, instance)

func regionCode(location string) string => {
  westeurope: 'weu'
  northeurope: 'neu'
  uksouth: 'uks'
  eastus: 'eus'
  eastus2: 'eus2'
  centralus: 'cus'
  westus2: 'wus2'
  eastasia: 'ea'
  southeastasia: 'sea'
  australiaeast: 'aue'
  switzerlandnorth: 'chn'
  germanywestcentral: 'gwc'
  francecentral: 'frc'
}[?location] ?? take(location, 4)

@export()
func suffix(workload string, environment string, location string, instance string) string => '${workload}-${environment}-${regionCode(location)}-${instance}'

@export()
func resourceGroupName(sfx string) string => 'rg-${sfx}'

@export()
func staticWebAppName(sfx string) string => 'stapp-${sfx}'

@export()
func logAnalyticsName(sfx string) string => 'log-${sfx}'

@export()
func applicationInsightsName(sfx string) string => 'appi-${sfx}'

@export()
func actionGroupName(sfx string) string => 'ag-${sfx}'

@export()
func actionGroupShortName(workload string, environment string) string => take(replace('${workload}${environment}', '-', ''), 12)

@export()
func budgetName(sfx string) string => 'budget-${sfx}'

@export()
func virtualNetworkName(sfx string) string => 'vnet-${sfx}'

@export()
func subnetPrivateEndpointsName(sfx string) string => 'snet-pe-${sfx}'

@export()
func subnetProbeName(sfx string) string => 'snet-probe-${sfx}'

@export()
func nsgPrivateEndpointsName(sfx string) string => 'nsg-pe-${sfx}'

@export()
func nsgProbeName(sfx string) string => 'nsg-probe-${sfx}'

@export()
func privateLinkScopeName(sfx string) string => 'ampls-${sfx}'

@export()
func privateEndpointSiteName(sfx string) string => 'pe-stapp-${sfx}'

@export()
func privateEndpointStorageName(sfx string) string => 'pe-st-${sfx}'

@export()
func storageRoleName(sfx string) string => 'role-files-${sfx}'

@description('3-24 lowercase letters and digits, globally unique: 4 characters of a hash of the seed (the subscription ID) are appended.')
@export()
func storageAccountName(sfx string, seed string) string => take('st${replace(sfx, '-', '')}${take(uniqueString(seed), 4)}', 24)
