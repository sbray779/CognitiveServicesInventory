using 'main-management-group-rbac.bicep'

// This is the principal ID output from the main deployment
// Run the main deployment first and get the userAssignedIdentityPrincipalId output
param userAssignedIdentityPrincipalId = '<user-assigned-identity-principal-id-from-main-deployment>'
