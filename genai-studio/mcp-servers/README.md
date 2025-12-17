# MCP Weather Server Deployment

This directory contains Kubernetes/OpenShift manifests to deploy the MCP Weather Server.

## Image

- **Image**: `quay.io/hayesphilip/mcp-weather`

## Files

| File | Description |
|------|-------------|
| `ns.yaml` | Creates the `mcp-weather` namespace |
| `deployment.yaml` | Deploys the MCP weather server container |
| `service.yaml` | Exposes the deployment as a ClusterIP service |
| `route.yaml` | Creates an OpenShift Route for external access |
| `configmap.yaml` | ConfigMap for GenAI playground MCP server registration |

## Deployment

### Deploy all resources

```bash
# Create namespace
oc apply -f ns.yaml

# Deploy the server
oc apply -f deployment.yaml

# Create the service
oc apply -f service.yaml

# Create the route (OpenShift only)
oc apply -f route.yaml
```

Or deploy everything at once:

```bash
oc apply -f ns.yaml -f deployment.yaml -f service.yaml -f route.yaml
```

### Verify deployment

```bash
# Check deployment status
oc get deployment -n mcp-weather

# Check pods
oc get pods -n mcp-weather

# Get the route URL
oc get route mcp-weather -n mcp-weather -o jsonpath='{.spec.host}'
```

## Configuration

The default deployment exposes the server on port **8000**. Adjust the deployment if your MCP server uses a different port.

### Health Probes

The deployment includes liveness and readiness probes pointing to `/health` on port 8000. Modify these paths if your MCP server uses different health endpoints.

### How to test MCP Server Demo
Please ensure to check the box of the MCP server you want to test it. 

## Sample Weather MCP Demo 

Use the following prompt to test how Weather MCP works with GenAI Studio Playground. 

```bash
what is the weather in Boston? 
```

## Sample GitHub MCP Demo

Use the following prompt to test how GitHub MCP works with GenAI Studio Playground. 

```bash
get me the latest commit from "https://github.com/dinlaks/OpenShiftAISetup-3.x" repo
```

## Sample Tavily MCP Demo 

Use the following prompt to test how Tavily Web-Search MCP works with GenAI Studio Playground. 

```bash
summarize the latest top 5 news
```
