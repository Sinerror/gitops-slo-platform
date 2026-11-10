output "kubeconfig_path" {
  value = module.cluster.kubeconfig_path
}

output "urls" {
  value = {
    shop_prod    = "http://shop.localtest.me:18080"
    shop_staging = "http://staging.localtest.me:18081"
    argocd       = "http://argocd.localtest.me:18090"
    grafana      = "http://grafana.localtest.me:18090"
  }
}
