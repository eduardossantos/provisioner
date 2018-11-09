#!/bin/bash
#/ Description:
#/      CREATE DOCKER SWARM AWS EC2 CLUSTER
#/ Usage:
#/ Options:
#/ Examples:
#/      DEBUG=true ./create-ec2-swarm-cluster.sh  (Enable debug messages)
#/      NO_COLORS=true ./create-ec2-swarm-cluster.sh (Disable colors)
#/ --------------------------------------------------------------------------------
#/ Author: Rogério Castelo Branco Peixoto (rogerio.c.peixoto@accenture.com)
#/ --------------------------------------------------------------------------------
usage() { grep '^#/' "$0" | cut -c4- ; exit 0 ; }
expr "$*" : ".*--help" > /dev/null && usage

BASEDIR=$(dirname "$0")

##################################################################
# SOURCING LIB FUNCTIONS
##################################################################

# shellcheck source=utils/colors.sh
source "${BASEDIR}"/utils/colors.sh
# shellcheck source=utils/check-dependencies.sh
source "${BASEDIR}"/utils/check-dependencies.sh
# shellcheck source=utils/properties-utils.sh
source "${BASEDIR}"/utils/properties-utils.sh
# shellcheck source=aws/lib/aws-security-group-utils.sh
source "${BASEDIR}"/aws/lib/aws-security-utils.sh
# shellcheck source=aws/lib/aws-vpc-network-utils.sh
source "${BASEDIR}"/aws/lib/aws-vpc-network-utils.sh
# shellcheck source=aws/lib/aws-iam-policy-utils.sh
source "${BASEDIR}"/aws/lib/aws-iam-policy-utils.sh
# shellcheck source=aws/lib/aws-route53-utils.sh
source "${BASEDIR}"/aws/lib/aws-route53-utils.sh
# shellcheck source=aws/lib/aws-docker-swarm-utils.sh
source "${BASEDIR}"/aws/lib/aws-docker-swarm-utils.sh
# shellcheck source=aws/lib/aws-elb-utils.sh
source "${BASEDIR}"/aws/lib/aws-elb-utils.sh
# shellcheck source=aws/lib/aws-logs-utils.sh
source "${BASEDIR}"/aws/lib/aws-logs-utils.sh
# shellcheck source=aws/lib/aws-acm-utils.sh
source "${BASEDIR}"/aws/lib/aws-acm-utils.sh
# shellcheck source=aws/lib/aws-cleanup-utils.sh
source "${BASEDIR}"/aws/lib/aws-cleanup-utils.sh
# shellcheck source=ansible/lib/ansible-utils.sh
source "${BASEDIR}"/ansible/lib/ansible-utils.sh

PROPERTIES_FILE="${BASEDIR}/aws-variables.properties"
# load properties from file into environment variable
# shellcheck source=aws-variables.properties
set -o allexport; source "${PROPERTIES_FILE}"; set +o allexport
# load passwords from file into environment variables
PASSWORDS_FILE="${BASEDIR}/password.properties"
# shellcheck source=password.properties
set -o allexport; source "${PASSWORDS_FILE}"; set +o allexport
# properties output file
PROPERTIES_FILE_OUT="${BASEDIR}/aws-variables-out.properties"
touch "${PROPERTIES_FILE_OUT}"
# shellcheck source=./aws-variables-out.properties
set -o allexport; source "${PROPERTIES_FILE_OUT}"; set +o allexport

export AWS_PROFILE=$AWS_PROFILE
export AWS_REGION=$AWS_REGION
aws configure set region "$AWS_REGION" --profile "$AWS_PROFILE"
##################################################################
# MANDATORY VARIABLES
##################################################################
# CLI PARAMS
AWS_KEY_ID=${AWS_KEY_ID:?}
AWS_SECRET_KEY=${AWS_SECRET_KEY:?}

# SSH KEYS
AWS_KEY_PAIR_NAME=${AWS_KEY_PAIR_NAME:?}
AWS_KEY_PAIR_PATH=${AWS_KEY_PAIR_PATH:?}

# TAG INFORMATION
TAG_PREFIX=${TAG_PREFIX:?}
PROJECT_OWNER=${PROJECT_OWNER:?}

##################################################################
# SETTING DEFAULT PROPERTIES
##################################################################

KEY_PAIR_CREATED_FILE=${KEY_PAIR_CREATED_FILE:-'ec2-swarm-cluster.pem'}
KEY_PAIR_CREATED_NAME=${KEY_PAIR_CREATED_NAME:-'ec2-swarm-cluster'}

DOCKER_MACHINE_DRIVER=${DOCKER_MACHINE_DRIVER:-'amazonec2'}

ENVIRONMENT=${ENVIRONMENT:-'development'}
DATE=$(date "+%Y%m%dT%H%M%S")
AWS_TAGS=${AWS_TAGS:-"Key=Project,Value=$TAG_PREFIX Key=Cost,Value=oi-wfm Key=Environment,Value=$ENVIRONMENT Key=Owner,Value=$PROJECT_OWNER Key=Date,Value=$DATE"}
VPC_NAME="${TAG_PREFIX}-${ENVIRONMENT}-vpc"

AWS_SUBNET_ID=${AWS_SUBNET_ID:-''}
AWS_AV_ZONE=${AWS_AV_ZONE:-'c'}
AWS_INSTANCE_TYPE=${AWS_INSTANCE_TYPE:-'t2.medium'}
AWS_INSTANCE_SIZE=${AWS_INSTANCE_SIZE:-'50'}
AWS_SECGROUP_NAME=${AWS_SECGROUP_NAME:-"$TAG_PREFIX-swarm-cluster-sec-group"}
AWS_CERTIFICATE_DOMAIN=${AWS_CERTIFICATE_DOMAIN:-"*.digitaltechstudio.net"}

AWS_DKR_MACHINE_TAGS=${AWS_DKR_MACHINE_TAGS:-"Project,$TAG_PREFIX"}
AWS_FILTER_TAG_KEY=$(echo "${AWS_DKR_MACHINE_TAGS}" | awk '{split($0, a, ","); print a[1]}')
AWS_FILTER_TAG_VALUE=$(echo "${AWS_DKR_MACHINE_TAGS}" | awk '{split($0, a, ","); print a[2]}')

AWS_PROFILE=${AWS_PROFILE:-'swarm-admin'}
AWS_REGION=${AWS_REGION:-'us-east-1'}
AWS_REGISTRY_ID=${AWS_REGISTRY_ID:-'728118514760'}
AWS_CLI_USER=${AWS_CLI_USER:-'root'}

# DNS info
AWS_ROUTE_53_DOMAIN=${AWS_ROUTE_53_DOMAIN:-'digitaltechstudio.net'}
AWS_ROUTE_53_SUBDOMAIN=${AWS_ROUTE_53_SUBDOMAIN:-"$TAG_PREFIX-sub-domain"}

AWS_EC2_AMI_DEFAULT_USER=${AWS_EC2_AMI_DEFAULT_USER:-'ubuntu'}

# NETWORK CIDR
AWS_VPC_IPV4_CIDR=${AWS_VPC_IPV4_CIDR:-'172.31.0.0/24'}

# swarm nodes
NODE_PREFIX="$TAG_PREFIX-$ENVIRONMENT"
DOCKER_SWARM_MANAGER_NAME=${DOCKER_SWARM_MANAGER_NAME:-"$NODE_PREFIX-manager01"}

declare -a DOCKER_SWARM_WORKERS_ARRAY=("$NODE_PREFIX-worker01" "$NODE_PREFIX-worker02")
declare -a DOCKER_SWARM_PORTS_TO_OPEN_ARRAY=("tcp:2377" "tcp:7946" "udp:7946" "tcp:4789" "udp:4789")

AWS_VPC_FLOW_LOGS_ROLE=${AWS_VPC_FLOW_LOGS_ROLE:-"$TAG_PREFIX-vpc-flow-logs-role"}
AWS_VPC_FLOW_LOGS_POLICY=${AWS_VPC_FLOW_LOGS_POLICY:-"$TAG_PREFIX-flow-logs-policy"}
AWS_VPC_FLOW_LOGS_POLICY_FILE=${AWS_VPC_FLOW_LOGS_POLICY_FILE:-'file://aws/vpc-flow-logs-policy.json'}
AWS_VPC_FLOW_LOGS_ROLE_FILE=${AWS_VPC_FLOW_LOGS_ROLE_FILE:-'file://aws/vpc-flow-logs-role.json'}

AWS_LOG_GROUP_NAME=${AWS_LOG_GROUP_NAME:-"$TAG_PREFIX-vpc-log-group"}
AWS_LOG_GROUP_RETENTION=${AWS_LOG_GROUP_RETENTION:-"180"}

AWS_ELB_NAME="$TAG_PREFIX-classic-elb"
AWS_SSH_ELB_NAME="$AWS_ELB_NAME-ssh"

AWS_PROVISIONING_COMPLETE=${AWS_PROVISIONING_COMPLETE:-false}

declare -a AWS_ELB_MAPPING=("HTTP/80:80" "HTTPS/443:443")

##################################################################
# ENF OF SETTING DEFAULT PROPERTIES
##################################################################

IFS=' '

wait_for(){
  debug

  local TIME_TO_WAIT=$1

  warning "Waiting $TIME_TO_WAIT seconds"
  sleep ${TIME_TO_WAIT}
}

check_current_script_dependencies(){
  debug
  
  check_awk
  check_docker_machine
  check_python
  check_pip
  check_aws_cli
  check_jq
  check_ansible
}

if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
  SECONDS=0

  if is_no_colors; then
    unset_colors
  else
    set_colors
  fi

  trap 'err_cleanup "$BASH_COMMAND"' ERR
  trap 'exit_cleanup' EXIT

  set -eE

  export CURRENT_PHASE=0
  separator
  bump_step "CREATING EC2 SWARM CLUSTER"

  if [[ "$AWS_PROVISIONING_COMPLETE" != "true" ]]; then
    separator
    bump_step "CHECKING SCRIPT DEPENDENCIES"

    check_current_script_dependencies

    separator
    bump_step "CREATING VPC"

    create_vpc

    wait_for 10

    separator
    bump_step "CREATING SUBNET"

    create_subnet_in_vpc

    wait_for 20

    separator
    bump_step "CREATING INTERNET GATEWAY"

    create_internet_gateway_vpc

    wait_for 10

    log "${MAG}[PHASE]   1       COMPLETE${NC}"
    export CURRENT_PHASE=1

    separator
    bump_step "CREATING VPC FLOW LOGS"

    create_role_for_flow_logs

    get_role_arn_for_flow_logs

    create_cloudwatch_log_group

    create_vpc_flow_logs

    log "${MAG}[PHASE]   2       COMPLETE${NC}"
    export CURRENT_PHASE=2

    separator
    bump_step "CREATING SWARM MANAGER"

    create_swarm_manager

    wait_for 15

    separator
    bump_step "CONFIGURING SECURITY GROUP"

    get_aws_security_group "${AWS_SECGROUP_NAME}"

    open_docker_swarm_ports_in_security_group "${AWS_SECURITY_GROUP_ID}"
    open_http_port_in_security_group "${AWS_SECURITY_GROUP_ID}"
    open_https_port_in_security_group "${AWS_SECURITY_GROUP_ID}"
    open_ssh_port_in_security_group "${AWS_SECURITY_GROUP_ID}"

    log "${MAG}[PHASE]   3       COMPLETE${NC}"
    export CURRENT_PHASE=3

    separator
    bump_step "CREATING SWARM WORKERS"

    create_swarm_workers

    wait_for 5

    log "${MAG}[PHASE]   4       COMPLETE${NC}"
    export CURRENT_PHASE=4

    separator
    bump_step "CREATING LOAD BALANCERS"

    get_ec2_instance_ids

    create_elb "$AWS_ELB_NAME"

    wait_for 5

    create_ssh_elb "$AWS_SSH_ELB_NAME"

    log "${MAG}[PHASE]   5       COMPLETE${NC}"
    export CURRENT_PHASE=5


    separator
    bump_step "ENABLING TERMINATION PROTECTION"

    #AWS_EC2_INSTANCES_IDS
    get_ec2_instance_ids

    iterate_and_enable_termination_protection

    AWS_PROVISIONING_COMPLETE="true"
    set_property "AWS_PROVISIONING_COMPLETE" "$AWS_PROVISIONING_COMPLETE"

    wait_for 5
  fi

  separator
  bump_step "CREATING AWS ANSIBLE INVENTORY FILE"

  create_aws_ansible_inventory_file

  separator
  bump_step "EXPORTING DOCKER MACHINE CONFIGS"

  export_docker_machine_configs

  log "${MAG}[PHASE]   6       COMPLETE${NC}"
  export CURRENT_PHASE=6

  separator
  bump_step "CONFIGURING DOCKER SWARM"

  run_swarm_init_ansible_playbook

  separator
  bump_step "CLOSING SSH TO EXTERNAL NETWORK"

  close_ssh_port_in_security_group "0.0.0.0/0"

  separator
  bump_step "OPENING SSH TO INTERNAL NETWORK CIDR $AWS_VPC_IPV4_CIDR (SSH ELB)"

  open_ssh_port_direct "${AWS_VPC_IPV4_CIDR}"

  separator
  bump_step "SUBDOMAIN CREATION IN ROUTE 53"

  get_elb_dns_name "$AWS_ELB_NAME"

  create_registry_set_in_hosted_zone "${AWS_ROUTE_53_SUBDOMAIN}" "${AWS_ROUTE_53_DOMAIN}" "${AWS_ELB_DNS}"

  separator
  bump_step "FINISHED CREATING SWARM CLUSTER "
  separator
fi
