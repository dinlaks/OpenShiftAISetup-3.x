# OpenShift AI 3.0 - Deploy Model

## Overview
This guide covers deploying a model on Red Hat OpenShift AI 3.0.

## Prerequisites
- OpenShift cluster access
- OpenShift AI 3.0 installed
- Model artifacts prepared

## Steps

### 1. Prepare Your Model
- Package model files
- Define model serving requirements
- Configure resource limits

### 2. Create Model Server
- Deploy model serving runtime
- Configure model endpoints
- Set up authentication

### 3. Deploy the Model
- Push model to model registry
- Create inference service
- Validate deployment

### 4. Test Inference
- Query model endpoints
- Verify predictions
- Monitor performance

## Troubleshooting
Check OpenShift logs for deployment issues:
```bash
oc logs -f <pod-name>
```

## Additional Resources
- [OpenShift AI Documentation](https://access.redhat.com/documentation/en-us/red_hat_openshift_ai/)
- [Deploy Model Guide](https://rhpds.github.io/redhat-openshift-ai-3-showroom/modules/03-03-deploy-model.html)
