
# OpenShift AI Setup - LLM Distributed (llm-d) Guide - TBD

## Overview

This guide covers the setup and deployment of Large Language Models (LLMs) using OpenShift AI's distributed inference service (llm-d). **The order of operations is critical** — improper sequencing will result in authentication failures or access issues.

## Prerequisites

- OpenShift cluster with administrator access
- Cluster domain information

## Setup Steps

### 1. Configure Gateway (Cluster Administrator)

Create a `GatewayClass` and `Gateway` for the inference service.

**Important:** Replace `<cluster-domain>` placeholder and configure allowed namespaces in the `allowedRoutes` section.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
    name: openshift-ai-inference
spec:
    controllerName: openshift.io/gateway-controller/v1
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
    labels:
        istio.io/rev: openshift-gateway
    name: openshift-ai-inference
    namespace: openshift-ingress
spec:
    gatewayClassName: openshift-ai-inference
    listeners:
        - allowedRoutes:
                namespaces:
                    from: Selector
                    selector:
                        matchExpressions:
                            - key: kubernetes.io/metadata.name
                                operator: In
                                values:
                                    - openshift-ingress
                                    - redhat-ods-applications
                                    - my-first-model
            hostname: inference-gateway.apps.<cluster-domain>
            name: https
            port: 443
            protocol: HTTPS
            tls:
                certificateRefs:
                    - group: ''
                        kind: Secret
                        name: default-gateway-tls
                mode: Terminate
```

### 2. Install LeaderWorkerSet Operator (Optional)

**Required only for:** MoE, MultiGPU/node llm-d deployments

```yaml
apiVersion: operator.openshift.io/v1
kind: LeaderWorkerSetOperator
metadata:
    name: cluster
    namespace: openshift-lws-operator
spec:
    managementState: Managed
    logLevel: Normal
    operatorLogLevel: Normal
```

### 3. Create Kuadrant Namespace & Install RHCL Operator

1. Create the `kuadrant-system` namespace
2. Install Red Hat Connectivity Link (RHCL) Operator in `kuadrant-system` (required namespace)

### 4. Create Kuadrant Instance

```yaml
apiVersion: kuadrant.io/v1beta1
kind: Kuadrant
metadata:
    name: kuadrant
    namespace: kuadrant-system
```

### 5. Enable SSL in Authorino

**Option A:** Annotate the Authorino service

```bash
oc annotate svc/authorino-authorino-authorization \
    service.beta.openshift.io/serving-cert-secret-name=authorino-server-cert \
    -n kuadrant-system
```

**Option B:** Update Authorino object

```yaml
apiVersion: operator.authorino.kuadrant.io/v1beta1
kind: Authorino
metadata:
    name: authorino
    namespace: kuadrant-system
spec:
    replicas: 1
    clusterWide: true
    listener:
        tls:
            enabled: true
            certSecretRef:
                name: authorino-server-cert
    oidcServer:
        tls:
            enabled: false
```

## Deploying Models

### Via UI

1. Select **llm-d** as the serving runtime
2. Configure deployment parameters:
     - **Model Location:** URI v3
     - **Connection Name:** (e.g., `qwen3-sample`)
     - **URI:** `oci://registry.redhat.io/rhelai1/modelcar-qwen3-8b-fp8-dynamic:latest`
     - **Model Type:** Generative AI Model
     - **Hardware Profile:** gpu-profile
     - **Replicas:** 1 or 2
3. Check **Require Authentication** (optional, but setup steps are mandatory)
4. Specify ServiceAccount name or allow auto-creation
5. Enable **Model Playground** as AI asset endpoint

## Notes

- All setup steps must be completed in order, even without authentication enabled
- Misconfiguration at any step may cause authentication or access failures
- Security consideration: Use namespace selectors to prevent unauthorized traffic hijacking
