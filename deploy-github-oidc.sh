#!/bin/bash
set -e

CFN_TEMPLATE_PATH="cloudformation/templates/github-oidc.cfn.yaml"
CONFIG_FILE="config.yaml"

# Check if required files exist
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found at $CONFIG_FILE"
    exit 1
fi

if [ ! -f "$CFN_TEMPLATE_PATH" ]; then
    echo "Error: CloudFormation template not found at $CFN_TEMPLATE_PATH"
    exit 1
fi

# Check if yq is installed
if ! command -v yq &> /dev/null; then
    echo "Error: yq is not installed. Please install it first."
    echo "Install with:"
    echo "  - On macOS: brew install yq"
    echo "  - On Linux: snap install yq or wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && chmod +x /usr/bin/yq"
    exit 1
fi

# Load configuration using yq
echo "Loading configuration from $CONFIG_FILE..."

# Get values with defaults using yq and strip quotes
AWS_PROFILE=$(yq '.aws_profile' "$CONFIG_FILE" | tr -d '"')
GITHUB_ORG=$(yq '.github_organization // ""' "$CONFIG_FILE" | tr -d '"')
STACK_NAME=$(yq '.provider_stack_name // ""' "$CONFIG_FILE" | tr -d '"')
REGION=$(yq '.aws_region' "$CONFIG_FILE" | tr -d '"')
PROVIDER_NAME=$(yq '.provider_name // "GitHubOIDCProvider"' "$CONFIG_FILE" | tr -d '"')
SSM_PREFIX=$(yq '.ssm_parameter_prefix // "/github/oidc"' "$CONFIG_FILE" | tr -d '"')

# Set AWS profile if not provided
if [ -z "$AWS_PROFILE" ]; then
    echo "Error: AWS_PROFILE not specified in config"
    exit 1
fi

# Set default stack name if not provided
if [ -z "$STACK_NAME" ]; then
    STACK_NAME="github-oidc-provider"
fi

# Validate required fields
if [ -z "$GITHUB_ORG" ]; then
    echo "Error: GitHub organization not specified in config"
    exit 1
fi

# Set default region if not provided
if [ -z "$REGION" ]; then
    REGION="eu-west-3"
fi

# Display deployment information
echo "Deploying GitHub OIDC Provider configuration with:"
echo "- Stack Name: $STACK_NAME"
echo "- GitHub Organization: $GITHUB_ORG"
echo "- Provider Name: $PROVIDER_NAME"
echo "- SSM Parameter Prefix: $SSM_PREFIX"
echo "- AWS Profile: $AWS_PROFILE"
echo "- AWS Region: $REGION"

# Confirm deployment
read -p "Do you want to continue with deployment? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 0
fi

# Deploy CloudFormation stack
echo "Deploying CloudFormation stack..."
aws cloudformation deploy \
  --profile "$AWS_PROFILE" \
  --region "$REGION" \
  --template-file "$CFN_TEMPLATE_PATH" \
  --stack-name "$STACK_NAME" \
  --parameter-overrides \
  GitHubOrganization="$GITHUB_ORG" \
  ProviderName="$PROVIDER_NAME" \
  SSMParameterPrefix="$SSM_PREFIX" \
  --capabilities CAPABILITY_IAM

# Get the OIDC Provider ARN and SSM parameter paths
PROVIDER_ARN=$(aws cloudformation describe-stacks \
  --profile "$AWS_PROFILE" \
  --region "$REGION" \
  --stack-name "$STACK_NAME" \
  --query "Stacks[0].Outputs[?OutputKey=='OIDCProviderARN'].OutputValue" \
  --output text)

SSM_ARN_PATH=$(aws cloudformation describe-stacks \
  --profile "$AWS_PROFILE" \
  --region "$REGION" \
  --stack-name "$STACK_NAME" \
  --query "Stacks[0].Outputs[?OutputKey=='SSMProviderARNPath'].OutputValue" \
  --output text)

SSM_URL_PATH=$(aws cloudformation describe-stacks \
  --profile "$AWS_PROFILE" \
  --region "$REGION" \
  --stack-name "$STACK_NAME" \
  --query "Stacks[0].Outputs[?OutputKey=='SSMProviderURLPath'].OutputValue" \
  --output text)

# Create a success message
echo "=================================================="
echo "Successfully created OIDC Provider: $PROVIDER_ARN"
echo ""
echo "SSM Parameters created:"
echo "- Provider ARN: $SSM_ARN_PATH"
echo "- Provider URL: $SSM_URL_PATH"
echo ""
echo "To create an IAM role that trusts this provider, use the script deploy-github-oidc-role.sh"
echo "Make sure to update the config file with:"
echo "oidc_provider_ssm_param: \"$SSM_ARN_PATH\""
echo "=================================================="