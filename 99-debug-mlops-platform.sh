#!/usr/bin/env bash
set -euo pipefail

# Comprehensive single-shot debugger for:
#   MLOps-Platform-for-LLM-Deployment (EKS + KServe + Monitoring)
#
# Outputs a time-stamped bundle in ./_debug/
#
# Usage:
#   chmod +x 99-debug-mlops-platform.sh
#   ./99-debug-mlops-platform.sh
#
# Optional env:
#   NS_APP=mlops-demo
#   ISVC_NAME=iris-model
#   NS_KSERVE=kserve
#   NS_MON=monitoring

TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUTDIR="_debug/${TS}"
NS_APP="${NS_APP:-mlops-demo}"
ISVC_NAME="${ISVC_NAME:-iris-model}"
NS_KSERVE="${NS_KSERVE:-kserve}"
NS_MON="${NS_MON:-monitoring}"

mkdir -p "${OUTDIR}"

say(){ printf "\n\033[1;32m==>\033[0m %s\n" "$*"; }
run(){ # run <cmd...> ; best-effort, captures stdout+stderr
  local name="$1"; shift
  {
    echo "### CMD: $*"
    echo "### TIME: $(date -u +%FT%TZ)"
    "$@"
  } > "${OUTDIR}/${name}.txt" 2>&1 || true
}
run_sh(){ # run_sh <name> "<shell string>"
  local name="$1"; shift
  local cmd="$1"
  {
    echo "### CMD: ${cmd}"
    echo "### TIME: $(date -u +%FT%TZ)"
    bash -lc "${cmd}"
  } > "${OUTDIR}/${name}.txt" 2>&1 || true
}

need_bin(){
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing required binary: $1" >&2
    exit 1
  }
}

say "0) Precheck binaries + cluster connectivity"
need_bin kubectl
need_bin awk
need_bin sed
need_bin grep

run "00_versions" kubectl version --client=true
run "01_ctx" kubectl config current-context
run "02_cluster_info" kubectl cluster-info
run "03_nodes" kubectl get nodes -o wide

say "1) Snapshot cluster health (namespaces, events, core components)"
run "10_namespaces" kubectl get ns -o wide
run "11_all_pods_all_ns" kubectl get pods -A -o wide
run "12_all_events_all_ns" kubectl get events -A --sort-by=.lastTimestamp
run "13_kube_system_pods" kubectl -n kube-system get pods -o wide
run "14_coredns" kubectl -n kube-system describe deploy coredns

say "2) Monitoring (Prometheus/Grafana) status"
run "20_monitoring_pods" kubectl -n "${NS_MON}" get pods -o wide
run "21_monitoring_svc" kubectl -n "${NS_MON}" get svc -o wide
run "22_prometheus_server_logs" kubectl -n "${NS_MON}" logs deploy/prometheus-server --tail=300
# grafana may be deployment or statefulset depending on chart; try both
run_sh "23_grafana_logs" "kubectl -n ${NS_MON} logs deploy/grafana --tail=300 || kubectl -n ${NS_MON} logs sts/grafana --tail=300 || true"

say "3) cert-manager (KServe prerequisite)"
run "30_cert_manager_pods" kubectl -n cert-manager get pods -o wide
run "31_cert_manager_deploys" kubectl -n cert-manager get deploy -o wide
run "32_cert_manager_events" kubectl -n cert-manager get events --sort-by=.lastTimestamp
run "33_cert_manager_logs" kubectl -n cert-manager logs deploy/cert-manager --tail=200
run_sh "34_cert_manager_webhook_logs" "kubectl -n cert-manager logs deploy/cert-manager-webhook --tail=200 || true"

say "4) KServe control-plane (controller/webhooks/config/CRDs)"
run "40_kserve_ns" kubectl get ns "${NS_KSERVE}" -o yaml
run "41_kserve_pods" kubectl -n "${NS_KSERVE}" get pods -o wide
run "42_kserve_deploys" kubectl -n "${NS_KSERVE}" get deploy -o wide
run "43_kserve_services" kubectl -n "${NS_KSERVE}" get svc -o wide
run "44_kserve_events" kubectl -n "${NS_KSERVE}" get events --sort-by=.lastTimestamp
run "45_kserve_controller_logs" kubectl -n "${NS_KSERVE}" logs deploy/kserve-controller-manager --tail=600
run_sh "46_kserve_webhook_logs" "kubectl -n ${NS_KSERVE} get pods -o name | grep -i webhook | head -n1 | xargs -r kubectl -n ${NS_KSERVE} logs --tail=600 || true"
run "47_inferenceservice_config_cm" kubectl -n "${NS_KSERVE}" get cm inferenceservice-config -o yaml
run "48_kserve_configmaps" kubectl -n "${NS_KSERVE}" get cm -o wide
run "49_kserve_secrets" kubectl -n "${NS_KSERVE}" get secret -o wide

say "5) Webhooks & Admission (common cause of 'cannot create isvc' / stalls)"
run "50_validating_webhooks" kubectl get validatingwebhookconfigurations -o wide
run "51_mutating_webhooks" kubectl get mutatingwebhookconfigurations -o wide
run_sh "52_kserve_webhook_objects" "kubectl get validatingwebhookconfigurations -o name | grep -i kserve || true; kubectl get mutatingwebhookconfigurations -o name | grep -i kserve || true"

say "6) CRDs (versions + what API versions are actually served)"
run_sh "60_kserve_crds_list" "kubectl get crd | egrep -i 'kserve|inferenceservice|servingruntime|clusterservingruntime|trainedmodel|llm' || true"
run_sh "61_isvc_crd_versions" "kubectl get crd inferenceservices.serving.kserve.io -o yaml | sed -n '1,220p' || true"
run_sh "62_servingruntime_crd_versions" "kubectl get crd servingruntimes.serving.kserve.io -o yaml | sed -n '1,220p' || true"
run_sh "63_clusterservingruntime_crd_versions" "kubectl get crd clusterservingruntimes.serving.kserve.io -o yaml | sed -n '1,220p' || true"

say "7) Built-in runtimes present?"
run_sh "70_clusterservingruntimes" "kubectl get clusterservingruntime -o wide 2>/dev/null || kubectl get clusterservingruntimes -o wide 2>/dev/null || true"
run_sh "71_servingruntimes_all_ns" "kubectl get servingruntime -A -o wide 2>/dev/null || kubectl get servingruntimes -A -o wide 2>/dev/null || true"

say "8) App namespace (InferenceService) deep dive"
run "80_app_ns" kubectl get ns "${NS_APP}" -o yaml
run "81_app_pods" kubectl -n "${NS_APP}" get pods -o wide
run "82_app_svc" kubectl -n "${NS_APP}" get svc -o wide
run "83_app_deploy_rs" kubectl -n "${NS_APP}" get deploy,rs -o wide
run "84_app_events" kubectl -n "${NS_APP}" get events --sort-by=.lastTimestamp

# isvc objects: try to read by name; also list all isvc
run_sh "85_isvc_list" "kubectl -n ${NS_APP} get isvc -o wide 2>/dev/null || kubectl -n ${NS_APP} get inferenceservices -o wide 2>/dev/null || true"
run_sh "86_isvc_yaml" "kubectl -n ${NS_APP} get isvc ${ISVC_NAME} -o yaml 2>/dev/null || true"
run_sh "87_isvc_describe" "kubectl -n ${NS_APP} describe isvc ${ISVC_NAME} 2>/dev/null || true"

# If created pods exist, capture their logs and describe
run_sh "88_app_pod_describes" "for p in \$(kubectl -n ${NS_APP} get pod -o name 2>/dev/null | head -n 10); do echo '--- '\"\$p\"; kubectl -n ${NS_APP} describe \"\$p\"; done || true"
run_sh "89_app_pod_logs" "for p in \$(kubectl -n ${NS_APP} get pod -o name 2>/dev/null | head -n 10); do echo '--- '\"\$p\"; kubectl -n ${NS_APP} logs \"\$p\" --all-containers --tail=300; done || true"

say "9) Image pull / scheduling / DNS sanity (common silent blockers)"
run "90_pending_pods_all_ns" kubectl get pods -A --field-selector=status.phase=Pending -o wide
run_sh "91_failed_pods_all_ns" "kubectl get pods -A -o jsonpath='{range .items[?(@.status.phase==\"Failed\")]}{.metadata.namespace}/{.metadata.name}{\"\\n\"}{end}' || true"
run "92_nodes_describe" kubectl describe nodes
run_sh "93_coredns_logs" "kubectl -n kube-system logs deploy/coredns --tail=200 || true"

say "10) Quick conclusions (heuristics) + next actions"
{
  echo "### QUICK FLAGS"
  echo "- If ${NS_KSERVE} namespace is Terminating: delete stuck webhooks/CRDs or remove finalizers; check 50/51/60 outputs."
  echo "- If isvc shows 'ServerlessModeRejected': you are in RawDeployment mode (no Knative). Ensure inferenceservice-config deploy is valid JSON."
  echo "- If admission webhook denies requests: check 46, 50, 51, 47 outputs."
  echo "- If no pods/services created for ISVC: controller logs (45) will show why (missing runtime, invalid storage, webhook, permission)."
  echo
  echo "### CURRENT CONFIG CHECKS"
  echo -n "deploy CM (.data.deploy): "
  kubectl -n "${NS_KSERVE}" get cm inferenceservice-config -o jsonpath='{.data.deploy}{"\n"}' 2>/dev/null || echo "N/A"
  echo
  echo "### SUGGESTED ONE-LINERS"
  echo "kubectl -n ${NS_KSERVE} logs deploy/kserve-controller-manager --tail=200"
  echo "kubectl -n ${NS_APP} describe isvc ${ISVC_NAME}"
  echo "kubectl -n ${NS_APP} get deploy,po,svc -o wide"
} > "${OUTDIR}/99_summary.txt" 2>&1 || true

say "DONE ✅"
echo "Debug bundle saved to: ${OUTDIR}"
echo
echo "Share these files here (copy/paste content):"
echo "  ${OUTDIR}/45_kserve_controller_logs.txt"
echo "  ${OUTDIR}/87_isvc_describe.txt"
echo "  ${OUTDIR}/47_inferenceservice_config_cm.txt"
echo "  ${OUTDIR}/99_summary.txt"
