#!/bin/bash
#/ Description:
#/      DELETE DOCKER SWARM AWS EC2 CLUSTER
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

# load properties from file into environment variable
# shellcheck source=aws-variables.properties
PROPERTIES_FILE="${BASEDIR}/aws-variables.properties"
set -o allexport; source "${PROPERTIES_FILE}"; set +o allexport
# load passwords from file into environment variables
# shellcheck source=password.properties
PASSWORDS_FILE="${BASEDIR}/password.properties"
set -o allexport; source "${PASSWORDS_FILE}"; set +o allexport

export AWS_PROFILE=$AWS_PROFILE
export AWS_REGION=$AWS_REGION
aws configure set region "$AWS_REGION" --profile "$AWS_PROFILE"

if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
  SECONDS=0

  if is_no_colors; then
    unset_colors
  else
    set_colors
  fi

  separator
  bump_step "CLEANING UP DOCKER SWARM CLUSTER"
  
  cleanup_elb

  wait_for 10

  cleanup_workers

  wait_for 15

  cleanup_managers

  wait_for 15

  cleanup_flow_logs    

  wait_for 10

  cleanup_vpc
  #TODO
  
  separator
  ELAPSED="Elapsed: $((SECONDS / 3600))hrs $(((SECONDS / 60) % 60))min $((SECONDS % 60))sec"
  bump_step "FINISHED CREATING SWARM CLUSTER :: $ELAPSED"
  separator
fi