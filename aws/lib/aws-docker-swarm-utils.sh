#!/bin/bash
#
# Requires colors.sh script
#
create_swarm_workers(){
  debug

  rm -rf $HOME/.docker/machine/machines/$NODE_PREFIX*worker*

  IFS=$'\n'
  for CURRENT_WORKER in "${DOCKER_SWARM_WORKERS_ARRAY[@]}"
  do
    create_ec2_instance "${CURRENT_WORKER}" "Name,${CURRENT_WORKER},Type,worker"

    wait_for 15

    get_inet_interface_ip "${DOCKER_SWARM_MANAGER_NAME}"
    info "Worker created IP address: ${NODE_IP_ADDRESS}"
  done
}

create_swarm_manager(){
  debug

  rm -rf $HOME/.docker/machine/machines/$NODE_PREFIX*manager*

  create_ec2_instance "${DOCKER_SWARM_MANAGER_NAME}" "Name,${DOCKER_SWARM_MANAGER_NAME},Type,manager"
}

export_docker_machine_configs(){
  debug

  "${BASEDIR}"/docker/docker-machine-export.sh "${DOCKER_SWARM_MANAGER_NAME}"

  IFS=$'\n'
  for WORKER in "${DOCKER_SWARM_WORKERS_ARRAY[@]}"
  do
    "${BASEDIR}"/docker/docker-machine-export.sh "${WORKER}"
  done
}

get_inet_interface_ip(){
  debug

  local NODE_NAME=$1

  info "ifconfig interface info"
  info

  multi_info "$(docker-machine ssh "${NODE_NAME}" ifconfig eth0)"

  NODE_IP_ADDRESS=$(docker-machine ip "${NODE_NAME}")
}

enable_instance_termination_protection(){
  debug
  declare INSTANCES=$1
  aws ec2 modify-instance-attribute --instance-id "$INSTANCES" --disable-api-termination
}

iterate_and_enable_termination_protection(){
  debug
  IFS=' '
  for CURRENT_EC2_ID in ${AWS_EC2_INSTANCES_IDS} 
  do
    info "Enabling termination protection for $CURRENT_EC2_ID"
    enable_instance_termination_protection "${CURRENT_EC2_ID}"
  done
}

create_ec2_instance(){
  debug

  local INSTANCE_NAME=$1
  local AWS_DKR_MACHINE_TAGS=$2

  info "Executing EC2 docker-machine creation command for :: ${INSTANCE_NAME}"

  # engine-opt -> enable docker engine metrics for prometheus
  [ "$DEBUG" == "true" ] && set -x
  docker-machine create --driver "${DOCKER_MACHINE_DRIVER}" \
    --engine-opt "experimental" \
    --engine-opt "metrics-addr=0.0.0.0:4999" \
    --amazonec2-tags "${AWS_DKR_MACHINE_TAGS}" \
    --amazonec2-vpc-id "${AWS_VPC_ID}" \
    --amazonec2-subnet-id "${AWS_SUBNET_ID}" \
    --amazonec2-region "${AWS_REGION}" \
    --amazonec2-zone "${AWS_AV_ZONE}" \
    --amazonec2-keypair-name "${AWS_KEY_PAIR_NAME}" \
    --amazonec2-ssh-keypath "${AWS_KEY_PAIR_PATH}" \
    --amazonec2-instance-type "${AWS_INSTANCE_TYPE}"  \
    --amazonec2-root-size "${AWS_INSTANCE_SIZE}" \
    --amazonec2-security-group "${AWS_SECGROUP_NAME}" "${INSTANCE_NAME}"

    wait_for 20

    CURRENT_EC2_ID=$(get_ec2_instance_id_sub "${INSTANCE_NAME}")
    [ -z "$CURRENT_EC2_ID" ] && fatal 'Unable to retrieve created instance id'
    
    info "Created EC2 ID :: $CURRENT_EC2_ID"
    
    create_tag "$CURRENT_EC2_ID" "$AWS_TAGS"
  [ "$DEBUG" == "true" ] && set +x
}

get_ec2_instance_id_sub(){
  declare INSTANCE_NAME=$1
  aws ec2 describe-instances --filter "Name=tag:Name,Values=${INSTANCE_NAME}" | jq -r '.[][].Instances[] | select(.State.Name == "running") | .InstanceId' #sed -e :a -e N -e '$!ba' -e 's/\n/ /g'
}

is_osx(){
  debug
  [[ "$(uname)" == *"arwin" ]]
}
