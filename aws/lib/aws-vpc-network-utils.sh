#!/bin/bash
#
# Requires colors.sh script
# Requires properties-utils.sh script
#
create_vpc(){
  debug

  [ "$DEBUG" == "true" ] && set -x

  info "Creating VPC"
  AWS_VPC_ID_DOC=$(create_vpc_subsh)

  AWS_VPC_ID=$(echo "$AWS_VPC_ID_DOC" | jq -r '.Vpc.VpcId')

  info "Creating tags for vpc"
  create_tag "${AWS_VPC_ID}" "${AWS_TAGS} Key=Name,Value=$VPC_NAME"

  [ "$DEBUG" == "true" ] && set +x

  [ -z "$AWS_VPC_ID" ] && fatal 'Error creating vpc'

  info "VPC created id: ${AWS_VPC_ID}"
  set_property "AWS_VPC_ID" "$AWS_VPC_ID"

}

create_vpc_subsh(){
  aws ec2 create-vpc --cidr-block "${AWS_VPC_IPV4_CIDR}"
}

create_subnet_in_vpc(){
  debug

  [ "$DEBUG" == "true" ] && set -x

  info "Creating subnet ipv4 CIDR ${AWS_VPC_IPV4_CIDR}"

  SUBNET_DOC=$(create_subnet_subsh)
  AWS_SUBNET_ID=$(echo "$SUBNET_DOC" | jq -r '.Subnet.SubnetId')

  create_tag "$AWS_SUBNET_ID" "$AWS_TAGS Key=Name,Value=$TAG_PREFIX"

  [ "$DEBUG" == "true" ] && set +x

  info "Subnet created id: ${AWS_SUBNET_ID}"
  set_property "AWS_SUBNET_ID" "$AWS_SUBNET_ID"
}

create_subnet_subsh(){
  aws ec2 create-subnet --availability-zone "${AWS_REGION}${AWS_AV_ZONE}" \
    --vpc-id "${AWS_VPC_ID}" \
    --cidr-block "${AWS_VPC_IPV4_CIDR}"
}

create_internet_gateway_vpc(){
  debug

  create_internet_gateway_and_attach_to_vpc "$AWS_VPC_ID"

  create_route_table "$AWS_VPC_ID"

  create_route_in_route_table

  info "Listing subnets"
  AWS_SUBNET_ID=$(get_subnet_subsh)
  
  info "Subnet ID: ${AWS_SUBNET_ID}"
  set_property "AWS_SUBNET_ID" "$AWS_SUBNET_ID"

  info "Associate route table to subnet"
  AWS_ROUTE_TABLE_ASSOCIATION_ID=$(associate_route_subsh)

  [ -z "$AWS_ROUTE_TABLE_ASSOCIATION_ID" ] && fatal "Association failed"
  
  info "Route table association ID: ${AWS_ROUTE_TABLE_ASSOCIATION_ID}"
  set_property "AWS_ROUTE_TABLE_ASSOCIATION_ID" "$AWS_ROUTE_TABLE_ASSOCIATION_ID"
}

get_subnet_subsh(){
  aws ec2 describe-subnets --filters "Name=vpc-id,Values=${AWS_VPC_ID}" --query 'Subnets[*].{ID:SubnetId,CIDR:CidrBlock}' | jq -r '.[0].ID'
}

associate_route_subsh(){
  aws ec2 associate-route-table  --subnet-id "${AWS_SUBNET_ID}" --route-table-id "${AWS_ROUTES_TABLE_ID}" | jq -r '.AssociationId'
}

create_internet_gateway_subsh(){
  aws ec2 create-internet-gateway
}

create_internet_gateway_and_attach_to_vpc(){
  info "Creating internet gateway"

  declare VPC_ID=$1

  [ "$DEBUG" == "true" ] && set -x

  AWS_INTERNET_GATEWAY_DOC=$(create_internet_gateway_subsh)
  AWS_INTERNET_GATEWAY_ID=$(echo "$AWS_INTERNET_GATEWAY_DOC" | jq -r '.InternetGateway.InternetGatewayId' )

  [ -z "$AWS_INTERNET_GATEWAY_ID" ] && fatal 'Error creating internet gateway'

  info "Internet Gateway ID: $AWS_INTERNET_GATEWAY_ID"
  set_property "AWS_INTERNET_GATEWAY_ID" "$AWS_INTERNET_GATEWAY_ID"

  create_tag "$AWS_INTERNET_GATEWAY_ID" "$AWS_TAGS Key=Name,Value=$TAG_PREFIX"

  info "Attach internet gateway to VPC"
  aws ec2 attach-internet-gateway \
    --vpc-id "${VPC_ID}" \
    --internet-gateway-id "${AWS_INTERNET_GATEWAY_ID}"

  [ "$DEBUG" == "true" ] && set +x
}

create_route_table(){
  info "Creating routes table"

  declare VPC_ID=$1

  [ "$DEBUG" == "true" ] && set -x

  ROUTES_TABLE_DOC=$(aws ec2 create-route-table --vpc-id "${VPC_ID}")
  AWS_ROUTES_TABLE_ID=$(echo "$ROUTES_TABLE_DOC" | jq -r '.RouteTable.RouteTableId')

  info "Created routes table id: $AWS_ROUTES_TABLE_ID"
  set_property "AWS_ROUTES_TABLE_ID" "$AWS_ROUTES_TABLE_ID"

  [ -z "$AWS_ROUTES_TABLE_ID" ] && fatal 'Error creating routes table'

  create_tag "$AWS_ROUTES_TABLE_ID" "$AWS_TAGS Key=Name,Value=$TAG_PREFIX"

  [ "$DEBUG" == "true" ] && set +x
}

create_route_in_route_table(){
  info "Creating route to redirect all traffic (0.0.0.0/0) to internet gateway"
  aws ec2 create-route --route-table-id "${AWS_ROUTES_TABLE_ID}" \
    --destination-cidr-block "0.0.0.0/0" \
    --gateway-id "${AWS_INTERNET_GATEWAY_ID}"

  create_tag "$AWS_ROUTES_TABLE_ID" "$AWS_TAGS"

  info "Listing routes tables"
  aws ec2 describe-route-tables --route-table-id "${AWS_ROUTES_TABLE_ID}"
}

allocate_elastic_ip(){
  debug

  ELASTIC_IP_DOC=$(aws ec2 allocate-address --output json)
  ELASTIC_IP=$(echo "$ELASTIC_IP_DOC" | jq -r '.PublicIp')
  AWS_ELASTIC_IP_ALLOCATION_ID=$(echo "$ELASTIC_IP_DOC" | jq -r '.AllocationId')

  [ -z "${AWS_ELASTIC_IP_ALLOCATION_ID}" ] && fatal "ERROR creating elastic ip"

  create_tag "$AWS_ELASTIC_IP_ALLOCATION_ID" "$AWS_TAGS"

  info "Elastic ip created ID: ${AWS_ELASTIC_IP_ALLOCATION_ID}"
  set_property "AWS_ELASTIC_IP_ALLOCATION_ID" "${AWS_ELASTIC_IP_ALLOCATION_ID}"
}

associate_elastic_ip_to_manager(){
  debug

  set -x

  EC2_INSTANCE_ID=$(get_ec2_instanceid_subsh 'manager')

  get_inet_interface_ip "${DOCKER_SWARM_MANAGER_NAME}"
  info "Manager created IP address ${NODE_IP_ADDRESS}"

  info "Associate previously created elastic ip to manager node"
  associate_elastic_ip
}

associate_elastic_ip(){
  debug

  info "Associate elastic ip"
  
  AWS_ELASTIC_IP_ASSOCIATION_ID=$(associate_address_subsh)

  [ -z "$AWS_ELASTIC_IP_ASSOCIATION_ID" ] && fatal "ERROR in elastic ip association"

  info "Elastic ip address association ID: ${AWS_ELASTIC_IP_ASSOCIATION_ID}"
  set_property "AWS_ELASTIC_IP_ASSOCIATION_ID" "$AWS_ELASTIC_IP_ASSOCIATION_ID"
}

get_ec2_instanceid_subsh(){
  declare TYPE=$1
  aws ec2 describe-instances --filters "Name=tag:$AWS_FILTER_TAG_KEY,Values=$AWS_FILTER_TAG_VALUE,Name=tag:Type,Values=$TYPE" --output text | jq -r '.[][].Instances[] | select(.State.Name == "running") | .InstanceId'
}

associate_address_subsh(){
  aws ec2 associate-address --instance-id "${EC2_INSTANCE_ID}" --allocation-id "${AWS_ELASTIC_IP_ALLOCATION_ID}" | jq -r '.AssociationId'
}