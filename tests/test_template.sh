#!/bin/bash -eux

CHART="charts/codesealer"

function fail {
    echo "line $BASH_LINENO: $1" && exit 1
}

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add securecodebox https://charts.securecodebox.io/  

helm dependency build "${CHART}"

echo "========= RUNNING TESTS ========="

helm template codesealer "${CHART}" \
    --set codesealerToken="CODESEALER_TOKEN" \
    --set sidecar.enabled=true \
    --set ingress-nginx.install=false \
    >/dev/null || fail "Expected command to succeed"

helm template codesealer "${CHART}" \
    --set codesealerToken="CODESEALER_TOKEN" \
    --set sidecar.enabled=false \
    --set ingress-nginx.install=false \
    >/dev/null || fail "Expected command to succeed"

helm template codesealer "${CHART}" \
    --set codesealerToken="CODESEALER_TOKEN" \
    --set sidecar.enabled=false \
    --set ingress-nginx.install=true \
    >/dev/null || fail "Expected command to succeed"

helm template codesealer "${CHART}" \
    --set codesealerToken="CODESEALER_TOKEN" \
    --set sidecar.enabled=true \
    --set ingress-nginx.install=true \
    &>/dev/null && fail "Expected command to fail"

echo "========= END TESTS ========="

exit 0