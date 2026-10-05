# Cluster-admin through EKS access entries. Keyed by a static name so for_each keys are known at plan time.
admin_principal_arns = {
  deploy   = "arn:aws:iam::721500739616:role/sentinel-damian-gha-deploy"
  operator = "arn:aws:iam::721500739616:user/damian.vegapolanco2@gmail.com"
}
