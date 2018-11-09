#!/bin/bash
#
# Requires colors.sh script
# Requires properties-utils.sh
# Requires aws-acm-utils.sh
#
create_elb(){
    debug
    info "Create HTTP and HTTPS load balancer"

    declare NAME=$1

    [ "$DEBUG" == "true" ] && set -x

    info "Getting ACM SSL Certificate ARN"
    AWS_ACM_SSL_CERT_ARN=$(get_acm_certificate_arn)

    eval aws elb create-load-balancer \
        --load-balancer-name "${NAME}" \
        --listeners "Protocol=HTTPS,LoadBalancerPort=443,InstanceProtocol=HTTPS,InstancePort=443,SSLCertificateId=${AWS_ACM_SSL_CERT_ARN}" \
        --tags "${AWS_TAGS}" \
        --subnets "${AWS_SUBNET_ID}" \
        --security-groups "${AWS_SECURITY_GROUP_ID}"

    [ "$DEBUG" == "true" ] && set +x

    info "Created ELB : $AWS_SSH_ELB_NAME"
    set_property "AWS_SSH_ELB_NAME" "$AWS_SSH_ELB_NAME"
}

create_ssh_elb(){
    debug
    info "Create SSH load balancer"

    declare NAME=$1

    [ "$DEBUG" == "true" ] && set -x

    eval aws elb create-load-balancer \
        --load-balancer-name "${NAME}" \
        --listeners "Protocol=TCP,LoadBalancerPort=22,InstanceProtocol=TCP,InstancePort=22" \
        --subnets "${AWS_SUBNET_ID}" \
        --tags "${AWS_TAGS}" \
        --security-groups "${AWS_SECURITY_GROUP_ID}"

    [ "$DEBUG" == "true" ] && set +x

    info "Created SSH ELB : $AWS_SSH_ELB_NAME"
    set_property "AWS_SSH_ELB_NAME" "$AWS_SSH_ELB_NAME"
}

get_elb_dns_name(){
    debug
    
    declare ELB_NAME=$1
    info "Getting ELB dns for $ELB_NAME"

    AWS_ELB_DNS=$(aws elb describe-load-balancers | jq -r ".LoadBalancerDescriptions[] | select(.LoadBalancerName == \"${ELB_NAME}\") | .DNSName")

    [ -z "$AWS_ELB_DNS" ] && fatal 'ELB DNS not found'  
    set_property "AWS_ELB_DNS" "$AWS_ELB_DNS"
}

get_ec2_instance_ids(){
    debug

    [ "$DEBUG" == "true" ] && set -x


    info "Get all ec2 instances ids"
    AWS_EC2_INSTANCES_IDS=$(get_all_swarm_instances_ids_subsh)

    [ -z "${AWS_EC2_INSTANCES_IDS}" ] && fatal "Unable to find EC2 instances ids"

    [ "$DEBUG" == "true" ] && set +x
}

get_all_swarm_instances_ids_subsh(){
    aws ec2 describe-instances --filters "Name=tag:Name,Values=$NODE_PREFIX*" "Name=instance-state-name,Values=running" \
        --query 'Reservations[*].Instances[*].InstanceId' --output text | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/ /g'
}

register_instance(){
    debug

    [ "$DEBUG" == "true" ] && set -x
    
    info "Registering the following instances ::"

    IFS=' '
    for EC2_ID in $AWS_EC2_INSTANCES_IDS
    do
        info "EC2 INSTANCE ID: $EC2_ID"
        create_tag "$EC2_ID" "$AWS_TAGS"
    done

    aws elb register-instances-with-load-balancer \
        --load-balancer-name "${AWS_ELB_NAME}" \
        --instances "${AWS_EC2_INSTANCES_IDS}"


    [ $? != 0 ] && fatal "Unable to register EC2 instances Ids"

    [ "$DEBUG" == "true" ] && set -x
}

