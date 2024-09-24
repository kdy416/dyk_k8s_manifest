export KARPENTER_NAMESPACE="kube-system"
export KARPENTER_VERSION="1.0.1"
export K8S_VERSION="1.30"

export AWS_PARTITION="aws" # if you are not using standard partitions, you may need to configure to aws-cn / aws-us-gov
export CLUSTER_NAME="dyk-test-cluster"
export AWS_DEFAULT_REGION="ap-northeast-2"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export TEMPOUT="$(mktemp)"
export ARM_AMI_ID="$(aws ssm get-parameter --name /aws/service/eks/optimized-ami/${K8S_VERSION}/amazon-linux-2-arm64/recommended/image_id --query Parameter.Value --output text)"
export AMD_AMI_ID="$(aws ssm get-parameter --name /aws/service/eks/optimized-ami/${K8S_VERSION}/amazon-linux-2/recommended/image_id --query Parameter.Value --output text)"
export GPU_AMI_ID="$(aws ssm get-parameter --name /aws/service/eks/optimized-ami/${K8S_VERSION}/amazon-linux-2-gpu/recommended/image_id --query Parameter.Value --output text)"

echo "${KARPENTER_NAMESPACE}" "${KARPENTER_VERSION}" "${K8S_VERSION}" "${CLUSTER_NAME}" "${AWS_DEFAULT_REGION}" "${AWS_ACCOUNT_ID}" "${TEMPOUT}" "${ARM_AMI_ID}" "${AMD_AMI_ID}" "${GPU_AMI_ID}"

# CloudFormation 파일 다운로드 
curl -fsSL https://raw.githubusercontent.com/aws/karpenter-provider-aws/v"${KARPENTER_VERSION}"/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml  > "${TEMPOUT}" 

# CloudFormation 적용
aws cloudformation deploy \
  --stack-name "Karpenter-${CLUSTER_NAME}" \
  --template-file "${TEMPOUT}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterName=${CLUSTER_NAME}"

# EKS Cluster Tag 구성
aws eks tag-resource \
  --resource-arn arn:aws:eks:${AWS_REGION}:${AWS_ACCOUNT_ID}:cluster/${CLUSTER_NAME} \
  --tags karpenter.sh/discovery=${CLUSTER_NAME}

# EKS Pod Identity Agent 설치
aws eks create-addon --cluster-name ${CLUSTER_NAME} --addon-name eks-pod-identity-agent --addon-version v1.0.0-eksbuild.1
kubectl get pods -n kube-system | grep 'eks-pod-identity-agent'

# EKS IAM ServiceAccount 생성
eksctl create iamserviceaccount \
  --name karpenter \
  --namespace ${KARPENTER_NAMESPACE} \
  --cluster ${CLUSTER_NAME} \
  --attach-policy-arn arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerPolicy-${CLUSTER_NAME} \
  --role-name ${CLUSTER_NAME}-karpenter \
  --approve

# EKS IAM Identity Mapping
eksctl create iamidentitymapping \
  --cluster ${CLUSTER_NAME} \
  --arn arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME} \
  --username system:node:{{EC2PrivateDNSName}} \
  --group system:bootstrappers \
  --group system:nodes