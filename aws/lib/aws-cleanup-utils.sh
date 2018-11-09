#!/bin/bash
#
# Requires colors.sh script
#

err_cleanup(){
  read line file <<<$(caller)
  error "An error occurred in line $line of file $file:"
  error "Offending function :: $(sed "${line}q;d" "$file")"
  error "Offending line: $1"
  
  set -eE

  export FILTER="Name=tag:$AWS_FILTER_TAG_KEY,Values=$AWS_FILTER_TAG_VALUE"

  warning "Removing from PHASE: $CURRENT_PHASE backwards"
  [ "$DEBUG" == "true" ] && set -x

  if [ -z "$AWS_PROVISIONING_COMPLETE" ] || [ "$AWS_PROVISIONING_COMPLETE" == "false" ]; then
    if (( CURRENT_PHASE >= 5 )); then
      cleanup_elb

      wait_for 5
    fi

    if (( CURRENT_PHASE >= 4 )); then
      cleanup_workers

      wait_for 5
    fi

    if (( CURRENT_PHASE >= 2 )); then 
      cleanup_managers

      wait_for 5
    fi

    if (( CURRENT_PHASE >= 1 )); then    
      cleanup_flow_logs

      wait_for 5
    fi

    if (( CURRENT_PHASE >= 0 )); then

      cleanup_vpc

      wait_for 5
    fi
  fi

  separator
  error "FINISHED CLEANUP"
  ELAPSED="Elapsed: $((SECONDS / 3600))hrs $(((SECONDS / 60) % 60))min $((SECONDS % 60))sec"
  fatal "$ELAPSED"
}

cleanup_flow_logs(){
  warning "Cleaning up flow logs"
  
  get_curr_flow_log_id | xargs -r -i aws ec2 delete-flow-logs --flow-log-id {}

  aws logs describe-log-groups --query "logGroups[*].logGroupName" | jq -r ".[] | select(. | contains(\"$TAG_PREFIX\"))" | xargs -i -r aws logs delete-log-group --log-group-name "${AWS_LOG_GROUP_NAME}"
}

cleanup_elb(){
  warning "Cleaning up loadbalancers"
  aws elb delete-load-balancer --load-balancer-name "${AWS_ELB_NAME}"

  wait_for 5

  aws elb delete-load-balancer --load-balancer-name "${AWS_SSH_ELB_NAME}"
}

cleanup_desassociate_elasticip(){
  warning "Desassociate elastic ip adress :: ${AWS_ELASTIC_IP_ASSOCIATION_ID}"
  aws ec2 describe-addresses --filters "$FILTER" \
    --query "Addresses[*].AssociationId" \
    --output text | xargs -i aws ec2 disassociate-address --association-id {}
}

cleanup_elasticip(){
  warning "Releasing elastic ip address :: ${AWS_ELASTIC_IP_ALLOCATION_ID}"
  aws ec2 describe-addresses --filters "$FILTER" \
    --query "Addresses[*].AllocationId" \
    --output text | xargs -i -r aws ec2 release-address --allocation-id {}
}

cleanup_workers(){
  warning "Removing workers instances"

  aws ec2 describe-instances --filters "Name=tag:$AWS_FILTER_TAG_KEY,Values=$AWS_FILTER_TAG_VALUE" "Name=tag:Type,Values=worker" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text | xargs -r -i aws ec2 terminate-instances --instance-ids {}
  
  wait_for 25

}

cleanup_managers(){
  warning "Removing managers instances"
  
  aws ec2 describe-instances --filters "Name=tag:$AWS_FILTER_TAG_KEY,Values=$AWS_FILTER_TAG_VALUE" "Name=tag:Type,Values=manager" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text | xargs -r -i aws ec2 terminate-instances --instance-ids {}

  wait_for 25

}

get_vpc_id(){
  aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query "Vpcs[*].VpcId" --output text
}

cleanup_vpc(){
  warning "Deleting VPC :: ${AWS_VPC_ID}"
  [ "$DEBUG" == "true" ] && set -x

  export FILTER="Name=tag:$AWS_FILTER_TAG_KEY,Values=$AWS_FILTER_TAG_VALUE"

  VPC_ID=$(get_vpc_id)

  warning "Removing security group"
  aws ec2 describe-security-groups --filters "$FILTER" \
    --query 'SecurityGroups[*].GroupId' \
    --output text | xargs -i -r aws ec2 delete-security-group --group-id {}
  
  wait_for 5
  
  warning "Removing subnet"
  aws ec2 describe-subnets --filters "$FILTER" \
    --query 'Subnets[*].SubnetId' \
    --output text | xargs -i -r aws ec2 delete-subnet --subnet-id {}

  wait_for 5

  warning "Removing route table"
  aws ec2 describe-route-tables --filters "$FILTER" \
    --query "RouteTables[*].RouteTableId" \
    --output text | xargs -i -r aws ec2 delete-route-table --route-table-id {}

  wait_for 5

  warning "Detach internet gateway"
  aws ec2 describe-internet-gateways --filters "$FILTER" \
    --query "InternetGateways[*].InternetGatewayId" \
    --output text | xargs -i -r aws ec2 detach-internet-gateway --internet-gateway-id {} --vpc-id "${VPC_ID}"

  wait_for 5

  warning "Removing internet gateway"
  aws ec2 describe-internet-gateways --filters "$FILTER" \
    --query "InternetGateways[*].InternetGatewayId" \
    --output text | xargs -i -r aws ec2 delete-internet-gateway --internet-gateway-id {}

  wait_for 5

  warning "Removing vpc"
  [ ! -z "${VPC_ID}" ] && aws ec2 delete-vpc --vpc-id "${VPC_ID}"

  [ "$DEBUG" == "true" ] && set +x
}

exit_cleanup(){
  debug
  warning "Cleaning Docker Machine"
  rm -rf $HOME/.docker/machine/machines/$NODE_PREFIX*
  separator
  info "FINISHED EXIT CLEANUP"
  ELAPSED="Elapsed: $((SECONDS / 3600))hrs $(((SECONDS / 60) % 60))min $((SECONDS % 60))sec"
  info "TOTAL $ELAPSED"
}

