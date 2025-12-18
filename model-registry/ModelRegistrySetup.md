
# Model Registry Setup Guide

## Prerequisites
- OpenShift cluster access
- kubectl or oc CLI installed
- YAML configuration files ready

## Step 1: Configure MySQL Database

Use the `mysql-db.yaml` configuration file to deploy MySQL:

```bash
oc apply -f mysql-db.yaml
```

This creates:
- MySQL deployment
- Database service
- Persistent storage (if configured)

Verify the MySQL pod is running:

```bash
oc get pods -l app=mysql
```

## Step 2: Create Model Registry

Once MySQL is ready, deploy the Model Registry using `model-registry-create.yaml`:

```bash
oc apply -f model-registry-create.yaml
```

Verify the Model Registry deployment:

```bash
oc get pods -l app=model-registry
```

## Verification

Check all resources are running:

```bash
oc get all
```

Access logs for troubleshooting:

```bash
oc logs -l app=model-registry
oc logs -l app=mysql
```

## Registering a Model in the UI

### Overview
The Model Registry supports two methods for registering models. The primary method uses the UI registration interface.

### Important Note
Model Registry captures the model location rather than storing the model directly. You must first obtain your model (from Hugging Face or similar sources) and store it in an S3 bucket.

### Registration Steps

1. Click the **Register Model** button on the Model Catalog screen
2. Fill in the registration form with the following information:
    - Model name and version
    - Model description
    - Framework and task type

3. Configure the **Data Connection** section:
    - Provide your S3 bucket details
    - Enter S3 credentials (access key and secret key)
    - Specify the path to your model in the S3 bucket

4. Click **Submit** to complete registration

### After Registration
Your registered model will appear in the Model Catalog screen and be available for use in your ML workflows.


### Additional Resources

For more detailed information on using the Model Registry UI, refer to the [github documentation](https://github.com/opendatahub-io/model-registry-operator/blob/main/docs/how-to-use-ui.md).


## Next Steps

- Configure Model Registry settings
- Set up connections to your ML workflow
- Review security policies and networking
