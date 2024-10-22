# cgahiu 

## Summary

In this project, I implemented **ArgoCD Image Updater** to automate the continuous deployment of containerized applications in a Kubernetes environment. By utilizing **Semantic Versioning (SemVer)**, I automated image updates and ensured scalability using Kubernetes autoscaling, including Pub/Sub-based autoscaling. Slack notifications were integrated to monitor ArgoCD events, and secrets were securely managed using Google Cloud Secret Manager. This report outlines the folder structure, configuration files, and Helm templates used in the implementation, showcasing a robust and scalable deployment solution.The project utilized **cgahiuQ1's cluster** and Artifact Registry.

### Disclaimer
The YAML files provided in the **`infra-config`** folder contain the actual production configuration files used in this project. The examples of YAML configurations shown in the documentation are simplified or shortened versions intended to demonstrate the usage and structure of these files. For the full and exact configurations deployed in this project, please refer to the files in the **`infra-config`** folder


## Requirements Overview

### Fulfilled Requirements:

1. **Git Folder Structure for Multiple Namespaces/Deployments**
    - I implemented a well-structured Git repository supporting multiple environments (development, production) and namespaces.
2. **Proper Helm Template Usage**
    - I used Helm charts to dynamically generate Kubernetes manifests based on environment-specific values.
3. **Slack Notifications Integration**
    - I configured Slack notifications for ArgoCD events, using Google Cloud Secret Manager for secure management of Slack API tokens.
4. **Automated Image Synchronization**
    - I set up ArgoCD Image Updater to automatically pull the latest container images and trigger application syncs when new images were pushed to the container registry.
5. **Scalable Application with Pub/Sub-based Autoscaling**
    - Kubernetes Horizontal Pod Autoscaling (HPA) was configured to dynamically scale application resources based on both CPU utilization and unacknowledged Pub/Sub messages, ensuring smooth scalability under load.

## Implementation Summary

### 1. Git Folder Structure

The Git repository is designed to manage multiple environments and namespaces, with separate `values.yaml` files for development and production configurations.

**Folder Structure:**

```
nodejs-express-mysql/
├── Dockerfile                 
├── README.md                  
├── app/                       
│   ├── ...                    
├── deploy/                    
│   ├── dev/                   
│   │   └── values-dev.yaml    
│   ├── prod/                  
│   │   └── values-prod.yaml   
│   └── helm/                  
│       ├── Chart.yaml         
│       ├── templates/         
│       └── values.yaml        
```

### 2. Helm Template Usage

Helm is used to manage Kubernetes manifests and parameterize deployments for different environments. 

**Sample Helm Values for Development Environment (`values-dev.yaml`):**

```yaml
replicaCount: 2
app:
  name: nodejs-express-app
  namespace: nodejs-dev
  environment: dev
image:
  repository: europe-west1-docker.pkg.dev/cgahiu-q1/cgahiu-repo/nodejs-express-app
  pullPolicy: Always
  tag: ""
service:
  type: LoadBalancer
  port: 8080
resources:
  requests:
    memory: "64Mi"
    cpu: "10m"
  limits:
    memory: "128Mi"
    cpu: "100m"
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  pubsub:
    enabled: true
    subscription: "projects/cgahiu-q1/subscriptions/nodejs-dev-nodejs-express-app-topic-sub"
    unacknowledgedMessageThreshold: 50
```

### 3. Slack Notification Integration

ArgoCD is configured to send notifications to Slack channels for sync events (success, failure, and health degradation). OAuth2 tokens are managed securely through Google Cloud Secret Manager.

_Please check the `#argocd-img-updater` channel._

[**Slack Workspace Invite** ](https://join.slack.com/t/okaykacar/shared_invite/zt-2r24duzde-IQmyll2ifaFVvamj92OJGQ)

**ClusterSecretStore for GCP Secret Manager:**

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: gcp-secret-manager
spec:
  provider:
    gcpsm:
      projectID: cgahiu-q1  
      auth:
        secretRef:
          secretAccessKeySecretRef:
            name: gcp-credentials-secret
            key: credentials.json
            namespace: argocd
```

**ExternalSecret for Slack Token:**

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: argocd-notifications-secret
  namespace: argocd
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-secret-manager
    kind: ClusterSecretStore
  target:
    name: argocd-notifications-secret
    creationPolicy: Owner
  data:
    - secretKey: slack-token    
      remoteRef:
        key: slack-token       
        version: latest         
```

**ConfigMap for Slack Notifications:**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  service.slack: |
    token: $slack-token
  subscribe.on-sync-failed.slack: '#argocd-img-updater'
  subscribe.on-sync-running.slack: '#argocd-img-updater'
  subscribe.on-sync-succeeded.slack: '#argocd-img-updater'
  template.app-deployed: |
    slack:
      attachments: |
        [{
          "title": "{{ .app.metadata.name}}",
          "title_link": "{{.context.argocdUrl}}/applications/{{.app.metadata.name}}",
          "color": "#18be52",
          "fields": [
          {
            "title": "Sync Status",
            "value": "{{.app.status.sync.status}}",
            "short": true
          }]
        }]
```


### 4. Automated Image Synchronization and Authentication

I utilized **ArgoCD Image Updater** to automate the synchronization of container images. Every time a new Docker image is pushed to the Google Artifact Registry, ArgoCD automatically pulls and updates the Kubernetes deployments.

The following sections outline the integration of the image updater, including the setup of a **GitHub Actions workflow** for building and pushing images to Google Artifact Registry, and the **authentication ConfigMap** for granting ArgoCD access to the registry.

#### a. GitHub Actions Workflow

A **GitHub Actions** workflow automates the process of building and pushing Docker images to the **Google Artifact Registry** whenever new changes are pushed to the main branch. The workflow tags images semantically using versioning and provides the necessary environment variables and secrets for registry authentication.

**GitHub Actions Workflow (`github-actions.yml`):**

```yaml
name: Build and Push Docker Image
on:
  push:
    branches:
      - main
jobs:
  build:
    if: github.actor != 'argocd-image-updater'
    runs-on: ubuntu-latest
    env:
      IMAGE_TAG: 1.0.${{ github.run_number }}
    steps:
      - name: Checkout Source Code
        uses: actions/checkout@v3

      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v1
        with:
          credentials_json: ${{ secrets.GCP_SERVICE_ACCOUNT_KEY }}

      - name: Configure Docker to use the Artifact Registry
        run: |
          gcloud auth configure-docker europe-west1-docker.pkg.dev

      - name: Build and Push Docker Image
        run: |
          docker build -t europe-west1-docker.pkg.dev/cgahiu-q1/cgahiu-repo/nodejs-express-app:${{ env.IMAGE_TAG }} .
          docker push europe-west1-docker.pkg.dev/cgahiu-q1/cgahiu-repo/nodejs-express-app:${{ env.IMAGE_TAG }}
```

Key steps:
- **Authenticate to Google Cloud**: The workflow uses a secret service account key stored in GitHub secrets to authenticate with Google Cloud.
- **Docker Configuration**: Docker is configured to authenticate with Google Artifact Registry, allowing it to push images.
- **Build and Push**: The Docker image is built and pushed to the specified registry with a versioned tag.

#### b. ArgoCD Image Updater Configuration

**ArgoCD Image Updater** is responsible for monitoring the Google Artifact Registry for new images and automatically updating the Kubernetes deployments when a new image is detected. 

To enable ArgoCD Image Updater to access the **Google Artifact Registry**, we use a **ConfigMap** containing a script that retrieves the necessary OAuth2 access token.

**ArgoCD Image Updater Config (`argocd-image-updater-config.yaml`):**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-image-updater-config
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-image-updater-config
    app.kubernetes.io/part-of: argocd-image-updater
data:
  git.commit-message-template: |
    Auto-commit by ArgoCD Image Updater [{{ .AppName }}]

    {{ range .AppChanges -}}
    updates image {{ .Image }} tag '{{ .OldTag }}' to '{{ .NewTag }}'
    {{ end -}}
  log.level: debug
  registries.conf: |
    registries:
      - name: GCP Artifact Registry
        prefix: europe-west1-docker.pkg.dev
        api_url: https://europe-west1-docker.pkg.dev
        credentials: ext:/auth/auth.sh
        credsexpire: 30m
```

Key configurations:
- **Automated Sync**: ArgoCD is configured to automatically sync and prune resources upon detecting new image updates.
- **Image Updater**: The `argocd-image-updater` annotations specify the image registry URL and the tag update strategy (SemVer in this case).

#### c. Authorization to Google Artifact Registry

To enable ArgoCD Image Updater to pull images from the **Google Artifact Registry**, we configure a **ConfigMap** that fetches the necessary OAuth2 access token from the Google Cloud Metadata server. This token is used to authenticate requests to the registry.

**Authentication ConfigMap (`auth-cm.yaml`):**

```yaml
apiVersion: v1
data:
  auth.sh: |
    #!/bin/sh
    ACCESS_TOKEN=$(wget --header 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token -q -O - | grep -Eo '"access_token":.*?[^\\]",' | cut -d '"' -f 4)
    echo "oauth2accesstoken:$ACCESS_TOKEN"
kind: ConfigMap
metadata:
  name: auth-cm
  namespace: argocd
```

- **OAuth2 Token Retrieval**: This script retrieves an access token from the **Google Cloud Metadata** server by querying the service account attached to the GKE (Google Kubernetes Engine) node.
- **Token Format**: The access token is formatted as `oauth2accesstoken:$ACCESS_TOKEN`, which ArgoCD uses for authenticating to the Google Artifact Registry.

### d. ArgoCD Image Updater Deployment with Authentication

To integrate the **authentication script** with ArgoCD, we configure ArgoCD to use the token retrieved by the script in the `auth-cm` ConfigMap. This ensures that ArgoCD can securely pull images from the registry.

**ArgoCD Image Updater with Authorization (`argocd-repository.yaml`):**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: repository-credentials
  namespace: argocd
data:
  url: europe-west1-docker.pkg.dev
  config: |
    authConfig:
      method: oauth2
      secretRef:
        name: auth-cm
        key: auth.sh
```

Key Points:
- **OAuth2 Authorization**: The Image Updater uses the script in the `auth-cm` ConfigMap to obtain the OAuth2 token for authenticating with the registry.
- **Repository Credentials**: The configuration defines the repository URL and references the `auth.sh` script for authorization.


### 5. Scalability and Pub/Sub-based Autoscaling

The Kubernetes Horizontal Pod Autoscaler (HPA) is configured to scale based on CPU utilization and the number of unacknowledged messages in a Google Pub/Sub subscription.

**Horizontal Pod Autoscaler (`hpa.yaml`):**

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ .Values.app.name }}-hpa
  namespace: {{ .Values.app.namespace }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ .Values.app.name }}
  minReplicas: {{ .Values.autoscaling.minReplicas }}
  maxReplicas: {{ .Values.autoscaling.maxReplicas }}
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: {{ .Values.autoscaling.targetCPUUtilizationPercentage }}
  - type: External
    external:
      metric:
        name: pubsub.googleapis.com|subscription|num_undelivered_messages
      target:
        type: Value
        value: {{ .Values.autoscaling.pubsub.unacknowledgedMessageThreshold }}
```

### 6. Deployment Configuration

The deployment manifests are designed to allow for flexible configuration across different environments using Helm templates.

**Deployment Template (`deployment.yaml`):**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.app.name }}
  namespace: {{ .Values.app.namespace }}
spec:
  replicas: {{ .Values.replicaCount }}
  template:
    metadata:
      labels:
        app: {{ .Values.app.name }}
        version: {{ .Values.image.tag | quote }}
    spec:
      containers:
      - name: {{ .Values.app.name }}
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        ports:
        - containerPort: {{ .Values.service.port }}
        resources:
          requests:
            memory: {{ .Values.resources.requests.memory }}
            cpu: {{ .Values.resources.requests.cpu }}
          limits:
            memory: {{ .Values.resources.limits.memory }}
            cpu: {{ .Values.resources.limits.cpu }}
```

## Conclusion

I successfully implemented **ArgoCD Image Updater** to automate container image updates and deployed a scalable solution using Kubernetes autoscaling with Pub/Sub integration. This was enhanced with **Slack notifications** for real-time deployment event monitoring and **Helm** for flexible configuration management. The project utilized cgahiuQ1's cluster and Google Artifact Registry, demonstrating an efficient and secure continuous deployment pipeline capable of dynamic scaling.

# cloud-native-gitops-argocd-helm-image-updater
# cloud-native-gitops-argocd-helm-image-updater
