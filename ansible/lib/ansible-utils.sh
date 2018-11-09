#!/bin/bash
#
# Requires colors.sh script
#
run_swarm_init_ansible_playbook(){
  debug

  run_playbook "docker-provision-ubuntu" "AWS"
  wait_for 15

  run_playbook "docker-swarm-provision" "AWS"
  wait_for 15

  run_playbook "docker-cleanup-cron" "AWS"
  wait_for 15
}

run_playbook(){
  debug
  
  export ANSIBLE_NOCOWS=1
  export ANSIBLE_RETRY_FILES_ENABLED=${ANSIBLE_RETRY_FILES_ENABLED:-false}
  export ANSIBLE_STDOUT_CALLBACK=${ANSIBLE_STDOUT_CALLBACK:-debug}

  local PLAYBOOK="$BASEDIR/ansible/playbook/$1.yml"
  local INVENTORY="$BASEDIR/ansible/inventory/$2"

  echo "Running $PLAYBOOK"
  echo "Using $INVENTORY"

  AWS_KEY_ID=${AWS_KEY_ID:="$(aws configure get aws_access_key_id --profile ${AWS_PROFILE})"}
  AWS_SECRET_KEY=${AWS_SECRET_KEY:="$(aws configure get aws_secret_access_key --profile ${AWS_PROFILE})"}

  EXTRA_PARAMS="--extra-vars 'aws_cli_user=${AWS_CLI_USER} aws_region=${AWS_REGION} aws_profile=${AWS_PROFILE} aws_key_id=${AWS_KEY_ID} aws_secret_key=${AWS_SECRET_KEY} aws_registry_id=${AWS_REGISTRY_ID}'"

  [ "$DEBUG" == "true" ] && set -x
  eval ansible-playbook -i "$INVENTORY" "$PLAYBOOK" -e 'host_key_checking=False' "${EXTRA_PARAMS}" -v
  [ "$DEBUG" == "true" ] && set +x
}

# oneliner with \n as separator
get_workers_ips(){
  aws ec2 describe-instances --filters "Name=tag:Name,Values=$NODE_PREFIX*worker*" "Name=tag:Type,Values=worker" \
    --query "Reservations[*].Instances[*].PublicIpAddress" \
    --output text | sed -e :a -e N -e '$!ba' -e 's/\n/\\n/g'
}

get_managers_ips(){
  aws ec2 describe-instances --filters "Name=tag:Name,Values=$NODE_PREFIX*manager*" "Name=tag:Type,Values=manager" \
    --query "Reservations[*].Instances[*].PublicIpAddress" \
    --output text
}

create_aws_ansible_inventory_file(){
  debug

  [ "$DEBUG" == "true" ] && set -x

  MANAGER_IP=$(get_managers_ips)
  WORKERS_IPS_STR=$(get_workers_ips)

  info "WORKERS IPS :: "
  echo "$WORKERS_IPS_STR"

  if is_osx; then
    warning "GNU sed must be available as gsed"

    gsed -e "s_##MANAGERIP##_${MANAGER_IP}_" \
      -e "s_##EC2USER##_${AWS_EC2_AMI_DEFAULT_USER}_" \
      -e "s_##KEYPATH##_${AWS_KEY_PAIR_PATH}_" \
      -e 's_##WORKERSIPS##_'"${WORKERS_IPS_STR}"'_' \
      "${BASEDIR}"/ansible/inventory/AWS.tmpl > "${BASEDIR}"/ansible/inventory/AWS
  else
    sed -e "s_##MANAGERIP##_${MANAGER_IP}_" \
      -e "s_##EC2USER##_${AWS_EC2_AMI_DEFAULT_USER}_" \
      -e "s_##KEYPATH##_${AWS_KEY_PAIR_PATH}_" \
      -e 's_##WORKERSIPS##_'"${WORKERS_IPS_STR}"'_' \
      "${BASEDIR}"/ansible/inventory/AWS.tmpl > "${BASEDIR}"/ansible/inventory/AWS
  fi
  [ "$DEBUG" == "true" ] && set +x
}
