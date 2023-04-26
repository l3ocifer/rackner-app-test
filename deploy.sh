#!/bin/bash

set -e

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Install required tools if not present
if ! command_exists aws; then
  echo "Installing AWS CLI..."
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip
  sudo ./aws/install
  rm awscliv2.zip
fi

if ! command_exists terraform; then
  echo "Installing Terraform..."
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt-get update && sudo apt-get install terraform -y
fi

if ! command_exists docker; then
  echo "Installing Docker..."
  curl -fsSL https://get.docker.com -o get-docker.sh
  sudo sh get-docker.sh
  rm get-docker.sh
fi

if ! command_exists envsubst; then
  echo "Installing gettext (provides envsubst)..."
  sudo apt-get install gettext -y
fi

if ! command_exists kubectl; then
  echo "Installing kubectl..."
  curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x ./kubectl
  sudo mv ./kubectl /usr/local/bin/kubectl
fi

# Check for AWS credentials in environment variables, or prompt the user for input
if [[ -z ${AWS_ACCESS_KEY_ID} || -z ${AWS_SECRET_ACCESS_KEY} ]]; then
  read -p "Enter your AWS access key: " AWS_ACCESS_KEY_ID
  read -p "Enter your AWS secret access key: " AWS_SECRET_ACCESS_KEY
fi

# Configure AWS CLI
aws configure set aws_access_key_id ${AWS_ACCESS_KEY_ID}
aws configure set aws_secret_access_key ${AWS_SECRET_ACCESS_KEY}

# Prompt for optional image tag
DEFAULT_TAG="1.24.0"
if [[ -z ${IMAGE_TAG} ]]; then
  read -p "Enter the image tag (default: ${DEFAULT_TAG}): " IMAGE_TAG
fi
IMAGE_TAG=${IMAGE_TAG:-$DEFAULT_TAG}

# Apply Terraform configuration
terraform init
terraform apply -auto-approve

# Update Kubeconfig
AWS_REGION=$(aws configure get region)
CLUSTER_NAME=$(terraform output -raw cluster_name)
aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}

# Get the ECR repository URL
ECR_REPOSITORY_URL=$(terraform output -raw ecr_repository_url)

# Authenticate Docker with ECR
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REPOSITORY_URL}


# Build the custom Nginx image using the Dockerfile
LOCAL_IMAGE_NAME="custom-nginx:${IMAGE_TAG}"
REMOTE_IMAGE_NAME="${ECR_REPOSITORY_URL}:${IMAGE_TAG}"

docker build -t ${LOCAL_IMAGE_NAME} .

# Tag the local image with the ECR repository URL
docker tag ${LOCAL_IMAGE_NAME} ${REMOTE_IMAGE_NAME}

# Push the image to ECR
docker push ${REMOTE_IMAGE_NAME}

# Replace the image URL and tag in the nginx-deploy.yml file
export ECR_REPOSITORY_URL IMAGE_TAG
envsubst < nginx-deploy.yml > nginx-deploy-final.yml

# Apply the updated deployment and service configuration
kubectl apply -f nginx-deploy-final.yml
kubectl apply -f nginx-svc.yml

#Remove final for cleanup
rm nginx-deploy-final.yml

echo "Waiting for the service to be available..."

while kubectl get svc nginx-svc | grep -q "<pending>"; do
#while ! kubectl get svc nginx-svc | grep -q "<EXTERNAL-IP>"; do
  sleep 5
done

# Get the LoadBalancer URL
LOAD_BALANCER_URL=$(kubectl get svc nginx-svc -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Write the LoadBalancer URL to url.md
echo "Visit the following URL to test the deployment: http://${LOAD_BALANCER_URL}" > url.md

# Write the LoadBalancer URL to output
echo "Visit the following URL to test the deployment: http://${LOAD_BALANCER_URL}"
echo "The site can sometimes take another minute or two to load. Please check the browser again in 1 minute if no message appears."
