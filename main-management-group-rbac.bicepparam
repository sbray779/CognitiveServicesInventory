using 'main-management-group-rbac.bicep'

// This is the principal ID output from the main deployment
// Run the main deployment first and get the logicAppPrincipalId output
param logicAppPrincipalId = '<logic-app-principal-id-from-main-deployment>'
