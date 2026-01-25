resource "kubernetes_namespace" "app_ns" {
  metadata { name = "demo-app" }
}

resource "kubernetes_deployment" "hello_world" {
  metadata {
    name      = "hello-world"
    namespace = kubernetes_namespace.app_ns.metadata[0].name
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "hello" } }
    template {
      metadata { labels = { app = "hello" } }
      spec {
        container {
          image = "nginxdemos/hello"
          name  = "hello-world"
        }
      }
    }
  }
}

resource "kubernetes_service" "hello_service" {
  metadata {
    name      = "hello-svc"
    namespace = kubernetes_namespace.app_ns.metadata[0].name
  }
  spec {
    selector = { app = "hello" }
    port { port = 80 }
    type = "ClusterIP"
  }
}

resource "kubernetes_ingress_v1" "hello_ingress" {
  metadata {
    name      = "hello-ingress"
    namespace = kubernetes_namespace.app_ns.metadata[0].name
  }
  spec {
    ingress_class_name = "nginx" # <--- Currently using NGINX
    rule {
      http {
        path {
          path = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.hello_service.metadata[0].name
              port { number = 80 }
            }
          }
        }
      }
    }
  }
}
