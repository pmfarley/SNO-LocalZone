#!/bin/bash
#######################################################################
## Edit these variables as needed

export REGION="us-east-1"
export LOCAL_ZONE="us-east-1-chi-1a"
export SNO_IMAGE_ID="ami-0ae9702360611e715"       #RHEL 8.4
export SNO_INSTANCE_TYPE=r5d.2xlarge 
export KEY_NAME=pmf-key

#######################################################################
echo ##################################################################
#### Create the VPC.
echo Create the VPC

export VPC_ID=$(aws ec2 --region $REGION \
--output text create-vpc --cidr-block 10.0.0.0/16 \
--query 'Vpc.VpcId') && echo '\nVPC_ID='$VPC_ID

#######################################################################
echo ##################################################################
#### Create an internet gateway and attach it to the VPC.
echo Create an internet gateway 

export IGW_ID=$(aws ec2 --region $REGION \
--output text create-internet-gateway \
--query 'InternetGateway.InternetGatewayId') && echo '\nIGW_ID='$IGW_ID

echo Attach the internet gateway to the VPC
aws ec2 --region $REGION  attach-internet-gateway \
 --vpc-id $VPC_ID  --internet-gateway-id $IGW_ID

#######################################################################
echo ##################################################################
#### Create the SNO security group along with ingress rules.
echo Create the SNO security group

export SNO_SG_ID=$(aws ec2 --region $REGION \
--output text create-security-group --group-name sno-sg \
--description "Security group for SNO host" --vpc-id $VPC_ID \
--query 'GroupId') && echo '\nSNO_SG_ID='$SNO_SG_ID

echo Create the SNO security group ingress rules
aws ec2 --region $REGION authorize-security-group-ingress \
--group-id $SNO_SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0

aws ec2 --region $REGION authorize-security-group-ingress \
--group-id $SNO_SG_ID --protocol tcp --port 6443 --cidr 0.0.0.0/0

aws ec2 --region $REGION authorize-security-group-ingress \
--group-id $SNO_SG_ID --protocol tcp --port 22623 --cidr 0.0.0.0/0

aws ec2 --region $REGION authorize-security-group-ingress \
--group-id $SNO_SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0

aws ec2 --region $REGION authorize-security-group-ingress \
--group-id $SNO_SG_ID --protocol tcp --port 443 --cidr 0.0.0.0/0

aws ec2 --region $REGION authorize-security-group-ingress \
--group-id $SNO_SG_ID --protocol icmp --port 0 --cidr 0.0.0.0/0

#######################################################################
echo ##################################################################
#### Create the Local Zone subnet.
echo Create the Local Zone subnet

export LZ_SUBNET_ID=$(aws ec2 --region $REGION \
--output text create-subnet --cidr-block 10.0.0.0/24 \
--availability-zone $LOCAL_ZONE --vpc-id $VPC_ID \
--query 'Subnet.SubnetId') && echo '\nLZ_SUBNET_ID='$LZ_SUBNET_ID

#######################################################################
echo ##################################################################
#### Create the Local Zone subnet route table
echo Create the Local Zone subnet route table 

export LZ_RT_ID=$(aws ec2 --region $REGION \
--output text create-route-table --vpc-id $VPC_ID \
--query 'RouteTable.RouteTableId') && echo '\nLZ_RT_ID='$LZ_RT_ID 

#######################################################################
echo ##################################################################
#### Associate the Local Zone subnet route table 
#### and a route to direct traffic to the internet gateway.
echo Associate the Local Zone subnet route table 

aws ec2 --region $REGION  associate-route-table \
--subnet-id $LZ_SUBNET_ID --route-table-id $LZ_RT_ID \
--output text --query 'AssociationId'

echo Create route to direct traffic to the internet gateway 
aws ec2 --region $REGION  create-route --route-table-id $LZ_RT_ID \
--destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID 

#######################################################################
echo ##################################################################
#### Modify the Local Zone subnet to assign public IPs by default.
echo Modify the Local Zone subnet to assign public IPs by default

aws ec2 --region $REGION  modify-subnet-attribute \
--subnet-id $LZ_SUBNET_ID  --map-public-ip-on-launch

#######################################################################
echo ##################################################################
#### Deploy the SNO instance 
echo Deploy the SNO instance 

export SNO_INSTANCE_ID=$(aws ec2 --region $REGION run-instances  --instance-type $SNO_INSTANCE_TYPE \
--associate-public-ip-address --subnet-id $LZ_SUBNET_ID --output text --query Instances[*].[InstanceId] \
--image-id $SNO_IMAGE_ID --security-group-ids $SNO_SG_ID --key-name $KEY_NAME \
--block-device-mappings '[{"DeviceName": "/dev/sda1", "Ebs":{"VolumeSize": 120, "VolumeType": "gp2"}}]' \
--tag-specifications 'ResourceType=instance,Tags=[{Key="kubernetes.io/cluster/ocp-lz-sno",Value=shared}]') \
&& echo '\nSNO_INSTANCE_ID='$SNO_INSTANCE_ID

